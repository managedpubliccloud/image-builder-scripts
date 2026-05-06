<#
.SYNOPSIS
    Installs Windows Package Manager (winget) if missing or outdated.
    Skips installation if the currently installed version is already up to date.

.DESCRIPTION
    This script installs or repairs Windows Package Manager (winget) using
    Microsoft-supported tooling:
      - Microsoft.WinGet.Client PowerShell module
      - Repair-WinGetPackageManager

    If winget is already installed, the script attempts to determine the
    latest available winget release via the GitHub releases API and will
    skip the install/repair step when the installed version is already latest
    (or newer). If version detection fails, the script proceeds with repair.

    This script intentionally avoids deprecated OneGet / manual NuGet provider
    bootstrap logic.

.PARAMETER IncludePrerelease
    Install the latest prerelease version of winget.

.PARAMETER LogPath
    Optional path to the log file.
    Default: %TEMP%\Install-WingetV2.log

.EXAMPLE
    .\Install-Winget.Latest.ps1
    Standard installation/repair of winget with default logging.

.EXAMPLE
    .\Install-Winget.Latest.ps1 -IncludePrerelease
    Install/repair winget using the prerelease channel.

.EXAMPLE
    .\Install-Winget.Latest.ps1 -LogPath "C:\Logs\Install-WingetV2.log"
    Run with a custom log file path.

.NOTES
    Requirements:
    - Windows 10 version 1809 (build 17763) or later,
      or Windows Server 2022 or later
    - PowerShell 5.1 or higher
    - Administrative privileges
    - Internet connectivity (PSGallery required; GitHub API used opportunistically)

.LINK
    https://github.com/microsoft/winget-cli
#>

[CmdletBinding()]
param(
    [switch]$IncludePrerelease,
    [string]$LogPath = (Join-Path $env:TEMP "Install-WingetV2.log")
)

# ============================
# Initialization
# ============================

$script:StartTime = Get-Date
$script:LogPath   = $LogPath

# Ensure the log directory exists (best-effort; logging should never break the script)
try {
    $requestedDir = Split-Path -Path $script:LogPath -Parent
    if ($requestedDir -and -not (Test-Path -Path $requestedDir)) {
        New-Item -Path $requestedDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}
catch {
    # ignore
}

# Required for PSGallery downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================
# Logging
# ============================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","SUCCESS","WARNING","ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp][$Level] $Message"

    Write-Host $entry
    try {
        $logDir = Split-Path -Path $script:LogPath -Parent
        if ($logDir -and -not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Add-Content -Path $script:LogPath -Value $entry -ErrorAction Stop
    }
    catch {
        # If we cannot write to the log file, still keep console output working.
    }
}

# ============================
# Prerequisite Checks
# ============================

function Test-Prerequisites {

    Write-Log "Running prerequisite checks..."

    # Admin check
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Script must be run as Administrator." "ERROR"
        return $false
    }

    # PowerShell version
    if ($PSVersionTable.PSVersion -lt [Version]"5.1") {
        Write-Log "PowerShell 5.1 or later is required." "ERROR"
        return $false
    }

    # Windows build
    $build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
    if ([int]$build -lt 17763) {
        Write-Log "Windows build 17763 (Windows 10 1809) or newer required." "ERROR"
        return $false
    }

    Write-Log "Prerequisite checks passed." "SUCCESS"
    return $true
}

# ============================
# WinGet Client Module
# ============================

function Install-WinGetClientModule {

    Write-Log "Checking Microsoft.WinGet.Client module..."

    if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
        Write-Log "Installing Microsoft.WinGet.Client module..."
        Set-PSRepository PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module Microsoft.WinGet.Client -Scope AllUsers -Force -ErrorAction Stop
        Write-Log "Microsoft.WinGet.Client installed." "SUCCESS"
    }
    else {
        Write-Log "Microsoft.WinGet.Client already installed." "SUCCESS"
    }

    return $true
}

# ============================
# Latest Version Detection
# ============================

function ConvertTo-WinGetVersionString {
    param([string]$VersionString)

    if (-not $VersionString) { return $null }
    $v = $VersionString.Trim()
    if ($v.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
        $v = $v.Substring(1)
    }

    # Keep only digits and dots (e.g. "1.8.2101")
    $v = ($v -replace '[^0-9\.]', '')
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v
}

