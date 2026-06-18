#requires -Version 5.1
<#
.SYNOPSIS
    Windows Deployment Readiness Toolkit.
.DESCRIPTION
    Read-only Windows endpoint deployment readiness checker.
#>
[CmdletBinding()]
param([string]$OutputPath)
$RunStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Deployment_Readiness_Reports'}
New-Item -Path $OutputPath -ItemType Directory -Force|Out-Null
function New-Check{param($Area,$Name,$Status,$Value,$Recommendation)[PSCustomObject]@{Area=$Area;Name=$Name;Status=$Status;Value=$Value;Recommendation=$Recommendation}}
$checks=@();$os=Get-CimInstance Win32_OperatingSystem;$cs=Get-CimInstance Win32_ComputerSystem
$checks+=New-Check 'System' 'OS build' 'Info' "$($os.Caption) Build $($os.BuildNumber)" 'Record deployment baseline.'
$checks+=New-Check 'Hardware' 'Memory' ($(if($cs.TotalPhysicalMemory -lt 8GB){'Warning'}else{'OK'})) ("{0:N2} GB" -f ($cs.TotalPhysicalMemory/1GB)) 'Review deployment requirement.'
$drive=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'";$free=[math]::Round($drive.FreeSpace/1GB,2);$checks+=New-Check 'Disk' 'System drive free' ($(if($free -lt 20){'Warning'}else{'OK'})) "$free GB" 'Review free space requirement.'
try{$tpm=Get-Tpm;$checks+=New-Check 'TPM' 'TPM present and ready' ($(if($tpm.TpmPresent -and $tpm.TpmReady){'OK'}else{'Warning'})) "Present=$($tpm.TpmPresent); Ready=$($tpm.TpmReady)" 'TPM is commonly required for modern deployment.'}catch{$checks+=New-Check 'TPM' 'TPM query' 'Info' $_.Exception.Message 'Could not query TPM.'}
try{$sb=Confirm-SecureBootUEFI;$checks+=New-Check 'Secure Boot' 'Secure Boot' ($(if($sb){'OK'}else{'Warning'})) $sb 'Review deployment requirement.'}catch{$checks+=New-Check 'Secure Boot' 'Secure Boot query' 'Info' $_.Exception.Message 'Legacy BIOS may not support query.'}
try{dsregcmd.exe /status|Out-File (Join-Path $OutputPath "dsregcmd_status_$RunStamp.txt") -Encoding UTF8;$checks+=New-Check 'Join State' 'dsregcmd output' 'Info' 'Exported' 'Review join and registration state output.'}catch{}
try{Get-BitLockerVolume|Select-Object MountPoint,ProtectionStatus,VolumeStatus|Export-Csv (Join-Path $OutputPath "bitlocker_$RunStamp.csv") -NoTypeInformation -Encoding UTF8}catch{}
$checks|Export-Csv (Join-Path $OutputPath "deployment_readiness_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$checks|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutputPath "deployment_readiness_$RunStamp.json") -Encoding UTF8
$checks|ConvertTo-Html -Title 'Deployment Readiness' -PreContent "<h1>Deployment Readiness - $env:COMPUTERNAME</h1><p>Generated $(Get-Date)</p>"|Set-Content (Join-Path $OutputPath "deployment_readiness_$RunStamp.html") -Encoding UTF8
$checks|Format-Table -AutoSize -Wrap
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
Start-Process explorer.exe -ArgumentList "`"$OutputPath`"" -ErrorAction SilentlyContinue
