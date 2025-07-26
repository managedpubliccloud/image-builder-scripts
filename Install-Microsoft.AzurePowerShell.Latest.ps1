<#
.SYNOPSIS
    Azure PowerShell Latest Version installation script
.DESCRIPTION
    This script automatically fetches the latest version of Azure PowerShell from GitHub releases,
    downloads the x64 MSI installer, and performs a silent installation.
.NOTES
    Uses GitHub API to get the latest release information.
    Supports Windows PowerShell 5.1 and PowerShell 7+
#>

# Package information
$AppPublisher = "Microsoft" 
$AppName = "AzurePowerShell"
$Architecture = "x64"

# Script variables
$RootFolder = "$env:programdata\ETHAN\ImageBuild"
$RootFolderApp = Join-Path -Path $RootFolder -ChildPath "$AppPublisher.$AppName"

Write-Host "###### Starting $AppPublisher $AppName (Latest) installation script ######"

# Main execution
try {
    # Create app folder
    if ((Test-Path $RootFolderApp) -eq $false) {
        New-Item -Path $RootFolderApp -ItemType Directory -Force | Out-Null
        Write-Host "Created $RootFolderApp directory"
    }
    
    # Get latest version from GitHub API
    $latestReleaseInfo = Get-LatestAzurePowerShellRelease
    $AppVersion = $latestReleaseInfo.Version
    $DownloadUrl = $latestReleaseInfo.DownloadUrl
    $SetupFileName = $latestReleaseInfo.FileName
    
    Write-Host "Latest version: $AppVersion"
    Write-Host "Download URL: $DownloadUrl"
    Write-Host "Setup file: $SetupFileName"
    
    $SetupFilePath = Join-Path -Path $RootFolderApp -ChildPath $SetupFileName
    
    # Check if already installed (optional - can be commented out for force reinstall)
    $installedVersion = Get-InstalledAzurePowerShellVersion
    if ($installedVersion -and $installedVersion -eq $AppVersion) {
        Write-Host "Azure PowerShell $AppVersion is already installed"
        Write-Host "###### $AppPublisher $AppName installation script complete (already installed) ######"
        exit 0
    }
    
    # Download installer
    Write-Host "Downloading $SetupFileName to $SetupFilePath"
    Download-FileWithRetry -Url $DownloadUrl -DestinationPath $SetupFilePath
    
    # Verify download
    if (-not (Test-Path $SetupFilePath)) {
        throw "Download failed - file not found: $SetupFilePath"
    }
    
    $fileSize = (Get-Item $SetupFilePath).Length
    Write-Host "Downloaded file size: $([math]::Round($fileSize / 1MB, 2)) MB"
    
    # Install MSI
    Write-Host "Installing $AppPublisher $AppName $AppVersion"
    $MSIParams = "/i `"$SetupFilePath`" /quiet /norestart /l*v `"$RootFolderApp\$AppPublisher.$AppName-install.log`""
    Write-Host "Executing: msiexec.exe $MSIParams"
    
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $MSIParams -Wait -PassThru
    $exitCode = $process.ExitCode
    
    Write-Host "Installation exit code: $exitCode"
    
    # Check exit codes
    switch ($exitCode) {
        0 { 
            Write-Host "Installation completed successfully" 
            Write-Host "###### $AppPublisher $AppName installation script complete ######"
        }
        3010 { 
            Write-Host "Installation completed successfully - Restart required" 
            Write-Host "###### $AppPublisher $AppName installation script complete (restart required) ######"
        }
        1641 { 
            Write-Host "Installation completed successfully - Restart initiated" 
            Write-Host "###### $AppPublisher $AppName installation script complete (restart initiated) ######"
        }
        default { 
            Write-Host "Installation may have failed with exit code: $exitCode" -ForegroundColor Yellow
            Write-Host "Check installation log: $RootFolderApp\$AppPublisher.$AppName-install.log"
            Write-Host "###### $AppPublisher $AppName installation script complete (with warnings) ######"
        }
    }
    
    exit $exitCode
}
catch {
    Write-Host "Error during installation: $_" -ForegroundColor Red
    Write-Host "###### $AppPublisher $AppName installation script failed ######"
    exit 1
}

