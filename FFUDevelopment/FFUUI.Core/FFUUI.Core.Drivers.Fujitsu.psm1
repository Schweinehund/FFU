<#
.SYNOPSIS
    Provides functions for discovering, downloading, and processing Fujitsu drivers.

.DESCRIPTION
    This module contains the logic specific to handling Fujitsu LIFEBOOK and STYLISTIC
    drivers for the FFU Builder UI. Fujitsu uses a search-input pattern (similar to Lenovo)
    because the product range is large and spans multiple regions.

    The implementation scrapes Fujitsu's support portal for model-specific driver packages
    and handles mixed download formats (EXE with silent extraction and ZIP archives).

    FALLBACK BEHAVIOR: When the Fujitsu support portal is unreachable or returns no results,
    the module automatically falls back to a curated static list of common enterprise
    LIFEBOOK and STYLISTIC models. The portal provides the most current drivers, while the
    fallback ensures the UI remains functional during portal outages.

    The module provides:
    - Model discovery via search (portal scraping + static fallback)
    - Background task for downloading and extracting driver packages
    - Mixed format extraction (EXE with /extract or /s /e flags, ZIP with Expand-Archive)
    - Robust error handling with graceful degradation
    - WIM compression support for driver packages

.NOTES
    Version: 1.0.0
    - 1.0.0: Initial Tier 2 implementation with portal scraping and static fallback
#>

# Function to get the list of Fujitsu models using portal search
function Get-FujitsuDriversModelList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelSearchTerm,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$UserAgent
    )

    $models = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Static fallback list of common Fujitsu enterprise models
    $knownModels = @(
        'LIFEBOOK U7412', 'LIFEBOOK U7512', 'LIFEBOOK U7612',
        'LIFEBOOK U9312', 'LIFEBOOK U9312X',
        'LIFEBOOK E5412', 'LIFEBOOK E5512',
        'LIFEBOOK A3510', 'LIFEBOOK A3511',
        'LIFEBOOK U7311', 'LIFEBOOK U7411', 'LIFEBOOK U7511',
        'LIFEBOOK U9311', 'LIFEBOOK U9311X',
        'LIFEBOOK E5411', 'LIFEBOOK E5511',
        'STYLISTIC Q7312', 'STYLISTIC Q5010',
        'LIFEBOOK U7413', 'LIFEBOOK U7513',
        'LIFEBOOK E5413', 'LIFEBOOK E5513'
    )

    WriteLog "Querying Fujitsu support portal for model: $ModelSearchTerm"

    # Construct the Fujitsu support search URL
    $searchUrl = "https://support.ts.fujitsu.com/IndexSearch.asp?lng=COM&CT=1&ESSION=1&ProductSearch=$([uri]::EscapeDataString($ModelSearchTerm))"

    $portalSuccess = $false
    try {
        # Suppress verbose output during web request
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'

        $response = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop -TimeoutSec 30

        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Fujitsu portal query complete."

        # Parse HTML response to extract model names and product links
        # Look for product listing patterns - Fujitsu support pages have product links with ProductName parameter
        $linkPattern = '<a[^>]+href="([^"]*ProductName=([^"&]+)[^"]*)"[^>]*>([^<]+)</a>'
        $matches = [regex]::Matches($response.Content, $linkPattern)

        foreach ($match in $matches) {
            if ($match.Groups.Count -ge 4) {
                $productPageUrl = $match.Groups[1].Value
                # Ensure absolute URL
                if (-not $productPageUrl.StartsWith('http')) {
                    $productPageUrl = "https://support.ts.fujitsu.com/$($productPageUrl.TrimStart('/'))"
                }
                $productId = $match.Groups[2].Value
                $productName = $match.Groups[3].Value.Trim()

                # Filter out navigation/header links and ensure it matches the search term
                if ($productName -match 'LIFEBOOK|STYLISTIC' -and $productName -like "*$ModelSearchTerm*") {
                    $models.Add([PSCustomObject]@{
                        Make  = 'Fujitsu'
                        Model = $productName
                        Link  = $productPageUrl
                    })
                    $portalSuccess = $true
                }
            }
        }

        if ($models.Count -gt 0) {
            WriteLog "Found $($models.Count) Fujitsu models matching '$ModelSearchTerm' from portal."
        }
    }
    catch {
        WriteLog "Error querying Fujitsu support portal: $($_.Exception.Message)"
        # Will fall through to static fallback
    }

    # If portal returned no results or failed, use static fallback
    if ($models.Count -eq 0) {
        WriteLog "WARNING: Fujitsu portal search failed or returned no results. Using static model list."

        $filtered = $knownModels | Where-Object { $_ -like "*$ModelSearchTerm*" }

        foreach ($staticModel in $filtered) {
            $models.Add([PSCustomObject]@{
                Make  = 'Fujitsu'
                Model = $staticModel
                Link  = $null  # Save-FujitsuDriversTask will construct URL from model name
            })
        }

        if ($models.Count -gt 0) {
            WriteLog "Static fallback: Found $($models.Count) models matching '$ModelSearchTerm'."
        }
        else {
            WriteLog "No models found matching '$ModelSearchTerm' in portal or static list."
        }
    }

    $models
}

