# PowerShell Cross Platform Backup Script

## .SYNOPSIS

PowerShell Cross Platform Backup Script

## .DESCRIPTION

This script provides a cross-platform backup solution using PowerShell.

Based on the PowerShell-Backup-Script by Michael Seidl\
[https://github.com/Seidlm/PowerShell-Backup-Script](https://github.com/Seidlm/PowerShell-Backup-Script)

## .NOTES

Written by      : Daniel Ames\
Build Version   : v1.2.0\
Created         : 2025-08-15\
Modified        : 2025-09-16

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
.\BackupScript.ps1 @splat
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
    C:\Git\GitHub\PowerShell-Backup-Script\BackupScript.ps1 [-Backup ] [-BackupName <String>] [-SourceDirs <String[]>] [-Destination <String>] [-VersionKeepCount <Int32>] [-ExcludeDirs <String[]>] [-logPath <String>] [-LogfileName <String>] [-CodeDebug <Boolean>] [<CommonParameters>]

    C:\Git\GitHub\PowerShell-Backup-Script\BackupScript.ps1 [-Restore ] [-SourceDirs <String[]>] [-Destination <String>] [-logPath <String>] [-LogfileName <String>] [-CodeDebug <Boolean>] [<CommonParameters>]

    C:\Git\GitHub\PowerShell-Backup-Script\BackupScript.ps1 [-Copy ] [-ExcludeDirs <String[]>] [-logPath <String>] [-LogfileName <String>] [-Source <String>] [-Target <String>] [-CodeDebug <Boolean>] [<CommonParameters>]
```
