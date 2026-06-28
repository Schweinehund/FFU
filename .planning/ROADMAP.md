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
- ✅ **v1.11.0 USB from Existing Components** - Phases 45-50 (shipped 2026-06-26)
- 🚧 **v1.12.0 Upstream Sync — Correctness, Drivers & Device Naming** - Phases 51-58 (in progress)

## Phases

<details>
<summary>✅ v1.8.0 through v1.10.0 + Phase 44 (Phases 1-44) - SHIPPED</summary>

Phases 1-44 complete. See MILESTONES.md for details.

</details>

<details>
<summary>✅ v1.11.0 USB from Existing Components (Phases 45-50) — SHIPPED 2026-06-26</summary>

**Milestone Goal:** Enable USB deployment media creation from pre-existing build artifacts without running the full 40+ minute build pipeline.

- [x] Phase 45: Config Schema Extension (2/2 plans) — completed 2026-03-20
- [x] Phase 46: FFU.ArtifactScanner Module (2/2 plans) — completed 2026-03-14
- [x] Phase 47: USB Mode Pipeline Entry (1/1 plan) — completed 2026-03-20
- [x] Phase 48: XAML Mode Toggle and USB Tab (2/2 plans) — completed 2026-03-24
- [x] Phase 49: UI Event Wiring and Artifact Integration (5/5 plans) — completed 2026-03-25
- [x] Phase 50: Selective Rebuild Pipeline (6/6 plans) — completed 2026-06-22

Full phase details archived in `.planning/milestones/v1.11.0-ROADMAP.md`.
Requirements archived in `.planning/milestones/v1.11.0-REQUIREMENTS.md`.

</details>

### 🚧 v1.12.0 Upstream Sync — Correctness, Drivers & Device Naming (In Progress)

**Milestone Goal:** Selectively port the remaining high-value upstream changes (`rbalsleyMSFT/FFU` branch `UI`) into the fork's modular architecture — correctness fixes that prevent wrong/unbootable artifacts, driver-grid bug fixes, the device-naming/unattend feature family, shell-independent UI improvements, and hygiene fixes — while skipping the Fluent shell rewrite and anything that would regress fork-specific work.

**Scoping basis:** `.planning/reports/upstream-sync-verdict-2026-06-25.md`

- [x] **Phase 51: Capture/Boot Correctness** - Prevent wrong-edition, unbootable, and LTSC-failing artifacts (P1 must-ship core) (completed 2026-06-27)
- [ ] **Phase 52: Driver-Grid UI Fixes** - Fix filter/sort/save-scope bugs and CopyDrivers validation in the driver grid
- [ ] **Phase 53: Driver Build/Deploy Correctness** - Surface SKU matching, cached MS links, ReTrim compaction, 8-OEM deploy precision
- [ ] **Phase 54: Update Cache & Capture Naming** - OS-scoped update cache with stale prune and param-driven FFU naming
- [ ] **Phase 55: Device-Naming Foundation & Migrations** - DeviceNamingMode framework and USB UniqueId, with atomic config-schema migrations
- [ ] **Phase 56: Device-Naming Consumers & Unattend** - Serial CSV, auto ComputerName, custom unattend paths, surgical menu/`*` fallback
- [ ] **Phase 57: Shell-Independent UI** - ESD/ISO radios, expandable sections, ListView auto-resize, BYO app-list control
- [ ] **Phase 58: Hygiene & Robustness** - JSON-corruption recovery, dirty.txt path fix, output silencing, cleanup guards, ESD retain

## Phase Details

### Phase 51: Capture/Boot Correctness

**Goal**: Builds never produce a wrong-edition, unbootable, or LTSC-failing artifact — the captured FFU always matches the edition the user actually built, boots on modern Secure Boot devices, and supports LTSC driver downloads.
**Depends on**: Phase 50 (prior milestone)
**Requirements**: CORRECT-01, CORRECT-02, CORRECT-03, CORRECT-04
**Success Criteria** (what must be TRUE):

  1. When a user picks a fallback image because their exact SKU isn't present, the resulting FFU is named, cached, and serviced as the *selected* edition (not the originally-requested one).
  2. A user can download OEM drivers for an LTSC build (2019/2021/2024) without the driver step failing on a release-year validation error.
  3. A captured image boots on a device with the Secure Boot 2023 certificate because boot files were written with the ADK's BCDBoot rather than the host's.
  4. The correct edition is captured from non-English / multi-edition media because the image index is selected via EditionId/InstallationType, not a localized name substring.

**Plans**: 4 plans
Plans:
**Wave 1**

- [x] 51-01-PLAN.md - Get-WindowsImageSelection EditionId selection + selected-edition propagation (CORRECT-01, CORRECT-04)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 51-02-PLAN.md - Add-BootFiles ADK bcdboot + Test-FFUADK bcdboot preflight check (CORRECT-03)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 51-03-PLAN.md - Get-EffectiveDriverWindowsRelease LTSC year normalization at driver dispatch (CORRECT-02)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 51-04-PLAN.md - version.json/ApplyFFU bump + CHANGELOG_FORK + verify-app gate (CORRECT-01..04)

