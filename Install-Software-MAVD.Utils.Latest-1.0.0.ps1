<#
.SYNOPSIS
    Install applications using Winget by category or individual package selection.

.DESCRIPTION
    Six ways to run this script:

    1. Install ALL DevOps applications:
       .\Install-Software-MAVD.Utils.Latest-1.0.0.ps1 -DevOps

    2. Install SPECIFIC applications from the DevOps list:
       .\Install-Software-MAVD.Utils.Latest-1.0.0.ps1 -DevOps "Microsoft.VisualStudioCode","Git.Git"

    3. Install ALL ITMgmt applications:
       .\Install-Software-MAVD.Utils.Latest-1.0.0.ps1 -ITMgmt

    4. Install SPECIFIC applications from the ITMgmt list:
       .\Install-Software-MAVD.Utils.Latest-1.0.0.ps1 -ITMgmt "Microsoft.AzureCLI","Notepad++.Notepad++"

    5. Install SPECIFIC applications from either list by Winget ID:
       .\Install-Software-MAVD.Utils.Latest-1.0.0.ps1 -Packages "Git.Git","Microsoft.AzureCLI"

    6. Install ALL applications (DevOps + ITMgmt):
       .\Install-Software-MAVD.Utils.Latest-1.0.0.ps1 -All
#>

param(
    [switch]$All,
    [switch]$DevOps,
    [switch]$ITMgmt,
    [Parameter(Position = 0)]
    [string[]]$Packages
)

# ─────────────────────────────────────────────
# Tools folder configuration — edit as needed
# ─────────────────────────────────────────────

$ToolsPath = "C:\Program Files\Tools"   # Destination folder for portable/CLI tools

# Packages to install into $ToolsPath — portable and CLI tools only
# (packages with traditional installers, e.g. VS Code, Git, Chrome, should NOT be listed here)
$ToolsPackages = @(
    "OpenTofu.Tofu",
    "FluxCD.Flux",
    "Helm.Helm",
    "Microsoft.Sysinternals.Suite",
    "Microsoft.Sysinternals.PsTools",
    "Microsoft.Sysinternals.RDCMan"
)

# ─────────────────────────────────────────────
# Package Bundles — edit these lists as needed
# ─────────────────────────────────────────────

$DevOpsPackages = @(
    "Microsoft.VisualStudioCode",    # VS Code
    "Git.Git",                       # Git
    "OpenTofu.Tofu",                 # OpenTofu (Terraform fork)
    "FluxCD.Flux",                   # Flux CLI (GitOps tool)
    "Helm.Helm"                      # Helm CLI (Kubernetes package manager)
)

$ITMgmtPackages = @(
    "Microsoft.Sysinternals.Suite",         # Sysinternals Suite (Procmon, etc.)
    "Microsoft.Sysinternals.PsTools",       # PsTools Suite (PsExec, etc.)
    "Microsoft.Sysinternals.RDCMan"         # Remote Desktop Connection Manager
)

# Combined reference list (used for -Packages lookup)
$AllPackages = $DevOpsPackages + $ITMgmtPackages

# ─────────────────────────────────────────────
# Logging Setup
# ─────────────────────────────────────────────

$LogFolder = "C:\Windows\System32\config\systemprofile\AppData\Local\Ethan"
$LogFile   = Join-Path $LogFolder "Install-Software-MAVD.Utils.Latest_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry     = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry -Encoding UTF8
    switch ($Level) {
        "INFO"    { Write-Host $entry -ForegroundColor White }
        "WARN"    { Write-Host $entry -ForegroundColor DarkYellow }
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
    }
}

# Create log folder if it doesn't exist
if (-not (Test-Path $LogFolder)) {
    try {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
        Write-Host "[INFO] Log folder created: $LogFolder" -ForegroundColor Cyan
    } catch {
        Write-Warning "Could not create log folder '$LogFolder': $_"
        Write-Warning "Falling back to TEMP folder for logging."
        $LogFolder = $env:TEMP
        $LogFile   = Join-Path $LogFolder "Install-Software-MAVD.Utils.Latest_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
    }
}

