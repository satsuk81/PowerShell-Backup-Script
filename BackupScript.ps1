<#
.SYNOPSIS
    PowerShell Cross Platform Backup Script

.DESCRIPTION
    This script provides a cross-platform backup solution using PowerShell.

    Based on the PowerShell-Backup-Script by Michael Seidl
    https://github.com/Seidlm/PowerShell-Backup-Script

.NOTES
    Written by      : Daniel Ames
    Build Version   : v1.3.0
    Created         : 2025-08-15
    Updated         : 2026-06-03

    Version history:
    1.3.0 - (2026-06-03) Added PostCheck step, removed global variables, fixed Windows PowerShell 5.1 compatibility, improved backup version cleanup loop
    1.2.0 - (2025-09-16) improved logic and performance
    1.1.0 - (2025-08-29) Added Copy function, large code overhaul, improved logging.
    1.0.0 - (2025-08-15) Initial v1 release

.EXAMPLE
    .\BackupScript.ps1 -SourceDirs 'C:\Data' -Destination '\\server\backup'
#>
#Requires -Version 5.1

[CmdletBinding(DefaultParameterSetName = 'BackupSet')]
#[CmdletBinding(DefaultParameterSetName = 'RestoreSet')]
#[CmdletBinding(DefaultParameterSetName = 'CopySet')]