### Phase 52: Driver-Grid UI Fixes

**Goal**: The driver-selection grid behaves correctly under filtering, sorting, and saving — no selections are silently lost and invalid CopyDrivers configurations are blocked before a build starts.
**Depends on**: Phase 51
**Requirements**: DGRID-01, DGRID-02, DGRID-03
**Success Criteria** (what must be TRUE):

  1. Sorting the driver list while a filter is active keeps the filter applied instead of resetting to all rows.
  2. Selecting/deselecting drivers while filtered and then saving preserves selections for the filtered-out (hidden) rows, and the select-all header checkbox is correctly aligned.
  3. The UI prevents an invalid CopyDrivers configuration by requiring BuildUSBDrive when CopyDrivers is enabled.

**Plans**: 5 plans

Plans:
**Wave 1**

- [ ] 52-01-PLAN.md - Test scaffold (Test-Phase52DriverGridFixes.ps1) + DGRID-01 Invoke-ListViewSort filter capture/reapply (b4305a1) (DGRID-01)

**Wave 2** *(blocked on Wave 1)*

- [ ] 52-02-PLAN.md - DGRID-02 select-all visible scope + Save-DriversJson master-list source + driver-grid opt-in + header alignment (f09c989, 42ed281) (DGRID-02)

**Wave 3** *(blocked on Wave 2)*

- [ ] 52-03-PLAN.md - DGRID-03 CopyDrivers/BuildUSBDrive dependency throw in BuildFFUVM.ps1 END block, USBOnlyMode-guarded (dc801e9) (DGRID-03)

**Wave 4** *(blocked on Wave 3)*

- [ ] 52-04-PLAN.md - Version bumps (FFUUI.Core 0.0.22 / main 1.12.1 / ApplyFFU) + CHANGELOG_FORK + verify-app BLOCKING gate (DGRID-01, DGRID-02, DGRID-03)

**Wave 5** *(blocked on Wave 4)*

- [ ] 52-05-PLAN.md - Manual UAT checkpoint: six WPF driver-grid behaviors (DGRID-01, DGRID-02, DGRID-03)

**UI hint**: yes

### Phase 53: Driver Build/Deploy Correctness

**Goal**: OEM/Surface driver acquisition and deployment are precise and resilient — drivers match by hardware identifiers, download links survive page/proxy changes, captured artifacts are reclaimed to minimum size, and the 8 newer OEMs match with SystemID precision at deploy time.
**Depends on**: Phase 51
**Requirements**: DRVR-01, DRVR-02, DRVR-03, DRVR-04
**Success Criteria** (what must be TRUE):

  1. A user can auto-match Microsoft Surface drivers by System SKU rather than relying on an exact model-name string match.
  2. Microsoft/Surface driver download links are cached so builds don't break or stall when the live page changes or a proxy blocks the scrape.
  3. The captured FFU / cached VHDX is reclaimed to minimum size via `Optimize-Volume -ReTrim` before compaction, producing a smaller deployable artifact.
  4. At deploy time, the 8 newer OEMs (Panasonic, Getac, Fujitsu, etc.) are matched with SystemID-level precision in addition to the existing model-name fallback (NICE/3-tier fallback preserved).

**Plans**: TBD

### Phase 54: Update Cache & Capture Naming

**Goal**: Update servicing uses only the correct OS-scoped packages, and FFU naming is derived from build parameters — fast and reliable — without ever servicing an image with a leftover update from a different release.
**Depends on**: Phase 51
**Requirements**: CACHE-01, CACHE-02
**Success Criteria** (what must be TRUE):

  1. Update packages are cached per-OS and stale/cross-OS MSUs are pruned before servicing, so an image is never serviced with a leftover update from a different release.
  2. FFU file naming is driven by build parameters (avoiding the offline registry-hive read and its ~2 min of sleeps) while preserving the existing CBS/CSI corruption guards and DisplayVersion derivation.

**Plans**: TBD

### Phase 55: Device-Naming Foundation & Migrations

**Goal**: The DeviceNamingMode framework exists as the foundation for all naming modes, and USB drives are identified by UniqueId — with both config-schema migrations landing atomically so existing configs upgrade cleanly without data loss.
**Depends on**: Phase 51
**Requirements**: NAMING-01, NAMING-07
**Success Criteria** (what must be TRUE):

  1. A user can choose a device-naming mode (Template / Prefixes / Serial mapping / Prompt / None) via a unified DeviceNamingMode framework.
  2. An existing config is migrated to the new schema (DeviceNamingMode + UniqueId identifiers) without losing data and without breaking an existing build.
  3. USB drives are identified by UniqueId instead of SerialNumber, eliminating mis-selection of duplicate/blank-serial drives.
  4. Both schema changes (naming framework and UniqueId) land together so a partially-migrated config never occurs.

