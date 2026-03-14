<#
.SYNOPSIS
    FFU Builder Artifact Scanner Module

.DESCRIPTION
    Discovers, validates, and cross-checks deployment artifacts from an FFUDevelopmentPath.
    Defines the data contract (PowerShell classes and enums) consumed by Phase 47 (pipeline),
    Phase 48 (UI columns), and Phase 49 (controls).

    Public functions:
    - Get-ArtifactMetadata     : Extract FFU metadata via DISM with filename fallback
    - Find-FFUArtifacts        : Discover all 7 artifact types from FFUDevelopmentPath
    - Test-ArtifactCompatibility : Cross-validate artifact compatibility (arch mismatch)
    - New-ArtifactManifest     : Factory function for cross-scope ArtifactManifest instantiation
    - New-ArtifactResult       : Factory function for cross-scope ArtifactResult instantiation

.NOTES
    Module: FFU.ArtifactScanner
    Version: 1.0.0

    ThreadJob compatibility:
    - Uses [DateTime]::Now instead of Get-Date (known ThreadJob issue, FFU.Common v0.0.9)
    - Uses safe WriteLog pattern instead of Write-Warning (v0.0.11)
    - Uses [Console]::Error.WriteLine() in module init catch blocks

    Class cross-scope access (Pitfall 4 from 46-RESEARCH.md):
    - PowerShell module classes are NOT exported to caller's scope
    - Use New-ArtifactManifest and New-ArtifactResult factory functions
    - Accept [object] not [ArtifactResult] in cross-scope function parameters
#>

#Requires -Version 7.0

# Module-scope path variables
$script:ModuleRoot  = $PSScriptRoot
$script:ClassesPath = Join-Path $script:ModuleRoot 'Classes'

#region Load Classes (enums first, then classes that use them)

. (Join-Path $script:ClassesPath 'ArtifactScanner.Classes.ps1')

#endregion

#region Module Initialization

# Verify WriteLog function is available from FFU.Core.
# Uses $function: drive instead of Get-Command for ThreadJob compatibility.
if (-not $function:WriteLog) {
    # Fallback: simple console writer when FFU.Core is not loaded
    # Uses [Console]::WriteLine instead of Write-Host for ThreadJob compatibility
    function script:WriteLog {
        param([string]$Message)
        [Console]::WriteLine("[FFU.ArtifactScanner] $Message")
    }
}

#endregion

#region Private Helper Functions

<#
.SYNOPSIS
    Maps a DISM architecture integer to a canonical architecture string.

.DESCRIPTION
    DISM Get-WindowsImage returns Architecture as an integer matching Windows PE constants:
    0 = x86, 9 = x64/amd64, 12 = arm64. This private function converts that integer
    to the string representation used throughout FFU Builder.

.PARAMETER ArchInt
    The DISM architecture integer (0, 9, or 12).

.OUTPUTS
    [string] - 'x86', 'x64', 'arm64', or 'Unknown(<int>)'
#>
function ConvertTo-ArchitectureString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $ArchInt
    )

    switch ($ArchInt) {
        0  { return 'x86' }
        9  { return 'x64' }
        12 { return 'arm64' }
        default { return "Unknown($ArchInt)" }
    }
}

<#
.SYNOPSIS
    Parses architecture and version hints from an FFU filename.

.DESCRIPTION
    Used as fallback when DISM metadata extraction fails or WIMMount is unavailable.
    Attempts to extract architecture (x64, arm64, x86) and version string (e.g., 23H2)
    from the FFU filename using regex patterns.

.PARAMETER FileName
    The FFU filename (not full path) to parse.

.OUTPUTS
    [hashtable] with keys: Architecture, VersionHint
