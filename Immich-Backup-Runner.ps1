function Backup-Windows {
    $immichappFolder = "D:\immich-app"
    $destinationFolder = "\\TRUENAS\dataset1\Backup\Immich"

    if (!(Test-Path -Path $immichappFolder)) {
        Write-Host "Immich-app folder not found. Exiting script."
        exit
    }

    if (!(Test-Path -Path $destinationFolder)) {
        Write-Host "Destination folder not found. Exiting script."
        exit
    }

    Get-ChildItem -Path "$immichappFolder" -File | Copy-Item -Destination $destinationFolder -Force -Verbose

    $splat = @{
        BackupName       = 'Immich'
        SourceDirs       = @(
            "$immichappFolder\config",
            "$immichappFolder\library\backups",
            "$immichappFolder\library\encoded-video",
            "$immichappFolder\library\library",
            "$immichappFolder\library\profile",
            "$immichappFolder\library\thumbs",
            "$immichappFolder\library\upload"
        )
        Destination      = "$destinationFolder"
        VersionKeepCount = 1
        ExcludeDirs      = @(                                           # Exclude large folders that can be regenerated
            'encoded-video\96f15949-e102-4366-b70f-86523935e411',
            'encoded-video\5eaf650b-3e6d-4ec2-8d92-a54334f4efd8',
            'thumbs\96f15949-e102-4366-b70f-86523935e411',
            'thumbs\5eaf650b-3e6d-4ec2-8d92-a54334f4efd8'
        )
        #logPath           = ''
        LogfileName      = 'Immich-Backup-Runner.log'
    }

    Set-Location $PSScriptRoot
    .\BackupScript.ps1 @splat -Backup
}

function Copy-Backup {
    $immichappFolder = "\\TRUENAS\dataset1\Backup\Immich\Immich-2025-09-01"
    $destinationFolder = "\\TRUENAS\apps\immich-app\library"

    if (!(Test-Path -Path $immichappFolder)) {
        Write-Host "Immich-app folder not found. Exiting script."
        exit
    }

    if (!(Test-Path -Path $destinationFolder)) {
        Write-Host "Destination folder not found. Exiting script."
        exit
    }

    $splat = @{
        Source      = "$immichappFolder"
        Target      = "$destinationFolder"
        #ExcludeDirs = @('encoded-videos', 'thumbs')
        LogfileName = 'Immich-CopyTo-TrueNAS-Docker-Runner.log'
    }

    Set-Location $PSScriptRoot
    .\BackupScript.ps1 @splat -Copy

}

#Backup-Windows
Copy-Backup
exit

#$dbDump = & (docker exec -t immich_postgres pg_dumpall --clean --if-exists --username=postgres)
#[System.IO.File]::WriteAllLines("D:\immich-app\dbdump\dbdump.sql", (docker exec -t immich_postgres pg_dumpall --clean --if-exists --username=<DB_USERNAME>))
