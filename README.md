# Windows Deployment Readiness Toolkit

A PowerShell toolkit for Windows deployment readiness checks and selected guarded repairs.

## Diagnostic script

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows_Deployment_Readiness_Toolkit.ps1
```

## Repair script

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows_Deployment_Repair_Toolkit.ps1 -EnableWinRE -DryRun
```

Examples:

```powershell
.\Windows_Deployment_Repair_Toolkit.ps1 -EnableWinRE
.\Windows_Deployment_Repair_Toolkit.ps1 -RepairSystemFiles
.\Windows_Deployment_Repair_Toolkit.ps1 -ResumeBitLocker -DriveLetter C
.\Windows_Deployment_Repair_Toolkit.ps1 -StartDeploymentServices
.\Windows_Deployment_Repair_Toolkit.ps1 -ClearTemp
```

## What the repair does

- Enables Windows Recovery Environment.
- Runs DISM RestoreHealth and System File Checker.
- Resumes protection on an already encrypted BitLocker volume.
- Starts selected deployment and update services.
- Removes stale current-user temporary files older than seven days.
- Captures OS, TPM, Secure Boot, WinRE, BitLocker, storage and service state before and after repair.
- Supports `-DryRun`, confirmation prompts, logs and clear exit codes.

## Safety

The tool does not join or unjoin a domain or Entra ID, start BitLocker encryption, clear TPM ownership, change Secure Boot firmware settings or deploy an operating system automatically.

## Author

Dewald Pretorius — L2 IT Support Engineer
