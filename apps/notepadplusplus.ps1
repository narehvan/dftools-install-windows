# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install Notepad++
function Install-NotepadPlusPlus {
    [CmdletBinding()]
    param()

    $LocalTempDir = $env:TEMP
    Log-Text "installing notepad++..." "INFO"

    # Find the link to the latest version of notepad++
    $webAddress = "https://notepad-plus-plus.org/"
    try {
        $webPage = Invoke-WebRequest -Uri $webAddress -UseBasicParsing
        if ($webPage.StatusCode -ne 200) {
            Log-Text "Unable to access: $webAddress HTTP StatusCode: $($webPage.StatusCode)" "ERROR"
            return $false
        }
    }
    catch {
        Log-Text "Failed to access Notepad++ site: $_" "ERROR"
        return $false
    }

    $partialUrl = ($webPage.Links | Where-Object {$_.outerHTML -like "*Current Version *"})[0].href
    $downloadUrl = Merge-URI-Path -Url $webAddress -Path $partialUrl

    # find the current version available on the download page
    $latestVersion = if ($partialUrl -match 'v([\d.]+)') { $matches[1] } else { $null }
    if (-not $latestVersion) {
        Log-Text "Could not determine latest Notepad++ version" "ERROR"
        return $false
    }

    # Check if Notepad++ is already installed
    $installedVersion = Get-IsApplicationInstalled "Notepad++"
    if ($installedVersion) {
        Log-Text "Notepad++ version $installedVersion found installed" "INFO"
        if ($installedVersion -ge $latestVersion) {
            Log-Text "Notepad++ version installed is same or newer. will not update" "WARN"
            return $true
        }
        else {
            Log-Text "Notepad++ latest version $latestVersion is newer than installed $installedVersion version. Upgrading..." "INFO"
        }
    } 
    else {
        Log-Text "Notepad++ not installed. Will install it" "INFO"
    }
        
    # Find the executable file download link
    try {
        $webPageInstaller = Invoke-WebRequest -Uri $downloadUrl -UseBasicParsing
        if ($webPageInstaller.StatusCode -ne 200) {
            Log-Text "Unable to access download page: $downloadUrl HTTP StatusCode: $($webPageInstaller.StatusCode)" "ERROR"
            return $false
        }
    }
    catch {
        Log-Text "Failed to access download page: $_" "ERROR"
        return $false
    }

    try {

        if (Get-Is64BitWindows) {
            Log-Text "Installing 64-bit version" "INFO"
            $fileDownloadUrl = ($webPageInstaller.Links | Where-Object {$_.href -like "*Installer.x64.exe"})[0].href
            $fileDownloadSigUrl = ($webPageInstaller.Links | Where-Object {$_.href -like "*Installer.x64.exe.sig"})[0].href
        } else {
            Log-Text "Installing 32-bit version" "INFO"
            $fileDownloadUrl = ($webPageInstaller.Links | Where-Object {$_.href -like "*Installer.exe"})[0].href
            $fileDownloadSigUrl = ($webPageInstaller.Links | Where-Object {$_.href -like "*Installer.exe.sig"})[0].href
        }
    }
    catch {
        Log-Text "installer not found!" "ERROR"
    }

    if (-not $fileDownloadUrl -or -not $fileDownloadSigUrl) {
        Log-Text "Could not find download links for installer or signature" "ERROR"
        return $false
    }

    Log-Text $fileDownloadUrl "INFO"
    Log-Text $fileDownloadSigUrl "INFO"

    # Download the files
    $executableFilePath = $null
    $executableFileSigPath = $null
    try {
        $executableFilePath = Download-File $fileDownloadUrl $LocalTempDir
        $executableFileSigPath = Download-File $fileDownloadSigUrl $LocalTempDir

        if (-not $executableFilePath -or -not $executableFileSigPath) {
            Log-Text "Download failed - one or more files missing" "ERROR"
            return $false
        }
        else {
            Log-Text "Notepad++ installer downloaded" "INFO"
            $fileSizeBytes = (Get-Item $executableFilePath).Length 
            $fileSizeFormatted = Get-Filesize-Formatted $fileSizeBytes
            Log-Text "Downloaded notepad++ installer: $fileSizeFormatted" "INFO"
        }

        Log-Text $executableFilePath "INFO"
        Log-Text $executableFileSigPath "INFO"
    }
    catch {
        Log-Text "Download error: $($_.Exception.Message)" "ERROR"
        return $false
    }

    # Install it silently
    Log-Text "Installing Notepad++..." "INFO"
    try {
        $process = Start-Process -FilePath $executableFilePath -Args "/S" -Verb RunAs -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            Log-Text "Installer returned non-zero exit code: $($process.ExitCode)" "ERROR"
            return $false
        }
    }
    catch {
        Log-Text "Installation failed to start: $_" "ERROR"
        return $false
    }

    # check if it was installed successfully
    $installedVersion = Get-IsApplicationInstalled "Notepad++"
    if ($installedVersion -eq $latestVersion) {
        Log-Text "Installation of Notepad++ version $installedVersion successful" "INFO"
    }
    else {
        Log-Text "Installed $installedVersion not matching the latest $latestVersion" "WARN"
        # Still return true since it installed something
    }

    # cleanup the downloaded files
    $cleanupSuccess1 = Remove-Downloaded-File $executableFilePath
    if ($cleanupSuccess1) {
        Log-Text "$executableFilePath Temp file cleaned up successfully" "INFO"
    } else {
        Log-Text "Failed to cleanup $executableFilePath temp file" "WARN"
    }
    
    $cleanupSuccess2 = Remove-Downloaded-File $executableFileSigPath
    if ($cleanupSuccess2) {
        Log-Text "$executableFileSigPath Temp file cleaned up successfully" "INFO"
    } else {
        Log-Text "Failed to cleanup $executableFileSigPath temp file" "WARN"
    }

    return $true
}

