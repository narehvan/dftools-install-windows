# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install Wireshark
function Install-Wireshark {
    [CmdletBinding()]
    param()

    $installedAppNameSearchString = "*wireshark*"
    $LocalTempDir = $env:TEMP
    $appName = "wireshark"

    $productURL = "https://www.wireshark.org"
    $downloadUrl = "$productURL/#download"

    Log-Text "Installing $appName..." "INFO"

    # Determine correct download URL based on architecture
    try {
        if (Get-Is64BitWindows) {
            Log-Text "Installing 64-bit version" "INFO"
        } 
        else {
            Log-Text "You are running a 32-bit version. You need to install $appName manually" "ERROR"
            return $false
        }
    }
    catch {
        Log-Text "Failed to determine $appName download URL: $_" "ERROR"
        return $false
    }

    # Check if app is already installed
    $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
    if ($installedVersion) {
        Log-Text "$appName version $installedVersion found installed. can't upgrade. should be done manually" "ERROR"
        return $false
    } 
    else {
        Log-Text "$appName not installed. Will install it" "INFO"
    }


    # Check if the web address is accessible
    try {
        $webPage = Invoke-WebRequest -Uri $downloadUrl -UseBasicParsing
        if ($webPage.StatusCode -ne 200) {
            Log-Text "Unable to access: $downloadUrl HTTP StatusCode: $($webPage.StatusCode)" "ERROR"
            return $false
        }
    }
    catch {
        Log-Text "Failed to access $appName site: $_" "ERROR"
        return $false
    }

    # Find the link to the latest version of the product
    try {
        $versionSearchString = '*Windows x64 Installer*'
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

    # Discover the download filename
    try {
        $response = Invoke-WebRequest -Uri $fileDownloadUrl -MaximumRedirection 5 -Method Head  -UseBasicParsing

        if ($response.Headers['Content-Length']) {
            $expectedSize = [long]$response.Headers['Content-Length']
            Log-Text "Expected size: $(Get-Filesize-Formatted $expectedSize)" "INFO"
        }
        
        # Try to get filename from Content-Disposition
        $filename = $null
        $contentDisposition = $response.Headers['Content-Disposition']
        if ($contentDisposition -and $contentDisposition -match 'filename="?([^";]+)"?') {
            $filename = $matches[1]
        }

        # Fallback: use last segment of the final URL
        if (-not $filename) {
            $finalUri = $response.BaseResponse.ResponseUri.AbsoluteUri
            $filename = [System.IO.Path]::GetFileName($finalUri)
        }

        Log-Text "Filename to download: $filename" "INFO"

    }
    catch {
        Log-Text "Unable to discover the download filename: $_" "ERROR"
        return $false
    }

    # Get the version number from the download filename
    try {
        if ($filename) {
            $versionMatch = [regex]::Match($filename, 'Wireshark-(\d+(?:\.\d+){2})')
            if ($versionMatch.Success) {
                $latestVersion = $versionMatch.Groups[1].Value
                Log-Text "Version found in filename: $latestVersion" "INFO"
            } 
            else {
                Log-Text "Could not extract version from filename: $filename" "WARN"
                $latestVersion = "Unknown"
            }
        }
    }
    catch {
        Log-Text "Could not extract version from filename: $filename" "WARN"
        $latestVersion = "Unknown"
    }

    # Download the installer
    try {
        Log-Text "Downloading $fileDownloadUrl..." "INFO"
        $installerFile = Join-Path $LocalTempDir $filename
        Log-Text "Installer download location: $installerFile" "INFO"
        
        Invoke-WebRequest -Uri $fileDownloadUrl -OutFile $installerFile -UseBasicParsing

        if (-not (Test-Path $installerFile)) {
            Log-Text "Failed to download $appName installer" "ERROR"
            return $false
        }
        else {
            Log-Text "$appName installer downloaded" "INFO"
            $fileSizeBytes = (Get-Item $installerFile).Length 
            $fileSizeFormatted = Get-Filesize-Formatted $fileSizeBytes
            Log-Text "Downloaded $appName installer: $fileSizeFormatted" "INFO"
        }
    }
    catch {
        Log-Text "Failed to download $appName $_" "ERROR"
        return $false
    }

    # Silent install
    try {
        Log-Text "Starting installation of $appName" "INFO"

        # silent install parameters
        $args = @(
            "/S" 
            "/desktopicon=yes"      
            "/EXTRACOMPONENTS=androiddump,ciscodump,randpktdump,sshdump,udpdump"     
        )

        # NOTE: /S runs the installer or uninstaller silently with default values. The silent installer will not install Npcap
    
        Start-Process -FilePath $installerFile -ArgumentList $args -Wait -NoNewWindow

        Log-Text "Starting installation of $appName" "INFO"

        # Verify installation
        $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
        if ($installedVersion) {
            Log-Text "$appName $installedVersion installed successfully" "INFO"
        } 
        else {
            Log-Text "$appName installation completed but not detected" "WARN"
        }
    
    }
    catch {
        Log-Text "Installation of $appName failed: $_" "ERROR"
        return $false
    }
    finally {
        # Cleanup
        if (Test-Path $installerFile) {
            $cleanupSuccess = Remove-Downloaded-File $installerFile
            if ($cleanupSuccess) {
                Log-Text "$installerFile Temp file cleaned up successfully" "INFO"
            } 
            else {
                Log-Text "Failed to cleanup $installerFile file" "WARN"
            } 
        }
    }

    Log-Text "npcap free version does not support silent install. If you wish to capture traffic, install it manually from https://npcap.com/" "WARN"
    return $true
}