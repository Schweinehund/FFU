# Roadmap: FFU Builder

## Milestones

- ✅ **v1.8.0 Codebase Health** - Phases 1-10 (shipped 2026-01-20)
- ✅ **v1.8.1 Bug Fixes** - Phases 11-13 (shipped 2026-01-20)
- ✅ **v1.8.3 VMware UI Settings** - Phase 14 (shipped 2026-01-21)
- ✅ **v1.9.0 Reliability Hardening** - Phases 15-25 (shipped 2026-01-24)
- ✅ **v1.9.1 Build Phase Integration** - Phase 26 (shipped 2026-01-24)
- ✅ **v1.9.2 Smart Configuration & Bug Fixes** - Phases 27-30 (shipped 2026-01-25)
- ✅ **v1.9.3 OEM Driver Bug Fixes** - Phases 31-33 (shipped 2026-01-27)
- ✅ **v1.10.0 Upstream Cherry-Pick** - Phases 34-43 (shipped 2026-02-02)
- ✅ **Phase 44: DISM Resilience Updates** - (shipped 2026-03-12, ad-hoc)
- 🚧 **v1.11.0 USB from Existing Components** - Phases 45-50 (in progress)

## Phases

<details>
<summary>✅ v1.8.0 through v1.10.0 + Phase 44 (Phases 1-44) - SHIPPED</summary>

Phases 1-44 complete. See MILESTONES.md for details.

</details>

### 🚧 v1.11.0 USB from Existing Components (In Progress)

**Milestone Goal:** Enable USB deployment media creation from pre-existing build artifacts without running the full 40+ minute build pipeline.

- [ ] **Phase 45: Config Schema Extension** - Extend config schema with USB Mode fields and migration for existing configs
- [x] **Phase 46: FFU.ArtifactScanner Module** - New module for artifact discovery, metadata extraction, and compatibility validation (completed 2026-03-14)
- [ ] **Phase 47: USB Mode Pipeline Entry** - Add `-USBOnlyMode` switch and artifact manifest reading block to BuildFFUVM.ps1
- [ ] **Phase 48: XAML Mode Toggle and USB Tab** - Add mode toggle RadioButton group and USB Mode TabItem to BuildFFUVM_UI.xaml
- [ ] **Phase 49: UI Event Wiring and Artifact Integration** - Wire scanner into UI with browse dialogs, per-artifact controls, and USB drive selection
- [ ] **Phase 50: Selective Rebuild Pipeline** - User-controlled per-artifact rebuild disposition with selective phase execution

## Phase Details

### Phase 45: Config Schema Extension
**Goal**: Config schema and migration support USB Mode state so artifact paths and dispositions persist across sessions
**Depends on**: Nothing (first phase of milestone)
**Requirements**: CONFIG-01, CONFIG-02
**Success Criteria** (what must be TRUE):
  1. Config schema includes a `USBMode` section with artifact path overrides and per-artifact disposition fields
  2. Loading an existing v1.10.0 config automatically migrates to v1.11.0 schema without data loss
  3. USB Mode artifact paths saved in one session are present when the UI is reloaded
  4. `Get-UIConfig` and `Set-UIConfig` read and write USB Mode fields without error
  5. Pester migration test passes with before/after config fixture files
**Plans**: TBD

### Phase 46: FFU.ArtifactScanner Module
**Goal**: A tested, isolated module that discovers all deployable artifacts, extracts metadata, and validates cross-artifact compatibility
**Depends on**: Phase 45 (schema defines artifact manifest structure)
**Requirements**: DISC-01, VALID-01, VALID-02, VALID-03, VALID-04
**Success Criteria** (what must be TRUE):
  1. `Find-FFUArtifacts` discovers FFU, boot ISO, drivers, PPKG, unattend, Autopilot, and Apps.iso from a given FFUDevelopmentPath
  2. `Get-ArtifactMetadata` extracts Windows version, SKU, and architecture from an FFU file via DISM without mounting
  3. `Test-ArtifactCompatibility` returns an architecture-mismatch warning when FFU arch and boot ISO arch differ
  4. Each artifact result includes found/missing status, file path, and file size
  5. Each artifact result includes a staleness indicator (age in days from file last-write time)
  6. All DISM calls run with explicit `Import-Module DISM` and WIMMount filter service validation
**Plans**: 2 plans
Plans:
- [ ] 46-01-PLAN.md — Module scaffold, data contract classes, Get-ArtifactMetadata
- [ ] 46-02-PLAN.md — Find-FFUArtifacts scanner, Test-ArtifactCompatibility, integration tests

