<#
.SYNOPSIS
    Microsft Teams x64 Windows installation script
.DESCRIPTION
    Downloads latest bootsrapper and MSIX
    Installs Teams via Bootstrapper
    Updates registry settings for:
        - AVD
        - RemoteApp Desktop Sharing
        - Autoupdate
        - Autostart

    NB:
        - Does not install VC++ Dependancies - https://support.microsoft.com/help/2977003/the-latest-supported-visual-c-downloads
        - Does not configure TeamsTfwStartupTask for profiles (HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask)

.NOTES
    See ./../Changelog.txt for version history.
#>

# Package information
$AppPublisher = "Microsoft" 
$AppName = "Teams"
$AppVersion = "Latest"
$AppSetupFile = ""
$ExeParams = ""
$URIRoot = "https://stethanmavdswpublicae1.blob.core.windows.net/builder-software-media"
$URITeamsBootStrapper =  "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409"
$URITeamsMSIX = "https://go.microsoft.com/fwlink/?linkid=2196106"
$AppBootstrapperName = "TeamsBootstrapper.exe"
$AppMSIXName = "MSTeams-x64.msix"

# Script variables
$RootFolder = "$env:programdata\ETHAN\ImageBuild"
$RootFolderApp = Join-Path -Path $RootFolder -ChildPath "$AppPublisher.$AppName"
$AppMoniker = "$AppPublisher.$AppName.$AppVersion"
$AppURI = "$URIRoot/$AppPublisher.$AppName.$AppVersion/$AppSetupFile"
$AppURI = $AppURI.ToLower()
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile

Write-Host "###### Starting $AppPublisher $AppName ($AppVersion) installation script! ######"
Write-Host "App: $AppMoniker SetupFile: $AppSetupFile URI: $AppURI RootFolder: $RootFolder RootFolderApp: $RootFolderApp"

# Root folder for app
if (!(Test-Path $RootFolderApp)) {New-Item -Path $RootFolderApp -ItemType Directory -Force | Out-Null; Write-Host "Created $RootFolderApp directory"} else {Write-Host "$RootFolderApp directory already exists"}

# # Download content
# Write-Host "Downloading $AppMoniker from $AppURI to $SetupFolderFile"
# try {
#     $ProgressPreference = 'SilentlyContinue'
#     Invoke-WebRequest -Uri $AppURI -OutFile "$SetupFolderFile" -UseBasicParsing -ErrorAction Stop
#     Write-Host "Downloaded $AppMoniker $AppSetupFile from $AppURI to $SetupFolderFile"
# }
# catch {
#     Write-Host "Failed to download $AppMoniker $AppSetupFile from $AppURI to $SetupFolderFile"
#     Exit 1
# }

# Download Bootstrapper
$AppMoniker = "$AppMoniker-$AppBootstrapperName"
$AppURI = $URITeamsBootStrapper
$AppSetupFile = $AppBootstrapperName 
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile
Write-Host "Downloading $AppMoniker from $AppURI to $SetupFolderFile"
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $AppURI -OutFile "$SetupFolderFile" -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded $AppMoniker $AppSetupFile from $AppURI to $SetupFolderFile"
}
catch {
    Write-Host "Failed to download $AppMoniker $AppSetupFile from $AppURI to $SetupFolderFile"
    Exit 1
}

# Download Teams MSIX
$AppMoniker = "$AppMoniker-$AppMSIXName"
$AppURI = $URITeamsMSIX
$AppSetupFile = $AppMSIXName
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile
Write-Host "Downloading $AppMoniker from $AppURI to $SetupFolderFile"
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $AppURI -OutFile "$SetupFolderFile" -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded $AppMoniker $AppSetupFile from $AppURI to $SetupFolderFile"
}
catch {
    Write-Host "Failed to download $AppMoniker $AppSetupFile from $AppURI to $SetupFolderFile"
    Exit 1
}

# Do installation
$AppSetupFile = $AppMSIXName
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile
Write-Host "Installing $AppMoniker $AppSetupFile"
$ExeParams = "-p -o $RootFolderApp\$AppSetupFile"
$arglist = "$ExeParams"
$SetupFolderFileBootstrapper = Join-Path -Path $RootFolderApp -ChildPath $AppBootstrapperName
Write-Host "Executing Start-Process -FilePath $SetupFolderFileBootstrapper -ArgumentList $arglist -Wait -Passthru"
$Result = Start-Process -FilePath $SetupFolderFileBootstrapper -ArgumentList $arglist -Wait -Passthru
Write-Host "$AppMoniker installation result: $($result.ExitCode)"

# Update registry settings
Write-Host "Updating registry settings for $AppMoniker"

# AVD
Write-Host "Setting Teams to AVD mode"
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name IsWVDEnvironment -PropertyType DWORD -Value 1 -Force

# RemoteApp Desktop Sharing
Write-Host "Enabling RemoteApp Desktop Sharing"
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\AddIns\WebRTC Redirector\Policy" -Force
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\AddIns\WebRTC Redirector\Policy" -Name ShareClientDesktop -PropertyType DWORD -Value 1 -Force

# Disable Autoupdate
Write-Host "Disabling autoupdate"
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name disableAutoUpdate -PropertyType DWORD -Value 1 -Force

# Disable autostart
Write-Host "Disabling autostart"
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableFullTrustStartupTasks -PropertyType DWORD -Value 0 -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableUwpStartupTasks -PropertyType DWORD -Value 0 -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name SupportFullTrustStartupTasks -PropertyType DWORD -Value 0 -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name SupportFullTrustStartupTasks -PropertyType DWORD -Value 0 -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name SupportUwpStartupTasks -PropertyType DWORD -Value 0 -Force


Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.ExitCode