#>
function Get-MetadataFromFilename {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $FileName
    )

    $result = @{
        Architecture = 'Unknown'
        VersionHint  = ''
    }

    # Architecture extraction - try common patterns
    # Patterns: Windows11_23H2_x64_Pro.ffu, arm64, x86
    # Note: \b word boundary fails with underscores (which are word chars), so use
    # non-alphabetic delimiter anchors instead: [^a-z] or start/end of filename
    if ($FileName -imatch '(?:^|[^a-z])(arm64)(?:[^a-z]|$)') {
        $result.Architecture = 'arm64'
    }
    elseif ($FileName -imatch '(?:^|[^a-z])(x64|amd64)(?:[^a-z]|$)') {
        $result.Architecture = 'x64'
    }
    elseif ($FileName -imatch '(?:^|[^a-z])(x86|i386)(?:[^a-z]|$)') {
        $result.Architecture = 'x86'
    }

    # Version hint extraction - look for Windows release patterns
    if ($FileName -match '\b(2[0-9]H[12])\b') {
        $result.VersionHint = $Matches[1]
    }

    return $result
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Extracts metadata from an FFU file using DISM, with filename-parsing fallback.

.DESCRIPTION
    Primary path: Calls Get-WindowsImage on the FFU file via DISM module to extract
    Windows version, SKU, architecture, and image name. Requires WIMMount filter driver
    to be loaded (gate via WimMountAvailable parameter).

    Fallback path: When DISM fails or WimMountAvailable is false, parses the FFU filename
    to extract architecture and version hints. Sets MetadataSource='Filename' and populates
    ErrorMessage with the DISM failure reason.

.PARAMETER FFUPath
    Full path to the FFU file.

.PARAMETER WimMountAvailable
    Whether the WIMMount filter driver is available. When false, skips DISM and uses
    filename fallback immediately. Default: true.

.OUTPUTS
    [FFUMetadata] - Always returns an FFUMetadata object. Check MetadataSource to
    determine whether data came from DISM or filename parsing.

.EXAMPLE
    $meta = Get-ArtifactMetadata -FFUPath 'C:\FFUDevelopment\FFU\Windows11.ffu'
    Write-Host "Windows $($meta.WindowsVersion) $($meta.Architecture) $($meta.WindowsSKU)"
#>
function Get-ArtifactMetadata {
    [CmdletBinding()]
    [OutputType([FFUMetadata])]
    param(
        [Parameter(Mandatory)]
        [string] $FFUPath,

        [Parameter()]
        [bool] $WimMountAvailable = $true
    )

    $metadata = [FFUMetadata]::new()
    $ffuFileName = [System.IO.Path]::GetFileName($FFUPath)

    # Get file LastWriteTime for BuildDate (using .NET directly for ThreadJob compatibility)
    try {
        $fileInfo = [System.IO.FileInfo]::new($FFUPath)
        if ($fileInfo.Exists) {
            $metadata.BuildDate = $fileInfo.LastWriteTime
        }
    }
    catch {
        # Non-critical: BuildDate will remain default
        $msg = "ArtifactScanner: Could not read LastWriteTime for '$ffuFileName': $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }
    }

    # --- DISM extraction path ---
    if ($WimMountAvailable) {
        try {
            Import-Module DISM -ErrorAction Stop
            $imageInfo = Get-WindowsImage -ImagePath $FFUPath -Index 1 -ErrorAction Stop

            $metadata.WindowsVersion  = $imageInfo.Version
            $metadata.WindowsSKU      = $imageInfo.EditionId
            $metadata.Architecture    = ConvertTo-ArchitectureString -ArchInt $imageInfo.Architecture
            $metadata.ImageName       = $imageInfo.ImageName
            $metadata.MetadataSource  = 'DISM'

            $msg = "ArtifactScanner: DISM extracted metadata for '$ffuFileName' — $($metadata.Architecture) $($metadata.WindowsSKU) $($metadata.WindowsVersion)"
            if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }

            return $metadata
        }
        catch {
            # DISM failed — fall through to filename parsing
            $dismError = $_.Exception.Message
            $metadata.ErrorMessage = "DISM failed: $dismError"

            $msg = "ArtifactScanner: DISM extraction failed for '$ffuFileName' — $dismError. Falling back to filename parsing."
            if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }
        }
    }
    else {
        $metadata.ErrorMessage = 'WIMMount filter driver unavailable; skipped DISM extraction'
        $msg = "ArtifactScanner: WIMMount unavailable — using filename parsing for '$ffuFileName'"
        if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }
    }

    # --- Filename parsing fallback ---
    $parsed = Get-MetadataFromFilename -FileName $ffuFileName
    $metadata.Architecture   = $parsed.Architecture
    $metadata.MetadataSource = 'Filename'

    # Populate partial version/SKU from filename if possible
    if ($parsed.VersionHint) {
        $metadata.WindowsVersion = $parsed.VersionHint
    }

    return $metadata
}