#####################################################
# Get the notepad++ installation path from registry
function Get-NotepadPlusPlus-Registry-Path() {
    # Find Notepad++ path from registry
    $nppPath = $null
    $regPaths = @(
        'HKLM:\SOFTWARE\Notepad++',
        'HKLM:\SOFTWARE\WOW6432Node\Notepad++'
    )

    foreach ($regPath in $regPaths) {
        try {
            $nppPath = Get-ItemProperty -Path $regPath -Name '(default)' -ErrorAction SilentlyContinue | 
                Select-Object -ExpandProperty '(default)'
            $nppPath = $nppPath.Trim()
            if ($nppPath -and (Test-Path $nppPath -PathType Container)) {
                return $nppPath
            }
        }
        catch { }
    }

    return $null # not found
}

#####################################################
# Install Notepad++ ComparePlusPlugin
# Homepage: https://github.com/pnedev/comparePlus
function Install-NotepadPlusPlus-ComparePlusPlugin {
    [CmdletBinding()]
    param(
        [string]$DownloadPath = $env:TEMP
    )

    Log-Text "Installing latest ComparePlus plugin..." "INFO"

    # check if Notepad++ is installed. if it is not installed, abort
    $installedVersion = Get-IsApplicationInstalled "Notepad++"
    if ($installedVersion) {
        Log-Text "Notepad++ version $installedVersion found installed" "INFO"
    } 
    else {
        Log-Text "Notepad++ not installed. Cannot continue" "ERROR"
        return $false
    }

    Log-Text "Downloading latest ComparePlus plugin..." "INFO"
    
    # GitHub repo info
    $repoOwner = "pnedev"
    $repoName = "comparePlus"
    
    # Get latest release info
    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
    try {
        $releaseJson = Invoke-RestMethod $apiUrl -UseBasicParsing
    }
    catch {
        Log-Text "Failed to get ComparePlus release info: $_" "ERROR"
        return $false
    }


    if (Get-Is64BitWindows) {
        Log-Text "Installing 64-bit version" "INFO"
        $searchString = "*ComparePlus*_x64*"
    } else {
        Log-Text "Installing 32-bit version" "INFO"
        $searchString = "*ComparePlus*_Win32*"
    }
    
    # Find ZIP asset (usually ComparePlus_vX.Y.Z.zip)
    $zipAsset = $releaseJson.assets | Where-Object { 
        $_.name -match '\.zip$' -and $_.name -like $searchString 
    } | Select-Object -First 1
    
    if (-not $zipAsset) {
        Log-Text "No ZIP asset found in ComparePlus release" "ERROR"
        return $false
    }
    
    $downloadUrl = $zipAsset.browser_download_url
    $fileName = $zipAsset.name
    $zipPath = Join-Path $DownloadPath $fileName
    
    Log-Text "Downloading: $fileName (v$($releaseJson.tag_name))" "INFO"
    
    try {
        # Download ZIP
        Invoke-WebRequest $downloadUrl -OutFile $zipPath
        
        # Find Notepad++ path from registry
        $nppPath = Get-NotepadPlusPlus-Registry-Path
        if (-not $nppPath) {
            Log-Text "Notepad++ not found in registry!" "ERROR"
            return $false
        }
        else {
            Log-Text "Notepad++ path found: $nppPath" "INFO"
        }

        # If it's already a directory, use it directly
        if (Test-Path $nppPath -PathType Container) {
            $nppBaseDir = $nppPath
            Log-Text "Using directory from registry: $nppBaseDir" "INFO"
        } 

        # If it's an EXE file, get parent directory
        elseif (Test-Path $nppPath -PathType Leaf -and $nppPath -like "*notepad++.exe") {
            $nppBaseDir = Split-Path $nppPath -Parent
            Log-Text "Using EXE parent directory: $nppBaseDir" "INFO"
        }
        else {
            Log-Text "Invalid Notepad++ path from registry: $nppPath" "ERROR"
            return $false
        }

        $nppPluginsDir = Join-Path $nppBaseDir "plugins"
        Log-Text "Using Notepad++ plugin directory: $nppPluginsDir" "INFO"

        if (-not (Test-Path $nppPluginsDir)) {
            Log-Text "Notepad++ plugins folder not found!" "ERROR"
            return $false
        }


        $comparePlusPluginDir = Join-Path $nppPluginsDir "ComparePlus"
        
        # Create ComparePlus subfolder
        if (-not (Test-Path $comparePlusPluginDir)) {
            New-Item -Path $comparePlusPluginDir -ItemType Directory -Force | Out-Null
            Log-Text "Created ComparePlus directory: $comparePlusPluginDir" "INFO"
        }        
                
        Expand-Archive $zipPath "$comparePlusPluginDir" -Force
        
        Log-Text "ComparePlus installed successfully to $nppPluginsDir" "INFO"
        Remove-Downloaded-File $zipPath
        
        return $true
    }
    catch {
        Log-Text "ComparePlus download failed: $_" "ERROR"
        return $false
    }
}

