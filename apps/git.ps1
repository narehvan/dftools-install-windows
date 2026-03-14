# Get directory of THIS script
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$rootDir = Split-Path $scriptDir -Parent  # Go up to auto-install/

# Load shared utilities
. "$rootDir\utility_functions.ps1"

#####################################################
# Install Git
function Install-Git {
    [CmdletBinding()]
    param()

    $installedAppNameSearchString = "*git*"
    $webAddress = "https://git-scm.com/install/windows"
    $LocalTempDir = $env:TEMP
    $appName = "Git"

    Log-Text "installing $appName..." "INFO"

    # Find the link to the latest version
    Log-Text "Downloading $appName from: $webAddress" "INFO"
   

    try {
        $webPage = Invoke-WebRequest -Uri $webAddress -UseBasicParsing
        if ($webPage.StatusCode -ne 200) {
            Log-Text "Unable to access: $webAddress HTTP StatusCode: $($webPage.StatusCode)" "ERROR"
            return $false
        }
    }
    catch {
        Log-Text "Failed to access appName++ site: $_" "ERROR"
        return $false
    }

    try {
        # Try ParsedHtml first (PS5/Windows PowerShell)
        $linkElement = $webPage.ParsedHtml.getElementById('auto-download-link')
        $downloadURL = $linkElement.href
        Log-Text "Found Git download via ParsedHtml: $downloadURL" "INFO"
    }
    catch {
        # Fallback to regex (PS6+/Core)
        $match = $webPage.Content | Select-String 'id="auto-download-link"[^>]*href="([^"]+)"' 
        $downloadURL = $match.Matches.Groups[1].Value
        Log-Text "Found Git download: $downloadURL" "INFO"
    }
    
    # get the latest version number
    if (-not $downloadURL) {
        $latestVersion = "0"
    } 
    else {
        $filename = Split-Path $downloadURL -Leaf
        $latestVersion = if ($filename -match '(\d+\.\d+\.\d+\.\d+)') { 
            $matches[1] 
        } 
        else { 
            "0" 
        }
    }
    Log-Text "Identified latest version number from filename: $latestVersion" "INFO"

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

    # Downlad the file
    try {
        Log-Text "Downloding $filename" "INFO"
        
        # Build full path and download using that filename
        $destination = Join-Path $LocalTempDir $filename
        Log-Text "Installer download location: $destination" "INFO"
        
        Invoke-WebRequest -Uri $downloadURL -OutFile $destination -UseBasicParsing

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
        $args = @(
            "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", 
            "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS",
    
            # Git configuration
            '/o:PathOption=CmdTools',
            '/o:SSHOption=OpenSSH',
            '/o:WTProfileForGitBash=Enabled',
    
            # VS Code as default Git editor
            '/o:EditorOption=VisualStudioCode',

            # Let Git decide default branch (modern main behavior)
            '/o:DefaultBranchOption=gitConfig',

            # Use the native Windows Secure Channel library
            '/o:HTTPSBackend=schannel',

            # configuring line ending conversion
            '/o:CRLFOption=CRLFCommitAsIs', 
            
            # configuring the terminal emulator to use with git bash
            '/o:BashTerminalOption=MinTTY',

            # choose the default behaviour of git pull
            '/o:PullBehavior=merge',

            # Got credential manager
            '/o:UseCredentialManager=Enabled',
                
            # "Enable file system caching
            '/o:FSCK=Enabled',

            # Components
            '/COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh,gitlfs"'
        )
        
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