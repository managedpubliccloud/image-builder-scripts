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
$tag = (Invoke-WebRequest $releases -UseBasicParsing| ConvertFrom-Json)[0].tag_name
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

# Expand Zip, move file, clean up
Write-Host "Expanding $SetupFolderFile"
if (Test-Path "$RootFolderApp\$AppSetupFile") {Remove-Item -Path "$RootFolderApp\$AppSetupFile" -Force}
Expand-Archive -Path $SetupFolderFile -Destination $RootFolderApp -Force
$FilePath = Get-ChildItem -Path $RootFolderApp -Filter $AppSetupFile -Recurse
# Write-Host "Found for $($FilePath.count) matches for $AppSetupFile in $RootFolderApp"
# Write-Host "Copying $($FilePath[0].FullName) to $RootFolderApp"
# Copy-Item -Path $FilePath[0].FullName -Destination $RootFolderApp -Force
# if (Test-Path -Path $SetupFolderFile) {Remove-Item -Path $SetupFolderFile -Force}

# $FolderPath = Get-ChildItem -Path $RootFolderApp -Filter "Virtual-Desktop-Optimization-Tool*" -Recurse
# Write-Host "Found for $($FolderPath.count) matches for Virtual-Desktop-Optimization-Tool in $RootFolderApp"
# Remove-Item -Path $FolderPath[0].FullName -Recurse -Force
$VDOPRoot = $FilePath[0].DirectoryName
Write-Host "VDOPRoot: $VDOPRoot"

# Create custom AppxPackages.json file
$AppxPackagesJsonFile = Join-Path -Path $VDOPRoot -ChildPath "2009\ConfigurationFiles\AppxPackages.json"

