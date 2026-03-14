@{
    # Module manifest for FFU.ArtifactScanner
    # Artifact discovery, validation, and cross-compatibility checking for FFU Builder USB Mode

    # Script module file associated with this manifest
    RootModule = 'FFU.ArtifactScanner.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # Unique identifier for this module
    GUID = 'b1997a2f-2858-4b6d-a486-1ca8e77f142c'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'FFU Builder'

    # Copyright statement
    Copyright = '(c) 2026 FFU Builder Team. MIT License.'

    # Description of the functionality provided by this module
    Description = 'FFU artifact discovery, validation, and cross-compatibility checking for USB Mode. Defines the typed data contract (ArtifactManifest, ArtifactResult, FFUMetadata) consumed by Phase 47 pipeline, Phase 48 UI columns, and Phase 49 controls.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module.
    # Uses standardized hashtable format (project convention from FFU.Core.psd1, FFU.Hypervisor.psd1).
    RequiredModules = @(
        @{ModuleName = 'FFU.Core';      ModuleVersion = '1.0.0'},
        @{ModuleName = 'FFU.Preflight'; ModuleVersion = '1.0.0'}
    )

    # Functions to export from this module.
    # Factory functions (New-*) are exported for cross-scope class instantiation (Pitfall 4).
    FunctionsToExport = @(
        'Get-ArtifactMetadata',
        'Find-FFUArtifacts',
        'Test-ArtifactCompatibility',
        'New-ArtifactManifest',
        'New-ArtifactResult'
    )

    # No cmdlets, variables, or aliases to export
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('FFU', 'WindowsDeployment', 'ArtifactScanner', 'USBMode', 'DISM')

            LicenseUri = 'https://github.com/FFUBuilder/FFU/blob/main/LICENSE'
            ProjectUri = 'https://github.com/FFUBuilder/FFU'

            ReleaseNotes = @'
v1.0.0 (2026-03-14)
- NEW: FFU.ArtifactScanner module scaffold (Phase 46 Plan 01)
- NEW: Data contract classes — ArtifactFileEntry, FFUMetadata, ArtifactResult, CompatibilityWarning, ArtifactManifest
- NEW: Enums — ArtifactStatus (Found/Missing/Error/Degraded), ArtifactType (FFU/DeployISO/Drivers/PPKG/Unattend/Autopilot/AppsISO)
- NEW: Get-ArtifactMetadata - extracts FFU metadata via DISM (Get-WindowsImage) with filename-parsing fallback
  - DISM primary path: WindowsVersion, WindowsSKU, Architecture, ImageName via Get-WindowsImage
  - Architecture mapping: integer 0=x86, 9=x64, 12=arm64 (DISM encoding)
  - Filename fallback: when WIMMount unavailable or DISM fails, parses arch/version from filename
  - MetadataSource property: 'DISM' or 'Filename' to indicate extraction path
- NEW: Factory functions for cross-scope class instantiation (Pitfall 4 pattern from FFU.Hypervisor)
  - New-ArtifactManifest: returns [ArtifactManifest] with ScanTimestamp initialized
  - New-ArtifactResult: returns [ArtifactResult] with ArtifactType set and Files list initialized
- NEW: Stub implementations of Find-FFUArtifacts and Test-ArtifactCompatibility (full implementation in Plan 46-02)
- ThreadJob compatible: [DateTime]::Now, safe WriteLog pattern, [Console]::Error.WriteLine
'@
        }
    }
}