#mark PARAMETERS
param(
    [Parameter(ParameterSetName = 'BackupSet')][Switch]$Backup,
    [Parameter(ParameterSetName = 'RestoreSet')][Switch]$Restore,
    [Parameter(ParameterSetName = 'CopySet')][Switch]$Copy,
    
    [Parameter(ParameterSetName = 'BackupSet')]
    [string]$BackupName = 'PowerShellBackupScript',

    [Parameter(Mandatory = $false, ParameterSetName = 'BackupSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'RestoreSet')]
    [string[]]$SourceDirs = @('C:\Temp\Source', 'C:\Temp\Source2'),

    [Parameter(Mandatory = $false, ParameterSetName = 'BackupSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'RestoreSet')]
    [string]$Destination = 'C:\Temp\Destination',

    [Parameter(Mandatory = $false, ParameterSetName = 'BackupSet')]
    [int]$VersionKeepCount = 3,

    [Parameter(Mandatory = $false, ParameterSetName = 'BackupSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'CopySet')]
    [string[]]$ExcludeDirs = @('$RECYCLE.BIN', '\.', '\_'),

    [Parameter(Mandatory = $false, ParameterSetName = 'BackupSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'RestoreSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'CopySet')]
    [string]$logPath = "$env:temp\_PowerShellBackupScript",

    [Parameter(Mandatory = $false, ParameterSetName = 'BackupSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'RestoreSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'CopySet')]
    [string]$LogfileName = 'PowerShellBackupScript',

    [Parameter(Mandatory = $false, ParameterSetName = 'CopySet')]
    [string]$Source = 'C:\Temp\Source',

    [Parameter(Mandatory = $false, ParameterSetName = 'CopySet')]
    [string]$Target = 'C:\Temp\Destination',

    [Parameter(Mandatory = $false, ParameterSetName = 'BackupSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'RestoreSet')]
    [Parameter(Mandatory = $false, ParameterSetName = 'CopySet')]
    [boolean]$CodeDebug = $true
)

#region Functions
function Write-Log {
    param(
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR')]
        [string]$Type,
        [string]$Text
    )
       
    [string]$logFile = '{0}\{1}_{2}.log' -f $logPath, $LogfileName, $(Get-Date -Format yyyy-MM-dd)
    $logEntry = '{0}: <{1}> <{2}> {3}' -f $(Get-Date -Format yyyy-MM-ddTHH.mm.ss), $Type, $PID, $Text
    
    try { Add-Content -Path $logFile -Value $logEntry }
    catch {
        Start-Sleep -Milliseconds 50
        try { Add-Content -Path $logFile -Value $logEntry }
        catch { Write-Verbose "Failed to write log entry: $_" }
    }
    switch ($Type) {
        'DEBUG' {
            if ($CodeDebug) {
                Write-Host $Text -ForegroundColor DarkGray 
            }
        }
        'INFO' { Write-Host $Text -ForegroundColor Green }
        'WARNING' { Write-Host $Text -ForegroundColor Yellow }
        'ERROR' { Write-Host $Text -ForegroundColor Red }
        default {}
    }
}

function Invoke-CrossPlatformCopy {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [string[]]$Excludes = @(),
        [string]$PerSourceLogPath = $logPath
    )

    # ensure target exists
    New-Item -Path $Target -ItemType Directory -Force | Out-Null

    $folderName = Split-Path -Path $Source -Leaf
    $robolog = Join-Path $PerSourceLogPath ('{0}_robocopy_{1}_{2}.log' -f $LogfileName, $folderName, (Get-Date -Format 'yyyy-MM-ddTHH.mm.ss'))
    $rsynclog = Join-Path $PerSourceLogPath ('{0}_rsync_{1}_{2}.log' -f $LogfileName, $folderName, (Get-Date -Format 'yyyy-MM-ddTHH.mm.ss'))

    if ($PSVersionTable.PSEdition -ne 'Core' -or $IsWindows) {
        # Build robocopy args
        $roboArgs = @(
            $Source, 
            $Target, 
            '/E', 
            #'/PURGE',
            '/COPY:DAT',
            '/R:0',
            '/W:0',
            '/MT:8',
            #'/NFL',
            #'/V',
            '/TEE',
            "/LOG:$robolog"
        )
        #$roboArgs = @($Source, $Target, '/E', '/COPY:DAT', '/R:0', '/W:0', '/MT:8', '/NFL', '/NDL', '/V', '/TEE', "/LOG:$robolog")
        if ($Excludes.Count -gt 0) {
            $roboArgs += '/XD'
            $roboArgs += $Excludes
        }

        Write-Log -Type INFO -Text ('Starting robocopy: {0} -> {1}' -f $Source, $Target)
        #Write-Log -Type DEBUG -Text ('robocopy ' + ($roboArgs -join ' '))

        $proc = Start-Process -FilePath 'robocopy.exe' -ArgumentList $roboArgs -Wait -PassThru
        $rc = $proc.ExitCode

        # robocopy 0-7 are considered success, >=8 is failure
        $ok = ($rc -lt 8)
        return @{ Ok = $ok; ExitCode = $rc; Log = $robolog }
    }
    else {
        # Non-Windows: use rsync
        if (-not (Get-Command rsync -ErrorAction SilentlyContinue)) {
            Write-Log -Type ERROR -Text 'rsync not found on system. Install rsync or run on Windows.'
            return @{ Ok = $false; ExitCode = 127; Log = $rsynclog }
        }

        # Ensure trailing slash on source for rsync semantics
        $src = $Source
        if (-not ($src.EndsWith('/') -or $src.EndsWith('\'))) { $src = $src + '/' }

        $rsyncArgs = @('-a', '--links', '--perms', '--times', '--delete', '--partial', '--compress', '--stats')
        foreach ($ex in $Excludes) {
            # basic normalization: convert backslashes to forward slashes for rsync
            $pattern = $ex -replace '\\', '/'
            $rsyncArgs += '--exclude'
            $rsyncArgs += $pattern
        }
        $rsyncArgs += '--log-file=' + $rsynclog
        $rsyncArgs += $src
        $rsyncArgs += $Target

        Write-Log -Type INFO -Text ('Starting rsync: {0} -> {1}' -f $src, $Target)
        Write-Log -Type DEBUG -Text ('rsync ' + ($rsyncArgs -join ' '))

        & rsync @rsyncArgs
        $rc = $LASTEXITCODE

        # rsync 0 = OK, 23 means some files vanished (often non-fatal); treat 0 and 23 as usable but log code
        $ok = ($rc -eq 0 -or $rc -eq 23)
        if (-not $ok) {
            Write-Log -Type WARNING -Text ('rsync exit code {0}. See log: {1}' -f $rc, $rsynclog)
        }
        return @{ Ok = $ok; ExitCode = $rc; Log = $rsynclog }
    }
}

function Invoke-Backup {
    param(
        [Parameter(Mandatory)][hashtable]$BackupDirFiles,
        [Parameter(Mandatory)][string]$Target,
        [string[]]$DirsToExclude = @()
    )

    # Initialize counters and flags
    [int]$ErrorCount = 0
    [bool]$BackUpCheck = $false

    Write-Log -Type INFO -Text "Backup Name: $BackupName"
    try {
        Write-Log -Type INFO -Text 'Create Backup Dirs'
        #$BackupDestination = Join-Path -Path $Target -ChildPath ("$BackupName-" + (Get-Date -Format yyyy-MM-ddTHH.mm.ss))
        $BackupDestination = Join-Path -Path $Target -ChildPath ("$BackupName-" + (Get-Date -Format yyyy-MM-dd))
        New-Item -Path $BackupDestination -ItemType Directory -Force | Out-Null
        Write-Log -Type INFO -Text "Create Backupdir $BackupDestination"
    }
    catch {
        Write-Log -Type ERROR -Text "Failed to Create Backupdir $BackupDestination"
        Write-Log -Type ERROR -Text $_
        return
    }

    try {
        Write-Log -Type INFO -Text 'Run Backup (robocopy/rsync wrapper)'
        foreach ($Backup in $BackupDirFiles.Keys) {
            Write-Log -Type INFO -Text "Processing : $($Backup)"
            Write-Log -Type INFO -Text "Files : $($BackupDirFiles.$Backup)"
            $folderName = Split-Path -Path $Backup -Leaf
            $targetName = Join-Path $BackupDestination $folderName

            $result = Invoke-CrossPlatformCopy -Source $Backup -Target $targetName -Excludes $DirsToExclude -PerSourceLogPath $logPath
            if (-not $result.Ok) {
                Write-Log -Type ERROR -Text $("Backup failed for $Backup (code $($result.ExitCode))") 
                Write-Log -Type ERROR -Text $("Log: $($result.Log)")
                $ErrorCount++
                $BackUpCheck = $false
            }
            else {
                Write-Log -Type INFO -Text $("Backup succeeded for $Backup (code $($result.ExitCode))")
                Write-Log -Type INFO -Text $("Log: $($result.Log)")
                $BackUpCheck = $true
            }
        }
    }
    catch {
        Write-Log -Type ERROR -Text 'Failed to Backup'
        Write-Log -Type ERROR -Text $_
        $BackUpCheck = $false
    }

    #region CLEANUP VERSION
    Write-Log -Type INFO -Text 'Cleanup Backup Dir'
    while ((Get-ChildItem $Target | Where-Object { $_.PSIsContainer }).Count -gt $VersionKeepCount) {
        $Count = (Get-ChildItem $Target | Where-Object { $_.PSIsContainer }).Count
        Write-Log -Type INFO -Text "Found $Count Backups (limit $VersionKeepCount), removing oldest"
        $Folder = Get-ChildItem $Target | Where-Object { $_.PSIsContainer } | Sort-Object -Property Name | Select-Object -First 1
        Write-Log -Type INFO -Text "Remove Dir: $Folder"
        Remove-Item -Path $Folder.FullName -Recurse -Force
    }
    #endregion
    
    return $BackUpCheck
}

function Invoke-Restore {
    #System Variables, do not change
    $PreCheck = $true
    $FinalSourceDirs = @()

    # Initialize counters and flags
    [int]$ErrorCount = 0
    [bool]$BackUpCheck = $false

    #region PRE CHECK
    #Write-Log -Type INFO -Text "Backup Name: $BackupName"
    Write-Log -Type INFO -Text 'Checking Destination Folder Path to ensure it exists'
    foreach ($Dir in $Destination) {
        if ((Test-Path $Dir)) {
                
            Write-Log -Type INFO -Text "$Dir is fine"
            $FinalSourceDirs += $Dir
        }
        else {
            Write-Log -Type WARNING -Text "$Dir is missing"
            $PreCheck = $false
            return
        }
    }
    #endregion

    #region RESTORE
    #endregion
}

function Invoke-Copy {
    param(
        [Parameter(Mandatory)][hashtable]$BackupDirFiles,
        [Parameter(Mandatory)][string]$Target,
        [string[]]$DirsToExclude = @()
    )

    [int]$ErrorCount = 0
    [bool]$BackUpCheck = $false
    try {
        Write-Log -Type INFO -Text 'Run Copy (robocopy/rsync wrapper)'
        foreach ($Backup in $BackupDirFiles.Keys) {
            Write-Log -Type INFO -Text "Processing : $($Backup)"
            #Write-Log -Type INFO -Text "Files : $($BackupDirFiles.$Backup)"
            #$folderName = Split-Path -Path $Backup -Leaf
            #$targetName = Join-Path $Target $folderName

            $result = Invoke-CrossPlatformCopy -Source $Backup -Target $Target -Excludes $DirsToExclude -PerSourceLogPath $logPath
            if (-not $result.Ok) {
                Write-Log -Type ERROR -Text $("Copy failed for $Backup (code $($result.ExitCode))") 
                Write-Log -Type ERROR -Text $("Log: $($result.Log)")
                $ErrorCount++
                $BackUpCheck = $false
            }
            else {
                Write-Log -Type INFO -Text $("Copy succeeded for $Backup (code $($result.ExitCode))")
                Write-Log -Type INFO -Text $("Log: $($result.Log)")
                $BackUpCheck = $true
            }
        }
    }
    catch {
        Write-Log -Type ERROR -Text 'Failed to Copy'
        Write-Log -Type ERROR -Text $_
        $BackUpCheck = $false
    }
    return $BackUpCheck
}

function Invoke-SourceAnalyse {
    param(
        [Parameter(Mandatory)][string[]]$SourceDirs,
        [Parameter(Mandatory)][string[]]$ExcludeDirs
    )

    [int]$totalFileCount = 0
    [double]$totalSizeGB = 0

    $backupDirFiles = @{}                   # Hash of BackupDir & Files 
    $dirsToInclude = @()
    $dirsToExclude = @()
    $excludePatterns = @()                  # Build array of regex patterns for exclusion
    foreach ($Entry in $ExcludeDirs) {
        # Exclude the directory itself
        #$excludePatterns += '^' + [regex]::Escape($Entry) + '$'
        $excludePatterns += [regex]::Escape($Entry) + '$'
        # Exclude the directory's children
        #$excludePatterns += '^' + [regex]::Escape($Entry) + '\\.*'
        # Exclude folders matching the pattern
        #$excludePatterns += [regex]::Escape($Entry)
    }
    $excludePatterns | ForEach-Object { Write-Log -Type DEBUG -Text "Exclude pattern: $_" }

    # Function to check if a path matches any exclusion pattern
    function IsExcluded($path, $patterns) {
        foreach ($pattern in $patterns) {
            if ($path -match $pattern) { 
                return $true
            }
        }
        return $false
    }
 
    Write-Log -Type INFO -Text 'Analyzing SourceDirs for Files and Sizes'
    foreach ($Backup in $SourceDirs) {
        if (-not (Test-Path $Backup)) {
            Write-Log -Type WARNING -Text "$Backup does not exist"
            continue
        }
        $allItems = Get-ChildItem -LiteralPath $Backup -Recurse -ErrorAction SilentlyContinue
        <#$files = $files |
        Where-Object {
            -not (IsExcluded $_.FullName $excludePatterns) -and
            -not (IsExcluded $_.DirectoryName $excludePatterns)
        } |            
        Where-Object { -not $_.PSIsContainer }
        if (!$files) {
            Write-Log -Type WARNING -Text "$Backup has no valid files"
            #continue
        }#>
        # Count files and sizes for logging
        $fileItems = $allItems | Where-Object { -not $_.PSIsContainer }
        $fileCount = $fileItems.Count
        $totalFileCount += $fileCount
        $totalSize = ($fileItems | Measure-Object -Property Length -Sum).Sum
        $totalSizeGB += $totalSize / 1GB
        Write-Log -Type INFO -Text "Found $fileCount files in $Backup with total size $([Math]::Round($totalSize / 1GB, 2)) GB"

        # Build include/exclude dir lists from the same scan
        $dirItems = $allItems | Where-Object { $_.PSIsContainer }
        $dirsToInclude += $dirItems | Where-Object {
            -not (IsExcluded $_.FullName $excludePatterns) -and
            -not (IsExcluded $_.DirectoryName $excludePatterns)
        } | Select-Object -ExpandProperty FullName

        $dirsToExclude += $dirItems | Where-Object {
            (IsExcluded $_.FullName $excludePatterns) -or
            (IsExcluded $_.DirectoryName $excludePatterns)
        } | Select-Object -ExpandProperty FullName

        $backupDirFiles.Add($Backup, $allItems)
    }
    Write-Log -Type INFO -Text "Totals Found: $totalFileCount files, size $([Math]::Round($totalSizeGB, 2)) GB"
    if ($backupDirFiles.Count -le 0) {
        Write-Log -Type ERROR -Text 'No valid BackupDirs found, exiting'
        return
    }
    if ($dirsToInclude.Count -lt 100) {
        $dirsToInclude | ForEach-Object { Write-Log -Type DEBUG -Text "Dirs to include: $_" }
    }
    if ($dirsToExclude.Count -lt 100) {
        $dirsToExclude | ForEach-Object { Write-Log -Type DEBUG -Text "Dirs to exclude: $_" }
    }
    #return $backupDirFiles
    return [pscustomobject]@{
        BackupDirFiles  = $backupDirFiles
        TotalSizeGB     = $totalSizeGB
        DirsToInclude   = $dirsToInclude
        DirsToExclude   = $dirsToExclude
    }
}

function Invoke-PreCheck {
    param(
        [Parameter(Mandatory)][string[]]$SourceDirs,
        [Parameter(Mandatory)][string]$Target
    )

    $PreCheck = $true
    $finalSourceDirs = @()
    [double]$totalSizeGB = 0
    [double]$freeSpaceGB = 0
    Write-Log -Type INFO -Text 'Checking all SourceDirs Folders Path to ensure they exist'

    foreach ($Dir in $SourceDirs) {
        if ((Test-Path $Dir)) {          
            Write-Log -Type INFO -Text "$Dir is fine"
            $finalSourceDirs += $Dir
            $files = Get-ChildItem -Path $Dir -Recurse -File -ErrorAction SilentlyContinue
            $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
            $totalSizeGB += $totalSize / 1GB
        }
        else {
            Write-Log -Type WARNING -Text "$Dir does not exist and was removed from Backup"
        }
    }

    if ($finalSourceDirs.Count -le 0) {
        Write-Log -Type ERROR -Text 'No valid SourceDirs found, exiting'
        $PreCheck = $false
    }

    Write-Log -Type INFO -Text 'Checking Destination Folder Path to ensure it exist'
    foreach ($Dir in $Target) {
        if ((Test-Path $Dir)) {          
            Write-Log -Type INFO -Text "$Dir is fine"
        }
        else {
            Write-Log -Type WARNING -Text "$Dir is not found"
            $PreCheck = $false
        }
    }

    try {
        $freeSpaceGB = (Get-PSDrive -Name ((Split-Path -Path $Target -Qualifier -ErrorAction SilentlyContinue)[0])).Free / 1GB
        if ($totalSizeGB -gt 0 -and $freeSpaceGB -lt $totalSizeGB) {
            Write-Log -Type ERROR -Text "Not enough free space on destination drive. Need $($totalSizeGB.ToString('N2')) GB but only $($freeSpaceGB.ToString('N2')) GB available."
            $PreCheck = $false
        }
        else {
            Write-Log -Type INFO -Text "Free space on destination drive: $($freeSpaceGB.ToString('N2')) GB"
        }
    }
    catch {
        Write-Log -Type ERROR -Text 'Failed to get free space on destination drive'
        Write-Log -Type WARNING -Text 'Proceeding with backup, but this may fail due to insufficient space.'
        #Write-Log -Type ERROR -Text $_
        $PreCheck = $true
    }
    
    return [pscustomobject]@{
        PreCheck    = $PreCheck
        FreeSpaceGB = $freeSpaceGB
        TotalSizeGB = $totalSizeGB
        FinalSourceDirs = $finalSourceDirs
    }
}

function Invoke-PostCheck {
    param(
        [Parameter(Mandatory)][string]$Target,
        [double]$TotalSizeGB
    )

    $PostCheck = $true
    [double]$freeSpaceGB = 0
    Write-Log -Type INFO -Text "Updated Total Size from SourceAnalyse: $($TotalSizeGB.ToString('N2')) GB"
    Write-Log -Type INFO -Text 'Checking for free space on Destination Drive'
    try {
        $freeSpaceGB = (Get-PSDrive -Name ((Split-Path -Path $Target -Qualifier -ErrorAction SilentlyContinue)[0])).Free / 1GB
        if ($TotalSizeGB -gt 0 -and $freeSpaceGB -lt $TotalSizeGB) {
            Write-Log -Type ERROR -Text "Not enough free space on destination drive. Need $($TotalSizeGB.ToString('N2')) GB but only $($freeSpaceGB.ToString('N2')) GB available."
            $PostCheck = $false
        }
        else {
            Write-Log -Type INFO -Text "Free space on destination drive: $($freeSpaceGB.ToString('N2')) GB"
        }
    }
    catch {
        Write-Log -Type ERROR -Text 'Failed to get free space on destination drive'
        Write-Log -Type WARNING -Text 'Proceeding with backup, but this may fail due to insufficient space.'
        #Write-Log -Type ERROR -Text $_
        $PostCheck = $true
    }
    
    return [pscustomobject]@{
        PostCheck = $PostCheck
    }
}
#endregion

#region SCRIPT
#$global:FinalSourceDirs = @()

Set-Location $PSScriptRoot

# One-time log directory initialisation
if (-not (Test-Path -Path $logPath)) {
    try {
        $null = New-Item -Path $logPath -ItemType Directory
        Write-Verbose ('Path: "{0}" was created.' -f $logPath)
    }
    catch {
        Write-Warning ("Path: ""{0}"" couldn't be created. Logging may fail." -f $logPath)
    }
}
(Get-Variable -Scope:'Local' -Include:@($MyInvocation.MyCommand.Parameters.keys) | `
    Format-Table -AutoSize `
@{ Label = 'Name'; Expression = { "$($_.Name)" }; }, `
@{ Label = 'Value'; Expression = { if ( $_.ParameterType -notmatch 'String' ) { $_.Value; } else { "`"$($_.Value)`""; } }; Alignment = 'left'; }
)
Write-Host "ParamSet: $($PSCmdlet.ParameterSetName)"

Write-Log -Type INFO -Text 'Start the Script'
switch ($PSCmdlet.ParameterSetName) {
    'BackupSet' {
        $result = Invoke-PreCheck -SourceDirs $SourceDirs -Target $Destination
        if ($result.PreCheck) {
            Write-Log -Type WARNING -Text 'PreCheck successful, starting SourceAnalyse'
            $FinalSourceDirs = $result.FinalSourceDirs
            $sourceResults = Invoke-SourceAnalyse -SourceDirs $FinalSourceDirs -ExcludeDirs $ExcludeDirs
            if ($sourceResults) {
                Write-Log -Type WARNING -Text 'SourceAnalyse successful, starting PostCheck'
                $postCheckResults = Invoke-PostCheck -Target $Destination -TotalSizeGB $sourceResults.TotalSizeGB
                if ($postCheckResults.PostCheck) {
                    Write-Log -Type WARNING -Text 'PostCheck successful, starting Backup'
                    Invoke-Backup -BackupDirFiles $sourceResults.BackupDirFiles -Target $Destination -DirsToExclude $sourceResults.DirsToExclude
                }
            }
        }
        else {
            Write-Log -Type ERROR -Text 'PreCheck failed so do not run Copy'
        }
        
    }
    'RestoreSet' {
        #Invoke-Restore
    }
    'CopySet' {
        $result = Invoke-PreCheck -SourceDirs @($Source) -Target $Target
        if ($result.PreCheck) {
            Write-Log -Type WARNING -Text 'PreCheck successful, starting SourceAnalyse'
            $FinalSourceDirs = $result.FinalSourceDirs
            $sourceResults = Invoke-SourceAnalyse -SourceDirs $FinalSourceDirs -ExcludeDirs $ExcludeDirs
            if ($sourceResults) {
                Write-Log -Type WARNING -Text 'SourceAnalyse successful, starting PostCheck'
                $postCheckResults = Invoke-PostCheck -Target $Target -TotalSizeGB $sourceResults.TotalSizeGB
                if ($postCheckResults.PostCheck) {
                    Write-Log -Type WARNING -Text 'PostCheck successful, starting Copy'
                    Invoke-Copy -BackupDirFiles $sourceResults.BackupDirFiles -Target $Target -DirsToExclude $sourceResults.DirsToExclude
                }
            }
        }
        else {
            Write-Log -Type ERROR -Text 'PreCheck failed so do not run Copy'
        }
    }
    default {

    }
}
#endregion
exit

Get-Help ./BackupScript.ps1 -ShowWindow