#####################################################
# Install Notepad++ XmlToolsPlugin
# Homepage: https://github.com/morbac/xmltools
function Install-NotepadPlusPlus-XmlToolsPlugin {
    [CmdletBinding()]
    param([string]$DownloadPath = $env:TEMP)

    # Check if Notepad++ is installed
    $installedVersion = Get-IsApplicationInstalled "Notepad++"
    if ($installedVersion) {
        Log-Text "Notepad++ version $installedVersion found installed" "INFO"
    } 
    else {
        Log-Text "Notepad++ not installed. Cannot continue" "ERROR"
        return $false
    }

    Log-Text "Downloading latest XMLTools plugin..." "INFO"
    
    # GitHub repo info
    $repoOwner = "morbac"
    $repoName = "xmltools"
    
    # Get latest release info
    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
    try {
        $releaseJson = Invoke-RestMethod $apiUrl -UseBasicParsing
    }
    catch {
        Log-Text "Failed to get XMLTools release info: $_" "ERROR"
        return $false
    }
    

    if (Get-Is64BitWindows) {
        Log-Text "Installing 64-bit version" "INFO"
        $searchString = "*XMLTools*-x64*"
    } else {
        Log-Text "Installing 32-bit version" "INFO"
        $searchString = "*XMLTools*-x86*"
    }

    # Find ZIP asset (XMLTools_x.x.x.x-x64.zip or similar)
    $zipAsset = $releaseJson.assets | Where-Object { 
        $_.name -match '\.zip$' -and $_.name -like $searchString
    } | Select-Object -First 1
    
    if (-not $zipAsset) {
        Log-Text "No suitable ZIP asset found in XMLTools release. Assets available:" "WARN"
        $releaseJson.assets.name | ForEach-Object { Log-Text "  - $_" "DEBUG" }
        return $false
    }
    
    $downloadUrl = $zipAsset.browser_download_url
    $fileName = $zipAsset.name
    $zipPath = Join-Path $DownloadPath $fileName
    
    Log-Text "Downloading: $fileName (v$($releaseJson.tag_name))" "INFO"
    
    try {
        # Download ZIP
        Invoke-WebRequest $downloadUrl -OutFile $zipPath
        
        # Find Notepad++ path from registry
        $nppPath = Get-NotepadPlusPlus-Registry-Path
        if (-not $nppPath) {
            Log-Text "Notepad++ not found in registry!" "ERROR"
            return $false
        }
        else {
            Log-Text "Notepad++ path found: $nppPath" "INFO"
        }

        if (-not $nppPath -or -not (Test-Path $nppPath -PathType Container)) {
            Log-Text "Notepad++ directory not found in registry!" "ERROR"
            return $false
        }

        # If it's already a directory, use it directly
        if (Test-Path $nppPath -PathType Container) {
            $nppBaseDir = $nppPath
            Log-Text "Using directory from registry: $nppBaseDir" "INFO"
        } 

        # If it's an EXE file, get parent directory
        elseif (Test-Path $nppPath -PathType Leaf -and $nppPath -like "*notepad++.exe") {
            $nppBaseDir = Split-Path $nppPath -Parent
            Log-Text "Using EXE parent directory: $nppBaseDir" "INFO"
        }
        else {
            Log-Text "Invalid Notepad++ path from registry: $nppPath" "ERROR"
            return $false
        }

        $nppPluginsDir = Join-Path $nppBaseDir "plugins"
        Log-Text "Using Notepad++ plugin directory: $nppPluginsDir" "INFO"

        if (-not (Test-Path $nppPluginsDir)) {
            Log-Text "Notepad++ plugins folder not found!" "ERROR"
            return $false
        }

        $xmlToolsDir = Join-Path $nppPluginsDir "XMLTools"
        
        # Create XMLTools subfolder
        if (-not (Test-Path $xmlToolsDir)) {
            New-Item -Path $xmlToolsDir -ItemType Directory -Force | Out-Null
            Log-Text "Created XMLTools directory: $xmlToolsDir" "INFO"
        }

        # uncompress ZIP to XMLTools folder
        Expand-Archive $zipPath "$xmlToolsDir" -Force
        Log-Text "XMLTools installed successfully to $xmlToolsDir" "INFO"
        
        # Cleanup
        Remove-Downloaded-File $zipPath
        
        return $true
    }
    catch {
        Log-Text "XMLTools installation failed: $_" "ERROR"
        return $false
    }
}


