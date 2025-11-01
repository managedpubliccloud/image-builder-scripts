<#
.SYNOPSIS
    Dynamic software installation script using WinGet API
.DESCRIPTION
    This script dynamically fetches the latest version from WinGet repository and installs it
.PARAMETER PackageIdentifier
    The WinGet package identifier (e.g., "WinDirStat.WinDirStat" or "Microsoft.DotNet.DesktopRuntime")
    IMPORTANT: Identifiers are case-sensitive and must match the format used in the WinGet repository.
.PARAMETER Architecture
    The architecture to install (x64, x86, arm64). Default is x64
.NOTES
    This is a template that can be adapted for any software in the WinGet repository
    Use package names from https://github.com/winget-pkgs/manifests

    There is an issue with this script with packages that have an extra folder of versions - eg https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Microsoft/DotNet/Runtime/9/9.0.7
#>

param(
    [string]$PackageIdentifier = "WinDirStat.WinDirStat",
    [ValidateSet("x64", "x86", "arm64", "neutral")]
    [string]$Architecture = "x64",
    [switch]$WhatIf
)

function mainscript{
    
    # Enhanced package identifier parsing
    $parts = $PackageIdentifier -split '\.'
    if ($parts.Count -lt 2) {
        throw "Package ID must contain at least Publisher and AppName separated by dots"
    }
    
    # Handle different package identifier structures
    $AppPublisher = $parts[0]
    if ($parts.Count -eq 2) {
        $AppName = $parts[1]
        $RootFolderApp = Join-Path -Path "$env:programdata\ETHAN\ImageBuild" -ChildPath "$AppPublisher.$AppName"
    } else {
        # For multi-part identifiers, use the full identifier for folder name
        $AppName = $parts[1..($parts.Count-1)] -join '.'
        $RootFolderApp = Join-Path -Path "$env:programdata\ETHAN\ImageBuild" -ChildPath $PackageIdentifier
    }

    Write-Host "###### Starting $AppPublisher $AppName (Latest) installation script ######"
    
    # Main execution
    try {
        # Create app folder
        if ((Test-Path $RootFolderApp) -eq $false) {
            New-Item -Path $RootFolderApp -ItemType Directory -Force | Out-Null
            Write-Host "Created $RootFolderApp directory"
        }
        
        # Get latest version
        $versionInfo = Get-LatestWinGetVersion -PackageId $PackageIdentifier
        $AppVersion = $versionInfo.Version
        
        # Get installer info
        $installerInfo = Get-InstallerInfo -ManifestPath $versionInfo.ManifestPath -Architecture $Architecture -PackageId $PackageIdentifier
        
        Write-Host "Latest version: $AppVersion"
        Write-Host "Installer URL: $($installerInfo.Url)"
        Write-Host "Installer Type: $($installerInfo.Type)"
        
        # Determine file extension based on installer type
        $fileExtension = switch ($installerInfo.Type) {
            "msi" { ".msi" }
            "exe" { ".exe" }
            "msix" { ".msix" }
            "appx" { ".appx" }
            "zip" { ".zip" }
            default { ".exe" }
        }
        
        $SetupFileName = "$($PackageIdentifier.Replace('.', '_')).$AppVersion$fileExtension"
        $SetupFilePath = Join-Path -Path $RootFolderApp -ChildPath $SetupFileName
        
        Write-Host "Setup file path: $SetupFilePath"
        Write-Host "Installer type: $($installerInfo.Type)"
        Write-Host "Setup file name: $SetupFileName"

        # WhatIf mode check - before downloading
        If ($WhatIf) {
            Write-Host "WhatIf mode enabled. No download or installation will be performed."
            Write-Host "Would download: $($installerInfo.Url)"
            Write-Host "Would install: $SetupFilePath with type: $($installerInfo.Type)"
            Write-Host "###### $PackageIdentifier installation script complete (WhatIf mode) ######"
            exit 0
        }

        # Download installer
        Write-Host "Downloading $SetupFileName to $SetupFilePath"
        Download-FileWithRetry -Url $installerInfo.Url -DestinationPath $SetupFilePath
        
        # Verify download with SHA256 if provided
        if ($installerInfo.Sha256) {
            Write-Host "Verifying file hash..."
            $actualHash = (Get-FileHash -Path $SetupFilePath -Algorithm SHA256).Hash
            if ($actualHash -ne $installerInfo.Sha256) {
                throw "File hash mismatch! Expected: $($installerInfo.Sha256), Actual: $actualHash"
            }
            Write-Host "File hash verified successfully"
        }
        
        # Install based on installer type
        Write-Host "Installing $AppPublisher $AppName $AppVersion"
    
        
        $exitCode = 0
        switch ($installerInfo.Type) {
            "msi" {
                # Check if already installed using ProductCode - using CIM instead of WMI
                if ($installerInfo.ProductCode) {
                    try {
                        # Use Get-CimInstance instead of Get-WmiObject (which is deprecated in newer PowerShell)
                        $installed = Get-CimInstance -ClassName Win32_Product -Filter "IdentifyingNumber='$($installerInfo.ProductCode)'" -ErrorAction SilentlyContinue
                        
                        if ($installed) {
                            Write-Host "Product already installed with ProductCode: $($installerInfo.ProductCode)"
                            Write-Host "###### $PackageIdentifier installation script complete (already installed) ######"
                            exit 0
                        }
                    }
                    catch {
                        # Fall back to registry check if CIM query fails
                        Write-Host "CIM query failed, checking registry instead..."
                        $installed = $false
                        
                        # Check common registry paths for installed software
                        $regPaths = @(
                            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                        )
                        
                        foreach ($path in $regPaths) {
                            $regKey = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
                                    Where-Object { $_.PSChildName -eq $installerInfo.ProductCode -or $_.DisplayName -like "*$AppName*" }
                            if ($regKey) {
                                $installed = $true
                                Write-Host "Product found in registry: $($regKey.DisplayName)"
                                Write-Host "###### $PackageIdentifier installation script complete (already installed) ######"
                                exit 0
                            }
                        }
                    }
                }
                
                $arguments = "/i `"$SetupFilePath`" /quiet /norestart /l*v `"$RootFolderApp\$PackageIdentifier-install.log`""
                Write-Host "Executing: msiexec.exe $arguments"
                $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
                $exitCode = $process.ExitCode
            }
            "exe" {
                # Common silent install arguments - may need adjustment per application
                $arguments = "/S", "/SILENT", "/VERYSILENT", "/Q", "/quiet", "--silent", "/s"
                $installed = $false
                
                foreach ($arg in $arguments) {
                    Write-Host "Trying installer with argument: $arg"
                    try {
                        $process = Start-Process -FilePath $SetupFilePath -ArgumentList $arg -Wait -PassThru -ErrorAction Stop
                        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                            $exitCode = $process.ExitCode
                            $installed = $true
                            Write-Host "Installation succeeded with argument: $arg"
                            break
                        }
                    }
                    catch {
                        Write-Host "Installation attempt failed with argument $arg : $_"
                    }
                }
                
                if (-not $installed) {
                    Write-Host "Warning: Silent installation attempts failed. Trying default installation..."
                    $process = Start-Process -FilePath $SetupFilePath -Wait -PassThru
                    $exitCode = $process.ExitCode
                }
            }
            "msix" {
                Write-Host "Installing MSIX package..."
                try {
                    Add-AppxPackage -Path $SetupFilePath -ErrorAction Stop
                    $exitCode = 0
                }
                catch {
                    Write-Host "MSIX installation failed: $_" -ForegroundColor Red
                    $exitCode = 1
                }
            }
            "appx" {
                Write-Host "Installing APPX package..."
                try {
                    Add-AppxPackage -Path $SetupFilePath -ErrorAction Stop
                    $exitCode = 0
                }
                catch {
                    Write-Host "APPX installation failed: $_" -ForegroundColor Red
                    $exitCode = 1
                }
            }
            "zip" {
                Write-Host "Extracting ZIP archive..."
                try {
                    $extractPath = Join-Path -Path $RootFolderApp -ChildPath "extracted"
                    Expand-Archive -Path $SetupFilePath -DestinationPath $extractPath -Force
                    Write-Host "Extracted to: $extractPath"
                    Write-Host "Note: Manual installation steps may be required for ZIP packages"
                    $exitCode = 0
                }
                catch {
                    Write-Host "ZIP extraction failed: $_" -ForegroundColor Red
                    $exitCode = 1
                }
            }
            default {
                throw "Unsupported installer type: '$($installerInfo.Type)'"
            }
        }
            
            Write-Host "Installation exit code: $exitCode"
            
            # Common exit codes
            switch ($exitCode) {
                0 { Write-Host "Installation completed successfully" }
                3010 { Write-Host "Installation completed successfully - Restart required" }
                1641 { Write-Host "Installation completed successfully - Restart initiated" }
                default { 
                    if ($exitCode -ne 0) {
                        Write-Host "Installation may have failed with exit code: $exitCode"
                    }
                }
            }
            
            Write-Host "$PackageIdentifier installation script complete"
            exit $exitCode
    }
    catch {
        Write-Host "Error during installation: $_" -ForegroundColor Red
        Write-Host "$PackageIdentifier installation script failed"
        exit 1
    }

}


