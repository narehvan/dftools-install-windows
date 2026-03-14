# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install Sleuthkit
function Install-Sleuthkit {
    [CmdletBinding()]
    param()

    $LocalTempDir = $env:TEMP
    $appName = "sleuthkit"
    $downloadUrl = "https://www.sleuthkit.org/sleuthkit/download.php"

    Log-Text "Installing $appName..." "INFO"

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
        $versionSearchString = '*Windows Binaries*'
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
        Log-Text "Installation failed: $_" "ERROR"
        return $false
    }

    # Get the version number from the download filename
    try {
        if ($filename) {
            $versionMatch = [regex]::Match($filename, 'sleuthkit-(\d+(?:\.\d+){2})')
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

    # Extract downloaded zip file
    try {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($filename)

        $parentDir = "C:\forensics\sleuthkit\"
        $installDir = "$parentDir$baseName"
        if (Test-Path -Path $installDir) {
            Log-Text "Directory exists: $installDir. will not install. aborting..."
            Remove-Downloaded-File $destination
            return $true
        } 
        else {
            Log-Text "Directory does not exists: $installDir. extracting the downloaded file there"
        }

        Expand-Archive -Path $destination -DestinationPath $parentDir -Force

        if (-not (Test-Path $installDir)) {
            Log-Text "Extraction failed" "ERROR"
            Remove-Downloaded-File $destination
            return $false
        }
        else {
            Log-Text "Extraction successful" "INFO"
            Remove-Downloaded-File $destination
        }
    }
    catch {
        Log-Text "Extracting zip file failed. Abort!" "ERROR"
        Remove-Downloaded-File $destination
        return $false
    }

    # Add to the PATH
    try {
        $paths = @(
            "$installDir\lib",
            "$installDir\bin"
        )
        Add-ToPath -Paths $paths -Target "User"
    }
    catch {
        Log-Text "Failed to add to PATH" "ERROR"
        return $false
    }

    return $true
}