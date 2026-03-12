# Project Research Summary

**Project:** FFU Builder v1.11.0 — USB from Existing Components
**Domain:** WPF/PowerShell deployment tool — new UI mode for artifact-based USB creation
**Researched:** 2026-03-12
**Confidence:** HIGH

## Executive Summary

FFU Builder v1.11.0 introduces a "USB Mode" that lets users create deployment USB drives from pre-existing build artifacts (FFU, WinPE ISO, drivers, PPKG, unattend, Autopilot) without running the full 40+ minute build pipeline. This is an additive feature on top of a mature PowerShell/WPF codebase (13 modules, 2,400+ line orchestrator, established UI patterns). All research was conducted via direct codebase inspection with HIGH confidence — no speculation about capabilities or integration points.

The recommended approach avoids creating parallel infrastructure. Rather than a new entry-point script or separate window, USB Mode routes through a `-USBOnlyMode` switch on the existing `BuildFFUVM.ps1`, uses the existing `New-DeploymentUSB` function unchanged, and adds a single new module (`FFU.ArtifactScanner`) for artifact discovery and metadata extraction. The UI changes are limited to a mode toggle and a new `TabItem` in the existing `MainTabControl`. All metadata extraction uses Windows built-in DISM and Storage cmdlets already validated in this codebase.

The principal risks are: (1) failing to make the cancel/reset flow mode-aware, which causes incorrect button labels and broken cancellation; (2) running artifact scanning synchronously on the WPF STA thread, causing UI freezes; and (3) skipping config schema extension, which causes USB Mode artifact paths to not persist across sessions. All three have HIGH recovery cost if deferred. A fourth structural risk — repeating the documented param block coupling violation — causes ThreadJob launch failures that only appear when the UI is used, not during interactive testing. These pitfalls are well-understood from prior bug history and are fully preventable with the checklist items in PITFALLS.md.

## Key Findings

### Recommended Stack

No new external dependencies are required. All new capabilities use Windows built-ins already validated in the project: `Get-WindowsImage` (DISM module) for FFU/WIM metadata, `Mount-DiskImage` (Storage module) for ISO inspection, and WPF `Visibility` toggling for the mode switch. Two new code units are needed: `FFU.ArtifactScanner` module (new module following established psd1+psm1 naming) and a `FFUUI.Core.USBMode.psm1` submodule for USB Mode UI handlers. Both follow existing architectural conventions exactly.

**Core technologies (new for v1.11.0):**
- `Get-WindowsImage -ImagePath *.ffu` (DISM module): FFU/WIM metadata extraction without mounting — already used in `FFU.Imaging.psm1`; confirmed to accept `.ffu` paths
- `Mount-DiskImage -Access ReadOnly` (Storage module): ISO inspection for WinPE metadata — already used in `FFU.Imaging.psm1`; `Get-WimFromISO` pattern is directly reusable
- WPF `TabItem` + `Visibility` toggling: Mode switch UI — established pattern used throughout `FFUUI.Core.Handlers.psm1` and `FFUUI.Core.Initialize.psm1`
- `FFU.ArtifactScanner` (new module v1.0.0): Artifact discovery, metadata extraction, compatibility validation, manifest serialization
- `FFUUI.Core.USBMode.psm1` (new submodule v1.0.0): USB Mode tab UI handlers and mode toggle logic

### Expected Features

The MVP for v1.11.0 is a thin configuration layer over the existing `New-DeploymentUSB` function. All 8 P1 features have LOW-to-MEDIUM implementation complexity because they reuse existing codebase patterns.

**Must have (table stakes — v1.11.0):**
- Mode toggle (Full Build vs USB Mode) at top level — RadioButton group controls tab visibility
- Artifact auto-detection from `FFUDevelopmentPath` standard locations (FFU/, Drivers/, PPKG/, Unattend/, Autopilot/, WinPE*.iso)
- Artifact status display (ListView) with path and file size — mirrors existing `lvDriverModels` pattern
- Per-artifact include/exclude checkboxes — maps directly to existing `CopyFFU`, `CopyDrivers`, `CopyPPKG`, `CopyUnattend`, `CopyAutopilot` config flags
- Browse-to-path overrides per artifact — OpenFileDialog/FolderBrowserDialog (5 existing Browse buttons establish this pattern)
- WinPE ISO required pre-check — hard blocking gate before USB creation starts
- USB drive selection reuse — same `lstUSBDrives`/`chkSelectSpecificUSBDrives` controls from Build tab
- Wire through to existing `New-DeploymentUSB` via `-USBOnlyMode` + `-ArtifactManifest` params in `BuildFFUVM.ps1`

