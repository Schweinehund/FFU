<#
.SYNOPSIS
    FFU Builder OEM Driver Management Module

.DESCRIPTION
    OEM-specific driver download, parsing, and injection for FFU Builder.
    Supports Microsoft Surface, HP, Lenovo, and Dell driver catalogs with
    automatic download, extraction, and DISM injection capabilities.

.NOTES
    Module: FFU.Drivers
    Version: 1.0.0
    Dependencies: FFU.Core
#>

#Requires -Version 7.0

# Import constants module
using module ..\FFU.Constants\FFU.Constants.psm1

function Invoke-DriverDownloadWithRetry {
    <#
    .SYNOPSIS
    Executes a driver download with retry logic and exponential backoff

    .DESCRIPTION
    Wraps Start-BitsTransferWithRetry calls with additional retry logic using exponential
    backoff and jitter. Provides consistent error handling for transient network failures
    when downloading OEM drivers.

    This function is used internally by Get-DellDrivers, Get-HPDrivers, Get-LenovoDrivers,
    and Get-MicrosoftDrivers to make driver downloads resilient to transient failures.

    REL-DRV-01: Driver Download Retry - Makes OEM driver downloads resilient to network failures

    .PARAMETER Source
    URL of the driver file to download

    .PARAMETER Destination
    Local path where the driver file will be saved

    .PARAMETER OperationName
    Friendly name for the operation (used in log messages)

    .PARAMETER MaxRetries
    Maximum number of retry attempts (default: 3)

    .PARAMETER BaseDelaySeconds
    Base delay in seconds for exponential backoff (default: 5)
    Actual delay = BaseDelay * 2^(attempt-1) + jitter

    .EXAMPLE
    Invoke-DriverDownloadWithRetry -Source $downloadUrl -Destination $filePath -OperationName "Dell driver catalog"

    .EXAMPLE
    # With custom retry parameters
    Invoke-DriverDownloadWithRetry -Source $driverUrl -Destination $localPath -OperationName "HP driver $Name" -MaxRetries 4

    .OUTPUTS
    None - Downloads file to specified Destination path

    .NOTES
    Error handling:
    - Logs warning on each failed attempt with attempt number and source URL
    - Uses exponential backoff: 5s, 10s, 20s (with jitter 0-3s)
    - Throws the last exception after all retries exhausted
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter()]
        [string]$OperationName = 'Driver download',

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$BaseDelaySeconds = 5
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            Start-BitsTransferWithRetry -Source $Source -Destination $Destination -ErrorAction Stop

            # Log success
            $successMsg = "$OperationName completed successfully"
            if ($function:WriteLog) {
                WriteLog $successMsg
            }
            else {
                Write-Verbose $successMsg
            }
            return
        }
        catch {
            $lastError = $_

            # Safe logging pattern for ThreadJob compatibility
            $warningMsg = "$OperationName failed (attempt $attempt of $MaxRetries): $($_.Exception.Message) [Source: $Source]"
            if ($function:WriteLog) {
                WriteLog "WARNING: $warningMsg"
            }
            else {
                Write-Verbose "WARNING: $warningMsg"
            }

            if ($attempt -lt $MaxRetries) {
                # Exponential backoff with jitter (prevents thundering herd)
                $jitter = Get-Random -Minimum 0 -Maximum 3
                $delay = ($BaseDelaySeconds * [math]::Pow(2, $attempt - 1)) + $jitter

                $retryMsg = "Retrying $OperationName in $delay seconds..."
                if ($function:WriteLog) {
                    WriteLog $retryMsg
                }
                else {
                    Write-Verbose $retryMsg
                }

                Start-Sleep -Seconds $delay
            }
        }
    }

    # All retries exhausted
    $errorMsg = "$OperationName failed after $MaxRetries attempts [Source: $Source]"
    if ($function:WriteLog) {
        WriteLog "ERROR: $errorMsg"
    }
    else {
        Write-Verbose "ERROR: $errorMsg"
    }

    throw $lastError
}

function Get-DriverExtractionResult {
    <#
    .SYNOPSIS
    Classifies vendor-specific driver extraction exit codes

    .DESCRIPTION
    Analyzes exit codes from driver extraction processes (HP softpaq, Lenovo SCCM,
    Dell, Microsoft MSI) and determines whether extraction succeeded, failed non-critically,
    or encountered a critical error requiring attention.

    REL-DRV-02: Vendor-Specific Extraction Error Handling

    .PARAMETER Vendor
    The OEM vendor (Dell, HP, Lenovo, Microsoft)

    .PARAMETER ExitCode
    The process exit code from the extraction command

    .PARAMETER DriverName
    Name of the driver being extracted (for logging/messages)

    .OUTPUTS
    PSCustomObject with Success, Critical, Message, and Action properties

    .EXAMPLE
    $result = Get-DriverExtractionResult -Vendor 'HP' -ExitCode 3010 -DriverName 'sp12345'
    # Returns: Success=$true, Action='Continue' (reboot required is normal)

    .NOTES
    Internal function - not exported.
    Exit code classifications based on vendor documentation:
    - HP softpaq: https://support.hp.com/document/c03672226
    - Lenovo: Standard Windows Installer codes
    - Dell: Dell Command Update documentation
    - Microsoft: Windows Installer exit codes
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Dell', 'HP', 'Lenovo', 'Microsoft')]
        [string]$Vendor,

        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter()]
        [string]$DriverName = 'Unknown'
    )

    $result = [PSCustomObject]@{
        Success  = $false
        Critical = $false
        Message  = ''
        Action   = 'Continue'
    }

    switch ($Vendor) {
        'HP' {
            switch ($ExitCode) {
                0       {
                    $result.Success = $true
                    $result.Message = "HP ${DriverName} extracted successfully"
                }
                1       {
                    $result.Message = "HP ${DriverName} extraction warning (general error)"
                    $result.Action = 'Warn'
                }
                2       {
                    $result.Critical = $true
                    $result.Message = "HP ${DriverName} - Invalid command line"
                    $result.Action = 'Fail'
                }
                3       {
                    $result.Message = "HP ${DriverName} initialization error (non-critical)"
                    $result.Action = 'Warn'
                }
                1641    {
                    $result.Success = $true
                    $result.Message = "HP ${DriverName} extracted (reboot initiated - ignored)"
                }
                3010    {
                    $result.Success = $true
                    $result.Message = "HP ${DriverName} extracted (reboot required - expected)"
                }
                default {
                    $result.Message = "HP ${DriverName} unknown exit code ${ExitCode} (continuing)"
                    $result.Action = 'Warn'
                }
            }
        }
        'Lenovo' {
            switch ($ExitCode) {
                0       {
                    $result.Success = $true
                    $result.Message = "Lenovo ${DriverName} extracted successfully"
                }
                1       {
                    $result.Message = "Lenovo ${DriverName} extraction warning (general error)"
                    $result.Action = 'Warn'
                }
                2       {
                    $result.Critical = $true
                    $result.Message = "Lenovo ${DriverName} - Invalid parameter"
                    $result.Action = 'Fail'
                }
                3       {
                    $result.Critical = $true
                    $result.Message = "Lenovo ${DriverName} - File not found"
                    $result.Action = 'Fail'
                }
                5       {
                    $result.Critical = $true
                    $result.Message = "Lenovo ${DriverName} - Access denied"
                    $result.Action = 'Fail'
                }
                1603    {
                    $result.Message = "Lenovo ${DriverName} - Fatal error during extraction (non-critical, continuing)"
                    $result.Action = 'Warn'
                }
                3010    {
                    $result.Success = $true
                    $result.Message = "Lenovo ${DriverName} extracted (reboot required - expected)"
                }
                default {
                    $result.Message = "Lenovo ${DriverName} unknown exit code ${ExitCode} (continuing)"
                    $result.Action = 'Warn'
                }
            }
        }
        'Dell' {
            switch ($ExitCode) {
                0       {
                    $result.Success = $true
                    $result.Message = "Dell ${DriverName} extracted successfully"
                }
                1       {
                    $result.Message = "Dell ${DriverName} extraction warning (general error)"
                    $result.Action = 'Warn'
                }
                2       {
                    $result.Critical = $true
                    $result.Message = "Dell ${DriverName} - Invalid parameter"
                    $result.Action = 'Fail'
                }
                3010    {
                    $result.Success = $true
                    $result.Message = "Dell ${DriverName} extracted (reboot required - expected)"
                }
                default {
                    $result.Message = "Dell ${DriverName} unknown exit code ${ExitCode} (continuing)"
                    $result.Action = 'Warn'
                }
            }
        }
        'Microsoft' {
            switch ($ExitCode) {
                0       {
                    $result.Success = $true
                    $result.Message = "Microsoft ${DriverName} extracted successfully"
                }
                1601    {
                    $result.Message = "Microsoft ${DriverName} - Windows Installer service not accessible (non-critical)"
                    $result.Action = 'Warn'
                }
                1602    {
                    $result.Message = "Microsoft ${DriverName} - User cancelled (non-critical)"
                    $result.Action = 'Warn'
                }
                1603    {
                    $result.Message = "Microsoft ${DriverName} - Fatal error during installation (non-critical)"
                    $result.Action = 'Warn'
                }
                1618    {
                    $result.Message = "Microsoft ${DriverName} - Another installation in progress (non-critical)"
                    $result.Action = 'Warn'
                }
                3010    {
                    $result.Success = $true
                    $result.Message = "Microsoft ${DriverName} extracted (reboot required - expected)"
                }
                default {
                    $result.Message = "Microsoft ${DriverName} unknown exit code ${ExitCode} (continuing)"
                    $result.Action = 'Warn'
                }
            }
        }
    }

    return $result
}

