<#
.Synopsis
   MAVD OpsScript Installer
.DESCRIPTION
   Configures Windows regional settings (Windows display language and language for non-Unicode programs)
   Verifies the settings were applied
   Updates local software register with status
   IMPORTANT: Do not duplicate - always get a clean template from the source repo: https://dev.azure.com/eCorpSystems/Ethan.MAVD.Builder/_git/Ethan.MAVD.Builder.Software
.NOTES
   This is a configuration package, not a setup.exe/msi installer. It sets the Windows display
   language and the language for non-Unicode programs to English (Australia) (en-AU), and the
   Country or region (home location) to Australia (GeoId 12), via the built-in "International"
   PowerShell module, then copies the settings to the Welcome screen and Default User profile
   (Copy-UserInternationalSettingsToSystem) so every new session on this shared host picks up
   English (Australia) by default. A restart is required for the system locale (non-Unicode
   programs) change to take full effect.

   IMPORTANT (execution context): Set-WinUserLanguageList / Set-WinUILanguageOverride /
   Set-WinHomeLocation are HKCU-scoped - they only affect the profile the script runs under.
   Set-WinSystemLocale is the one genuinely machine-wide (HKLM) setting. Copy-UserInternationalSettingsToSystem
   only updates the logon screen (HKU\.DEFAULT) and the Default User profile template
   (C:\Users\Default\NTUSER.DAT) that new profiles are cloned from - it does NOT touch any
   already-existing FSLogix/local user profile. To bring an existing user onto en-AU, either
   delete their FSLogix profile container and have them log in again (so a new profile is
   cloned from the now-updated Default profile on whichever host they land on), or apply the
   change inside that user's own session.

   The script mounts C:\Users\Default\NTUSER.DAT read-only (reg.exe load/unload) after
   Copy-UserInternationalSettingsToSystem runs, to directly confirm the Default profile
   template's Control Panel\International\Geo\Nation (GeoId) value was actually updated -
   this is the concrete signal that new/recreated profiles on this host will pick up en-AU.

   Version     Date            Author      Notes
   3.4.0       2026-09-07      KSM         Initial version - sets Windows display language and language for non-Unicode programs to en-AU, propagated to Welcome screen and Default User profile
   3.4.0       2026-09-07      KSM         Added Country or region (home location) - GeoId 12 (Australia)
   3.4.0       2026-09-08      KSM         Added direct verification of the Default User profile hive (GeoId, best-effort UI language) after Copy-UserInternationalSettingsToSystem
#>

# Package information
$AppPublisher   = "Windows"
$AppName        = "RegionalSettings"
$AppVersion     = "en-AU"
$TargetLanguage = "en-AU"   # BCP-47 language tag applied to Windows display language, user language list, and system locale (non-Unicode programs)
$TargetGeoId    = 12        # GeoId for Country or region (home location) - 12 = Australia
$CustID         = "TRLF"    # Specify customer ID for private packages, do not specify for public
$ScriptType     = "Public"  # Public or Private - determines error return behavior (see MainScript)
$ScriptVersion  = "3.4.0"   # This script version

#========================================================================================================#
#    Main Script Functions                                                                               #
#========================================================================================================#

