<#
.SYNOPSIS
    Provides functions for discovering, downloading, and processing Samsung Galaxy Book device drivers.
.DESCRIPTION
    This module contains the logic specific to handling Samsung drivers for the FFU UI. Samsung's
    enterprise PC management portal (pcmanagement.biz.samsung.com) provides SCCM/MDT driver pack ZIPs
    for Galaxy Book models. The module attempts to parse the Samsung portal for available models, with
    a static fallback list of known Galaxy Book models when the portal is unreachable or its HTML
    structure changes. Driver packages are ZIP files extracted using Expand-Archive.
#>

# Function to get the list of Samsung Galaxy Book models
function Get-SamsungDriversModelList {
    [CmdletBinding()]
    param(
        [hashtable]$Headers,
        [string]$UserAgent
    )

    # Static fallback model list - CRITICAL for resilience when portal HTML changes
    $staticModels = @(
        @{ Make = 'Samsung'; Model = 'Galaxy Book4 Pro 360'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book4 Pro'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book4 Ultra'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book4 360'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book4'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book3 Pro 360'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book3 Pro'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book3 Ultra'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book3 360'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book3'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book2 Pro 360'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book2 Pro'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book2 360'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book2'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book Pro 360'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book Pro'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book Go'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book Go 5G'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book Ion'; Link = 'https://pcmanagement.biz.samsung.com' }
        @{ Make = 'Samsung'; Model = 'Galaxy Book Flex'; Link = 'https://pcmanagement.biz.samsung.com' }
    )

    $portalUrl = [FFUConstants]::SAMSUNG_PORTAL_URL
    $models = @()

    try {
        WriteLog "Getting Samsung driver information from $portalUrl"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $webContent = Invoke-WebRequest -Uri $portalUrl -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -TimeoutSec 15
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Complete"

        WriteLog "Parsing web content for models and download links"
        $html = $webContent.Content

        # Parse for download links matching "driver" or "sccm" and model names matching "Galaxy Book"
        $linkPattern = '<a[^>]+href="([^"]+)"[^>]*>.*?(Galaxy\s+Book[^<]*)</a>'
        $linkMatches = [regex]::Matches($html, $linkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)

        foreach ($match in $linkMatches) {
            $downloadUrl = $match.Groups[1].Value
            $modelName = [System.Net.WebUtility]::HtmlDecode($match.Groups[2].Value.Trim())

            # Only include links that appear to be download-related
            if ($downloadUrl -match '\.(zip|cab)$|download|driver|sccm') {
                $models += [PSCustomObject]@{
                    Make  = 'Samsung'
                    Model = $modelName
                    Link  = if ($downloadUrl -match '^https?://') { $downloadUrl } else { "$portalUrl/$downloadUrl" }
                }
            }
        }

        # If parsing returned fewer than 5 models, fall back to static list
        if ($models.Count -lt 5) {
            WriteLog "WARNING: Samsung portal scraping returned $($models.Count) models. Using static Galaxy Book model list as fallback."
            $models = $staticModels | ForEach-Object { [PSCustomObject]$_ }
        }
    }
    catch {
        WriteLog "WARNING: Failed to retrieve Samsung portal ($($_.Exception.Message)). Using static Galaxy Book model list as fallback."
        $models = $staticModels | ForEach-Object { [PSCustomObject]$_ }
    }

    WriteLog "Samsung model list: Found $($models.Count) models."
    return $models
}

