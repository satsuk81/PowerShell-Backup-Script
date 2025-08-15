$splat = @{
    BackupName       = 'Immich'
    SourceDirs       = @('D:\immich-app\library\library')
    #SourceDirs       = @('D:\Projects')
    Destination      = '\\TRUENAS\dataset1\Backup\Immich'
    VersionKeepCount = 3
    #ExcludeDirs      = @()
    #logPath           = ''
    LogfileName      = 'Immich-Backup-Runner.log'
}

cd $PSScriptRoot
.\BackupScript.ps1 @splat