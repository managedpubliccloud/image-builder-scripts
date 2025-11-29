<#
.SYNOPSIS
    iManage.AgentServices.110.0.7 installation script
.DESCRIPTION
    This script downloads and installs iManage.AgentServices.110.0.7 on a Windows machine.
.NOTES
    See ./../Changelog.txt for version history.
#>

# Package information
$AppPublisher = "iManage" 
$AppName = "AgentServices"
$AppVersion = "110.0.7"
$AppSetupFile = "iManageAgentServices.exe"
$ExeParams = "/silent"
$URIRoot = "https://stethanmavdswpublicae1.blob.core.windows.net/builder-software-media"

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

# Download content
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
Write-Host "Installing $AppMoniker $SetupFolderFile"
$arglist = "$ExeParams"
Write-Host "Executing Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru"
$Result = Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru
Write-Host "$AppMoniker installation result: $($result.ExitCode)"

Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.ExitCode
