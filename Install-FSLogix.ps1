<#
.SYNOPSIS
    FSLogix installation script.

.DESCRIPTION
    This script downloads and installs FSLogix on a Windows machine.

.NOTES
    Author: NSP
    Date: 2024-11-17
    Version: 1.0.1
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
Write-Host "FSLogix installation result: $Result"


    #     Write-Host "Configuring FSLogix Profile Settings"
    # Push-Location 
    # Set-Location HKLM:\SOFTWARE\
    # New-Item `
    #     -Path HKLM:\SOFTWARE\FSLogix `
    #     -Name Profiles `
    #     -Value "" `
    #     -Force
    # New-Item `
    #     -Path HKLM:\Software\FSLogix\Profiles\ `
    #     -Name Apps `
    #     -Force
    # Set-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name "Enabled" `
    #     -Type "Dword" `
    #     -Value "1"
    # New-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name "CCDLocations" `
    #     -Value "type=smb,connectionString=$ProfilePath" `
    #     -PropertyType MultiString `
    #     -Force
    # Set-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name "SizeInMBs" `
    #     -Type "Dword" `
    #     -Value "30000"
    # Set-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name "IsDynamic" `
    #     -Type "Dword" `
    #     -Value "1"
    # Set-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name "VolumeType" `
    #     -Type String `
    #     -Value "vhdx"
    # Set-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name "FlipFlopProfileDirectoryName" `
    #     -Type "Dword" `
    #     -Value "1" 
    # Set-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name "SIDDirNamePattern" `
    #     -Type String `
    #     -Value "%username%%sid%"
    # Set-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name "SIDDirNameMatch" `
    #     -Type String `
    #     -Value "%username%%sid%"
    # Set-ItemProperty `
    #     -Path HKLM:\Software\FSLogix\Profiles `
    #     -Name DeleteLocalProfileWhenVHDShouldApply `
    #     -Type DWord `
    #     -Value 1
    # Pop-Location


Write-Host "###### FSLogix installation script is complete ######"
exit 0
