<#
.SYNOPSIS
    Provides functions to retrieve Acer model lists and download corresponding driver packs.
.DESCRIPTION
    This module contains the logic specific to handling Acer drivers for the FFU Builder UI. It includes functions to:
    - Download and parse the AcerCatalog.xml to generate a list of supported Acer computer models.
    - For a selected model, find the most appropriate SCCM driver pack based on the OS version.
    - Download the driver pack (CAB or ZIP), extract driver files.
    - Optionally compress the final extracted drivers into a single WIM file.
    These functions are designed to be called by the main UI logic via the Get-ModelsForMake switch block.
#>

# Function to get the list of Acer models from the AcerCatalog.xml
function Get-AcerDriversModelList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$Make  # Expected to be 'Acer'
    )

    WriteLog "Getting Acer driver model list..."
    $acerDriversFolder = Join-Path -Path $DriversFolder -ChildPath $Make
    $catalogXmlPath = Join-Path -Path $acerDriversFolder -ChildPath "AcerCatalog.xml"
    $modelList = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        # Ensure Acer drivers folder exists
        if (-not (Test-Path -Path $acerDriversFolder)) {
            WriteLog "Creating Acer Drivers folder: $acerDriversFolder"
            New-Item -Path $acerDriversFolder -ItemType Directory -Force | Out-Null
        }

        # Download/cache the catalog XML - fallback approach for compatibility
        # Manual cache check + download (same as HP pattern)
        if (-not (Test-Path -Path $catalogXmlPath) -or ((Get-Date) - (Get-Item $catalogXmlPath).LastWriteTime).TotalDays -gt 7) {
            WriteLog "Downloading AcerCatalog.xml to $catalogXmlPath"
            Start-BitsTransferWithRetry -Source ([FFUConstants]::ACER_CATALOG_URL) -Destination $catalogXmlPath -ErrorAction Stop
            WriteLog "AcerCatalog.xml download complete."
        } else {
            WriteLog "Using existing AcerCatalog.xml found at $catalogXmlPath"
        }

        # Parse the XML to extract model list
        WriteLog "Parsing AcerCatalog.xml to extract Acer models..."
        [xml]$catalogContent = Get-Content -Path $catalogXmlPath -Raw -Encoding UTF8 -ErrorAction Stop

        # Defensive parser - try expected schema first
        $uniqueModels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $modelsFound = $false

        # Try expected schema: ModelList/Model with name attribute
        if ($catalogContent.AcerCatalog.ModelList.Model) {
            foreach ($modelNode in $catalogContent.AcerCatalog.ModelList.Model) {
                $modelName = $modelNode.name
                if (-not [string]::IsNullOrWhiteSpace($modelName) -and $uniqueModels.Add($modelName)) {
                    $modelList.Add([PSCustomObject]@{
                        Make  = $Make
                        Model = $modelName
                    })
                }
            }
            $modelsFound = $true
        }

        # Fallback: Try any element with 'name' or 'Name' attribute at any depth
        if (-not $modelsFound) {
            WriteLog "Expected schema (ModelList/Model) not found, trying alternate approaches..."
            # Try XPath for any Model element at any depth
            $xpathModels = Select-Xml -Xml $catalogContent -XPath "//Model"
            if ($xpathModels) {
                foreach ($modelXml in $xpathModels) {
                    $modelName = $modelXml.Node.name
                    if (-not [string]::IsNullOrWhiteSpace($modelName) -and $uniqueModels.Add($modelName)) {
                        $modelList.Add([PSCustomObject]@{
                            Make  = $Make
                            Model = $modelName
                        })
                    }
                }
                $modelsFound = $true
            }
        }

        # Log schema information if no models found
        if (-not $modelsFound -or $modelList.Count -eq 0) {
            WriteLog "WARNING: Could not find models in expected schema. Root element: $($catalogContent.DocumentElement.LocalName)"
            if ($catalogContent.DocumentElement.ChildNodes) {
                WriteLog "Root child elements: $($catalogContent.DocumentElement.ChildNodes.LocalName -join ', ')"
            }
        }

        WriteLog "Successfully parsed $($modelList.Count) unique Acer models from AcerCatalog.xml."

    }
    catch {
        WriteLog "Error getting Acer driver model list: $($_.Exception.Message)"
    }

    # Sort the list alphabetically by Model name before returning
    $modelList | Sort-Object -Property Model
}