# Log header
@"
================================================================
  Install-Software-MAVD.Utils.Latest-1.0.0.ps1  —  Run started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  User   : $env:USERNAME
  Host   : $env:COMPUTERNAME
  Log    : $LogFile
================================================================
"@ | Add-Content -Path $LogFile -Encoding UTF8

Write-Host "`nLogging to: $LogFile`n" -ForegroundColor Cyan

# ─────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────

# Check 1: SYSTEM account
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentIdentity.IsSystem) {
    Write-Log "Script must be run as SYSTEM. Current identity: $($currentIdentity.Name)" "ERROR"
    Write-Host "ERROR: This script must run as NT AUTHORITY\SYSTEM (current: $($currentIdentity.Name)). Exiting." -ForegroundColor Red
    exit 1
}
Write-Log "Running as SYSTEM: confirmed." "INFO"

# Check 2: Elevated (Administrator)
if (-not ([Security.Principal.WindowsPrincipal]$currentIdentity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run elevated (Administrator)." "ERROR"
    Write-Host "ERROR: This script must be run elevated. Exiting." -ForegroundColor Red
    exit 1
}
Write-Log "Running elevated: confirmed." "INFO"

# Check 3: PowerShell 7+ (Core) required — Microsoft.WinGet.Client cmdlets do not support Windows PowerShell 5.1
if ($PSVersionTable.PSEdition -ne 'Core') {
    Write-Log "Windows PowerShell $($PSVersionTable.PSVersion) detected. Microsoft.WinGet.Client requires PowerShell 7+." "WARN"
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        Write-Log "Relaunching script under pwsh.exe (PowerShell 7+)..." "INFO"
        Write-Host "Relaunching under PowerShell 7 (pwsh.exe)..." -ForegroundColor Cyan
        $scriptArgs = $MyInvocation.BoundParameters.GetEnumerator() |
            ForEach-Object { if ($_.Value -is [switch]) { "-$($_.Key)" } else { "-$($_.Key)", $_.Value } }
        & $pwsh.Source -NonInteractive -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path @scriptArgs
        exit $LASTEXITCODE
    } else {
        Write-Log "pwsh.exe not found. Run this script using PowerShell 7+: pwsh.exe -File Install-Software-MAVD.Utils.Latest-1.0.0.ps1" "ERROR"
        Write-Host "ERROR: This script requires PowerShell 7+. Install it from https://aka.ms/powershell and rerun with pwsh.exe." -ForegroundColor Red
        exit 1
    }
}
Write-Log "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)): confirmed." "INFO"

# Check 4: Microsoft.WinGet.Client module
if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
    Write-Log "Microsoft.WinGet.Client module not found — run Install-Winget.Latest.ps1 first." "ERROR"
    Write-Host "ERROR: Microsoft.WinGet.Client module is not installed. Exiting." -ForegroundColor Red
    exit 1
}
Write-Log "Microsoft.WinGet.Client module found." "INFO"

# ─────────────────────────────────────────────
# Build the install list based on the parameters
# ─────────────────────────────────────────────

$List = @()

# ── Mode 1: -All ──────────────────────────────
# Installs every package from both bundles
if ($All) {
    Write-Host "Mode: Install ALL packages (DevOps + ITMgmt)" -ForegroundColor Cyan
    Write-Log "Mode: -All selected" "INFO"
    $List = $AllPackages
}

