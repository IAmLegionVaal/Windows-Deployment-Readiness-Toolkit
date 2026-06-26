#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$EnableRequiredServices,
    [switch]$RepairComponentStore,
    [switch]$ClearSetupCache,
    [switch]$SyncTime,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = "$env:USERPROFILE\Desktop\DeploymentReadinessRepair"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$warnings = [System.Collections.Generic.List[string]]::new()
$logPath = $null

function Write-RepairLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN')][string]$Level = 'INFO'
    )

    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    Write-Host $entry
    if ($logPath) {
        Add-Content -LiteralPath $logPath -Value $entry -Encoding UTF8
    }
}

function Add-RepairWarning {
    param([Parameter(Mandatory)][string]$Message)

    $warnings.Add($Message)
    Write-RepairLog -Level WARN -Message $Message
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int[]]$SuccessExitCodes = @(0)
    )

    $outputFile = Join-Path $OutputPath (($Name -replace '[^A-Za-z0-9-]', '_') + '.txt')
    & $FilePath @ArgumentList 2>&1 | Tee-Object -FilePath $outputFile
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $SuccessExitCodes) {
        throw "$Name exited with code $exitCode. Review '$outputFile'."
    }
}

try {
    if ($env:OS -ne 'Windows_NT') {
        throw 'This repair requires Windows.'
    }

    if (-not ($EnableRequiredServices -or $RepairComponentStore -or $ClearSetupCache -or $SyncTime)) {
        throw 'Choose at least one repair action.'
    }

    if (-not (Test-IsAdministrator)) {
        throw 'Run PowerShell as Administrator.'
    }

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $logPath = Join-Path $OutputPath ('repair-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))

    Get-ComputerInfo |
        Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, CsName, CsTotalPhysicalMemory |
        ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $OutputPath 'before.json') -Encoding UTF8

    if ($EnableRequiredServices) {
        foreach ($serviceName in 'wuauserv', 'bits', 'cryptsvc', 'trustedinstaller') {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if (-not $service) {
                Add-RepairWarning "Service '$serviceName' is unavailable."
                continue
            }

            if ($PSCmdlet.ShouldProcess($serviceName, 'Set manual startup and start service')) {
                try {
                    Set-Service -Name $serviceName -StartupType Manual -ErrorAction Stop
                    if ($service.Status -ne 'Running') {
                        Start-Service -Name $serviceName -ErrorAction Stop
                    }
                    Write-RepairLog "Prepared service '$serviceName'."
                }
                catch {
                    Add-RepairWarning "Could not prepare '$serviceName': $($_.Exception.Message)"
                }
            }
        }
    }

    if ($RepairComponentStore -and $PSCmdlet.ShouldProcess('Windows component store', 'Run DISM RestoreHealth and SFC')) {
        Invoke-NativeCommand -Name 'DISM RestoreHealth' -FilePath 'dism.exe' `
            -ArgumentList @('/Online', '/Cleanup-Image', '/RestoreHealth') `
            -SuccessExitCodes @(0, 3010)
        Invoke-NativeCommand -Name 'SFC ScanNow' -FilePath 'sfc.exe' `
            -ArgumentList @('/scannow') -SuccessExitCodes @(0, 1, 2)
        Write-RepairLog 'Component-store and protected-system-file repair completed.'
    }

    if ($ClearSetupCache) {
        foreach ($setupPath in @(
            (Join-Path $env:SystemDrive '$WINDOWS.~BT\Sources\Panther'),
            (Join-Path $env:WINDIR 'Panther')
        )) {
            if (-not (Test-Path -LiteralPath $setupPath)) {
                continue
            }

            $temporaryFiles = @(Get-ChildItem -LiteralPath $setupPath -Filter '*.tmp' -File -ErrorAction SilentlyContinue)
            foreach ($file in $temporaryFiles) {
                if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove stale setup temporary file')) {
                    try {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    }
                    catch {
                        Add-RepairWarning "Could not remove '$($file.FullName)': $($_.Exception.Message)"
                    }
                }
            }
            Write-RepairLog "Processed $($temporaryFiles.Count) temporary setup file(s) in '$setupPath'."
        }
    }

    if ($SyncTime -and $PSCmdlet.ShouldProcess('Windows Time service', 'Start and resynchronise')) {
        Set-Service -Name 'W32Time' -StartupType Manual -ErrorAction Stop
        Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue
        Invoke-NativeCommand -Name 'Windows Time Resync' -FilePath 'w32tm.exe' -ArgumentList @('/resync')
        Write-RepairLog 'Windows time resynchronisation completed.'
    }

    Get-Service -Name 'wuauserv', 'bits', 'cryptsvc', 'trustedinstaller', 'W32Time' -ErrorAction SilentlyContinue |
        Select-Object Name, Status, StartType |
        Export-Csv (Join-Path $OutputPath 'services-after.csv') -NoTypeInformation -Encoding UTF8

    $warnings | Set-Content -LiteralPath (Join-Path $OutputPath 'warnings.txt') -Encoding UTF8
    if ($warnings.Count -gt 0) {
        Write-RepairLog -Level WARN -Message "Completed with $($warnings.Count) warning(s)."
        exit 2
    }

    Write-RepairLog 'Windows deployment readiness repair workflow completed.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