# Function to download and extract drivers for a specific Acer model (Designed for ForEach-Object -Parallel)
function Save-AcerDriversTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData,  # Contains Make, Model
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [string]$WindowsVersion,  # e.g., 22H2, 23H2
        [Parameter()]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null,
        [Parameter()]
        [bool]$CompressToWim = $false,
        [Parameter()]
        [bool]$PreserveSourceOnCompress = $false
    )

    $modelName = $DriverItemData.Model
    $make = $DriverItemData.Make
    $identifier = $modelName
    $sanitizedModelName = ConvertTo-SafeName -Name $modelName
    if ($sanitizedModelName -ne $modelName) { WriteLog "Sanitized model name: '$modelName' -> '$sanitizedModelName'" }
    $acerDriversBaseFolder = Join-Path -Path $DriversFolder -ChildPath $make
    $catalogXmlPath = Join-Path -Path $acerDriversBaseFolder -ChildPath "AcerCatalog.xml"
    $modelSpecificFolder = Join-Path -Path $acerDriversBaseFolder -ChildPath $sanitizedModelName
    $driverRelativePath = Join-Path -Path $make -ChildPath $sanitizedModelName
    $finalStatus = ""
    $successState = $true

    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking Acer drivers for $modelName..." }

    try {
        # Check for existing drivers
        $existingDriver = Test-ExistingDriver -Make $make -Model $sanitizedModelName -DriversFolder $DriversFolder -Identifier $identifier -ProgressQueue $ProgressQueue
        if ($null -ne $existingDriver) {
            # The return object from Test-ExistingDriver uses 'Model' as the identifier key.
            # We need to return 'Identifier' for Acer's logic.
            $existingDriver | Add-Member -MemberType NoteProperty -Name 'Identifier' -Value $identifier -Force
            $existingDriver.PSObject.Properties.Remove('Model')

            # Special handling for existing folders that need compression
            if ($CompressToWim -and $existingDriver.Status -eq 'Already downloaded') {
                $wimFilePath = Join-Path -Path $acerDriversBaseFolder -ChildPath "$($sanitizedModelName).wim"
                $sourceFolderPath = Join-Path -Path $acerDriversBaseFolder -ChildPath $sanitizedModelName
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
        WriteLog "Acer drivers for '$identifier' not found locally. Starting download process..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Downloading..." }

        # Ensure AcerCatalog.xml exists (it should have been downloaded by Get-AcerDriversModelList)
        if (-not (Test-Path -Path $catalogXmlPath)) {
            # Attempt to download it again if missing
            WriteLog "AcerCatalog.xml not found for Acer task, attempting download..."
            if (-not (Test-Path -Path $acerDriversBaseFolder)) {
                New-Item -Path $acerDriversBaseFolder -ItemType Directory -Force | Out-Null
            }
            Start-BitsTransferWithRetry -Source ([FFUConstants]::ACER_CATALOG_URL) -Destination $catalogXmlPath -ErrorAction Stop
            WriteLog "AcerCatalog.xml download complete for Acer task."
            if (-not (Test-Path -Path $catalogXmlPath)) {
                throw "Failed to obtain AcerCatalog.xml for Acer driver task."
            }
        }

        # Parse catalog XML to find the selected model's driver package URL
        WriteLog "Parsing $catalogXmlPath for model '$modelName' details..."
        [xml]$catalogContent = Get-Content -Path $catalogXmlPath -Raw -Encoding UTF8 -ErrorAction Stop

        # Find model node matching $modelName
        $modelNode = $null
        if ($catalogContent.AcerCatalog.ModelList.Model) {
            $modelNode = $catalogContent.AcerCatalog.ModelList.Model | Where-Object { $_.name -eq $modelName } | Select-Object -First 1
        }

        # Fallback: try XPath if initial search fails
        if ($null -eq $modelNode) {
            $xpathResult = Select-Xml -Xml $catalogContent -XPath "//Model[@name='$modelName']"
            if ($xpathResult) {
                $modelNode = $xpathResult.Node
            }
        }

        if ($null -eq $modelNode) {
            throw "Model '$modelName' not found in AcerCatalog.xml."
        }

        # Find SCCM child element matching requested OS
        $sccmNode = $null
        $requestedOsString = "Windows $WindowsRelease"

        # Try to find exact match first
        foreach ($sccm in $modelNode.SCCM) {
            $osAttr = $sccm.os
            $versionAttr = $sccm.version

            if ($osAttr -like "*$requestedOsString*" -and $versionAttr -eq $WindowsVersion) {
                $sccmNode = $sccm
                WriteLog "Found exact match for $requestedOsString $WindowsVersion"
                break
            }
        }

        # Fallback: find newest version for same OS release
        if ($null -eq $sccmNode) {
            WriteLog "Exact version match not found, attempting fallback to newest version for $requestedOsString..."
            $matchingOs = $modelNode.SCCM | Where-Object { $_.os -like "*$requestedOsString*" }
            if ($matchingOs) {
                # Sort by version and take newest (simple string comparison should work for most cases)
                $sccmNode = $matchingOs | Sort-Object -Property version -Descending | Select-Object -First 1
                WriteLog "Using fallback version: $($sccmNode.version)"
            }
        }

        if ($null -eq $sccmNode) {
            throw "No driver pack found for Acer model '$modelName' matching Windows $WindowsRelease $WindowsVersion"
        }

        # Extract driver package URL
        $driverPackUrl = $sccmNode.'#text'
        if ([string]::IsNullOrWhiteSpace($driverPackUrl)) {
            $driverPackUrl = $sccmNode.InnerText
        }

        if ([string]::IsNullOrWhiteSpace($driverPackUrl)) {
            throw "Driver package URL is empty for model '$modelName'"
        }

        WriteLog "Found driver pack URL: $driverPackUrl"

        # Download driver package
        $extension = [System.IO.Path]::GetExtension($driverPackUrl)
        if ([string]::IsNullOrWhiteSpace($extension)) {
            # Default to .cab if no extension
            $extension = ".cab"
        }
        $driverPackFile = Join-Path -Path $acerDriversBaseFolder -ChildPath "AcerDriverPack_$($sanitizedModelName)$extension"

        WriteLog "Downloading driver pack to $driverPackFile"
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Downloading driver pack..." }
        Start-BitsTransferWithRetry -Source $driverPackUrl -Destination $driverPackFile -ErrorAction Stop
        WriteLog "Driver pack download complete."

        # Extract driver package
        if (-not (Test-Path -Path $modelSpecificFolder)) {
            New-Item -Path $modelSpecificFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Extracting drivers..." }
        WriteLog "Extracting driver pack to $modelSpecificFolder"

        if ($extension -eq ".cab") {
            # CAB extraction using expand.exe
            WriteLog "Extracting CAB file using expand.exe"
            Invoke-Process -FilePath "expand.exe" -ArgumentList @($driverPackFile, "-F:*", $modelSpecificFolder) -ErrorAction Stop | Out-Null
        }
        elseif ($extension -eq ".zip") {
            # ZIP extraction using Expand-Archive
            WriteLog "Extracting ZIP file using Expand-Archive"
            Expand-Archive -Path $driverPackFile -DestinationPath $modelSpecificFolder -Force -ErrorAction Stop
        }
        else {
            # Unknown format - try ZIP as default
            WriteLog "WARNING: Unknown driver pack format '$extension', attempting ZIP extraction..."
            Expand-Archive -Path $driverPackFile -DestinationPath $modelSpecificFolder -Force -ErrorAction Stop
        }

        WriteLog "Driver pack extraction complete."

        # Cleanup: Remove downloaded archive
        Remove-Item -Path $driverPackFile -Force -ErrorAction SilentlyContinue
        WriteLog "Deleted driver pack file: $driverPackFile"

        $finalStatus = "Completed"

        # WIM compression if requested
        if ($CompressToWim) {
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing..." }
            $wimFilePath = Join-Path -Path $acerDriversBaseFolder -ChildPath "$($sanitizedModelName).wim"
            WriteLog "Compressing '$modelSpecificFolder' to '$wimFilePath'..."
            try {
                Compress-DriverFolderToWim -SourceFolderPath $modelSpecificFolder -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                WriteLog "Compression successful for '$identifier'."
                $finalStatus = "Completed & Compressed"
                $driverRelativePath = Join-Path -Path $make -ChildPath "$($sanitizedModelName).wim"
            }
            catch {
                WriteLog "Error during compression for '$identifier': $($_.Exception.Message)"
                $finalStatus = "Completed (Compression Failed)"
            }
        }
        $successState = $true
    }
    catch {
        $errorMessage = "Error saving Acer drivers for $($modelName): $($_.Exception.Message)"
        WriteLog $errorMessage
        $finalStatus = "Error: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
        $successState = $false
        $driverRelativePath = $null
        if (Test-Path -Path $modelSpecificFolder -PathType Container) {
            WriteLog "Attempting to remove partially created folder $modelSpecificFolder due to error."
            Remove-Item -Path $modelSpecificFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $finalStatus }
    return [PSCustomObject]@{ Identifier = $identifier; Status = $finalStatus; Success = $successState; DriverPath = $driverRelativePath }
}

Export-ModuleMember -Function *
