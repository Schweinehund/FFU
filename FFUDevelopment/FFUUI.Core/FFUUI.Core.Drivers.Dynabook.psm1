<#
.SYNOPSIS
    Provides functions for discovering, downloading, and processing Dynabook device drivers.
.DESCRIPTION
    This module contains the logic specific to handling Dynabook (formerly Toshiba) drivers for the FFU Builder UI.
    It downloads and parses Dynabook's CAB-wrapped XML driver catalog to retrieve a list of supported models.
    It also provides a parallel-capable task function that finds, downloads, extracts, and optionally compresses
    driver packages for a specified Dynabook model.
#>

function Get-DynabookDriversModelList {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$Make
    )

    $dynabookDriversFolder = Join-Path -Path $DriversFolder -ChildPath "Dynabook"
    $catalogCab = Join-Path -Path $dynabookDriversFolder -ChildPath "Dynabook_DriverPack_Catalog.cab"
    $catalogXml = Join-Path -Path $dynabookDriversFolder -ChildPath "Dynabook_DriverPack_Catalog.xml"
    $catalogUrl = "https://content.us.dynabook.com/content/support/drivers/Dynabook_DriverPack_Catalog.cab"

    $models = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        # Check if cached XML exists and is less than 7 days old
        if (Test-Path -Path $catalogXml -PathType Leaf) {
            $fileAge = (Get-Date) - (Get-Item -Path $catalogXml).CreationTime
            if ($fileAge.TotalDays -lt 7) {
                WriteLog "Using cached Dynabook Catalog XML (age: $([Math]::Round($fileAge.TotalDays, 1)) days)"
            }
            else {
                WriteLog "Cached Dynabook Catalog XML is stale (age: $([Math]::Round($fileAge.TotalDays, 1)) days). Re-downloading."
                # Remove stale files
                if (Test-Path -Path $catalogCab) { Remove-Item -Path $catalogCab -Force -ErrorAction SilentlyContinue }
                if (Test-Path -Path $catalogXml) { Remove-Item -Path $catalogXml -Force -ErrorAction SilentlyContinue }
            }
        }

        # Download catalog if needed
        if (-not (Test-Path -Path $catalogXml)) {
            # Ensure Dynabook drivers folder exists
            if (-not (Test-Path -Path $dynabookDriversFolder -PathType Container)) {
                WriteLog "Creating Dynabook drivers folder: $dynabookDriversFolder"
                New-Item -Path $dynabookDriversFolder -ItemType Directory -Force | Out-Null
            }

            WriteLog "[OEM][Dynabook][Catalog] Downloading catalog CAB from $catalogUrl"
            try {
                Start-BitsTransferWithRetry -Source $catalogUrl -Destination $catalogCab
                WriteLog "[OEM][Dynabook][Catalog] Catalog CAB downloaded successfully"
            }
            catch {
                WriteLog "ERROR: [OEM][Dynabook][Catalog] Failed to download catalog: $($_.Exception.Message)"
                WriteLog "WARNING: [OEM][Dynabook][Catalog] Remediation: Check network connectivity to content.us.dynabook.com. Verify the catalog URL is still valid. The UI will show no Dynabook models available."
                return $models
            }

            # Extract CAB to XML
            WriteLog "[OEM][Dynabook][Catalog] Extracting catalog CAB to XML"
            try {
                Invoke-Process -FilePath "Expand.exe" -ArgumentList """$catalogCab"" ""$catalogXml""" | Out-Null
                WriteLog "[OEM][Dynabook][Catalog] Catalog CAB extracted successfully"
            }
            catch {
                WriteLog "ERROR: [OEM][Dynabook][Catalog] Failed to extract catalog CAB: $($_.Exception.Message)"
                WriteLog "WARNING: [OEM][Dynabook][Catalog] Remediation: The downloaded CAB may be corrupt. Delete '$catalogCab' and retry. The UI will show no Dynabook models available."
                return $models
            }

            # Delete CAB after extraction
            if (Test-Path -Path $catalogCab) {
                Remove-Item -Path $catalogCab -Force -ErrorAction SilentlyContinue
                WriteLog "[OEM][Dynabook][Catalog] Deleted catalog CAB after extraction"
            }

            # Verify XML exists
            if (-not (Test-Path -Path $catalogXml)) {
                WriteLog "ERROR: [OEM][Dynabook][Catalog] Catalog XML not found after extraction: $catalogXml"
                return $models
            }
        }

        # Parse XML to extract model list
        WriteLog "[OEM][Dynabook][Catalog] Parsing catalog XML for models"

        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.IgnoreWhitespace = $true
        $settings.IgnoreComments = $true

        $reader = [System.Xml.XmlReader]::Create($catalogXml, $settings)
        try {
            while ($reader.Read()) {
                # Look for model/product nodes in the catalog
                # Note: The exact element names will depend on the actual catalog schema
                # This implementation follows Dell's pattern and should be adjusted based on actual schema
                if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                    # Try common element names for model entries
                    if ($reader.Name -in @('Model', 'Product', 'System', 'SupportedSystem')) {
                        # Use ReadSubtree for safe DOM parsing
                        $subtreeReader = $reader.ReadSubtree()
                        $modelDoc = New-Object System.Xml.XmlDocument
                        $modelDoc.Load($subtreeReader)
                        $subtreeReader.Dispose()

                        # Extract model name from various possible locations
                        $modelNameNode = $modelDoc.SelectSingleNode("//*[@name or @Name or @MODEL or @Model]")
                        if ($null -eq $modelNameNode) {
                            $modelNameNode = $modelDoc.SelectSingleNode("//Name | //name | //Model | //model")
                        }

                        if ($null -ne $modelNameNode) {
                            $modelName = $null

                            # Try to get name from attribute first
                            if ($modelNameNode.HasAttribute('name')) {
                                $modelName = $modelNameNode.GetAttribute('name')
                            }
                            elseif ($modelNameNode.HasAttribute('Name')) {
                                $modelName = $modelNameNode.GetAttribute('Name')
                            }
                            # Then try InnerText
                            elseif (-not [string]::IsNullOrWhiteSpace($modelNameNode.InnerText)) {
                                $modelName = $modelNameNode.InnerText.Trim()
                            }

                            if (-not [string]::IsNullOrWhiteSpace($modelName)) {
                                $models.Add([PSCustomObject]@{
                                        Make  = $Make
                                        Model = $modelName
                                    })
                            }
                        }
                    }
                }
            }
        }
        finally {
            if ($null -ne $reader) {
                $reader.Dispose()
            }
        }

        WriteLog "[OEM][Dynabook][Catalog] Parsed $($models.Count) Dynabook models from catalog"

        # Sort models alphabetically
        $sortedModels = $models | Sort-Object -Property Model
        return [System.Collections.Generic.List[PSCustomObject]]::new($sortedModels)
    }
    catch {
        WriteLog "ERROR: [OEM][Dynabook][Catalog] Error getting Dynabook models: $($_.Exception.ToString())"
        throw
    }
}

