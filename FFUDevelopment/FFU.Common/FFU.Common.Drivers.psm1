<#
.SYNOPSIS
    Provides common functions for driver management, including compression, mapping, and existence checks.

.DESCRIPTION
    The FFU.Common.Drivers module contains a set of shared functions used across the FFU project for handling driver packages.
    This includes compressing driver folders into WIM files for efficient storage and deployment, maintaining a JSON-based mapping
    of downloaded drivers to their respective makes and models, and checking for the pre-existence of driver packages to avoid
    redundant downloads.
#>
function Compress-DriverFolderToWim {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$SourceFolderPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationWimPath,

        [Parameter()]
        [string]$WimName, # Optional, defaults to folder name

        [Parameter()]
        [string]$WimDescription, # Optional, defaults to folder name

        [Parameter()]
        [bool]$PreserveSource = $false # When $true, do not delete source folder; create marker for deferred cleanup
    )

    WriteLog "Starting compression of folder '$SourceFolderPath' to '$DestinationWimPath'."

    # Default WIM Name and Description to the source folder name if not provided
    $sourceFolderName = Split-Path -Path $SourceFolderPath -Leaf
    if ([string]::IsNullOrWhiteSpace($WimName)) {
        $WimName = $sourceFolderName
        WriteLog "WIM Name not provided, defaulting to source folder name: '$WimName'."
    }
    if ([string]::IsNullOrWhiteSpace($WimDescription)) {
        $WimDescription = $sourceFolderName
        WriteLog "WIM Description not provided, defaulting to source folder name: '$WimDescription'."
    }

    # Ensure destination directory exists
    $destinationDir = Split-Path -Path $DestinationWimPath -Parent
    if (-not (Test-Path -Path $destinationDir -PathType Container)) {
        WriteLog "Creating destination directory: $destinationDir"
        try {
            New-Item -Path $destinationDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            WriteLog "Failed to create destination directory '$destinationDir': $($_.Exception.Message)"
            $false # Indicate failure
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("Folder '$SourceFolderPath'", "Compress to WIM '$DestinationWimPath'")) {
        try {
            # Construct arguments for dism.exe
            $dismArgs = "/Capture-Image /ImageFile:`"$DestinationWimPath`" /CaptureDir:`"$SourceFolderPath`" /Name:`"$WimName`" /Description:`"$WimDescription`" /Compress:Max /CheckIntegrity /Quiet"

            WriteLog "Executing dism.exe via Invoke-Process with arguments:"
            WriteLog "dism.exe $dismArgs"

            # Call Invoke-Process (assumed to be available from FFUUI.Core.psm1 or another imported module)
            # Invoke-Process is expected to throw an exception for non-zero exit codes.
            Invoke-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait $true

            WriteLog "Successfully compressed '$SourceFolderPath' to '$DestinationWimPath' using dism.exe."

            # Remove the source folder after successful compression
            if ($PreserveSource) {
                WriteLog "Preserving source driver folder for deferred WinPE driver harvesting: $SourceFolderPath"
                try {
                    $markerFile = Join-Path -Path $SourceFolderPath -ChildPath '__PreservedForPEDrivers.txt'
                    if (-not (Test-Path -Path $markerFile -PathType Leaf)) {
                        New-Item -Path $markerFile -ItemType File -Force | Out-Null
                        WriteLog "Created preservation marker file: $markerFile"
                    }
                }
                catch {
                    WriteLog "Warning: Failed to create preservation marker in $SourceFolderPath. Error: $($_.Exception.Message)"
                }
            }
            else {
                WriteLog "Removing source driver folder: $SourceFolderPath"
                try {
                    Remove-Item -Path $SourceFolderPath -Recurse -Force -ErrorAction Stop
                    WriteLog "Successfully removed source folder '$SourceFolderPath'."
                }
                catch {
                    WriteLog "Warning: Failed to remove source folder '$SourceFolderPath'. Error: $($_.Exception.Message)"
                    # Do not fail the whole operation, just log a warning.
                }
            }

            $true # Indicate success
        }
        catch {
            WriteLog "Failed to compress folder '$SourceFolderPath' to WIM '$DestinationWimPath' using dism.exe."
            WriteLog "Error details: $($_.Exception.Message)"
            # Check if the error message contains details about the DISM log (dism.exe output might be in the exception)
            if ($_.Exception.Message -match 'DISM log file can be found at (.*)') {
                $dismLogPath = $matches[1].Trim()
                WriteLog "Check the DISM log for more details: $dismLogPath"
            }
            $false # Indicate failure
        }
    }
    else {
        WriteLog "Compression operation skipped due to -WhatIf."
        $false # Indicate skipped operation
    }
}

# --------------------------------------------------------------------------
# SECTION: HP PlatformList.xml SystemID Lookup
# --------------------------------------------------------------------------

function Get-HPSystemIdFromPlatformList {
    <#
    .SYNOPSIS
        Resolves an HP model name to a SystemID using PlatformList.xml.

    .DESCRIPTION
        Loads HP PlatformList.xml, builds a ProductName-to-SystemID hashtable cache,
        and performs 3-tier matching (exact, alphanumeric-stripped, contains) to find
        the SystemID for a given HP model. If PlatformList.xml is not found locally,
        attempts download from HP's CDN. All failures are non-throwing.

    .PARAMETER ModelName
        The HP model name to look up.

    .PARAMETER DriversFolder
        Base drivers folder (e.g., C:\FFUDevelopment\Drivers).

    .PARAMETER PlatformCache
        Optional pre-built hashtable of ProductName -> SystemID mappings.
        If provided, skips XML parsing and uses the cache directly.

    .OUTPUTS
        [string] The SystemID in uppercase, or $null if not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelName,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter()]
        [hashtable]$PlatformCache = $null
    )

    # Build cache if not provided
    if ($null -eq $PlatformCache) {
        $PlatformCache = @{}
        $platformListXml = Join-Path -Path $DriversFolder -ChildPath "HP\PlatformList.xml"

        # Attempt download if file doesn't exist
        if (-not (Test-Path -Path $platformListXml -PathType Leaf)) {
            try {
                WriteLog "HP PlatformList.xml not found at '$platformListXml'. Attempting download..."
                $hpDriversFolder = Join-Path -Path $DriversFolder -ChildPath "HP"
                if (-not (Test-Path -Path $hpDriversFolder -PathType Container)) {
                    New-Item -Path $hpDriversFolder -ItemType Directory -Force | Out-Null
                }
                $platformListCab = Join-Path -Path $hpDriversFolder -ChildPath "platformList.cab"
                $platformListUrl = 'https://hpia.hpcloud.hp.com/ref/platformList.cab'

                # Use .NET WebClient for download (no BITS dependency)
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($platformListUrl, $platformListCab)
                $webClient.Dispose()
                WriteLog "HP PlatformList.cab downloaded to '$platformListCab'."

                # Expand CAB
                $expandArgs = @($platformListCab, $platformListXml)
                $expandProcess = Start-Process -FilePath "expand.exe" -ArgumentList $expandArgs `
                    -Wait -PassThru -NoNewWindow
                if ($expandProcess.ExitCode -ne 0) {
                    WriteLog "WARNING: expand.exe returned exit code $($expandProcess.ExitCode) for PlatformList.cab."
                }

                # Clean up CAB
                Remove-Item -Path $platformListCab -Force -ErrorAction SilentlyContinue
            }
            catch {
                WriteLog "WARNING: Could not download HP PlatformList.xml for SystemID extraction: $($_.Exception.Message)"
                return $null
            }
        }

        # Parse PlatformList.xml into cache
        if (-not (Test-Path -Path $platformListXml -PathType Leaf)) {
            WriteLog "WARNING: HP PlatformList.xml still not available after download attempt."
            return $null
        }

        try {
            [xml]$platformListContent = Get-Content -Path $platformListXml -Raw -Encoding UTF8 -ErrorAction Stop
            foreach ($platform in $platformListContent.ImagePal.Platform) {
                $productNames = @($platform.ProductName)
                foreach ($productNameNode in $productNames) {
                    $productName = $null
                    if ($productNameNode -is [string]) {
                        $productName = $productNameNode.Trim()
                    }
                    elseif ($null -ne $productNameNode.'#text') {
                        $productName = $productNameNode.'#text'.Trim()
                    }
                    elseif ($null -ne $productNameNode.InnerText) {
                        $productName = $productNameNode.InnerText.Trim()
                    }

                    if (-not [string]::IsNullOrWhiteSpace($productName) -and
                        -not [string]::IsNullOrWhiteSpace($platform.SystemID)) {
                        $normalizedId = $platform.SystemID.Trim().ToUpperInvariant()
                        if (-not $PlatformCache.ContainsKey($productName)) {
                            $PlatformCache[$productName] = $normalizedId
                        }
                    }
                }
            }
            WriteLog "HP PlatformList.xml parsed: $($PlatformCache.Count) product-to-SystemID mappings cached."
        }
        catch {
            WriteLog "WARNING: Could not parse HP PlatformList.xml: $($_.Exception.Message)"
            return $null
        }
    }

    if ($PlatformCache.Count -eq 0) {
        WriteLog "HP SystemID lookup skipped: PlatformList.xml cache is empty."
        return $null
    }

    # Tier 1: Exact case-insensitive match
    $exactMatch = $PlatformCache.GetEnumerator() | Where-Object {
        $_.Key -eq $ModelName
    } | Select-Object -First 1

    if ($null -ne $exactMatch) {
        return $exactMatch.Value.Trim().ToUpperInvariant()
    }

    # Tier 2: Stripped-to-alphanumeric match
    $strippedModel = ($ModelName -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    $alphanumericMatch = $PlatformCache.GetEnumerator() | Where-Object {
        ($_.Key -replace '[^A-Za-z0-9]', '').ToLowerInvariant() -eq $strippedModel
    } | Select-Object -First 1

    if ($null -ne $alphanumericMatch) {
        return $alphanumericMatch.Value.Trim().ToUpperInvariant()
    }

    # Tier 3: Contains match (ProductName contains model name or vice versa)
    $containsMatch = $PlatformCache.GetEnumerator() | Where-Object {
        $_.Key.IndexOf($ModelName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $ModelName.IndexOf($_.Key, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    } | Select-Object -First 1

    if ($null -ne $containsMatch) {
        return $containsMatch.Value.Trim().ToUpperInvariant()
    }

    WriteLog "HP SystemID not found in PlatformList.xml for model '$ModelName'."
    return $null
}

# --------------------------------------------------------------------------
# SECTION: Driver Mapping Function
# --------------------------------------------------------------------------

function Update-DriverMappingJson {
    <#
    .SYNOPSIS
        Updates DriverMapping.json with downloaded driver entries, including
        SystemID (Dell/HP) and MachineType (Lenovo) extraction.

    .DESCRIPTION
        Maintains a JSON-based mapping of downloaded drivers to their respective
        makes and models. Now includes build-time extraction of vendor-specific
        identifiers: SystemId for Dell (regex from model name) and HP (PlatformList.xml
        lookup), MachineType for Lenovo (regex from model name). All extraction
        failures are non-throwing with $null fallback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DownloadedDrivers, # Array of PSCustomObjects with Make, Model, DriverPath

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder # Base drivers folder (e.g., C:\FFUDevelopment\Drivers)
    )

    $mappingFilePath = Join-Path -Path $DriversFolder -ChildPath "DriverMapping.json"
    WriteLog "Updating driver mapping file at: $mappingFilePath"

    # Load existing mapping file or create a new list
    $mappingList = [System.Collections.Generic.List[PSCustomObject]]::new()
    if (Test-Path -Path $mappingFilePath -PathType Leaf) {
        try {
            $existingJson = Get-Content -Path $mappingFilePath -Raw | ConvertFrom-Json
            # Ensure it's a collection before adding to the list
            if ($existingJson -is [array]) {
                # Iterate through the array to avoid type conversion issues with AddRange
                foreach ($item in $existingJson) {
                    $mappingList.Add($item)
                }
            }
            else {
                $mappingList.Add($existingJson)
            }
            WriteLog "Loaded $($mappingList.Count) existing entries from $mappingFilePath"
        }
        catch {
            WriteLog "Warning: Could not read or parse existing DriverMapping.json. A new file will be created. Error: $($_.Exception.Message)"
        }
    }

    $updatedCount = 0
    $addedCount = 0

    # Regex for extracting parenthesized suffix from model names (Dell SystemId, Lenovo MachineType)
    # Example: "Dell Latitude 7490 (ABC1)" -> "ABC1", "ThinkPad T14s (21BR)" -> "21BR"
    $parenthesizedSuffixRegex = '\(([^)]+)\)\s*$'

    # Per-call HP PlatformList.xml cache (built once on first HP entry)
    $hpPlatformCache = $null
    $hpCacheInitialized = $false

    foreach ($driver in $DownloadedDrivers) {
        # Skip if any required property is missing or null
        if (-not $driver.PSObject.Properties['Make'] -or -not $driver.PSObject.Properties['Model'] -or -not $driver.PSObject.Properties['DriverPath'] -or [string]::IsNullOrWhiteSpace($driver.DriverPath)) {
            WriteLog "Skipping driver entry due to missing or empty Make, Model, or DriverPath. Details: $(($driver | ConvertTo-Json -Compress -Depth 3))"
            continue
        }

        # Extract SystemId/MachineType based on manufacturer
        $systemId = $null
        $machineType = $null
        $make = $driver.Make
        $modelName = $driver.Model

        switch -Wildcard ($make) {
            'Dell' {
                # Dell: Extract SystemId from parenthesized suffix in model name
                if ($modelName -match $parenthesizedSuffixRegex) {
                    $systemId = $matches[1].Trim().ToUpperInvariant()
                    WriteLog "[Dell] Extracted SystemId '$systemId' from model '$modelName'."
                }
                else {
                    WriteLog "[Dell] No parenthesized SystemId found in model '$modelName'."
                }
            }
            'HP' {
                # HP: Lookup SystemId from PlatformList.xml with 3-tier matching
                if (-not $hpCacheInitialized) {
                    $hpPlatformCache = @{}
                    $platformListXml = Join-Path -Path $DriversFolder -ChildPath "HP\PlatformList.xml"

                    if (Test-Path -Path $platformListXml -PathType Leaf) {
                        try {
                            [xml]$platformDoc = Get-Content -Path $platformListXml -Raw -Encoding UTF8 -ErrorAction Stop
                            foreach ($platform in $platformDoc.ImagePal.Platform) {
                                $productNames = @($platform.ProductName)
                                foreach ($pnNode in $productNames) {
                                    $pn = $null
                                    if ($pnNode -is [string]) {
                                        $pn = $pnNode.Trim()
                                    }
                                    elseif ($null -ne $pnNode.'#text') {
                                        $pn = $pnNode.'#text'.Trim()
                                    }
                                    elseif ($null -ne $pnNode.InnerText) {
                                        $pn = $pnNode.InnerText.Trim()
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($pn) -and
                                        -not [string]::IsNullOrWhiteSpace($platform.SystemID)) {
                                        $normalizedId = $platform.SystemID.Trim().ToUpperInvariant()
                                        if (-not $hpPlatformCache.ContainsKey($pn)) {
                                            $hpPlatformCache[$pn] = $normalizedId
                                        }
                                    }
                                }
                            }
                            WriteLog "HP PlatformList.xml cache built: $($hpPlatformCache.Count) entries."
                        }
                        catch {
                            WriteLog "WARNING: Could not parse HP PlatformList.xml for SystemID cache: $($_.Exception.Message)"
                        }
                    }
                    else {
                        WriteLog "HP PlatformList.xml not found at '$platformListXml'. HP SystemID extraction unavailable."
                    }
                    $hpCacheInitialized = $true
                }

                $systemId = Get-HPSystemIdFromPlatformList -ModelName $modelName `
                    -DriversFolder $DriversFolder -PlatformCache $hpPlatformCache
                if ($null -ne $systemId) {
                    WriteLog "[HP] Extracted SystemId '$systemId' from PlatformList.xml for model '$modelName'."
                }
                else {
                    WriteLog "[HP] SystemId not found for model '$modelName'."
                }
            }
            'Lenovo' {
                # Lenovo: Extract MachineType from parenthesized suffix in model name
                if ($modelName -match $parenthesizedSuffixRegex) {
                    $machineType = $matches[1].Trim().ToUpperInvariant()
                    WriteLog "[Lenovo] Extracted MachineType '$machineType' from model '$modelName'."
                }
                else {
                    WriteLog "[Lenovo] No parenthesized MachineType found in model '$modelName'."
                }
            }
        }

        # Find existing entry
        $existingEntry = $mappingList | Where-Object {
            $_.Manufacturer -eq $driver.Make -and $_.Model -eq $driver.Model
        } | Select-Object -First 1

        if ($null -ne $existingEntry) {
            $entryChanged = $false

            # Update driver path if different
            if ($existingEntry.DriverPath -ne $driver.DriverPath) {
                WriteLog "Updating driver path for '$($driver.Make) - $($driver.Model)' from '$($existingEntry.DriverPath)' to '$($driver.DriverPath)'."
                $existingEntry.DriverPath = $driver.DriverPath
                $entryChanged = $true
            }

            # Update SystemId if changed or was previously null
            if ($null -ne $systemId) {
                $existingSystemId = if ($existingEntry.PSObject.Properties['SystemId']) {
                    $existingEntry.SystemId
                }
                else { $null }
                if ($existingSystemId -ne $systemId) {
                    if (-not $existingEntry.PSObject.Properties['SystemId']) {
                        $existingEntry | Add-Member -MemberType NoteProperty -Name 'SystemId' -Value $systemId
                    }
                    else {
                        $existingEntry.SystemId = $systemId
                    }
                    $entryChanged = $true
                }
            }

            # Update MachineType if changed or was previously null
            if ($null -ne $machineType) {
                $existingMachineType = if ($existingEntry.PSObject.Properties['MachineType']) {
                    $existingEntry.MachineType
                }
                else { $null }
                if ($existingMachineType -ne $machineType) {
                    if (-not $existingEntry.PSObject.Properties['MachineType']) {
                        $existingEntry | Add-Member -MemberType NoteProperty -Name 'MachineType' -Value $machineType
                    }
                    else {
                        $existingEntry.MachineType = $machineType
                    }
                    $entryChanged = $true
                }
            }

            if ($entryChanged) {
                $updatedCount++
            }
        }
        else {
            # Add new entry with optional SystemId/MachineType
            $newEntry = [PSCustomObject]@{
                Manufacturer = $driver.Make
                Model        = $driver.Model
                DriverPath   = $driver.DriverPath
            }

            # Add SystemId property if available (Dell/HP)
            if ($null -ne $systemId) {
                $newEntry | Add-Member -MemberType NoteProperty -Name 'SystemId' -Value $systemId
            }

            # Add MachineType property if available (Lenovo)
            if ($null -ne $machineType) {
                $newEntry | Add-Member -MemberType NoteProperty -Name 'MachineType' -Value $machineType
            }

            $mappingList.Add($newEntry)
            WriteLog "Adding new mapping for '$($driver.Make) - $($driver.Model)' with path '$($driver.DriverPath)'."
            $addedCount++
        }
    }

    if ($updatedCount -gt 0 -or $addedCount -gt 0) {
        try {
            # Sort the list for consistency before saving
            $sortedList = $mappingList | Sort-Object -Property Manufacturer, Model
            $sortedList | ConvertTo-Json -Depth 5 | Set-Content -Path $mappingFilePath -Encoding UTF8
            WriteLog "Successfully saved DriverMapping.json with $addedCount new entries and $updatedCount updated entries."
        }
        catch {
            WriteLog "Error saving updated DriverMapping.json: $($_.Exception.Message)"
            throw "Failed to save driver mapping file."
        }
    }
    else {
        WriteLog "No changes needed for DriverMapping.json."
    }
}

# --------------------------------------------------------------------------
# SECTION: Driver Existence Check Function
# --------------------------------------------------------------------------
function Test-ExistingDriver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$Identifier,

        [Parameter()]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null
    )

    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $Model
    $driverRelativePath = Join-Path -Path $Make -ChildPath $Model

    # Check for WIM file first
    $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($Model).wim"
    if (Test-Path -Path $wimFilePath -PathType Leaf) {
        $status = "Already downloaded (WIM)"
        WriteLog "Driver WIM for '$Identifier' already exists at '$wimFilePath'."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $Identifier -Status $status }
        $wimRelativePath = Join-Path -Path $Make -ChildPath "$($Model).wim"
        return [PSCustomObject]@{
            Model      = $Identifier # Return original identifier
            Status     = $status
            Success    = $true
            DriverPath = $wimRelativePath
        }
    }

    # Check for existing driver folder
    if (Test-Path -Path $modelPath -PathType Container) {
        $folderSize = (Get-ChildItem -Path $modelPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($folderSize -gt 1MB) {
            $status = "Already downloaded"
            WriteLog "Drivers for '$Identifier' already exist in '$modelPath'."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $Identifier -Status $status }
            return [PSCustomObject]@{
                Model      = $Identifier # Return original identifier
                Status     = $status
                Success    = $true
                DriverPath = $driverRelativePath
            }
        }
        else {
            WriteLog "Driver folder '$modelPath' for '$Identifier' exists but is empty or very small. Re-downloading."
        }
    }

    # If neither WIM nor a valid folder exists, return null
    $null
}
function Get-LenovoPSREFToken {

    <# 
        .DESCRIPTION
        Retrieves the Lenovo PSREF token from the Edge browser's local storage.

        .NOTES

        Lenovo's PSREF site creates a cookie/token via javascript when navigating to the PSREF site. This cookie only needs
        to be retrieved once on a single machine, and every machine within the same network will be able to access the PSREF API. 

        Using Invoke-Webrequest with sessionvariable or websession doesn't work because the token is created by javascript.
        Using edge in headless mode with remote debugging enabled allows for the retrieval of the token via the DevTools protocol.

        You couldn't be more unhappy about this solution than I am, but it works.

        Why use PSREF and not catalogv2.xml? Catalogv2.xml doesn't include all models. PSREF provides an API that can be used to retrieve
        the friendly model and machine type information for both business and consumer models. Many EDU devices are deemed consumer. 

        System Update and other tools rely on the user to input machine type and model information, but finding the machine type is difficult for some.
        Our solution makes it easier to simply type the model name and you can match the machine type to the model name.

        If you have a better solution, please submit a PR or open a discussion on Github. Happy to consider alternatives. An easy way to test
        if your alternative works is to see if you can retrieve 100e, 300w, 500w, etc. These don't show up in catalogv2.xml, but they do in PSREF.
    #>

    $token = $null
    $socket = $null
    $edgeProcess = $null
    $tempProfile = $null
    $port = $null

    function Get-FreeLocalTcpPort {
        $listener = $null
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $endpoint = [System.Net.IPEndPoint]$listener.LocalEndpoint
            $endpoint.Port
        }
        finally {
            if ($null -ne $listener) {
                $listener.Stop()
            }
        }
    }

    function Get-EdgeDevToolsPageTarget {
        param(
            [Parameter(Mandatory = $true)][int]$Port,
            [int]$MaxAttempts = 20,
            [int]$DelayMilliseconds = 500,
            [string]$UrlContains
        )

        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try {
                $targets = Invoke-RestMethod -Uri "http://localhost:$Port/json" -ErrorAction Stop
                if ($null -ne $targets) {
                    if ($targets -isnot [System.Array]) { $targets = @($targets) }
                    $pageTargets = $targets | Where-Object { $_.type -eq 'page' }
                    if (-not [string]::IsNullOrWhiteSpace($UrlContains)) {
                        $pageTargets = $pageTargets | Where-Object {
                            -not [string]::IsNullOrWhiteSpace($_.url) -and $_.url -like "*$UrlContains*"
                        }
                    }

                    $target = $pageTargets | Select-Object -First 1
                    if ($null -ne $target) {
                        $target
                        return
                    }

                    WriteLog "DevTools endpoint on port $Port returned targets but no page matched the criteria (attempt $attempt of $MaxAttempts)."
                }
                else {
                    WriteLog "DevTools endpoint on port $Port returned no targets (attempt $attempt of $MaxAttempts)."
                }
            }
            catch {
                WriteLog "DevTools endpoint on port $Port not ready (attempt $attempt of $MaxAttempts). Error: $($_.Exception.Message)"
            }

            Start-Sleep -Milliseconds $DelayMilliseconds
        }

        throw "Edge DevTools endpoint on port $Port did not expose a matching page target after $MaxAttempts attempts."
    }

    try {
        $ffuDevelopmentRoot = Split-Path -Path $PSScriptRoot -Parent
        WriteLog "Derived FFUDevelopmentPath from module path: $ffuDevelopmentRoot"

        if ([string]::IsNullOrWhiteSpace($ffuDevelopmentRoot)) {
            throw "FFUDevelopmentPath could not be resolved. Unable to create Edge profile."
        }

        if (-not (Test-Path -Path $ffuDevelopmentRoot -PathType Container)) {
            throw "Resolved FFUDevelopmentPath '$ffuDevelopmentRoot' does not exist."
        }

        $tempProfile = Join-Path -Path $ffuDevelopmentRoot -ChildPath ("edge-psref-" + [guid]::NewGuid())
        WriteLog "Creating temporary Edge profile at $tempProfile."
        New-Item -ItemType Directory -Path $tempProfile -Force | Out-Null

        $edgeExe = "$Env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe"
        $uri = 'https://psref.lenovo.com'
        $port = Get-FreeLocalTcpPort
        WriteLog "Using Edge DevTools port $port for Lenovo PSREF token retrieval."

        $flags = "--headless=new --disable-gpu --remote-debugging-port=$port $uri --user-data-dir=`"$tempProfile`""
        $edgeProcess = Start-Process -FilePath $edgeExe -ArgumentList $flags -PassThru
        WriteLog "Edge process started with PID: $($edgeProcess.Id)."

        $pageTarget = Get-EdgeDevToolsPageTarget -Port $port -MaxAttempts 40 -DelayMilliseconds 500 -UrlContains 'psref.lenovo.com'
        if (-not [string]::IsNullOrWhiteSpace($pageTarget.url)) {
            WriteLog "Selected DevTools target URL: $($pageTarget.url)"
        }

        $wsUrl = $pageTarget.webSocketDebuggerUrl
        if ([string]::IsNullOrWhiteSpace($wsUrl)) {
            throw "Edge DevTools page target on port $port did not provide a WebSocket URL."
        }

        $socket = [System.Net.WebSockets.ClientWebSocket]::new()
        $socket.ConnectAsync($wsUrl, [Threading.CancellationToken]::None).Wait()

        function Send-DevToolsCommand {
            param([int]$id, [string]$method, [hashtable]$params = @{})
            $cmd = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress
            $data = [Text.Encoding]::UTF8.GetBytes($cmd)
            $socket.SendAsync([ArraySegment[byte]]$data, 'Text', $true, [Threading.CancellationToken]::None).Wait()
        }

        $buffer = New-Object byte[] 8192

        function Invoke-DevToolsValue {
            param(
                [Parameter(Mandatory = $true)][int]$CommandId,
                [Parameter(Mandatory = $true)][string]$Expression,
                [int]$MaxPolls = 25
            )

            Send-DevToolsCommand -id $CommandId -method 'Runtime.evaluate' -params @{
                expression    = $Expression
                returnByValue = $true
                awaitPromise  = $true
            }

            for ($poll = 1; $poll -le $MaxPolls; $poll++) {
                $localStream = $null
                try {
                    $localStream = New-Object System.IO.MemoryStream
                    do {
                        $segment = [ArraySegment[byte]]::new($buffer)
                        $result = $socket.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result
                        $localStream.Write($buffer, 0, $result.Count)
                    } until ($result.EndOfMessage)

                    $jsonBytes = $localStream.ToArray()
                    $jsonText = [Text.Encoding]::UTF8.GetString($jsonBytes)
                    $previewPayload = $jsonText
                    if (-not [string]::IsNullOrEmpty($previewPayload) -and $previewPayload.Length -gt 500) {
                        $previewPayload = $previewPayload.Substring(0, 500) + '...'
                    }
                    WriteLog "DevTools eval payload (cmd $CommandId, poll $poll): $previewPayload"

                    $message = $null
                    try {
                        $message = $jsonText | ConvertFrom-Json
                    }
                    catch {
                        WriteLog "Failed to parse DevTools eval payload for command id $CommandId (poll $poll): $($_.Exception.Message)"
                        continue
                    }

                    if ($message.PSObject.Properties['id'] -and $message.id -eq $CommandId) {
                        if ($message.PSObject.Properties['error']) {
                            $errorMessage = $message.error.message
                            throw "Edge DevTools reported an error for expression '$Expression': $errorMessage"
                        }

                        if ($message.PSObject.Properties['result'] -and $message.result.PSObject.Properties['result']) {
                            $innerResult = $message.result.result
                            return [PSCustomObject]@{
                                Value   = $innerResult.value
                                Type    = $innerResult.type
                                Subtype = $innerResult.subtype
                            }
                        }

                        $serializedMessage = $message | ConvertTo-Json -Compress -Depth 5
                        WriteLog "DevTools response for command id $CommandId lacked result data. Message: $serializedMessage"
                        $null
                        return
                    }

                    if ($message.PSObject.Properties['method']) {
                        WriteLog "Received DevTools event '$($message.method)' while waiting for command id $CommandId."
                    }
                    else {
                        WriteLog "Received DevTools message without id or method while waiting for command id $CommandId."
                    }
                }
                finally {
                    if ($null -ne $localStream) {
                        $localStream.Dispose()
                    }
                }
            }

            throw "No DevTools response received for command id $CommandId after $MaxPolls polls."
        }

        WriteLog "Waiting for PSREF page to initialize local storage context."
        Start-Sleep -Seconds 2

        $commandCounter = 1000
        $rawToken = $null
        $maxTokenAttempts = 12
        for ($attempt = 1; $attempt -le $maxTokenAttempts -and [string]::IsNullOrWhiteSpace($rawToken); $attempt++) {
            $commandCounter++
            $tokenResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "window.localStorage?.getItem('asut')" -MaxPolls 25
            if ($null -ne $tokenResponse -and -not [string]::IsNullOrWhiteSpace($tokenResponse.Value)) {
                $rawToken = $tokenResponse.Value
                WriteLog "DevTools response for command id $commandCounter returned token length $($rawToken.Length)."
                break
            }

            WriteLog "Lenovo PSREF token not yet available (attempt $attempt of $maxTokenAttempts)."

            $commandCounter++
            $keysResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "JSON.stringify(Object.keys(window.localStorage || {}))" -MaxPolls 10
            if ($null -ne $keysResponse -and -not [string]::IsNullOrWhiteSpace($keysResponse.Value)) {
                WriteLog "Current localStorage keys: $($keysResponse.Value)"
            }

            $commandCounter++
            $cookieResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "document.cookie" -MaxPolls 10
            if ($null -ne $cookieResponse -and -not [string]::IsNullOrWhiteSpace($cookieResponse.Value)) {
                WriteLog "document.cookie contents: $($cookieResponse.Value)"
                $cookieEntry = ($cookieResponse.Value -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -like 'asut=*' } | Select-Object -First 1
                if ($cookieEntry) {
                    $rawToken = $cookieEntry.Substring($cookieEntry.IndexOf('=') + 1)
                    WriteLog "Extracted Lenovo PSREF token from cookies with length $($rawToken.Length)."
                    break
                }
            }

            Start-Sleep -Milliseconds 750
        }

        if ([string]::IsNullOrWhiteSpace($rawToken)) {
            throw "Received empty Lenovo PSREF token from Edge DevTools after $maxTokenAttempts attempts."
        }

        $token = "X-PSREF-USER-TOKEN=$rawToken"
        WriteLog "Retrieved Lenovo PSREF token: $token"
    }
    catch {
        WriteLog "Failed to retrieve Lenovo PSREF token. Error: $($_.Exception.Message)"
        throw
    }
    finally {
        if ($null -ne $socket) {
            try {
                $socket.Dispose()
                WriteLog "Edge DevTools WebSocket disposed."
            }
            catch {
                WriteLog "Error disposing Edge DevTools WebSocket: $($_.Exception.Message)"
            }
        }

        $listeningPid = $null
        if ($null -ne $port) {
            try {
                $netstatOutput = netstat -ano -p TCP | Where-Object { $_ -match "127\.0\.0\.1:$port.*LISTENING" }
                if ($netstatOutput) {
                    $listeningPid = ($netstatOutput -split '\s+')[-1]
                    WriteLog "Found Edge process PID $listeningPid listening on port $port."
                }
                else {
                    WriteLog "No process reported as listening on port $port."
                }
            }
            catch {
                WriteLog "Could not run netstat to find listening PID for port $port. Error: $($_.Exception.Message)"
            }
        }

        $pidToKill = $null
        if ($null -ne $listeningPid) {
            $pidToKill = $listeningPid
        }
        elseif ($null -ne $edgeProcess -and -not $edgeProcess.HasExited) {
            $pidToKill = $edgeProcess.Id
            WriteLog "Falling back to initial Edge process PID $pidToKill for termination."
        }

        if ($null -ne $pidToKill) {
            try {
                taskkill /PID $pidToKill /T /F | Out-Null
                WriteLog "Issued termination command for Edge process tree with PID: $pidToKill."
            }
            catch {
                WriteLog "Failed to terminate Edge process tree with PID: $pidToKill. Error: $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "No active Edge process found to terminate."
        }

        if ($null -ne $edgeProcess) {
            try {
                $edgeProcess.WaitForExit(3000) | Out-Null
            }
            catch {
                WriteLog "Error while waiting for Edge process PID $($edgeProcess.Id) to exit: $($_.Exception.Message)"
            }
        }

        Start-Sleep -Milliseconds 250

        if (-not [string]::IsNullOrWhiteSpace($tempProfile) -and (Test-Path -Path $tempProfile -PathType Container)) {
            $maxRemoveAttempts = 5
            $originalProgressPreference = $ProgressPreference
            try {
                $ProgressPreference = 'SilentlyContinue'
                for ($removeAttempt = 1; $removeAttempt -le $maxRemoveAttempts; $removeAttempt++) {
                    try {
                        Remove-Item -Path $tempProfile -Recurse -Force -ErrorAction Stop
                        WriteLog "Removed temporary Edge profile at $tempProfile."
                        break
                    }
                    catch {
                        if ($removeAttempt -eq $maxRemoveAttempts) {
                            WriteLog "Failed to remove temporary Edge profile at $tempProfile after $maxRemoveAttempts attempts. Error: $($_.Exception.Message)"
                        }
                        else {
                            WriteLog "Temporary Edge profile still locked (attempt $removeAttempt of $maxRemoveAttempts). Retrying..."
                            Start-Sleep -Milliseconds 500
                        }
                    }
                }
            }
            finally {
                $ProgressPreference = $originalProgressPreference
            }
        }
    }

    $token
}


# --------------------------------------------------------------------------
# SECTION: Lenovo PSREF Token Caching
# --------------------------------------------------------------------------

function Set-LenovoPSREFTokenCache {
    <#
    .SYNOPSIS
        Caches a Lenovo PSREF token with DPAPI encryption.

    .DESCRIPTION
        Stores the Lenovo PSREF token in a secure cache file using Export-Clixml
        (which provides DPAPI encryption on Windows). Optionally applies NTFS
        encryption for an additional layer of protection.

    .PARAMETER FFUDevelopmentPath
        The root path of the FFU Development folder. The cache will be stored
        in .security\token-cache\ under this path.

    .PARAMETER Token
        The Lenovo PSREF token string to cache.

    .EXAMPLE
        Set-LenovoPSREFTokenCache -FFUDevelopmentPath "C:\FFUDevelopment" -Token "X-PSREF-USER-TOKEN=abc123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    $cacheDir = Join-Path -Path $FFUDevelopmentPath -ChildPath ".security\token-cache"
    $cachePath = Join-Path -Path $cacheDir -ChildPath "lenovo-psref.xml"

    # Create .security\token-cache directory if missing
    if (-not (Test-Path -Path $cacheDir -PathType Container)) {
        WriteLog "Creating token cache directory: $cacheDir"
        New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
    }

    # Store hashtable with Token and Timestamp (ISO 8601 format)
    $cacheData = @{
        Token     = $Token
        Timestamp = (Get-Date).ToString('o')
    }

    # Export with Export-Clixml (provides DPAPI encryption on Windows)
    $cacheData | Export-Clixml -Path $cachePath -Force
    WriteLog "Cached Lenovo PSREF token to $cachePath"

    # Apply NTFS encryption (try/catch, non-fatal if unavailable)
    try {
        (Get-Item -Path $cachePath).Encrypt()
        WriteLog "Applied NTFS encryption to token cache file."
    }
    catch {
        WriteLog "NTFS encryption not available for token cache: $($_.Exception.Message)"
    }
}

function Get-LenovoPSREFTokenCached {
    <#
    .SYNOPSIS
        Retrieves a Lenovo PSREF token, using cache when available.

    .DESCRIPTION
        Checks for a cached Lenovo PSREF token first. If a valid cached token
        exists (not expired), it is returned immediately, avoiding the need for
        browser automation. If the cache is expired, missing, or ForceRefresh
        is specified, the function retrieves a fresh token using Get-LenovoPSREFToken
        and caches it for future use.

    .PARAMETER FFUDevelopmentPath
        The root path of the FFU Development folder.

    .PARAMETER CacheValidMinutes
        The number of minutes a cached token remains valid. Default is 60.

    .PARAMETER ForceRefresh
        When specified, bypasses the cache and retrieves a fresh token.

    .OUTPUTS
        [string] The Lenovo PSREF token.

    .EXAMPLE
        $token = Get-LenovoPSREFTokenCached -FFUDevelopmentPath "C:\FFUDevelopment"

    .EXAMPLE
        $token = Get-LenovoPSREFTokenCached -FFUDevelopmentPath "C:\FFUDevelopment" -ForceRefresh
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter()]
        [int]$CacheValidMinutes = 60,

        [Parameter()]
        [switch]$ForceRefresh
    )

    $cacheDir = Join-Path -Path $FFUDevelopmentPath -ChildPath ".security\token-cache"
    $cachePath = Join-Path -Path $cacheDir -ChildPath "lenovo-psref.xml"

    # Check cache first (unless ForceRefresh)
    if (-not $ForceRefresh -and (Test-Path -Path $cachePath -PathType Leaf)) {
        try {
            $cached = Import-Clixml -Path $cachePath
            $cacheTimestamp = [datetime]$cached.Timestamp
            $age = (Get-Date) - $cacheTimestamp

            if ($age.TotalMinutes -lt $CacheValidMinutes) {
                WriteLog "Using cached Lenovo PSREF token (age: $([int]$age.TotalMinutes) minutes, valid for $CacheValidMinutes minutes)"
                return $cached.Token
            }
            else {
                WriteLog "Cached Lenovo PSREF token expired (age: $([int]$age.TotalMinutes) minutes > $CacheValidMinutes minutes)"
            }
        }
        catch {
            WriteLog "Failed to read token cache, will retrieve fresh token: $($_.Exception.Message)"
        }
    }
    elseif ($ForceRefresh) {
        WriteLog "Force refresh requested, bypassing token cache."
    }
    else {
        WriteLog "No cached Lenovo PSREF token found."
    }

    # Retrieve fresh token using existing browser automation
    WriteLog "Retrieving fresh Lenovo PSREF token via browser automation..."
    $token = Get-LenovoPSREFToken

    # Cache the token if retrieval succeeded
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        Set-LenovoPSREFTokenCache -FFUDevelopmentPath $FFUDevelopmentPath -Token $token
        WriteLog "Fresh token cached for $CacheValidMinutes minutes."
    }
    else {
        WriteLog "Warning: Failed to retrieve Lenovo PSREF token, cache not updated."
    }

    return $token
}

function Clear-LenovoPSREFTokenCache {
    <#
    .SYNOPSIS
        Removes the cached Lenovo PSREF token.

    .DESCRIPTION
        Deletes the cached Lenovo PSREF token file if it exists. This forces
        the next token request to perform fresh browser automation.

    .PARAMETER FFUDevelopmentPath
        The root path of the FFU Development folder.

    .EXAMPLE
        Clear-LenovoPSREFTokenCache -FFUDevelopmentPath "C:\FFUDevelopment"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    $cachePath = Join-Path -Path $FFUDevelopmentPath -ChildPath ".security\token-cache\lenovo-psref.xml"

    if (Test-Path -Path $cachePath -PathType Leaf) {
        Remove-Item -Path $cachePath -Force
        WriteLog "Removed cached Lenovo PSREF token from $cachePath"
    }
    else {
        WriteLog "No cached Lenovo PSREF token to remove."
    }
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function Compress-DriverFolderToWim, Update-DriverMappingJson, Test-ExistingDriver, Get-LenovoPSREFToken, Get-LenovoPSREFTokenCached, Set-LenovoPSREFTokenCache, Clear-LenovoPSREFTokenCache, Get-HPSystemIdFromPlatformList