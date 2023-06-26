<#
.NOTES
    Copyright (c) Roman Ermakov <r.ermakov@emg.fm>
    Use of this sample source code is subject to the terms of the
    GNU General Public License under which you licensed this sample source code. If
    you did not accept the terms of the license agreement, you are not
    authorized to use this sample source code.
    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
    THIS CODE IS PROVIDED "AS IS" WITH NO WARRANTIES.
    
.SYNOPSIS
    This script backups DJin folders over the network computers. Use a Windows Scheduler to run it as:
    C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
    with argument:
    -NoProfile -ExecutionPolicy bypass -File "C:\path-to\Digispot-Backup.ps1"
    
.DESCRIPTION
    Use Digispot-BackupDJin.csv file to set folders to backup.
    Use $dstPath variable to set destination path to store backups.
    Each backup will be stored to folder in $dstPath like COMPUTERNAME\2022-12-22 and will
        consist of licensing files and SYSTEM folder.
    Script operation logs save to .\log folder

.LINK
    https://github.com/ykmn/

.EXAMPLE
    Digispot-BackupDJin.ps1 [configFile.csv]
.PARAMETER cfg
    Configuration file. Should have .csv extension and consist one URI to DJin folder per line. Example:
\\computername1\c$\Program Files (x86)\Digispot II\AMPV_Europa_main\Djin
\\computername1\c$\Program Files (x86)\Digispot II\AMPV_Retro_main\Djin
    If specific configuration file is omitted the script uses Digispot-BackupDJin.csv
.
#>
<#
.VERSIONS
    Digispot-BackupDJin.ps1

v1.00 2022-12-23 initial version
v1.01 2023-06-15 small fixes
#>
# Handling command-line parameters
param (
    [Parameter(Mandatory=$false)][string]$cfg
)
$encoding = [Console]::OutputEncoding
#[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("UTF8")
#[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("oem")
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "`n`nThis script works with PowerShell Core 7.0 or newer.`nPlease upgrade!`n"
    Break
}

###############################################################
#
# Configuration >>
$dstPath = "\\EMG-STORAGE\Tech\-djin backups-"
$include = @('KeyDll*.dll', '*.info', '*.ini')
$exclude = @('*.tmp','*.log')
$backupsAge = -90    # delete backups older than 90 days
$fileversion = "v1.01 2023-06-15"
#
#
###############################################################

Write-Host "`nDigispot-BackupDJin.ps1   " $fileversion
Write-Host "Backup DJin folders`n"
if (!($cfg)) { $cfg = "Digispot-BackupDJin.csv" }

# Setup log files
[string]$currentdir = Get-Location
$PSscript = Get-Item $MyInvocation.MyCommand.Name


if (!(Test-Path $currentdir"\log")) {
    New-Item -Path $currentdir"\log" -Force -ItemType Directory | Out-Null
}
function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$message,
        [Parameter(Mandatory=$false)][string]$color
    )
    #$logfile = $currentdir + "\log\" + $(Get-Date -Format yyyy-MM-dd) + "-" + $MyInvocation.MyCommand.Name + ".log"
    $logfile = $currentdir + "\log\" + $(Get-Date -Format yyyy-MM-dd) + "-" + $PSscript.BaseName + ".log"
    $now = Get-Date -Format HH:mm:ss.fff
    $message = "$now : " + $message
    if ($color) {
        Write-Host $message -ForegroundColor $color    
    } else {
        Write-Host $message
    }
    $message | Out-File $logfile -Append -Encoding "UTF8"
    
}
Write-Log -message "** Script started"

# Check destination for availability
if (!(Test-Path $dstPath)) {
    Write-Log -message "[-] Destination path $dstPath is not available"
    break
}

# Import CSV to array
$array = Import-Csv -Path $cfg -Delimiter ";" -Header "UNC", "hostname", "path"
# for ($n=0; $n -lt $array.count; $n++) {
#     # parsing array values
#     $array[$n].hostname = [string]$array[$n].UNC.Split('\')[2]
#     $array[$n].path = [string]::Join('\', $array[$n].UNC.Split('\')[6..$($array[$n].UNC.Split('\').Length)])
# }
# $array | ft # behold!

###############################################################
# Reading configuration array. For each raw:
for ($n=0; $n -lt $array.count; $n++) {
    $skip = $false

    # parsing array values
    $array[$n].hostname = [string]$array[$n].UNC.Split('\')[2]
    $array[$n].path = [string]::Join('\', $array[$n].UNC.Split('\')[6..$($array[$n].UNC.Split('\').Length)])

    # create source and destination strings
    $src = $array[$n].UNC
    $dst = $dstPath+"\"+$array[$n].hostname+"\"+$(Get-Date -Format yyyy-MM-dd)+"\"+$array[$n].path
    $dstStore = $dstPath+"\"+$array[$n].hostname

    Write-Host "`n$($array[$n].hostname)" -BackgroundColor DarkGray -ForegroundColor Black
    Write-Log "[!] Source:      $src"
    Write-Log "[!] Store:       $dstStore"
    Write-Log "[!] Destination: $dst"

###############################################################   
# Check source for availability
    if (!(Test-Path $src)) {
        Write-Log -message "[-] Source path $src is not available" -color Yellow
        $skip = $true
    }

# Creating destination folder
    if (!($skip)) {
        if (!(Test-Path $dst)) {
            Write-Log "[+] Creating folder $dst" -color Green
            try {
                New-Item -Path $dst -Force -ItemType Directory | Out-Null
            }
            catch {
                Write-Log "[-] Can't create $dst folder, error: $($Error[0])" -color Red
            }
        } else {
            Write-Log "[*] Destination folder already exists"
        }
    } else {
        Write-Log "[-] Skip creating of $dst" -color Yellow
    }
# Copying
    if (!($skip)) {
        Write-Log "[+] Copying $src" -color Green
        Write-Log "    to $dst" -color Green
        try {
            Copy-Item -Path $($src+"\SYSTEM") -Destination $dst -Exclude $exclude -Recurse -Force #-ErrorAction 0
            Copy-Item -Path $($src+"\*.*") -Include $include -Destination $dst -Force #-ErrorAction 0
        }
        catch {
            Write-Log "[-] Can't copy, error: $($Error[0])" -color Red
        }
    } else {
        Write-Log "[-] Skip copy of $src" -color Yellow
    }
# Purging
    Write-Log "[+] Purging $dstStore" -color Green
    try {
        Get-ChildItem –Path $($dstStore) `
            | Where-Object {($_.LastWriteTime -lt (Get-Date).AddDays($backupsAge))} `
            | Remove-Item
        }
    catch {
        Write-Log "[-] Can't purge old backups, error: $($Error[0])" -color Red
    }
}

Write-Log -message "** Script finished normally."
[Console]::OutputEncoding = $encoding
