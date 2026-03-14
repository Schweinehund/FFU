# Phase 46: FFU.ArtifactScanner Module - Context

**Gathered:** 2026-03-14
**Status:** Ready for planning

<domain>
## Phase Boundary

A tested, isolated module that discovers all deployable artifacts from an FFUDevelopmentPath, extracts FFU metadata via DISM, and validates cross-artifact compatibility. The module defines the data contract (classes/enums) that Phase 47 (pipeline), Phase 48 (UI columns), and Phase 49 (controls) depend on.

</domain>

<decisions>
## Implementation Decisions

### Artifact Catalog
- Always scan for all 7 artifact types regardless of config flags: FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO
- Missing optional artifacts show as informational "Not found" status, not errors
- Discover ALL .ffu files in the FFU folder, flag newest as primary
- Drivers treated as single artifact (folder-level): found/missing, total size, file count
- Deploy ISO only (no Capture ISO) — USB Mode is for deployment
- FFUDevelopmentPath only as input — per-artifact path overrides deferred to Phase 49
- Architecture-specific unattend scanning: look for unattend_x64.xml and unattend_arm64.xml (matches BuildFFUVM.ps1 lines 1504-1515)
- Deploy ISO architecture parsed from filename pattern (WinPE_FFU_Deploy_{arch}.iso)
- Apps.iso: existence + file size only, no ISO mount validation
- Autopilot: any .json files in Autopilot folder (matches existing validation at BuildFFUVM.ps1 line 2107)
- PPKG: any .ppkg files in PPKG folder, report count + paths + sizes
- Find-FFUArtifacts returns a single [ArtifactManifest] object (not array or hashtable)
- Graceful degradation on errors: mark individual artifacts as 'Error' status with message, continue scanning remaining artifacts

### FFU Metadata Extraction
- DISM primary via Get-WindowsImage, filename parsing fallback if DISM fails
- Metadata extracted automatically during Find-FFUArtifacts (not lazy/separate)
- Extract metadata for ALL discovered FFU files, not just primary
- Core fields: WindowsVersion, WindowsSKU, Architecture, ImageName, BuildDate
- On DISM failure: return partial metadata from filename with MetadataSource='Filename' and ErrorMessage property
- Get-ArtifactMetadata is a public exported function (testable independently, callable by Phase 49)
- WIMMount prerequisite: reuse existing Test-FFUWimMount from FFU.Preflight (fltmc check + auto-repair), call once at scan start, cache result, skip DISM if unavailable

### Staleness & Compatibility
- Staleness: age in days from file LastWriteTime, returned as integer AgeDays property — no tiered labels baked into scanner
- Compatibility: architecture mismatch only (FFU arch vs Deploy ISO arch)
- Mismatch severity: warning level (not blocking error) — scanner informs, doesn't gatekeep
- Compatibility checks run automatically during Find-FFUArtifacts
- Each warning includes human-readable Message property (e.g., "FFU architecture (ARM64) does not match Deploy ISO architecture (x64)")

### Output Data Model
- PowerShell classes (not PSCustomObject) — matches FFU.Common.Classes.psm1 and FFU.Hypervisor/Classes/ pattern
- [ArtifactStatus] enum: Found, Missing, Error, Degraded
- [ArtifactType] enum: FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO
- Multi-file artifacts: Files array (path, size, lastWrite) + summary properties (FileCount, TotalSizeBytes)
- Compatibility warnings: top-level Warnings array on ArtifactManifest (array of [CompatibilityWarning] with Severity, Message, AffectedArtifacts)
- Readiness summary: FoundCount, MissingCount, ErrorCount, IsReady boolean (true if FFU + DeployISO found, no errors)
- Scan provenance: ScanTimestamp ([DateTime]) and BasePath on manifest

### Module Structure
- Classes/ subfolder with ArtifactScanner.Classes.psm1 (enums + data classes)
- Single FFU.ArtifactScanner.psm1 with all public functions
- Located at Modules/FFU.ArtifactScanner/

### Claude's Discretion
- Whether to add ConvertTo/ConvertFrom JSON serialization helpers (depends on how native ConvertTo-Json handles the classes)
- Internal helper function organization within the single .psm1
- Exact class property types for edge cases (e.g., nullable vs default values)

</decisions>

<specifics>
## Specific Ideas

- Multi-FFU discovery aligns with existing CopyAdditionalFFUFiles mechanism in BuildFFUVM.ps1
- Error handling follows existing graceful degradation pattern (Invoke-BuildPhase)
- WIMMount validation reuses Phase 44's established pattern (fltmc filters check, registry repair, service restart)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- Test-FFUWimMount (FFU.Preflight): WIMMount filter service validation with auto-repair — call before DISM operations
- Get-WindowsImage (DISM module): Works with FFU files for metadata extraction without mounting
- FFU.Common.Classes.psm1: Pattern for defining shared PowerShell classes
- FFU.Hypervisor/Classes/: Pattern for Classes/ subfolder organization

### Established Patterns
- Module naming: FFU.<Name> convention with .psd1 manifest
- Module dependencies: RequiredModules hashtable format in .psd1
- Error handling: Invoke-WithErrorHandling, try/catch with specific exceptions
- Function naming: Verb-FFU<Noun> pattern (e.g., Find-FFUArtifacts, Get-ArtifactMetadata, Test-ArtifactCompatibility)

### Integration Points
- FFU.Core: Required dependency for WriteLog, error handling utilities
- FFU.Preflight: Test-FFUWimMount for DISM prerequisite validation
- BuildFFUVM.ps1 artifact paths (lines 1830-1867): Default path conventions for all artifact types
- Phase 45 config schema: ArtifactManifest structure must align with USBMode config section
- Phase 47 pipeline: Reads manifest to set skip flags
- Phase 48 UI: Manifest properties drive ListView columns
- Phase 49 controls: Per-artifact ArtifactResult drives browse buttons and checkboxes

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 46-ffu-artifactscanner-module*
*Context gathered: 2026-03-14*
