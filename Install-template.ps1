<#
.SYNOPSIS
    Install template

.DESCRIPTION
    This script does...

.NOTES
    NB: Use Winget names where possible - https://github.com/microsoft/winget-pkgs
    Author: NSP
    Date: 2024-11-17
    Version: 1.0.1
#>

$AppPublisher = "SomeCorp" 
$AppName = "SomeApp"
$AppVersion = "1.1.1"
$AppSetupFile = ""

$RootFolder = "$env:programdata\ETHAN\ImageBuild\"
$RootFolderApp = Join-Path -Path $RootFolder -ChildPath "$AppPublisher.$AppName"
$AppMoniker = "$AppPublisher.$AppName.$AppVersion"

# Downloads
$AppURI = ""
$AppDownloadFile = ""

Write-Host "###### Starting $AppPublisher $AppName ($AppVersion) installation script ######"

# Root folder for app
if ((Test-Path $RootFolderApp) -eq $false) {
    New-Item -Path $RootFolderApp -ItemType Directory -Force
    Write-Host "Created $RootFolderApp directory"
} else {
    Write-Host "$RootFolderApp directory already exists"
}

# Download content
Write-Host "Downloading $AppMoniker from $AppURI to $RootFolderApp\$AppDownloadFile"
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $URI -OutFile "$RootFolderApp\$AppDownloadFile" -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded $AppMoniker"
}
catch {
    Write-Host "Failed to download $AppMoniker"
    Exit 1
}

# Unzip content
Write-Host "Unzipping $AppDownloadFile"
$RootFolderAppUnzip = Join-Path -Path $RootFolderApp -ChildPath "Source"
Expand-Archive -LiteralPath "$RootFolderApp\$AppDownloadFile" -DestinationPath $RootFolderAppUnzip -Force -Verbose

# Do installation
Write-Host "Installing $AppMoniker"
$SetupFile = Join-Path -Path $RootFolderAppUnzip -ChildPath $AppSetupFile
$Result = Start-Process -FilePath $SetupFile -ArgumentList "/install /quiet /norestart" -Wait -Passthru
Write-Host "$AppMoniker installation result: $Result"


Write-Host "###### $AppMoniker installation script is complete ######"
exit 0
