<#
.SYNOPSIS
    PowerShell Cross Platform Backup Script

.DESCRIPTION
    This script provides a cross-platform backup solution using PowerShell.

    Based on the PowerShell-Backup-Script by Michael Seidl
    https://github.com/Seidlm/PowerShell-Backup-Script

.NOTES
    Written by      : Daniel Ames
    Build Version   : v1.2.0
    Created         : 2025-08-15
    Updated         : 2025-09-16

    Version history:
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
       
    # Set logging path
    if (!(Test-Path -Path $logPath)) {
        try {
            $null = New-Item -Path $logPath -ItemType Directory
            Write-Verbose ('Path: "{0}" was created.' -f $logPath)
        }
        catch {
            Write-Verbose ("Path: ""{0}"" couldn't be created." -f $logPath)
        }
    }
    else {
        Write-Verbose ('Path: "{0}" already exists.' -f $logPath)
    }
    [string]$logFile = '{0}\{1}_{2}.log' -f $logPath, $LogfileName, $(Get-Date -Format yyyy-MM-dd)
    $logEntry = '{0}: <{1}> <{2}> {3}' -f $(Get-Date -Format yyyy-MM-ddTHH.mm.ss), $Type, $PID, $Text
    
    try { Add-Content -Path $logFile -Value $logEntry }
    catch {
        Start-Sleep -Milliseconds 50
        Add-Content -Path $logFile -Value $logEntry
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

    if ($IsWindows) {
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

        Start-Process -FilePath 'robocopy.exe' -ArgumentList $roboArgs -Wait
        $rc = $LASTEXITCODE

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
        [Parameter(Mandatory)][string]$Target
    )

    # Initialize counters and flags
    [int]$ErrorCount = 0

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
            #Write-Log -Type INFO -Text "Files : $($BackupDirFiles.$Backup)"
            $folderName = Split-Path -Path $Backup -Leaf
            $targetName = Join-Path $BackupDestination $folderName

            $result = Invoke-CrossPlatformCopy -Source $Backup -Target $targetName -Excludes $global:dirsToExclude -PerSourceLogPath $logPath
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
    $Count = (Get-ChildItem $Target | Where-Object { $_.PSIsContainer }).count
    if ($Count -gt $VersionKeepCount) {
        Write-Log -Type INFO -Text "Found $Count Backups"
        $Folder = Get-ChildItem $Target | Where-Object { $_.PSIsContainer } | Sort-Object -Property CreationTime | Select-Object -First 1
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
        [Parameter(Mandatory)][string]$Target
    )

    try {
        Write-Log -Type INFO -Text 'Run Backup (robocopy/rsync wrapper)'
        foreach ($Backup in $BackupDirFiles.Keys) {
            Write-Log -Type INFO -Text "Processing : $($Backup)"
            #Write-Log -Type INFO -Text "Files : $($BackupDirFiles.$Backup)"
            #$folderName = Split-Path -Path $Backup -Leaf
            #$targetName = Join-Path $Target $folderName

            $result = Invoke-CrossPlatformCopy -Source $Backup -Target $Target -Excludes $global:dirsToExclude -PerSourceLogPath $logPath
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
    return $BackUpCheck
}

function Invoke-SourceAnalyse {
    param(
        [Parameter(Mandatory)][string[]]$SourceDirs,
        [Parameter(Mandatory)][string[]]$ExcludeDirs
    )

    [int]$TotalFileCount = 0
    [int]$TotalSizeSumGB = 0
    Write-Log -Type INFO -Text 'Analyzing SourceDirs for Files and Sizes'
    foreach ($Dir in $SourceDirs) {
        if ((Test-Path $Dir)) {
            $Files = Get-ChildItem -Path $Dir -Recurse -File -ErrorAction SilentlyContinue
            $FileCount = $Files.Count
            $TotalFileCount += $FileCount
            $TotalSize = ($Files | Measure-Object -Property Length -Sum).Sum
            $TotalSizeSumGB += $TotalSize / 1GB
            Write-Log -Type INFO -Text "Found $FileCount files in $Dir with total size $([Math]::Round($TotalSize / 1GB, 2)) GB"
        }
        else {
            Write-Log -Type WARNING -Text "$Dir does not exist"
        }
    }
    Write-Log -Type INFO -Text "Totals Found: $TotalFileCount files, size $([Math]::Round($TotalSizeSumGB, 2)) GB"

    $BackupDirFiles = @{}                   # Hash of BackupDir & Files 
    $global:dirsToInclude = @()
    $global:dirsToExclude = @()
    $ExcludePatterns = @()                  # Build array of regex patterns for exclusion
    foreach ($Entry in $ExcludeDirs) {
        # Exclude the directory itself
        #$ExcludePatterns += '^' + [regex]::Escape($Entry) + '$'
        $ExcludePatterns += [regex]::Escape($Entry) + '$'
        # Exclude the directory's children
        #$ExcludePatterns += '^' + [regex]::Escape($Entry) + '\\.*'
        # Exclude folders matching the pattern
        #$ExcludePatterns += [regex]::Escape($Entry)
    }
    $ExcludePatterns | ForEach-Object { Write-Log -Type DEBUG -Text "Exclude pattern: $_" }

    # Function to check if a path matches any exclusion pattern
    function IsExcluded($path, $patterns) {
        foreach ($pattern in $patterns) {
            if ($path -match $pattern) { 
                return $true
            }
        }
        return $false
    }
 
    foreach ($Backup in $SourceDirs) {
        <#$Files = Get-ChildItem -LiteralPath $Backup -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            -not (IsExcluded $_.FullName $ExcludePatterns) -and
            -not (IsExcluded $_.DirectoryName $ExcludePatterns)
        } |            
        Where-Object { -not $_.PSIsContainer }
        if (!$Files) {
            Write-Log -Type WARNING -Text "$Backup has no valid files"
            #continue
        }#>
        #$dirsToInclude += $Backup
        $global:dirsToInclude += Get-ChildItem -Directory -LiteralPath $Backup -Recurse -ErrorAction SilentlyContinue | 
        Where-Object {
            -not (IsExcluded $_.FullName $ExcludePatterns) -and
            -not (IsExcluded $_.DirectoryName $ExcludePatterns)
        } |
        Where-Object { $_.PSIsContainer } |
        Select-Object -ExpandProperty FullName

        $global:dirsToExclude += Get-ChildItem -Directory -LiteralPath $Backup -Recurse -ErrorAction SilentlyContinue | 
        Where-Object {
            (IsExcluded $_.FullName $ExcludePatterns) -or
            (IsExcluded $_.DirectoryName $ExcludePatterns)
        } |
        Where-Object { $_.PSIsContainer } |
        Select-Object -ExpandProperty FullName

        $BackupDirFiles.Add($Backup, $Files)
    }
    if ($BackupDirFiles.Count -le 0) {
        Write-Log -Type ERROR -Text 'No valid BackupDirs found, exiting'
        return
    }
    if ($dirsToInclude.Count -lt 100) {
        $dirsToInclude | ForEach-Object { Write-Log -Type DEBUG -Text "Dirs to include: $_" }
    }
    if ($dirsToExclude.Count -lt 100) {
        $dirsToExclude | ForEach-Object { Write-Log -Type DEBUG -Text "Dirs to exclude: $_" }
    }
    return $BackupDirFiles
}

function Invoke-PreCheck {
    param(
        [Parameter(Mandatory)][string[]]$SourceDirs,
        [Parameter(Mandatory)][string]$Target
    )

    $PreCheck = $true
    Write-Log -Type INFO -Text 'Checking all SourceDirs Folders Path to ensure they exist'
    foreach ($Dir in $SourceDirs) {
        if ((Test-Path $Dir)) {          
            Write-Log -Type INFO -Text "$Dir is fine"
            $global:FinalSourceDirs += $Dir
        }
        else {
            Write-Log -Type WARNING -Text "$Dir does not exist and was removed from Backup"
        }
    }
    if ($FinalSourceDirs.Count -le 0) {
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

    Write-Log -Type INFO -Text 'Checking for free space on Destination Drive'
    try {
        $freeSpace = (Get-PSDrive -Name ((Split-Path -Path $Target -Qualifier -ErrorAction SilentlyContinue)[0])).Free / 1GB
        if ($freeSpace -lt ($SumMB / 1GB)) {
            Write-Log -Type ERROR -Text "Not enough free space on destination drive. Only $($freeSpace.ToString('N2')) GB available."
            $PreCheck = $false
        }
        else {
            Write-Log -Type INFO -Text "Free space on destination drive: $($freeSpace.ToString('N2')) GB"
        }
    }
    catch {
        Write-Log -Type ERROR -Text 'Failed to get free space on destination drive'
        Write-Log -Type WARNING -Text 'Proceeding with backup, but this may fail due to insufficient space.'
        #Write-Log -Type ERROR -Text $_
        $PreCheck = $true
    }
    return $PreCheck
}
#endregion

#region SCRIPT
$global:FinalSourceDirs = @()

Set-Location $PSScriptRoot
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
        if ($result) {
            Write-Log -Type WARNING -Text 'PreCheck successful, starting SourceAnalyse'
            $sourceResults = Invoke-SourceAnalyse -SourceDirs $FinalSourceDirs -ExcludeDirs $ExcludeDirs
            if ($sourceResults) {
                Write-Log -Type WARNING -Text 'SourceAnalyse successful, starting Copy'
                Invoke-Backup -BackupDirFiles $sourceResults -Target $Destination
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
        if ($result) {
            Write-Log -Type WARNING -Text 'PreCheck successful, starting SourceAnalyse'
            $sourceResults = Invoke-SourceAnalyse -SourceDirs $FinalSourceDirs -ExcludeDirs $ExcludeDirs
            if ($sourceResults) {
                Write-Log -Type WARNING -Text 'SourceAnalyse successful, starting Copy'
                Invoke-Copy -BackupDirFiles $sourceResults -Target $Target
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