#region AppxPackages.json
$AppxPackagesJson = @"
[
  {
    "AppxPackage": "Bing Search",
    "VDIState": "Disabled",
    "URL": "https://apps.microsoft.com/detail/9nzbf4gt040c",
    "Description": "Web Search from Microsoft Bing provides web results and answers in Windows Search"
  },
  {
    "AppxPackage": "Clipchamp.Clipchamp",
    "VDIState": "Disabled",
    "URL": "https://apps.microsoft.com/detail/9p1j8s7ccwwt?hl=en-us&gl=US",
    "Description": "Create videos with a few clicks"
  },
  {
    "AppxPackage": "Microsoft.549981C3F5F10",
    "VDIState": "Disabled",
    "URL": "https://apps.microsoft.com/detail/cortana/9NFFX4SZZ23L?hl=en-us&gl=US",
    "Description": "Cortana (could not update)"
  },
  {
    "AppxPackage": "Microsoft.BingNews",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/microsoft-news/9wzdncrfhvfw",
    "Description": "Microsoft News app"
  },
  {
    "AppxPackage": "Microsoft.BingWeather",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/msn-weather/9wzdncrfj3q2",
    "Description": "MSN Weather app"
  },
  {
    "AppxPackage": "Microsoft.DesktopAppInstaller",
    "VDIState": "Unchanged",
    "URL": "https://apps.microsoft.com/detail/9NBLGGH4NNS1",
    "Description": "Microsoft App Installer for Windows 10 makes sideloading Windows apps easy"
  },
  {
    "AppxPackage": "Microsoft.GamingApp",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/xbox/9mv0b5hzvk9z",
    "Description": "Xbox app"
  },
  {
    "AppxPackage": "Microsoft.GetHelp",
    "VDIState": "Disabled",
    "URL": "https://docs.microsoft.com/en-us/windows-hardware/customize/desktop/customize-get-help-app",
    "Description": "App that facilitates free support for Microsoft products"
  },
  {
    "AppxPackage": "Microsoft.Getstarted",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/microsoft-tips/9wzdncrdtbjj",
    "Description": "Windows 10 tips app"
  },
  {
    "AppxPackage": "Microsoft.MicrosoftOfficeHub",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/office/9wzdncrd29v9",
    "Description": "Office UWP app suite"
  },
  {
    "AppxPackage": "Microsoft.Office.OneNote",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/onenote-for-windows-10/9wzdncrfhvjl",
    "Description": "Office UWP OneNote app"
  },
  {
    "AppxPackage": "Microsoft.MicrosoftSolitaireCollection",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/microsoft-solitaire-collection/9wzdncrfhwd2",
    "Description": "Solitaire suite of games"
  },
  {
    "AppxPackage": "Microsoft.MicrosoftStickyNotes",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/microsoft-sticky-notes/9nblggh4qghw",
    "Description": "Note-taking app"
  },
  {
    "AppxPackage": "Microsoft.OutlookForWindows",
    "VDIState": "Disabled",
    "URL": "https://apps.microsoft.com/detail/9NRX63209R7B?hl=en-us&gl=US",
    "Description": "a best-in-class email experience that is free for anyone with Windows"
  },
  {
    "AppxPackage": "Microsoft.MSPaint",
    "VDIState": "Disabled",
    "URL": "https://apps.microsoft.com/store/detail/paint-3d/9NBLGGH5FV99",
    "Description": "Paint 3D app (not Classic Paint app)"
  },
  {
    "AppxPackage": "Microsoft.Paint",
    "VDIState": "Disabled",
    "URL": "https://apps.microsoft.com/detail/9PCFS5B6T72H?hl=en-us&gl=US",
    "Description": "Classic Paint app"
  },
  {
    "AppxPackage": "Microsoft.People",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/microsoft-people/9nblggh10pg8",
    "Description": "Contact management app"
  },
  {
    "AppxPackage": "Microsoft.PowerAutomateDesktop",
    "VDIState": "Disabled",
    "URL": "https://flow.microsoft.com/en-us/desktop/",
    "Description": "Power Automate Desktop app. Record desktop and web actions in a single flow"
  },
  {
    "AppxPackage": "Microsoft.ScreenSketch",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/snip-sketch/9mz95kl8mr0l",
    "Description": "Snip and Sketch app"
  },
  {
    "AppxPackage": "Microsoft.SkypeApp",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/skype/9wzdncrfj364",
    "Description": "Instant message, voice or video call app"
  },
  {
    "AppxPackage": "Microsoft.StorePurchaseApp",
    "VDIState": "Disabled",
    "URL": "",
    "Description": "Store purchase app helper"
  },
  {
    "AppxPackage": "Microsoft.Todos",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/microsoft-to-do-lists-tasks-reminders/9nblggh5r558",
    "Description": "Microsoft To Do makes it easy to plan your day and manage your life"
  },
  {
    "AppxPackage": "Microsoft.WinDbg.Fast",
    "VDIState": "Unchanged",
    "URL": "https://apps.microsoft.com/detail/9PGJGD53TN86?hl=en-us&gl=US",
    "Description": "Microsoft WinDbg"
  },
  {
    "AppxPackage": "Microsoft.Windows.DevHome",
    "VDIState": "Disabled",
    "URL": "https://learn.microsoft.com/en-us/windows/dev-home/",
    "Description": "A control center providing the ability to monitor projects in your dashboard using customizable widgets and more"
  },
  {
    "AppxPackage": "Microsoft.Windows.Photos",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/microsoft-photos/9wzdncrfjbh4",
    "Description": "Photo and video editor"
  },
  {
    "AppxPackage": "Microsoft.WindowsAlarms",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/windows-alarms-clock/9wzdncrfj3pr",
    "Description": "A combination app, of alarm clock, world clock, timer, and stopwatch."
  },
  {
    "AppxPackage": "Microsoft.WindowsCalculator",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/windows-calculator/9wzdncrfhvn5",
    "Description": "Microsoft Calculator app"
  },
  {
    "AppxPackage": "Microsoft.WindowsCamera",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/windows-camera/9wzdncrfjbbg",
    "Description": "Camera app to manage photos and video"
  },
  {
    "AppxPackage": "microsoft.windowscommunicationsapps",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/mail-and-calendar/9wzdncrfhvqm",
    "Description": "Mail & Calendar apps"
  },
  {
    "AppxPackage": "Microsoft.WindowsFeedbackHub",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/feedback-hub/9nblggh4r32n",
    "Description": "App to provide Feedback on Windows and apps to Microsoft"
  },
  {
    "AppxPackage": "Microsoft.WindowsMaps",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/windows-maps/9wzdncrdtbvb",
    "Description": "Microsoft Maps app"
  },
  {
    "AppxPackage": "Microsoft.WindowsNotepad",
    "VDIState": "Unchanged",
    "URL": "https://www.microsoft.com/en-us/p/windows-notepad/9msmlrh6lzf3",
    "Description": "Fast, simple text editor for plain text documents and source code files."
  },
  {
    "AppxPackage": "Microsoft.WindowsStore",
    "VDIState": "Unchanged",
    "URL": "https://blogs.windows.com/windowsexperience/2021/06/24/building-a-new-open-microsoft-store-on-windows-11/",
    "Description": "Windows Store app"
  },
  {
    "AppxPackage": "Microsoft.WindowsSoundRecorder",
    "VDIState": "Unchanged",
    "URL": "https://www.microsoft.com/en-us/p/windows-voice-recorder/9wzdncrfhwkn",
    "Description": "(Voice recorder)"
  },
  {
    "AppxPackage": "Microsoft.WindowsTerminal",
    "VDIState": "Unchanged",
    "URL": "https://www.microsoft.com/en-us/p/windows-terminal/9n0dx20hk701",
    "Description": "A terminal app featuring tabs, panes, Unicode, UTF-8 character support, and GPU text rendering engine."
  },
  {
    "AppxPackage": "Microsoft.Winget.Platform.Source",
    "VDIState": "Unchanged",
    "URL": "https://learn.microsoft.com/en-us/windows/package-manager/winget/",
    "Description": "The Winget tool enables users to manage applications on Win10 and Win11 devices. This tool is the client interface to the Windows Package Manager service"
  },
  {
    "AppxPackage": "Microsoft.Xbox.TCUI",
    "VDIState": "Disabled",
    "URL": "https://docs.microsoft.com/en-us/gaming/xbox-live/features/general/tcui/live-tcui-overview",
    "Description": "XBox Title Callable UI (TCUI) enables your game code to call pre-defined user interface displays"
  },
  {
    "AppxPackage": "Microsoft.XboxGameOverlay",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/xbox-game-bar/9nzkpstsnw4p",
    "Description": "Xbox Game Bar extensible overlay"
  },
  {
    "AppxPackage": "Microsoft.XboxGamingOverlay",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/xbox-game-bar/9nzkpstsnw4p",
    "Description": "Xbox Game Bar extensible overlay"
  },
  {
    "AppxPackage": "Microsoft.XboxIdentityProvider",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/xbox-identity-provider/9wzdncrd1hkw",
    "Description": "A system app that enables PC games to connect to Xbox Live."
  },
  {
    "AppxPackage": "Microsoft.XboxSpeechToTextOverlay",
    "VDIState": "Disabled",
    "URL": "https://support.xbox.com/help/account-profile/accessibility/use-game-chat-transcription",
    "Description": "Xbox game transcription overlay"
  },
  {
    "AppxPackage": "Microsoft.YourPhone",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/Your-phone/9nmpj99vjbwv",
    "Description": "Android phone to PC device interface app"
  },
  {
    "AppxPackage": "Microsoft.ZuneMusic",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/groove-music/9wzdncrfj3pt",
    "Description": "Groove Music app"
  },
  {
    "AppxPackage": "Microsoft.ZuneVideo",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/movies-tv/9wzdncrfj3p2",
    "Description": "Movies and TV app"
  },
  {
    "AppxPackage": "MicrosoftCorporationII.QuickAssist",
    "VDIState": "Disabled",
    "URL": "https://apps.microsoft.com/detail/9P7BP5VNWKX5?hl=en-us&gl=US",
    "Description": "Microsoft remote help app"
  },
  {
    "AppxPackage": "MicrosoftWindows.Client.WebExperience",
    "VDIState": "Disabled",
    "URL": "",
    "Description": "Windows 11 Internet information widget"
  },
  {
    "AppxPackage": "Microsoft.XboxApp",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/store/apps/9wzdncrfjbd8",
    "Description": "Xbox 'Console Companion' app (games, friends, etc.)"
  },
  {
    "AppxPackage": "Microsoft.MixedReality.Portal",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/mixed-reality-portal/9ng1h8b3zc7m",
    "Description": "The app that facilitates Windows Mixed Reality setup, and serves as the command center for mixed reality experiences"
  },
  {
    "AppxPackage": "Microsoft.Microsoft3DViewer",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/p/3d-viewer/9nblggh42ths",
    "Description": "App to view common 3D file types"
  },
  {
    "AppxPackage": "MicrosoftTeams",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/microsoft-teams/group-chat-software",
    "Description": "Microsoft communication platform"
  },
  {
    "AppxPackage": "Microsoft.OneDriveSync",
    "VDIState": "Disabled",
    "URL": "https://docs.microsoft.com/en-us/onedrive/one-drive-sync",
    "Description": "Microsoft OneDrive sync app (included in Office 2016 or later)"
  },
  {
    "AppxPackage": "Microsoft.Wallet",
    "VDIState": "Disabled",
    "URL": "https://www.microsoft.com/en-us/payments",
    "Description": "(Microsoft Pay) for Edge browser on certain devices"
  }
]
"@
#end-region AppxPackages.json
Write-Host "Writing $AppxPackagesJsonFile"
Out-File -FilePath $AppxPackagesJsonFile -InputObject $AppxPackagesJson -Encoding utf8


# Do installation
$SetupFolderFile = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile 
Write-Host "Installing $AppMoniker $SetupFolderFile"
$arglist = "$VDOPRoot\$AppSetupFile $ExeParams"
Write-Host "Executing Start-Process -FilePath powershell.exe -ArgumentList $arglist -Wait -Passthru"
$Result = Start-Process -FilePath "powershell.exe" -ArgumentList $arglist -Wait -Passthru
Write-Host "$AppMoniker installation result: $($result.ExitCode)"

Write-Host "###### $AppMoniker installation script is complete ######"
exit $result.ExitCode
