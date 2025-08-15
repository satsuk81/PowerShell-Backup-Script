########################################################
# Name: BackupScript_v2.ps1                              
# Creator: Michael Seidl aka Techguy                    
# CreationDate: 05.08.2021                              
# LastModified: 05.08.2021                               
# Version: 2.1
# Doc: http://www.techguy.at/tag/backupscript/
# GitHub: https://github.com/Seidlm/PowerShell-Backup-Script
# PSVersion tested: 5
#
# PowerShell Self Service Web Portal at www.au2mator.com/PowerShell
#
#
# Description: Copies the Bakupdirs to the Destination
# You can configure more than one SourceDirs, every Dir
# wil be copied to the Destination.
# Only Change Variables in Variables Section
# Change LoggingLevel to 3 an get more output in Powershell Windows
# 
#
########################################################
#
# www.techguy.at                                        
# www.facebook.com/TechguyAT                            
# www.twitter.com/TechguyAT                             
# michael@techguy.at 
#
#
########################################################


#Variables, only Change here
$SourceDirs = @(                                            # What Folders you want to backup
 'C:\Temp\Source'
 'C:\Temp\Source2'
)
$Destination = 'C:\Temp\Destination'                        # Copy the Files to this Location
$Versions = 3                                               # How many of the last Backups you want to keep
$ExcludeDirs = @(                                           # This list of Directories will not be copied
    ($env:SystemDrive + '\Users\.*\AppData\Local')
    'C:\Program Files (x86)\Common Files\Adobe' 
)

$logPath = 'C:\temp\_Backup'                                # Log Path
$LogfileName = 'Log'                                        # Log Name

$Zip = $false                                               # Zip the Backup Destination
$ZipFile = ''                                               # Path to the ZIP file (initialized empty)
$Use7ZIP = $false                                           # 7ZIP Module will be installed https://www.powershellgallery.com/packages/7Zip4Powershell/2.0.0
$UseStaging = $false                                        # only if you use ZIP, than we copy file to Staging, zip it and copy the ZIP to destination, like Staging, and to save NetworkBandwith
$StagingPath = 'C:\temp\_Staging'                           # Zip Staging Path
$RemoveBackupDestination = $true                            # Remove copied files after Zip, only if $Zip is true

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
    [string]$logFile = '{0}\{1}_{2}.log' -f $logPath, $(Get-Date -Format yyyy-MM-dd), $LogfileName
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

#endregion

#System Variables, do not change
$PreCheck = $true
$BackUpCheck = $false
$FinalSourceDirs = @()


#SCRIPT
##PRE CHECK
Write-au2matorLog -Type INFO -Text 'Start the Script'
Write-au2matorLog -Type INFO -Text 'Create Backup Dirs and Check all Folders an Path if they exist'

try {
    #Create Backup Dir
    $BackupDestination = $Destination + '\Backup-' + (Get-Date -Format yyyy-MM-ddTHH.mm.ss) + '\'
    New-Item -Path $BackupDestination -ItemType Directory | Out-Null
    Start-Sleep -Seconds 5
    Write-au2matorLog -Type INFO -Text "Create Backupdir $BackupDestination"

    try {
        #Ceck all Directories
        Write-au2matorLog -Type INFO -Text 'Check if SourceDirs exist'
        foreach ($Dir in $SourceDirs) {
            if ((Test-Path $Dir)) {
                
                Write-au2matorLog -Type INFO -Text "$Dir is fine"
                $FinalSourceDirs += $Dir
            }
            else {
                Write-au2matorLog -Type WARNING -Text "$Dir does not exist and was removed from Backup"
            }
        }
        try {
            if ($UseStaging) {
                if ((Test-Path $StagingPath)) {
                
                    Write-au2matorLog -Type INFO -Text "$StagingPath is fine"
                }
                else {
                    Write-au2matorLog -Type ERROR -Text "$StagingPath does not exist"
                    Write-au2matorLog -Type ERROR -Text $_
                    $PreCheck = $false
                }
            }
        }
        catch {
            Write-au2matorLog -Type ERROR -Text "Failed to Check Staging Dir $StagingPath"
            Write-au2matorLog -Type ERROR -Text $_
            $PreCheck = $false
        }
    }
    catch {
        Write-au2matorLog -Type ERROR -Text "Failed to Check Backupdir $BackupDestination"
        Write-au2matorLog -Type ERROR -Text $_
        $PreCheck = $false
        
    }
}
catch {
    Write-au2matorLog -Type ERROR -Text "Failed to Create Backupdir $BackupDestination"
    Write-au2matorLog -Type ERROR -Text $_
    $PreCheck = $false
}


