<#
.SYNOPSIS
    Notepad ++ installation script
.DESCRIPTION
    This script downloads the latest x64 NPP and installs on a Windows machine.
.NOTES
    See ./../Changelog.txt for version history.
#>

# Package information
$AppPublisher = "NotepadPP" 
$AppName = "NotepadPP"
$AppVersion = "Latest"
$AppSetupFile = "npp.latest.Installer.exe"
$ExeParams = "/S"
$URIRoot = ""


function Get-NotepadppBinary {
    #  This script will be used for downloading the latest Notepad++ version from its official site.

    $InstallerSourceUrl = "https://notepad-plus-plus.org/downloads"
    $HttpRequest = [System.Net.WebRequest]::Create($InstallerSourceUrl)
    $HttpResponse = $HttpRequest.GetResponse()
    $HttpStatusCode = [int]$HttpResponse.StatusCode
    if ($HttpStatusCode -ne 200) { Write-Error -Message "[$InstallerSourceUrl] unable to reach out with status code [$HttpStatusCode]." -ErrorAction Stop}

    # Get site contents.
    $SiteContents = Invoke-WebRequest -Uri $InstallerSourceUrl -UseBasicParsing
    $SiteHrefs = $SiteContents.Links
    #dynamic array for storing Notepad++ version extracted from site.
    $ApplicationVersion = [system.Collections.ArrayList]@()
    #filter only uri contains the Notepad++ versions.
    foreach ($SiteHref in $SiteHrefs)
    {
        if ($SiteHref.href -match "https://notepad-plus-plus.org/downloads/v\d.*/$")
        {
            $UrlVersion = $SiteHref.href -replace "https://notepad-plus-plus.org/downloads/", ""
            $VersionNumber = $UrlVersion -replace "/", ""
            $ApplicationVersion.Add($VersionNumber) | Out-Null
        }
    }
    #get latest Notepad++ installer version.
    $LatestApplicationVersion = $ApplicationVersion[0]
    #remove space from installer version.
    $VersionNumber = $( $LatestApplicationVersion -replace "v", "" )
    $BinaryFileName = "npp.$VersionNumber.Installer.x64.exe"

    #get full path of Notepad++ binary source url.
    $BinarySourceUrl = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/$LatestApplicationVersion/$BinaryFileName"

    #download latest Notepad++ binary file from site.
    Write-Host "Downloading Notepad++ binary from [$BinarySourceUrl] to npp.latest.Installer.exe"
    Invoke-WebRequest -Uri $BinarySourceUrl -OutFile $SetupFolderFile -Verbose -TimeoutSec 60
}





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
Get-NotepadppBinary

# Do installation

Write-Host "Installing $AppMoniker $SetupFolderFile"
$arglist = "$ExeParams"
Write-Host "Executing Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru"
$Result = Start-Process -FilePath $SetupFolderFile -ArgumentList $arglist -Wait -Passthru
Write-Host "$AppMoniker installation result: $($result.ExitCode)"

Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.ExitCode
