<#
.SYNOPSIS
    FSLogix installation script
.DESCRIPTION
    This script downloads and installs latest FSLogix on a Windows machine.
.NOTES
    See ./../Changelog.txt for version history.
#>

Write-Host "###### Starting FSLogix installation script ######"
$localPath = "$env:programdata\ETHAN\ImageBuild\FSLogix"
$fslogixURI = 'https://aka.ms/fslogix_download'
$fslogixInstaller = 'FSLogixAppsSetup.zip'

# Local staging folder
if ((Test-Path $LocalPath) -eq $false) {
    New-Item -Path $LocalPath -ItemType Directory -Force
    Write-Host "Created $LocalPath directory"
} else {
    Write-Host "$LocalPath directory already exists"
}

Write-Host "Downloading FSLogix"
Invoke-WebRequest -Uri $fslogixURI -OutFile "$LocalPath\$fslogixInstaller"

Write-Host "Unzipping FSLogix"
Expand-Archive -LiteralPath "$LocalPath\$fslogixInstaller" -DestinationPath "$LocalPath\FSLogix" -Force -Verbose
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


Write-Host "Installing FSLogix"
$Result = Start-Process -FilePath "$LocalPath\FSLogix\x64\Release\FSLogixAppsSetup.exe" -ArgumentList "/install /quiet /norestart" -Wait -Passthru
Write-Host "FSLogix installation result: $($result.exitcode)"

Write-Host "###### FSLogix installation script is complete ######"
exit 0
