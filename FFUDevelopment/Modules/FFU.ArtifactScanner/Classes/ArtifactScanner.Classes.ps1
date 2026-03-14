<#
.SYNOPSIS
    Data contract classes and enums for FFU.ArtifactScanner module.

.DESCRIPTION
    Defines the typed data contract consumed by Phase 47 (pipeline), Phase 48 (UI columns),
    and Phase 49 (controls). All classes follow the PowerShell class pattern established
    in FFU.Hypervisor/Classes/VMConfiguration.ps1.

.NOTES
    Module: FFU.ArtifactScanner
    Version: 1.0.0

    PowerShell classes are dot-sourced by FFU.ArtifactScanner.psm1 during module load.
    Because PowerShell module classes are not exported to the caller's scope, factory
    functions (New-ArtifactManifest, New-ArtifactResult) are provided for cross-scope
    class instantiation. See Pitfall 4 in 46-RESEARCH.md.
#>

#region Enums

enum ArtifactStatus {
    Found
    Missing
    Error
    Degraded
}

enum ArtifactType {
    FFU
    DeployISO
    Drivers
    PPKG
    Unattend
    Autopilot
    AppsISO
}

#endregion

#region Data Classes

class ArtifactFileEntry {
    [string]   $FilePath
    [long]     $FileSizeBytes
    [DateTime] $LastWriteTime
}

class FFUMetadata {
    [string]   $WindowsVersion
    [string]   $WindowsSKU
    [string]   $Architecture
    [string]   $ImageName
    [DateTime] $BuildDate
    [string]   $MetadataSource   # 'DISM' or 'Filename'
    [string]   $ErrorMessage     # Populated on DISM failure
}

class ArtifactResult {
    [ArtifactType]   $ArtifactType
    [ArtifactStatus] $Status
    [string]         $ErrorMessage
    [int]            $AgeDays

    # Single-file artifact properties
    [string]         $FilePath
    [long]           $FileSizeBytes
    [DateTime]       $LastWriteTime

    # Multi-file artifact properties (PPKG, Autopilot, Unattend)
    [System.Collections.Generic.List[ArtifactFileEntry]] $Files
    [int]            $FileCount
    [long]           $TotalSizeBytes

    # FFU-specific properties
    [bool]           $IsPrimary    # True for the newest FFU when multiple exist
    [FFUMetadata]    $Metadata

    # Constructor: initializes the Files list so callers can always call .Add()
    ArtifactResult() {
        $this.Files = [System.Collections.Generic.List[ArtifactFileEntry]]::new()
    }
}

class CompatibilityWarning {
    [string]   $Severity           # 'Warning' — mismatch is informational, not blocking
    [string]   $Message
    [string[]] $AffectedArtifacts
}

class ArtifactManifest {
    [string]   $BasePath
    [DateTime] $ScanTimestamp

    # Per-artifact results
    [ArtifactResult[]] $FFUFiles
    [ArtifactResult]   $DeployISO
    [ArtifactResult]   $Drivers
    [ArtifactResult[]] $PPKGFiles
    [ArtifactResult[]] $UnattendFiles
    [ArtifactResult[]] $AutopilotFiles
    [ArtifactResult]   $AppsISO

    # Cross-artifact compatibility warnings
    [CompatibilityWarning[]] $Warnings

    # Readiness summary
    [int]  $FoundCount
    [int]  $MissingCount
    [int]  $ErrorCount
    [bool] $IsReady    # True if FFU + DeployISO found, no errors
}

#endregion
