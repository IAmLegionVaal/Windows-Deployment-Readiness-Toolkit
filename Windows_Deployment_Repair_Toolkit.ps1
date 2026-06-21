[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
 [switch]$EnableWinRE,
 [switch]$RepairSystemFiles,
 [switch]$ResumeBitLocker,
 [ValidatePattern('^[A-Z]$')][string]$DriveLetter='C',
 [switch]$StartDeploymentServices,
 [switch]$ClearTemp,
 [switch]$DryRun,[switch]$Yes,
 [string]$OutputPath=(Join-Path $env:ProgramData 'DeploymentReadinessRepair')
)
$ErrorActionPreference='Stop';$script:Failures=0;$script:Actions=0
$run=Join-Path $OutputPath (Get-Date -Format yyyyMMdd_HHmmss);New-Item -ItemType Directory $run -Force|Out-Null
$log=Join-Path $run 'repair.log';$before=Join-Path $run 'before.json';$after=Join-Path $run 'after.json'
function Log($m){"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"|Tee-Object -FilePath $log -Append}
function Admin{$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent());$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
function State{[pscustomobject]@{Collected=Get-Date;OS=Get-CimInstance Win32_OperatingSystem|Select-Object Caption,BuildNumber,OSArchitecture;TPM=Get-Tpm -ErrorAction SilentlyContinue;SecureBoot=try{Confirm-SecureBootUEFI}catch{$null};WinRE=(& reagentc.exe /info|Out-String);BitLocker=Get-BitLockerVolume -ErrorAction SilentlyContinue|Select-Object MountPoint,VolumeStatus,ProtectionStatus;Disk=Get-Volume -DriveLetter $DriveLetter|Select-Object Size,SizeRemaining,HealthStatus;Services=Get-Service dmwappushservice,DiagTrack,wuauserv,bits -ErrorAction SilentlyContinue|Select-Object Name,Status,StartType}}
function Act($d,[scriptblock]$a){$script:Actions++;Log $d;if($DryRun){Log "DRY-RUN: $d";return};try{&$a;Log "SUCCESS: $d"}catch{$script:Failures++;Log "FAILED: $d - $($_.Exception.Message)"}}
State|ConvertTo-Json -Depth 6|Set-Content $before -Encoding UTF8
if(-not($EnableWinRE -or $RepairSystemFiles -or $ResumeBitLocker -or $StartDeploymentServices -or $ClearTemp)){Write-Error 'Choose at least one repair action.';exit 2}
if(-not $DryRun -and -not(Admin)){Write-Error 'Run from elevated PowerShell.';exit 4}
if(-not $Yes -and -not $DryRun){if((Read-Host 'Apply selected deployment-readiness repairs? Type YES') -ne 'YES'){Log 'Cancelled.';exit 10}}
if($EnableWinRE){Act 'Enabling Windows Recovery Environment' {& reagentc.exe /enable|Out-File (Join-Path $run 'reagentc-enable.txt');if($LASTEXITCODE){throw "reagentc exited $LASTEXITCODE"}}}
if($RepairSystemFiles){Act 'Running DISM RestoreHealth' {$p=Start-Process dism.exe -ArgumentList '/Online','/Cleanup-Image','/RestoreHealth' -Wait -PassThru -NoNewWindow;if($p.ExitCode){throw "DISM exited $($p.ExitCode)"}};Act 'Running System File Checker' {$p=Start-Process sfc.exe -ArgumentList '/scannow' -Wait -PassThru -NoNewWindow;if($p.ExitCode -notin 0,1){throw "SFC exited $($p.ExitCode)"}}}
if($ResumeBitLocker){$mount="${DriveLetter}:";$v=Get-BitLockerVolume -MountPoint $mount -ErrorAction Stop;if($v.ProtectionStatus -eq 'On'){Log "$mount BitLocker protection is already active."}else{Act "Resuming BitLocker on $mount" {Resume-BitLocker -MountPoint $mount}}}
if($StartDeploymentServices){foreach($s in 'dmwappushservice','DiagTrack','wuauserv','bits'){if(Get-Service $s -ErrorAction SilentlyContinue){Act "Starting service $s" {Start-Service $s -ErrorAction Stop}}}}
if($ClearTemp){Act 'Removing stale deployment temp files older than seven days' {Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue|Where-Object LastWriteTime -lt (Get-Date).AddDays(-7)|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue}}
Start-Sleep 2;State|ConvertTo-Json -Depth 6|Set-Content $after -Encoding UTF8
if($script:Failures){Log "Completed with $script:Failures failure(s).";exit 20};Log "Repair completed. Actions: $script:Actions";exit 0
