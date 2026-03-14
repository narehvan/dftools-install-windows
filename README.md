# dftools-install-windows
Powershell scripts to auto install several tools on a fresh Windows 11 OS. The concept is that when Windows 11 is freshly installed, then it takes time to install digital forensics tools manually. Running these powershell scripts will automatically attempt to download the latest version of these products and install them silently. 

# how to use
- download the scripts
- start powershell as administrator
- update the "auto-install.ps1" file and comment tools you don't want to have it installed
- run "auto-install.ps1"
- look at the RED colour texts to see if there were errors during the installation

# notes
- Running the powershelgl script requires administrative privileges 
- VScode installation also installs few extensions:
	- "ms-vscode.PowerShell",           # PowerShell
	- "ms-python.python",               # Python (includes debugpy/pylance/envs)
	- "ms-dotnettools.csharp",          # C#
	- "ms-dotnettools.csdevkit",        # C# Dev Kit
	- "vscode-icons-team.vscode-icons", # File icons
	- "esbenp.prettier-vscode",         # Auto-format ALL files
	- "eamodio.gitlens",                # Git supercharged
	- "redhat.vscode-yaml",             # YAML
	- "infosec-intern.yara"             # YARA
	- "ms-vscode-remote.remote-containers", # Dev containers
	- "ms-azuretools.vscode-docker",        # Docker
	- "github.vscode-pull-request-github" # PRs 
- Wireshark installer does not install npcap. You need to install that manually if you need to capture traffic
- Most tools are installed for the logged in user. This means they are placed in "C:\Users\<user>\AppData\Local" director 
- Tools that do not have installer, are copied to "C:\forensics" directory
- The PATH variable is updated to include the "C:\forensics" and recursive directories
- Notepad++ includes few plugins:
	- ComparePlusPlugin - https://github.com/pnedev/comparePlus
	- XmlToolsPlugin - https://github.com/morbac/xmltools
	- JsonToolsPlugin - https://github.com/molsonkiko/JsonToolsNppPlugin