# Function to download and extract drivers for a specific Samsung model
function Save-SamsungDriversTask {
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

    $modelName = $DriverItemData.Model
    $modelLink = $DriverItemData.Link
    $make = $DriverItemData.Make
    $driverRelativePath = Join-Path -Path $make -ChildPath $modelName
    $status = "Getting download link..."
    $success = $false

    # Initial status update
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status "Checking..." }

    try {
        # Check for existing drivers
        $existingDriver = Test-ExistingDriver -Make $make -Model $modelName -DriversFolder $DriversFolder -Identifier $modelName -ProgressQueue $ProgressQueue
        if ($null -ne $existingDriver) {
            if (-not $existingDriver.PSObject.Properties['Model']) {
                $existingDriver | Add-Member -MemberType NoteProperty -Name 'Model' -Value $modelName
            }

            # Special handling for existing folders that need compression
            if ($CompressToWim -and $existingDriver.Status -eq 'Already downloaded') {
                $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $make
                $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($modelName).wim"
                $sourceFolderPath = Join-Path -Path $makeDriversPath -ChildPath $modelName
                WriteLog "[Samsung][$modelName][Compress] Attempting compression of existing folder to WIM"
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status "Compressing existing..." }
                try {
                    Compress-DriverFolderToWim -SourceFolderPath $sourceFolderPath -DestinationWimPath $wimFilePath -WimName $modelName -WimDescription "Drivers for $modelName" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                    $existingDriver.Status = "Already downloaded & Compressed"
                    $existingDriver.DriverPath = Join-Path -Path $make -ChildPath "$($modelName).wim"
                    $existingDriver.Success = $true
                    WriteLog "[Samsung][$modelName][Compress] Successfully compressed existing drivers to WIM"
                }
                catch {
                    WriteLog "[Samsung][$modelName][Error] Compression failed: $($_.Exception.Message)"
                    $existingDriver.Status = "Already downloaded (Compression failed)"
                    $existingDriver.Success = $false
                }
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $existingDriver.Status }
            }

            return $existingDriver
        }

        ### GET THE DOWNLOAD LINK
        $status = "Getting download link..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

        $downloadLink = $null

        # If modelLink is already a direct ZIP URL, use it
        if ($modelLink -match '\.zip$') {
            WriteLog "[Samsung][$modelName][Download] Using direct download link: $modelLink"
            $downloadLink = $modelLink
        }
        else {
            # Navigate to model download page to find ZIP link
            WriteLog "[Samsung][$modelName][Download] Fetching download page from $modelLink"
            $OriginalVerbosePreference = $VerbosePreference
            $VerbosePreference = 'SilentlyContinue'
            $pageContent = Invoke-WebRequest -Uri $modelLink -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
            $VerbosePreference = $OriginalVerbosePreference
            WriteLog "[Samsung][$modelName][Download] Page retrieved successfully"

            # Parse for ZIP download links
            $zipPattern = 'href="(https?://[^"]+\.zip)"'
            $zipMatches = [regex]::Matches($pageContent.Content, $zipPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

            if ($zipMatches.Count -gt 0) {
                # Prefer Windows release-specific packages (Win11, Win10, W11, W10)
                $releasePattern = if ($WindowsRelease -eq 11) { 'Win11|W11' } else { 'Win10|W10' }
                $matchedLink = $zipMatches | Where-Object { $_.Groups[1].Value -match $releasePattern } | Select-Object -First 1

                if ($null -eq $matchedLink) {
                    # No release-specific match, take first ZIP
                    $matchedLink = $zipMatches[0]
                }

                $downloadLink = $matchedLink.Groups[1].Value
                WriteLog "[Samsung][$modelName][Download] Found ZIP download link: $downloadLink"
            }
            else {
                WriteLog "[Samsung][$modelName][Error] No ZIP download link found on page"
                throw "No downloadable driver pack found for $modelName"
            }
        }

        ### DOWNLOAD AND EXTRACT
        if ($downloadLink) {
            $status = "Downloading..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

            # Create directories
            if (-not (Test-Path -Path $DriversFolder)) {
                WriteLog "[Samsung][$modelName][Setup] Creating Drivers folder: $DriversFolder"
                New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
            }

            $sanitizedModelName = ConvertTo-SafeName -Name $modelName
            if ($sanitizedModelName -ne $modelName) {
                WriteLog "[Samsung][$modelName][Setup] Sanitized model name: '$modelName' -> '$sanitizedModelName'"
            }

            $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $make
            $modelPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedModelName

            if (-not (Test-Path -Path $modelPath)) {
                WriteLog "[Samsung][$modelName][Setup] Creating model folder: $modelPath"
                New-Item -Path $modelPath -ItemType Directory -Force | Out-Null
            }
            else {
                WriteLog "[Samsung][$modelName][Setup] Model folder already exists: $modelPath"
            }

            ### DOWNLOAD
            $fileName = Split-Path -Path $downloadLink -Leaf
            $filePath = Join-Path -Path $makeDriversPath -ChildPath $fileName
            WriteLog "[Samsung][$modelName][Download] Downloading driver pack from $downloadLink to $filePath"
            Start-BitsTransferWithRetry -Source $downloadLink -Destination $filePath
            WriteLog "[Samsung][$modelName][Download] Download complete"

            ### EXTRACT
            $status = "Extracting ZIP..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
            WriteLog "[Samsung][$modelName][Extract] Extracting ZIP to $modelPath"
            $ProgressPreference = 'SilentlyContinue'
            Expand-Archive -Path $filePath -DestinationPath $modelPath -Force
            $ProgressPreference = 'Continue'
            WriteLog "[Samsung][$modelName][Extract] Extraction complete"

            # Remove downloaded file
            $status = "Cleaning up..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
            WriteLog "[Samsung][$modelName][Cleanup] Removing $filePath"
            Remove-Item -Path $filePath -Force
            WriteLog "[Samsung][$modelName][Cleanup] Cleanup complete"

            # --- Compress to WIM if requested ---
            if ($CompressToWim) {
                $status = "Compressing..."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                $wimFileName = "$($modelName).wim"
                $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
                $driverRelativePath = Join-Path -Path $make -ChildPath $wimFileName
                WriteLog "[Samsung][$modelName][Compress] Compressing '$modelPath' to '$destinationWimPath'"
                try {
                    $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $modelName -WimDescription $modelName -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                    if ($compressResult) {
                        WriteLog "[Samsung][$modelName][Compress] Compression successful"
                        $status = "Completed & Compressed"
                    }
                    else {
                        WriteLog "[Samsung][$modelName][Compress] Compression failed - check verbose output"
                        $status = "Completed (Compression Failed)"
                    }
                }
                catch {
                    WriteLog "[Samsung][$modelName][Error] Compression error: $($_.Exception.Message)"
                    $status = "Completed (Compression Error)"
                }
            }
            else {
                $status = "Completed"
            }
            # --- End Compression ---

            $success = $true
        }
        else {
            WriteLog "[Samsung][$modelName][Error] No download link available"
            $status = "Error: No download link"
            $success = $false
        }
    }
    catch {
        $status = "Error: $($_.Exception.Message.Split('.')[0])"
        WriteLog "[Samsung][$modelName][Error] Failed to save drivers: $($_.Exception.Message)"
        $success = $false
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success; DriverPath = $null }
    }

    # Enqueue the final status
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

    # Return the final status
    return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success; DriverPath = $driverRelativePath }
}

Export-ModuleMember -Function *