**Should have (competitive — v1.x follow-up patches):**
- Artifact metadata display (FFU Windows version/SKU/arch, WinPE ISO file date, driver model count)
- Cross-artifact compatibility validation — block assembly when FFU arch != Deploy ISO arch
- Staleness indicators (artifact age relative to configurable threshold)
- Config persistence for USB Mode artifact path overrides

**Defer (v2+):**
- Selective pipeline execution (rebuild individual artifacts without full build) — requires deep `Invoke-BuildPhase` integration; high complexity; defer until USB Mode adoption validates demand
- Saved USB Mode profiles (named configurations per deployment scenario)

**Anti-features to avoid:** Automatic rebuild of stale artifacts (masks intent, unexpectedly triggers 40+ min pipeline), cloud/network artifact sources (authentication scope explosion), USB Mode without WinPE ISO (produces non-bootable drive).

### Architecture Approach

USB Mode adds a vertical slice through the existing 4-layer architecture (WPF UI → ThreadJob boundary → Build Orchestrator → Module Layer) without modifying any existing module logic. The core insight is that USB Mode is effectively a "checkpoint-resume from after all build phases" — `BuildFFUVM.ps1` already has skip flags for each phase; USB Mode simply sets all of them except USB Creation and the optional rebuild phases. `New-DeploymentUSB` runs unchanged, receiving its required `$using:` variable set from the manifest-reading block.

**Major components and responsibilities:**
1. `FFU.ArtifactScanner` (new module): Scan standard paths, extract metadata via DISM, validate cross-artifact compatibility, serialize artifact manifest to temp JSON
2. `BuildFFUVM.ps1` manifest-reading block (new ~50 lines): Read manifest JSON, set skip flags, resolve all `$using:` variable names that `New-DeploymentUSB` reads
3. `FFUUI.Core.USBMode.psm1` (new submodule): Mode toggle event handlers, artifact ListView binding, manifest creation, USB Mode `btnRun` branch
4. `BuildFFUVM_UI.xaml` additions: Mode toggle RadioButton group, USB Mode `TabItem` with artifact ListView and per-artifact ComboBoxes
5. Config schema `USBMode` section (new fields in existing schema): Artifact path overrides, per-artifact disposition flags; version bump + migration rule

**Key patterns:**
- Artifact Manifest as Contract: UI serializes user decisions to temp JSON; pipeline reads and acts — clean decoupling, consistent with existing ConfigFile pattern
- Selective Pipeline via Phase Skip Flags: Reuses existing `$skipXxx` flag mechanism; no new phase infrastructure needed
- Reduced Preflight: New `Invoke-USBModePreflight` in FFU.ArtifactScanner calls only admin + disk space + ADK tiers from existing `FFU.Preflight` checks — avoids false Hyper-V/VMware failures on non-host machines

### Critical Pitfalls

1. **Mode state not propagated to cancel/reset flow** — Introduce `currentMode` flag in `$script:uiState.Flags` before setting `isBuilding = $true`; audit all 4 hardcoded `"Build FFU"` strings in `BuildFFUVM_UI.ps1` (lines 332, 413, 827) and `FFUUI.Core.StateRecovery.psm1` (line 35); make `Reset-FFUUIToIdle` mode-aware. Must be addressed in the first phase that wires `btnRun` to the USB path.

2. **Artifact scanning on the WPF STA thread** — All file system enumeration (`Get-ChildItem`) and DISM metadata calls must run in a `Start-ThreadJob` with `$window.Dispatcher.Invoke()` callbacks for UI updates. Never place synchronous I/O in button click handlers or `Window.Loaded`. Add progress spinner. Must be designed correctly from day one — retrofitting is harder than building it right.

3. **Config schema not extended before UI is wired** — Define USB Mode fields in `ffubuilder-config.schema.json` with a schema version bump, add migration rule in `FFU.ConfigMigration`, and update `Get-UIConfig`/`Set-UIConfig` before any UI code that reads artifact state from config. Recovery cost is HIGH (schema change after users have saved configs).

