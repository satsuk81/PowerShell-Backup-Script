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

#Copy-Item -Path "$immichappFolder\*" -Include '.env', 'docker-compose.yml', 'immich-config.json' -Destination $destinationFolder -Force -Verbose
Get-ChildItem -Path "$immichappFolder" -File | Copy-Item -Destination $destinationFolder -Force -Verbose

$splat = @{
    BackupName       = 'Immich'
    SourceDirs       = @(
        "$immichappFolder\config",
        "$immichappFolder\library\backups",
        "$immichappFolder\library\library",
        "$immichappFolder\library\profile",
        "$immichappFolder\library\upload"
    )
    Destination      = "$destinationFolder"
    VersionKeepCount = 3
    #ExcludeDirs      = @()
    #logPath           = ''
    LogfileName      = 'Immich-Backup-Runner.log'
}

Set-Location $PSScriptRoot
.\BackupScript.ps1 @splat
exit

#$dbDump = & (docker exec -t immich_postgres pg_dumpall --clean --if-exists --username=postgres)
#[System.IO.File]::WriteAllLines("D:\immich-app\dbdump\dbdump.sql", (docker exec -t immich_postgres pg_dumpall --clean --if-exists --username=<DB_USERNAME>))
