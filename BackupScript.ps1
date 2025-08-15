<#
.SYNOPSIS
    PowerShell Cross Platform Backup Script

.DESCRIPTION
    This script provides a cross-platform backup solution using PowerShell.

    Based on the PowerShell-Backup-Script by Michael Seidl
    https://github.com/Seidlm/PowerShell-Backup-Script

.NOTES
    Written by      : Daniel Ames
    Build Version   : v1
    Created         : 2025-08-15
    Modified        : 2025-08-15

.EXAMPLE
    .\BackupScript.ps1 -SourceDirs 'C:\Data' -Destination '\\server\backup'
#>
#Requires -Version 5.0

param(
    [Parameter(Mandatory = $false)]
    [string]$BackupName = 'PowerShellBackupScript',

    [Parameter(Mandatory = $false)]
    [string[]]$SourceDirs = @('C:\Temp\Source', 'C:\Temp\Source2'),

    [Parameter(Mandatory = $false)]
    [string]$Destination = 'C:\Temp\Destination',

    [Parameter(Mandatory = $false)]
    [int]$VersionKeepCount = 3,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeDirs = @('$RECYCLE.BIN', '\.', '\_'),

    [Parameter(Mandatory = $false)]
    [string]$logPath = "$env:temp\_PowerShellBackupScript",

    [Parameter(Mandatory = $false)]
    [string]$LogfileName = 'PowerShellBackupScript'
)