4. **Cross-architecture artifact mismatch not validated** — Architecture must be a required field extracted during scan (via `Get-WindowsImage` for FFU, WIM boot record for ISO), stored in the artifact metadata object, and validated as a hard blocking gate before USB assembly starts. Shipping without this creates silent deployment failures in the field.

5. **Param block coupling violation** — Any new parameters added to `BuildFFUVM.ps1`'s param block must use hardcoded literal defaults, not `[FFUConstants]::` expressions. Violations cause parse-time failures that only appear when launched via `Start-ThreadJob` from the UI, not during interactive testing. Add a Pester test that launches `BuildFFUVM.ps1` via `Start-ThreadJob` with USB Mode parameters.

6. **DISM cmdlets unavailable in ThreadJob** — Explicitly call `Import-Module DISM` and `Set-CommonCoreLogPath` inside any ThreadJob scriptblock that invokes `Get-WindowsImage`. Validate WIMMount filter service (`fltmc filters`) before any DISM image inspection, using the v1.3.12 auto-repair pattern.

## Implications for Roadmap

Based on research dependencies and pitfall severity, the suggested phase structure has 6 phases. The ordering is driven by: (1) config schema must precede UI; (2) scanner module must precede UI wiring; (3) pipeline contract must be testable before UI integration; (4) UI components can be developed in parallel after the contract is defined.

### Phase 1: Config Schema Extension and Migration
**Rationale:** Config schema defines the data contract for all other phases. The UI cannot serialize artifact state, and the pipeline cannot read a manifest, until the schema is defined. Schema changes after users have saved configs require migrations — getting this right first prevents HIGH-cost recovery later (Pitfall 6 from PITFALLS.md).
**Delivers:** Updated `ffubuilder-config.schema.json` with `USBMode` section; schema version bump; `FFU.ConfigMigration` rule for v1.10.0 → v1.11.0 upgrade; updated `Get-UIConfig`/`Set-UIConfig`; Pester migration test.
**Addresses:** Config persistence for USB Mode paths (P1 table stakes).
**Avoids:** Config schema not extended pitfall (recovery cost: HIGH if deferred).

### Phase 2: FFU.ArtifactScanner Module (Core Scan Functions)
**Rationale:** Everything else — UI display, pipeline contract, manifest creation — depends on the scanner. Building it as an isolated module first allows full test coverage without UI complexity. The `$using:` variable constraint in `New-DeploymentUSB` means the scanner's manifest schema must be defined before the pipeline integration phase.
**Delivers:** `FFU.ArtifactScanner.psd1` + `FFU.ArtifactScanner.psm1` with `Find-FFUArtifacts`, `Get-ArtifactMetadata`, `Test-ArtifactCompatibility`, `New-ArtifactManifest`; `FFU.ArtifactScanner.Tests.ps1`.
**Addresses:** Auto-detect artifacts, artifact status display, browse-to-path, WinPE ISO pre-check (all P1 table stakes).
**Avoids:** ThreadJob DISM failure (Pitfall 5), cross-architecture mismatch (Pitfall 4) — both must be built into the scanner from iteration 1.

### Phase 3: BuildFFUVM.ps1 USB Mode Pipeline Entry
**Rationale:** Adding `-USBOnlyMode` switch and manifest-reading block to `BuildFFUVM.ps1` can be built and tested via CLI before any UI work exists. This validates the pipeline contract (all `$using:` variable names correctly populated, skip flags correctly set, reduced preflight correctly scoped) without UI complexity.
**Delivers:** `-USBOnlyMode` switch + `-ArtifactManifest` param in `BuildFFUVM.ps1`; manifest-reading block (~50 lines setting all skip flags and `$using:` variable names); `Invoke-USBModePreflight` function; Pester `Start-ThreadJob` launch test.
**Addresses:** Wire through to `New-DeploymentUSB` (P1), reduced preflight for non-Hyper-V machines.
**Avoids:** Param block coupling pitfall (Pitfall 7), selective pipeline bypassing needed preflight (Pitfall 3).