# ── Mode 2 & 3: -DevOps ───────────────────────
# -DevOps alone     → install the full DevOps bundle
# -DevOps "a","b"   → install only those specific IDs from the DevOps bundle
elseif ($DevOps) {
    if ($Packages) {
        # Specific packages requested — validate each one is in the DevOps bundle
        Write-Host "Mode: Install SPECIFIC packages from the DevOps bundle" -ForegroundColor Cyan
        Write-Log "Mode: -DevOps with specific packages: $($Packages -join ', ')" "INFO"
        foreach ($pkg in $Packages) {
            if ($DevOpsPackages -contains $pkg) {
                $List += $pkg
            } else {
                Write-Host "  [SKIP] '$pkg' is not in the DevOps bundle." -ForegroundColor DarkYellow
                Write-Log "Skipped '$pkg' — not found in DevOps bundle." "WARN"
            }
        }
    } else {
        # No specific packages — install the whole DevOps bundle
        Write-Host "Mode: Install ALL DevOps packages" -ForegroundColor Cyan
        Write-Log "Mode: -DevOps selected (full bundle)" "INFO"
        $List = $DevOpsPackages
    }
}

# ── Mode 4 & 5: -ITMgmt ───────────────────────
# -ITMgmt alone     → install the full ITMgmt bundle
# -ITMgmt "a","b"   → install only those specific IDs from the ITMgmt bundle
elseif ($ITMgmt) {
    if ($Packages) {
        # Specific packages requested — validate each one is in the ITMgmt bundle
        Write-Host "Mode: Install SPECIFIC packages from the ITMgmt bundle" -ForegroundColor Cyan
        Write-Log "Mode: -ITMgmt with specific packages: $($Packages -join ', ')" "INFO"
        foreach ($pkg in $Packages) {
            if ($ITMgmtPackages -contains $pkg) {
                $List += $pkg
            } else {
                Write-Host "  [SKIP] '$pkg' is not in the ITMgmt bundle." -ForegroundColor DarkYellow
                Write-Log "Skipped '$pkg' — not found in ITMgmt bundle." "WARN"
            }
        }
    } else {
        # No specific packages — install the whole ITMgmt bundle
        Write-Host "Mode: Install ALL ITMgmt packages" -ForegroundColor Cyan
        Write-Log "Mode: -ITMgmt selected (full bundle)" "INFO"
        $List = $ITMgmtPackages
    }
}

# ── Mode 6: -Packages only ────────────────────
# Picks matching IDs from either bundle (DevOps or ITMgmt)
elseif ($Packages) {
    Write-Host "Mode: Install SPECIFIC packages from any bundle" -ForegroundColor Cyan
    Write-Log "Mode: -Packages only: $($Packages -join ', ')" "INFO"
    foreach ($pkg in $Packages) {
        if ($AllPackages -contains $pkg) {
            $List += $pkg
        } else {
            Write-Host "  [SKIP] '$pkg' was not found in the DevOps or ITMgmt bundle." -ForegroundColor DarkYellow
            Write-Log "Skipped '$pkg' — not found in any bundle." "WARN"
        }
    }
}

# ── No valid parameters provided ──────────────
else {
    Write-Log "No parameters provided — script exited." "WARN"
    Write-Warning @"

No parameters provided. Usage:

  -DevOps                              Install all DevOps applications
  -DevOps "Slack.Slack","Git.Git"      Install specific apps from DevOps list
  -ITMgmt                              Install all ITMgmt applications
  -ITMgmt "PuTTY.PuTTY","WinSCP.WinSCP"  Install specific apps from ITMgmt list
  -Packages "Google.Chrome","Git.Git"  Install specific apps from either list
  -All                                 Install all applications (DevOps + ITMgmt)
"@
    return
}

# ─────────────────────────────────────────────
# Guard: nothing to install after filtering
# ─────────────────────────────────────────────

if ($List.Count -eq 0) {
    Write-Log "No valid packages to install after filtering — exiting." "WARN"
    Write-Host "`nNo valid packages to install. Exiting." -ForegroundColor Red
    return
}

# ─────────────────────────────────────────────
# Show what will be installed and confirm
# ─────────────────────────────────────────────

Write-Host "`n===== Packages to be installed =====" -ForegroundColor Cyan
$List | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
Write-Host "====================================`n" -ForegroundColor Cyan
Write-Log "Packages queued: $($List -join ', ')" "INFO"

