# Phase 45: Config Schema Extension - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend the config schema with USB Mode fields and migration for existing configs. The schema defines the persistent state that Phase 49 (UI controls) reads/writes and Phase 50 (selective rebuild) operates on. This phase does NOT build UI or pipeline — only schema, migration, and config I/O.

</domain>

<decisions>
## Implementation Decisions

### USBMode Section Structure
- **D-01:** New `USBMode` top-level section with nested `Artifacts` object keyed by artifact type
- **D-02:** One path per artifact type (not arrays) — USB Mode uses a single artifact per type
- **D-03:** Artifact keys match Phase 46's `[ArtifactType]` enum values: FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO
- **D-04:** Each artifact entry has two fields: `Path` (string or null) and `Disposition` (string enum: Reuse, Rebuild, Skip)
- **D-05:** Default disposition for all artifact types is `Reuse` (USB Mode's primary purpose is reusing existing artifacts)
- **D-06:** Default path for all artifact types is `null` (populated by Phase 49 browse dialogs or auto-scan)

### Mode State Persistence
- **D-07:** New `ActiveMode` field at top level (not inside USBMode section)
- **D-08:** Valid values: `"FullBuild"` or `"USBMode"`
- **D-09:** Default: `"FullBuild"` (preserves current behavior for existing configs)

### Existing USB Field Relationship
- **D-10:** Existing `BuildUSBDrive`, `USBDriveList`, `MaxUSBDrives` remain at top level — they serve Full Build mode
- **D-11:** USB Mode reuses existing `USBDriveList` and `MaxUSBDrives` for drive selection (no duplication)
- **D-12:** The `USBMode` section is cleanly scoped to artifact paths and dispositions only

### Schema Version and Migration
- **D-13:** Schema version bumps from 1.2 to 1.3
- **D-14:** Migration injects `ActiveMode: "FullBuild"` and full `USBMode.Artifacts` section with null paths and Reuse dispositions
- **D-15:** Existing config data preserved — no fields removed or renamed in this migration
- **D-16:** Backup created before migration (existing pattern: `config.json.backup-{timestamp}`)

### Config I/O
- **D-17:** `Get-UIConfig` collects USBMode artifact paths and dispositions from UI state
- **D-18:** `Update-UIFromConfig` applies USBMode fields to UI controls (Phase 48/49 will add the actual controls)
- **D-19:** Schema file (`ffubuilder-config.schema.json`) updated with USBMode section definition

### Claude's Discretion
- Internal migration function organization within FFU.ConfigMigration
- Schema JSON structure for `oneOf`/`enum` constraints on Disposition values
- Whether to add schema validation for ActiveMode values or rely on code-level validation
- Test fixture file structure for migration tests

</decisions>

<specifics>
## Specific Ideas

- Config structure mirrors the ArtifactType enum from Phase 46 — downstream phases iterate artifact keys without mapping
- Single migration step (v1.2 → v1.3) avoids a second migration when Phase 50 adds disposition controls

</specifics>

<canonical_refs>
## Canonical References

### Config schema and migration
- `FFUDevelopment/config/ffubuilder-config.schema.json` — Current schema definition (v1.2, 656 lines)
- `FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1` — Migration logic, Get-FFUConfigSchemaVersion, Invoke-FFUConfigMigration
- `FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psd1` — Module manifest v1.1.1

### UI config I/O
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` — Get-UIConfig (line 13), Update-UIFromConfig (line 505), Invoke-SaveConfiguration (line 968)

### Phase 46 data contract (artifact types)
- `.planning/phases/46-ffu-artifactscanner-module/46-CONTEXT.md` — ArtifactType enum, ArtifactManifest structure

### Existing USB config fields
- `FFUDevelopment/config/ffubuilder-config.schema.json` — BuildUSBDrive, USBDriveList, MaxUSBDrives definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- FFU.ConfigMigration: Established migration pattern (version detection, backup, transform, version stamp)
- Test-FFUConfigVersion: Detects if migration needed — already handles missing `configSchemaVersion` field
- ffubuilder-config.schema.json: JSON Schema Draft-07 with property definitions, defaults, and CommonValues

### Established Patterns
- Migration adds defaults for new fields (e.g., v1.1 added IncludePreviewUpdates:false, v1.2 added VMwareSettings)
- Schema version is a string (e.g., "1.2") returned by Get-FFUConfigSchemaVersion
- Get-UIConfig collects all UI state into ordered hashtable; Update-UIFromConfig applies loaded config to controls
- Config keys sorted alphabetically on save for consistent output

### Integration Points
- Phase 48: Mode toggle reads `ActiveMode` from config on startup to restore UI state
- Phase 49: Browse dialogs write to `USBMode.Artifacts.{type}.Path`; controls write `Disposition`
- Phase 50: Reads `Disposition` values to determine which build phases to execute
- BuildFFUVM_UI.ps1 auto-load (line 197): Must handle new fields gracefully

</code_context>

<deferred>
## Deferred Ideas

- Auto-scan artifacts when restoring to USB Mode on startup — Phase 49 behavior
- Saved USB Mode profiles (named configurations per deployment scenario) — REBUILD-04, future requirement

</deferred>

---

*Phase: 45-config-schema-extension*
*Context gathered: 2026-03-20*