Function MainScript {
    Write-LogEntry -Message "Starting execution, log file: $LogFilePath" -Level Info

    # Script variables
    $AppMoniker   = "$AppPublisher.$AppName.$AppVersion"
    $RegistryRoot = "HKLM:\Software\ETHAN"
    $RegistryPath = Join-Path $RegistryRoot -ChildPath $AppMoniker

    Write-LogEntry "Starting $AppPublisher $AppName ($AppVersion) configuration script version $ScriptVersion" -Level Info -EventLog $true
    Write-LogEntry "App: $AppMoniker TargetLanguage: $TargetLanguage TargetGeoId: $TargetGeoId" -Level Info

    # Apply regional settings
    try {
        # International cmdlets (Set-WinSystemLocale, Set-WinUILanguageOverride, etc.) ship built-in on Windows 10/Server 2016+
        Import-Module International -ErrorAction Stop

        $currentDisplay = (Get-WinUILanguageOverride).Name
        Write-LogEntry "Current Windows display language: $currentDisplay" -Level Info

        # Ensure target language is present in the user language list and is first (Windows display language),
        # preserving any other languages already configured
        $languageList = Get-WinUserLanguageList
        if ($languageList.LanguageTag -contains $TargetLanguage) {
            $existing = $languageList | Where-Object { $_.LanguageTag -eq $TargetLanguage }
            $others   = $languageList | Where-Object { $_.LanguageTag -ne $TargetLanguage }
            $languageList = @($existing) + @($others)
            Write-LogEntry "$TargetLanguage already present in user language list - moved to first position" -Level Info
        } else {
            $languageList.Insert(0, $TargetLanguage)
            Write-LogEntry "Added $TargetLanguage to user language list" -Level Info
        }
        Set-WinUserLanguageList -LanguageList $languageList -Force
        Write-LogEntry "Set-WinUserLanguageList applied: $($languageList.LanguageTag -join ', ')" -Level Info

        # Windows display language (Settings > Time & language > Language & region > Windows display language)
        Set-WinUILanguageOverride -Language $TargetLanguage
        Write-LogEntry "Set-WinUILanguageOverride -Language $TargetLanguage applied (takes effect after next sign-in)" -Level Info

        # Language for non-Unicode programs (Region > Additional settings > Change system locale)
        $currentSystemLocale = (Get-WinSystemLocale).Name
        Write-LogEntry "Current system locale (non-Unicode programs): $currentSystemLocale" -Level Info
        if ($currentSystemLocale -ne $TargetLanguage) {
            Set-WinSystemLocale -SystemLocale $TargetLanguage
            Write-LogEntry "Set-WinSystemLocale -SystemLocale $TargetLanguage applied (takes effect after restart)" -Level Info
        } else {
            Write-LogEntry "System locale already set to $TargetLanguage - skipping" -Level Info
        }

        # Country or region / home location (Settings > Time & language > Language & region > Country or region)
        $currentGeoId = (Get-WinHomeLocation).GeoId
        Write-LogEntry "Current home location GeoId: $currentGeoId" -Level Info
        if ($currentGeoId -ne $TargetGeoId) {
            Set-WinHomeLocation -GeoId $TargetGeoId
            Write-LogEntry "Set-WinHomeLocation -GeoId $TargetGeoId applied" -Level Info
        } else {
            Write-LogEntry "Home location already set to GeoId $TargetGeoId - skipping" -Level Info
        }

        # Propagate current settings (incl. display language and home location) to Welcome screen and Default
        # User profile so new sessions on this shared host inherit English (Australia) without needing to be
        # set per-user
        $DefaultProfileHive = "C:\Users\Default\NTUSER.DAT"
        $defaultProfileBeforeWrite = if (Test-Path $DefaultProfileHive) { (Get-Item $DefaultProfileHive).LastWriteTimeUtc } else { $null }

        Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
        Write-LogEntry "Copy-UserInternationalSettingsToSystem applied to Welcome screen and Default User profile" -Level Info

        # Verify the Default User profile template was actually updated, since new FSLogix/local profiles are
        # cloned from it - this confirms new profiles (or a profile recreated after deleting an existing
        # FSLogix container) will pick up the target settings, without needing to touch any existing profile
        $defaultProfileVerified       = $false
        $defaultProfileTouched        = $false
        $defaultProfileGeoIdMatches   = $false
        $defaultProfileLangMatches    = $false
        try {
            if (-not (Test-Path $DefaultProfileHive)) {
                throw "Default profile hive not found at $DefaultProfileHive"
            }

            $defaultProfileAfterWrite = (Get-Item $DefaultProfileHive).LastWriteTimeUtc
            $defaultProfileTouched = ($null -eq $defaultProfileBeforeWrite) -or ($defaultProfileAfterWrite -gt $defaultProfileBeforeWrite)
            Write-LogEntry "Default profile hive LastWriteTimeUtc before/after: $defaultProfileBeforeWrite / $defaultProfileAfterWrite (Touched: $defaultProfileTouched)" -Level Info

            # Mount the Default profile's hive read-only under HKU so its registry values can be inspected directly
            $hiveName = "DefaultProfileCheck_$([guid]::NewGuid().ToString('N'))"
            $loadOutput = & reg.exe load "HKU\$hiveName" $DefaultProfileHive 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "reg.exe load failed (exit $LASTEXITCODE): $loadOutput"
            }
            try {
                $geoPath = "Registry::HKEY_USERS\$hiveName\Control Panel\International\Geo"
                $defaultProfileGeoId = if (Test-Path $geoPath) { (Get-ItemProperty -Path $geoPath -Name "Nation" -ErrorAction SilentlyContinue).Nation } else { $null }
                $defaultProfileGeoIdMatches = ($defaultProfileGeoId -eq "$TargetGeoId")

                # Best-effort: the UI language override key/format can vary slightly across Windows builds
                $desktopPath = "Registry::HKEY_USERS\$hiveName\Control Panel\Desktop"
                $defaultProfileUILanguages = if (Test-Path $desktopPath) { (Get-ItemProperty -Path $desktopPath -Name "PreferredUILanguages" -ErrorAction SilentlyContinue).PreferredUILanguages } else { $null }
                $defaultProfileLangMatches = [bool]($defaultProfileUILanguages -and ($defaultProfileUILanguages -contains $TargetLanguage))

                Write-LogEntry "Default profile verification - GeoId: $defaultProfileGeoId (expected $TargetGeoId, Match: $defaultProfileGeoIdMatches), PreferredUILanguages: $($defaultProfileUILanguages -join ', ') (Match: $defaultProfileLangMatches)" -Level Info
                $defaultProfileVerified = $true
            }
            finally {
                # Release any lingering .NET registry handles before unloading, otherwise reg.exe unload can fail
                [gc]::Collect()
                [gc]::WaitForPendingFinalizers()
                $unloadOutput = & reg.exe unload "HKU\$hiveName" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-LogEntry "reg.exe unload of Default profile hive returned exit $LASTEXITCODE`: $unloadOutput" -Level Warning
                }
            }
        }
        catch {
            Write-LogEntry "Could not verify Default User profile hive directly: $($_.Exception.Message)" -Level Warning
        }
    }
    catch {
        $StatusMessage = "Failed to apply regional settings (Language $TargetLanguage, GeoId $TargetGeoId): $($_.Exception.Message)"
        Write-LogEntry -Message $StatusMessage -Level Error -EventLog $true
        $result = Update-PackageRegistryStatus -RegistryPath $RegistryPath -Success $false -StatusMessage $StatusMessage -ScriptVersion $ScriptVersion -AppPublisher $AppPublisher -AppName $AppName -AppVersion $AppVersion -ScriptType $ScriptType
        Write-LogEntry -Message $result.Message -Level Info
        if ($ScriptType -eq "Public") {
            Exit 1
        }
        return @{ Success = $false; Severity = "Error"; Message = $StatusMessage; Data = "" }
    }

    # Verify applied settings
    $verifyDisplay      = (Get-WinUILanguageOverride).Name
    $verifySystemLocale = (Get-WinSystemLocale).Name
    $verifyPrimaryLang  = (Get-WinUserLanguageList)[0].LanguageTag
    $verifyGeoId        = (Get-WinHomeLocation).GeoId
    Write-LogEntry "Verification - DisplayLanguageOverride: $verifyDisplay, SystemLocale: $verifySystemLocale, PrimaryUserLanguage: $verifyPrimaryLang, GeoId: $verifyGeoId" -Level Info
    Write-LogEntry "Verification - Default User profile: Verified=$defaultProfileVerified, Touched=$defaultProfileTouched, GeoIdMatch=$defaultProfileGeoIdMatches, PreferredUILanguagesMatch(best-effort)=$defaultProfileLangMatches" -Level Info

    # Default profile GeoId is a hard check (stable, documented registry value) when verification was possible;
    # if the hive couldn't be inspected (e.g. locked), that failure doesn't itself fail the overall result -
    # PreferredUILanguages is logged as a best-effort signal only, since its exact format can vary by OS build
    $defaultProfileOK = (-not $defaultProfileVerified) -or $defaultProfileGeoIdMatches
    $allMatch = ($verifyDisplay -eq $TargetLanguage) -and ($verifySystemLocale -eq $TargetLanguage) -and ($verifyPrimaryLang -eq $TargetLanguage) -and ($verifyGeoId -eq $TargetGeoId) -and $defaultProfileOK

    if ($allMatch) {
        # Update registry with configuration status
        $StatusMessage = "Regional settings applied successfully: Windows display language and language for non-Unicode programs set to $TargetLanguage, Country or region set to GeoId $TargetGeoId. Default User profile template verified=$defaultProfileVerified (GeoId match=$defaultProfileGeoIdMatches, UI language match=$defaultProfileLangMatches) - new/recreated profiles on this host will inherit these settings. A restart is required for the system locale change to take full effect."
        $result = Update-PackageRegistryStatus -RegistryPath $RegistryPath -Success $true -StatusMessage $StatusMessage -ScriptVersion $ScriptVersion -AppPublisher $AppPublisher -AppName $AppName -AppVersion $AppVersion -ScriptType $ScriptType
        Write-LogEntry -Message $result.Message -Level Info
    } else {
        Write-LogEntry "One or more checks failed" -Level Error
        # Update registry with configuration success and verification failure status
        $StatusMessage = "Regional settings applied, but verification failed - DisplayLanguageOverride: $verifyDisplay, SystemLocale: $verifySystemLocale, PrimaryUserLanguage: $verifyPrimaryLang, GeoId: $verifyGeoId, DefaultProfileGeoIdMatch: $defaultProfileGeoIdMatches (expected Language $TargetLanguage, GeoId $TargetGeoId)"
        $result = Update-PackageRegistryStatus -RegistryPath $RegistryPath -Success $false -StatusMessage $StatusMessage -ScriptVersion $ScriptVersion -AppPublisher $AppPublisher -AppName $AppName -AppVersion $AppVersion -ScriptType $ScriptType
        Write-LogEntry -Message $StatusMessage -Level Error -EventLog $true
        if ($ScriptType -eq "Public") {
            Exit 1
        }
        return @{ Success = $false; Severity = "Error"; Message = $StatusMessage; Data = "" }
    }

    ## Wrap Up ##
    $duration = [math]::round(((New-TimeSpan -Start $Global:ScriptStart).TotalSeconds),1)
    $Message = "Regional settings configured OK. Verification checks passed OK. Duration: $duration seconds. Restart recommended to fully apply the system locale (non-Unicode programs) change."
    Write-LogEntry -Message $Message -Level Info -EventLog $true
    return @{ Success = $true; Severity = "Info"; Message = $Message; Data = "" }
}

#========================================================================================================#
#    Script Functions                                                                                    #
#========================================================================================================#

# Add script-specific functions here...

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

    $VerbosePreference = "Continue" # Ensure verbose messages are shown for debugging

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
        Write-LogEntry "Elapsed:`t`t $Elapsed seconds" -Level Info -EventLog $false
        Add-Content -Path $LogFilePath -Value "=============================================================================================`n"
    }
    Catch {Write-Error $_.Exception.Message}
}

# Script setup - Edit if needed
$Manufacturer = "ETHAN"             # Used in output and log file details
#Requires -RunAsAdministrator       # Set-WinSystemLocale and Copy-UserInternationalSettingsToSystem require admin rights
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
3.4.0    2026-09-07       - Initial version, sets Windows display language and language for non-Unicode programs to en-AU
3.4.0    2026-09-07       - Added Country or region (home location) - GeoId 12 (Australia)
3.4.0    2026-09-08       - Added direct verification of the Default User profile hive after Copy-UserInternationalSettingsToSystem
#>
