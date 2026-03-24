<#
.Synopsis
   MAVD OpsScript Installer
.DESCRIPTION
   Install specified software
   Verifies installation
   Updates local software register with status
   IMPORTANT: Do not duplicate - always get a clean template from the source repo: https://dev.azure.com/eCorpSystems/Ethan.MAVD.Builder/_git/Ethan.MAVD.Builder.Software
#>

# Package information
$AppPublisher   = "RegionalSettings" 
$AppName        = "EN-AU"
$AppVersion     = "Latest"
$AppSetupFile   = ""
$Params         = ""
$TestPaths      = @(
                    "C:\ProgramData\ETHAN\SWPackages\RegionalSettings.EN-AU"
                   )        # Verify the regional settings XML file was written successfully
$CustID         = ""        # Specify customer ID for private packages, do not specify for public
$ScriptType     = "Public"  # Public or Private - determines URI root and error return behavior
$ScriptVersion  = "1.0.0"   # This script version
$TestLab        = $true     # Specify $true to enable test lab URI for Private packages

# URI Root Override - optional, specify for non-standard download locations
# $URIRootOverride = "https://stSomeOtherName1.blob.core.windows.net/SomeFolder"

#========================================================================================================# 
#    Main Script Functions                                                                               #
#========================================================================================================# 

Function MainScript {
    Write-LogEntry -Message "Starting execution, log file: $LogFilePath" -Level Info

    # Determine URI Root
    $uriResult = Get-PackageURIRoot -ScriptType $ScriptType -CustID $CustID -TestLab $TestLab -URIRootOverride $URIRootOverride
    if (-not $uriResult.Success) {
        Write-LogEntry -Message $uriResult.Message -Level Error -EventLog $true
        if ($ScriptType -eq "Public") {
            exit 1
        }
        return @{ Success = $false; Severity = "Error"; Message = $uriResult.Message; Data = "" }
    }
    $URIRoot = $uriResult.Data
    Write-LogEntry -Message "URI Root: $URIRoot" -Level Info
    
    # URI Root - the actual file to download           
    $AppURI = "$URIRoot/$AppPublisher.$AppName.$AppVersion/$AppSetupFile"
    $AppURI = $AppURI.ToLower()
    
    # Script variables
    $AppMoniker         = "$AppPublisher.$AppName.$AppVersion"
    $RegistryRoot       = "HKLM:\Software\ETHAN"        
    $RegistryPath       = Join-Path $RegistryRoot -ChildPath "$AppPublisher.$AppName.$AppVersion"
    $RootFolder         = "$env:programdata\ETHAN\SWPackages"
    $RootFolderApp      = Join-Path -Path $RootFolder -ChildPath "$AppPublisher.$AppName"
    $SetupFolderFile    = Join-Path -Path $RootFolderApp -ChildPath $AppSetupFile


    Write-LogEntry "Starting $AppPublisher $AppName ($AppVersion) installation script version $ScriptVersion" -Level Info -EventLog $true
    Write-LogEntry "App: $AppMoniker SetupFile: $AppSetupFile URI: $AppURI RootFolder: $RootFolder RootFolderApp: $RootFolderApp" -Level Info

    # Root folder for app
    if (!(Test-Path $RootFolderApp)) {New-Item -Path $RootFolderApp -ItemType Directory -Force | out-null; Write-LogEntry "Created $RootFolderApp directory" -Level Info} else {Write-LogEntry "$RootFolderApp directory already exists" -Level Info}

    # Apply EN-AU regional settings via PowerShell International cmdlets
    Write-LogEntry "Applying EN-AU regional settings via PowerShell International cmdlets" -Level Info
    try {
        Set-WinSystemLocale -SystemLocale 'en-AU'
        Write-LogEntry "Set-WinSystemLocale en-AU: OK" -Level Info

        Set-WinHomeLocation -GeoId 12
        Write-LogEntry "Set-WinHomeLocation GeoId 12 (Australia): OK" -Level Info

        Set-Culture -CultureInfo 'en-AU'
        Write-LogEntry "Set-Culture en-AU: OK" -Level Info

        Set-WinUserLanguageList -LanguageList 'en-AU' -Force
        Write-LogEntry "Set-WinUserLanguageList en-AU: OK" -Level Info

        # Copy settings to the Welcome Screen and Default User profile so all new users receive EN-AU
        Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
        Write-LogEntry "Copy-UserInternationalSettingsToSystem (WelcomeScreen + NewUser): OK" -Level Info

        Write-LogEntry "EN-AU regional settings applied successfully" -Level Info
    }
    catch {
        $StatusMessage = "Failed to apply EN-AU regional settings. Error: $_"
        Write-LogEntry $StatusMessage -Level Error -EventLog $true
        $result = Update-PackageRegistryStatus -RegistryPath $RegistryPath -Success $false -StatusMessage $StatusMessage -ScriptVersion $ScriptVersion -AppPublisher $AppPublisher -AppName $AppName -AppVersion $AppVersion -AppSetupFile $AppSetupFile -Params $Params -URIRoot $URIRoot -ScriptType $ScriptType
        Write-LogEntry -Message $result.Message -Level Info
        if ($ScriptType -eq "Public") {
            Exit 1
        }
        return @{ Success = $false; Severity = "Error"; Message = $StatusMessage; Data = "" }
    }
        
    # Test paths to verify sucesessful installation
    $result = Test-AppPaths -TestPaths $TestPaths
    if ($result.Success) {
        $AppPaths = $result.Data
        Write-LogEntry -Message $AppPaths.Message -Level $result.Severity
        if ($AppPaths.AllMatch) {
            # Update registry with installation status
            $StatusMessage = "Installation successful, and $($AppPaths.Message)"
            $result = Update-PackageRegistryStatus -RegistryPath $RegistryPath -Success $true -StatusMessage $StatusMessage -ScriptVersion $ScriptVersion -AppPublisher $AppPublisher -AppName $AppName -AppVersion $AppVersion -AppSetupFile $AppSetupFile -Params $Params -URIRoot $URIRoot -ScriptType $ScriptType
            Write-LogEntry -Message $Result.Message -Level info
        } else {
            Write-LogEntry "One or more checks failed" -Level Error
            # Update registry with installation success and file path check failure  status
            $StatusMessage = "Installation successful, but $($AppPaths.Message)"
            $result = Update-PackageRegistryStatus -RegistryPath $RegistryPath -Success $false -StatusMessage $StatusMessage -ScriptVersion $ScriptVersion -AppPublisher $AppPublisher -AppName $AppName -AppVersion $AppVersion -AppSetupFile $AppSetupFile -Params $Params -URIRoot $URIRoot -ScriptType $ScriptType
            $duration = [math]::round(((New-TimeSpan -Start $Global:ScriptStart).TotalSeconds),1)
            Write-LogEntry -Message $$StatusMessage  -Level Error -EventLog $true
            if ($ScriptType -eq "Public") {
                exit 1    
            }
            return @{ Success = $false; Severity = "Error"; Message = $StatusMessage ; Data = "" }
        }
    }
 
    ## Wrap Up ##
    $duration = [math]::round(((New-TimeSpan -Start $Global:ScriptStart).TotalSeconds),1)
    $Message = "Application installed OK. Applications checks passed OK. Duration: $duration seconds"
    Write-LogEntry -Message $Message -Level Info -EventLog $true
    return @{ Success = $true; Severity = "Info"; Message = $Message; Data = "" }
}

