$splat = @{
    SourceDirs       = @('D:\immich-app\library\library')
    #SourceDirs       = @('D:\Projects')
    Destination      = 'C:\Temp\Destination'
    VersionKeepCount = 3
    #ExcludeDirs      = @()
    #logPath           = ''
    LogfileName      = 'Immich-Backup-Runner.log'
}

cd $PSScriptRoot
.\BackupScript.ps1 @splat