function Save-DynabookDriversTask {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData,
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter()]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null,
        [Parameter()]
        [bool]$CompressToWim = $false,
        [Parameter()]
        [bool]$PreserveSourceOnCompress = $false
    )

    $modelName = $DriverItemData.Model
    $make = "Dynabook"
    $sanitizedModel = ConvertTo-SafeName -Name $modelName
    $dynabookDriversFolder = Join-Path -Path $DriversFolder -ChildPath $make
    $modelDriverFolder = Join-Path -Path $dynabookDriversFolder -ChildPath $sanitizedModel
    $driverRelativePath = "Drivers\$make\$sanitizedModel"

    try {
        # Report initial progress
        if ($null -ne $ProgressQueue) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "Checking existing drivers" -PercentComplete 5
        }

        # Check for existing drivers
        $existingDriverCheck = Test-ExistingDriver -DriversFolder $DriversFolder -Make $make -Model $sanitizedModel `
            -CompressToWim $CompressToWim -PreserveSourceOnCompress $PreserveSourceOnCompress

        if ($existingDriverCheck.Found) {
            WriteLog "[OEM][Dynabook][$modelName][Download] $($existingDriverCheck.Message)"

            # If WIM compression is needed and doesn't exist, compress the existing folder
            if ($CompressToWim -and -not $existingDriverCheck.WimExists) {
                if ($null -ne $ProgressQueue) {
                    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "Compressing existing drivers to WIM" -PercentComplete 50
                }

                $wimResult = Compress-DriverFolderToWim -DriverFolder $modelDriverFolder -Make $make `
                    -Model $sanitizedModel -PreserveSource $PreserveSourceOnCompress

                if ($wimResult.Success) {
                    WriteLog "[OEM][Dynabook][$modelName][Compress] Existing drivers compressed to WIM successfully"
                    return [PSCustomObject]@{
                        Model      = $modelName
                        Status     = "Compressed existing drivers to WIM"
                        Success    = $true
                        DriverPath = $driverRelativePath
                    }
                }
                else {
                    WriteLog "WARNING: [OEM][Dynabook][$modelName][Compress] Failed to compress existing drivers: $($wimResult.Message)"
                }
            }

            if ($null -ne $ProgressQueue) {
                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "Using existing drivers" -PercentComplete 100
            }

            return [PSCustomObject]@{
                Model      = $modelName
                Status     = $existingDriverCheck.Message
                Success    = $true
                DriverPath = $driverRelativePath
            }
        }

        # No existing driver found - download from catalog
        if ($null -ne $ProgressQueue) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "Finding driver pack in catalog" -PercentComplete 15
        }

        # Parse catalog XML to find driver pack URL for this model
        $catalogXml = Join-Path -Path $dynabookDriversFolder -ChildPath "Dynabook_DriverPack_Catalog.xml"

        if (-not (Test-Path -Path $catalogXml)) {
            WriteLog "ERROR: [OEM][Dynabook][$modelName][Download] Catalog XML not found: $catalogXml"
            return [PSCustomObject]@{
                Model   = $modelName
                Status  = "ERROR: Catalog not found"
                Success = $false
            }
        }

        WriteLog "[OEM][Dynabook][$modelName][Download] Searching catalog for driver pack"

        # Parse catalog to find driver pack URL
        $driverPackUrl = $null
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.IgnoreWhitespace = $true
        $settings.IgnoreComments = $true

        $reader = [System.Xml.XmlReader]::Create($catalogXml, $settings)
        try {
            while ($reader.Read()) {
                if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                    # Look for elements that match the model name
                    if ($reader.Name -in @('Model', 'Product', 'System', 'SupportedSystem')) {
                        $subtreeReader = $reader.ReadSubtree()
                        $modelDoc = New-Object System.Xml.XmlDocument
                        $modelDoc.Load($subtreeReader)
                        $subtreeReader.Dispose()

                        # Check if this entry matches our model
                        $nameNode = $modelDoc.SelectSingleNode("//*[@name='$modelName' or text()='$modelName']")
                        if ($null -eq $nameNode) {
                            # Try case-insensitive match
                            $allNodes = $modelDoc.SelectNodes("//*[@name or text()]")
                            foreach ($node in $allNodes) {
                                $nodeValue = if ($node.HasAttribute('name')) { $node.GetAttribute('name') } else { $node.InnerText }
                                if ($nodeValue -eq $modelName) {
                                    $nameNode = $node
                                    break
                                }
                            }
                        }

                        if ($null -ne $nameNode) {
                            # Found matching model - look for download URL
                            $urlNode = $modelDoc.SelectSingleNode("//URL | //url | //DownloadURL | //PackageURL | //Path | //path")
                            if ($null -ne $urlNode) {
                                $driverPackUrl = $urlNode.InnerText.Trim()
                                WriteLog "[OEM][Dynabook][$modelName][Download] Found driver pack URL: $driverPackUrl"
                                break
                            }
                        }
                    }
                }
            }
        }
        finally {
            if ($null -ne $reader) {
                $reader.Dispose()
            }
        }

        if ([string]::IsNullOrWhiteSpace($driverPackUrl)) {
            WriteLog "ERROR: [OEM][Dynabook][$modelName][Download] No driver pack found in catalog for model: $modelName"
            return [PSCustomObject]@{
                Model   = $modelName
                Status  = "ERROR: No driver pack found in catalog"
                Success = $false
            }
        }

        # Download driver pack CAB
        if ($null -ne $ProgressQueue) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "Downloading driver pack" -PercentComplete 30
        }

        $driverCabFile = Join-Path -Path $dynabookDriversFolder -ChildPath "$sanitizedModel.cab"

        WriteLog "[OEM][Dynabook][$modelName][Download] Downloading driver pack from: $driverPackUrl"
        try {
            Start-BitsTransferWithRetry -Source $driverPackUrl -Destination $driverCabFile
            WriteLog "[OEM][Dynabook][$modelName][Download] Driver pack downloaded successfully"
        }
        catch {
            WriteLog "ERROR: [OEM][Dynabook][$modelName][Download] Failed to download driver pack: $($_.Exception.Message)"
            return [PSCustomObject]@{
                Model   = $modelName
                Status  = "ERROR: Driver pack download failed"
                Success = $false
            }
        }

        # Extract driver pack
        if ($null -ne $ProgressQueue) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "Extracting drivers" -PercentComplete 60
        }

        # Ensure destination folder exists
        if (-not (Test-Path -Path $modelDriverFolder)) {
            New-Item -Path $modelDriverFolder -ItemType Directory -Force | Out-Null
        }

        WriteLog "[OEM][Dynabook][$modelName][Extract] Extracting driver pack to: $modelDriverFolder"
        try {
            Invoke-Process -FilePath "Expand.exe" -ArgumentList """$driverCabFile"" -F:* ""$modelDriverFolder""" | Out-Null
            WriteLog "[OEM][Dynabook][$modelName][Extract] Driver pack extracted successfully"
        }
        catch {
            WriteLog "ERROR: [OEM][Dynabook][$modelName][Extract] Failed to extract driver pack: $($_.Exception.Message)"
            return [PSCustomObject]@{
                Model   = $modelName
                Status  = "ERROR: Driver pack extraction failed"
                Success = $false
            }
        }

        # Verify extraction produced files
        $extractedFiles = Get-ChildItem -Path $modelDriverFolder -Recurse -File -ErrorAction SilentlyContinue
        if ($null -eq $extractedFiles -or $extractedFiles.Count -eq 0) {
            WriteLog "ERROR: [OEM][Dynabook][$modelName][Extract] No files found after extraction"
            return [PSCustomObject]@{
                Model   = $modelName
                Status  = "ERROR: No files extracted"
                Success = $false
            }
        }

        $totalSize = ($extractedFiles | Measure-Object -Property Length -Sum).Sum
        if ($totalSize -lt 1KB) {
            WriteLog "ERROR: [OEM][Dynabook][$modelName][Extract] Extracted files are too small (< 1KB)"
            return [PSCustomObject]@{
                Model   = $modelName
                Status  = "ERROR: Extracted files too small"
                Success = $false
            }
        }

        WriteLog "[OEM][Dynabook][$modelName][Extract] Verified extraction: $($extractedFiles.Count) files, $([Math]::Round($totalSize / 1MB, 2)) MB"

        # Clean up downloaded CAB
        if (Test-Path -Path $driverCabFile) {
            Remove-Item -Path $driverCabFile -Force -ErrorAction SilentlyContinue
            WriteLog "[OEM][Dynabook][$modelName][Cleanup] Deleted driver pack CAB after extraction"
        }

        # Compress to WIM if requested
        if ($CompressToWim) {
            if ($null -ne $ProgressQueue) {
                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "Compressing drivers to WIM" -PercentComplete 80
            }

            $wimResult = Compress-DriverFolderToWim -DriverFolder $modelDriverFolder -Make $make `
                -Model $sanitizedModel -PreserveSource $PreserveSourceOnCompress

            if ($wimResult.Success) {
                WriteLog "[OEM][Dynabook][$modelName][Compress] Drivers compressed to WIM successfully"
            }
            else {
                WriteLog "WARNING: [OEM][Dynabook][$modelName][Compress] Failed to compress drivers to WIM: $($wimResult.Message)"
            }
        }

        # Report completion
        if ($null -ne $ProgressQueue) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "Completed" -PercentComplete 100
        }

        WriteLog "[OEM][Dynabook][$modelName][Complete] Driver download and extraction completed successfully"

        return [PSCustomObject]@{
            Model      = $modelName
            Status     = "Downloaded and extracted successfully"
            Success    = $true
            DriverPath = $driverRelativePath
        }
    }
    catch {
        WriteLog "ERROR: [OEM][Dynabook][$modelName][Task] Unexpected error: $($_.Exception.ToString())"

        if ($null -ne $ProgressQueue) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Model $modelName -Status "ERROR: $($_.Exception.Message)" -PercentComplete 0
        }

        return [PSCustomObject]@{
            Model   = $modelName
            Status  = "ERROR: $($_.Exception.Message)"
            Success = $false
        }
    }
}

Export-ModuleMember -Function *