function Get-CachedOEMCatalog {
    <#
    .SYNOPSIS
    Downloads OEM catalog with caching and fallback URL support

    .DESCRIPTION
    Checks for cached catalog file with staleness validation. If cache is valid,
    returns cached path. If cache is stale or missing, downloads from primary URL.
    If primary fails, tries backup URL if provided.

    REL-DRV-03: Catalog Fallback Sources

    .PARAMETER Vendor
    OEM vendor name (Dell, HP, Lenovo)

    .PARAMETER CatalogType
    Type of catalog (PC, Server, Platform for differentiation)

    .PARAMETER PrimaryUrl
    Primary URL to download catalog from

    .PARAMETER BackupUrl
    Optional backup URL if primary fails

    .PARAMETER CachePath
    Local path where catalog should be cached

    .PARAMETER MaxCacheAgeHours
    Maximum age in hours before cache is considered stale (default: 168 = 7 days)

    .PARAMETER ForceRefresh
    Force download even if cache is valid

    .OUTPUTS
    String - Path to the catalog file (cached or newly downloaded)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Dell', 'HP', 'Lenovo')]
        [string]$Vendor,

        [Parameter(Mandatory)]
        [string]$CatalogType,

        [Parameter(Mandatory)]
        [string]$PrimaryUrl,

        [Parameter()]
        [string]$BackupUrl,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter()]
        [int]$MaxCacheAgeHours = [FFUConstants]::OEM_CATALOG_CACHE_HOURS,

        [Parameter()]
        [switch]$ForceRefresh
    )

    $catalogName = "$Vendor $CatalogType catalog"

    # Check cache validity
    if (-not $ForceRefresh -and (Test-Path $CachePath)) {
        $cacheAge = ([DateTime]::Now - (Get-Item $CachePath).LastWriteTime).TotalHours
        if ($cacheAge -lt $MaxCacheAgeHours) {
            WriteLog "Using cached $catalogName (age: $([math]::Round($cacheAge, 1)) hours)"
            return $CachePath
        }
        WriteLog "Cached $catalogName is stale (age: $([math]::Round($cacheAge, 1)) hours, max: $MaxCacheAgeHours)"
    }

    # Ensure cache directory exists
    $cacheDir = Split-Path $CachePath -Parent
    if (-not (Test-Path $cacheDir)) {
        New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
    }

    # Try primary URL
    WriteLog "Downloading $catalogName from primary: $PrimaryUrl"
    try {
        Invoke-DriverDownloadWithRetry -Source $PrimaryUrl -Destination $CachePath -OperationName $catalogName
        WriteLog "$catalogName downloaded successfully"
        return $CachePath
    }
    catch {
        $primaryError = $_.Exception.Message
        WriteLog "WARNING: Primary $catalogName download failed: $primaryError"

        # Try backup URL if available
        if ($BackupUrl) {
            WriteLog "Attempting fallback: $BackupUrl"
            try {
                Invoke-DriverDownloadWithRetry -Source $BackupUrl -Destination $CachePath -OperationName "$catalogName (fallback)"
                WriteLog "$catalogName downloaded from fallback successfully"
                return $CachePath
            }
            catch {
                WriteLog "ERROR: Fallback $catalogName download also failed: $($_.Exception.Message)"
            }
        }

        # Check if we have a stale cache we can use
        if (Test-Path $CachePath) {
            $cacheAge = ([DateTime]::Now - (Get-Item $CachePath).LastWriteTime).TotalHours
            WriteLog "WARNING: Using stale cached $catalogName (age: $([math]::Round($cacheAge, 1)) hours) - network download failed"
            return $CachePath
        }

        # No cache, no download - fail
        throw "Failed to download $catalogName from primary ($primaryError) and no valid cache available"
    }
}

function Test-DriverDiskSpace {
    <#
    .SYNOPSIS
    Validates disk space for driver extraction operations

    .DESCRIPTION
    Estimates disk space requirements for OEM driver extraction and validates
    against available free space. Returns actionable result with recommendations.

    REL-DRV-04: Large Driver Set Disk Space Handling

    .PARAMETER DriversFolder
    Target folder where drivers will be extracted

    .PARAMETER EstimatedCompressedSizeMB
    Estimated compressed size of driver packages in MB (default: 2000 for typical OEM)

    .PARAMETER Vendor
    OEM vendor for size estimation hints (Dell, HP, Lenovo, Microsoft)

    .OUTPUTS
    PSCustomObject with:
      - HasSpace: Boolean indicating if enough space is available
      - FreeSpaceGB: Current free space in GB
      - EstimatedNeedGB: Estimated required space in GB
      - Message: Human-readable status
      - Recommendation: Action to take if space is low
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$DriversFolder,

        [Parameter()]
        [int]$EstimatedCompressedSizeMB = 2000,

        [Parameter()]
        [ValidateSet('Dell', 'HP', 'Lenovo', 'Microsoft')]
        [string]$Vendor = 'Dell'
    )

    # Get free space on target drive
    $driveLetter = (Split-Path $DriversFolder -Qualifier).TrimEnd(':')
    $drive = [System.IO.DriveInfo]::new($driveLetter)
    $freeSpaceBytes = $drive.AvailableFreeSpace
    $freeSpaceGB = [math]::Round($freeSpaceBytes / 1GB, 2)

    # Calculate estimated need
    $compressedBytes = [int64]$EstimatedCompressedSizeMB * 1MB
    $extractedBytes = $compressedBytes * [FFUConstants]::DRIVER_EXTRACTION_MULTIPLIER
    $totalNeededBytes = $extractedBytes + [FFUConstants]::MIN_DRIVER_FREE_SPACE + [FFUConstants]::DRIVER_SPACE_WARNING_BUFFER
    $estimatedNeedGB = [math]::Round($totalNeededBytes / 1GB, 2)

    # Determine size category
    $sizeCategory = if ($compressedBytes -lt [FFUConstants]::DRIVER_SET_SMALL_THRESHOLD) {
        'small'
    } elseif ($compressedBytes -gt [FFUConstants]::DRIVER_SET_LARGE_THRESHOLD) {
        'large'
    } else {
        'medium'
    }

    $result = [PSCustomObject]@{
        HasSpace        = $freeSpaceBytes -ge $totalNeededBytes
        FreeSpaceGB     = $freeSpaceGB
        EstimatedNeedGB = $estimatedNeedGB
        SizeCategory    = $sizeCategory
        Message         = ''
        Recommendation  = ''
    }

    if ($result.HasSpace) {
        $result.Message = "Sufficient disk space for $Vendor drivers ($sizeCategory set). Free: ${freeSpaceGB}GB, Need: ${estimatedNeedGB}GB"
    }
    else {
        $shortfall = [math]::Round($estimatedNeedGB - $freeSpaceGB, 2)
        $result.Message = "Insufficient disk space for $Vendor drivers. Free: ${freeSpaceGB}GB, Need: ${estimatedNeedGB}GB (short by ${shortfall}GB)"

        if ($sizeCategory -eq 'large') {
            $result.Recommendation = @"
Large $Vendor driver set detected. Options:
1. Free at least ${shortfall}GB on drive ${driveLetter}:
2. Use -DriversFolder parameter to specify a different drive
3. If injecting to VHDX, consider expanding the VHDX before driver injection
4. Download drivers to a larger temporary location first
"@
        }
        else {
            $result.Recommendation = "Free at least ${shortfall}GB on drive ${driveLetter}: or use -DriversFolder parameter to specify a different location."
        }
    }

    return $result
}

