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

    IMPORTANT: This function is a stub in Plan 46. Full implementation in Plan 46-02.

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
        [string] $FFUDevelopmentPath
    )

    $msg = "ArtifactScanner: Find-FFUArtifacts called for '$FFUDevelopmentPath' — stub implementation (Plan 46-02)"
    if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }

    # Stub: return empty manifest. Full implementation in Plan 46-02.
    $manifest = [ArtifactManifest]::new()
    $manifest.BasePath      = $FFUDevelopmentPath
    $manifest.ScanTimestamp = [DateTime]::Now
    $manifest.FFUFiles      = @()
    $manifest.PPKGFiles     = @()
    $manifest.UnattendFiles = @()
    $manifest.AutopilotFiles = @()
    $manifest.Warnings      = @()

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
        [object] $Manifest   # Use [object] to avoid cross-scope type resolution issues
    )

    $msg = 'ArtifactScanner: Test-ArtifactCompatibility called — stub implementation (Plan 46-02)'
    if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }

    # Stub: return empty array. Full implementation in Plan 46-02.
    return @()
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
