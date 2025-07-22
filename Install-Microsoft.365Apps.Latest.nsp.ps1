<#
.SYNOPSIS
    Office / 365 Apps installation script
.DESCRIPTION
    Installs 365 Apps. Does not install Teams or OneDrive
    Note channel, update and activation settings
.NOTES
    See ./../Changelog.txt for version history.
#>

# Package information
$AppPublisher = "Microsoft" 
$AppName = "365Apps"
$AppVersion = "Latest"
$AppSetupFile = "setup.exe"
#$ExeParams = ""
$URIRoot = "https://stethanmavdswpublicae1.blob.core.windows.net/builder-software-media"


# Office Config
$OfficeConfig = [xml]@"
<Configuration ID="9636bff2-567a-4044-9568-e724ea546fec">
  <Info Description="AVD Base Install&#xA;- x64&#xA;- LTSC Semi-annual&#xA;- No updates&#xA;- Core apps only&#xA;- no Teams, OneDrive&#xA;- EN-US&#xA;- Shared Computer Activation, non-roaming&#xA;- No registry customisations" />
  <Add OfficeClientEdition="64" Channel="SemiAnnual">
    <Product ID="O365ProPlusEEANoTeamsRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="Publisher" />
      <ExcludeApp ID="Bing" />
    </Product>
  </Add>
  <Property Name="SharedComputerLicensing" Value="1" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="DeviceBasedLicensing" Value="0" />
  <Property Name="SCLCacheOverride" Value="0" />
  <Updates Enabled="FALSE" />
  <RemoveMSI />
  <AppSettings>
    <User Key="software\microsoft\office\16.0\excel\options" Name="defaultformat" Value="51" Type="REG_DWORD" App="excel16" Id="L_SaveExcelfilesas" />
    <User Key="software\microsoft\office\16.0\powerpoint\options" Name="defaultformat" Value="27" Type="REG_DWORD" App="ppt16" Id="L_SavePowerPointfilesas" />
    <User Key="software\microsoft\office\16.0\word\options" Name="defaultformat" Value="" Type="REG_SZ" App="word16" Id="L_SaveWordfilesas" />
  </AppSettings>
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@


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

# Write XML locally
Write-Host "Writing OfficeConfig.xml to $RootFolderApp"
if (Test-Path "$RootFolderApp\OfficeConfig.xml") {Remove-Item "$RootFolderApp\OfficeConfig.xml" -Force}
$OfficeConfig.Save("$RootFolderApp\OfficeConfig.xml")

# Do installation
Write-Host "Installing $AppMoniker $SetupFolderFile"
$ExeParams = "/configure $RootFolderApp\OfficeConfig.xml"
$arglist = "$ExeParams"
Write-Host "Executing Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru"
$Result = Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru
Write-Host "$AppMoniker installation result: $($result.ExitCode)"

Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.ExitCode