#========================================================================================================# 
#    Script Functions                                                                                    #
#========================================================================================================# 

# Add script-specific functions here...

function Get-PackageURIRoot {
    <#
    .SYNOPSIS
        Determines the appropriate URI root for package downloads
    .DESCRIPTION
        Returns the correct URI root based on ScriptType (Public/Private), CustID, TestLab flag, and optional override.
        Follows the hybrid error handling pattern.
    .PARAMETER ScriptType
        "Public" or "Private" - determines which URI root to use
    .PARAMETER CustID
        Customer ID for private packages (required if ScriptType is "Private")
    .PARAMETER TestLab
        If true, uses test lab URI for private packages. Default is false.
    .PARAMETER URIRootOverride
        Optional URI override - if provided, this value is returned directly
    .OUTPUTS
        Hashtable with Success, Severity, Message, and Data (URIRoot string)
    .EXAMPLE
        $result = Get-PackageURIRoot -ScriptType "Private" -CustID "ETST" -TestLab $true
        if ($result.Success) {
            $uriRoot = $result.Data
        }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Public", "Private")]
        [string]$ScriptType,
        
        [Parameter(Mandatory=$false)]
        [string]$CustID,
        
        [Parameter(Mandatory=$false)]
        [bool]$TestLab = $false,
        
        [Parameter(Mandatory=$false)]
        [string]$URIRootOverride
    )
    
    try {
        # Print all parameters for debugging
        $PSBoundParameters.Keys | ForEach-Object { 
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name) Parameter: $_ = $($PSBoundParameters[$_])"
        }
        
        $URIRoot = $null
        
        # Check for override first
        if ($URIRootOverride) {
            $URIRoot = $URIRootOverride
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Using URI override: $URIRoot"
        }
        elseif ($ScriptType -eq "Private" -and $CustID) {
            if ($TestLab) {
                # Private, lab URI
                $URIRoot = "https://stethanmavdswpublicae1.blob.core.windows.net/builder-software-private-media/$($CustID.ToLower())"
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Using private test lab URI for customer: $CustID"
            } else {
                # Private, customer URI
                $URIRoot = "https://st$($CustID.ToLower())avdsharedzrsae1.blob.core.windows.net/avd-software"
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Using private customer URI for customer: $CustID"
            }
        }
        elseif ($ScriptType -eq "Public") {
            # Public URI
            $URIRoot = "https://stethanmavdswpublicae1.blob.core.windows.net/builder-software-media"
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Using public URI"
        }
        else {
            # Invalid configuration
            return @{ 
                Success = $false
                Severity = "Error"
                Message = "$($MyInvocation.MyCommand.Name): Invalid configuration - ScriptType is Private but CustID is missing"
                Data = $null
            }
        }
        
        # Success
        return @{ 
            Success = $true
            Severity = "Info"
            Message = "$($MyInvocation.MyCommand.Name): Determined URI root: $URIRoot"
            Data = $URIRoot
        }
    }
    catch {
        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $_"
        return @{ 
            Success = $false
            Severity = "Error"
            Message = "$($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
            Data = $null
        }
    }
}

