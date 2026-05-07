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

    Designed to run reliably in unattended/headless environments such as
    Azure Packer image builds, AVD image templates, and CI pipelines.

.PARAMETER IncludePrerelease
    Install the latest prerelease version of winget.

.PARAMETER LogPath
    Optional path to the log file.
    Default: %TEMP%\Install-WingetV2.log

.PARAMETER WinGetVerifyRetryCount
    Number of times to retry winget detection after repair.
    Default: 10

.PARAMETER WinGetVerifyRetryDelay
    Seconds to wait between each retry.
    Default: 5

.PARAMETER ModuleInstallTimeoutSec
    Maximum seconds to wait for Microsoft.WinGet.Client module installation from PSGallery.
    If the install exceeds this limit the script aborts with an error rather than hanging indefinitely.
    Default: 180

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
    [string]$LogPath = (Join-Path $env:TEMP "Install-WingetV2.log"),
    [ValidateRange(1, 60)][int]$WinGetVerifyRetryCount = 10,
    [ValidateRange(1, 60)][int]$WinGetVerifyRetryDelay = 5,
    [ValidateRange(30, 600)][int]$ModuleInstallTimeoutSec = 180
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

    # --- FIX: Ensure NuGet provider is present first ---
    # Packer/SYSTEM context often lacks NuGet, causing Install-Module to stall
    # waiting for an interactive prompt that never comes.
    Write-Log "Ensuring NuGet package provider is available..."
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Log "NuGet provider ready." "SUCCESS"
    }
    catch {
        Write-Log "NuGet provider install failed: $_" "WARNING"
        # Non-fatal — continue; PSGallery may still work if NuGet was already present.
    }

    # --- FIX: Trust PSGallery with Stop so failures are caught, not silently skipped ---
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        Write-Log "PSGallery set to Trusted." "SUCCESS"
    }
    catch {
        Write-Log "Could not set PSGallery to Trusted: $_" "WARNING"
        # Non-fatal — the repo may already be trusted or module may already be installed.
    }

    if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
        Write-Log "Installing Microsoft.WinGet.Client module (timeout: ${ModuleInstallTimeoutSec}s)..."

        # Run Install-Module in a background job so we can enforce a hard timeout.
        # In headless AVD image builds, PSGallery can be slow or unresponsive and
        # Install-Module has no built-in -TimeoutSec parameter.
        $job = Start-Job -ScriptBlock {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module Microsoft.WinGet.Client `
                -Repository PSGallery `
                -Scope AllUsers `
                -Force `
                -AllowClobber `
                -Confirm:$false `
                -ErrorAction Stop
        }

        $completed = Wait-Job -Job $job -Timeout $ModuleInstallTimeoutSec
        if (-not $completed) {
            Stop-Job  -Job $job
            Remove-Job -Job $job -Force
            Write-Log "Microsoft.WinGet.Client install timed out after ${ModuleInstallTimeoutSec}s." "ERROR"
            throw "Module install timed out - PSGallery may be unreachable from this image builder."
        }

        Receive-Job -Job $job -ErrorVariable jobError | Out-Null
        Remove-Job -Job $job -Force
        if ($jobError) {
            Write-Log "Microsoft.WinGet.Client install failed: $jobError" "ERROR"
            throw "Module install failed: $jobError"
        }

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

    # --- NOTE: GitHub API is hit unauthenticated. Azure shared egress IPs can be
    #     rate-limited (HTTP 429). We handle this gracefully: a $null return causes
    #     the caller to proceed with Repair-WinGetPackageManager. ---
    try {
        $headers = @{ "User-Agent" = "Install-Winget.Latest.ps1" }
        if ($IncludePrerelease) {
            $releases = Invoke-RestMethod `
                -Uri "https://api.github.com/repos/microsoft/winget-cli/releases?per_page=30" `
                -Headers $headers `
                -ErrorAction Stop
            $release = $releases | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1
        }
        else {
            $release = Invoke-RestMethod `
                -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" `
                -Headers $headers `
                -ErrorAction Stop
        }

        $tag = $release.tag_name
        $normalized = ConvertTo-WinGetVersionString -VersionString $tag
        if ($normalized) { return $normalized }
    }
    catch {
        Write-Log "Could not query latest winget release version (rate-limit or network issue): $_" "WARNING"
    }

    return $null
}

# ============================
# Direct MSIX Provisioning (PS 5.1 fallback)
# ============================

function Install-WinGetViaMsix {
    param([switch]$IncludePrerelease)

    Write-Log "Provisioning winget via direct MSIX download (PS 5.1 path)..."
    $tempDir = Join-Path $env:TEMP "WinGetMsix"
    New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $savedProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        $headers = @{ "User-Agent" = "Install-Winget.Latest.ps1" }
        if ($IncludePrerelease) {
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases?per_page=10" -Headers $headers -TimeoutSec 30 -ErrorAction Stop
            $release  = $releases | Where-Object { $_.prerelease } | Select-Object -First 1
        }
        else {
            $release  = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -Headers $headers -TimeoutSec 30 -ErrorAction Stop
        }

        $msixUrl    = ($release.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url | Select-Object -First 1
        $licenseUrl = ($release.assets | Where-Object { $_.name -like "*License*.xml" }).browser_download_url | Select-Object -First 1

        if (-not $msixUrl -or -not $licenseUrl) {
            Write-Log "Could not locate winget MSIX bundle or license asset in GitHub release." "ERROR"
            return $false
        }

        $vcLibsPath  = Join-Path $tempDir "VCLibs.appx"
        $xamlPath    = Join-Path $tempDir "UIXaml.appx"
        $msixPath    = Join-Path $tempDir "winget.msixbundle"
        $licensePath = Join-Path $tempDir "License.xml"

        Write-Log "Downloading VCLibs dependency..."
        Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $vcLibsPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop

        Write-Log "Downloading Microsoft.UI.Xaml dependency..."
        Invoke-WebRequest -Uri "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -OutFile $xamlPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop

        Write-Log "Downloading winget MSIX bundle..."
        Invoke-WebRequest -Uri $msixUrl -OutFile $msixPath -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop

        Write-Log "Downloading winget license..."
        Invoke-WebRequest -Uri $licenseUrl -OutFile $licensePath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop

        Write-Log "Running Add-AppxProvisionedPackage..."
        Add-AppxProvisionedPackage -Online `
            -PackagePath $msixPath `
            -DependencyPackagePath $vcLibsPath, $xamlPath `
            -LicensePath $licensePath `
            -ErrorAction Stop | Out-Null

        Write-Log "winget provisioned for all users via MSIX." "SUCCESS"
        return $true
    }
    catch {
        Write-Log "MSIX provisioning failed: $_" "ERROR"
        return $false
    }
    finally {
        $ProgressPreference = $savedProgressPreference
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
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
        $latestNorm    = Get-LatestWingetVersionString -IncludePrerelease:$IncludePrerelease

        if ($installedNorm -and $latestNorm) {
            $installedV = ConvertTo-VersionOrNull -VersionString $installedNorm
            $latestV    = ConvertTo-VersionOrNull -VersionString $latestNorm

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

    # Repair-WinGetPackageManager requires PowerShell 7+ (Core edition).
    # In Windows PowerShell 5.1 try pwsh.exe first, then fall back to direct MSIX provisioning.
    $isWindowsPowerShell = $PSVersionTable.PSEdition -ne 'Core'

    if ($isWindowsPowerShell) {
        Write-Log "Windows PowerShell 5.1 detected - Repair-WinGetPackageManager requires PowerShell 7+." "WARNING"
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwsh) {
            Write-Log "Invoking Repair-WinGetPackageManager via pwsh.exe..."
            $repairCmd = "Import-Module Microsoft.WinGet.Client -Force; Repair-WinGetPackageManager -Force -AllUsers$(if ($IncludePrerelease) { ' -IncludePrerelease' })"
            & $pwsh.Source -NonInteractive -NoProfile -Command $repairCmd
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Repair-WinGetPackageManager via pwsh.exe failed (exit $LASTEXITCODE)." "ERROR"
                return $false
            }
        }
        else {
            Write-Log "pwsh.exe not found - falling back to direct MSIX provisioning..." "WARNING"
            if (-not (Install-WinGetViaMsix -IncludePrerelease:$IncludePrerelease)) {
                return $false
            }
            # Add-AppxProvisionedPackage registers for future user logins, not the current
            # SYSTEM session — Get-Command winget will never succeed here, so return early.
            return $true
        }
    }
    else {
        Write-Log "Running Repair-WinGetPackageManager..."
        Repair-WinGetPackageManager @params
    }

    # --- FIX: Replace fixed Start-Sleep with a retry loop ---
    # AppX registration after Repair-WinGetPackageManager can take variable time,
    # especially on a fresh Packer image. Poll instead of assuming a fixed delay.
    Write-Log "Waiting for winget to become available (up to $($WinGetVerifyRetryCount * $WinGetVerifyRetryDelay)s)..."
    $wingetFound = $false
    for ($i = 1; $i -le $WinGetVerifyRetryCount; $i++) {
        $newCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($newCmd) {
            $wingetFound = $true
            break
        }
        Write-Log "winget not yet detected, retry $i/$WinGetVerifyRetryCount (waiting ${WinGetVerifyRetryDelay}s)..." "INFO"
        Start-Sleep -Seconds $WinGetVerifyRetryDelay
    }

    if (-not $wingetFound) {
        Write-Log "winget installation failed — not found after $($WinGetVerifyRetryCount * $WinGetVerifyRetryDelay)s." "ERROR"
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
        # In image build / SYSTEM context, Add-AppxProvisionedPackage registers winget for
        # future user logins but not the current session — treat a provisioned package as success.
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' }
        if ($provisioned) {
            Write-Log "winget provisioned for all users (available on next user login). Version: $($provisioned.Version)" "SUCCESS"
            return $true
        }
        Write-Log "winget executable not found and package not provisioned." "ERROR"
        return $false
    }

    # --- FIX: Check exit code, not just presence ---
    # winget can be present but broken (e.g. missing AppX registration).
    # Discarding output with Out-Null masked this; now we capture and verify.
    $output = & $cmd.Source --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "winget found but returned exit code $LASTEXITCODE. Output: $output" "ERROR"
        return $false
    }

    Write-Log "winget verified successfully. Version: $($output.Trim())" "SUCCESS"
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