## BACKUP
if ($PreCheck) {
    Write-au2matorLog -Type INFO -Text 'PreCheck was good, so start with Backup'

    try {
        Write-au2matorLog -Type INFO -Text 'Calculate Size and check Files'
        $BackupDirFiles = @{ } #Hash of BackupDir & Files
        $Files = @()
        $SumMB = 0
        $SumItems = 0
        $SumCount = 0
        $colItems = 0
        #$ExcludeString = ""
        
        # Build array of regex patterns for exclusion
        $ExcludePatterns = @()
        foreach ($Entry in $ExcludeDirs) {
            # Exclude the directory itself
            $ExcludePatterns += '^' + [regex]::Escape($Entry) + '$'
            # Exclude the directory's children
            $ExcludePatterns += '^' + [regex]::Escape($Entry) + '\\.*'
        }

        # Function to check if a path matches any exclusion pattern
        function IsExcluded($path, $patterns) {
            foreach ($pattern in $patterns) {
                if ($path -match $pattern) { return $true }
            }
            return $false
        }

        foreach ($Backup in $FinalSourceDirs) {
            $Files = Get-ChildItem -LiteralPath $Backup -Recurse -ErrorVariable +errItems -ErrorAction SilentlyContinue |
            Where-Object {
                -not (IsExcluded $_.FullName $ExcludePatterns) -and
                -not (IsExcluded $_.DirectoryName $ExcludePatterns)
            } |
            Where-Object { -not $_.PSIsContainer }
            $BackupDirFiles.Add($Backup, $Files)
    
            $colItems = ($Files | Measure-Object -Property length -Sum) 
            $Items = 0
            
            $SumMB += $colItems.Sum.ToString()
            $SumItems += $colItems.Count
        }
    
        $TotalMB = '{0:N2}' -f ($SumMB / 1MB) + ' MB of Files'
        Write-au2matorLog -Type INFO -Text "There are $SumItems Files with  $TotalMB to copy"
    
        #Log any errors from above from building the list of files to backup.
        [System.Management.Automation.ErrorRecord]$errItem = $null
        foreach ($errItem in $errItems) {
            Write-au2matorLog -Type WARNING -Text ("Skipping `"" + $errItem.TargetObject + "`" Error: " + $errItem.CategoryInfo)
        }
        Remove-Variable errItem
        Remove-Variable errItems

        try {
            Write-au2matorLog -Type INFO -Text 'Run Backup'


            foreach ($Backup in $FinalSourceDirs) {
                $Index = $Backup.LastIndexOf('\')
                $SplitBackup = $Backup.substring(0, $Index)
                $Files = $BackupDirFiles[$Backup]
        
                foreach ($File in $Files) {
                    $restpath = $file.fullname.replace($SplitBackup, '')
                    try {
                        # Use New-Item to create the destination directory if it doesn't yet exist. Then copy the file.
                        New-Item -Path (Split-Path -Path $($BackupDestination + $restpath) -Parent) -ItemType 'directory' -Force -ErrorAction SilentlyContinue | Out-Null
                        Copy-Item -LiteralPath $file.fullname $($BackupDestination + $restpath) -Force -ErrorAction SilentlyContinue | Out-Null
                        Write-au2matorLog -Type Info -Text $("'" + $File.FullName + "' was copied")
                    }
                    catch {
                        $ErrorCount++
                        Write-au2matorLog -Type ERROR -Text $("'" + $File.FullName + "' returned an error and was not copied")
                    }
                    $Items += (Get-Item -LiteralPath $file.fullname).Length
                    $Index = [array]::IndexOf($SourceDirs, $Backup) + 1
                    $Text = 'Copy data Location {0} of {1}' -f $Index , $SourceDirs.Count
                    if ($File.Attributes -ne 'Directory') { $count++ }
                }
            }
            $SumCount += $Count
            $SumTotalMB = '{0:N2}' -f ($Items / 1MB) + ' MB of Files'
            Write-au2matorLog -Type INFO -Text '----------------------'
            Write-au2matorLog -Type INFO -Text "Copied $SumCount files with $SumTotalMB"
            if ($ErrorCount ) { Write-au2matorLog -Type INFO -Text "$ErrorCount Files could not be copied" }

            $BackUpCheck = $true
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


## ZIP
if ($BackUpCheck) {
    Write-au2matorLog -Type INFO -Text 'BackUpCheck is fine, so lets se if we need to ZIP'
    
    if ($Zip) {
        Write-au2matorLog -Type INFO -Text 'ZIP is on, so lets go'

        if ($Use7ZIP) {
            Write-au2matorLog -Type INFO -Text 'We should use 7Zip for this'
        
            try {
                Write-au2matorLog -Type INFO -Text 'Check for the 7ZIP Module'
                if (Get-Module -Name 7Zip4Powershell) {
                    Write-au2matorLog -Type INFO -Text '7ZIP Module is installed'
                }
                else {
                    Write-au2matorLog -Type INFO -Text '7ZIP Module is not installed, try to install'
                    Install-Module -Name 7Zip4Powershell -Force
                    Import-Module 7Zip4Powershell
                }

                $ZipFile = $StagingPath + ('\' + $BackupDestination.Replace($Destination, '').Replace('\', '') + '.zip')
                
                Write-au2matorLog -Type INFO -Text 'Compress File'
                Compress-7Zip -ArchiveFileName $ZipFile -Path $BackupDestination
                            
                Write-au2matorLog -Type INFO -Text 'Move Zip to Destination'
                Move-Item -Path $ZipFile -Destination $Destination

                $ZIPCheck = $true
            }
            catch {
                Write-au2matorLog -Type ERROR -Text 'Error on 7ZIP compression'
                Write-au2matorLog -Type ERROR -Text $_
                $ZIPCheck = $false
            }
        }
        else {
            # Built-in ZIP logic can be added here if needed
            # Example:
            # $ZipFile = Join-Path $Destination ("Backup-" + (Get-Date -format yyyy-MM-dd) + ".zip")
            # Compress-Archive -Path $BackupDestination -DestinationPath $ZipFile -Force
            # $ZIPCheck = $true
        }
    }
    else {
        Write-au2matorLog -Type INFO -Text 'No Zip, so go ahead'
    }
}
else {
    Write-au2matorLog -Type ERROR -Text 'BackUpCheck failed so do not try to ZIP'
}

##CLEANUP BACKUP
if ($Zip -and $RemoveBackupDestination -and $ZIPCheck) {
    try {
        Write-au2matorLog -Type INFO -Text 'Lets remove Backup Dir after ZIP'
        Get-ChildItem -Path $BackupDestination -Recurse -Force | Remove-Item -Confirm:$false -ErrorAction SilentlyContinue -Recurse 
        Get-Item -Path $BackupDestination | Remove-Item -Confirm:$false  -ErrorAction SilentlyContinue -Recurse | Out-Null

    }
    catch {
        Write-au2matorLog -Type ERROR -Text "Error to Remove Backup Dir: $BackupDestination"
        Write-au2matorLog -Type ERROR -Text $_
        
    }
}


##CLEANUP VERSION
Write-au2matorLog -Type INFO -Text 'Cleanup Backup Dir'

$Count = (Get-ChildItem $Destination | Where-Object { $_.PSIsContainer }).count
if ($Count -gt $Versions) {
    Write-au2matorLog -Type INFO -Text "Found $Count Backups"
    $Folder = Get-ChildItem $Destination | Where-Object { $_.PSIsContainer } | Sort-Object -Property CreationTime | Select-Object -First 1

    Write-au2matorLog -Type INFO -Text "Remove Dir: $Folder"
    Remove-Item -Path $Folder.FullName -Recurse -Force
}


$CountZip = (Get-ChildItem $Destination | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.zip' }).Count
Write-au2matorLog -Type INFO -Text "Check if there are more than $Versions Zip in the Backupdir"

if ($CountZip -gt $Versions) {
    $ZipFileToRemove = Get-ChildItem $Destination | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.zip' } | Sort-Object -Property CreationTime | Select-Object -First 1

    Write-au2matorLog -Type INFO -Text "Remove Zip: $ZipFileToRemove"
    Remove-Item -Path $ZipFileToRemove.FullName -Force
}