# Function to get latest version from WinGet API
function Get-LatestWinGetVersion {
    param(
        [string]$PackageId
    )
    
    try {
        # Split package ID for folder structure
        $parts = $PackageId -split '\.'
        
        # Handle different package identifier structures
        switch ($parts.Count) {
            2 {
                # Simple two-part identifier like "WinDirStat.WinDirStat"
                Write-Host "Fetching latest version for two-part identifier: $PackageId"
                $publisher = $parts[0]
                $appName = $parts[1]
                $firstLetter = $publisher.Substring(0,1).ToLower()
                Write-Host "Publisher: `t$publisher`nApp Name: `t$appName"
        
                # Get the package folder from WinGet API
                $apiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$firstLetter/$publisher/$appName"
                Write-Host "Checking WinGet API: $apiUrl"
                $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
                
                # Get all version folders and sort to find latest
                $versions = $response | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name
                
                # Get the latest version using enhanced sorting
                $versionInfo = Get-LatestVersionFromList -Versions $versions -PackageId $PackageId
                $latestVersion = $versionInfo.Latest
                Write-Host "Found latest version: $latestVersion"
                
                return @{
                    Version = $latestVersion
                    ManifestPath = "manifests/$firstLetter/$publisher/$appName/$latestVersion"
                }
            }
            3 {
                # Three-part identifier like "Microsoft.DotNet.DesktopRuntime"
                

                Write-Host "Fetching latest version for three-part identifier: $PackageId"
                $publisher = $parts[0]
                $department = $parts[1]
                $appName = $parts[2]
                $firstLetter = $publisher.Substring(0,1).ToLower()
                Write-Host "Publisher: `t$publisher`nDepartment: `t$department`nApp Name: `t$appName"

                # Get the package folder from WinGet API
                $apiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$firstLetter/$publisher/$department/$appName"
                Write-Host "Checking WinGet API: $apiUrl"
                $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
                
                # Get all version folders and sort to find latest
                $versions = $response | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name
                
                # Get the latest version using enhanced sorting
                $versionInfo = Get-LatestVersionFromList -Versions $versions -PackageId $PackageId
                $latestVersion = $versionInfo.Latest
                Write-Host "Found latest version: $latestVersion"
                
                return @{
                    Version = $latestVersion
                    ManifestPath = "manifests/$firstLetter/$publisher/$department/$appName/$latestVersion"
                }
            }
            4 {
                # Four-part identifier like "Microsoft.Azure.Storage.Explorer"
                Write-Host "Fetching latest version for four-part identifier: $PackageId"
                $publisher = $parts[0]
                $department1 = $parts[1]
                $department2 = $parts[2]
                $appName = $parts[3]
                $firstLetter = $publisher.Substring(0,1).ToLower()
                Write-Host "Publisher: `t$publisher`nDepartment: `t$department1/$department2`nApp Name: `t$appName"

                # Get the package folder from WinGet API
                $apiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$firstLetter/$publisher/$department1/$department2/$appName"
                Write-Host "Checking WinGet API: $apiUrl"
                $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
                
                # Get all version folders and sort to find latest
                $versions = $response | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name
                
                # Get the latest version using enhanced sorting
                $versionInfo = Get-LatestVersionFromList -Versions $versions -PackageId $PackageId
                $latestVersion = $versionInfo.Latest
                Write-Host "Found latest version: $latestVersion"
                
                return @{
                    Version = $latestVersion
                    ManifestPath = "manifests/$firstLetter/$publisher/$department1/$department2/$appName/$latestVersion"
                }
            }
            
            default {
                # Handle complex identifiers with 5+ parts
                Write-Host "Fetching latest version for multi-part identifier: $PackageId"
                $publisher = $parts[0]
                $appParts = $parts[1..($parts.Count-1)]
                $folderStructure = $appParts -join '/'
                $firstLetter = $publisher.Substring(0,1).ToLower()
                Write-Host "Publisher: `t$publisher`nFolder Structure: `t$folderStructure"

                # Get the package folder from WinGet API
                $apiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$firstLetter/$publisher/$folderStructure"
                Write-Host "Checking WinGet API: $apiUrl"
                $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
                
                # Get all version folders and sort to find latest
                $versions = $response | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name
                
                # Get the latest version using enhanced sorting
                $versionInfo = Get-LatestVersionFromList -Versions $versions -PackageId $PackageId
                $latestVersion = $versionInfo.Latest
                Write-Host "Found latest version: $latestVersion"
                
                return @{
                    Version = $latestVersion
                    ManifestPath = "manifests/$firstLetter/$publisher/$folderStructure/$latestVersion"
                }
            }
        }

    }
    catch {
        Write-Host "Error getting latest version: $_"
        throw
    }
}

