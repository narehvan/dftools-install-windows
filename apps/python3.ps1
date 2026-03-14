# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install Python3
function Install-Python3 {
    [CmdletBinding()]
    param()

    $installedAppNameSearchString = "py"
    $LocalTempDir = $env:TEMP
    $appName = "python3"
    $pythonURL = "https://www.python.org"
    $downloadUrl = "$pythonURL/downloads/windows/"

    Log-Text "Installing $appName..." "INFO"


    # Check if app is already installed
    if (Get-Command $installedAppNameSearchString -ErrorAction SilentlyContinue) {
        Log-Text "$installedAppNameSearchString version $(& $installedAppNameSearchString --version) found installed. Will not continue" "WARN"
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


    # Find the link to the latest version of the Python install manager
    try {
        Log-Text "Installing Python install manager" "INFO"
        $versionSearchString = '*Latest Python install manager*'
        $link = $webPage.Links |
            Where-Object { $_.outerHTML -like $versionSearchString } |
            Select-Object -First 1
        $fileDownloadUrl = $link.href

        $fileDownloadUrl = "$pythonURL$fileDownloadUrl"

        Log-Text $fileDownloadUrl "INFO"

        $webPage = Invoke-WebRequest -Uri $fileDownloadUrl -UseBasicParsing
        $versionSearchString = '*Installer (MSIX)*'
            $link = $webPage.Links |
            Where-Object { $_.outerHTML -like $versionSearchString } |
            Select-Object -First 1
        $fileDownloadUrlMSIX = $link.href

        Log-Text $fileDownloadUrlMSIX "INFO"
    }
    catch {
        Log-Text "installer not found!" "ERROR"
        return $false
    }

    # Discover the download filename
    try {
        $response = Invoke-WebRequest -Uri $fileDownloadUrlMSIX -MaximumRedirection 5 -Method Head  -UseBasicParsing

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

    # Download the installer
    try {
        Log-Text "Downloading $fileDownloadUrlMSIX..." "INFO"
        $pythonInstallerFile = Join-Path $LocalTempDir $filename
        Log-Text "Installer download location: $pythonInstallerFile" "INFO"
        
        Invoke-WebRequest -Uri $fileDownloadUrlMSIX -OutFile $pythonInstallerFile -UseBasicParsing

        if (-not (Test-Path $pythonInstallerFile)) {
            Log-Text "Failed to download $appName installer" "ERROR"
            return $false
        }
        else {
            Log-Text "$appName installer downloaded" "INFO"
            $fileSizeBytes = (Get-Item $pythonInstallerFile).Length 
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
        $deps = Get-AppxPackageManifest "$pythonInstallerFile" | 
            Select-Object -ExpandProperty Package | 
            Select-Object -ExpandProperty Dependencies

        # Convert object → formatted string for logging
        $depsString = if ($deps) { 
            $deps | Format-List | Out-String 
        } 
        else { 
            "No dependencies found" 
        }

        Log-Text $depsString "INFO"
      
        Add-AppxPackage -Path "$pythonInstallerFile"
    
    }
    catch {
        Log-Text "Installation of $appName failed: $_" "ERROR"
        return $false
    }
    finally {
        # Cleanup
        if (Test-Path $pythonInstallerFile) {
            $cleanupSuccess = Remove-Downloaded-File $pythonInstallerFile
            if ($cleanupSuccess) {
                Log-Text "$pythonInstallerFile Temp file cleaned up successfully" "INFO"
            } 
            else {
                Log-Text "Failed to cleanup $pythonInstallerFile file" "WARN"
            } 
        }
    }

    return $true
}