function Update-PackageRegistryStatus {
    <#
    .SYNOPSIS
        Updates registry with package installation status
    .DESCRIPTION
        Retrieves current registry values, logs them, and updates Status, StatusDate, and StatusMessage properties.
        Uses Get-RegistryKeyInfo to read and Set-RegistryKeyInfo to write registry data.
        Follows the hybrid error handling pattern.
    .PARAMETER RegistryPath
        Full registry path (e.g., "HKLM:\Software\ETHAN\Windows.RSAT.Latest")
    .PARAMETER Success
        Boolean indicating if installation was successful
    .PARAMETER StatusMessage
        Status message to write to registry
    .PARAMETER ScriptVersion
        Script version to write to registry
    .PARAMETER ControllerScriptVersion
        Optional controller script version to write to registry
    .OUTPUTS
        Hashtable with Success, Severity, Message, and Data fields
    .EXAMPLE
        $result = Update-PackageRegistryStatus -RegistryPath $RegistryPath -Success $true -StatusMessage "Installed successfully" -ScriptVersion "1.0.0"
        Write-LogEntry -Message $result.Message -Level $result.Severity
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$RegistryPath,
        
        [Parameter(Mandatory=$true)]
        [bool]$Success,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$StatusMessage,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptVersion,
        
        [Parameter(Mandatory=$false)]
        [string]$AppPublisher,
        
        [Parameter(Mandatory=$false)]
        [string]$AppName,
        
        [Parameter(Mandatory=$false)]
        [string]$AppVersion,
        
        [Parameter(Mandatory=$false)]
        [string]$AppSetupFile,
        
        [Parameter(Mandatory=$false)]
        [string]$Params,
        
        [Parameter(Mandatory=$false)]
        [string]$URIRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$ScriptType
    )
    
    $VerbosePreference = "SilentlyContinue"

    # Print all parameters for debugging
    $PSBoundParameters.Keys | ForEach-Object { 
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name) Parameter: $_ = $($PSBoundParameters[$_])"
    }

    try {
        # Get current registry values
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Reading current registry values from $RegistryPath"
        $regResult = Get-RegistryKeyInfo -KeyPath $RegistryPath
        
        # Log current registry values
        if ($regResult.Success) {
            Write-LogEntry -Message "$($MyInvocation.MyCommand.Name): Current registry values for $RegistryPath" -Level Info
            foreach ($propName in $regResult.Data.PropertyDetails.Keys) {
                $prop = $regResult.Data.PropertyDetails[$propName]
                Write-LogEntry -Message "  $($prop.Name) = $($prop.Value) (Type: $($prop.Type))" -Level Info
            }
            
            # Start with existing properties
            $propertyDetails = $regResult.Data.PropertyDetails
        } else {
            Write-LogEntry -Message "$($MyInvocation.MyCommand.Name): Registry key does not exist, will create new" -Level Info
            # Create new ordered hashtable
            $propertyDetails = [ordered]@{}
        }
        
        # Update Status property
        $statusValue = if ($Success) { "INSTALLED" } else { "FAILED" }
        if ($propertyDetails.Contains('Status')) {
            $propertyDetails['Status'].Value = $statusValue
        } else {
            $propertyDetails['Status'] = [PSCustomObject]@{
                Name = 'Status'
                Value = $statusValue
                Type = 'String'
            }
        }
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting Status = $statusValue"
        
        # Update StatusDate property
        $dateTimeNow = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        if ($propertyDetails.Contains('StatusDate')) {
            $propertyDetails['StatusDate'].Value = $dateTimeNow
        } else {
            $propertyDetails['StatusDate'] = [PSCustomObject]@{
                Name = 'StatusDate'
                Value = $dateTimeNow
                Type = 'String'
            }
        }
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting StatusDate = $dateTimeNow"
        
        # Update StatusMessage property
        if ($propertyDetails.Contains('StatusMessage')) {
            $propertyDetails['StatusMessage'].Value = $StatusMessage
        } else {
            $propertyDetails['StatusMessage'] = [PSCustomObject]@{
                Name = 'StatusMessage'
                Value = $StatusMessage
                Type = 'String'
            }
        }
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting StatusMessage = $StatusMessage"
        
        # Update ScriptVersion property
        if ($propertyDetails.Contains('ScriptVersion')) {
            $propertyDetails['ScriptVersion'].Value = $ScriptVersion
        } else {
            $propertyDetails['ScriptVersion'] = [PSCustomObject]@{
                Name = 'ScriptVersion'
                Value = $ScriptVersion
                Type = 'String'
            }
        }
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting ScriptVersion = $ScriptVersion"
        
        # Update AppPublisher property if provided
        if ($AppPublisher) {
            if ($propertyDetails.Contains('AppPublisher')) {
                $propertyDetails['AppPublisher'].Value = $AppPublisher
            } else {
                $propertyDetails['AppPublisher'] = [PSCustomObject]@{
                    Name = 'AppPublisher'
                    Value = $AppPublisher
                    Type = 'String'
                }
            }
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting AppPublisher = $AppPublisher"
        }
        
        # Update AppName property if provided
        if ($AppName) {
            if ($propertyDetails.Contains('AppName')) {
                $propertyDetails['AppName'].Value = $AppName
            } else {
                $propertyDetails['AppName'] = [PSCustomObject]@{
                    Name = 'AppName'
                    Value = $AppName
                    Type = 'String'
                }
            }
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting AppName = $AppName"
        }
        
        # Update AppVersion property if provided
        if ($AppVersion) {
            if ($propertyDetails.Contains('AppVersion')) {
                $propertyDetails['AppVersion'].Value = $AppVersion
            } else {
                $propertyDetails['AppVersion'] = [PSCustomObject]@{
                    Name = 'AppVersion'
                    Value = $AppVersion
                    Type = 'String'
                }
            }
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting AppVersion = $AppVersion"
        }
        
        # Update AppSetupFile property if provided
        if ($AppSetupFile) {
            if ($propertyDetails.Contains('AppSetupFile')) {
                $propertyDetails['AppSetupFile'].Value = $AppSetupFile
            } else {
                $propertyDetails['AppSetupFile'] = [PSCustomObject]@{
                    Name = 'AppSetupFile'
                    Value = $AppSetupFile
                    Type = 'String'
                }
            }
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting AppSetupFile = $AppSetupFile"
        }
        
        # Update Params property if provided
        if ($Params) {
            if ($propertyDetails.Contains('Params')) {
                $propertyDetails['Params'].Value = $Params
            } else {
                $propertyDetails['Params'] = [PSCustomObject]@{
                    Name = 'Params'
                    Value = $Params
                    Type = 'String'
                }
            }
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting Params = $Params"
        }
        
        # Update URIRoot property if provided
        if ($URIRoot) {
            if ($propertyDetails.Contains('URIRoot')) {
                $propertyDetails['URIRoot'].Value = $URIRoot
            } else {
                $propertyDetails['URIRoot'] = [PSCustomObject]@{
                    Name = 'URIRoot'
                    Value = $URIRoot
                    Type = 'String'
                }
            }
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting URIRoot = $URIRoot"
        }
        
        # Update ScriptType property if provided
        if ($ScriptType) {
            if ($propertyDetails.Contains('ScriptType')) {
                $propertyDetails['ScriptType'].Value = $ScriptType
            } else {
                $propertyDetails['ScriptType'] = [PSCustomObject]@{
                    Name = 'ScriptType'
                    Value = $ScriptType
                    Type = 'String'
                }
            }
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting ScriptType = $ScriptType"
        }
        
        # Update ControllerScriptVersion property if provided
        if ($ControllerScriptVersion) {
            if ($propertyDetails.Contains('ScriptVersionCTL')) {
                $propertyDetails['ScriptVersionCTL'].Value = $ControllerScriptVersion
            } else {
                $propertyDetails['ScriptVersionCTL'] = [PSCustomObject]@{
                    Name = 'ScriptVersionCTL'
                    Value = $ControllerScriptVersion
                    Type = 'String'
                }
            }
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Setting ScriptVersionCTL = $ControllerScriptVersion"
        }
        
        # Write updated values to registry
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Writing updated values to registry"
        $setResult = Set-RegistryKeyInfo -KeyPath $RegistryPath -PropertyDetails $propertyDetails
        
        if ($setResult.Success) {
            Write-LogEntry -Message "$($MyInvocation.MyCommand.Name): Successfully updated registry with Status=$statusValue, StatusDate=$dateTimeNow" -Level Info
            
            # Return success
            return @{ 
                Success = $true
                Severity = "Info"
                Message = "$($MyInvocation.MyCommand.Name): Successfully updated registry status"
                Data = @{
                    Status = $statusValue
                    StatusDate = $dateTimeNow
                    StatusMessage = $StatusMessage
                    PropertiesSet = $setResult.Data.PropertiesSet
                }
            }
        } else {
            # Set-RegistryKeyInfo failed
            return @{ 
                Success = $false
                Severity = $setResult.Severity
                Message = "$($MyInvocation.MyCommand.Name): Failed to write registry: $($setResult.Message)"
                Data = $null
            }
        }
    }
    catch {
        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $_"
        return @{ 
            Success = $false
            Severity = "Error"
            Message = "$($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
            Data = $null
        }
    }
}