function Get-LatestVersionFromList {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Versions,
        
        [Parameter(Mandatory = $false)]
        [string]$PackageId = "Package"
    )
    
    Write-Host "Found versions: $($Versions -join ', ')"
    
    # Enhanced version sorting to handle single digits and preview versions
    $sortedVersions = @()
    $semanticVersions = @()
    $otherVersions = @()
    
    foreach ($version in $Versions) {
        try {
            # Handle single digit versions and preview versions
            if ($version -match '^\d+$') {
                # Single digit version like "9" -> treat as "9.0.0"
                $semVer = [Version]"$version.0.0"
                $semanticVersions += @{
                    Original = $version
                    Parsed = $semVer
                    Priority = 1
                }
            }
            elseif ($version -match '^\d+\.\d+') {
                # Standard semantic version
                $semVer = [Version]$version
                $semanticVersions += @{
                    Original = $version
                    Parsed = $semVer
                    Priority = 1
                }
            }
            else {
                # Non-numeric versions like "Preview"
                $otherVersions += @{
                    Original = $version
                    Priority = 0
                }
            }
        }
        catch {
            # Fallback for any parsing errors
            $otherVersions += @{
                Original = $version
                Priority = 0
            }
        }
    }
    
    # Sort semantic versions by parsed version, then add other versions
    $sortedSemantic = $semanticVersions | Sort-Object { $_.Parsed } -Descending | ForEach-Object { $_.Original }
    $sortedOther = $otherVersions | Sort-Object { $_.Original } -Descending | ForEach-Object { $_.Original }
    
    # Combine: semantic versions first, then other versions
    $sortedVersions = $sortedSemantic + $sortedOther
    
    if ($sortedVersions.Count -eq 0) {
        throw "No versions found for $PackageId - note API is case sensitive."
    }
    
    $latestVersion = $sortedVersions[0]
    
    # Return both the latest version and the full sorted list
    return @{
        Latest = $latestVersion
        AllVersions = $sortedVersions
        SemanticVersions = $sortedSemantic
        OtherVersions = $sortedOther
    }
}