#####################################################
# Install Notepad++ JsonToolsPlugin
# Homepage: https://github.com/molsonkiko/JsonToolsNppPlugin
function Install-NotepadPlusPlus-JsonToolsPlugin {
    [CmdletBinding()]
    param([string]$DownloadPath = $env:TEMP)

    # Check if Notepad++ is installed
    $installedVersion = Get-IsApplicationInstalled "Notepad++"
    if ($installedVersion) {
        Log-Text "Notepad++ version $installedVersion found installed" "INFO"
    } 
    else {
        Log-Text "Notepad++ not installed. Cannot continue" "ERROR"
        return $false
    }

    Log-Text "Downloading latest JsonTools plugin..." "INFO"
    
    # GitHub repo info
    $repoOwner = "molsonkiko"
    $repoName = "JsonToolsNppPlugin"
    
    # Get latest release info
    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
    try {
        $releaseJson = Invoke-RestMethod $apiUrl -UseBasicParsing
    }
    catch {
        Log-Text "Failed to get JsonTools release info: $_" "ERROR"
        return $false
    }

    if (Get-Is64BitWindows) {
        Log-Text "Installing 64-bit version" "INFO"
        $searchString = "*Release_x64*" 
    } else {
        Log-Text "Installing 32-bit version" "INFO"
        $searchString = "*Release_x86*" 
    }
    
    # Find ZIP asset (Release_x64.zip)
    $zipAsset = $releaseJson.assets | Where-Object { 
        $_.name -match '\.zip$' -and $_.name -like $searchString
    } | Select-Object -First 1
    
    if (-not $zipAsset) {
        Log-Text "No suitable ZIP asset found in JsonTools release. Assets available:" "WARN"
        $releaseJson.assets.name | ForEach-Object { Log-Text "  - $_" "DEBUG" }
        return $false
    }
    
    $downloadUrl = $zipAsset.browser_download_url
    $fileName = $zipAsset.name
    $zipPath = Join-Path $DownloadPath $fileName
    
    Log-Text "Downloading: $fileName (v$($releaseJson.tag_name))" "INFO"
    
    try {
        # Download ZIP
        Invoke-WebRequest $downloadUrl -OutFile $zipPath
        
        # Find Notepad++ path from registry
        $nppPath = Get-NotepadPlusPlus-Registry-Path
        if (-not $nppPath) {
            Log-Text "Notepad++ not found in registry!" "ERROR"
            return $false
        }
        else {
            Log-Text "Notepad++ path found: $nppPath" "INFO"
        }

        # Handle registry path (directory or exe)
        if (Test-Path $nppPath -PathType Container) {
            $nppBaseDir = $nppPath
            Log-Text "Using directory from registry: $nppBaseDir" "INFO"
        } 
        elseif (Test-Path $nppPath -PathType Leaf -and $nppPath -like "*notepad++.exe") {
            $nppBaseDir = Split-Path $nppPath -Parent
            Log-Text "Using EXE parent directory: $nppBaseDir" "INFO"
        }
        else {
            Log-Text "Invalid Notepad++ path from registry: $nppPath" "ERROR"
            return $false
        }

        $nppPluginsDir = Join-Path $nppBaseDir "plugins"
        Log-Text "Using Notepad++ plugin directory: $nppPluginsDir" "INFO"

        if (-not (Test-Path $nppPluginsDir)) {
            Log-Text "Notepad++ plugins folder not found!" "ERROR"
            return $false
        }

        $jsonToolsDir = Join-Path $nppPluginsDir "JsonTools"
        
        # Create JsonTools subfolder
        if (-not (Test-Path $jsonToolsDir)) {
            New-Item -Path $jsonToolsDir -ItemType Directory -Force | Out-Null
            Log-Text "Created JsonTools directory: $jsonToolsDir" "INFO"
        }

        # Uncompress ZIP to JsonTools folder
        Expand-Archive $zipPath $jsonToolsDir -Force
        Log-Text "JsonTools installed successfully to $jsonToolsDir" "INFO"
        
        # Cleanup
        Remove-Downloaded-File $zipPath
        
        return $true
    }
    catch {
        Log-Text "JsonTools installation failed: $_" "ERROR"
        return $false
    }
}