**Plans**: TBD
**UI hint**: yes

### Phase 56: Device-Naming Consumers & Unattend

**Goal**: The naming framework's consumers are fully wired — serial→name CSV authoring, auto-generated ComputerName, per-architecture custom unattend paths, correct UI state/labels, and a surgically-ported skippable menu with `*` fallback that preserves the fork's NICE-02 skip-drivers logic.
**Depends on**: Phase 55
**Requirements**: NAMING-02, NAMING-03, NAMING-04, NAMING-05, NAMING-06
**Success Criteria** (what must be TRUE):

  1. A user can author, load, and save a SerialComputerNames CSV in the UI, and the builder stages it onto the USB for serial→name mapping at deploy time.
  2. A ComputerName is auto-generated into the Unattend XML when the user supplies a minimal template, instead of the deploy step throwing on a missing element.
  3. A user can select a custom Unattend XML file path per architecture (x64/arm64), wired through both the USB-copy and audit-mode injection paths.
  4. The DeviceNamingMode UI tracks state/defaults correctly and uses clear labels (prompt option, serial-mapping labels).
  5. Deployment menu prompts are skippable via a shared Read-MenuSelection helper and unattend supports the `*` default-name fallback, with the fork's NICE-02 skip-drivers logic verified intact.

**Plans**: TBD
**UI hint**: yes

### Phase 57: Shell-Independent UI

**Goal**: Targeted UI usability improvements that don't depend on the (skipped) Fluent shell — media-source radios, collapsible dense sections, auto-resizing ListView columns, and a BYO app-list path control — expose existing backend capabilities cleanly.
**Depends on**: Phase 51
**Requirements**: UIX-01, UIX-02, UIX-03, UIX-04
**Success Criteria** (what must be TRUE):

  1. A user can choose the Windows media source (download ESD vs supply ISO) via radio buttons that toggle the relevant fields.
  2. Dense option sections (General Build Options, USB Drive Options, Post-Build Cleanup) are collapsible via expandable controls.
  3. ListView columns resize automatically to fit content/window width.
  4. A user can select a custom (BYO) app-list file path in the UI, exposing the existing `-UserAppListPath` backend capability.

**Plans**: TBD
**UI hint**: yes

### Phase 58: Hygiene & Robustness

**Goal**: Operational robustness and noise-reduction fixes — interrupted-run JSON recovery, working-directory-independent dirty marker, quieter tooling output, safe per-OEM cleanup, redundant-code removal, and an opt-in ESD retain — make builds more resilient and logs more readable.
**Depends on**: Phase 51
**Requirements**: HYG-01, HYG-02, HYG-03, HYG-04, HYG-05, HYG-06
**Success Criteria** (what must be TRUE):

  1. A corrupt `WinGetWin32Apps.json` from an interrupted prior run is backed up and rebuilt rather than aborting the build.
  2. The `dirty.txt` marker is created at an absolute path so the dirty-environment check works regardless of current working directory (ThreadJob/UI contexts).
  3. Robocopy and Format-Volume calls in the USB tooling and cache paths run without spamming console/log output, and redundant Images-directory creation is removed from `USBImagingToolCreator.ps1`.
  4. Per-OEM driver folder cleanup uses a shared helper that guards against deleting outside the drivers tree or the drivers root.
  5. A user can opt to retain downloaded ESD files for reuse across builds instead of having them deleted unconditionally.

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 51 → 52 → 53 → 54 → 55 → 56 → 57 → 58

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-44. Previous Milestones | v1.8.0-v1.10.0 | 133/133 | Complete | 2026-03-12 |
| 45-50. USB from Existing Components | v1.11.0 | 18/18 | Complete | 2026-06-26 |
| 51. Capture/Boot Correctness | v1.12.0 | 4/4 | Complete    | 2026-06-27 |
| 52. Driver-Grid UI Fixes | v1.12.0 | 0/TBD | Not started | - |
| 53. Driver Build/Deploy Correctness | v1.12.0 | 0/TBD | Not started | - |
| 54. Update Cache & Capture Naming | v1.12.0 | 0/TBD | Not started | - |
| 55. Device-Naming Foundation & Migrations | v1.12.0 | 0/TBD | Not started | - |
| 56. Device-Naming Consumers & Unattend | v1.12.0 | 0/TBD | Not started | - |
| 57. Shell-Independent UI | v1.12.0 | 0/TBD | Not started | - |
| 58. Hygiene & Robustness | v1.12.0 | 0/TBD | Not started | - |

---
*Roadmap created: 2026-03-12 for v1.11.0 USB from Existing Components*
*Last updated: 2026-06-25 — added v1.12.0 Upstream Sync (Phases 51-58), 30 requirements mapped, 100% coverage*