<#
.SYNOPSIS
    Discovers all deployable artifacts from an FFUDevelopmentPath.

.DESCRIPTION
    Scans for all 7 artifact types: FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot,
    AppsISO. Always scans all types regardless of config flags. Missing optional artifacts
    are reported as ArtifactStatus.Missing (not errors).

    Returns a single [ArtifactManifest] object with per-artifact results, cross-artifact
    compatibility warnings, and readiness summary (FoundCount, MissingCount, IsReady).

.PARAMETER FFUDevelopmentPath
    Root development path containing all artifact subfolders (FFU\, Drivers\, PPKG\, etc.)

.OUTPUTS
    [ArtifactManifest]
#>
function Find-FFUArtifacts {
    [CmdletBinding()]
    [OutputType([ArtifactManifest])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FFUDevelopmentPath
    )

    $msg = "ArtifactScanner: Find-FFUArtifacts scanning '$FFUDevelopmentPath'"
    if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }

    # --- WIMMount gate ---
    # Call once at start; cache result for all FFU metadata extractions.
    # Function names with hyphens cannot use $function:Name drive syntax directly;
    # use Get-Command within try/catch as a safe check (ThreadJob compatible per context).
    $wimMountAvailable = $false
    $wimMountFnAvailable = $false
    try {
        $null = Get-Command -Name 'Test-FFUWimMount' -ErrorAction Stop
        $wimMountFnAvailable = $true
    }
    catch {
        # Test-FFUWimMount not loaded — expected when FFU.Preflight is not imported
    }

    if ($wimMountFnAvailable) {
        try {
            $wimResult = Test-FFUWimMount -AttemptRemediation:$true
            $wimMountAvailable = ($wimResult.Status -eq 'Passed')
        }
        catch {
            $wmMsg = "ArtifactScanner: Test-FFUWimMount threw during WIMMount gate: $($_.Exception.Message). Defaulting WIMMount to unavailable."
            if ($function:WriteLog) { WriteLog $wmMsg } else { Write-Verbose $wmMsg }
        }
    }
    else {
        $wmMsg = 'ArtifactScanner: Test-FFUWimMount not available (FFU.Preflight not loaded). WIMMount defaulting to unavailable.'
        if ($function:WriteLog) { WriteLog $wmMsg } else { Write-Verbose $wmMsg }
    }

    # --- Create manifest ---
    $manifest               = [ArtifactManifest]::new()
    $manifest.BasePath      = $FFUDevelopmentPath
    $manifest.ScanTimestamp = [DateTime]::Now
    $manifest.FFUFiles      = @()
    $manifest.PPKGFiles     = @()
    $manifest.UnattendFiles = @()
    $manifest.AutopilotFiles = @()
    $manifest.Warnings      = @()

    # --- Private scanner: FFU files ---
    try {
        $ffuDir   = Join-Path $FFUDevelopmentPath 'FFU'
        $ffuFiles = Get-ChildItem -Path $ffuDir -Filter '*.ffu' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending

        if ($ffuFiles -and @($ffuFiles).Count -gt 0) {
            $ffuResults = @()
            $isFirst    = $true
            foreach ($file in $ffuFiles) {
                $ffuResult              = [ArtifactResult]::new()
                $ffuResult.ArtifactType = [ArtifactType]::FFU
                $ffuResult.Status       = [ArtifactStatus]::Found
                $ffuResult.FilePath     = $file.FullName
                $ffuResult.FileSizeBytes = $file.Length
                $ffuResult.LastWriteTime = $file.LastWriteTime
                $ffuResult.AgeDays      = [int][Math]::Floor(([DateTime]::Now - $file.LastWriteTime).TotalDays)
                $ffuResult.IsPrimary    = $isFirst
                $isFirst                = $false

                # Call Get-ArtifactMetadata for each FFU — wrapped in try/catch for graceful degradation
                try {
                    $ffuResult.Metadata = Get-ArtifactMetadata -FFUPath $file.FullName -WimMountAvailable $wimMountAvailable
                }
                catch {
                    $metaMsg = "ArtifactScanner: Get-ArtifactMetadata failed for '$($file.Name)': $($_.Exception.Message)"
                    if ($function:WriteLog) { WriteLog $metaMsg } else { Write-Verbose $metaMsg }
                    # Metadata remains null — result still valid
                }
                $ffuResults += $ffuResult
            }
            $manifest.FFUFiles = $ffuResults
        }
        else {
            # No .ffu files — return single Missing result
            $missing              = [ArtifactResult]::new()
            $missing.ArtifactType = [ArtifactType]::FFU
            $missing.Status       = [ArtifactStatus]::Missing
            $manifest.FFUFiles    = @($missing)
        }
    }
    catch {
        $errMsg = "ArtifactScanner: Error scanning FFU folder: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $errMsg } else { Write-Verbose $errMsg }
        $errResult              = [ArtifactResult]::new()
        $errResult.ArtifactType = [ArtifactType]::FFU
        $errResult.Status       = [ArtifactStatus]::Error
        $errResult.ErrorMessage = $_.Exception.Message
        $manifest.FFUFiles      = @($errResult)
    }

    # --- Private scanner: Deploy ISO ---
    try {
        $isoResult              = [ArtifactResult]::new()
        $isoResult.ArtifactType = [ArtifactType]::DeployISO
        $isoResult.Status       = [ArtifactStatus]::Missing

        $isoNames = @('WinPE_FFU_Deploy_x64.iso', 'WinPE_FFU_Deploy_arm64.iso')
        foreach ($isoName in $isoNames) {
            $isoPath = Join-Path $FFUDevelopmentPath $isoName
            $isoFile = [System.IO.FileInfo]::new($isoPath)
            if ($isoFile.Exists) {
                $isoResult.Status        = [ArtifactStatus]::Found
                $isoResult.FilePath      = $isoFile.FullName
                $isoResult.FileSizeBytes = $isoFile.Length
                $isoResult.LastWriteTime = $isoFile.LastWriteTime
                $isoResult.AgeDays       = [int][Math]::Floor(([DateTime]::Now - $isoFile.LastWriteTime).TotalDays)
                break
            }
        }
        $manifest.DeployISO = $isoResult
    }
    catch {
        $errMsg = "ArtifactScanner: Error scanning Deploy ISO: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $errMsg } else { Write-Verbose $errMsg }
        $errResult              = [ArtifactResult]::new()
        $errResult.ArtifactType = [ArtifactType]::DeployISO
        $errResult.Status       = [ArtifactStatus]::Error
        $errResult.ErrorMessage = $_.Exception.Message
        $manifest.DeployISO     = $errResult
    }

    # --- Private scanner: Drivers folder ---
    try {
        $driversResult              = [ArtifactResult]::new()
        $driversResult.ArtifactType = [ArtifactType]::Drivers

        $driversDir = Join-Path $FFUDevelopmentPath 'Drivers'
        $driverDirInfo = [System.IO.DirectoryInfo]::new($driversDir)
        if ($driverDirInfo.Exists) {
            $driverFiles = Get-ChildItem -Path $driversDir -Recurse -File -ErrorAction SilentlyContinue
            if ($driverFiles -and @($driverFiles).Count -gt 0) {
                $driversResult.Status        = [ArtifactStatus]::Found
                $driversResult.FileCount     = @($driverFiles).Count
                $driversResult.TotalSizeBytes = ($driverFiles | Measure-Object -Property Length -Sum).Sum
                # AgeDays from newest file LastWriteTime, not folder timestamp (per Pitfall 6)
                $newestFile = $driverFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                $driversResult.AgeDays = [int][Math]::Floor(([DateTime]::Now - $newestFile.LastWriteTime).TotalDays)
                $driversResult.FilePath = $driversDir
            }
            else {
                $driversResult.Status = [ArtifactStatus]::Missing
            }
        }
        else {
            $driversResult.Status = [ArtifactStatus]::Missing
        }
        $manifest.Drivers = $driversResult
    }
    catch {
        $errMsg = "ArtifactScanner: Error scanning Drivers folder: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $errMsg } else { Write-Verbose $errMsg }
        $errResult              = [ArtifactResult]::new()
        $errResult.ArtifactType = [ArtifactType]::Drivers
        $errResult.Status       = [ArtifactStatus]::Error
        $errResult.ErrorMessage = $_.Exception.Message
        $manifest.Drivers       = $errResult
    }

    # --- Private scanner: PPKG files ---
    try {
        $ppkgDir   = Join-Path $FFUDevelopmentPath 'PPKG'
        $ppkgFiles = Get-ChildItem -Path $ppkgDir -Filter '*.ppkg' -ErrorAction SilentlyContinue

        if ($ppkgFiles -and @($ppkgFiles).Count -gt 0) {
            $ppkgResults = @()
            foreach ($file in $ppkgFiles) {
                $ppkgResult              = [ArtifactResult]::new()
                $ppkgResult.ArtifactType = [ArtifactType]::PPKG
                $ppkgResult.Status       = [ArtifactStatus]::Found
                $ppkgResult.FilePath     = $file.FullName
                $ppkgResult.FileSizeBytes = $file.Length
                $ppkgResult.LastWriteTime = $file.LastWriteTime
                $ppkgResult.AgeDays      = [int][Math]::Floor(([DateTime]::Now - $file.LastWriteTime).TotalDays)
                $ppkgResults += $ppkgResult
            }
            $manifest.PPKGFiles = $ppkgResults
        }
        else {
            $missing              = [ArtifactResult]::new()
            $missing.ArtifactType = [ArtifactType]::PPKG
            $missing.Status       = [ArtifactStatus]::Missing
            $manifest.PPKGFiles   = @($missing)
        }
    }
    catch {
        $errMsg = "ArtifactScanner: Error scanning PPKG folder: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $errMsg } else { Write-Verbose $errMsg }
        $errResult              = [ArtifactResult]::new()
        $errResult.ArtifactType = [ArtifactType]::PPKG
        $errResult.Status       = [ArtifactStatus]::Error
        $errResult.ErrorMessage = $_.Exception.Message
        $manifest.PPKGFiles     = @($errResult)
    }

    # --- Private scanner: Unattend files ---
    # Scans specifically for unattend_x64.xml and unattend_arm64.xml per BuildFFUVM.ps1 lines 1504-1515
    try {
        $unattendDir   = Join-Path $FFUDevelopmentPath 'Unattend'
        $unattendNames = @('unattend_x64.xml', 'unattend_arm64.xml')
        $unattendResults = @()

        foreach ($name in $unattendNames) {
            $unattendPath = Join-Path $unattendDir $name
            $unattendFile = [System.IO.FileInfo]::new($unattendPath)
            if ($unattendFile.Exists) {
                $uResult              = [ArtifactResult]::new()
                $uResult.ArtifactType = [ArtifactType]::Unattend
                $uResult.Status       = [ArtifactStatus]::Found
                $uResult.FilePath     = $unattendFile.FullName
                $uResult.FileSizeBytes = $unattendFile.Length
                $uResult.LastWriteTime = $unattendFile.LastWriteTime
                $uResult.AgeDays      = [int][Math]::Floor(([DateTime]::Now - $unattendFile.LastWriteTime).TotalDays)
                $unattendResults     += $uResult
            }
        }

        if ($unattendResults.Count -eq 0) {
            $missing              = [ArtifactResult]::new()
            $missing.ArtifactType = [ArtifactType]::Unattend
            $missing.Status       = [ArtifactStatus]::Missing
            $manifest.UnattendFiles = @($missing)
        }
        else {
            $manifest.UnattendFiles = $unattendResults
        }
    }
    catch {
        $errMsg = "ArtifactScanner: Error scanning Unattend folder: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $errMsg } else { Write-Verbose $errMsg }
        $errResult              = [ArtifactResult]::new()
        $errResult.ArtifactType = [ArtifactType]::Unattend
        $errResult.Status       = [ArtifactStatus]::Error
        $errResult.ErrorMessage = $_.Exception.Message
        $manifest.UnattendFiles = @($errResult)
    }

    # --- Private scanner: Autopilot files ---
    # Scans for *.json in Autopilot folder per BuildFFUVM.ps1 line 2107
    try {
        $autopilotDir   = Join-Path $FFUDevelopmentPath 'Autopilot'
        $autopilotFiles = Get-ChildItem -Path $autopilotDir -Filter '*.json' -ErrorAction SilentlyContinue

        if ($autopilotFiles -and @($autopilotFiles).Count -gt 0) {
            $autopilotResults = @()
            foreach ($file in $autopilotFiles) {
                $aResult              = [ArtifactResult]::new()
                $aResult.ArtifactType = [ArtifactType]::Autopilot
                $aResult.Status       = [ArtifactStatus]::Found
                $aResult.FilePath     = $file.FullName
                $aResult.FileSizeBytes = $file.Length
                $aResult.LastWriteTime = $file.LastWriteTime
                $aResult.AgeDays      = [int][Math]::Floor(([DateTime]::Now - $file.LastWriteTime).TotalDays)
                $autopilotResults    += $aResult
            }
            $manifest.AutopilotFiles = $autopilotResults
        }
        else {
            $missing               = [ArtifactResult]::new()
            $missing.ArtifactType  = [ArtifactType]::Autopilot
            $missing.Status        = [ArtifactStatus]::Missing
            $manifest.AutopilotFiles = @($missing)
        }
    }
    catch {
        $errMsg = "ArtifactScanner: Error scanning Autopilot folder: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $errMsg } else { Write-Verbose $errMsg }
        $errResult               = [ArtifactResult]::new()
        $errResult.ArtifactType  = [ArtifactType]::Autopilot
        $errResult.Status        = [ArtifactStatus]::Error
        $errResult.ErrorMessage  = $_.Exception.Message
        $manifest.AutopilotFiles = @($errResult)
    }

    # --- Private scanner: Apps.iso ---
    try {
        $appsIsoPath   = Join-Path $FFUDevelopmentPath 'Apps' | Join-Path -ChildPath 'Apps.iso'
        $appsIsoFile   = [System.IO.FileInfo]::new($appsIsoPath)
        $appsResult              = [ArtifactResult]::new()
        $appsResult.ArtifactType = [ArtifactType]::AppsISO

        if ($appsIsoFile.Exists) {
            $appsResult.Status        = [ArtifactStatus]::Found
            $appsResult.FilePath      = $appsIsoFile.FullName
            $appsResult.FileSizeBytes = $appsIsoFile.Length
            $appsResult.LastWriteTime = $appsIsoFile.LastWriteTime
            $appsResult.AgeDays       = [int][Math]::Floor(([DateTime]::Now - $appsIsoFile.LastWriteTime).TotalDays)
        }
        else {
            $appsResult.Status = [ArtifactStatus]::Missing
        }
        $manifest.AppsISO = $appsResult
    }
    catch {
        $errMsg = "ArtifactScanner: Error scanning Apps.iso: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $errMsg } else { Write-Verbose $errMsg }
        $errResult              = [ArtifactResult]::new()
        $errResult.ArtifactType = [ArtifactType]::AppsISO
        $errResult.Status       = [ArtifactStatus]::Error
        $errResult.ErrorMessage = $_.Exception.Message
        $manifest.AppsISO       = $errResult
    }

    # --- Readiness summary ---
    # Collect all results into a flat list for counting
    $allResults = @()
    $allResults += $manifest.FFUFiles
    if ($null -ne $manifest.DeployISO)  { $allResults += $manifest.DeployISO }
    if ($null -ne $manifest.Drivers)    { $allResults += $manifest.Drivers }
    $allResults += $manifest.PPKGFiles
    $allResults += $manifest.UnattendFiles
    $allResults += $manifest.AutopilotFiles
    if ($null -ne $manifest.AppsISO)    { $allResults += $manifest.AppsISO }

    $manifest.FoundCount   = ($allResults | Where-Object { $_.Status.ToString() -eq 'Found' }).Count
    $manifest.MissingCount = ($allResults | Where-Object { $_.Status.ToString() -eq 'Missing' }).Count
    $manifest.ErrorCount   = ($allResults | Where-Object { $_.Status.ToString() -eq 'Error' }).Count

    # IsReady: at least one FFU found AND DeployISO found AND no errors
    $ffuFound    = $manifest.FFUFiles | Where-Object { $_.Status.ToString() -eq 'Found' }
    $isoFound    = $manifest.DeployISO -and ($manifest.DeployISO.Status.ToString() -eq 'Found')
    $manifest.IsReady = ($null -ne $ffuFound -and @($ffuFound).Count -gt 0 -and $isoFound -and $manifest.ErrorCount -eq 0)

    # --- Automatic compatibility check ---
    try {
        $rawWarnings = Test-ArtifactCompatibility -Manifest $manifest
        # Filter nulls and use explicit array to prevent @($null) coercion issue with typed properties.
        # When Where-Object has nothing to return it produces $null; wrap in @() to get empty array.
        $filteredWarnings = @($rawWarnings | Where-Object { $null -ne $_ })
        $manifest.Warnings = $filteredWarnings
    }
    catch {
        $cwMsg = "ArtifactScanner: Test-ArtifactCompatibility threw: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $cwMsg } else { Write-Verbose $cwMsg }
        $manifest.Warnings = @()
    }

    $summaryMsg = "ArtifactScanner: Scan complete — Found=$($manifest.FoundCount) Missing=$($manifest.MissingCount) Errors=$($manifest.ErrorCount) IsReady=$($manifest.IsReady)"
    if ($function:WriteLog) { WriteLog $summaryMsg } else { Write-Verbose $summaryMsg }

    return $manifest
}

