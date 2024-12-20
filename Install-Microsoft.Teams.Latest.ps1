<#
.SYNOPSIS
    XXXX installation script
.DESCRIPTION
    This script downloads and installs XXX on a Windows machine.

    https://support.microsoft.com/help/2977003/the-latest-supported-visual-c-downloads

    HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Teams IsWVDEnvironment 	DWORD 	1
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name IsWVDEnvironment -PropertyType DWORD -Value 1 -Force

    Enable content sharing for Teams for RemoteApp
    HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\AddIns\WebRTC Redirector\Policy
    Add the ShareClientDesktop as a DWORD value.
    Set the value to 1 to enable the feature.

    Disable Autoupdate
    Location: Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Teams
    Name: disableAutoUpdate
    Type: DWORD
    Value: 1

    Disable autostart
    [HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System] 
"EnableFullTrustStartupTasks"=dword:00000000
"EnableUwpStartupTasks"=dword:00000000
"SupportFullTrustStartupTasks"=dword:00000000
"SupportUwpStartupTasks"=dword:00000000

    Disable autostart #2
    [HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask]
"State"=dword:00000003
"UserEnabledStartupOnce"=dword:00000001

    TeamsTfwStartupTask  roaming - reasearch


    Bootstrapper: https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409
    MSIX: https://go.microsoft.com/fwlink/?linkid=2196106

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

Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.ExitCode