function Test-AppPaths {
    <#
    .SYNOPSIS
        Tests existence of file, folder, and registry paths
    .DESCRIPTION
        Validates an array of paths (files, folders, registry keys, registry properties).
        Automatically detects path type and returns detailed status for each.
        Follows the hybrid error handling pattern.
    .PARAMETER TestPaths
        Array of path strings to test. Can include:
        - File paths (e.g., "C:\Program Files\App\app.exe")
        - Folder paths (e.g., "C:\Scripts")
        - Registry keys (e.g., "HKLM:\Software\Company")
        - Registry properties (e.g., "HKLM:\Software\Company\Version")
    .OUTPUTS
        Hashtable with Success, Severity, Message, and Data fields
        Data contains:
        - Paths: Array of PSCustomObjects with Path, Found, PathType, MatchType, Message
        - AllMatch: Boolean indicating if all paths were found
        - Message: Formatted string showing all paths and their status
    .EXAMPLE
        $paths = @("C:\Scripts", "HKLM:\Software\ETHAN", "C:\test.txt")
        $result = Test-AppPaths -TestPaths $paths
        if ($result.Success -and $result.Data.AllMatch) {
            Write-Host "All paths exist"
        }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [string[]]$TestPaths
    )
    
    # Print all parameters for debugging
    $PSBoundParameters.Keys | ForEach-Object { 
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name) Parameter: $_ = $($PSBoundParameters[$_])"
    }

    try {
        $pathResults = @()
        $allMatch = $true
        $messageLines = @()
        
        foreach ($path in $TestPaths) {
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Testing path: $path"
            
            $isRegistry = $path -match '^HK(LM|CU|CR|U|CC):\\'
            $found = $false
            $pathType = $null
            $message = $null
            
            if ($isRegistry) {
                # Registry path - test if it's a key or property
                if (Test-Path -Path $path) {
                    # It's a registry key
                    $found = $true
                    $pathType = "RegKey"
                    $message = "Registry key exists"
                    Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Registry key found: $path"
                } else {
                    # Check if it's a registry property (parent key + property name)
                    $parentPath = Split-Path -Path $path -Parent
                    $propertyName = Split-Path -Path $path -Leaf
                    
                    if ((Test-Path -Path $parentPath)) {
                        $property = Get-ItemProperty -Path $parentPath -Name $propertyName -ErrorAction SilentlyContinue
                        if ($property) {
                            $found = $true
                            $pathType = "RegProperty"
                            $message = "Registry property exists"
                            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Registry property found: $path"
                        } else {
                            $found = $false
                            $pathType = "RegProperty"
                            $message = "Registry property not found (parent key exists)"
                            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Registry property not found: $path"
                        }
                    } else {
                        $found = $false
                        $pathType = "RegKey"
                        $message = "Registry key not found"
                        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Registry key not found: $path"
                    }
                }
            } else {
                # File system path
                if (Test-Path -Path $path -PathType Container) {
                    $found = $true
                    $pathType = "Folder"
                    $message = "Folder exists"
                    Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Folder found: $path"
                } elseif (Test-Path -Path $path -PathType Leaf) {
                    $found = $true
                    $pathType = "File"
                    $message = "File exists"
                    Write-Verbose -Message "$($MyInvocation.MyCommand.Name): File found: $path"
                } else {
                    $found = $false
                    $pathType = "File"
                    $message = "Path not found"
                    Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Path not found: $path"
                }
            }
            
            # Track if all paths match
            if (-not $found) {
                $allMatch = $false
            }
            
            # Create result object for this path
            $pathResult = [PSCustomObject]@{
                Path = $path
                Found = $found
                PathType = $pathType
                MatchType = "PathPresent"
                Message = $message
            }
            $pathResults += $pathResult
            
            # Build message line
            $status = if ($found) { "FOUND" } else { "NOT FOUND" }
            $messageLines += "$status [$pathType] $path - $message"
        }
        
        # Build summary message
        $summaryMessage = "Tested $($TestPaths.Count) paths: $($pathResults.Where({$_.Found}).Count) found, $($pathResults.Where({-not $_.Found}).Count) missing"
        $formattedMessage = "$summaryMessage`n" + ($messageLines -join "; ")
        
        # Build return data
        $returnData = @{
            Paths = $pathResults
            AllMatch = $allMatch
            Message = $formattedMessage
            TotalPaths = $TestPaths.Count
            FoundCount = $pathResults.Where({$_.Found}).Count
            MissingCount = $pathResults.Where({-not $_.Found}).Count
        }
        
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): AllMatch=$allMatch, Found=$($returnData.FoundCount)/$($returnData.TotalPaths)"
        
        # Determine severity based on results
        $severity = if ($allMatch) { "Info" } else { "Warning" }
        
        # Success
        return @{ 
            Success = $true
            Severity = $severity
            Message = "$($MyInvocation.MyCommand.Name): $summaryMessage"
            Data = $returnData
        }
    }
    catch {
        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $_"
        return @{ 
            Success = $false
            Severity = "Error"
            Message = "$($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
            Data = $null
        }
    }
}

