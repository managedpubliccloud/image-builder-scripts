<#
.SYNOPSIS
    Refresh CI Policy installation script
.DESCRIPTION
    This script downloads and installs Refresh CI Policy on a Windows machine.
.NOTES
    See ./../Changelog.txt for version history.
#>

# Package information
$AppPublisher = "Microsoft" 
$AppName = "RefreshCIPolicy"
$AppVersion = "1.0.0"
$AppSetupFile = "RefreshPolicy(AMD64).exe"
$AppSetupFileFinal = "RefreshPolicy.exe"
$ExeParams = "/quiet /norestart"
$URIRoot = "https://download.microsoft.com/download/2/d/5/2d598537-6131-40ba-a1e3-f664b97fef6e/RefreshCIPolicy/AMD64/RefreshPolicy(AMD64).exe"

# Script variables
$RootFolder = "$env:programdata\Microsoft"
$RootFolderApp = Join-Path -Path $RootFolder -ChildPath "$AppName"
$AppMoniker = "$AppPublisher.$AppName.$AppVersion"
$AppURI = "$URIRoot/$AppPublisher.$AppName.$AppVersion/$AppSetupFile"
$AppURI = $AppURI.ToLower()
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile

Write-Host "###### Starting $AppPublisher $AppName ($AppVersion) installation script! ######"
Write-Host "App: $AppMoniker SetupFile: $AppSetupFile URI: $AppURI RootFolder: $RootFolder RootFolderApp: $RootFolderApp"

# Root folder for app
if (!(Test-Path $RootFolderApp)) {New-Item -Path $RootFolderApp -ItemType Directory -Force | Out-Null; Write-Host "Created $RootFolderApp directory"} else {Write-Host "$RootFolderApp directory already exists"}

# Download content
Write-Host "Downloading $AppMoniker from $URIRoot to $SetupFolderFile"
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $URIRoot -OutFile "$SetupFolderFile" -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded $AppMoniker from $URIRoot to $SetupFolderFile"
}
catch {
    Write-Host "Failed to download $AppMoniker $AppSetupFile from $URIRoot to $SetupFolderFile"
    Exit 1
}

# Do post download config
Write-Host "Unblocking $SetupFolderFile"
Unblock-File -Path $SetupFolderFile -ErrorAction SilentlyContinue

Write-Host "Renaming $SetupFolderFile to $AppSetupFileFinal"
Remove-Item -Path "$env:programdata\Microsoft\RefreshCIPolicy\$AppSetupFileFinal" -ErrorAction SilentlyContinue
Rename-Item -Path $SetupFolderFile -NewName $AppSetupFileFinal -Force

Write-Host "###### $AppMoniker installation script is complete ######"
exit 0
