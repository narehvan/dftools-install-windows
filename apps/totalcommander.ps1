# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install Total Commander
function Install-TotalCommander {
    [CmdletBinding()]
    param()


    $installedAppNameSearchString = "*Total Commander*"
    $webAddress = "https://www.ghisler.com/download.htm"
    $LocalTempDir = $env:TEMP
    $appName = "Total Commander"

    Log-Text "installing $appName..." "INFO"

    Log-Text "Downloading $appName from: $webAddress" "INFO"

    # Check if the web address is accessible. if yes, download the page
    try {
        $webPage = Invoke-WebRequest -Uri $webAddress -UseBasicParsing
        if ($webPage.StatusCode -ne 200) {
            Log-Text "Unable to access: $webAddress HTTP StatusCode: $($webPage.StatusCode)" "ERROR"
            return $false
        }
    }
    catch {
        Log-Text "Failed to access $appName site: $_" "ERROR"
        return $false
    }

    # Find the link to the latest version
    # extract the link to download based on windows 32bit, or 64bit. Download 32bit if it's 32bit windows
    try {
        if (Get-Is64BitWindows) {
            Log-Text "Installing 64-bit version" "INFO"
            $versionSearchString = '*64-bit version only*'
        } 
        else {
            Log-Text "Installing 32-bit version" "INFO"
            $versionSearchString = '*32-bit version only*'
        }
        $link = $webPage.Links |
            Where-Object { $_.outerHTML -like $versionSearchString } |
            Select-Object -First 1
        $fileDownloadUrl = $link.href
        Log-Text $fileDownloadUrl "INFO"
    }
    catch {
        Log-Text "installer not found!" "ERROR"
        return $false
    }


    # Extract only the file name from that URL
    $filename = Split-Path -Path $fileDownloadUrl -Leaf

    # Extract the 4-digit number (1156)
    $versionNumber = [regex]::Match($filename, 'tcmd(\d{4})').Groups[1].Value  # "1156"
    $latestVersion = '{0}.{1}' -f $versionNumber.Substring(0,2), $versionNumber.Substring(2)

    if (-not $versionNumber) {
        Log-Text "Could not extract version from filename: $filename" "ERROR"
        return $false
    }

    Log-Text "Version found on the website is $latestVersion" "INFO"

    # Check if app is already installed
    $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
    if ($installedVersion) {
        if ($installedVersion -ge $latestVersion) {
            Log-Text "$appName version $installedVersion installed is same or newer. will not update" "INFO"
            return $true
        }
        else {
            Log-Text "$appName latest version $latestVersion is newer than installed $installedVersion version. Upgrading..." "INFO"
        }
    } 
    else {
        Log-Text "$appName not installed. Will install it" "INFO"
    }


    # Downlad the file
    try {
        Log-Text "Downloding $filename" "INFO"
        

        # Build full path and download using that filename
        $destination = Join-Path $LocalTempDir $filename
        Log-Text "Installer download location: $destination" "INFO"
        
        Invoke-WebRequest -Uri $fileDownloadUrl -OutFile $destination -UseBasicParsing

        # Check if download was successful
        if (-not (Test-Path $destination)) {
            Log-Text "Failed to download $appName installer" "ERROR"
            return $false
        }
        else {
            Log-Text "$appName installer downloaded" "INFO"
            $fileSizeBytes = (Get-Item $destination).Length 
            $fileSizeFormatted = Get-Filesize-Formatted $fileSizeBytes
            Log-Text "Downloaded $appName installer: $fileSizeFormatted" "INFO"
        }
    }
    catch {
        Log-Text "Failed to download for $appName $_" "ERROR"
        return $false
    }


    # Silent install with Git defaults
    try {
        Log-Text "Starting the installation of $appName" "INFO"
        $args = "/AHMGDU" 
        # A - Auto install: Runs automated installation without prompts.
        # H - Hidden: No UI elements shown on screen (fully silent).
        # M - Minimal: Minimal setup (skips optional components).
        # G - Generate desktop icon: Creates shortcut on desktop.
        # D - Use default settings: Applies standard configuration paths/registry.
        # U - Update mode: Allows overwriting existing install (handles upgrades).

        Start-Process -FilePath $destination -ArgumentList $args -Wait -NoNewWindow
        
        # Verify
        $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
        if ($installedVersion) {
            Log-Text "$appName $installedVersion installed successfully" "INFO"
        } else {
            Log-Text "$appName installation completed but not detected" "WARN"
        }
    }
    catch {
        Log-Text "Installation of $appName failed: $_" "ERROR"
        return $false
    }
    finally {
        # Cleanup
        if (Test-Path $destination) {
            $cleanupSuccess = Remove-Downloaded-File $destination
            if ($cleanupSuccess) {
                Log-Text "$destination Temp file cleaned up successfully" "INFO"
            } else {
                Log-Text "Failed to cleanup $destination file" "WARN"
            } 
        }
    }

    return $true
}