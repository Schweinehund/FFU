<#
.SYNOPSIS
    Provides functions to retrieve Panasonic TOUGHBOOK model lists and download corresponding driver packs.
.DESCRIPTION
    This module contains the logic specific to handling Panasonic drivers for the FFU Builder UI. It includes functions to:
    - Download and parse the Panasonic SCCM catalog (CAB format) to generate a list of supported TOUGHBOOK models.
    - For a selected model, find and download the appropriate driver pack based on the specified Windows release and version.
    - Extract the driver pack CAB file using expand.exe.
    - Optionally, compress the final extracted drivers into a single WIM file for easier deployment.
    - Fallback to a static TOUGHBOOK model list if the SCCM catalog is unavailable or empty.
    These functions are designed to be called by the main UI logic, often in parallel, to efficiently manage driver acquisition.
#>

# Function to get the list of Panasonic models from the SCCM catalog
function Get-PanasonicDriversModelList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$Make # Expected to be 'Panasonic'
    )

    WriteLog "Getting Panasonic driver model list..."
    $panasonicDriversFolder = Join-Path -Path $DriversFolder -ChildPath $Make
    $catalogCab = Join-Path -Path $panasonicDriversFolder -ChildPath "PanasonicSCCM.cab"
    $catalogXml = Join-Path -Path $panasonicDriversFolder -ChildPath "PanasonicSCCM.xml"
    $modelList = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Static fallback model list for TOUGHBOOK/TOUGHPAD line
    $staticModels = @(
        'TOUGHBOOK 33 (CF-33)',
        'TOUGHBOOK 40 (FZ-40)',
        'TOUGHBOOK 55 (FZ-55)',
        'TOUGHBOOK G2 (FZ-G2)',
        'TOUGHBOOK A3 (FZ-A3)',
        'TOUGHBOOK S1 (FZ-S1)',
        'TOUGHBOOK N1 (FZ-N1)',
        'TOUGHBOOK T1 (FZ-T1)',
        'TOUGHBOOK CF-20',
        'TOUGHBOOK CF-31',
        'TOUGHBOOK CF-54',
        'TOUGHPAD FZ-G1',
        'TOUGHPAD FZ-M1'
    )

    try {
        # Ensure Panasonic drivers folder exists
        if (-not (Test-Path -Path $panasonicDriversFolder)) {
            WriteLog "Creating Panasonic Drivers folder: $panasonicDriversFolder"
            New-Item -Path $panasonicDriversFolder -ItemType Directory -Force | Out-Null
        }

        # Check if catalog URL is available
        $catalogUrl = [FFUConstants]::PANASONIC_CATALOG_URL
        if ([string]::IsNullOrEmpty($catalogUrl)) {
            WriteLog "WARNING: [Panasonic][Catalog] PANASONIC_CATALOG_URL is empty. Using static TOUGHBOOK model list."
            # Use static fallback
            foreach ($modelName in $staticModels) {
                $modelList.Add([PSCustomObject]@{
                        Make  = $Make
                        Model = $modelName
                    })
            }
            WriteLog "Successfully loaded $($modelList.Count) models from static TOUGHBOOK list."
            return ($modelList | Sort-Object -Property Model)
        }

        # Download PanasonicSCCM.cab if it doesn't exist or is outdated (e.g., older than 7 days)
        if (-not (Test-Path -Path $catalogCab) -or ((Get-Date) - (Get-Item $catalogCab).LastWriteTime).TotalDays -gt 7) {
            WriteLog "Downloading $catalogUrl to $catalogCab"
            # Use Get-CachedOEMCatalog for consistent caching behavior
            try {
                Get-CachedOEMCatalog -Vendor 'Panasonic' -CatalogType 'SCCM' `
                    -PrimaryUrl $catalogUrl -CachePath $catalogCab | Out-Null
                WriteLog "PanasonicSCCM.cab download complete."
            }
            catch {
                WriteLog "WARNING: [Panasonic][Catalog] Failed to download SCCM catalog: $($_.Exception.Message). Using static TOUGHBOOK model list."
                # Use static fallback
                foreach ($modelName in $staticModels) {
                    $modelList.Add([PSCustomObject]@{
                            Make  = $Make
                            Model = $modelName
                        })
                }
                WriteLog "Successfully loaded $($modelList.Count) models from static TOUGHBOOK list."
                return ($modelList | Sort-Object -Property Model)
            }
            # Force extraction if downloaded
            if (Test-Path -Path $catalogXml) {
                Remove-Item -Path $catalogXml -Force
            }
        }
        else {
            WriteLog "Using existing PanasonicSCCM.cab found at $catalogCab"
        }

        # Extract PanasonicSCCM.xml if it doesn't exist
        if (-not (Test-Path -Path $catalogXml)) {
            WriteLog "Expanding $catalogCab to $catalogXml"
            # Note: Do not embed quotes in argument array - PowerShell handles quoting automatically
            Invoke-Process -FilePath "expand.exe" -ArgumentList @($catalogCab, $catalogXml) -ErrorAction Stop | Out-Null
            WriteLog "PanasonicSCCM.xml extraction complete."
        }
        else {
            WriteLog "Using existing PanasonicSCCM.xml found at $catalogXml"
        }

        # Parse the PanasonicSCCM.xml to extract TOUGHBOOK models
        WriteLog "Parsing PanasonicSCCM.xml to extract Panasonic models..."
        [xml]$catalogContent = Get-Content -Path $catalogXml -Raw -Encoding UTF8 -ErrorAction Stop

        $uniqueModels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Parse SCCM catalog structure
        # Expected schema: SystemsManagementCatalog -> SoftwareDistributionPackage -> InstallableItem -> ApplicabilityRules
        if ($catalogContent.SystemsManagementCatalog) {
            foreach ($package in $catalogContent.SystemsManagementCatalog.SoftwareDistributionPackage) {
                # Look for Panasonic publisher
                if ($package.Properties.PublisherDisplayName -match 'Panasonic') {
                    # Extract model information from InstallableItem WmiQuery
                    foreach ($installableItem in $package.InstallableItem) {
                        if ($installableItem.ApplicabilityRules.IsInstallable.And) {
                            foreach ($wmiQuery in $installableItem.ApplicabilityRules.IsInstallable.And.WmiQuery) {
                                # Extract model from WQL query - look for Model or ComputerSystem queries
                                $wql = $wmiQuery.WqlQuery
                                if ($wql -match 'Model.*=.*["\']([^"\']+)["\']') {
                                    $modelName = $matches[1].Trim()
                                    if (-not [string]::IsNullOrWhiteSpace($modelName) -and $uniqueModels.Add($modelName)) {
                                        $modelList.Add([PSCustomObject]@{
                                                Make  = $Make
                                                Model = $modelName
                                            })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        # If parsing yielded 0 models, fall back to static list
        if ($modelList.Count -eq 0) {
            WriteLog "WARNING: [Panasonic][Catalog] SCCM catalog parsing returned 0 models. Using static TOUGHBOOK model list."
            foreach ($modelName in $staticModels) {
                $modelList.Add([PSCustomObject]@{
                        Make  = $Make
                        Model = $modelName
                    })
            }
        }

        WriteLog "Successfully parsed $($modelList.Count) unique Panasonic models."

    }
    catch {
        WriteLog "ERROR: [Panasonic][Catalog] Error getting Panasonic driver model list: $($_.Exception.Message)"
        WriteLog "WARNING: [Panasonic][Catalog] Using static TOUGHBOOK model list."
        # Use static fallback
        foreach ($modelName in $staticModels) {
            $modelList.Add([PSCustomObject]@{
                    Make  = $Make
                    Model = $modelName
                })
        }
    }

    # Sort the list alphabetically by Model name before returning
    $modelList | Sort-Object -Property Model
}

# Function to download and extract drivers for a specific Panasonic model (Designed for ForEach-Object -Parallel)
function Save-PanasonicDriversTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData, # Contains Make, Model
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [string]$WindowsVersion, # e.g., 22H2, 23H2, etc.
        [Parameter()] # Made optional
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null, # Default to null
        [Parameter()]
        [bool]$CompressToWim = $false, # New parameter for compression
        [Parameter()]
        [bool]$PreserveSourceOnCompress = $false
    )

    $modelName = $DriverItemData.Model
    $make = $DriverItemData.Make # Should be 'Panasonic'
    $identifier = $modelName # Unique identifier for progress updates
    $sanitizedModelName = ConvertTo-SafeName -Name $modelName
    if ($sanitizedModelName -ne $modelName) { WriteLog "Sanitized model name: '$modelName' -> '$sanitizedModelName'" }
    $panasonicBaseFolder = Join-Path -Path $DriversFolder -ChildPath $make
    $catalogXml = Join-Path -Path $panasonicBaseFolder -ChildPath "PanasonicSCCM.xml"
    $modelSpecificFolder = Join-Path -Path $panasonicBaseFolder -ChildPath $sanitizedModelName
    $driverRelativePath = Join-Path -Path $make -ChildPath $sanitizedModelName # Relative path for the driver folder
    $finalStatus = "" # Initialize final status
    $successState = $true # Assume success unless an operation fails

    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking Panasonic drivers for $modelName..." }

    try {
        # Check for existing drivers
        $existingDriver = Test-ExistingDriver -Make $make -Model $sanitizedModelName -DriversFolder $DriversFolder -Identifier $identifier -ProgressQueue $ProgressQueue
        if ($null -ne $existingDriver) {
            # The return object from Test-ExistingDriver uses 'Model' as the identifier key.
            # We need to return 'Identifier' for Panasonic's logic.
            $existingDriver | Add-Member -MemberType NoteProperty -Name 'Identifier' -Value $identifier -Force
            $existingDriver.PSObject.Properties.Remove('Model')

            # Special handling for existing folders that need compression
            if ($CompressToWim -and $existingDriver.Status -eq 'Already downloaded') {
                $wimFilePath = Join-Path -Path $panasonicBaseFolder -ChildPath "$($sanitizedModelName).wim"
                $sourceFolderPath = Join-Path -Path $panasonicBaseFolder -ChildPath $sanitizedModelName
                WriteLog "Attempting compression of existing folder '$sourceFolderPath' to '$wimFilePath'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing existing..." }
                try {
                    Compress-DriverFolderToWim -SourceFolderPath $sourceFolderPath -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                    $existingDriver.Status = "Already downloaded & Compressed"
                    $existingDriver.DriverPath = Join-Path -Path $make -ChildPath "$($sanitizedModelName).wim"
                    $existingDriver.Success = $true
                    WriteLog "Successfully compressed existing drivers for $identifier to $wimFilePath."
                }
                catch {
                    WriteLog "Error compressing existing drivers for $($identifier): $($_.Exception.Message)"
                    $existingDriver.Status = "Already downloaded (Compression failed)"
                    $existingDriver.Success = $false
                }
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $existingDriver.Status }
            }

            $existingDriver
            return
        }

        # If folder does not exist, proceed with download and extraction
        WriteLog "Panasonic drivers for '$identifier' not found locally. Starting download process..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Downloading..." }

        # Ensure PanasonicSCCM.xml exists
        if (-not (Test-Path -Path $catalogXml)) {
            # Attempt to download/extract catalog if missing
            WriteLog "[Panasonic][$modelName][Catalog] PanasonicSCCM.xml not found, attempting download/extract..."
            $catalogUrl = [FFUConstants]::PANASONIC_CATALOG_URL
            if ([string]::IsNullOrEmpty($catalogUrl)) {
                throw "Panasonic SCCM catalog URL not configured and no cached catalog available. Manual driver download required for model '$modelName'."
            }
            $catalogCab = Join-Path -Path $panasonicBaseFolder -ChildPath "PanasonicSCCM.cab"
            if (-not (Test-Path -Path $panasonicBaseFolder)) {
                New-Item -Path $panasonicBaseFolder -ItemType Directory -Force | Out-Null
            }
            Start-BitsTransferWithRetry -Source $catalogUrl -Destination $catalogCab -ErrorAction Stop
            if (Test-Path -Path $catalogXml) { Remove-Item -Path $catalogXml -Force }
            # Note: Do not embed quotes in argument array - PowerShell handles quoting automatically
            Invoke-Process -FilePath "expand.exe" -ArgumentList @($catalogCab, $catalogXml) -ErrorAction Stop | Out-Null
            WriteLog "[Panasonic][$modelName][Catalog] PanasonicSCCM.xml download/extract complete."
            if (-not (Test-Path -Path $catalogXml)) {
                throw "Failed to obtain PanasonicSCCM.xml for Panasonic driver task."
            }
        }

        # Parse catalog XML to find driver pack URL for the model
        WriteLog "[Panasonic][$modelName][Catalog] Parsing PanasonicSCCM.xml for driver pack URL..."
        [xml]$catalogContent = Get-Content -Path $catalogXml -Raw -Encoding UTF8 -ErrorAction Stop

        $driverPackUrl = $null
        if ($catalogContent.SystemsManagementCatalog) {
            foreach ($package in $catalogContent.SystemsManagementCatalog.SoftwareDistributionPackage) {
                # Look for matching model
                $matchFound = $false
                foreach ($installableItem in $package.InstallableItem) {
                    if ($installableItem.ApplicabilityRules.IsInstallable.And) {
                        foreach ($wmiQuery in $installableItem.ApplicabilityRules.IsInstallable.And.WmiQuery) {
                            $wql = $wmiQuery.WqlQuery
                            if ($wql -match [regex]::Escape($modelName) -or $wql -match [regex]::Escape($sanitizedModelName)) {
                                $matchFound = $true
                                break
                            }
                        }
                    }
                    if ($matchFound) { break }
                }

                # Extract driver pack download URL from matching package
                if ($matchFound) {
                    # Look for OriginUri or ContentUri elements
                    if ($package.InstallableItem.OriginUri) {
                        $driverPackUrl = $package.InstallableItem.OriginUri | Select-Object -First 1
                    }
                    elseif ($package.PayloadFiles.File.OriginUri) {
                        $driverPackUrl = $package.PayloadFiles.File.OriginUri | Select-Object -First 1
                    }
                    if ($driverPackUrl) {
                        WriteLog "[Panasonic][$modelName][Download] Found driver pack URL: $driverPackUrl"
                        break
                    }
                }
            }
        }

        if ([string]::IsNullOrEmpty($driverPackUrl)) {
            WriteLog "WARNING: [Panasonic][$modelName][Download] No driver pack URL found in catalog for model '$modelName' and Windows $WindowsRelease. Manual driver download may be required."
            throw "No driver pack URL found in Panasonic catalog for model '$modelName'"
        }

        # Download the driver pack CAB
        $driverCabFileName = Split-Path -Path $driverPackUrl -Leaf
        $driverCabPath = Join-Path -Path $panasonicBaseFolder -ChildPath $driverCabFileName

        WriteLog "[Panasonic][$modelName][Download] Downloading driver pack from $driverPackUrl to $driverCabPath"
        Start-BitsTransferWithRetry -Source $driverPackUrl -Destination $driverCabPath -ErrorAction Stop
        WriteLog "[Panasonic][$modelName][Download] Driver pack download complete."

        # Extract the CAB using expand.exe
        if (-not (Test-Path -Path $modelSpecificFolder)) {
            New-Item -Path $modelSpecificFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Extracting..." }
        WriteLog "[Panasonic][$modelName][Extract] Extracting driver pack to $modelSpecificFolder"
        # Note: Do not embed quotes in argument array - PowerShell handles quoting automatically
        # expand.exe -F:* extracts all files from the CAB
        Invoke-Process -FilePath "expand.exe" -ArgumentList @($driverCabPath, '-F:*', $modelSpecificFolder) -ErrorAction Stop | Out-Null
        WriteLog "[Panasonic][$modelName][Extract] Driver extraction complete."

        # Clean up the downloaded CAB file
        Remove-Item -Path $driverCabPath -Force -ErrorAction SilentlyContinue
        WriteLog "[Panasonic][$modelName][Cleanup] Removed driver CAB file: $driverCabPath"

        $finalStatus = "Completed"
        if ($CompressToWim) {
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing..." }
            $wimFilePath = Join-Path -Path $panasonicBaseFolder -ChildPath "$($sanitizedModelName).wim"
            WriteLog "Compressing '$modelSpecificFolder' to '$wimFilePath'..."
            try {
                Compress-DriverFolderToWim -SourceFolderPath $modelSpecificFolder -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                WriteLog "Compression successful for '$identifier'."
                $finalStatus = "Completed & Compressed"
                $driverRelativePath = Join-Path -Path $make -ChildPath "$($sanitizedModelName).wim" # Update relative path to the WIM
            }
            catch {
                WriteLog "Error during compression for '$identifier': $($_.Exception.Message)"
                $finalStatus = "Completed (Compression Failed)"
            }
        }
        $successState = $true
    }
    catch {
        $errorMessage = "Error saving Panasonic drivers for $($modelName): $($_.Exception.Message)"
        WriteLog $errorMessage
        $finalStatus = "Error: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
        $successState = $false
        $driverRelativePath = $null # Ensure path is null on error
        if (Test-Path -Path $modelSpecificFolder -PathType Container) {
            WriteLog "Attempting to remove partially created folder $modelSpecificFolder due to error."
            Remove-Item -Path $modelSpecificFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $finalStatus }
    return [PSCustomObject]@{ Identifier = $identifier; Status = $finalStatus; Success = $successState; DriverPath = $driverRelativePath }
}

Export-ModuleMember -Function *
