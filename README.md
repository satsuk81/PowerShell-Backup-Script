# PowerShell Cross Platform Backup Script

## .SYNOPSIS

PowerShell Cross Platform Backup Script

## .DESCRIPTION

This script provides a cross-platform backup solution using PowerShell.

The execution pipeline runs: **PreCheck** → **SourceAnalyse** → **PostCheck** → **Backup / Copy**

- **PreCheck** – validates source directories exist and checks available destination disk space
- **SourceAnalyse** – scans sources, builds file/size totals, and resolves include/exclude directory lists
- **PostCheck** – re-validates free space using the precise size from SourceAnalyse
- **Backup / Copy** – runs the operation via `robocopy` (Windows / Windows PowerShell 5.1) or `rsync` (non-Windows Core)

Based on the PowerShell-Backup-Script by Michael Seidl\
[https://github.com/Seidlm/PowerShell-Backup-Script](https://github.com/Seidlm/PowerShell-Backup-Script)

## .NOTES

Written by      : Daniel Ames\
Build Version   : v1.3.0\
Created         : 2025-08-15\
Modified        : 2026-06-03

## .EXAMPLES

### Example 1

``` powershell
$splat = @{
    BackupName       = 'Immich'
    SourceDirs       = @(
        'D:\immich-app\library\backups',
        'D:\immich-app\library\library',
        'D:\immich-app\library\profile',
        'D:\immich-app\library\upload'
    )
    Destination      = '\\TRUENAS\dataset1\Backup\Immich'
    VersionKeepCount = 3
    LogfileName      = 'Immich-Backup-Runner.log'
}
.\BackupScript.ps1 @splat -Backup
```

### Example 2

``` powershell
$splat = @{
    Source      = "$sourceFolder"
    Target      = "$destinationFolder"
}
.\BackupScript.ps1 @splat -Copy
```

## .SYNTAX

``` powershell
.\BackupScript.ps1 [-Backup ] [-BackupName <String>] [-SourceDirs <String[]>] [-Destination <String>] [-VersionKeepCount <Int32>] [-ExcludeDirs <String[]>] [-logPath <String>] [-LogfileName <String>] [-CodeDebug <Boolean>] [<CommonParameters>]

.\BackupScript.ps1 [-Restore ] [-SourceDirs <String[]>] [-Destination <String>] [-logPath <String>] [-LogfileName <String>] [-CodeDebug <Boolean>] [<CommonParameters>]

.\BackupScript.ps1 [-Copy ] [-ExcludeDirs <String[]>] [-logPath <String>] [-LogfileName <String>] [-Source <String>] [-Target <String>] [-CodeDebug <Boolean>] [<CommonParameters>]
```

## .CHANGELOG

| Version | Date       | Notes                                                                                                  |
| ------- | ---------- | ------------------------------------------------------------------------------------------------------ |
| 1.3.0   | 2026-06-03 | Added PostCheck step; removed global variables; fixed Windows PowerShell 5.1 compatibility; improved backup version cleanup loop |
| 1.2.0   | 2025-09-16 | Improved logic and performance                                                                         |
| 1.1.0   | 2025-08-29 | Added Copy function, large code overhaul, improved logging                                             |
| 1.0.0   | 2025-08-15 | Initial release                                                                                        |