### Phase 4: XAML Mode Toggle and USB Mode Tab
**Rationale:** Pure XAML work that can proceed in parallel with Phases 2-3 once the artifact data model is agreed. XAML changes are isolated — add mode toggle RadioButton group and USB Mode `TabItem` with artifact ListView skeleton. Must add Pester XAML parse test at the start of this phase.
**Delivers:** Updated `BuildFFUVM_UI.xaml` with mode toggle controls and USB Mode tab structure; Pester `[Windows.Markup.XamlReader]::Load()` validation test.
**Addresses:** Mode toggle UI (P1), artifact status display UI skeleton.
**Avoids:** XAML load failure pitfall (Pitfall 8) — parse test must precede any XAML PR merge.

### Phase 5: UI Event Wiring and End-to-End Integration
**Rationale:** Final integration phase — wires scanner (Phase 2) into UI (Phase 4) and connects to pipeline (Phase 3). This is the phase where mode-aware cancel/reset flow must be implemented. All `btnRun.Content` hardcoded strings must be audited in this phase.
**Delivers:** `FFUUI.Core.USBMode.psm1` with mode toggle handlers, scanner invocation (async via ThreadJob + Dispatcher.Invoke), artifact ListView binding, manifest creation, and USB Mode `btnRun` branch; mode-aware `Reset-FFUUIToIdle`; `currentMode` flag in `$script:uiState.Flags`.
**Addresses:** All remaining P1 table stakes (USB drive selection reuse, progress feedback, full end-to-end flow).
**Avoids:** Mode state not propagated to cancel flow (Pitfall 1 — CRITICAL), artifact scanner on STA thread (Pitfall 2).

### Phase 6: Metadata Display and Compatibility Validation (P2 Follow-up)
**Rationale:** P2 features (metadata display, cross-artifact compatibility validation, staleness indicators, config persistence) are valuable but not required for a viable USB Mode. Shipping Phase 5 and validating adoption before implementing P2 reduces risk of over-engineering. Cross-artifact compatibility validation (Pitfall 4) is partially addressed in Phase 2 (architecture extraction in scanner); Phase 6 completes the UI-facing validation gate.
**Delivers:** FFU metadata display in artifact ListView (Windows version/SKU/arch); architecture cross-validation blocking gate in UI; staleness indicators; config save/load for USB Mode artifact paths.
**Addresses:** Metadata extraction and display (P2), compatibility validation (P2), staleness indicators (P2), config persistence for paths (P2).

### Phase Ordering Rationale

- Config schema first (Phase 1) because changing schema after users save configs requires migrations — the only HIGH-cost recovery pitfall that worsens with time.
- Scanner module second (Phase 2) because it defines the data model (ArtifactCatalog, ArtifactManifest) that all other phases consume; testable in isolation with mock filesystem.
- Pipeline entry third (Phase 3) because the `$using:` variable constraint in `New-DeploymentUSB` means the manifest schema must be stable before this phase; CLI-testable without UI.
- XAML fourth (Phase 4) because it can proceed in parallel with Phases 2-3 once data model is agreed, but must be isolated from UI wiring until scanner/pipeline are stable.
- UI wiring last among P1 phases (Phase 5) because it depends on all prior phases; the cancel/reset mode-awareness is the most dangerous pitfall and belongs in a dedicated phase.
- P2 features deferred (Phase 6) to validate USB Mode adoption before adding complexity.

### Research Flags