function ConvertTo-VersionOrNull {
    param([string]$VersionString)
    try { return [Version]$VersionString } catch { return $null }
}

function Get-LatestWingetVersionString {
    [CmdletBinding()]
    param([switch]$IncludePrerelease)

    # Primary source: GitHub releases (public)
    try {
        $headers = @{ "User-Agent" = "Install-Winget.Latest.ps1" }
        if ($IncludePrerelease) {
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases?per_page=30" -Headers $headers -ErrorAction Stop
            $release = $releases | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1
        }
        else {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -Headers $headers -ErrorAction Stop
        }

        $tag = $release.tag_name
        $normalized = ConvertTo-WinGetVersionString -VersionString $tag
        if ($normalized) { return $normalized }
    }
    catch {
        Write-Log "Could not query latest winget release version: $_" "WARNING"
    }

    return $null
}

# ============================
# Winget Installation (Version-Aware)
# ============================

function Install-WinGet {
    [CmdletBinding()]
    param(
        [switch]$IncludePrerelease
    )

    Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop

    # Detect existing version
    $oldVersion = $null
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) {
        $oldVersion = (& $cmd.Source --version 2>$null).Trim()
        Write-Log "Detected installed winget version: $oldVersion" "INFO"
    }
    else {
        Write-Log "winget is not currently installed." "INFO"
    }

    # If winget is installed, check if it's already at (or above) the latest version and skip install.
    if ($oldVersion) {
        $installedNorm = ConvertTo-WinGetVersionString -VersionString $oldVersion
        $latestNorm = Get-LatestWingetVersionString -IncludePrerelease:$IncludePrerelease

        if ($installedNorm -and $latestNorm) {
            $installedV = ConvertTo-VersionOrNull -VersionString $installedNorm
            $latestV = ConvertTo-VersionOrNull -VersionString $latestNorm

            if ($installedV -and $latestV) {
                if ($installedV -ge $latestV) {
                    Write-Log "Latest winget version is already installed ($oldVersion). Skipping installation." "SUCCESS"
                    return $true
                }
            }
            else {
                # Fallback to string compare if parsing fails
                if ($installedNorm -eq $latestNorm) {
                    Write-Log "Latest winget version is already installed ($oldVersion). Skipping installation." "SUCCESS"
                    return $true
                }
            }
        }
        elseif (-not $latestNorm) {
            Write-Log "Unable to determine latest winget version online. Proceeding with Repair-WinGetPackageManager." "WARNING"
        }
    }

    # Build parameters
    $params = @{
        Force    = $true
        AllUsers = $true
    }

    if ($IncludePrerelease) {
        $params.IncludePrerelease = $true
        Write-Log "Prerelease channel enabled." "INFO"
    }

    Write-Log "Running Repair-WinGetPackageManager..."
    Repair-WinGetPackageManager @params

    Start-Sleep -Seconds 3

    # Verify version after repair
    $newCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $newCmd) {
        Write-Log "winget installation failed." "ERROR"
        return $false
    }

    $newVersion = (& $newCmd.Source --version 2>$null).Trim()

    if ($oldVersion -and $oldVersion -eq $newVersion) {
        Write-Log "Latest version is already installed ($newVersion)." "SUCCESS"
    }
    else {
        Write-Log "winget installed or upgraded to version: $newVersion" "SUCCESS"
    }

    return $true
}

# ============================
# Final Verification
# ============================

function Test-WinGet {

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Log "winget executable not found." "ERROR"
        return $false
    }

    & $cmd.Source --version | Out-Null
    Write-Log "winget verified successfully." "SUCCESS"
    return $true
}

# ============================
# Main
# ============================

try {
    Write-Log "=== Install-WinGet Started ==="

    if (-not (Test-Prerequisites)) { exit 1 }

    Install-WinGetClientModule | Out-Null
    Install-WinGet -IncludePrerelease:$IncludePrerelease | Out-Null

    if (-not (Test-WinGet)) { exit 1 }

    $duration = (Get-Date) - $script:StartTime
    Write-Log "Completed successfully in $($duration.TotalMinutes.ToString('F2')) minutes." "SUCCESS"
    Write-Log "=== Install-WinGet Completed ==="
    exit 0
}
catch {
    Write-Log "Fatal error: $_" "ERROR"
    exit 1
}