<#
.SYNOPSIS
    Validates cross-artifact compatibility (architecture mismatch warnings).

.DESCRIPTION
    Checks FFU architecture against Deploy ISO architecture. Returns a warning when
    architectures mismatch — the scanner informs but does not gatekeep (mismatch is
    a warning, not a blocking error).

    IMPORTANT: This function is a stub in Plan 46. Full implementation in Plan 46-02.

.PARAMETER Manifest
    The [ArtifactManifest] returned by Find-FFUArtifacts.

.OUTPUTS
    [CompatibilityWarning[]] - Empty array if compatible, warning objects if mismatches found.
#>
function Test-ArtifactCompatibility {
    [CmdletBinding()]
    [OutputType([CompatibilityWarning[]])]
    param(
        [Parameter(Mandatory)]
        [object] $Manifest   # Use [object] to avoid cross-scope type resolution issues (Pitfall 4)
    )

    [CompatibilityWarning[]]$warnings = @()

    # --- Extract FFU architecture ---
    # Find primary FFU result with metadata, or first with metadata
    $ffuArch = $null
    try {
        if ($null -ne $Manifest.FFUFiles -and @($Manifest.FFUFiles).Count -gt 0) {
            $primaryFfu = $Manifest.FFUFiles | Where-Object { $_.IsPrimary -eq $true -and $null -ne $_.Metadata -and $_.Metadata.Architecture -ne '' -and $_.Metadata.Architecture -ne 'Unknown' } | Select-Object -First 1
            if ($null -eq $primaryFfu) {
                $primaryFfu = $Manifest.FFUFiles | Where-Object { $null -ne $_.Metadata -and $_.Metadata.Architecture -ne '' -and $_.Metadata.Architecture -ne 'Unknown' } | Select-Object -First 1
            }
            if ($null -ne $primaryFfu -and $null -ne $primaryFfu.Metadata) {
                $ffuArch = $primaryFfu.Metadata.Architecture
            }
        }
    }
    catch {
        $msg = "ArtifactScanner: Test-ArtifactCompatibility could not read FFU architecture: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }
    }

    # --- Extract Deploy ISO architecture from filename ---
    $isoArch = $null
    try {
        if ($null -ne $Manifest.DeployISO -and $Manifest.DeployISO.Status.ToString() -eq 'Found' -and -not [string]::IsNullOrEmpty($Manifest.DeployISO.FilePath)) {
            $isoFileName = [System.IO.Path]::GetFileName($Manifest.DeployISO.FilePath)
            # Pattern: WinPE_FFU_Deploy_x64.iso or WinPE_FFU_Deploy_arm64.iso
            if ($isoFileName -match 'WinPE_FFU_Deploy_(.+)\.iso') {
                $isoArch = $Matches[1]
            }
        }
    }
    catch {
        $msg = "ArtifactScanner: Test-ArtifactCompatibility could not read ISO architecture: $($_.Exception.Message)"
        if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }
    }

    # --- Compare architectures ---
    if (-not [string]::IsNullOrEmpty($ffuArch) -and -not [string]::IsNullOrEmpty($isoArch)) {
        if ($ffuArch -ne $isoArch) {
            $warning = [CompatibilityWarning]::new()
            $warning.Severity          = 'Warning'
            $warning.Message           = "FFU architecture ($ffuArch) does not match Deploy ISO architecture ($isoArch). Deployment may fail if architectures are incompatible."
            $warning.AffectedArtifacts = @('FFU', 'DeployISO')
            $warnings += $warning

            $warnMsg = "ArtifactScanner: Architecture mismatch — FFU=$ffuArch ISO=$isoArch"
            if ($function:WriteLog) { WriteLog $warnMsg } else { Write-Verbose $warnMsg }
        }
    }

    return $warnings
}