Phases needing deeper research during planning:
- **Phase 3 (Pipeline Entry):** The exact set of `$using:` variable names read by `New-DeploymentUSB`'s `ForEach-Object -Parallel` block must be verified by line-by-line inspection of `BuildFFUVM.ps1` lines 1315-1549 before writing the manifest-reading block. Missing one variable causes silent skip of optional file copy (no error, just incomplete USB).
- **Phase 5 (UI Wiring):** The cancel flow audit requires reading every location where `isBuilding` is set and `btnRun.Content` is assigned. PITFALLS.md identified lines 332, 413, 827 of `BuildFFUVM_UI.ps1` and line 35 of `FFUUI.Core.StateRecovery.psm1` — the plan phase must verify this list is complete before implementation begins.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Config Schema):** FFU.ConfigMigration pattern is well-established; schema version bump + migration rule + test is a repeated operation in this codebase.
- **Phase 2 (ArtifactScanner Module):** `Get-WindowsImage`, `Mount-DiskImage`, `Get-ChildItem` patterns are directly reusable from `FFU.Imaging.psm1`; module structure follows 13 existing modules exactly.
- **Phase 4 (XAML):** WPF `TabItem` addition and `Visibility` toggling are established patterns in `FFUUI.Core.Handlers.psm1`; no research needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All recommendations verified in live source code; `Get-WindowsImage` confirmed to accept `.ffu` paths via live DISM test on this machine; no third-party dependencies |
| Features | HIGH | Based on direct codebase analysis of existing `New-DeploymentUSB`, `USBImagingToolCreator.ps1`, and config schema — not speculation; P1/P2/P3 split matches actual complexity |
| Architecture | HIGH | Integration points verified at specific line numbers in `BuildFFUVM.ps1`; `$using:` variable constraint documented at line 1152; anti-patterns verified via existing comment at same location |
| Pitfalls | HIGH | Derived from direct inspection of bug-prone code paths (cancel flow, `btnRun.Content` assignments, `FFUUI.Core.StateRecovery.psm1`) and project bug history (v1.3.5-v1.3.12 WIMMount progression, v0.0.9-v0.0.12 ThreadJob fixes) |

**Overall confidence:** HIGH

### Gaps to Address

- **Complete `$using:` variable inventory:** PITFALLS.md and ARCHITECTURE.md list the known variables (`$DeployISO`, `$DriversFolder`, `$CopyDrivers`, etc.) but the list was derived from reading the function — not a mechanical extraction. Phase 3 planning must include a line-by-line audit of `New-DeploymentUSB`'s `ForEach-Object -Parallel` block to produce a definitive, complete list.
- **FFU metadata extraction performance:** `Get-WindowsImage` on an FFU file may take 5-15 seconds depending on file size. STACK.md recommends caching in `$script:uiState.Data` after first extraction. The exact performance characteristics on this machine's storage are not measured — Phase 2 implementation should include a timing benchmark to determine whether async extraction is required or synchronous is acceptable.
- **USB drive selection sharing vs. duplication:** FEATURES.md notes that `lstUSBDrives` and `chkSelectSpecificUSBDrives` in the Build tab may need to be shared or duplicated for USB Mode. Whether these controls can be referenced from the USB Mode tab (shared binding) or require duplication into the new tab needs architectural decision in Phase 4 planning.

## Sources

### Primary (HIGH confidence — direct source code)
- `D:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM.ps1` — USB function block (lines 1150-1553), param block coupling documentation (lines 7-18), phase execution structure (lines 5086-5220)
- `D:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM_UI.ps1` — `$script:uiState` shape, ThreadJob launch pattern (lines 560-660), `btnRun` content assignments (lines 332, 413, 827)
- `D:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM_UI.xaml` — TabControl structure, existing tab list, USB Drive section XAML (lines 820-906)
- `D:\claude\FFUBuilder\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1` — `Get-WindowsImage`, `Mount-DiskImage`, `Get-WimFromISO` patterns (line 529, ~450)
- `D:\claude\FFUBuilder\FFUDevelopment\FFUUI.Core\FFUUI.Core.Handlers.psm1` — `Visibility` toggle pattern
- `D:\claude\FFUBuilder\FFUDevelopment\FFUUI.Core\FFUUI.Core.StateRecovery.psm1` — hardcoded idle label (line 35)
- `D:\claude\FFUBuilder\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1` — tiered check function list
- `D:\claude\FFUBuilder\FFUDevelopment\USBImagingToolCreator.ps1` — existing standalone USB creation flow
- `D:\claude\FFUBuilder\FFUDevelopment\config\ffubuilder-config.schema.json` — existing USB-related config properties

### Secondary (HIGH confidence — live system verification)
- Live DISM test on this machine — confirmed `Get-WindowsImage -ImagePath *.ffu` is a valid call signature (file-not-found error confirms format acceptance)
- CLAUDE.md bug history — v1.3.5-v1.3.12 WIMMount detection/repair progression; v1.2.7-v1.2.9 ThreadJob module loading failures; v0.0.9-v0.0.12 ThreadJob cmdlet availability fixes

---
*Research completed: 2026-03-12*
*Ready for roadmap: yes*
