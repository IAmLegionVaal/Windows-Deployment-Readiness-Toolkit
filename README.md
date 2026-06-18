# Windows Deployment Readiness Toolkit

A read-only PowerShell toolkit for Windows endpoint deployment readiness checks.

## Features

- OS edition and build context
- TPM and Secure Boot context
- Disk and memory readiness
- BitLocker context where available
- Domain and Entra join status evidence
- CSV, JSON, TXT, and HTML reports

## How to run

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows_Deployment_Readiness_Toolkit.ps1
```

## Safety

Diagnostic-only. It does not change deployment, encryption, or join settings.
