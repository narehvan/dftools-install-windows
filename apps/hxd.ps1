# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install HxD
# https://mh-nexus.de/downloads/HxDSetup.zip
function Install-HxD {
    [CmdletBinding()]
    param()

    $installedAppNameSearchString = "*HxD Hex Editor*"
    $webAddress = "https://mh-nexus.de/downloads/HxDSetup.zip"
    $LocalTempDir = $env:TEMP
    $appName = "HxD"

    Log-Text "installing $appName..." "INFO"

    # Check if app is already installed
    $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
    if ($installedVersion) {
        Log-Text "$appName version $installedVersion found installed. Will not install again. aborting" "WARN"
        return $true
    } 
    else {
        Log-Text "$appName not installed. Will install it" "INFO"
    }

    # Find the link to the latest version
    Log-Text "Downloading $appName from: $webAddress" "INFO"

    # Find the installation file
    try {

        $response = Invoke-WebRequest -Uri $webAddress -MaximumRedirection 5 -Method Head  -UseBasicParsing

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


        # Build full path and download using that filename
        $destination = Join-Path $LocalTempDir $filename
        Log-Text "Installer download location: $destination" "INFO"
    }
    catch {
        Log-Text "Failed to prepare the download for $appName $_" "ERROR"
        return $false
    }

    # Downlad the file
    try {
        Invoke-WebRequest -Uri $webAddress -OutFile $destination -UseBasicParsing

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

            if ($response.Headers['Content-Length'] -and $fileSizeBytes -lt [long]$response.Headers['Content-Length']) {
                Log-Text "Downloaded size smaller than expected" "WARN" 
            }
        }
    }
    catch {
        Log-Text "Failed to download for $appName $_" "ERROR"
        return $false
    }

    # Extract downloaded zip file
    try {
        $extractPath = Join-Path $LocalTempDir "HxD"
        Expand-Archive -Path $destination -DestinationPath $extractPath -Force

        # Find HxDSetup.exe
        $setupExe = Get-ChildItem -Path $extractPath -Filter "HxDSetup.exe" -Recurse -File | Select-Object -First 1 -ExpandProperty FullName
        Log-Text "Found setup.exe: $(Get-Filesize-Formatted (Get-Item $setupExe).Length)" "INFO"

        if (-not (Test-Path $setupExe)) {
            Log-Text "HxDSetup.exe not found in ZIP" "ERROR"
            return $false
        }
    }
    catch {
        Log-Text "Extracting zip file failed. Abort!" "ERROR"
        return $false
    }

    # Silent install
    try {
        $args = "/VERYSILENT", "/NORESTART", "/SP-"
        Start-Process -FilePath $setupExe -ArgumentList $args -Wait -NoNewWindow
        
        # Verify
        $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
        if ($installedVersion) {
            Log-Text "$appName $installedVersion installed successfully" "INFO"
        } 
        else {
            Log-Text "$appName installation completed but not detected in registry" "WARN"
        }
    }
    catch {
        Log-Text "Installation of $appName failed: $_" "ERROR"
        return $false
    }
    finally {
        # Cleanup ZIP
        $cleanupSuccess = Remove-Downloaded-File $destination
        if ($cleanupSuccess) { Log-Text "$destination cleaned up" "INFO" }
    
        # Cleanup extract folder
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
            Log-Text "$extractPath cleaned up" "INFO"
        }
    }
    return $true
 }
