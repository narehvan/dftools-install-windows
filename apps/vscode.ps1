# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install VSCode
function Install-VSCode {
    [CmdletBinding()]
    param()

    $installedAppNameSearchString = "*Visual Studio Code*"
    $webAddress = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
    $LocalTempDir = $env:TEMP

    Log-Text "installing VScode..." "INFO"

    # Find the link to the latest version
    Log-Text "Downloading VScode from: $webAddress" "INFO"

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

        # get the version from the filename
        if (-not $filename) {
            $latestVersion = "0"
        }
        else {
            $latestVersion = [regex]::Match($filename, '\d+\.\d+\.\d+').Value
        }

        Log-Text "Identified latest version number from filename: $latestVersion" "INFO"

        # Build full path and download using that filename
        $destination = Join-Path $LocalTempDir $filename
        Log-Text "Installer download location: $destination" "INFO"

        # Check if VSCode is already installed
        $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
        if ($installedVersion) {
            Log-Text "VScode version $installedVersion found installed" "INFO"
            if ($latestVersion -ne "0")  {
                if ([version]$installedVersion -ge [version]$latestVersion) {
                    Log-Text "VScode version installed is same or newer. will not update" "WARN"
                    return $true
                }
                else {
                    Log-Text "VSCode latest version $latestVersion is newer than installed $installedVersion version. Upgrading..." "INFO"
                }
            } 
            else {
                Log-Text "Unable to detect the latest version number. Will attempt to upgrade..." "WARN"
            }
        } 
        else {
            Log-Text "VSCode not installed. Will install it" "INFO"
        }

        # Downlad the file
        Invoke-WebRequest -Uri $webAddress -OutFile $destination

        # Check if download was successful
        if (-not (Test-Path $destination)) {
            Log-Text "Failed to download VSCode installer" "ERROR"
            return $false
        }
        else {
            Log-Text "VSCode installer downloaded" "INFO"
            $fileSizeBytes = (Get-Item $destination).Length 
            $fileSizeFormatted = Get-Filesize-Formatted $fileSizeBytes
            Log-Text "Downloaded VSCode installer: $fileSizeFormatted" "INFO"

            if ($response.Headers['Content-Length'] -and $fileSizeBytes -lt [long]$response.Headers['Content-Length']) {
                Log-Text "Downloaded size smaller than expected" "WARN" 
            }
        }
    }
    catch {
        Log-Text "Failed to access VSCode site: $_" "ERROR"
        return $false
    }

    try {
        # Install it
        Log-Text "Installing VSCode silently ..."

        # /VERYSILENT = no UI
        # /NORESTART  = don't reboot
        # /MERGETASKS=!runcode = prevent VS Code from auto-launching after install
        $args = "/VERYSILENT /NORESTART /MERGETASKS=!runcode"

        Start-Process -FilePath $destination -ArgumentList $args -Wait -NoNewWindow

        # check if it was installed successfully
        $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
        if ($installedVersion) {
            Log-Text "VScode version $installedVersion found installed" "INFO"
            if ($latestVersion -ne "0") {
                if ([version]$installedVersion -ge [version]$latestVersion) {
                    Log-Text "Installation of VSCode version $installedVersion successful" "INFO"
                }
                else {
                    Log-Text "Installed $installedVersion not matching the latest $latestVersion" "WARN"
                    # Still return true since it installed something
                }
            }
            else {
                Log-Text "Found version $installedVersion installed, but couldn't figure out the latest version number to compare" "WARN"
            }
        }
        else {
            Log-Text "Couldn't find an installed VSCode. It may have been installed successfully" "WARN"
        }
    }
    catch {
        Log-Text "Installation failed: $_" "ERROR"
        return $false
    }

    # cleanup the downloaded files
    $cleanupSuccess = Remove-Downloaded-File $destination
    if ($cleanupSuccess) {
        Log-Text "$destination Temp file cleaned up successfully" "INFO"
    } 
    else {
        Log-Text "Failed to cleanup $destination temp file" "WARN"
    }

    return $true
}


#####################################################
# Test of a VSCode extension is installed or not
function Test-VSCodeExtensionInstalled {
    [CmdletBinding()]
    param([string]$ExtensionId, [string]$VSCCmdPath)
    
    $result = & $VSCCmdPath --list-extensions --show-versions 2>$null
    return $result -match [regex]::Escape($ExtensionId)
}


#####################################################
# Install VSCode extensions
function Install-VScode-Extensions {
    [CmdletBinding()]
    param()

    $installedAppNameSearchString = "*Visual Studio Code*"
    $installResult = 0
    $extensions = @(
        # === CORE (Always) ===
        "ms-vscode.PowerShell",           # PowerShell
        "ms-python.python",               # Python (includes debugpy/pylance/envs)
        "ms-dotnettools.csharp",          # C#
        "ms-dotnettools.csdevkit",        # C# Dev Kit
    
        # === UI/UX ===
        "vscode-icons-team.vscode-icons", # File icons
        "esbenp.prettier-vscode",         # Auto-format ALL files
        "eamodio.gitlens",                # Git supercharged

        # === Files/Configs ===
        "redhat.vscode-yaml",             # YAML
        "infosec-intern.yara"             # YARA
 
        # === Modern Dev ===
        "ms-vscode-remote.remote-containers", # Dev containers
        "ms-azuretools.vscode-docker",        # Docker

        # === GitHub ===
        "github.vscode-pull-request-github" # PRs 
      )

    # Check if VSCode is already installed
    $installedVersion = Get-IsApplicationInstalled $installedAppNameSearchString
    if (-not $installedVersion) {
        Log-Text "VScode not installed. Can't install extensions. install VSCode first" "ERROR"
        return $false
    }
    else {
        Log-Text "Detected VScode version $installedVersion installed. Installing extensions" "INFO"
    }

    $VSCCmdPath = @(
        "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\bin\code.cmd",
        "C:\Program Files\Microsoft VS Code\bin\code.cmd",
        "code"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $VSCCmdPath) {
        Log-Text "VS Code command not found on any expected path" "ERROR"
        return $false
    }

    try {
        
        $counter=1
        foreach ($ext in $extensions) {
            Log-Text "Installing [$counter / $($extensions.Count)] $ext..." "INFO"
            $counter +=1
    
            & $VSCCmdPath --install-extension $ext --force
    
            if ($LASTEXITCODE -eq 0 -and (Test-VSCodeExtensionInstalled -ExtensionId $ext -VSCCmdPath $VSCCmdPath)) {
                Log-Text "$ext installed OK" "INFO"
            } 
            else {
                Log-Text "$ext failed to install properly (exit code: $LASTEXITCODE)" "ERROR"
                $installResult += 1
            }
        }
    }
    catch {
        Log-Text "Installation of extensions aborted: $_" "ERROR"
        return $false
    }


    $success = ($installResult -eq 0)
    if ($success) {
        Log-Text "All $($extensions.Count) extensions installed successfully" "INFO"
    } else {
        Log-Text "$installResult / $($extensions.Count) extensions FAILED" "ERROR"
    }

    return $success
}

#####################################################
# Install VSCode main starter
function Install-Full-VSCode {
    [CmdletBinding()]
    param()

    if (Install-VSCode) {
        Log-Text "VScode installation completed successfully!" "INFO"

        # continue with the extensions
        if (Install-VScode-Extensions) {
            Log-Text "VScode installation completed successfully!" "INFO"
        } 
        else {
            Log-Text "Some or all VScode extension installation failed!" "ERROR"
            return $false
        }
    } 
    else {
        Log-Text "VScode installation failed!" "ERROR"
        return $false
    }

    return $true
}