#endregion

#region Factory Functions (for cross-scope class instantiation)

<#
.SYNOPSIS
    Creates a new ArtifactManifest instance with ScanTimestamp initialized.

.DESCRIPTION
    Factory function for creating [ArtifactManifest] objects from outside the module scope.
    PowerShell module classes are not exported to the caller's scope, so direct use of
    [ArtifactManifest]::new() fails in caller code. Use this function instead.

    See: Pitfall 4 in 46-RESEARCH.md; FFU.Hypervisor v1.1.4 New-VMConfiguration pattern.

.OUTPUTS
    [ArtifactManifest] with ScanTimestamp set to [DateTime]::Now

.EXAMPLE
    $manifest = New-ArtifactManifest
    $manifest.BasePath = 'C:\FFUDevelopment'
#>
function New-ArtifactManifest {
    [CmdletBinding()]
    [OutputType([ArtifactManifest])]
    param()

    $manifest = [ArtifactManifest]::new()
    $manifest.ScanTimestamp  = [DateTime]::Now
    $manifest.FFUFiles       = @()
    $manifest.PPKGFiles      = @()
    $manifest.UnattendFiles  = @()
    $manifest.AutopilotFiles = @()
    $manifest.Warnings       = @()
    return $manifest
}

<#
.SYNOPSIS
    Creates a new ArtifactResult instance for the specified artifact type.