function Test-DoAppInstall {
    <#
    .SYNOPSIS
        Tests whether an application should be installed based on registry status and install flags
    .DESCRIPTION
        Checks registry for application installation status and determines if installation is required
        based on provided install flags. Follows the hybrid error handling pattern.
    .PARAMETER Publisher
        Application publisher name (e.g., "Windows")
    .PARAMETER AppName
        Application name (e.g., "RSAT")
    .PARAMETER AppVersion
        Application version (e.g., "Latest")
    .PARAMETER AppScriptVersion
        Installer script version to check against
    .PARAMETER ControllerScriptVersion
        Optional controller script version to check against
    .PARAMETER RegistryRoot
        Registry root path. Default is "HKLM:\Software\ETHAN"
    .PARAMETER InstallFlags
        Bitwise flags controlling install logic:
        0 = INSTALLALWAYS - Always install
        1 = INSTALLIFAPPMISSING - Install if app not present
        2 = INSTALLIFDELTAAPPVER - Install if app version mismatch
        4 = INSTALLIFDELTAAPPSCRIPTVER - Install if script version mismatch
        8 = INSTALLIFDELTAAPPSCRIPTCTLVER - Install if controller version mismatch
    .OUTPUTS
        Hashtable with Success, Severity, Message, and Data fields
    .EXAMPLE
        $result = Test-DoAppInstall -Publisher "Windows" -AppName "RSAT" -AppVersion "Latest" `
            -AppScriptVersion "1.0.0" -ControllerScriptVersion "1.0.0" -InstallFlags 15
        if ($result.Success -and $result.Data.InstallRequired) {
            Write-Host "Installation required"
        }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Publisher,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppName,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppVersion,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppScriptVersion,
        
        [Parameter(Mandatory=$false)]
        [string]$ControllerScriptVersion,
        
        [Parameter(Mandatory=$false)]
        [string]$RegistryRoot = "HKLM:\Software\ETHAN",
        
        [Parameter(Mandatory=$true)]
        [int]$InstallFlags
    )
    $VerbosePreference = "SilentlyContinue"
    # Print all parameters for debugging
    $PSBoundParameters.Keys | ForEach-Object { 
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name) Parameter: $_ = $($PSBoundParameters[$_])"
    }

    try {
        # Build registry path
        $registryPath = Join-Path $RegistryRoot "$Publisher.$AppName.$AppVersion"
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Checking registry path: $registryPath"
        
        # Initialize status flags
        $appKeyMatch = $false
        $appVersionMatch = $false
        $appScriptVersionMatch = $false
        $appInstalled = $false
        $scriptVersionMatch = $false
        
        # Get registry info
        $result = Get-RegistryKeyInfo -KeyPath $registryPath
        
        if ($result.Success) {
            $appKeyMatch = $true
            $appVersionMatch = $true
            $regKeyObj = $result.Data
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Registry key exists, checking properties..."
            
            # Check for specific properties and values
            if ($regKeyObj.PropertyDetails.Contains('Status') -and 
                $regKeyObj.PropertyDetails['Status'].Value -eq "INSTALLED") {
                $appInstalled = $true
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Status = 'INSTALLED' - App is installed"
            } else {
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Status property missing or not 'INSTALLED' - App not installed"
            }
            
            if ($regKeyObj.PropertyDetails.Contains('ScriptVersion') -and 
                $regKeyObj.PropertyDetails['ScriptVersion'].Value -eq $AppScriptVersion) {
                $appScriptVersionMatch = $true
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): ScriptVersion matches expected: $AppScriptVersion"
            } else {
                $registryScriptVersion = if ($regKeyObj.PropertyDetails.Contains('ScriptVersion')) { $regKeyObj.PropertyDetails['ScriptVersion'].Value } else { "Not found" }
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): ScriptVersion mismatch - Expected: $AppScriptVersion, Found: $registryScriptVersion"
            }
            
            if ($ControllerScriptVersion -and 
                $regKeyObj.PropertyDetails.Contains('ScriptVersionCTL') -and 
                $regKeyObj.PropertyDetails['ScriptVersionCTL'].Value -eq $ControllerScriptVersion) {
                $scriptVersionMatch = $true
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): ScriptVersionCTL matches expected: $ControllerScriptVersion"
            } else {
                if ($ControllerScriptVersion) {
                    $registryCtlVersion = if ($regKeyObj.PropertyDetails.Contains('ScriptVersionCTL')) { $regKeyObj.PropertyDetails['ScriptVersionCTL'].Value } else { "Not found" }
                    Write-Verbose -Message "$($MyInvocation.MyCommand.Name): ScriptVersionCTL mismatch - Expected: $ControllerScriptVersion, Found: $registryCtlVersion"
                }
            }
        } else {
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Registry key does not exist - App not installed"
        }
        
        # Determine status message
        $state = "$appInstalled|$appScriptVersionMatch|$scriptVersionMatch"
        $statusMessage = switch ($state) {
            "True|True|True" { "Application is already installed, with expected installer script version, and with expected installer CTL script version" }
            "True|True|False" { "Application is already installed, with expected installer script version" }
            "True|False|True" { "Application is already installed, installer script version does not match expected, with expected installer CTL script version" }
            "True|False|False" { "Application is already installed, installer script version does not match expected" }
            default { "Application is not installed" }
        }
        
        # Determine if install is required based on flags (bitwise operations)
        $installRequired = $false
        $installReasons = @()
        
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Evaluating install flags (value: $InstallFlags)..."
        
        if ($InstallFlags -eq 0) {
            # INSTALLALWAYS (0) - always install
            $installRequired = $true
            $installReasons += "InstallAlways flag is set (0)"
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): INSTALL REQUIRED - InstallAlways flag is set"
        } else {
            # Check individual flags using bitwise AND
            if (($InstallFlags -band 1) -and (-not $appInstalled)) {
                # INSTALLIFAPPMISSING (1)
                $installRequired = $true
                $installReasons += "App is not installed (flag 1)"
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): INSTALL REQUIRED - App is not installed (InstallIfAppMissing flag)"
            }
            if (($InstallFlags -band 2) -and (-not $appVersionMatch)) {
                # INSTALLIFDELTAAPPVER (2)
                $installRequired = $true
                $installReasons += "App version does not match (flag 2)"
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): INSTALL REQUIRED - App version does not match (InstallIfDeltaAppVer flag)"
            }
            if (($InstallFlags -band 4) -and (-not $appScriptVersionMatch)) {
                # INSTALLIFDELTAAPPSCRIPTVER (4)
                $installRequired = $true
                $installReasons += "Installer script version does not match (flag 4)"
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): INSTALL REQUIRED - Installer script version does not match (InstallIfDeltaAppScriptVer flag)"
            }
            if (($InstallFlags -band 8) -and $ControllerScriptVersion -and (-not $scriptVersionMatch)) {
                # INSTALLIFDELTAAPPSCRIPTCTLVER (8)
                $installRequired = $true
                $installReasons += "Controller script version does not match (flag 8)"
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): INSTALL REQUIRED - Controller script version does not match (InstallIfDeltaAppScriptCtlVer flag)"
            }
            
            if (-not $installRequired) {
                $installReasons += "All checked conditions are satisfied - no install needed"
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): NO INSTALL REQUIRED - All checked conditions are satisfied"
            }
        }
        
        # Build return data
        $returnData = @{
            RegistryKeyPath = $registryPath
            AppKeyMatch = $appKeyMatch
            AppVersionMatch = $appVersionMatch
            AppScriptVersionMatch = $appScriptVersionMatch
            ScriptVersionMatch = $scriptVersionMatch
            AppInstalled = $appInstalled
            InstallRequired = $installRequired
            InstallFlags = $InstallFlags
            InstallReasons = $installReasons
            StatusMessage = $statusMessage
        }
        
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Decision summary - InstallRequired: $installRequired, Reasons: $($installReasons -join '; ')"
        
        # Success
        return @{ 
            Success = $true
            Severity = "Info"
            Message = "$($MyInvocation.MyCommand.Name): $statusMessage"
            Data = $returnData
        }
    }
    catch {
        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $_"
        return @{ 
            Success = $false
            Severity = "Error"
            Message = "$($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
            Data = $null
        }
    }
}

function Get-RegistryKeyInfo {
    <#
    .SYNOPSIS
        Retrieves registry key properties and values as an object
    .DESCRIPTION
        Reads a registry key and returns all properties with their names, values, and types.
        Follows the hybrid error handling pattern returning Success, Severity, Message, and Data.
    .PARAMETER KeyPath
        The full registry path (e.g., "HKLM:\SOFTWARE\ETHAN\pub.app.77")
    .OUTPUTS
        Hashtable with:
        - Success: [bool] $true if key exists and was read, $false if not found
        - Severity: [string] "Info" on success, "Warning" if key not found, "Error" for other failures
        - Message: [string] Human-readable description of the result
        - Data: [object] Hashtable containing Properties array and PropertyDetails ordered hashtable
    .EXAMPLE
        $result = Get-RegistryKeyInfo -KeyPath "HKLM:\SOFTWARE\ETHAN\pub.app.77"
        if ($result.Success) {
            Write-Host "Properties: $($result.Data.Properties -join ', ')"
            $result.Data.PropertyDetails.Values | Format-Table
            # Direct access: $result.Data.PropertyDetails["StatusDate"].Value
        } else {
            Write-Host "Failed: $($result.Message)"
        }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$KeyPath
    )

    # Print all parameters for debugging
    $PSBoundParameters.Keys | ForEach-Object { 
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name) Parameter: $_ = $($PSBoundParameters[$_])"
    }

    try {
        # Check if registry key exists
        if (-not (Test-Path -Path $KeyPath)) {
            return @{ 
                Success = $false
                Severity = "Warning"
                Message = "$($MyInvocation.MyCommand.Name): Registry key not found: '$KeyPath'"
                Data = $null
            }
        }

        # Get the registry key item
        $regKey = Get-Item -Path $KeyPath -ErrorAction Stop
        
        # Get property names
        $propertyNames = $regKey.Property
        
        # Build detailed property information as ordered hashtable
        $propertyDetails = [ordered]@{}
        foreach ($propName in $propertyNames) {
            $propValue = $regKey.GetValue($propName)
            $propType = $regKey.GetValueKind($propName)
            
            $propertyDetails[$propName] = [PSCustomObject]@{
                Name  = $propName
                Value = $propValue
                Type  = $propType.ToString()
            }
        }
        
        # Build return data
        $returnData = @{
            Properties = $propertyNames
            PropertyDetails = $propertyDetails
        }
        
        # Success
        return @{ 
            Success = $true
            Severity = "Info"
            Message = "$($MyInvocation.MyCommand.Name): Successfully read '$KeyPath' with $($propertyNames.Count) properties"
            Data = $returnData
        }
    }
    catch [System.Security.SecurityException] {
        # Access denied - non-fatal
        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $_"
        return @{ 
            Success = $false
            Severity = "Warning"
            Message = "$($MyInvocation.MyCommand.Name): Access denied to registry key '$KeyPath'"
            Data = $null
        }
    }
    catch {
        # General error - fatal
        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $_"
        return @{ 
            Success = $false
            Severity = "Error"
            Message = "$($MyInvocation.MyCommand.Name): Failed to read registry key '$KeyPath': $($_.Exception.Message)"
            Data = $null
        }
    }
}

function Set-RegistryKeyInfo {
    <#
    .SYNOPSIS
        Sets registry key properties and values from an object
    .DESCRIPTION
        Takes an object with PropertyDetails (Name, Value, Type) and sets all registry properties.
        Deletes and recreates properties if needed. Optionally removes extra properties not in the input.
        Follows the hybrid error handling pattern returning Success, Severity, Message, and Data.
    .PARAMETER KeyPath
        The full registry path (e.g., "HKLM:\SOFTWARE\ETHAN\pub.app.77")
    .PARAMETER PropertyDetails
        Ordered hashtable of PSCustomObjects with Name, Value, and Type properties (keyed by property name)
    .PARAMETER Replace
        If true, removes properties in registry that are not in PropertyDetails. Default is false.
    .OUTPUTS
        Hashtable with:
        - Success: [bool] $true if operation succeeded, $false otherwise
        - Severity: [string] "Info" on success, "Warning" for non-fatal issues, "Error" for fatal failures
        - Message: [string] Human-readable description of the result
        - Data: [object] Hashtable with PropertiesSet, PropertiesDeleted counts
    .EXAMPLE
        $data = @{
            PropertyDetails = @(
                [PSCustomObject]@{ Name = "Version"; Value = "2.0.0"; Type = "String" }
                [PSCustomObject]@{ Name = "Port"; Value = 8080; Type = "DWord" }
            )
        }
        $result = Set-RegistryKeyInfo -KeyPath "HKLM:\Software\MyApp" -PropertyDetails $data.PropertyDetails
        if ($result.Success) {
            Write-Host "Set $($result.Data.PropertiesSet) properties"
        }
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$KeyPath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [System.Collections.Specialized.OrderedDictionary]$PropertyDetails,
        
        [Parameter(Mandatory=$false)]
        [bool]$Replace = $false
    )

    # Print all parameters for debugging
    $PSBoundParameters.Keys | ForEach-Object { 
        Write-Verbose -Message "$($MyInvocation.MyCommand.Name) Parameter: $_ = $($PSBoundParameters[$_])"
    }

    # Validate PropertyDetails structure
    if ($PropertyDetails.Count -eq 0) {
        return @{ 
            Success = $false
            Severity = "Warning"
            Message = "$($MyInvocation.MyCommand.Name): PropertyDetails array is empty"
            Data = $null
        }
    }

    try {
        # Ensure registry key exists
        if (-not (Test-Path -Path $KeyPath)) {
            Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Creating registry key '$KeyPath'"
            New-Item -Path $KeyPath -Force -ErrorAction Stop | Out-Null
        }

        # Get current properties if Replace mode is enabled
        $existingProperties = @()
        if ($Replace) {
            $regKey = Get-Item -Path $KeyPath -ErrorAction Stop
            $existingProperties = $regKey.Property
        }

        # Track operations
        $propertiesSet = 0
        $propertiesDeleted = 0
        $errors = @()

        # Set each property from PropertyDetails hashtable
        foreach ($propName in $PropertyDetails.Keys) {
            $prop = $PropertyDetails[$propName]
            if (-not $prop.Name) {
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Skipping property with empty Name"
                continue
            }

            try {
                # Map type string to RegistryValueKind
                $regType = switch ($prop.Type) {
                    "String"       { "String" }
                    "ExpandString" { "ExpandString" }
                    "DWord"        { "DWord" }
                    "QWord"        { "QWord" }
                    "Binary"       { "Binary" }
                    "MultiString"  { "MultiString" }
                    default        { "String" }  # Default to String if unknown
                }

                # Check if property exists and delete if needed to recreate
                if (Get-ItemProperty -Path $KeyPath -Name $prop.Name -ErrorAction SilentlyContinue) {
                    # Delete existing property to ensure clean recreation
                    Remove-ItemProperty -Path $KeyPath -Name $prop.Name -ErrorAction Stop
                    Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Deleted existing property '$($prop.Name)'"
                }

                # Create the property with correct type
                New-ItemProperty -Path $KeyPath `
                    -Name $prop.Name `
                    -Value $prop.Value `
                    -PropertyType $regType `
                    -Force `
                    -ErrorAction Stop | Out-Null
                
                $propertiesSet++
                Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Set property '$($prop.Name)' = '$($prop.Value)' (Type: $regType)"
            }
            catch {
                $errorMsg = "Failed to set property '$($prop.Name)': $($_.Exception.Message)"
                $errors += $errorMsg
                Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $errorMsg"
            }
        }

        # If Replace mode, delete properties not in PropertyDetails
        if ($Replace -and $existingProperties.Count -gt 0) {
            $inputPropertyNames = $PropertyDetails.Keys
            
            foreach ($existingProp in $existingProperties) {
                if ($existingProp -notin $inputPropertyNames) {
                    try {
                        Remove-ItemProperty -Path $KeyPath -Name $existingProp -ErrorAction Stop
                        $propertiesDeleted++
                        Write-Verbose -Message "$($MyInvocation.MyCommand.Name): Deleted extra property '$existingProp'"
                    }
                    catch {
                        $errorMsg = "Failed to delete property '$existingProp': $($_.Exception.Message)"
                        $errors += $errorMsg
                        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $errorMsg"
                    }
                }
            }
        }

        # Build result
        $resultData = @{
            PropertiesSet = $propertiesSet
            PropertiesDeleted = $propertiesDeleted
            Errors = $errors
        }

        if ($errors.Count -gt 0) {
            # Partial success with warnings
            return @{ 
                Success = $true
                Severity = "Warning"
                Message = "$($MyInvocation.MyCommand.Name): Set $propertiesSet properties, deleted $propertiesDeleted, with $($errors.Count) errors"
                Data = $resultData
            }
        } else {
            # Full success
            return @{ 
                Success = $true
                Severity = "Info"
                Message = "$($MyInvocation.MyCommand.Name): Successfully set $propertiesSet properties, deleted $propertiesDeleted"
                Data = $resultData
            }
        }
    }
    catch [System.Security.SecurityException] {
        # Access denied - fatal for write operations
        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $_"
        return @{ 
            Success = $false
            Severity = "Error"
            Message = "$($MyInvocation.MyCommand.Name): Access denied to registry key '$KeyPath'"
            Data = $null
        }
    }
    catch {
        # General error - fatal
        Write-Verbose -Message "Error $($MyInvocation.MyCommand.Name): $_"
        return @{ 
            Success = $false
            Severity = "Error"
            Message = "$($MyInvocation.MyCommand.Name): Failed to update registry key '$KeyPath': $($_.Exception.Message)"
            Data = $null
        }
    }
}

