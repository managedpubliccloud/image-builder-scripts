<#
.SYNOPSIS
    WinDirStat installation script
.DESCRIPTION
    This script downloads and installs WinDirStat on a Windows machine.
.NOTES
    See ./../Changelog.txt for version history.
#>

$AppPublisher = "WinDirStat" 
$AppName = "WinDirStat"
$AppVersion = "2.0.3"
$AppSetupFile = "WinDirStat-x64.msi"
$URIRoot = "https://stetstavdsharedpublicae1.blob.core.windows.net/source/AVD-Source-Files"

$RootFolder = "$env:programdata\ETHAN\ImageBuild"
$RootFolderApp = Join-Path -Path $RootFolder -ChildPath "$AppPublisher.$AppName"
$AppMoniker = "$AppPublisher.$AppName.$AppVersion"

$AppURI = "$URIRoot/$AppPublisher.$AppName.$AppVersion/$AppSetupFile"
$AppURI = $AppURI.ToLower()
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile

Write-Host "###### Starting $AppPublisher $AppName ($AppVersion) installation script! ######"
Write-Host "App: $AppMoniker SetupFile: $AppSetupFile URI: $AppURI RootFolder: $RootFolder RootFolderApp: $RootFolderApp"

# Root folder for app
if ((Test-Path $RootFolderApp) -eq $false) {
    New-Item -Path $RootFolderApp -ItemType Directory -Force
    Write-Host "Created $RootFolderApp directory"
} else {
    Write-Host "$RootFolderApp directory already exists"
}

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
$arglist = "/quiet /norestart /i $SetupFolderFile"
Write-Host "Executing Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru"
$Result = Start-Process -FilePath msiexec.exe -ArgumentList "/quiet /norestart /i $SetupFolderFile" -Wait -Passthru
Write-Host "$AppMoniker installation result: $($result.ExitCode)"

Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.ExitCode
