<#
.SYNOPSIS
    Azure Powershell MSI installation script
.DESCRIPTION
    This script downloads and installs AZ Powershell on a Windows machine using the Offline installation approach.
.NOTES
    See ./../Changelog.txt for version history.
#>

$AppPublisher = "Microsoft" 
$AppName = "Powershell"
$AppVersion = "7.4.6"
$AppSetupFile = "PowerShell-7.4.6-win-x64.msi"

$RootFolder = "$env:programdata\ETHAN\ImageBuild"
$RootFolderApp = Join-Path -Path $RootFolder -ChildPath "$AppPublisher.$AppName"
$AppMoniker = "$AppPublisher.$AppName.$AppVersion"

# Downloads
$AppURI = "https://stethanmavdswpublicae1.blob.core.windows.net/builder-software-media/Microsoft.PowerShell.7.4.6/PowerShell-7.4.6-win-x64.msi"
$AppDownloadFile = $AppSetupFile

Write-Host "###### Starting $AppPublisher $AppName ($AppVersion) installation script! ######"

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
    Invoke-WebRequest -Uri $AppURI -OutFile "$RootFolderApp\$AppDownloadFile" -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded $AppMoniker"
}
catch {
    Write-Host "Failed to download $AppMoniker"
    Exit 1
}

# Do installation
 Write-Host "Installing $AppMoniker $AppSetupFile"
 $SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile
 Write-Host "-FilePath $SetupFolderFile -ArgumentList `"/quiet /norestart /i $SetupFolderFile`" -Wait -Passthru"
 $Result = Start-Process -FilePath msiexec.exe -ArgumentList "/quiet /norestart /i $SetupFolderFile" -Wait -Passthru
 Write-Host "$AppMoniker installation result: $($result.exitcode)"

Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.exitcode