#region Functions
function Write-au2matorLog {
    [CmdletBinding()]
    param
    (
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
    if ($Type -eq 'ERROR') {
        Write-Host $Text -ForegroundColor Red
    }
    else {
        Write-Host $Text
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
            '/PURGE',
            '/COPY:DAT',
            '/R:0',
            '/W:0',
            '/MT:8',
            '/NFL',
            '/V',
            '/TEE',
            "/LOG:$robolog"
        )
        #$roboArgs = @($Source, $Target, '/E', '/COPY:DAT', '/R:0', '/W:0', '/MT:8', '/NFL', '/NDL', '/V', '/TEE', "/LOG:$robolog")
        if ($Excludes.Count -gt 0) {
            $roboArgs += '/XD'
            $roboArgs += $Excludes
        }

        Write-au2matorLog -Type INFO -Text ('Starting robocopy: {0} -> {1}' -f $Source, $Target)
        #Write-au2matorLog -Type DEBUG -Text ('robocopy ' + ($roboArgs -join ' '))

        Start-Process -FilePath 'robocopy.exe' -ArgumentList $roboArgs -Wait
        $rc = $LASTEXITCODE

        # robocopy 0-7 are considered success, >=8 is failure
        $ok = ($rc -lt 8)
        return @{ Ok = $ok; ExitCode = $rc; Log = $robolog }
    }
    else {
        # Non-Windows: use rsync
        if (-not (Get-Command rsync -ErrorAction SilentlyContinue)) {
            Write-au2matorLog -Type ERROR -Text 'rsync not found on system. Install rsync or run on Windows.'
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

        Write-au2matorLog -Type INFO -Text ('Starting rsync: {0} -> {1}' -f $src, $Target)
        Write-au2matorLog -Type DEBUG -Text ('rsync ' + ($rsyncArgs -join ' '))

        & rsync @rsyncArgs
        $rc = $LASTEXITCODE

        # rsync 0 = OK, 23 means some files vanished (often non-fatal); treat 0 and 23 as usable but log code
        $ok = ($rc -eq 0 -or $rc -eq 23)
        if (-not $ok) {
            Write-au2matorLog -Type WARNING -Text ('rsync exit code {0}. See log: {1}' -f $rc, $rsynclog)
        }
        return @{ Ok = $ok; ExitCode = $rc; Log = $rsynclog }
    }
}
#endregion

#System Variables, do not change
$PreCheck = $true
$FinalSourceDirs = @()

# Initialize counters and flags
[int]$ErrorCount = 0
[bool]$BackUpCheck = $false

#region SCRIPT
#region PRE CHECK
Write-au2matorLog -Type INFO -Text 'Start the Script'
Write-au2matorLog -Type INFO -Text "Backup Name: $BackupName"
Write-au2matorLog -Type INFO -Text 'Checking all SourceDirs Folders Path to ensure they exist'
foreach ($Dir in $SourceDirs) {
    if ((Test-Path $Dir)) {
                
        Write-au2matorLog -Type INFO -Text "$Dir is fine"
        $FinalSourceDirs += $Dir
    }
    else {
        Write-au2matorLog -Type WARNING -Text "$Dir does not exist and was removed from Backup"
    }
}
if ($FinalSourceDirs.Count -le 0) {
    Write-au2matorLog -Type ERROR -Text 'No valid SourceDirs found, exiting'
    $PreCheck = $false
    return
}
#endregion

#region BACKUP
if ($PreCheck) {
    Write-au2matorLog -Type INFO -Text 'PreCheck was good, so start with Backup'
    try {
        #Create Backup Dir
        Write-au2matorLog -Type INFO -Text 'Create Backup Dirs'
        #$BackupDestination = Join-Path -Path $Destination -ChildPath ("$BackupName-" + (Get-Date -Format yyyy-MM-ddTHH.mm.ss))
        $BackupDestination = Join-Path -Path $Destination -ChildPath ("$BackupName-" + (Get-Date -Format yyyy-MM-dd))
        New-Item -Path $BackupDestination -ItemType Directory -Force | Out-Null
        Write-au2matorLog -Type INFO -Text "Create Backupdir $BackupDestination"
    }
    catch {
        Write-au2matorLog -Type ERROR -Text "Failed to Create Backupdir $BackupDestination"
        Write-au2matorLog -Type ERROR -Text $_
        return
    }

    try {
        Write-au2matorLog -Type INFO -Text 'Calculate Size and check Files'
        $BackupDirFiles = @{ } #Hash of BackupDir & Files
        $Files = @()
        $SumMB = 0
        $SumItems = 0
        $colItems = 0

        # Build array of regex patterns for exclusion
        $ExcludePatterns = @()
        foreach ($Entry in $ExcludeDirs) {
            # Exclude the directory itself
            $ExcludePatterns += '^' + [regex]::Escape($Entry) + '$'
            # Exclude the directory's children
            $ExcludePatterns += '^' + [regex]::Escape($Entry) + '\\.*'
            # Exclude folders matching the pattern
            $ExcludePatterns += [regex]::Escape($Entry)
        }

        # Function to check if a path matches any exclusion pattern
        function IsExcluded($path, $patterns) {
            foreach ($pattern in $patterns) {
                if ($path -match $pattern) { return $true }
            }
            return $false
        }
        $dirsToInclude = @()
        $dirsToExclude = @()
        foreach ($Backup in $FinalSourceDirs) {
            $Files = Get-ChildItem -LiteralPath $Backup -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                -not (IsExcluded $_.FullName $ExcludePatterns) -and
                -not (IsExcluded $_.DirectoryName $ExcludePatterns)
            } |            
            Where-Object { -not $_.PSIsContainer }
            if (!$Files) {
                Write-au2matorLog -Type WARNING -Text "$Backup has no valid files"
                #continue
            }
            $dirsToInclude += $Backup
            $dirsToInclude += Get-ChildItem -LiteralPath $Backup -Recurse -ErrorAction SilentlyContinue | 
            Where-Object {
                -not (IsExcluded $_.FullName $ExcludePatterns) -and
                -not (IsExcluded $_.DirectoryName $ExcludePatterns)
            } |
            Where-Object { $_.PSIsContainer } |
            Select-Object -ExpandProperty FullName
            #Write-Host 'Folders to include:'
            #$dirsToInclude | Format-Table


            #$dirsToExclude += $Backup
            $dirsToExclude += Get-ChildItem -LiteralPath $Backup -Recurse -ErrorAction SilentlyContinue | 
            Where-Object {
                (IsExcluded $_.FullName $ExcludePatterns) -or
                (IsExcluded $_.DirectoryName $ExcludePatterns)
            } |
            Where-Object { $_.PSIsContainer } |
            Select-Object -ExpandProperty FullName
            #Write-Host 'Folders to exlclude:'
            #$dirsToExclude | Format-Table

            $BackupDirFiles.Add($Backup, $Files)
    
            $colItems = ($Files | Measure-Object -Property length -Sum)
            $SumMB += $colItems.Sum
            $SumItems += $colItems.Count
        }
    
        $TotalGB = ('{0:N2} GB of Files' -f ($SumMB / 1GB))
        Write-au2matorLog -Type INFO -Text "There are $SumItems Files with $TotalGB to copy"
        
        if ($BackupDirFiles.Count -le 0) {
            Write-au2matorLog -Type ERROR -Text 'No valid BackupDirs found, exiting'
            return
        }

        Write-au2matorLog -Type INFO -Text 'Checking for free space on Destination Drive'
        try {
            $freeSpace = (Get-PSDrive -Name ((Split-Path -Path $Destination -Qualifier -ErrorAction SilentlyContinue)[0])).Free / 1GB
            Write-au2matorLog -Type INFO -Text "Free space on destination drive: $($freeSpace.ToString('N2')) GB"
            if ($freeSpace -lt ($SumMB / 1GB)) {
                Write-au2matorLog -Type ERROR -Text "Not enough free space on destination drive. Only $($freeSpace.ToString('N2')) GB available."
                $PreCheck = $false
                return
            }
            else {
                Write-au2matorLog -Type INFO -Text "Free space on destination drive: $($freeSpace.ToString('N2')) GB"
            }
        }
        catch {
            Write-au2matorLog -Type ERROR -Text 'Failed to get free space on destination drive'
            Write-au2matorLog -Type WARNING -Text 'Proceeding with backup, but this may fail due to insufficient space.'
            #Write-au2matorLog -Type ERROR -Text $_
        }

        try {
            Write-au2matorLog -Type INFO -Text 'Run Backup (robocopy/rsync wrapper)'
            foreach ($Backup in $BackupDirFiles.Keys) {
                Write-au2matorLog -Type INFO -Text "Processing : $($Backup)"
                #Write-au2matorLog -Type INFO -Text "Files : $($BackupDirFiles.$Backup)"
                $folderName = Split-Path -Path $Backup -Leaf
                $target = Join-Path $BackupDestination $folderName

                $result = Invoke-CrossPlatformCopy -Source $Backup -Target $target -Excludes $dirsToExclude -PerSourceLogPath $logPath
                if (-not $result.Ok) {
                    Write-au2matorLog -Type ERROR -Text $("Backup failed for $Backup (code $($result.ExitCode))") 
                    Write-au2matorLog -Type ERROR -Text $("Log: $($result.Log)")
                    $ErrorCount++
                    $BackUpCheck = $false
                }
                else {
                    Write-au2matorLog -Type INFO -Text $("Backup succeeded for $Backup (code $($result.ExitCode))")
                    Write-au2matorLog -Type INFO -Text $("Log: $($result.Log)")
                    $BackUpCheck = $true
                }
            }
        }
        catch {
            Write-au2matorLog -Type ERROR -Text 'Failed to Backup'
            Write-au2matorLog -Type ERROR -Text $_
            $BackUpCheck = $false
        }
    }
    catch {
        Write-au2matorLog -Type ERROR -Text 'Failed to Measure Backupdir'
        Write-au2matorLog -Type ERROR -Text $_
        $BackUpCheck = $false
    }
}
else {
    Write-au2matorLog -Type ERROR -Text 'PreCheck failed so do not run Backup'
    $BackUpCheck = $false
}
#endregion

#region CLEANUP VERSION
Write-au2matorLog -Type INFO -Text 'Cleanup Backup Dir'
$Count = (Get-ChildItem $Destination | Where-Object { $_.PSIsContainer }).count
if ($Count -gt $VersionKeepCount) {
    Write-au2matorLog -Type INFO -Text "Found $Count Backups"
    $Folder = Get-ChildItem $Destination | Where-Object { $_.PSIsContainer } | Sort-Object -Property CreationTime | Select-Object -First 1
    Write-au2matorLog -Type INFO -Text "Remove Dir: $Folder"
    Remove-Item -Path $Folder.FullName -Recurse -Force
}
#endregion
#endregion