function Set-RegistryProperty {
    <#
    .SYNOPSIS
        Adds or updates a property in a registry data object (in memory)
    .DESCRIPTION
        Simple helper to add or update a property in the PropertyDetails hashtable.
        Does not modify the actual registry - just the object returned from Get-RegistryKeyInfo.
    .PARAMETER RegistryObject
        The registry data object (from Get-RegistryKeyInfo.Data) with a PropertyDetails hashtable
    .PARAMETER Name
        Property name
    .PARAMETER Value
        Property value
    .PARAMETER Type
        Property type. Default is String.
    .EXAMPLE
        Set-RegistryProperty -RegistryObject $key2 -Name "Version" -Value "2.0"
        Set-RegistryProperty -RegistryObject $key2 -Name "Port" -Value 8080 -Type DWord
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$RegistryObject,
        
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        $Value,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("String", "ExpandString", "DWord", "QWord", "Binary", "MultiString")]
        [string]$Type = "String"
    )
    
    # Add or update property in hashtable
    if ($RegistryObject.PropertyDetails.Contains($Name)) {
        # Update existing property
        $RegistryObject.PropertyDetails[$Name].Value = $Value
        $RegistryObject.PropertyDetails[$Name].Type = $Type
        Write-Verbose "Updated property: $Name = $Value (Type: $Type)"
    } else {
        # Add new property
        $RegistryObject.PropertyDetails[$Name] = [PSCustomObject]@{
            Name  = $Name
            Value = $Value
            Type  = $Type
        }
        Write-Verbose "Added property: $Name = $Value (Type: $Type)"
    }
}


