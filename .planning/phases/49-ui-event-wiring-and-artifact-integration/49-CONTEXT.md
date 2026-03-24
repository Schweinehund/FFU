# Phase 49: UI Event Wiring and Artifact Integration - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

USB Mode is fully interactive — users can browse to artifact paths, see artifact status, select per-artifact inclusions, and initiate USB creation. This phase wires all the XAML controls from Phase 48 with code-behind event handlers, integrates Phase 46's ArtifactScanner for live scanning, connects Phase 47's -USBOnlyMode pipeline entry, and adds config persistence for USB Mode state. Requirements: DISC-02, DISC-03, USB-02, USB-03.

</domain>

<decisions>
## Implementation Decisions

### Artifact Scanning Trigger & UX (Area A)
- **D-01:** Scan triggers on mode switch — when `rbUSBMode.Checked` fires, scan starts immediately after tab visibility swap
- **D-02:** Scanning runs synchronous on UI thread — `Find-FFUArtifacts` does filesystem-only operations (<2s), no ThreadJob/DispatcherTimer needed
- **D-03:** Per-card status updates — each artifact card's status TextBlock updates individually as results populate: `(scanning...)` → `Found` or `Missing`
- **D-04:** Rescan button — add `usbRescanArtifacts` Button at top of USB Mode tab for manual re-scan (requires small XAML addition)
- **D-05:** After scan completes, Browse buttons (`IsEnabled=$true`) and CheckBoxes (`IsEnabled=$true` for Found artifacts) are enabled

### Browse Override Behavior (Area B)
- **D-06:** Browse overrides scanner — user-browsed path replaces auto-detected path for that artifact
- **D-07:** Rescan respects overrides — re-scan only updates artifacts with `source='auto'`, preserves `source='user'` paths
- **D-08:** Internal state tracking per artifact: `source` ('auto' | 'user') and `path` — no visual distinction in UI between auto vs user paths
- **D-09:** Per-card reset clears override back to auto-detect — can be a small reset/× action on the card, or Rescan just skips user-overridden artifacts (simpler implementation)

### USB Drive Reuse Strategy (Area C)
- **D-10:** USB drive detection controls duplicated in USB Mode tab — new GroupBox "Target USB Drive" at bottom of USB tab with `usbCheckUSBDrives`, `usbUSBDriveList`, `usbSelectAllDrives` controls
- **D-11:** Both Build tab and USB tab call the same `Get-USBDrives` function — no shared state between the two sets of controls
- **D-12:** USB Mode tab is self-contained — user doesn't need to visit the Build tab for any USB Mode operation
- **D-13:** This requires a XAML addition (~30 lines) to Phase 48's USB Mode tab — small follow-up

### Mode-Aware Button & State (Area D)
- **D-14:** `btnRun.Content` updates on mode switch: USB Mode idle = "Create USB", Full Build idle = "Build FFU"
- **D-15:** During execution, `btnRun.Content = "Cancel"` regardless of mode — same cancel pattern as Full Build
- **D-16:** Cancel triggers existing `FFUCancellation` flag pattern — no new cancel mechanism
- **D-17:** `Reset-FFUUIToIdle` restores button label based on active mode (`rbUSBMode.IsChecked` → "Create USB", else "Build FFU")
- **D-18:** Active mode persists across restarts via config — read `config.ActiveMode` on startup, set RadioButton.IsChecked, fire mode switch handler (triggers scan if USB Mode)

### Pre-Launch Validation (Area D cont.)
- **D-19:** UI-side validation before launching ThreadJob: (1) FFU and DeployISO must be Found and checked, (2) at least one USB drive selected
- **D-20:** Show error dialog if validation fails — "Select an FFU file" / "Deploy ISO is required" / "Select a USB drive"
- **D-21:** Deeper validation (ISO mount test, architecture warnings) runs inside BuildFFUVM.ps1 -USBOnlyMode (Phase 47 D-10)

### Config Persistence (DISC-03)
- **D-22:** On config save: write `ActiveMode` ('FullBuild' | 'USBMode'), write user-browsed artifact paths to `USBMode.Artifacts.{Type}.Path`
- **D-23:** On config load: restore `ActiveMode` by setting RadioButton.IsChecked, restore user-overridden artifact paths (mark as `source='user'`), then scan fills remaining auto-detect paths
- **D-24:** Config save stubs in FFUUI.Core.Config.psm1 (lines 166-180, 622-628) must be replaced with actual control reads/writes

### Mode Switch Handler
- **D-25:** `rbUSBMode.Checked` handler sequence: (1) collapse 7 Full Build tabs, (2) show `usbModeTab`, (3) select `usbModeTab`, (4) run artifact scan, (5) update `btnRun.Content` to "Create USB"
- **D-26:** `rbFullBuild.Checked` handler sequence: (1) show 7 Full Build tabs, (2) collapse `usbModeTab`, (3) select first Full Build tab, (4) update `btnRun.Content` to "Build FFU"
- **D-27:** Tab names for toggling: `tabVMSettings`, `tabWindowsSettings`, `tabUpdates`, `tabApplications`, `tabM365AppsOffice`, `tabDrivers`, `tabBuild` (from Phase 48 D-06)

### Create USB Action
- **D-28:** "Create USB" click passes artifact paths and inclusion flags to `BuildFFUVM.ps1 -USBOnlyMode` via ThreadJob — same `Start-ThreadJob` pattern as Full Build
- **D-29:** Inclusion checkboxes map to copy gates: `usbFFUInclude.IsChecked` → `$CopyFFU`, `usbDriversInclude.IsChecked` → `$CopyDrivers`, etc.
- **D-30:** User-browsed paths override scanner defaults — passed as parameters or via config to the build script