.DESCRIPTION
    Factory function for creating [ArtifactResult] objects from outside the module scope.
    PowerShell module classes are not exported to the caller's scope, so direct use of
    [ArtifactResult]::new() fails in caller code. Use this function instead.

    The returned instance has its Files list pre-initialized via the ArtifactResult()
    constructor.

    See: Pitfall 4 in 46-RESEARCH.md; FFU.Hypervisor v1.1.4 New-VMConfiguration pattern.

.PARAMETER ArtifactType
    The type of artifact this result represents (FFU, DeployISO, Drivers, etc.)

.OUTPUTS
    [ArtifactResult] with ArtifactType set and Files list initialized

.EXAMPLE
    $result = New-ArtifactResult -ArtifactType FFU
    $result.Status = [ArtifactStatus]::Found
#>
function New-ArtifactResult {
    [CmdletBinding()]
    [OutputType([ArtifactResult])]
    param(
        [Parameter(Mandatory)]
        [ArtifactType] $ArtifactType
    )

    $result = [ArtifactResult]::new()
    $result.ArtifactType = $ArtifactType
    return $result
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-ArtifactMetadata',
    'Find-FFUArtifacts',
    'Test-ArtifactCompatibility',
    'New-ArtifactManifest',
    'New-ArtifactResult'
)