# Function to get latest Azure PowerShell release from GitHub
function Get-LatestAzurePowerShellRelease {
    try {
        Write-Host "Fetching latest Azure PowerShell release from GitHub..."
        
        # GitHub API endpoint for latest release
        $apiUrl = "https://api.github.com/repos/Azure/azure-powershell/releases/latest"
        
        # Add headers for better API handling
        $headers = @{
            'User-Agent' = 'Azure-PowerShell-Installer-Script/1.0'
            'Accept' = 'application/vnd.github.v3+json'
        }
        
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop -TimeoutSec 30
        
        if (-not $response) {
            throw "No response received from GitHub API"
        }
        
        $version = $response.tag_name -replace '^v', ''  # Remove 'v' prefix if present
        Write-Host "Found latest version: $version"
        
        # Find the x64 MSI asset
        $msiAsset = $response.assets | Where-Object { 
            $_.name -match "\.msi$" -and 
            $_.name -match "x64" -and 
            $_.name -notmatch "arm64"
        } | Select-Object -First 1
        
        if (-not $msiAsset) {
            # Fallback: look for any MSI file if x64 specific not found
            $msiAsset = $response.assets | Where-Object { 
                $_.name -match "\.msi$" 
            } | Select-Object -First 1
        }
        
        if (-not $msiAsset) {
            throw "No MSI installer found in the latest release"
        }
        
        Write-Host "Found MSI asset: $($msiAsset.name)"
        Write-Host "Asset size: $([math]::Round($msiAsset.size / 1MB, 2)) MB"
        
        return @{
            Version = $version
            DownloadUrl = $msiAsset.browser_download_url
            FileName = $msiAsset.name
            Size = $msiAsset.size
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            throw "GitHub API rate limit exceeded. Please wait before retrying."
        }
        elseif ($_.Exception.Response.StatusCode -eq 404) {
            throw "Azure PowerShell repository not found or no releases available."
        }
        else {
            throw "Failed to get latest release info: $($_.Exception.Message)"
        }
    }
}

# Function to check if Azure PowerShell is already installed
function Get-InstalledAzurePowerShellVersion {
    try {
        # Check registry for installed Azure PowerShell versions
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($path in $regPaths) {
            $installed = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
                        Where-Object { 
                            $_.DisplayName -like "*Azure PowerShell*" -or 
                            $_.DisplayName -like "*Az Cmdlets*" 
                        }
            
            if ($installed) {
                $version = $installed.DisplayVersion
                if ($version) {
                    Write-Host "Found installed Azure PowerShell version: $version"
                    return $version
                }
            }
        }
        
        # Alternative: Check if Az module is available
        try {
            $azModule = Get-Module -Name Az -ListAvailable -ErrorAction SilentlyContinue | 
                       Sort-Object Version -Descending | 
                       Select-Object -First 1
            
            if ($azModule) {
                Write-Host "Found Az module version: $($azModule.Version)"
                return $azModule.Version.ToString()
            }
        }
        catch {
            # Ignore errors from module check
        }
        
        return $null
    }
    catch {
        Write-Host "Error checking installed version: $_" -ForegroundColor Yellow
        return $null
    }
}

# Function to download file with retry
function Download-FileWithRetry {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [int]$MaxRetries = 3
    )
    
    Write-Host "Downloading file from $Url to $DestinationPath with up to $MaxRetries retries"
    
    # Ensure destination directory exists
    $destinationDir = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -Path $destinationDir)) {
        New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
        Write-Host "Created destination directory: $destinationDir"
    }
    
    $attempt = 0
    $baseDelay = 2
    
    while ($attempt -lt $MaxRetries) {
        try {
            $attempt++
            Write-Host "Download attempt $attempt of $MaxRetries"
            
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
            
            # Verify file was created and has content
            if ((Test-Path -Path $DestinationPath) -and ((Get-Item -Path $DestinationPath).Length -gt 0)) {
                Write-Host "Successfully downloaded file (Size: $((Get-Item -Path $DestinationPath).Length) bytes)"
                return $true
            } else {
                throw "Downloaded file is empty or was not created"
            }
        }
        catch {
            Write-Host "Download attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
            
            # Clean up partial download
            if (Test-Path -Path $DestinationPath) {
                Remove-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue
            }
            
            if ($attempt -eq $MaxRetries) {
                Write-Host "All download attempts failed. Last error: $($_.Exception.Message)" -ForegroundColor Red
                throw "Failed to download after $MaxRetries attempts. URL: $Url"
            }
            
            # Exponential backoff with jitter
            $delay = $baseDelay * [Math]::Pow(2, $attempt - 1) + (Get-Random -Minimum 1 -Maximum 3)
            Write-Host "Waiting $delay seconds before next attempt..."
            Start-Sleep -Seconds $delay
        }
    }
    
    return $false
}