# Function to get installer info from manifest
function Get-InstallerInfo {
    param(
        [string]$ManifestPath,
        [string]$Architecture,
        [string]$PackageId
    )
    
    try {
        # Extract package identifier from manifest path if not provided
        if (-not $PackageId) {
            $pathParts = $ManifestPath -split '/'
            if ($pathParts.Count -ge 5) {
                $publisher = $pathParts[2]
                $appParts = $pathParts[3..($pathParts.Count-2)]
                $PackageId = "$publisher.$($appParts -join '.')"
            } else {
                throw "Cannot extract package ID from manifest path: $ManifestPath"
            }
        }
        
        # Get installer manifest file
        $installerManifestUrl = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/$ManifestPath/$PackageId.installer.yaml"
        Write-Host "Fetching installer manifest: $installerManifestUrl"
        
        $manifestContent = Invoke-RestMethod -Uri $installerManifestUrl -ErrorAction Stop
        
        # Parse YAML content with regex patterns
        $lines = $manifestContent -split "`n"
        
        $installers = @()
        $currentInstaller = @{}
        $inInstaller = $false
        
        foreach ($line in $lines) {
            # Trim the line to handle various whitespace patterns
            $line = $line.Trim()
            
            # More robust pattern matching for architecture
            if ($line -match "^-\s*Architecture:\s*(.+)") {
                if ($currentInstaller.Count -gt 0) {
                    $installers += $currentInstaller
                }
                $currentInstaller = @{ Architecture = $matches[1].Trim() }
                $inInstaller = $true
            }
            # More robust pattern matching for installer properties
            elseif ($inInstaller -and $line -match "^\s*InstallerUrl:\s*(.+)") {
                $currentInstaller.Url = $matches[1].Trim()
            }
            elseif ($inInstaller -and $line -match "^\s*InstallerType:\s*(.+)") {
                $currentInstaller.Type = $matches[1].Trim()
            }
            elseif ($inInstaller -and $line -match "^\s*InstallerSha256:\s*(.+)") {
                $currentInstaller.Sha256 = $matches[1].Trim()
            }
            elseif ($inInstaller -and $line -match "^\s*ProductCode:\s*(.+)") {
                $currentInstaller.ProductCode = $matches[1].Trim()
            }
        }
        
        # Add last installer
        if ($currentInstaller.Count -gt 0) {
            $installers += $currentInstaller
        }
        
        # Find installer for requested architecture
        $installer = $installers | Where-Object { $_.Architecture -eq $Architecture } | Select-Object -First 1
        
        if (-not $installer) {
            # Fallback to neutral architecture
            $installer = $installers | Where-Object { $_.Architecture -eq "neutral" } | Select-Object -First 1
        }
        
        if (-not $installer) {
            throw "No installer found for architecture: $Architecture"
        }
        
        # If installer type is missing or empty, detect from URL
        if (-not $installer.Type -or $installer.Type -eq "") {
            Write-Host "Installer type not specified in manifest. Detecting from URL..."
            if ($installer.Url -match "\.msi$") {
                $installer.Type = "msi"
                Write-Host "Detected installer type: msi"
            }
            elseif ($installer.Url -match "\.exe$") {
                $installer.Type = "exe"
                Write-Host "Detected installer type: exe"
            }
            elseif ($installer.Url -match "\.msix$") {
                $installer.Type = "msix"
                Write-Host "Detected installer type: msix"
            }
            elseif ($installer.Url -match "\.appx$") {
                $installer.Type = "appx"
                Write-Host "Detected installer type: appx"
            }
            elseif ($installer.Url -match "\.zip$") {
                $installer.Type = "zip"
                Write-Host "Detected installer type: zip"
            }
            else {
                $installer.Type = "exe"
                Write-Host "Unable to detect, defaulting to installer type: exe"
            }
        }
        
        return $installer
    }
    catch {
        Write-Host "Error getting installer info: $_"
        throw
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
    $destinationDir = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -Path $destinationDir)) {
        New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
        Write-Host "Created destination directory: $destinationDir"
    }
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $attempt++
            Write-Host "Download attempt $attempt of $MaxRetries"
            
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
            
            Write-Host "Successfully downloaded file"
            return $true
        }
        catch {
            Write-Host "Download attempt $attempt failed: $_"
            if ($attempt -eq $MaxRetries) {
                throw "Failed to download after $MaxRetries attempts.URL: $Url"
            }
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

$output = mainscript
return $output