function Get-MicrosoftDrivers {
    <#
    .SYNOPSIS
    Downloads and extracts Microsoft Surface drivers for FFU builds

    .DESCRIPTION
    Downloads Microsoft Surface drivers from the official Microsoft support page,
    parses available models, and extracts the appropriate driver package for the
    specified Surface model and Windows version.

    .PARAMETER Make
    OEM manufacturer name (e.g., "Microsoft")

    .PARAMETER Model
    Surface model name (e.g., "Surface Pro 9")

    .PARAMETER WindowsRelease
    Windows release version (10 or 11)

    .PARAMETER Headers
    HTTP headers for web requests

    .PARAMETER UserAgent
    User agent string for web requests

    .PARAMETER DriversFolder
    Root path where drivers should be downloaded and extracted

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download tracking

    .EXAMPLE
    Get-MicrosoftDrivers -Make "Microsoft" -Model "Surface Pro 9" -WindowsRelease 11 `
                        -Headers $Headers -UserAgent $UserAgent -DriversFolder "C:\FFU\Drivers" `
                        -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    $url = "https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120"

    ### DOWNLOAD DRIVER PAGE CONTENT
    WriteLog "Getting Surface driver information from $url"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    try {
        $webContent = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
    }
    catch [System.Net.WebException] {
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "ERROR: Network error accessing Microsoft Surface drivers page: $($_.Exception.Message)"
        throw "Failed to access Microsoft Surface drivers page: $($_.Exception.Message)"
    }
    catch {
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "ERROR: Failed to retrieve Surface driver information: $($_.Exception.Message)"
        throw
    }
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Complete"

    ### PARSE THE DRIVER PAGE CONTENT FOR MODELS AND DOWNLOAD LINKS
    WriteLog "Parsing web content for models and download links"
    $html = $webContent.Content

    # Regex to match divs with selectable-content-options__option-content classes
    $divPattern = '<div[^>]*class="selectable-content-options__option-content(?: ocHidden)?"[^>]*>(.*?)</div>'
    $divMatches = [regex]::Matches($html, $divPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    $models = @()

    foreach ($divMatch in $divMatches) {
        $divContent = $divMatch.Groups[1].Value

        # Find all tables within the div
        $tablePattern = '<table[^>]*>(.*?)</table>'
        $tableMatches = [regex]::Matches($divContent, $tablePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

        foreach ($tableMatch in $tableMatches) {
            $tableContent = $tableMatch.Groups[1].Value

            # Find all rows in the table
            $rowPattern = '<tr[^>]*>(.*?)</tr>'
            $rowMatches = [regex]::Matches($tableContent, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

            foreach ($rowMatch in $rowMatches) {
                $rowContent = $rowMatch.Groups[1].Value

                # Extract cells from the row
                $cellPattern = '<td[^>]*>\s*(?:<p[^>]*>)?(.*?)(?:</p>)?\s*</td>'
                $cellMatches = [regex]::Matches($rowContent, $cellPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                if ($cellMatches.Count -ge 2) {
                    # Model name in the first TD
                    $modelName = ($cellMatches[0].Groups[1].Value).Trim()

                    # # Remove <p> and </p> tags if present
                    # $modelName = $modelName -replace '<p[^>]*>', '' -replace '</p>', ''
                    # $modelName = $modelName.Trim()


                    # The second TD might contain a link or just text
                    $secondTdContent = $cellMatches[1].Groups[1].Value.Trim()

                    # Look for a link in the second TD
                    $linkPattern = '<a[^>]+href="([^"]+)"[^>]*>'
                    $linkMatch = [regex]::Match($secondTdContent, $linkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

                    if ($linkMatch.Success) {
                        $modelLink = $linkMatch.Groups[1].Value
                    }
                    else {
                        # No link, just text instructions
                        $modelLink = $secondTdContent
                    }

                    $models += [PSCustomObject]@{ Model = $modelName; Link = $modelLink }
                }
            }
        }
    }

    WriteLog "Parsing complete"

    ### FIND THE MODEL IN THE LIST OF MODELS
    $selectedModel = $models | Where-Object { $_.Model -eq $Model }

    if ($null -eq $selectedModel) {
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "The model '$Model' was not found in the list of available models."
            Write-Host "Please run the script with the -Verbose switch to see the list of available models."
        }
        WriteLog "The model '$Model' was not found in the list of available models."
        WriteLog "Please select a model from the list below by number:"

        for ($i = 0; $i -lt $models.Count; $i++) {
            if ($VerbosePreference -ne 'Continue') {
                Write-Host "$($i + 1). $($models[$i].Model)"
            }
            WriteLog "$($i + 1). $($models[$i].Model)"
        }

        do {
            $selection = Read-Host "Enter the number of the model you want to select"
            WriteLog "User selected model number: $selection"

            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $models.Count) {
                $selectedModel = $models[$selection - 1]
            }
            else {
                if ($VerbosePreference -ne 'Continue') {
                    Write-Host "Invalid selection. Please try again."
                }
                WriteLog "Invalid selection. Please try again."
            }
        } while ($null -eq $selectedModel)
    }

    $Model = $selectedModel.Model
    WriteLog "Model: $Model"
    WriteLog "Download Page: $($selectedModel.Link)"

    ### GET THE DOWNLOAD LINK FOR THE SELECTED MODEL
    WriteLog "Getting download page content"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    try {
        $downloadPageContent = Invoke-WebRequest -Uri $selectedModel.Link -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
    }
    catch [System.Net.WebException] {
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "ERROR: Network error accessing download page for $Model : $($_.Exception.Message)"
        throw "Failed to access download page for '$Model': $($_.Exception.Message)"
    }
    catch {
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "ERROR: Failed to retrieve download page for $Model : $($_.Exception.Message)"
        throw
    }
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Complete"
    WriteLog "Parsing download page for file"
    $scriptPattern = '<script>window.__DLCDetails__={(.*?)}<\/script>'
    $scriptMatch = [regex]::Match($downloadPageContent.Content, $scriptPattern)

    if ($scriptMatch.Success) {
        $scriptContent = $scriptMatch.Groups[1].Value

        # Extract the download file information from the script tag
        $downloadFilePattern = '"name":"(.*?)",.*?"url":"(.*?)"'
        $downloadFileMatches = [regex]::Matches($scriptContent, $downloadFilePattern)

        $downloadLink = $null
        foreach ($downloadFile in $downloadFileMatches) {
            $fileName = $downloadFile.Groups[1].Value
            $fileUrl = $downloadFile.Groups[2].Value

            if ($fileName -match "Win$WindowsRelease") {
                $downloadLink = $fileUrl
                break
            }
        }


        ### CREATE FOLDER STRUCTURE AND DOWNLOAD AND EXTRACT THE FILE
        if ($downloadLink) {
            WriteLog "Download Link for Windows ${WindowsRelease}: $downloadLink"

            # Create directory structure
            if (-not (Test-Path -Path $DriversFolder)) {
                WriteLog "Creating Drivers folder: $DriversFolder"
                New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
                WriteLog "Drivers folder created"
            }
            $sanitizedModel = ConvertTo-SafeName -Name $Model
            if ($sanitizedModel -ne $Model) { WriteLog "Sanitized model name: '$Model' -> '$sanitizedModel'" }
            $surfaceDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
            $modelPath = Join-Path -Path $surfaceDriversPath -ChildPath $sanitizedModel
            if (-Not (Test-Path -Path $modelPath)) {
                WriteLog "Creating model folder: $modelPath"
                New-Item -Path $modelPath -ItemType Directory | Out-Null
                WriteLog "Complete"
            }

            ### DOWNLOAD THE FILE
            $filePath = Join-Path -Path $surfaceDriversPath -ChildPath ($fileName)
            WriteLog "Downloading $Model driver file to $filePath"
            Set-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $filePath
            try {
                Invoke-DriverDownloadWithRetry -Source $downloadLink -Destination $filePath -OperationName "Microsoft Surface driver for $Model"
            }
            catch {
                Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $filePath
                WriteLog "ERROR: Failed to download $Model drivers after all retries: $($_.Exception.Message)"
                throw
            }
            Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $filePath

            # Determine file extension
            $fileExtension = [System.IO.Path]::GetExtension($filePath).ToLower()

            ### EXTRACT THE FILE
            if ($fileExtension -eq ".msi") {
                # Extract the MSI file using an administrative install
                WriteLog "Extracting MSI file to $modelPath"
                $arguments = "/a `"$($filePath)`" /qn TARGETDIR=`"$($modelPath)`""
                try {
                    Invoke-Process -FilePath "msiexec.exe" -ArgumentList $arguments -ErrorAction Stop | Out-Null
                    WriteLog "MSI extraction complete"
                }
                catch {
                    WriteLog "ERROR: Failed to extract MSI file: $($_.Exception.Message)"
                    throw "Failed to extract MSI driver package for '$Model': $($_.Exception.Message)"
                }
            }
            elseif ($fileExtension -eq ".zip") {
                # Extract the ZIP file
                WriteLog "Extracting ZIP file to $modelPath"
                try {
                    Expand-Archive -Path $filePath -DestinationPath $modelPath -Force -ErrorAction Stop
                    WriteLog "ZIP extraction complete"
                }
                catch [System.IO.IOException] {
                    WriteLog "ERROR: IO error extracting ZIP file: $($_.Exception.Message)"
                    throw "Failed to extract ZIP driver package for '$Model': $($_.Exception.Message)"
                }
                catch {
                    WriteLog "ERROR: Failed to extract ZIP file: $($_.Exception.Message)"
                    throw
                }
            }
            else {
                WriteLog "WARNING: Unsupported file type: $fileExtension"
            }
            # Remove the downloaded file
            WriteLog "Removing $filePath"
            try {
                Remove-Item -Path $filePath -Force -ErrorAction Stop
                WriteLog "Driver installer file removed"
            }
            catch {
                WriteLog "WARNING: Failed to remove driver installer file: $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "No download link found for Windows $WindowsRelease."
        }
    }
    else {
        WriteLog "Failed to parse the download page for the MSI file."
    }
}

function Get-HPDrivers {
    <#
    .SYNOPSIS
    Downloads and extracts HP drivers for FFU builds

    .DESCRIPTION
    Downloads HP driver catalog, parses available models, and extracts the
    appropriate driver packages for the specified HP model and Windows version.
    Uses HP Image Assistant (HPIA) cloud catalog for driver discovery.

    .PARAMETER Make
    OEM manufacturer name (e.g., "HP")

    .PARAMETER Model
    HP model name (e.g., "EliteBook 840 G8")

    .PARAMETER WindowsArch
    Windows architecture (x64, x86, or ARM64)

    .PARAMETER WindowsRelease
    Windows release version (10 or 11)

    .PARAMETER WindowsVersion
    Specific Windows version/build (e.g., "21H2", "22H2")

    .PARAMETER DriversFolder
    Root path where drivers should be downloaded and extracted

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download tracking

    .EXAMPLE
    Get-HPDrivers -Make "HP" -Model "EliteBook 840 G8" -WindowsArch "x64" `
                  -WindowsRelease 11 -WindowsVersion "22H2" -DriversFolder "C:\FFU\Drivers" `
                  -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,

        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [string]$WindowsVersion,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    # Download and extract the PlatformList.cab (with caching)
    $DriversFolder = "$DriversFolder\$Make"
    $PlatformListCab = "$DriversFolder\platformList.cab"
    $PlatformListXml = "$DriversFolder\PlatformList.xml"

    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }

    try {
        $PlatformListCab = Get-CachedOEMCatalog -Vendor 'HP' -CatalogType 'Platform' `
            -PrimaryUrl ([FFUConstants]::HP_PLATFORM_LIST_URL) -CachePath $PlatformListCab
    }
    catch {
        WriteLog "ERROR: $($_.Exception.Message)"
        throw
    }

    WriteLog "Expanding $PlatformListCab to $PlatformListXml"
    try {
        Invoke-Process -FilePath expand.exe -ArgumentList "$PlatformListCab $PlatformListXml" -ErrorAction Stop | Out-Null
        WriteLog "Expansion complete"
    }
    catch {
        WriteLog "ERROR: Failed to expand HP platform cab file: $($_.Exception.Message)"
        throw "Failed to expand HP platform catalog: $($_.Exception.Message)"
    }

    # Parse the PlatformList.xml to find the SystemID based on the ProductName
    try {
        [xml]$PlatformListContent = Get-Content -Path $PlatformListXml -ErrorAction Stop
    }
    catch {
        WriteLog "ERROR: Failed to parse HP platform list XML: $($_.Exception.Message)"
        throw "Failed to parse HP platform catalog: $($_.Exception.Message)"
    }
    $ProductNodes = $PlatformListContent.ImagePal.Platform | Where-Object { $_.ProductName.'#text' -match $Model }

    # Create a list of unique ProductName entries
    $ProductNames = @()
    foreach ($node in $ProductNodes) {
        foreach ($productName in $node.ProductName) {
            if ($productName.'#text' -match $Model) {
                $ProductNames += [PSCustomObject]@{
                    ProductName = $productName.'#text'
                    SystemID    = $node.SystemID
                    OSReleaseID = $node.OS.OSReleaseIdFileName -replace 'H', 'h'
                    IsWindows11 = $node.OS.IsWindows11 -contains 'true'
                }
            }
        }
    }

    if ($ProductNames.Count -gt 1) {
        Write-Output "More than one model found matching '$Model':"
        WriteLog "More than one model found matching '$Model':"
        $ProductNames | ForEach-Object -Begin { $i = 1 } -Process {
            if ($VerbosePreference -ne 'Continue') {
                Write-Output "$i. $($_.ProductName)"
            }
            WriteLog "$i. $($_.ProductName)"
            $i++
        }
        $selection = Read-Host "Please select the number corresponding to the correct model"
        WriteLog "User selected model number: $selection"
        if ($selection -match '^\d+$' -and [int]$selection -le $ProductNames.Count) {
            $SelectedProduct = $ProductNames[[int]$selection - 1]
            $ProductName = $SelectedProduct.ProductName
            WriteLog "Selected model: $ProductName"
            $SystemID = $SelectedProduct.SystemID
            WriteLog "SystemID: $SystemID"
            $ValidOSReleaseIDs = $SelectedProduct.OSReleaseID
            WriteLog "Valid OSReleaseIDs: $ValidOSReleaseIDs"
            $IsWindows11 = $SelectedProduct.IsWindows11
            WriteLog "IsWindows11 supported: $IsWindows11"
        }
        else {
            WriteLog "Invalid selection. Exiting."
            if ($VerbosePreference -ne 'Continue') {
                Write-Host "Invalid selection. Exiting."
            }
            exit
        }
    }
    elseif ($ProductNames.Count -eq 1) {
        $SelectedProduct = $ProductNames[0]
        $ProductName = $SelectedProduct.ProductName
        WriteLog "Selected model: $ProductName"
        $SystemID = $SelectedProduct.SystemID
        WriteLog "SystemID: $SystemID"
        $ValidOSReleaseIDs = $SelectedProduct.OSReleaseID
        WriteLog "OSReleaseID: $ValidOSReleaseIDs"
        $IsWindows11 = $SelectedProduct.IsWindows11
        WriteLog "IsWindows11: $IsWindows11"
    }
    else {
        WriteLog "No models found matching '$Model'. Exiting."
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "No models found matching '$Model'. Exiting."
        }
        exit
    }

    if (-not $SystemID) {
        WriteLog "SystemID not found for model: $Model Exiting."
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "SystemID not found for model: $Model Exiting."
        }
        exit
    }

    # Validate if WindowsRelease is 11 and there is no IsWindows11 element set to true
    if ($WindowsRelease -eq 11 -and -not $IsWindows11) {
        WriteLog "WindowsRelease is set to 11, but no drivers are available for this Windows release. Please set the -WindowsRelease parameter to 10, or provide your own drivers to the FFUDevelopment\Drivers folder."
        Write-Output "WindowsRelease is set to 11, but no drivers are available for this Windows release. Please set the -WindowsRelease parameter to 10, or provide your own drivers to the FFUDevelopment\Drivers folder."
        exit
    }

    # Validate WindowsVersion against OSReleaseID
    $OSReleaseIDs = $ValidOSReleaseIDs -split ' '
    $MatchingReleaseID = $OSReleaseIDs | Where-Object { $_ -eq "$WindowsVersion" }

    if (-not $MatchingReleaseID) {
        Write-Output "The specified WindowsVersion value '$WindowsVersion' is not valid for the selected model. Please select a valid OSReleaseID:"
        $OSReleaseIDs | ForEach-Object -Begin { $i = 1 } -Process {
            Write-Output "$i. $_"
            $i++
        }
        $selection = Read-Host "Please select the number corresponding to the correct OSReleaseID"
        WriteLog "User selected OSReleaseID number: $selection"
        if ($selection -match '^\d+$' -and [int]$selection -le $OSReleaseIDs.Count) {
            $WindowsVersion = $OSReleaseIDs[[int]$selection - 1]
            WriteLog "Selected OSReleaseID: $WindowsVersion"
        }
        else {
            WriteLog "Invalid selection. Exiting."
            exit
        }
    }

    # Modify WindowsArch for URL
    $Arch = $WindowsArch -replace "^x", ""

    # Construct the URL to download the driver XML cab for the model
    # The HPcloud reference site is case sensitve so we must convert the Windowsversion to lower 'h' first
    $WindowsVersionHP = $WindowsVersion -replace 'H', 'h'
    $ModelRelease = $SystemID + "_$Arch" + "_$WindowsRelease" + ".0.$WindowsVersionHP"
    $DriverCabUrl = "https://hpia.hpcloud.hp.com/ref/$SystemID/$ModelRelease.cab"
    $DriverCabFile = "$DriversFolder\$ModelRelease.cab"
    $DriverXmlFile = "$DriversFolder\$ModelRelease.xml"

    if (-not (Test-Url -Url $DriverCabUrl)) {
        WriteLog "HP Driver cab URL is not accessible: $DriverCabUrl Exiting"
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "HP Driver cab URL is not accessible: $DriverCabUrl Exiting"
        }
        exit
    }

    # Download and extract the driver XML cab
    WriteLog "Downloading HP Driver cab from $DriverCabUrl to $DriverCabFile"
    try {
        Invoke-DriverDownloadWithRetry -Source $DriverCabUrl -Destination $DriverCabFile -OperationName "HP driver catalog for $ProductName"
    }
    catch {
        WriteLog "ERROR: Failed to download HP driver catalog after all retries: $($_.Exception.Message)"
        throw
    }

    WriteLog "Expanding HP Driver cab to $DriverXmlFile"
    try {
        Invoke-Process -FilePath expand.exe -ArgumentList "$DriverCabFile $DriverXmlFile" -ErrorAction Stop | Out-Null
    }
    catch {
        WriteLog "ERROR: Failed to expand HP driver cab file: $($_.Exception.Message)"
        throw "Failed to expand HP driver catalog: $($_.Exception.Message)"
    }

    # Parse the extracted XML file to download individual drivers
    try {
        [xml]$DriverXmlContent = Get-Content -Path $DriverXmlFile -ErrorAction Stop
    }
    catch {
        WriteLog "ERROR: Failed to parse HP driver XML: $($_.Exception.Message)"
        throw "Failed to parse HP driver catalog: $($_.Exception.Message)"
    }
    $baseUrl = "https://ftp.hp.com/pub/softpaq/sp"

    WriteLog "Downloading drivers for $ProductName"
    foreach ($update in $DriverXmlContent.ImagePal.Solutions.UpdateInfo) {
        if ($update.Category -notmatch '^Driver') {
            continue
        }

        $Name = $update.Name
        # Fix the name for drivers that contain illegal characters for folder name purposes
        $Name = $Name -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        WriteLog "Downloading driver: $Name"
        $Category = $update.Category
        $Category = $Category -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $Version = $update.Version
        $Version = $Version -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $DriverUrl = "https://$($update.URL)"
        WriteLog "Driver URL: $DriverUrl"
        $DriverFileName = [System.IO.Path]::GetFileName($DriverUrl)
        $downloadFolder = "$DriversFolder\$ProductName\$Category"
        $DriverFilePath = Join-Path -Path $downloadFolder -ChildPath $DriverFileName

        if (Test-Path -Path $DriverFilePath) {
            WriteLog "Driver already downloaded: $DriverFilePath, skipping"
            continue
        }

        if (-not (Test-Path -Path $downloadFolder)) {
            WriteLog "Creating download folder: $downloadFolder"
            New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            WriteLog "Download folder created"
        }

        # Download the driver with retry
        WriteLog "Downloading driver to: $DriverFilePath"
        Set-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $DriverFilePath
        try {
            Invoke-DriverDownloadWithRetry -Source $DriverUrl -Destination $DriverFilePath -OperationName "HP driver $Name"
            Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $DriverFilePath
        }
        catch {
            Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $DriverFilePath
            WriteLog "WARNING: Failed to download HP driver '$Name' after all retries: $($_.Exception.Message)"
            continue
        }

        # Make folder for extraction
        $extractFolder = "$downloadFolder\$Name\$Version\" + $DriverFileName.TrimEnd('.exe')
        WriteLog "Creating extraction folder: $extractFolder"
        try {
            New-Item -Path $extractFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            WriteLog 'Extraction folder created'
        }
        catch {
            WriteLog "WARNING: Failed to create extraction folder: $($_.Exception.Message)"
            continue
        }

        # Extract the driver with exit code classification (REL-DRV-02)
        $arguments = "/s /e /f `"$extractFolder`""
        WriteLog "Extracting driver"
        try {
            $extractProcess = Start-Process -FilePath $DriverFilePath -ArgumentList $arguments -PassThru -Wait -NoNewWindow
            $extractionResult = Get-DriverExtractionResult -Vendor 'HP' -ExitCode $extractProcess.ExitCode -DriverName $Name

            if ($extractionResult.Action -eq 'Warn') {
                WriteLog "WARNING: $($extractionResult.Message)"
            }
            elseif ($extractionResult.Action -eq 'Fail') {
                WriteLog "ERROR: $($extractionResult.Message)"
                continue  # Skip to next driver, don't halt entire build
            }
            else {
                WriteLog "Driver extracted to: $extractFolder"
            }
        }
        catch {
            WriteLog "WARNING: Failed to extract HP driver '$Name': $($_.Exception.Message)"
        }

        # Delete the .exe driver file after extraction
        if (-not [string]::IsNullOrWhiteSpace($DriverFilePath)) {
            try {
                Remove-Item -Path $DriverFilePath -Force -ErrorAction Stop
                WriteLog "Driver installation file deleted: $DriverFilePath"
            }
            catch {
                WriteLog "WARNING: Failed to delete driver installer: $($_.Exception.Message)"
            }
        }
    }
    # Clean up the downloaded cab and xml files - filter out null/empty paths to prevent "Value cannot be null" error
    $cleanupPaths = @($DriverCabFile, $DriverXmlFile, $PlatformListCab, $PlatformListXml) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($cleanupPaths.Count -gt 0) {
        Remove-Item -Path $cleanupPaths -Force -ErrorAction SilentlyContinue
        WriteLog "Driver cab and xml files deleted"
    }
}

function Get-LenovoDrivers {
    <#
    .SYNOPSIS
    Downloads and extracts Lenovo drivers for FFU builds

    .DESCRIPTION
    Downloads Lenovo driver catalog, parses available models using PSREF API,
    and extracts the appropriate driver packages for the specified Lenovo model
    and Windows version.

    .PARAMETER Make
    OEM manufacturer name (e.g., "Lenovo")

    .PARAMETER Model
    Lenovo model name or machine type (e.g., "ThinkPad X1 Carbon Gen 9" or "20XW")

    .PARAMETER WindowsArch
    Windows architecture (x64, x86, or ARM64)

    .PARAMETER WindowsRelease
    Windows release version (10 or 11)

    .PARAMETER Headers
    HTTP headers for web requests (modified by function to add PSREF authentication)

    .PARAMETER UserAgent
    User agent string for web requests

    .PARAMETER DriversFolder
    Root path where drivers should be downloaded and extracted

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download tracking

    .EXAMPLE
    Get-LenovoDrivers -Make "Lenovo" -Model "ThinkPad X1 Carbon Gen 9" -WindowsArch "x64" `
                      -WindowsRelease 11 -Headers $Headers -UserAgent $UserAgent `
                      -DriversFolder "C:\FFU\Drivers" -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,

        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    function Get-LenovoPSREF {
        param (
            [string]$ModelName
        )

        # Lenovo is special - they prevent access to the PSREF API without a cookie as of July 2025.
        # This cookie must be retrieved via Javascript
        # It appears that the cookie is hard-coded. We'll see how long this lasts.
        # If anyone knows how to reliably get the the model and machine type information from Lenovo, let me know.
        # https://download.lenovo.com/cdrt/td/catalogv2.xml only provides a subset of the information available from PSREF (e.g. it's missing 300w, 500w, and other consumer models).

        # $lenovoCookie = "X-PSREF-USER-TOKEN=eyJ0eXAiOiJKV1QifQ.bjVTdWk0YklZeUc2WnFzL0lXU0pTeU1JcFo0aExzRXl1UGxHN3lnS1BtckI0ZVU5WEJyVGkvaFE0NmVNU2U1ZjNrK3ZqTEVIZ29nTk1TNS9DQmIwQ0pTN1Q1VytlY1RpNzZTUldXbm4wZ1g2RGJuQWg4MXRkTmxKT2YrOW9LRjBzQUZzV05HM3NpcU92WFVTM0o0blM1SDQyUlVXNThIV1VBS2R0c1B2NjJyQjIrUGxNZ2x6RTRhUjY5UDZWclBX.ZDBmM2EyMWRjZTg2N2JmYWMxZDIxY2NiYjQzMWFhNjg1YjEzZTAxNmU2M2RmN2M5ZjIyZWJhMzZkOWI1OWJhZg"

        # Wrote a separate function to grab the token. Check the function notes for more details. Keep the above comment for now to see if the cookie ever changes.
        $lenovoCookie = Get-LenovoPSREFToken

        # Add the cookie to the headers
        $Headers["Cookie"] = $lenovoCookie

        $url = "https://psref.lenovo.com/api/search/DefinitionFilterAndSearch/Suggest?kw=$ModelName"
        WriteLog "Querying Lenovo PSREF API for model: $ModelName"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
        }
        catch [System.Net.WebException] {
            $VerbosePreference = $OriginalVerbosePreference
            WriteLog "ERROR: Network error querying Lenovo PSREF API: $($_.Exception.Message)"
            throw "Failed to query Lenovo PSREF API for model '$ModelName': $($_.Exception.Message)"
        }
        catch {
            $VerbosePreference = $OriginalVerbosePreference
            WriteLog "ERROR: Failed to query Lenovo PSREF API: $($_.Exception.Message)"
            throw
        }
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Complete"

        try {
            $jsonResponse = $response.Content | ConvertFrom-Json
        }
        catch {
            WriteLog "ERROR: Failed to parse Lenovo PSREF response: $($_.Exception.Message)"
            throw "Failed to parse Lenovo PSREF API response: $($_.Exception.Message)"
        }

        $products = @()
        foreach ($item in $jsonResponse.data) {
            if (-not [string]::IsNullOrEmpty($item.MachineType) -and -not [string]::IsNullOrEmpty($item.ProductName)) {
                $productName = $item.ProductName
                $machineTypes = $item.MachineType -split " / "

                foreach ($machineType in $machineTypes) {
                    if ($machineType -eq $ModelName) {
                        WriteLog "Model name entered is a matching machine type"
                        $products = @()
                        $products += [pscustomobject]@{
                            ProductName = $productName
                            MachineType = $machineType
                        }
                        WriteLog "Product Name: $productName Machine Type: $machineType"
                        return $products
                    }
                    $products += [pscustomobject]@{
                        ProductName = $productName
                        MachineType = $machineType
                    }
                }
            }
        }

        return , $products
    }

    # Parse the Lenovo PSREF page for the model
    $machineTypes = Get-LenovoPSREF -ModelName $Model
    if ($machineTypes.ProductName.Count -eq 0) {
        WriteLog "No machine types found for model: $Model"
        WriteLog "Enter a valid model or machine type in the -model parameter"
        exit
    }
    elseif ($machineTypes.ProductName.Count -eq 1) {
        $machineType = $machineTypes[0].MachineType
        $model = $machineTypes[0].ProductName
    }
    else {
        if ($VerbosePreference -ne 'Continue') {
            Write-Output "Multiple machine types found for model: $Model"
        }
        WriteLog "Multiple machine types found for model: $Model"
        for ($i = 0; $i -lt $machineTypes.ProductName.Count; $i++) {
            if ($VerbosePreference -ne 'Continue') {
                Write-Output "$($i + 1). $($machineTypes[$i].ProductName) ($($machineTypes[$i].MachineType))"
            }
            WriteLog "$($i + 1). $($machineTypes[$i].ProductName) ($($machineTypes[$i].MachineType))"
        }
        $selection = Read-Host "Enter the number of the model you want to select"
        $machineType = $machineTypes[$selection - 1].MachineType
        WriteLog "Selected machine type: $machineType"
        $model = $machineTypes[$selection - 1].ProductName
        WriteLog "Selected model: $model"
    }


    # Construct the catalog URL based on Windows release and machine type
    $ModelRelease = $machineType + "_Win" + $WindowsRelease
    $CatalogUrl = "https://download.lenovo.com/catalog/$ModelRelease.xml"
    WriteLog "Lenovo Driver catalog URL: $CatalogUrl"

    if (-not (Test-Url -Url $catalogUrl)) {
        Write-Error "Lenovo Driver catalog URL is not accessible: $catalogUrl"
        WriteLog "Lenovo Driver catalog URL is not accessible: $catalogUrl"
        exit
    }

    # Create the folder structure for the Lenovo drivers
    $driversFolder = "$DriversFolder\$Make"
    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }

    # Download and parse the Lenovo catalog XML
    $LenovoCatalogXML = "$DriversFolder\$ModelRelease.xml"
    WriteLog "Downloading $catalogUrl to $LenovoCatalogXML"
    try {
        Invoke-DriverDownloadWithRetry -Source $catalogUrl -Destination $LenovoCatalogXML -OperationName "Lenovo driver catalog for $model"
    }
    catch {
        WriteLog "ERROR: Failed to download Lenovo driver catalog after all retries: $($_.Exception.Message)"
        throw
    }

    try {
        $xmlContent = [xml](Get-Content -Path $LenovoCatalogXML -ErrorAction Stop)
    }
    catch {
        WriteLog "ERROR: Failed to parse Lenovo driver catalog XML: $($_.Exception.Message)"
        throw "Failed to parse Lenovo driver catalog: $($_.Exception.Message)"
    }

    WriteLog "Parsing Lenovo catalog XML"
    # Process each package in the catalog
    foreach ($package in $xmlContent.packages.package) {
        $packageUrl = $package.location
        $category = $package.category

        #If category starts with BIOS, skip the package
        if ($category -like 'BIOS*') {
            continue
        }

        #If category name is 'Motherboard Devices Backplanes core chipset onboard video PCIe switches', truncate to 'Motherboard Devices' to shorten path
        if ($category -eq 'Motherboard Devices Backplanes core chipset onboard video PCIe switches') {
            $category = 'Motherboard Devices'
        }

        $packageName = [System.IO.Path]::GetFileName($packageUrl)
        #Remove the filename from the $packageURL
        $baseURL = $packageUrl -replace $packageName, ""

        # Download the package XML
        $packageXMLPath = "$DriversFolder\$packageName"
        WriteLog "Downloading $category package XML $packageUrl to $packageXMLPath"
        try {
            Start-BitsTransferWithRetry -Source $packageUrl -Destination $packageXMLPath -ErrorAction Stop
        }
        catch {
            Write-Output "Failed to download $category package XML: $packageXMLPath - $($_.Exception.Message)"
            WriteLog "Failed to download $category package XML: $packageXMLPath - $($_.Exception.Message)"
            continue
        }

        # Load the package XML content
        $packageXmlContent = [xml](Get-Content -Path $packageXMLPath)
        $packageType = $packageXmlContent.Package.PackageType.type
        $packageTitle = $packageXmlContent.Package.title.InnerText

        # Fix the name for drivers that contain illegal characters for folder name purposes
        $packageTitle = $packageTitle -replace '[\\\/\:\*\?\"\<\>\|]', '_'

        # If ' - ' is in the package title, truncate the title to the first part of the string.
        $packageTitle = $packageTitle -replace ' - .*', ''

        #Check if packagetype = 2. If packagetype is not 2, skip the package. $packageType is a System.Xml.XmlElement.
        #This filters out Firmware, BIOS, and other non-INF drivers
        if ($packageType -ne 2) {
            Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
            continue
        }

        # Extract the driver file name and the extract command
        $driverFileName = $packageXmlContent.Package.Files.Installer.File.Name
        $extractCommand = $packageXmlContent.Package.ExtractCommand

        #if extract command is empty/missing, skip the package
        if (!($extractCommand)) {
            Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
            continue
        }

        # Create the download URL and folder structure
        $driverUrl = $baseUrl + $driverFileName
        $downloadFolder = "$DriversFolder\$Model\$Category\$packageTitle"
        $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driverFileName

        # Check if file has already been downloaded
        if (Test-Path -Path $driverFilePath) {
            Write-Output "Driver already downloaded: $driverFilePath skipping"
            WriteLog "Driver already downloaded: $driverFilePath skipping"
            continue
        }

        if (-not (Test-Path -Path $downloadFolder)) {
            WriteLog "Creating download folder: $downloadFolder"
            New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            WriteLog "Download folder created"
        }

        # Download the driver with retry
        WriteLog "Downloading driver: $driverUrl to $driverFilePath"
        Set-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
        try {
            Invoke-DriverDownloadWithRetry -Source $driverUrl -Destination $driverFilePath -OperationName "Lenovo driver $packageTitle"
            Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
        }
        catch {
            Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
            WriteLog "WARNING: Failed to download Lenovo driver '$packageTitle' after all retries: $($_.Exception.Message)"
            Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
            continue
        }

        # Make folder for extraction
        $extractFolder = $downloadFolder + "\" + $driverFileName.TrimEnd($driverFileName[-4..-1])
        WriteLog "Creating extract folder: $extractFolder"
        try {
            New-Item -Path $extractFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            WriteLog "Extract folder created"
        }
        catch {
            WriteLog "WARNING: Failed to create extract folder: $($_.Exception.Message)"
            Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
            continue
        }

        # Modify the extract command
        $modifiedExtractCommand = $extractCommand -replace '%PACKAGEPATH%', "`"$extractFolder`""

        # Extract the driver with exit code classification (REL-DRV-02)
        WriteLog "Extracting driver: $driverFilePath to $extractFolder"
        try {
            $extractProcess = Start-Process -FilePath $driverFilePath -ArgumentList $modifiedExtractCommand -PassThru -Wait -NoNewWindow
            $extractionResult = Get-DriverExtractionResult -Vendor 'Lenovo' -ExitCode $extractProcess.ExitCode -DriverName $packageTitle

            if ($extractionResult.Action -eq 'Warn') {
                WriteLog "WARNING: $($extractionResult.Message)"
            }
            elseif ($extractionResult.Action -eq 'Fail') {
                WriteLog "ERROR: $($extractionResult.Message)"
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
                continue  # Skip to next driver
            }
            else {
                WriteLog "Driver extracted"
            }
        }
        catch {
            WriteLog "WARNING: Failed to extract Lenovo driver '$packageTitle': $($_.Exception.Message)"
        }

        # Delete the .exe driver file after extraction
        WriteLog "Deleting driver installation file: $driverFilePath"
        try {
            Remove-Item -Path $driverFilePath -Force -ErrorAction Stop
            WriteLog "Driver installation file deleted: $driverFilePath"
        }
        catch {
            WriteLog "WARNING: Failed to delete driver installer: $($_.Exception.Message)"
        }

        # Delete the package XML file after extraction
        WriteLog "Deleting package XML file: $packageXMLPath"
        try {
            Remove-Item -Path $packageXMLPath -Force -ErrorAction Stop
            WriteLog "Package XML file deleted"
        }
        catch {
            WriteLog "WARNING: Failed to delete package XML: $($_.Exception.Message)"
        }
    }

    #Delete the catalog XML file after processing
    WriteLog "Deleting catalog XML file: $LenovoCatalogXML"
    Remove-Item -Path $LenovoCatalogXML -Force -ErrorAction SilentlyContinue
    WriteLog "Catalog XML file deleted"
}

function Get-DellDrivers {
    <#
    .SYNOPSIS
    Downloads and extracts Dell drivers for FFU builds

    .DESCRIPTION
    Downloads Dell driver catalog, parses available models, and extracts the
    appropriate driver packages for the specified Dell model and Windows version.
    Uses Dell's online catalog for driver discovery.

    .PARAMETER Make
    OEM manufacturer name (e.g., "Dell")

    .PARAMETER Model
    Dell model name (e.g., "Latitude 7490", "OptiPlex 7080")

    .PARAMETER WindowsArch
    Windows architecture (x64, x86, or ARM64)

    .PARAMETER WindowsRelease
    Windows release version (10, 11, 2016, 2019, 2022, 2025)

    .PARAMETER DriversFolder
    Root path where drivers should be downloaded and extracted

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download tracking

    .PARAMETER isServer
    Boolean indicating if target OS is Windows Server (affects driver extraction behavior)

    .EXAMPLE
    Get-DellDrivers -Make "Dell" -Model "Latitude 7490" -WindowsArch "x64" `
                    -WindowsRelease 11 -DriversFolder "C:\FFU\Drivers" `
                    -FFUDevelopmentPath "C:\FFU" -isServer $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,

        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [bool]$isServer
    )

    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }

    $DriversFolder = "$DriversFolder\$Make"
    WriteLog "Creating Dell Drivers folder: $DriversFolder"
    New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
    WriteLog "Dell Drivers folder created"

    #CatalogPC.cab is the catalog for Windows client PCs, Catalog.cab is the catalog for Windows Server (with caching)
    if ($WindowsRelease -le 11) {
        $catalogType = 'PC'
        $primaryUrl = [FFUConstants]::DELL_CATALOG_PC_URL
        $DellCabFile = "$DriversFolder\CatalogPC.cab"
        $DellCatalogXML = "$DriversFolder\CatalogPC.XML"
    }
    else {
        $catalogType = 'Server'
        $primaryUrl = [FFUConstants]::DELL_CATALOG_SERVER_URL
        $DellCabFile = "$DriversFolder\Catalog.cab"
        $DellCatalogXML = "$DriversFolder\Catalog.xml"
    }

    try {
        $DellCabFile = Get-CachedOEMCatalog -Vendor 'Dell' -CatalogType $catalogType `
            -PrimaryUrl $primaryUrl -CachePath $DellCabFile
    }
    catch {
        WriteLog "ERROR: $($_.Exception.Message)"
        throw
    }

    WriteLog "Extracting Dell Catalog cab file to $DellCatalogXML"
    try {
        Invoke-Process -FilePath Expand.exe -ArgumentList "$DellCabFile $DellCatalogXML" -ErrorAction Stop | Out-Null
        WriteLog "Dell Catalog cab file extracted"
    }
    catch {
        WriteLog "ERROR: Failed to extract Dell catalog cab file: $($_.Exception.Message)"
        throw "Failed to extract Dell driver catalog: $($_.Exception.Message)"
    }

    try {
        $xmlContent = [xml](Get-Content -Path $DellCatalogXML -ErrorAction Stop)
    }
    catch {
        WriteLog "ERROR: Failed to parse Dell catalog XML: $($_.Exception.Message)"
        throw "Failed to parse Dell driver catalog: $($_.Exception.Message)"
    }
    $baseLocation = "https://" + $xmlContent.manifest.baseLocation + "/"
    $latestDrivers = @{}

    $softwareComponents = $xmlContent.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq "DRVR" }
    foreach ($component in $softwareComponents) {
        $models = $component.SupportedSystems.Brand.Model
        foreach ($item in $models) {
            if ($item.Display.'#cdata-section' -match $Model) {

                if ($WindowsRelease -le 11) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { $_.osArch -eq $WindowsArch }
                }
                elseif ($WindowsRelease -eq 2016) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W14") }
                }
                elseif ($WindowsRelease -eq 2019) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W19") }
                }
                elseif ($WindowsRelease -eq 2022) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W22") }
                }
                elseif ($WindowsRelease -eq 2025) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W25") }
                }
                else {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W22") }
                }

                if ($validOS) {
                    $driverPath = $component.path
                    $downloadUrl = $baseLocation + $driverPath
                    $driverFileName = [System.IO.Path]::GetFileName($driverPath)
                    $name = $component.Name.Display.'#cdata-section'
                    $name = $name -replace '[\\\/\:\*\?\"\<\>\| ]', '_'
                    $name = $name -replace '[\,]', '-'
                    $category = $component.Category.Display.'#cdata-section'
                    $category = $category -replace '[\\\/\:\*\?\"\<\>\| ]', '_'
                    $version = [version]$component.vendorVersion
                    $namePrefix = ($name -split '-')[0]

                    # Use hash table to store the latest driver for each category to prevent downloading older driver versions
                    if ($latestDrivers[$category]) {
                        if ($latestDrivers[$category][$namePrefix]) {
                            if ($latestDrivers[$category][$namePrefix].Version -lt $version) {
                                $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                                    Name           = $name;
                                    DownloadUrl    = $downloadUrl;
                                    DriverFileName = $driverFileName;
                                    Version        = $version;
                                    Category       = $category
                                }
                            }
                        }
                        else {
                            $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                                Name           = $name;
                                DownloadUrl    = $downloadUrl;
                                DriverFileName = $driverFileName;
                                Version        = $version;
                                Category       = $category
                            }
                        }
                    }
                    else {
                        $latestDrivers[$category] = @{}
                        $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                            Name           = $name;
                            DownloadUrl    = $downloadUrl;
                            DriverFileName = $driverFileName;
                            Version        = $version;
                            Category       = $category
                        }
                    }
                }
            }
        }
    }

    foreach ($category in $latestDrivers.Keys) {
        foreach ($driver in $latestDrivers[$category].Values) {
            $downloadFolder = "$DriversFolder\$Model\$($driver.Category)"
            $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driver.DriverFileName

            if (Test-Path -Path $driverFilePath) {
                WriteLog "Driver already downloaded: $driverFilePath skipping"
                continue
            }

            WriteLog "Downloading driver: $($driver.Name)"
            if (-not (Test-Path -Path $downloadFolder)) {
                WriteLog "Creating download folder: $downloadFolder"
                New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
                WriteLog "Download folder created"
            }

            WriteLog "Downloading driver: $($driver.DownloadUrl) to $driverFilePath"
            Set-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
            try {
                Invoke-DriverDownloadWithRetry -Source $driver.DownloadUrl -Destination $driverFilePath -OperationName "Dell driver $($driver.Name)"
                Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
            }
            catch {
                Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
                WriteLog "WARNING: Failed to download Dell driver '$($driver.Name)' after all retries: $($_.Exception.Message)"
                continue
            }


            $extractFolder = $downloadFolder + "\" + $driver.DriverFileName.TrimEnd($driver.DriverFileName[-4..-1])
            # WriteLog "Creating extraction folder: $extractFolder"
            # New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
            # WriteLog "Extraction folder created"

            # $arguments = "/s /e /f `"$extractFolder`""
            $arguments = "/s /drivers=`"$extractFolder`""
            WriteLog "Extracting driver: $driverFilePath $arguments"
            try {
                #If Category is Chipset, use timeout-based extraction to prevent hanging on Intel chipset driver GUI windows
                if ($driver.Category -eq "Chipset") {
                    WriteLog "Extracting Chipset driver with timeout protection: $driverFilePath"
                    $process = Start-Process -FilePath $driverFilePath -ArgumentList $arguments -PassThru -NoNewWindow

                    # Wait with timeout - WaitForExit returns $true if process exited, $false if timed out
                    $timeoutSeconds = [FFUConstants]::DRIVER_EXTRACTION_TIMEOUT_SECONDS
                    $completed = $process.WaitForExit($timeoutSeconds * 1000)

                    if (-not $completed) {
                        WriteLog "WARNING: Chipset driver extraction timed out after ${timeoutSeconds}s - killing process tree"

                        # Kill child processes first (Intel GUI windows)
                        $childProcesses = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)" -ErrorAction SilentlyContinue
                        foreach ($child in $childProcesses) {
                            WriteLog "Stopping child process: $($child.Name) (PID: $($child.ProcessId))"
                            Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
                        }

                        # Kill parent process
                        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds ([FFUConstants]::SERVICE_STARTUP_WAIT)  # Allow cleanup
                    }
                    else {
                        # REL-DRV-02: Classify Dell Chipset driver extraction exit code
                        $extractionResult = Get-DriverExtractionResult -Vendor 'Dell' -ExitCode $process.ExitCode -DriverName $driver.Name
                        if ($extractionResult.Action -eq 'Warn') {
                            WriteLog "WARNING: $($extractionResult.Message)"
                        }
                        elseif ($extractionResult.Action -eq 'Fail') {
                            WriteLog "ERROR: $($extractionResult.Message)"
                            continue  # Skip to next driver
                        }
                        else {
                            WriteLog "Chipset driver extraction completed successfully"
                        }
                    }
                }
                #If Category is Network and $isServer is $false, use timeout-based extraction to prevent hanging on Intel network driver GUI windows
                elseif ($driver.Category -eq "Network" -and $isServer -eq $false) {
                    WriteLog "Extracting Network driver with timeout protection: $driverFilePath"
                    $process = Start-Process -FilePath $driverFilePath -ArgumentList $arguments -PassThru -NoNewWindow

                    # Wait with timeout
                    $timeoutSeconds = [FFUConstants]::DRIVER_EXTRACTION_TIMEOUT_SECONDS
                    $completed = $process.WaitForExit($timeoutSeconds * 1000)

                    if (-not $completed) {
                        WriteLog "WARNING: Network driver extraction timed out after ${timeoutSeconds}s - killing process tree"

                        # Kill child processes first (Intel GUI windows)
                        $childProcesses = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)" -ErrorAction SilentlyContinue
                        foreach ($child in $childProcesses) {
                            WriteLog "Stopping child process: $($child.Name) (PID: $($child.ProcessId))"
                            Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
                        }

                        # Kill parent process
                        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds ([FFUConstants]::SERVICE_STARTUP_WAIT)  # Allow cleanup
                        # Move on to the next driver - it won't extract on a client OS even with /s /e switches
                        continue
                    }
                    else {
                        # REL-DRV-02: Classify Dell Network driver extraction exit code
                        $extractionResult = Get-DriverExtractionResult -Vendor 'Dell' -ExitCode $process.ExitCode -DriverName $driver.Name
                        if ($extractionResult.Action -eq 'Warn') {
                            WriteLog "WARNING: $($extractionResult.Message)"
                        }
                        elseif ($extractionResult.Action -eq 'Fail') {
                            WriteLog "ERROR: $($extractionResult.Message)"
                            continue  # Skip to next driver
                        }
                        else {
                            WriteLog "Network driver extraction completed successfully"
                        }
                    }
                }
                else {
                    # Other Dell drivers - use Invoke-Process with exit code classification (REL-DRV-02)
                    $dellProcess = Start-Process -FilePath $driverFilePath -ArgumentList $arguments -PassThru -Wait -NoNewWindow
                    $extractionResult = Get-DriverExtractionResult -Vendor 'Dell' -ExitCode $dellProcess.ExitCode -DriverName $driver.Name
                    if ($extractionResult.Action -eq 'Warn') {
                        WriteLog "WARNING: $($extractionResult.Message)"
                    }
                    elseif ($extractionResult.Action -eq 'Fail') {
                        WriteLog "ERROR: $($extractionResult.Message)"
                        continue  # Skip to next driver
                    }
                }
                # If $extractFolder is empty, try alternative extraction method
                if (!(Get-ChildItem -Path $extractFolder -Recurse | Where-Object { -not $_.PSIsContainer })) {
                    WriteLog 'Extraction with /drivers= switch failed. Removing folder and retrying with /s /e switches'
                    Remove-Item -Path $extractFolder -Force -Recurse -ErrorAction SilentlyContinue
                    $arguments = "/s /e=`"$extractFolder`""
                    WriteLog "Extracting driver: $driverFilePath $arguments"
                    Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments | Out-Null
                }
            }
            catch {
                WriteLog 'Extraction with /drivers= switch failed. Retrying with /s /e switches'
                $arguments = "/s /e=`"$extractFolder`""
                WriteLog "Extracting driver: $driverFilePath $arguments"
                Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments | Out-Null
            }
            WriteLog "Driver extracted"

            WriteLog "Deleting driver file: $driverFilePath"
            Remove-Item -Path $driverFilePath -Force -ErrorAction SilentlyContinue
            WriteLog "Driver file deleted"
        }
    }
}

function Copy-Drivers {
    <#
    .SYNOPSIS
    Copies WinPE-compatible drivers from OEM driver repository to deployment media

    .DESCRIPTION
    Filters and copies essential drivers (system, storage, HID) from downloaded OEM
    driver packages to WinPE media. Uses device class GUIDs to identify required
    drivers and excludes unnecessary components (audio, camera, firmware) to minimize
    media size.

    .PARAMETER Path
    Source path containing OEM driver packages to filter

    .PARAMETER Output
    Destination path where filtered drivers will be copied (typically WinPE media)

    .PARAMETER WindowsArch
    Windows architecture (x64, x86, or ARM64) - used to copy architecture-specific driver files

    .EXAMPLE
    Copy-Drivers -Path "C:\FFU\Drivers\Dell\Latitude 7490" -Output "C:\FFU\PEDrivers" -WindowsArch "x64"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch
    )
    # Find more information about device classes here:
    # https://learn.microsoft.com/en-us/windows-hardware/drivers/install/system-defined-device-setup-classes-available-to-vendors
    # For now, included are system devices, scsi and raid controllers, keyboards, mice, HID devices, and network adapters
    # 4D36E97D-E325-11CE-BFC1-08002BE10318 = System devices
    # 4D36E97B-E325-11CE-BFC1-08002BE10318 = SCSI, RAID, and NVMe Controllers
    # 4d36e96b-e325-11ce-bfc1-08002be10318 = Keyboards
    # 4d36e96f-e325-11ce-bfc1-08002be10318 = Mice and other pointing devices
    # 745a17a0-74d3-11d0-b6fe-00a0c90f57da = Human Interface Devices
    # 4D36E972-E325-11CE-BFC1-08002BE10318 = Network Adapters (for WinPE network support, especially VMware)
    $filterGUIDs = @(
        "{4D36E97D-E325-11CE-BFC1-08002BE10318}",  # System devices
        "{4D36E97B-E325-11CE-BFC1-08002BE10318}",  # SCSI, RAID, NVMe
        "{4d36e96b-e325-11ce-bfc1-08002be10318}",  # Keyboards
        "{4d36e96f-e325-11ce-bfc1-08002be10318}",  # Mice
        "{745a17a0-74d3-11d0-b6fe-00a0c90f57da}",  # HID
        "{4D36E972-E325-11CE-BFC1-08002BE10318}"   # Network Adapters
    )
    # Exclude audio, camera, firmware, and wireless drivers to keep WinPE size small
    $exclusionList = "wdmaudio.inf|Sound|Machine Learning|Camera|Firmware|Bluetooth|WiFi|Wireless"
    $pathLength = $Path.Length
    $infFiles = Get-ChildItem -Path $Path -Recurse -Filter "*.inf"

    for ($i = 0; $i -lt $infFiles.Count; $i++) {
        $infFullName = $infFiles[$i].FullName
        $infPath = Split-Path -Path $infFullName
        $childPath = $infPath.Substring($pathLength)
        $targetPath = Join-Path -Path $Output -ChildPath $childPath

        if ((Get-PrivateProfileString -FileName $infFullName -SectionName "version" -KeyName "ClassGUID") -in $filterGUIDs) {
            #Avoid drivers that reference keywords from the exclusion list to keep the total size small
            if (((Get-Content -Path $infFullName) -match $exclusionList).Length -eq 0) {
                $providerName = (Get-PrivateProfileString -FileName $infFullName -SectionName "Version" -KeyName "Provider").Trim("%")

                WriteLog "Copying PE drivers for $providerName"
                WriteLog "Driver inf is: $infFullName"
                [void](New-Item -Path $targetPath -ItemType Directory -Force)
                Copy-Item -Path $infFullName -Destination $targetPath -Force
                $CatalogFileName = Get-PrivateProfileString -FileName $infFullName -SectionName "version" -KeyName "Catalogfile"
                Copy-Item -Path "$infPath\$CatalogFileName" -Destination $targetPath -Force

                $sourceDiskFiles = Get-PrivateProfileSection -FileName $infFullName -SectionName "SourceDisksFiles"
                foreach ($sourceDiskFile in $sourceDiskFiles.Keys) {
                    if (!$sourceDiskFiles[$sourceDiskFile].Contains(",")) {
                        Copy-Item -Path "$infPath\$sourceDiskFile" -Destination $targetPath -Force
                    }
                    else {
                        $subdir = ($sourceDiskFiles[$sourceDiskFile] -split ",")[1]
                        [void](New-Item -Path "$targetPath\$subdir" -ItemType Directory -Force)
                        Copy-Item -Path "$infPath\$subdir\$sourceDiskFile" -Destination "$targetPath\$subdir" -Force
                    }
                }

                #Arch specific files override the files specified in the universal section
                $sourceDiskFiles = Get-PrivateProfileSection -FileName $infFullName -SectionName "SourceDisksFiles.$WindowsArch"
                foreach ($sourceDiskFile in $sourceDiskFiles.Keys) {
                    if (!$sourceDiskFiles[$sourceDiskFile].Contains(",")) {
                        Copy-Item -Path "$infPath\$sourceDiskFile" -Destination $targetPath -Force
                    }
                    else {
                        $subdir = ($sourceDiskFiles[$sourceDiskFile] -split ",")[1]
                        [void](New-Item -Path "$targetPath\$subdir" -ItemType Directory -Force)
                        Copy-Item -Path "$infPath\$subdir\$sourceDiskFile" -Destination "$targetPath\$subdir" -Force
                    }
                }
            }
        }
    }
}

function Get-IntelEthernetDrivers {
    <#
    .SYNOPSIS
    Downloads Intel Ethernet drivers for WinPE network support (especially VMware e1000e)

    .DESCRIPTION
    Downloads the Intel Ethernet Adapter Complete Driver Pack and extracts
    the e1000e drivers needed for WinPE network connectivity in VMware VMs.
    VMware Workstation Pro uses e1000e (Intel 82574L) emulated NICs by default.

    .PARAMETER DestinationPath
    Path where the Intel e1000e drivers will be extracted

    .PARAMETER TempPath
    Temporary path for download and extraction operations. Defaults to $env:TEMP

    .EXAMPLE
    Get-IntelEthernetDrivers -DestinationPath "C:\FFU\VMwareDrivers"

    .NOTES
    Driver source: Intel Ethernet Adapter Complete Driver Pack v30.6
    https://www.intel.com/content/www/us/en/download/15084/intel-ethernet-adapter-complete-driver-pack.html
    Note: Intel CDN requires browser-like headers to avoid 403 Forbidden errors.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $false)]
        [string]$TempPath = $env:TEMP
    )

    # Intel Ethernet Adapter Complete Driver Pack v30.6
    # Source: https://www.intel.com/content/www/us/en/download/15084/intel-ethernet-adapter-complete-driver-pack.html
    # This contains PRO1000 drivers including e1000e for VMware compatibility
    $downloadUrl = "https://downloadmirror.intel.com/871940/Release_30.6.zip"
    $zipFile = Join-Path $TempPath "Intel_Ethernet_Drivers.zip"
    $extractPath = Join-Path $TempPath "Intel_Ethernet_Extract_$(Get-Date -Format 'yyyyMMddHHmmss')"

    # Browser-like headers required to bypass Intel CDN 403 block
    $headers = @{
        'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        'Accept-Language' = 'en-US,en;q=0.5'
        'Accept-Encoding' = 'gzip, deflate, br'
    }
    $userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

    WriteLog "Downloading Intel Ethernet Driver Pack v30.6 for VMware WinPE support..."
    WriteLog "Source: $downloadUrl"

    $downloadSuccess = $false
    try {
        # Download with browser-like headers to avoid 403 from Intel CDN
        WriteLog "Attempting download via Invoke-WebRequest..."
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -Headers $headers -UserAgent $userAgent -UseBasicParsing -ErrorAction Stop
        WriteLog "Download complete: $zipFile"
        WriteLog "File exists at: $zipFile = $(Test-Path $zipFile)"
        $downloadSuccess = $true
    }
    catch {
        WriteLog "WebRequest download failed: $($_.Exception.Message)"
        WriteLog "Attempting BITS transfer as fallback..."

        try {
            # BITS fallback for restricted networks
            Start-BitsTransfer -Source $downloadUrl -Destination $zipFile -ErrorAction Stop
            WriteLog "BITS download complete: $zipFile"
            WriteLog "File exists at: $zipFile = $(Test-Path $zipFile)"
            $downloadSuccess = $true
        }
        catch {
            WriteLog "BITS download also failed: $($_.Exception.Message)"
            throw "Failed to download Intel Ethernet drivers via both WebRequest and BITS. Original error: $($_.Exception.Message)"
        }
    }

    if (-not $downloadSuccess) {
        throw "Download failed - no successful download method"
    }

    # Verify download
    if (-not (Test-Path $zipFile)) {
        throw "Download verification failed: $zipFile does not exist"
    }

    $fileSize = (Get-Item $zipFile).Length
    # Intel Ethernet pack is ~65MB - use 50MB as minimum threshold
    $expectedMinSize = 50MB
    WriteLog "Downloaded file size: $([math]::Round($fileSize / 1MB, 2)) MB (expected: ~65 MB, minimum: 50 MB)"

    if ($fileSize -lt $expectedMinSize) {
        # Check if file is HTML (common proxy/firewall block response)
        try {
            $firstBytes = Get-Content $zipFile -First 1 -Raw -ErrorAction Stop
            if ($firstBytes -match '<!DOCTYPE|<html|<HTML') {
                WriteLog "ERROR: Downloaded file appears to be HTML (likely proxy/firewall block)"
                $preview = $firstBytes.Substring(0, [Math]::Min(200, $firstBytes.Length))
                WriteLog "Content preview: $preview"
            }
        }
        catch {
            WriteLog "Could not read file content for validation: $($_.Exception.Message)"
        }
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        throw "Downloaded file is too small ($([math]::Round($fileSize / 1MB, 2)) MB), expected ~65 MB. May be corrupted or blocked by proxy/firewall."
    }

    # Extract the archive
    WriteLog "Extracting Intel Ethernet drivers to: $extractPath"
    try {
        Expand-Archive -Path $zipFile -DestinationPath $extractPath -Force
    }
    catch {
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        throw "Failed to extract Intel Ethernet drivers: $($_.Exception.Message)"
    }

    # Verify extraction produced files
    $extractedFiles = Get-ChildItem -Path $extractPath -Recurse -File -ErrorAction SilentlyContinue
    WriteLog "Extraction complete. Found $($extractedFiles.Count) files in temp location"
    if ($extractedFiles.Count -eq 0) {
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        throw "Extraction produced no files - archive may be corrupted or empty"
    }

    # Locate e1000e drivers (PRO1000\Winx64\NDIS68 for Windows 10/11)
    # NDIS68 = Windows 10/11 compatible drivers
    # v30.6 structure may be: Release_30.6\PRO1000\Winx64\NDIS68
    $e1000ePaths = @(
        (Join-Path $extractPath "PRO1000\Winx64\NDIS68"),
        (Join-Path $extractPath "Release_*\PRO1000\Winx64\NDIS68"),
        (Join-Path $extractPath "Wired_driver*\PRO1000\Winx64\NDIS68"),
        (Join-Path $extractPath "*\PRO1000\Winx64\NDIS68")
    )

    $e1000eSource = $null
    foreach ($searchPath in $e1000ePaths) {
        $matches = Get-Item $searchPath -ErrorAction SilentlyContinue
        if ($matches) {
            $e1000eSource = $matches[0].FullName
            WriteLog "Found e1000e drivers at: $e1000eSource"
            break
        }
    }

    if (-not $e1000eSource) {
        # Fallback: search for e1000e.inf directly
        $infSearch = Get-ChildItem -Path $extractPath -Filter "e1000e.inf" -Recurse -ErrorAction SilentlyContinue
        if ($infSearch) {
            $e1000eSource = Split-Path $infSearch[0].FullName -Parent
            WriteLog "Found e1000e drivers via INF search at: $e1000eSource"
        }
    }

    if (-not $e1000eSource) {
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        throw "Could not locate e1000e drivers in extracted archive"
    }

    # Create destination and copy drivers
    $destE1000e = Join-Path $DestinationPath "e1000e"
    WriteLog "Copying e1000e drivers to: $destE1000e"
    WriteLog "Source path: $e1000eSource"

    # Create destination directory
    New-Item -Path $destE1000e -ItemType Directory -Force | Out-Null
    WriteLog "Destination directory created: $(Test-Path $destE1000e)"

    # Count source files before copy
    $sourceFiles = Get-ChildItem -Path "$e1000eSource" -Recurse -File -ErrorAction SilentlyContinue
    WriteLog "Source contains $($sourceFiles.Count) files to copy"

    # Copy files
    Copy-Item -Path "$e1000eSource\*" -Destination $destE1000e -Recurse -Force

    # Verify copied files
    $copiedFiles = Get-ChildItem -Path $destE1000e -Recurse -File -ErrorAction SilentlyContinue
    WriteLog "Copied $($copiedFiles.Count) total files to destination"

    $infFiles = Get-ChildItem -Path $destE1000e -Filter "*.inf" -ErrorAction SilentlyContinue
    if (-not $infFiles) {
        WriteLog "ERROR: No INF files found after copy!"
        WriteLog "Destination path exists: $(Test-Path $destE1000e)"
        WriteLog "Files in destination: $(($copiedFiles | Select-Object -ExpandProperty Name) -join ', ')"
        throw "Driver copy verification failed: no INF files found in $destE1000e"
    }
    WriteLog "Successfully verified $($infFiles.Count) driver INF file(s) in $destE1000e"
    foreach ($inf in $infFiles) {
        WriteLog "  - $($inf.Name)"
    }

    # Cleanup temp files
    WriteLog "Cleaning up temporary files..."
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

    WriteLog "Intel e1000e drivers ready for WinPE injection"
    return $destE1000e
}

# Export all functions
Export-ModuleMember -Function @(
    'Get-MicrosoftDrivers',
    'Get-HPDrivers',
    'Get-LenovoDrivers',
    'Get-DellDrivers',
    'Copy-Drivers',
    'Get-IntelEthernetDrivers'
)