# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install ZimmermanTools
function Install-ZimmermanTools {
    [CmdletBinding()]
    param()

    $LocalTempDir = $env:TEMP
    $appName = "zimmermanTools"
    $downloadUrl = "https://download.ericzimmermanstools.com/Get-ZimmermanTools.zip"

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

    # Discover the download filename
    try {
        $response = Invoke-WebRequest -Uri $downloadUrl -MaximumRedirection 5 -Method Head  -UseBasicParsing

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

    # Download the installer
    try {
        Log-Text "Downloading $filename..." "INFO"
        $downloadDestinationFile = Join-Path $LocalTempDir $filename
        Log-Text "Installer download location: $downloadDestinationFile" "INFO"
        
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadDestinationFile -UseBasicParsing

        if (-not (Test-Path $downloadDestinationFile)) {
            Log-Text "Failed to download $appName installer" "ERROR"
            return $false
        }
        else {
            Log-Text "$appName installer downloaded" "INFO"
            $fileSizeBytes = (Get-Item $downloadDestinationFile).Length 
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

        $parentDir = "C:\forensics"
        $installDir = "$parentDir\zimmermanTools"
        if (Test-Path -Path $installDir) {
            Log-Text "Directory exists: $installDir. will not install. aborting..."
            Remove-Downloaded-File $downloadDestinationFile
            return $true
        } 
        else {
            Log-Text "Directory does not exists: $installDir. extracting the downloaded file there"
        }

        Log-Text "Downloaded file $downloadDestinationFile" "INFO"
        Log-Text "Parent directory $parentDir" "INFO"
        Log-Text "Install directory $installDir" "INFO"

        # extract the downloaded file to the install direcrtoy. Then run it from there
        Expand-Archive -Path $downloadDestinationFile -DestinationPath $installDir -Force

        # Find and run the main PowerShell script
        $ps1Files = Get-ChildItem -Path $installDir -Recurse -Filter "*.ps1"

        $mainScript = "$installDir\$ps1Files"
        Log-Text "Extracted File $mainScript" "INFO"

        if (-not (Test-Path $mainScript)) {
            Log-Text "Extraction failed" "ERROR"
            Remove-Downloaded-File $downloadDestinationFile
            return $false
        }
        else {
            Log-Text "Extraction successful" "INFO"
            Remove-Downloaded-File $downloadDestinationFile
        }
    }
    catch {
        Log-Text "Extracting zip file failed. Abort!" "ERROR"
        Remove-Downloaded-File $downloadDestinationFile
        return $false
    }
    
    if ($mainScript) {
        Log-Text "Running main script: $($mainScript.FullName)" "INFO"
        & "$mainScript" -Dest $installDir
    } 
    else {
        Log-Text "No main script found. Extracted to: $installDir" "INFO"
        Log-Text "Run manually: cd '$installDir'; .\*.ps1" "INFO"
        return $false
    }

    # Add to the PATH
    try {
        $level1 = Get-ChildItem $installDir  -Directory

        foreach ($parent in $level1) {
            Add-ToPath -Paths $parent -Target "User"
            $children = Get-ChildItem $parent.FullName -Directory

            foreach ($child in $children) {
                Add-ToPath -Paths $child.FullName -Target "User"
            }
        }
    }
    catch {
        Log-Text "Failed to add to PATH" "ERROR"
        return $false
    }


    Log-Text "Check if all components were installed" "INFO"

    return $true
}