Write-Log "Starting installation of $($List.Count) package(s)." "INFO"

# ─────────────────────────────────────────────
# Import WinGet module
# ─────────────────────────────────────────────

Write-Log "Importing Microsoft.WinGet.Client module..." "INFO"
try {
    Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
    Write-Log "Microsoft.WinGet.Client imported successfully." "INFO"
} catch {
    Write-Log "Failed to import Microsoft.WinGet.Client: $_" "ERROR"
    Write-Host "ERROR: Could not import Microsoft.WinGet.Client module. Exiting." -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────
# Ensure Tools folder exists
# ─────────────────────────────────────────────

if (-not (Test-Path $ToolsPath)) {
    try {
        New-Item -Path $ToolsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Log "Created Tools folder: $ToolsPath" "INFO"
        Write-Host "Created Tools folder: $ToolsPath" -ForegroundColor Cyan
    } catch {
        Write-Log "Failed to create Tools folder '$ToolsPath': $_" "ERROR"
        Write-Host "ERROR: Could not create Tools folder '$ToolsPath'. Exiting." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Log "Tools folder already exists: $ToolsPath" "INFO"
}

# ─────────────────────────────────────────────
# Install loop
# ─────────────────────────────────────────────

$Results = @()

foreach ($App in $List) {
    Write-Host "`nInstalling $App..." -ForegroundColor Yellow
    Write-Log "Installing: $App" "INFO"

    # ── Helm.Helm: winget CLI to TEMP, then copy helm.exe to Tools folder ──
    if ($App -eq 'Helm.Helm') {
        $appStart = Get-Date
        try {
            winget install Helm.Helm --location $env:TEMP --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -ne 0) { throw "winget exited with code $LASTEXITCODE" }
            Copy-Item -Path (Join-Path $env:TEMP 'windows-amd64\helm.exe') -Destination (Join-Path $ToolsPath 'helm.exe') -Force -ErrorAction Stop
            $duration    = (Get-Date) - $appStart
            $durationStr = "{0}m {1}s" -f [int]$duration.TotalMinutes, $duration.Seconds
            Write-Host "  ✔ $App — installation successful. ($durationStr)" -ForegroundColor Green
            Write-Log "$App — installation successful. ($durationStr)" "SUCCESS"
            $Results += [PSCustomObject]@{ Package = $App; Status = "SUCCESS"; Duration = $durationStr }
        } catch {
            $duration    = (Get-Date) - $appStart
            $durationStr = "{0}m {1}s" -f [int]$duration.TotalMinutes, $duration.Seconds
            Write-Host "  ✘ $App — installation failed: $_ ($durationStr)" -ForegroundColor Red
            Write-Log "$App — installation failed: $_ ($durationStr)" "ERROR"
            $Results += [PSCustomObject]@{ Package = $App; Status = "FAILED"; Duration = $durationStr }
        }
        continue
    }

    $appStart     = Get-Date
    $wingetResult = $null
    $installParams = @{
        Id            = $App
        Mode          = 'Silent'
        MatchOption   = 'EqualsCaseInsensitive'
        ErrorAction   = 'Stop'
    }
    if ($ToolsPackages -contains $App) {
        $installParams['Location'] = $ToolsPath
        Write-Log "Installing $App to Tools folder: $ToolsPath" "INFO"
    }
    try {
        $wingetResult = Install-WinGetPackage @installParams
    } catch {
        $duration = (Get-Date) - $appStart
        $durationStr = "{0}m {1}s" -f [int]$duration.TotalMinutes, $duration.Seconds
        Write-Host "  ✘ $App — installation failed: $_ ($durationStr)" -ForegroundColor Red
        Write-Log "$App — installation failed: $_ ($durationStr)" "ERROR"
        $Results += [PSCustomObject]@{ Package = $App; Status = "FAILED"; Duration = $durationStr }
        continue
    }

    $duration    = (Get-Date) - $appStart
    $durationStr = "{0}m {1}s" -f [int]$duration.TotalMinutes, $duration.Seconds

    switch ($wingetResult.Status) {
        'Ok' {
            Write-Host "  ✔ $App — installation successful. ($durationStr)" -ForegroundColor Green
            Write-Log "$App — installation successful. ($durationStr)" "SUCCESS"
            $Results += [PSCustomObject]@{ Package = $App; Status = "SUCCESS"; Duration = $durationStr }
        }
        'RebootRequired' {
            Write-Host "  ✔ $App — installation successful, reboot required to complete. ($durationStr)" -ForegroundColor DarkGreen
            Write-Log "$App — installation successful. Status: REBOOT_REQUIRED. ($durationStr)" "SUCCESS"
            $Results += [PSCustomObject]@{ Package = $App; Status = "REBOOT_REQUIRED"; Duration = $durationStr }
        }
        'AlreadyInstalled' {
            Write-Host "  ℹ $App — ALREADY_INSTALLED or ALREADY_LATEST version. Skipping. ($durationStr)" -ForegroundColor DarkCyan
            Write-Log "$App — Status: ALREADY_INSTALLED or ALREADY_LATEST version. Skipped. ($durationStr)" "INFO"
            $Results += [PSCustomObject]@{ Package = $App; Status = "ALREADY_INSTALLED"; Duration = $durationStr }
        }
        'NoApplicableInstallers' {
            Write-Host "  ✘ $App — installation failed: no applicable installer for this OS/architecture. ($durationStr)" -ForegroundColor Red
            Write-Log "$App — installation failed: no applicable installer for this OS/architecture. ($durationStr)" "ERROR"
            $Results += [PSCustomObject]@{ Package = $App; Status = "FAILED"; Duration = $durationStr }
        }
        'PackageNotFound' {
            Write-Host "  ✘ $App — installation failed: package not found in winget source. ($durationStr)" -ForegroundColor Red
            Write-Log "$App — installation failed: package not found in winget source. ($durationStr)" "ERROR"
            $Results += [PSCustomObject]@{ Package = $App; Status = "FAILED"; Duration = $durationStr }
        }
        default {
            Write-Host "  ✘ $App — installation failed (Status: $($wingetResult.Status)). ($durationStr)" -ForegroundColor Red
            Write-Log "$App — installation failed (Status: $($wingetResult.Status)). ($durationStr)" "ERROR"
            $Results += [PSCustomObject]@{ Package = $App; Status = "FAILED"; Duration = $durationStr }
        }
    }
}

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────

Write-Host "`n===== Installation Summary =====" -ForegroundColor Cyan
$Results | Format-Table -AutoSize
Write-Host "================================`n" -ForegroundColor Cyan

$Results | Format-Table -AutoSize | Out-String | Add-Content -Path $LogFile -Encoding UTF8

Write-Log "─── Summary ───" "INFO"
foreach ($r in $Results) {
    $lvl = switch ($r.Status) {
        "SUCCESS"          { "SUCCESS" }
        "REBOOT_REQUIRED"  { "SUCCESS" }
        "ALREADY_INSTALLED"{ "INFO" }
        default            { "ERROR" }
    }
    Write-Log "$($r.Package) → $($r.Status)" $lvl
}

$successCount = ($Results | Where-Object { $_.Status -in @("SUCCESS", "REBOOT_REQUIRED") }).Count
$alreadyCount = ($Results | Where-Object { $_.Status -eq "ALREADY_INSTALLED" }).Count
$failCount    = ($Results | Where-Object { $_.Status -eq "FAILED" }).Count

Write-Log "Run complete — Installed: $successCount | Already present: $alreadyCount | Failed: $failCount" "INFO"
Write-Log "Log saved to: $LogFile" "INFO"
Write-Host "Log saved to: $LogFile`n" -ForegroundColor Cyan
