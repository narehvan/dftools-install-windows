# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install Autopsy
function Install-Autopsy {
    [CmdletBinding()]
    param()

    $installedAppNameSearchString = "*autopsy*"
    $LocalTempDir = $env:TEMP
    $appName = "autopsy"

    Log-Text "Installing $appName..." "INFO"

    # Determine correct download URL based on architecture
    try {
        if (Get-Is64BitWindows) {
            Log-Text "Installing 64-bit version" "INFO"
            $downloadUrl = "https://www.autopsy.com/download/"
        } 
        else {
            Log-Text "You are running a 32-bit version. You need to install $appName manually" "ERROR"
            return $false
        }
        Log-Text "Download URL: $downloadUrl" "INFO"
    }
    catch {
        Log-Text "Failed to determine $appName download URL: $_" "ERROR"
        return $false
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

    # Find the link to the latest version
    try {
        Log-Text "Installing 64-bit version" "INFO"
        $versionSearchString = '*Download 64-bit*'
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
            $versionMatch = [regex]::Match($filename, 'autopsy-(\d+(?:\.\d+){2})')
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

    # Check if app is already installed
    $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
    if ($installedVersion) {
        Log-Text "$appName version $installedVersion found installed" "INFO"
        if ($installedVersion -ge $latestVersion) {
            Log-Text "$appName version installed is same or newer. will not update" "WARN"
            return $true
        }
        else {
            Log-Text "$appName latest version $latestVersion is newer than installed $installedVersion version. Upgrading..." "INFO"
        }
    } 
    else {
        Log-Text "$appName not installed. Will install it" "INFO"
    }

    # Download the installer
    try {
        Log-Text "Downloading $filename..." "INFO"
        $destination = Join-Path $LocalTempDir $filename
        Log-Text "Installer download location: $destination" "INFO"
        
        Invoke-WebRequest -Uri $fileDownloadUrl -OutFile $destination -UseBasicParsing

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
        Log-Text "Failed to download $appName $_" "ERROR"
        return $false
    }


    # Silent MSI install Autopsy
    try {
        Log-Text "Starting installation of $appName" "INFO"
    
        # MSI silent install parameters
        $args = @(
            "/i"           # Install
            "`"$destination`""  # MSI file
            "/qn"          # Quiet (no UI)
            "/norestart"   # No reboot
            "REBOOT=ReallySuppress"  # Suppress any reboot prompts
        )
    
        Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -NoNewWindow
    
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
        if (Test-Path $destination) {
            $cleanupSuccess = Remove-Downloaded-File $destination
            if ($cleanupSuccess) {
                Log-Text "$destination Temp file cleaned up successfully" "INFO"
            } 
            else {
                Log-Text "Failed to cleanup $destination file" "WARN"
            } 
        }
    }

    return $true
}