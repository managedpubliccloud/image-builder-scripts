<#
.SYNOPSIS
    Run VDOT Cleanup
.DESCRIPTION
    This script downloads and runs VDOT Cleanup on a Windows machine.
.NOTES
    See ./../Changelog.txt for version history.
#>

# Package information
$AppPublisher = "Microsoft" 
$AppName = "VDOT"
$AppVersion = "Latest"
$AppSetupFile = "Windows_VDOT.ps1"
$ExeParams = "-Optimizations All -AdvancedOptimizations Edge,RemoveLegacyIE  -AcceptEULA -Verbose"
$URIRoot = ""
$Repo = "The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool"
$File = "vdop.zip"
$Releases = "https://api.github.com/repos/$repo/releases"

# Script variables
$RootFolder = "$env:programdata\ETHAN\ImageBuild"
$RootFolderApp = Join-Path -Path $RootFolder -ChildPath "$AppPublisher.$AppName"
$AppMoniker = "$AppPublisher.$AppName.$AppVersion"
$AppURI = "$URIRoot/$AppPublisher.$AppName.$AppVersion/$AppSetupFile"
$AppURI = $AppURI.ToLower()
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile

Write-Host "###### Starting $AppPublisher $AppName ($AppVersion) installation script! ######"
Write-Host "App: $AppMoniker SetupFile: $AppSetupFile URI: $AppURI RootFolder: $RootFolder RootFolderApp: $RootFolderApp"

# Determine latest release
Write-Host "Determining latest release of $Repo $File"
$tag = (Invoke-WebRequest $releases | ConvertFrom-Json)[0].tag_name
$AppURI = "https://github.com/$repo/archive/refs/tags/$tag.zip"


# Root folder for app
if (!(Test-Path $RootFolderApp)) {New-Item -Path $RootFolderApp -ItemType Directory -Force | Out-Null; Write-Host "Created $RootFolderApp directory"} else {Write-Host "$RootFolderApp directory already exists"}

# Download content
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $File
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

# Expand Zip and move file
Write-Host "Expanding $SetupFolderFile"
if (Test-Path "$RootFolderApp\$AppSetupFile") {Remove-Item -Path "$RootFolderApp\$AppSetupFile" -Force}
Expand-Archive -Path $SetupFolderFile -Destination $RootFolderApp -Force
$FilePath = Get-ChildItem -Path $RootFolderApp -Filter $AppSetupFile -Recurse
Write-Host "Found for $($FilePath.count) matches for $AppSetupFile in $RootFolderApp"
Write-Host "Copying $($FilePath[0].FullName) to $RootFolderApp"
Copy-Item -Path $FilePath[0] -Destination $RootFolderApp -Force

# Do installation
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile 
Write-Host "Installing $AppMoniker $SetupFolderFile"
$arglist = "$ExeParams"
Write-Host "Executing Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru"
$Result = Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru
Write-Host "$AppMoniker installation result: $($result.ExitCode)"

Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.ExitCode
