# Phase 47: USB Mode Pipeline Entry - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

BuildFFUVM.ps1 accepts a USB-only invocation that reads an artifact manifest, sets skip flags for all build phases, and runs only USB assembly. No UI changes, no new modules — only pipeline integration with the existing `New-DeploymentUSB` function and the FFU.ArtifactScanner module from Phase 46.

</domain>

<decisions>
## Implementation Decisions

### Entry Point Design
- **D-01:** New `-USBOnlyMode [switch]` parameter added to BuildFFUVM.ps1 param block — explicit switch, not inferred from config
- **D-02:** Live scan via `Find-FFUArtifacts -FFUDevelopmentPath $FFUDevelopmentPath` at execution time — no saved manifest file, no `-ArtifactManifestPath` parameter
- **D-03:** Short-circuit code path after module imports (~line 1600): scan → validate → populate variables → jump directly to USB creation. Does NOT fall through 3,000 lines of gated build phases
- **D-04:** Reuse `New-DeploymentUSB` as-is with no wrapper — populate the existing script-scoped gate variables from manifest before calling

### Copy Gate Population
- **D-05:** Copy gates (`$CopyDrivers`, `$CopyPPKG`, `$CopyUnattend`, `$CopyAutopilot`) driven by manifest artifact status: `Found` → `$true`, `Missing` → `$false`
- **D-06:** Disposition (Reuse/Rebuild/Skip) is Phase 50's concern — Phase 47 ignores it entirely
- **D-07:** Missing optional artifacts (Drivers, PPKG, Autopilot, Unattend, AppsISO) log a warning via WriteLog ("Skipping {type} — not found at {path}") and set copy gate to `$false`
- **D-08:** `$WindowsArch` populated from primary FFU metadata: `$manifest.FFUFiles[0].Metadata.Architecture`
- **D-09:** `$SelectedFFUFile` populated with all Found FFU file paths from manifest (supports multi-FFU via existing array handling in New-DeploymentUSB)

### Error Handling and Pre-Validation
- **D-10:** Three-step validation sequence before any USB writes:
  1. `$manifest.IsReady` check — FFU + DeployISO must be Found (BLOCKING)
  2. Deploy ISO mountable — test with `Mount-DiskImage` before touching USB drives (BLOCKING, satisfies USB-01)
  3. Log all `$manifest.Warnings` — architecture mismatches, staleness info (NON-BLOCKING)
- **D-11:** Architecture mismatch (FFU vs Deploy ISO) is warn-and-continue, not blocking — per Phase 46 decision (scanner informs, doesn't gatekeep)
- **D-12:** ISO mount failure produces actionable error message including expected path and suggestion to run full build — halts before any USB writes (satisfies success criterion 2)
- **D-13:** Pre-flight checks (Hyper-V, ADK, disk space) skipped entirely — not relevant to USB assembly, handled naturally by the short-circuit code path

### Claude's Discretion
- Exact placement of the short-circuit block within BuildFFUVM.ps1 (after module imports, before build phases)
- How to handle `$LogFile` initialization for USBOnlyMode (may need a subset of the normal init)
- Whether to add a `$resolvedUSBThrottle` calculation or reuse the existing one
- ISO mount/dismount cleanup pattern within the validation step

</decisions>

<specifics>
## Specific Ideas

- Short-circuit pattern keeps USBOnlyMode code self-contained — easier to maintain than scattered skip flags throughout 2,400 lines
- Live scan guarantees manifest reflects actual disk state — no staleness risk from cached manifests
- Multi-FFU support comes free from existing `New-DeploymentUSB -FFUFilesToCopy` array parameter

</specifics>

<canonical_refs>
## Canonical References

### Pipeline integration
- `FFUDevelopment/BuildFFUVM.ps1` — Param block (lines 294-582), module imports (lines 552-569), path initialization (lines 1830-1867), USB creation invocation (lines 5184-5226)
- `FFUDevelopment/BuildFFUVM.ps1` — `New-DeploymentUSB` function (lines 1315-1549), ForEach-Object -Parallel block (lines 1411-1542) with 14 `$using:` variables

### Artifact scanner (Phase 46 output)
- `FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1` — ArtifactManifest, ArtifactResult, FFUMetadata, ArtifactStatus enum
- `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1` — Find-FFUArtifacts, Get-ArtifactMetadata, New-ArtifactManifest

### Config schema (Phase 45 output)
- `FFUDevelopment/config/ffubuilder-config.schema.json` — ActiveMode, USBMode.Artifacts section (v1.3 schema)

### Existing skip flag pattern
- `FFUDevelopment/BuildFFUVM.ps1` — `$skipPreflightValidation` (lines 1713-1739), `$skipDriverDownload` (lines 2433-2441), `$skipUSBCreation` (lines 5148-5151)

### `$using:` variable inventory (complete audit)
- `$PSScriptRoot` (line 1415), `$LogFile` (1416), `$ISOMountPoint` (1464-1465), `$CopyFFU` (1469), `$SelectedFFUFile` (1469-1479), `$CopyDrivers` (1484), `$DriversFolder` (1487), `$CopyPPKG` (1491), `$PPKGFolder` (1494), `$CopyUnattend` (1498), `$WindowsArch` (1503-1510), `$UnattendFolder` (1504-1517), `$CopyAutopilot` (1529), `$AutopilotFolder` (1532)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `New-DeploymentUSB`: Self-contained USB assembly function, supports `-CopyFFU` switch and `-FFUFilesToCopy` array
- `Find-FFUArtifacts`: Returns `[ArtifactManifest]` with `IsReady`, per-artifact `Status`, `FilePath`, and `Warnings`
- Skip flag pattern: `$skip<Phase>` boolean with `Test-PhaseAlreadyComplete` — established convention for bypassing phases
- `Mount-DiskImage` / `Dismount-DiskImage`: Standard PowerShell cmdlets for ISO validation

### Established Patterns
- Param block uses hardcoded defaults (no `[FFUConstants]::` — per param block coupling rule)
- Path initialization at lines 1830-1867: `if (-not $Var) { $Var = "$FFUDevelopmentPath\..." }` pattern
- Background job compatibility: all code must work within `Start-ThreadJob` context
- WriteLog for all user-facing messages (ThreadJob-safe)

### Integration Points
- `$ISOMountPoint`: Set by mounting Deploy ISO — New-DeploymentUSB reads this via `$using:ISOMountPoint`
- `$BuildUSBDrive`: Must be `$true` for USB creation gate (line 5184)
- `$resolvedUSBThrottle`: Controls parallel USB drive formatting — derived from `$MaxUSBDrives` param
- Phase 48/49: UI will set `-USBOnlyMode` switch when launching background job in USB Mode

</code_context>

<deferred>
## Deferred Ideas

- Disposition-based copy gating (Reuse/Rebuild/Skip) — Phase 50: Selective Rebuild Pipeline
- Per-artifact path overrides from UI browse dialogs — Phase 49: UI Event Wiring
- Config-driven auto-detection of USBOnlyMode — not needed, explicit switch is clearer

</deferred>

---

*Phase: 47-usb-mode-pipeline-entry*
*Context gathered: 2026-03-20*