#========================================================================================================# 
#    Template Functions                                                                                  #
#========================================================================================================# 
#region TemplateFunctions
# Avoid editing here unless needed

function Start-Logging {
    [CmdletBinding()]
    param (
          
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]$Manufacturer = "Scripts",
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()]$Scriptname,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]$Version = "1.0",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][ValidateScript({ Split-Path $_ -Parent | Test-Path })]$LogPath = $env:LOCALAPPDATA,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][int]$MaxLogSize = 1MB,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][int]$MaxLogArchiveSize = 50KB,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][boolean]$ExtraInfo = $true,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][boolean]$NewLog = $true,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][boolean]$Display = $true
    )
	
    # Build file paths
    $LogFilePathRoot = Join-Path -Path $LogPath -ChildPath $Manufacturer
    $Global:LogFilePath = Join-Path -Path $LogFilePathRoot -ChildPath "$Scriptname.Log"
    $LogFileArchivePath = Join-Path -Path $LogFilePathRoot -ChildPath "$Scriptname.0.Zip"
    $LogFileArchiveArchivePath = Join-Path -Path $LogFilePathRoot -ChildPath "$Scriptname.1.Zip"
    $Global:ScriptStart = Get-Date
    $Global:Display = $Display

    Try {
       if (Test-Path -Path $LogFilePath){
            # Log exists - check size   
            If (((Get-ChildItem -Path $LogFilePath).Length -gt $MaxLogSize) -or ($NewLog)){
                #Too large - remove it
                
                if (Test-Path $LogFileArchivePath){
                    #A Zip already exists - test its size
                    if ((Get-ChildItem -Path $LogFileArchivePath).Length -gt $MaxLogArchiveSize){
                        #Zip is too large - roll it over
                        If (Test-Path $LogFileArchiveArchivePath){
                            Remove-Item -Path $LogFileArchiveArchivePath -Force
                        }
                        Write-Host "Move-Item -Path $LogFileArchivePath -Destination $LogFileArchiveArchivePath"
                        Move-Item -Path $LogFileArchivePath -Destination $LogFileArchiveArchivePath
                    }
                }
                # Add log to new or undersized zip
                $Date = $(((get-date).ToUniversalTime()).ToString("yyyyMMddTHHmmssZ"))
                Rename-Item -Path $LogFilePath -NewName "$Scriptname-$Date.Log"
                Compress-Archive -DestinationPath $LogFileArchivePath -Path "$LogFilePathRoot\$Scriptname-$Date.Log" -CompressionLevel Optimal -Update 
                Remove-Item -Path "$LogFilePathRoot\$Scriptname-$Date.Log" -Force -ErrorAction SilentlyContinue
            }
        } else { # Log does not exist
            if (-not(Test-Path -Path $LogFilePathRoot)){New-Item -Path $LogFilePathRoot -ItemType Directory | Out-Null}
            New-Item $LogFilePath -ItemType File | Out-Null
        }
                
        #Write log header
        $DateZ = ((get-date).ToUniversalTime()).ToString("yyyyMMddTHHmmssZ")
        Add-Content -Path $LogFilePath -Value "=============================================================================================`n"
        Add-Content -Path $LogFilePath -Value "Manufacturer:`t`t $Manufacturer"
        Add-Content -Path $LogFilePath -Value "Script:`t`t`t $Scriptname"
        Add-Content -Path $LogFilePath -Value "Version:`t`t $ScriptVersion"
        Add-Content -Path $LogFilePath -Value "Start:`t`t`t $(get-date) ($DateZ)"
        Add-Content -Path $LogFilePath -Value "User:`t`t`t $env:USERNAME"
        Add-Content -Path $LogFilePath -Value "UserDomain:`t`t $env:UserDomain"
        Add-Content -Path $LogFilePath -Value "UserDNSDomain:`t`t $env:UserDNSDomain"
        Add-Content -Path $LogFilePath -Value "ComputerName:`t`t $env:ComputerName"
        Add-Content -Path $LogFilePath -Value "LogonServer:`t`t $env:LogonServer"
        Add-Content -Path $LogFilePath -Value "PROCESSOR_ARCH:`t`t $env:PROCESSOR_ARCHITECTURE"
        Add-Content -Path $LogFilePath -Value "Is64BitOS:`t`t $([environment]::Is64BitOperatingSystem)"
        Add-Content -Path $LogFilePath -Value "Is64BitProcess:`t`t $([environment]::Is64BitProcess)"
        Add-Content -Path $LogFilePath -Value "OSVersion:`t`t $([environment]::OSVersion)"
        Add-Content -Path $LogFilePath -Value "ProcessorCount:`t`t $([environment]::ProcessorCount)"
        Add-Content -Path $LogFilePath -Value "UserInteractive:`t $([environment]::UserInteractive)"
        Add-Content -Path $LogFilePath -Value "Version:`t`t $([environment]::Version)"
        Add-Content -Path $LogFilePath -Value "PSVersion:`t`t $($PSVersionTable.PSVersion)"
        Add-Content -Path $LogFilePath -Value "PSEdition:`t`t $($PSVersionTable.PSEdition)"
        Add-Content -Path $LogFilePath -Value "BuildVersion:`t`t $($PSVersionTable.BuildVersion)"
        Add-Content -Path $LogFilePath -Value "CLRVersion:`t`t $($PSVersionTable.CLRVersion)"
        Add-Content -Path $LogFilePath -Value "WSManStackVersion:`t $($PSVersionTable.WSManStackVersion)"
        Add-Content -Path $LogFilePath -Value "PSRemotingProtVer:`t $($PSVersionTable.WSManStackVersion)"
        
        # Verify EventLog Source
        try {
            if (-not ([System.Diagnostics.EventLog]::SourceExists($Scriptname))){
                New-EventLog -LogName "Application" -Source $Scriptname -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Silently ignore EventLog source errors (requires admin privileges)
            Write-Verbose "EventLog source check failed (may require admin privileges): $_"
        }
    }
    catch {
        Write-Error $_.Exception.Message
    }
    
    #Finalise
    Add-Content -Path $LogFilePath -Value "Elapsed:`t`t $([math]::round(((New-TimeSpan -Start $Global:ScriptStart).TotalSeconds),1)) seconds"
    Add-Content -Path $LogFilePath -Value "=============================================================================================`n" 
    If ($Display){Write-Host "Starting $Scriptname..." -ForegroundColor Cyan}
}

