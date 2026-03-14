#####################################################
# Check if this is 32bit windows OS or 64bit windows OS
function Get-Is64BitWindows {
    return [Environment]::Is64BitOperatingSystem
}

#####################################################
# Logs the text to Stdio
function Log-Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Severity = 'INFO',

        [Parameter(Mandatory=$false)]
        [string]$LogFile
    )

    $date = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
    $formattedText = "$date [$Severity] $Message"

    # Console output with colours
    switch ($Severity) {
        'INFO'  { Write-Host $formattedText -ForegroundColor Green }
        'WARN'  { Write-Host $formattedText -ForegroundColor Yellow }
        'ERROR' { Write-Host $formattedText -ForegroundColor Red }
        'DEBUG' { Write-Host $formattedText -ForegroundColor Cyan }
    }

    # File output if LogFile specified
    if ($LogFile) {
        $formattedText | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
}

#####################################################
# joins a path to a URL
function Merge-URI-Path {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (
        [uri]::IsWellFormedUriString($Url, [System.UriKind]::Absolute) -and
        ([uri]$Url).Scheme -in @('http', 'https')
    )) {
        throw "Bad URL $Url"
    }

    if ($Url.EndsWith("/"))  { $Url  = $Url.TrimEnd("/") }
    if ($Path.StartsWith("/")) { $Path = $Path.TrimStart("/") }


    $finalUrl = "$Url/$Path"

    if (-not [uri]::IsWellFormedUriString($finalUrl, [System.UriKind]::Absolute)) {
        throw "Bad URL $finalUrl"
    }

    return $finalURL
}

#####################################################
# Downloads a file from a provided URL
function Download-File() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({[uri]::IsWellFormedUriString($_, [UriKind]::Absolute)})]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$DownloadPath
    )

    $downloadFilePath = Join-Path $DownloadPath (Split-Path $Url -Leaf)

    # Ensure directory exists
    $downloadDir = Split-Path $downloadFilePath -Parent
    if (-not (Test-Path $downloadDir)) {
        New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
    }

    try {
        Invoke-WebRequest -Uri $Url -OutFile $downloadFilePath -UseBasicParsing

        # Verify download
        if (-not (Test-Path $downloadFilePath)) {
            throw "Downloaded file not found at $downloadFilePath"
        }

        # Check file size > 0
        if ((Get-Item $downloadFilePath).Length -eq 0) {
            throw "Downloaded file is empty: $downloadFilePath"
        }
    } 
    catch {
        # print the current error in a new line
        throw "Download failed for $Url`nto $_"
    } 
    
    return $downloadFilePath
}

#####################################################
# Delete the temporarily downloaded file
function Remove-Downloaded-File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileNameWithPath
    )

    # File doesn't exist - nothing to do, return true (success)
    if (-not (Test-Path $FileNameWithPath)) {
        return $true
    }

    try {
        Remove-Item $FileNameWithPath -Force -ErrorAction Stop
        
        # Verify deletion
        if (-not (Test-Path $FileNameWithPath)) {
            return $true
        } else {
            return $false
        }
    }
    catch {
        Log-Text "Failed to delete $FileNameWithPath`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}


#####################################################
# If the $ApplicationName is installed, return it's version
function Get-IsApplicationInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ApplicationName
    )
    
    $appList = @()
    
    # Fixed paths - single backslash
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    # Current user apps
    if ($env:USERNAME) {
        $uninstallPaths += 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    
    foreach ($path in $uninstallPaths) {
        try {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -and $_.DisplayName -notmatch '^KB' }
            
            foreach ($app in $apps) {
                $appList += [PSCustomObject]@{
                    Name = $app.DisplayName
                    Version = $app.DisplayVersion
                    Publisher = $app.Publisher
                    InstallDate = $app.InstallDate
                    UninstallString = $app.UninstallString
                }
            }
        }
        catch { }
    }
    
    # Remove duplicates, sort by name
    $appList = $appList | Sort-Object Name -Unique
    
    # FILTER by application name and return ONLY version if found
    $matchingApp = $appList | Where-Object { $_.Name -like "*$ApplicationName*" }
    
    if ($matchingApp) {
        return $matchingApp.Version  # Returns version string (or first match)
    } else {
        return $null  # Not found
    }
}


#####################################################
# Get the filesize formatted
function Get-Filesize-Formatted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        $InputObject  # File path OR bytes
    )
    
    if ($InputObject -is [string] -and (Test-Path $InputObject)) {
        $fileSizeBytes = (Get-Item $InputObject).Length
    } 
    else {
        $fileSizeBytes = [long]$InputObject
    }

    $fileSizeFormatted = if ($fileSizeBytes -gt 1GB) {
        "{0:N2} GB" -f ($fileSizeBytes / 1GB)
    } 
    elseif ($fileSizeBytes -gt 1MB) {
        "{0:N2} MB" -f ($fileSizeBytes / 1MB)
    } 
    elseif ($fileSizeBytes -gt 1KB) {
        "{0:N2} KB" -f ($fileSizeBytes / 1KB)
    } 
    else {
        "$fileSizeBytes bytes"
    }

    return $fileSizeFormatted
}

#####################################################
# check if the powershell shell is being used with administrative priviledges
function Test-IsElevated {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#####################################################
# Add a directory to user's PATH variable
function Add-ToPath {
    param(
        [string[]]$Paths,
        [string]$Target = "User"
    )
    
    foreach ($path in $Paths) {
        if (-not $path) { continue }
        
        # Skip if already exists (case-insensitive)
        $currentPath = [Environment]::GetEnvironmentVariable("Path", $Target)
        if ($currentPath -notlike "*$path*") {
            $newPath = "$currentPath;$path"
            [Environment]::SetEnvironmentVariable("Path", $newPath, $Target)
            Log-Text "Added to PATH: $path" "INFO"
        } 
        else {
            Log-Text "$path already in PATH" "INFO"
        }
    }
}


#####################################################
# Get a list of all installed applications
# e.g., Get-InstalledApplications | Where-Object Name -like "*Notepad*"
function Get-InstalledApplications {
    [CmdletBinding()]
    param([switch]$Detailed)
    
    $appList = @()
    
    # 64-bit apps + 32-bit apps (WOW6432Node)
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    # Current user apps
    if ($env:USERNAME) {
        $uninstallPaths += 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    
    foreach ($path in $uninstallPaths) {
        try {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -and $_.DisplayName -notmatch '^KB' }
            
            foreach ($app in $apps) {
                $appList += [PSCustomObject]@{
                    Name = $app.DisplayName
                    Version = $app.DisplayVersion
                    Publisher = $app.Publisher
                    InstallDate = $app.InstallDate
                    UninstallString = $app.UninstallString
                }
            }
        }
        catch { }
    }
    
    # Remove duplicates, sort by name
    $appList = $appList | Sort-Object Name -Unique

    if ($Detailed) { 
        return $appList 
    }
    else { 
        return $appList | Select-Object Name, Publisher, InstallDate, Version 
    }
}