# Function to download and extract drivers for a specific Fujitsu model (Background Task)
function Save-FujitsuDriversTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData,
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$UserAgent,
        [Parameter()]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null,
        [Parameter()]
        [bool]$CompressToWim = $false,
        [Parameter()]
        [bool]$PreserveSourceOnCompress = $false
    )

    $identifier = $DriverItemData.Model
    $make = "Fujitsu"
    $sanitizedIdentifier = ConvertTo-SafeName -Name $identifier
    if ($sanitizedIdentifier -ne $identifier) {
        WriteLog "Sanitized model identifier: '$identifier' -> '$sanitizedIdentifier'"
    }
    $status = "Starting..."
    $success = $false

    # Define paths
    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $make
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedIdentifier
    $driverRelativePath = Join-Path -Path $make -ChildPath $sanitizedIdentifier
    $tempDownloadPath = Join-Path -Path $makeDriversPath -ChildPath "_TEMP_Fujitsu_$($sanitizedIdentifier)_$($PID)"

    if ($null -ne $ProgressQueue) {
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking..."
    }

    try {
        # Check for existing drivers
        $existingDriver = Test-ExistingDriver -Make $make -Model $sanitizedIdentifier -DriversFolder $DriversFolder -Identifier $identifier -ProgressQueue $ProgressQueue
        if ($null -ne $existingDriver) {
            # The return object from Test-ExistingDriver uses 'Model' as the identifier key.
            # We need to return 'Identifier' for Fujitsu's logic.
            $existingDriver | Add-Member -MemberType NoteProperty -Name 'Identifier' -Value $identifier -Force
            $existingDriver.PSObject.Properties.Remove('Model')

            # Special handling for existing folders that need compression
            if ($CompressToWim -and $existingDriver.Status -eq 'Already downloaded') {
                $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($sanitizedIdentifier).wim"
                $sourceFolderPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedIdentifier
                WriteLog "Attempting compression of existing folder '$sourceFolderPath' to '$wimFilePath'."
                if ($null -ne $ProgressQueue) {
                    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing existing..."
                }
                try {
                    Compress-DriverFolderToWim -SourceFolderPath $sourceFolderPath -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                    $existingDriver.Status = "Already downloaded & Compressed"
                    $existingDriver.DriverPath = Join-Path -Path $make -ChildPath "$($sanitizedIdentifier).wim"
                    $existingDriver.Success = $true
                    WriteLog "Successfully compressed existing drivers for $identifier to $wimFilePath."
                }
                catch {
                    WriteLog "Error compressing existing drivers for $($identifier): $($_.Exception.Message)"
                    $existingDriver.Status = "Already downloaded (Compression failed)"
                    $existingDriver.Success = $false
                }
                if ($null -ne $ProgressQueue) {
                    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $existingDriver.Status
                }
            }

            $existingDriver
            return
        }

        # Ensure base directories exist
        if (-not (Test-Path -Path $makeDriversPath)) {
            New-Item -Path $makeDriversPath -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path -Path $modelPath)) {
            New-Item -Path $modelPath -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path -Path $tempDownloadPath)) {
            New-Item -Path $tempDownloadPath -ItemType Directory -Force | Out-Null
        }

        # Determine driver download URL(s)
        $status = "Finding drivers..."
        if ($null -ne $ProgressQueue) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status
        }

        $driverUrls = @()

        if ($null -ne $DriverItemData.Link -and -not [string]::IsNullOrWhiteSpace($DriverItemData.Link)) {
            # Have a direct link from portal search - navigate and parse for downloads
            WriteLog "Navigating to Fujitsu product page: $($DriverItemData.Link)"
            try {
                $OriginalVerbosePreference = $VerbosePreference
                $VerbosePreference = 'SilentlyContinue'
                $productPage = Invoke-WebRequest -Uri $DriverItemData.Link -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop -TimeoutSec 30
                $VerbosePreference = $OriginalVerbosePreference

                # Look for download links - Fujitsu support pages have direct links to driver packs
                $downloadPattern = 'href="([^"]*\.(exe|zip))"'
                $downloadMatches = [regex]::Matches($productPage.Content, $downloadPattern)

                foreach ($downloadMatch in $downloadMatches) {
                    if ($downloadMatch.Groups.Count -ge 2) {
                        $driverUrl = $downloadMatch.Groups[1].Value
                        # Ensure absolute URL
                        if (-not $driverUrl.StartsWith('http')) {
                            $driverUrl = "https://support.ts.fujitsu.com/$($driverUrl.TrimStart('/'))"
                        }
                        # Filter for Windows driver packs
                        if ($driverUrl -match "win|driver|$WindowsRelease") {
                            $driverUrls += $driverUrl
                        }
                    }
                }
            }
            catch {
                WriteLog "WARNING: Failed to parse product page: $($_.Exception.Message)"
            }
        }

        # If no URLs from product page, construct search URL (static fallback case)
        if ($driverUrls.Count -eq 0) {
            $searchUrl = "https://support.ts.fujitsu.com/IndexDownload.asp?lng=COM&CT=1&LNG=EN&ProductSearch=$([uri]::EscapeDataString($identifier))&OSC=WIN&OSV=$WindowsRelease"
            WriteLog "Searching for drivers via: $searchUrl"
            try {
                $OriginalVerbosePreference = $VerbosePreference
                $VerbosePreference = 'SilentlyContinue'
                $searchPage = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop -TimeoutSec 30
                $VerbosePreference = $OriginalVerbosePreference

                # Parse for download links
                $downloadPattern = 'href="([^"]*\.(exe|zip))"'
                $downloadMatches = [regex]::Matches($searchPage.Content, $downloadPattern)

                foreach ($downloadMatch in $downloadMatches) {
                    if ($downloadMatch.Groups.Count -ge 2) {
                        $driverUrl = $downloadMatch.Groups[1].Value
                        # Ensure absolute URL
                        if (-not $driverUrl.StartsWith('http')) {
                            $driverUrl = "https://support.ts.fujitsu.com/$($driverUrl.TrimStart('/'))"
                        }
                        $driverUrls += $driverUrl
                    }
                }
            }
            catch {
                WriteLog "WARNING: Failed to search for drivers: $($_.Exception.Message)"
            }
        }

        if ($driverUrls.Count -eq 0) {
            WriteLog "WARNING: No driver packages found on Fujitsu support portal for model '$identifier' with Windows $WindowsRelease"
            $status = "No drivers found"
            $success = $false
            if ($null -ne $ProgressQueue) {
                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status
            }
            return [PSCustomObject]@{
                Identifier = $identifier
                Status = $status
                Success = $success
                DriverPath = $null
            }
        }

        WriteLog "Found $($driverUrls.Count) driver package(s) for '$identifier'"

        # Download and extract each driver package
        $packageCount = 0
        $successfulExtractions = 0

        foreach ($driverUrl in $driverUrls) {
            $packageCount++
            $fileName = [System.IO.Path]::GetFileName($driverUrl)
            $filePath = Join-Path -Path $tempDownloadPath -ChildPath $fileName

            $status = "($packageCount/$($driverUrls.Count)) Downloading $fileName..."
            if ($null -ne $ProgressQueue) {
                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status
            }
            WriteLog "($packageCount/$($driverUrls.Count)) Downloading: $driverUrl"

            try {
                Start-BitsTransferWithRetry -Source $driverUrl -Destination $filePath
                WriteLog "($packageCount/$($driverUrls.Count)) Downloaded: $fileName"
            }
            catch {
                WriteLog "($packageCount/$($driverUrls.Count)) WARNING: Failed to download '$fileName': $($_.Exception.Message). Skipping."
                continue
            }

            # Extract based on file extension
            $status = "($packageCount/$($driverUrls.Count)) Extracting $fileName..."
            if ($null -ne $ProgressQueue) {
                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status
            }

            # Use temporary extraction path to avoid long path issues
            $randomNumber = Get-Random -Minimum 1000 -Maximum 9999
            $tempExtractBase = Join-Path $env:TEMP "FujitsuDriverExtract_$randomNumber"
            $extractFolder = Join-Path $tempExtractBase ($fileName -replace '\.(exe|zip)$', '')
            $finalDestination = Join-Path $modelPath ($fileName -replace '\.(exe|zip)$', '')

            try {
                # Create temp extraction directory
                if (-not (Test-Path -Path $tempExtractBase)) {
                    New-Item -Path $tempExtractBase -ItemType Directory -Force | Out-Null
                }
                if (-not (Test-Path -Path $extractFolder)) {
                    New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
                }

                $extractionSucceeded = $false

                if ($fileName -like '*.zip') {
                    # ZIP extraction
                    WriteLog "($packageCount/$($driverUrls.Count)) Extracting ZIP: $fileName to $extractFolder"
                    Expand-Archive -Path $filePath -DestinationPath $extractFolder -Force -ErrorAction Stop
                    $extractionSucceeded = $true
                }
                elseif ($fileName -like '*.exe') {
                    # EXE silent extraction - try /extract first, fall back to /s /e
                    WriteLog "($packageCount/$($driverUrls.Count)) Extracting EXE: $fileName to $extractFolder"
                    try {
                        $extractArgs = "/extract `"$extractFolder`""
                        Invoke-Process -FilePath $filePath -ArgumentList $extractArgs -Wait $true | Out-Null
                        $extractionSucceeded = $true
                    }
                    catch {
                        WriteLog "($packageCount/$($driverUrls.Count)) WARNING: /extract failed for $fileName, trying /s /e flag..."
                        try {
                            $extractArgs = "/s /e=`"$extractFolder`""
                            Invoke-Process -FilePath $filePath -ArgumentList $extractArgs -Wait $true | Out-Null
                            $extractionSucceeded = $true
                        }
                        catch {
                            WriteLog "($packageCount/$($driverUrls.Count)) WARNING: EXE extraction failed for $fileName. Error: $($_.Exception.Message)"
                        }
                    }
                }
                else {
                    WriteLog "($packageCount/$($driverUrls.Count)) WARNING: Unknown file format '$fileName'. Skipping."
                }

                # Move from temp to final destination if extraction succeeded
                if ($extractionSucceeded) {
                    WriteLog "($packageCount/$($driverUrls.Count)) Moving extracted files to final destination..."

                    # Ensure final destination exists
                    if (-not (Test-Path -Path $finalDestination)) {
                        New-Item -Path $finalDestination -ItemType Directory -Force | Out-Null
                    }

                    # Move all items from temp to final
                    $extractedItems = Get-ChildItem -Path $extractFolder -ErrorAction Stop
                    foreach ($item in $extractedItems) {
                        $destPath = Join-Path -Path $finalDestination -ChildPath $item.Name
                        try {
                            Move-Item -Path $item.FullName -Destination $destPath -Force -ErrorAction Stop
                        }
                        catch {
                            WriteLog "($packageCount/$($driverUrls.Count)) WARNING: Failed to move '$($item.Name)': $($_.Exception.Message)"
                        }
                    }

                    WriteLog "($packageCount/$($driverUrls.Count)) Extraction complete: $fileName"
                    $successfulExtractions++

                    # Delete the downloaded file after successful extraction
                    Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                WriteLog "($packageCount/$($driverUrls.Count)) WARNING: Extraction error for '$fileName': $($_.Exception.Message)"
            }
            finally {
                # Clean up temp extraction folder
                if ($tempExtractBase -and (Test-Path -Path $tempExtractBase)) {
                    Remove-Item -Path $tempExtractBase -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Verify extracted content exists
        $extractedFiles = Get-ChildItem -Path $modelPath -Recurse -File -ErrorAction SilentlyContinue
        if ($extractedFiles.Count -eq 0) {
            WriteLog "WARNING: No driver files extracted for model '$identifier'. The driver packages may not contain extractable drivers."
            $status = "No files extracted"
            $success = $false
        }
        else {
            WriteLog "Successfully extracted $($extractedFiles.Count) driver files for model '$identifier'"
            $status = "Completed"
            $success = $true
        }

        # Compress to WIM if requested
        if ($CompressToWim -and $success) {
            $status = "Compressing..."
            if ($null -ne $ProgressQueue) {
                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status
            }
            $wimFileName = "$($sanitizedIdentifier).wim"
            $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
            $driverRelativePath = Join-Path -Path $make -ChildPath $wimFileName
            WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
            try {
                $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $identifier -WimDescription $identifier -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                if ($compressResult) {
                    WriteLog "Compression successful for '$identifier'."
                    $status = "Completed & Compressed"
                }
                else {
                    WriteLog "Compression failed for '$identifier'. Check verbose/error output from Compress-DriverFolderToWim."
                    $status = "Completed (Compression Failed)"
                }
            }
            catch {
                WriteLog "Error during compression for '$identifier': $($_.Exception.Message)"
                $status = "Completed (Compression Error)"
            }
        }
    }
    catch {
        $status = "Error: $($_.Exception.Message.Split('.')[0])"
        WriteLog "Error saving Fujitsu drivers for '$identifier': $($_.Exception.ToString())"
        $success = $false
        if ($null -ne $ProgressQueue) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status
        }
        return [PSCustomObject]@{
            Identifier = $identifier
            Status = $status
            Success = $success
            DriverPath = $null
        }
    }
    finally {
        # Clean up temp download folder
        WriteLog "Cleaning up temporary download folder: $tempDownloadPath"
        Remove-Item -Path $tempDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Enqueue final status
    if ($null -ne $ProgressQueue) {
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status
    }

    # Return final status
    return [PSCustomObject]@{
        Identifier = $identifier
        Status = $status
        Success = $success
        DriverPath = $driverRelativePath
    }
}

Export-ModuleMember -Function *
