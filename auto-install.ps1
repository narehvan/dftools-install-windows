#####################################################
# ===== GLOBAL CONFIG =====
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::"Tls13,Tls12"

#####################################################
# ===== LOAD FUNCTIONS =====
. .\utility_functions.ps1

# ===== LOAD APP-SPECIFIC SCRIPTS =====
. .\apps\autopsy.ps1
. .\apps\firefox.ps1
. .\apps\git.ps1
. .\apps\hxd.ps1
. .\apps\notepadplusplus.ps1
. .\apps\python3.ps1
. .\apps\sleuthkit.ps1
. .\apps\totalcommander.ps1
. .\apps\vscode.ps1
. .\apps\wireshark.ps1
. .\apps\zimmermanTools.ps1

#####################################################
# ===== MAIN SCRIPT =====

# Comment the line corresponding the app you don't want auto-installed
$appsToInstall = @{
    # === Tools ====
    notepadplusplus = { Install-Full-NotepadPlusPlus } # https://notepad-plus-plus.org/
    totalcommander  = { Install-TotalCommander }       # https://www.ghisler.com/
    wireshark       = { Install-Wireshark }            # https://www.wireshark.org/

    # === Coding ===
    git             = { Install-Git }                  # https://git-scm.com/install/windows/
    python3         = { Install-Python3 }              # https://www.python.org/
    vscode          = { Install-Full-VSCode }          # https://code.visualstudio.com/

    # === Browsers ===
    firefox         = { Install-Firefox }              # https://www.firefox.com/en-US/download/all/

    # === Digital Forensics ===
    hxd             = { Install-HxD }                  # https://mh-nexus.de/en/hxd/
    autopsy         = { Install-Autopsy }              # https://www.sleuthkit.org/autopsy/
    sleuthkit       = { Install-Sleuthkit }            # https://www.sleuthkit.org/sleuthkit/
    zimmermanTools  = { Install-ZimmermanTools }       # https://ericzimmerman.github.io/
}

# check if the script is being executed with administrative priviledges
if (-not (Test-IsElevated)) {
    Log-Text "This installer requires Administrator privileges. Please run as Administrator." "ERROR"
    return $false
}

# go through the list and install one by one
foreach ($appName in $appsToInstall.Keys | Sort-Object) {
    Log-Text "=== Installing $appName ===" "INFO"
    $success = & $appsToInstall[$appName]
    if ($success) {
        Log-Text "$appName installed successfully" "INFO"
    } 
    else {
        Log-Text "$appName installation failed" "ERROR"
    }
}

# List all the apps that are installed
Log-Text "Here is the list of all installed applications. It does not include applications that were copied (without installer)" "INFO"
Get-InstalledApplications