### Claude's Discretion
- Per-artifact state tracking implementation (hashtable, PSCustomObject, or class)
- Whether Rescan button also re-validates user-overridden paths (recommend yes — verify they still exist)
- Exact XAML layout for the USB drive section in the USB Mode tab
- Error dialog implementation (MessageBox vs WPF custom dialog)
- How to pass user-overridden paths to BuildFFUVM.ps1 -USBOnlyMode (config vs parameters)

</decisions>

<specifics>
## Specific Ideas

- Synchronous scan keeps implementation simple — no concurrent queue, no polling timer, no background job overhead for a <2s filesystem scan
- Per-artifact `source` tracking enables smart rescan without losing user's manual path selections
- Self-contained USB Mode tab (with its own drive detection) means the user never needs to visit Full Build tabs during USB workflow
- Config persistence of ActiveMode means USB-focused users don't toggle on every launch
- Pre-launch validation in UI catches obvious errors before spawning a ThreadJob (fail fast)

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### XAML controls (Phase 48 output)
- `FFUDevelopment/BuildFFUVM_UI.xaml` — Lines 78-79 (rbFullBuild/rbUSBMode RadioButtons), lines 932-1243 (usbModeTab with 46 named controls), lines 851-923 (Build tab USB drive section to replicate)

### Event handler patterns
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` — Register-EventHandlers (line 8), Add_Checked pattern (lines 112-153), Browse handler pattern (lines 909-917), shared handler scriptblock (lines 376-413)
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` — Invoke-BrowseAction (line 826): unified browse function for Folder/OpenFile/SaveFile

### Config persistence stubs (Phase 45)
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` — Build-UIConfiguration USBMode save stub (lines 166-180), Update-UIFromConfig USBMode load stub (lines 622-628), Set-UIValue pattern (line 221)

### Artifact scanner (Phase 46)
- `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1` — Find-FFUArtifacts (line 264+), Get-ArtifactMetadata (line 174+)
- `FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1` — ArtifactManifest, ArtifactResult, ArtifactStatus enum, FFUMetadata

### Pipeline entry (Phase 47)
- `FFUDevelopment/BuildFFUVM.ps1` — `-USBOnlyMode` switch, short-circuit block after module imports

### USB drive detection
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.psm1` — Get-USBDrives (line 362)
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` — btnCheckUSBDrives handler (lines 199-221)

### Build job and cancel patterns
- `FFUDevelopment/BuildFFUVM_UI.ps1` — btnRun dual-mode handler (lines 209-839), ThreadJob launch, DispatcherTimer polling, Cancel/FFUCancellation
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.StateRecovery.psm1` — Reset-FFUUIToIdle (line 63)

### Config schema
- `FFUDevelopment/config/ffubuilder-config.schema.json` — ActiveMode field, USBMode.Artifacts section (v1.3 schema)

### Prior phase contexts
- `.planning/phases/45-config-schema-extension/45-CONTEXT.md` — D-07 through D-09: ActiveMode values
- `.planning/phases/46-ffu-artifactscanner-module/46-CONTEXT.md` — Artifact types, data model
- `.planning/phases/47-usb-mode-pipeline-entry/47-CONTEXT.md` — D-01 through D-13: Pipeline integration decisions
- `.planning/phases/48-xaml-mode-toggle-usb-tab/48-CONTEXT.md` — D-01 through D-22: XAML structure decisions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Invoke-BrowseAction`: Single function for all file/folder dialogs — use with `-Type 'OpenFile'` and appropriate `-Filter` per artifact type (`.ffu`, `.iso`, `.xml`, `.ppkg`)
- `Get-USBDrives`: Returns USB drive info hashtables — reuse for USB Mode tab's drive detection
- `Find-FFUArtifacts`: Returns ArtifactManifest with per-artifact status, paths, metadata — direct integration target
- `Register-EventHandlers`: Central event wiring function — add USB Mode handlers here
- `Build-UIConfiguration` / `Update-UIFromConfig`: Config save/load with stubs ready for USB Mode data

### Established Patterns
- Event handlers: `$State.Controls.<name>.Add_Click({ ... $window.Tag ... })` with window.Tag for state access
- Browse handlers: Call Invoke-BrowseAction, update TextBlock.Text on success
- Shared handlers: Single scriptblock assigned to multiple controls via `Add_Checked`
- Config round-trip: Build-UIConfiguration reads controls → JSON, Update-UIFromConfig reads JSON → controls
- Control registration: All named controls available via `$State.Controls.<x:Name>`

### Integration Points
- `rbUSBMode.Add_Checked` / `rbFullBuild.Add_Checked`: Wire in Register-EventHandlers
- `usbFFUBrowse.Add_Click` (and 6 more Browse buttons): Wire with Invoke-BrowseAction
- `Build-UIConfiguration`: Replace USBMode stub with actual control reads
- `Update-UIFromConfig`: Replace USBMode stub with actual RadioButton + artifact path restoration
- `btnRun` handler: Add USB Mode branch that launches `-USBOnlyMode` ThreadJob
- `Reset-FFUUIToIdle`: Mode-aware button label restoration

</code_context>

<deferred>
## Deferred Ideas

- Per-artifact disposition controls (Reuse/Rebuild/Skip) — Phase 50: Selective Rebuild Pipeline
- Artifact version history or rollback selection — Future (REBUILD-05)
- Network/cloud artifact sources — Out of scope per REQUIREMENTS.md
- Auto-rebuild stale artifacts — Out of scope per REQUIREMENTS.md
- USB Mode profiles (named configurations) — Future (REBUILD-04)

</deferred>

---

*Phase: 49-ui-event-wiring-and-artifact-integration*
*Context gathered: 2026-03-24*
