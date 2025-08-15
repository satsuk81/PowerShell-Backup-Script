# PowerShell Cross Platform Backup Script

## .SYNOPSIS

PowerShell Cross Platform Backup Script

## .DESCRIPTION

This script provides a cross-platform backup solution using PowerShell.

Based on the PowerShell-Backup-Script by Michael Seidl\
[https://github.com/Seidlm/PowerShell-Backup-Script](https://github.com/Seidlm/PowerShell-Backup-Script)

## .NOTES

Written by      : Daniel Ames\
Build Version   : v1\
Created         : 2025-08-15\
Modified        : 2025-08-15

## .EXAMPLE

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