function Write-LogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)][string]$Message,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][ValidateSet("Debug","Verbose","Info","Warning","Error")][string]$Level = "Info",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][Boolean]$LogOnly = $false,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)][Boolean]$EventLog = $false
    )
	
   Try{
        $Elapsed = [math]::round(((New-TimeSpan -Start $Global:ScriptStart).TotalSeconds),1)
        Switch ($Level) {
            "Verbose" {
                $LevelText = "VBS"
                $TextColour = "Gray"
                Break
            }
            "Info" {
                $LevelText = "INF"
                $TextColour = "Cyan"
                Break
            }
            "Warning" {
                $LevelText = "WARNING"
                $TextColour = "Yellow"
                Break
            }
            "Error" {
                $LevelText = "ERROR"
                $TextColour = "Red"
                Break
            }
        }
        # Write to log     
        Add-Content -Path $LogFilePath -Value "$Elapsed $LevelText`:`t$Message"

        # Write to event log
        If ($EventLog){
            try {
                Switch ($Level) {
                    "Debug" {$EntryType = "Information"; Break}
                    "Verbose" {$EntryType = "Information"; Break}
                    "Info" {$EntryType = "Information"; Break}
                    "Warning" {$EntryType = "Warning"; Break}
                    "Error" {$EntryType = "Error"; Break}
                }
                $EventID = 57771
                $LogName = "Application"
                $Source = $ScriptName
                Write-EventLog -logname $LogName -source $Source -eventid $EventID -entrytype $EntryType -message $Message -ErrorAction Stop
            }
            catch {
                # Silently ignore EventLog write errors (source may not exist or no permissions)
            }
        }

        # Display to screen
        If ($Display){
            if (-not ($LogOnly)){ #override global display variable
                
                if (($Level -eq "Debug") -or ($Level -eq "Verbose")){
                    #Write-host -Object $Message
                    Write-Verbose -Message $Message
                } else {
                    Write-Host -ForegroundColor $TextColour -Object $Message 
                }
            }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}

function Stop-Logging {
   Try{
        $Elapsed = [math]::round(((New-TimeSpan -Start $Global:ScriptStart).TotalSeconds),1)
        Write-LogEntry "Elapsed:`t`t $([math]::round(((New-TimeSpan -Start $Global:ScriptStart).TotalSeconds),1)) seconds" -Level Info -EventLog $false
        Add-Content -Path $LogFilePath -Value "=============================================================================================`n"      
    }
    Catch {Write-Error $_.Exception.Message}    
}

# Script setup - Edit if needed
$Manufacturer = "ETHAN"             # Used in output and log file details
#Requires -RunAsAdministrator       # Remove comment if admin rights required for execution
#Requires -Version 5                # Specifiy minimum PowerShell version
$LogPath = $env:LOCALAPPDATA        # Specify log output folder
$NewLog = $true                     # Creates a new log each time the script is run (see end of script for options on rollover, archiving, etc.)

# Record values before stepping into any functions
$TemplateVersion    = "3.5.1"
$ScriptPath         = $PSCommandPath
$ScriptName         = ([io.fileinfo]$PSCommandPath).BaseName
$ScriptParentFolder = ([io.fileinfo]$PSCommandPath).DirectoryName
if (Test-Path "Variable:args") {$LocalArgs = $args}

#Initialise logging
$MaxLogSize         = 1MB
$MaxLogArchiveSize  = 1MB
$Display            = $true
Start-Logging -Scriptname $ScriptName -Manufacturer $Manufacturer -Version $ScriptVersion -ExtraInfo $false -NewLog $NewLog -LogPath $LogPath -MaxLogSize $MaxLogSize -MaxLogArchiveSize $MaxLogArchiveSize -Display $Display
Write-LogEntry -Message "Stepping into Main function..." -Level Info -LogOnly $true
Write-LogEntry -Message "Using template version $TemplateVersion" -Level Info  -LogOnly $true

# Other variables
# Call Main script
$Return = MainScript

# Wrap up
Write-LogEntry -Message "Return: $Return" -Level Info
Stop-Logging
Return $Return #fin

<#
Release history:
3.5.0    2026-02-07       - Cleaned up for MAVD Software Installation template release
3.5.1    2026-02-07       - Cleaned up for template release to MAVD.Builder.Software
#>