### Phase 47: USB Mode Pipeline Entry
**Goal**: BuildFFUVM.ps1 accepts a USB-only invocation that reads an artifact manifest, sets skip flags for all build phases, and runs only USB assembly
**Depends on**: Phase 46 (manifest schema must be stable)
**Requirements**: USB-01, USB-04
**Success Criteria** (what must be TRUE):
  1. Invoking `BuildFFUVM.ps1 -USBOnlyMode` with a valid artifact manifest assembles a USB drive without running any build phases
  2. Missing WinPE deployment ISO causes USB creation to halt with an actionable error message before any USB writes occur
  3. All `$using:` variable names required by `New-DeploymentUSB` are correctly populated from the manifest-reading block
  4. A Pester test launches `BuildFFUVM.ps1 -USBOnlyMode` via `Start-ThreadJob` and verifies no parse-time failures
  5. No new param block defaults use `[FFUConstants]::` expressions
**Plans**: TBD

### Phase 48: XAML Mode Toggle and USB Tab
**Goal**: The UI has a mode toggle that switches between Full Build and USB Mode views, and a USB Mode tab with artifact display structure
**Depends on**: Phase 45 (schema defines what fields exist), Phase 46 (artifact data model drives ListView columns)
**Requirements**: UIMODE-01, UIMODE-02, UIMODE-03
**Success Criteria** (what must be TRUE):
  1. A mode toggle control (RadioButton group or equivalent) is visible at the top level of the UI
  2. Selecting USB Mode hides or disables all Full Build-specific controls (VM settings, Windows version picker, etc.)
  3. Selecting USB Mode makes the USB Mode tab and artifact-focused controls visible
  4. Selecting Full Build restores the standard tab layout with no USB Mode controls visible
  5. The XAML file passes a `[Windows.Markup.XamlReader]::Load()` parse test with no exceptions
**Plans**: TBD

### Phase 49: UI Event Wiring and Artifact Integration
**Goal**: USB Mode is fully interactive — users can browse to artifact paths, see artifact status, select per-artifact inclusions, and initiate USB creation
**Depends on**: Phase 46 (scanner), Phase 47 (pipeline entry), Phase 48 (XAML controls exist)
**Requirements**: DISC-02, DISC-03, USB-02, USB-03
**Success Criteria** (what must be TRUE):
  1. Activating USB Mode triggers async artifact scanning (non-blocking — UI remains responsive during scan)
  2. Browse buttons open file/folder dialogs for each artifact type and update the artifact path display
  3. Per-artifact include/exclude checkboxes control which artifacts are copied to the USB drive
  4. USB drive selection uses the existing drive detection mechanism from the Full Build tab
  5. Mode-aware cancel/reset correctly labels the button and cleans up state for both Full Build and USB Mode
  6. User-specified artifact paths survive a session restart (persisted via config)
**Plans**: TBD

### Phase 50: Selective Rebuild Pipeline
**Goal**: Users can mark each artifact as reuse, rebuild, or skip, and the pipeline executes only the build phases needed for marked-rebuild artifacts
**Depends on**: Phase 49 (full USB Mode end-to-end must work before adding selective rebuild)
**Requirements**: REBUILD-01, REBUILD-02, REBUILD-03
**Success Criteria** (what must be TRUE):
  1. USB Mode artifact display shows a per-artifact disposition control (reuse / rebuild / skip)
  2. Marking an artifact as rebuild causes only the corresponding build phase(s) to run before USB assembly
  3. Artifacts marked reuse are taken from their current paths with no build phase execution
  4. Artifacts marked skip are excluded from USB assembly entirely
  5. Rebuilt artifacts are combined with reused artifacts and assembled into the final USB drive
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 45 → 46 → 47 → 48 → 49 → 50

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-44. Previous Milestones | v1.8.0-v1.10.0 | 133/133 | Complete | 2026-03-12 |
| 45. Config Schema Extension | v1.11.0 | 0/TBD | Not started | - |
| 46. FFU.ArtifactScanner Module | 2/2 | Complete   | 2026-03-14 | - |
| 47. USB Mode Pipeline Entry | v1.11.0 | 0/TBD | Not started | - |
| 48. XAML Mode Toggle and USB Tab | v1.11.0 | 0/TBD | Not started | - |
| 49. UI Event Wiring and Artifact Integration | v1.11.0 | 0/TBD | Not started | - |
| 50. Selective Rebuild Pipeline | v1.11.0 | 0/TBD | Not started | - |

---
*Roadmap created: 2026-03-12 for v1.11.0 USB from Existing Components*
*Last updated: 2026-03-14*
