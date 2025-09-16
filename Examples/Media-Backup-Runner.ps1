Set-Location $PSScriptRoot\..

function Backup-Media {
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

    .\BackupScript.ps1 @splat -Backup
}

function Copy-Files {
    param(
        [Parameter(Mandatory)][String]$SourceFolder,
        [Parameter(Mandatory)][String]$DestinationFolder
    )

    if (!(Test-Path -Path $sourceFolder)) {
        Write-Host "Source folder not found. Exiting script."
        exit
    }

    if (!(Test-Path -Path $destinationFolder)) {
        Write-Host "Destination folder not found. Exiting script."
        exit
    }

    $splat = @{
        Source      = "$sourceFolder"
        Target      = "$destinationFolder"
        #ExcludeDirs = @('encoded-videos', 'thumbs')
        LogfileName = 'Media-CopyTo-TrueNAS-Backup-Runner.log'
    }

    .\BackupScript.ps1 @splat -Copy

}

#Backup-Media
Copy-Files -SourceFolder "D:\Media\Backup" -DestinationFolder "\\truenas\dataset3\Backup\Media"
Copy-Files -SourceFolder "D:\Media\Photos" -DestinationFolder "\\truenas\dataset3\Backup\Photos"
Copy-Files -SourceFolder "\\TRUENAS\dataset2\olddisk\media\Pictures" -DestinationFolder "\\TRUENAS\dataset3\backup\Photos"
exit

Get-Help .\BackupScript.ps1 -ShowWindow