#####################################################
# Install Notepad++ main starter
function Install-Full-NotepadPlusPlus {
    [CmdletBinding()]
    param()

    # Install notepad++
    if (Install-NotepadPlusPlus) {
        Log-Text "Notepad++ installation completed successfully!" "INFO"
        # Continue with plugins

        # Install ComparePlusPlugin for notepad++
        $result = Install-NotepadPlusPlus-ComparePlusPlugin
        if ($result) {
            Log-Text "Install-NotepadPlusPlus-ComparePlusPlugin installed successfully!" "INFO"
        } 
        else {
            Log-Text "Install-NotepadPlusPlus-ComparePlusPlugin installation failed - aborting" "ERROR"
        }

        # Install XMLToolsPlugin for notepad++
        $result = Install-NotepadPlusPlus-XmlToolsPlugin
        if ($result) {
            Log-Text "Install-NotepadPlusPlus-XmlToolsPlugin installed successfully!" "INFO"
        } 
        else {
            Log-Text "Install-NotepadPlusPlus-XmlToolsPlugin installation failed - aborting" "ERROR"
        }


        # Install-NotepadPlusPlus-JsonToolsPlugin
        $result = Install-NotepadPlusPlus-JsonToolsPlugin
        if ($result) {
            Log-Text "IInstall-NotepadPlusPlus-JsonToolsPlugin installed successfully!" "INFO"
        } 
        else {
            Log-Text "Install-NotepadPlusPlus-JsonToolsPlugin installation failed - aborting" "ERROR"
        }

    } 
    else {
        Log-Text "Notepad++ installation failed!" "ERROR"
        return $false
    }

    return $true
}
