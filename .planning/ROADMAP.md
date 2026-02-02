# Roadmap: FFU Builder

## Milestones

- **v1.8.0 Codebase Health** - Phases 1-10 (shipped 2026-01-20)
- **v1.8.1 Bug Fixes** - Phases 11-13 (shipped 2026-01-20)
- **v1.8.3 VMware UI Settings** - Phase 14 (shipped 2026-01-21)
- **v1.9.0 Reliability Hardening** - Phases 15-25 (shipped 2026-01-24)
- **v1.9.1 Build Phase Integration** - Phase 26 (shipped 2026-01-24)
- **v1.9.2 Smart Configuration & Bug Fixes** - Phases 27-30 (shipped 2026-01-25) - [Archive](milestones/v1.9.2-ROADMAP.md)
- **v1.9.3 OEM Driver Bug Fixes** - Phases 31-33 (shipped 2026-01-27)
- **v1.10.0 Upstream Cherry-Pick** - Phases 34-43 (shipped 2026-02-02)

## Current Milestone

### v1.10.0 Upstream Cherry-Pick (Phases 34-43)

**Milestone Goal:** Selectively port upstream changes (60 commits, v2509.1→v2601.1preview) into our modular architecture — critical bug fixes, Winget improvements, driver enhancements, and deployment UX.

**Upstream Context:**
- Fork point: `UI_2510` (commit `1130a83`, Oct 22, 2025) = v2509.1preview
- Upstream HEAD: `upstream/UI` (commit `9d39ec8`, Jan 13, 2026) = v2601.1preview
- Strategy: Selective cherry-pick — keep our modular architecture

- [x] **Phase 34: Winget Bug Fixes and JSON Safety** - JSON corruption fix + MSI path quoting
- [x] **Phase 35: PPKG and xcopy Path Quoting** - Space handling in PPKG filenames
- [x] **Phase 36: CU Skip Logic and ESD BITS Downloads** - Version comparison + BITS transfer
- [x] **Phase 37: Winget App Ordering and Dependencies** - Enforce sequence + dedup dependencies
- [x] **Phase 38: SUBST Drive Mapping for Long Paths** - Virtual drive for >260 char paths
- [x] **Phase 39: Model Name Normalization and SystemID** - Brand dedup + BIOS extraction
- [x] **Phase 40: Dell Driver Refactoring (CatalogIndexPC)** - Efficient catalog selection
- [x] **Phase 41: Driver Matching, PE Copy, and UI Clarity** - Fallback, reliability, UI
- [x] **Phase 42: New OEM Manufacturers** - 8 new OEMs
- [x] **Phase 43: Deployment Improvements and Nice-to-Haves** - Multi-disk, empty drivers, delay

## Execution Waves (max 3 concurrent)

| Wave | Phases | Rationale |
|------|--------|-----------|
| 1 | 34, 35, 36 | Three independent bug fix phases |
| 2 | 37, 38, 39 | Winget (depends 34), SUBST (indep), model norm (indep) |
| 3 | 40, 43 | Dell refactor (depends 38,39), deploy (depends 35) |
| 4 | 41 | Driver matching (depends 39,40) |
| 5 | 42 | New OEMs (depends 39,41) — largest phase |

## Phases

<details>
<summary>v1.9.3 OEM Driver Bug Fixes (Phases 31-33) - SHIPPED 2026-01-27</summary>

- [x] Phase 31: HP Driver Fix (1/1 plans) - completed 2026-01-26
- [x] Phase 32: Dell Driver Fix (1/1 plans) - completed 2026-01-27
- [x] Phase 33: OEM Driver Logging (3/3 plans) - completed 2026-01-27

</details>

<details>
<summary>v1.9.2 Smart Configuration & Bug Fixes (Phases 27-30) - SHIPPED 2026-01-25</summary>

See [milestones/v1.9.2-ROADMAP.md](milestones/v1.9.2-ROADMAP.md) for details.

</details>

<details>
<summary>Earlier Milestones (Phases 1-26) - SHIPPED</summary>

See `.planning/milestones/` for archived milestone details.

</details>

## Phase Details

### Phase 34: Winget Bug Fixes and JSON Safety
**Goal**: Eliminate JSON corruption and path quoting failures in the Winget module for reliable concurrent app management
**Depends on**: Nothing (independent)
**Requirements**: BUGFIX-01, BUGFIX-03
**Success Criteria** (what must be TRUE):
  1. Parallel Winget app updates complete without JSON corruption when multiple apps write to WinGetWin32Apps.json simultaneously
  2. MSI installers with spaces in their paths execute successfully without "file not found" errors
  3. Pester tests verify mutex/file-lock protection on JSON writes and path quoting for MSI commands
**Research**: Complete (34-RESEARCH.md — mutex patterns, MSI quoting, concurrency pitfalls)
**Plans**: 3 plans
Plans:
- [x] 34-01-PLAN.md — Mutex-protected JSON writes for WinGetWin32Apps.json (BUGFIX-01)
- [x] 34-02-PLAN.md — EXE and MSI path quoting for spaces (BUGFIX-03)
- [x] 34-03-PLAN.md — Pester tests for mutex safety and path quoting
**Completed:** 2026-01-28 — Verified (6/6 must-haves)

### Phase 35: PPKG and xcopy Path Quoting
**Goal**: Fix provisioning package filename handling so PPKG files with spaces copy correctly during deployment
**Depends on**: Nothing (independent)
**Requirements**: BUGFIX-02
**Success Criteria** (what must be TRUE):
  1. PPKG files with spaces in filenames copy successfully via ApplyFFU.ps1
  2. Pester tests verify quoting behavior for paths containing spaces
**Note**: USBImagingToolCreator.ps1 was evaluated during research and has no PPKG copy operations — no changes needed
**Research**: Complete (35-RESEARCH.md — xcopy quoting, Invoke-Process, Copy-Item fallback)
**Plans**: 1 plan
Plans:
- [x] 35-01-PLAN.md — Fix PPKG xcopy quoting with Copy-Item fallback and Pester tests
**Completed:** 2026-01-28 — Verified (4/4 must-haves)

### Phase 36: CU Skip Logic and ESD BITS Downloads
**Goal**: Skip CU downloads when ESD version already matches/exceeds CU version, and switch ESD downloads to BITS transfer
**Depends on**: Nothing (independent)
**Requirements**: BUGFIX-04, DL-01
**Success Criteria** (what must be TRUE):
  1. Build skips CU download when ESD version equals or exceeds available CU
  2. Build log shows explicit message explaining CU skip with version comparison result
  3. ESD downloads use BITS transfer with progress logging
  4. Pester tests verify CU skip version comparison logic and BITS transfer integration
**Research**: Complete (36-RESEARCH.md — upstream CU skip logic, BITS priority, version comparison, VHDX cache)
**Plans**: 3 plans
Plans:
- [x] 36-01-PLAN.md — CU skip version comparison logic (Get-WindowsESDMetadata + Get-KBLink version + BuildFFUVM skip logic)
- [x] 36-02-PLAN.md — BITS priority configuration (Set-BitsTransferPriority + UI + config + env var propagation)
- [x] 36-03-PLAN.md — Pester tests for CU skip and BITS priority
**Completed:** 2026-01-28 — Verified (4/4 must-haves)

### Phase 37: Winget App Ordering and Dependencies
**Goal**: Enforce AppList.json installation order and resolve Win32 app dependencies with deduplication
**Depends on**: Phase 34 (both modify FFU.Common.Winget.psm1)
**Requirements**: WINGET-01, WINGET-02
**Success Criteria** (what must be TRUE):
  1. Apps install in the exact order specified in AppList.json
  2. Win32 app dependencies automatically resolved and deduplicated before installation
  3. Build log shows installation order and dependency insertions
  4. Pester tests verify ordering preservation and dependency resolution
**Research**: Complete (37-RESEARCH.md — upstream ordering/dependency commits, helper functions, reorder algorithm)
**Plans**: 3 plans
Plans:
- [x] 37-01-PLAN.md — Helper functions + Add-Win32SilentInstallCommand upgrade (mutex wrapper, atomic writes, dedup, metadata)
- [x] 37-02-PLAN.md — Dependency resolution (Add-Win32DependencySilentInstallCommands) + post-download reorder logic
- [x] 37-03-PLAN.md — Pester tests for ordering, dependencies, deduplication, and fail-safe behavior
**Completed:** 2026-01-28 — Verified (4/4 must-haves)

### Phase 38: SUBST Drive Mapping for Long Paths
**Goal**: Map a SUBST virtual drive during driver operations to prevent long path failures (>260 chars)
**Depends on**: Nothing (independent)
**Requirements**: PATH-01
**Success Criteria** (what must be TRUE):
  1. Driver extraction uses SUBST-mapped drive to keep paths below 260 characters
  2. SUBST mapping cleaned up after operations, even on failure
  3. Build log shows SUBST creation and removal
**Research**: Complete (38-RESEARCH.md — SUBST patterns, INF parsing, long-path prefix, upstream commits)
**Plans**: 2 plans
Plans:
- [x] 38-01-PLAN.md — SUBST helper functions + INF parsing improvements (Get-AvailableDriveLetter, New/Remove-DriverSubstMapping, auto-growing buffer, GUID normalization, -LiteralPath)
- [x] 38-02-PLAN.md — SUBST loop integration (Invoke-DismDriverInjectionWithSubstLoop, FFU.Imaging New-FFU, ApplyFFU.ps1 folder/WIM injection)
**Completed:** 2026-01-29 — Verified (12/12 must-haves)

### Phase 39: Model Name Normalization and SystemID Improvements
**Goal**: Prevent duplicate brand prefixes in model names and improve SystemID extraction for driver matching
**Depends on**: Nothing (independent)
**Requirements**: DRV-02, DRV-03
**Success Criteria** (what must be TRUE):
  1. Model names like "Dell Dell Latitude" normalized to "Dell Latitude"
  2. SystemID extraction works correctly for HP, Dell, and Lenovo
  3. Pester tests verify normalization and SystemID extraction
**Research**: Unlikely (straightforward regex and WMI patterns)
**Plans**: 2 plans
Plans:
- [x] 39-01-PLAN.md — Build-time model normalization (Dell GroupManifest Display CDATA) + SystemID/MachineType extraction in Update-DriverMappingJson
- [x] 39-02-PLAN.md — Deploy-time SystemID extraction (Get-SystemIdentityMetadata, Get-NormalizedManufacturer, enhanced matching) + Pester tests
**Completed:** 2026-01-29 — Verified (11/11 must-haves)

### Phase 40: Dell Driver Refactoring (CatalogIndexPC)
**Goal**: Refactor Dell driver download to use CatalogIndexPC.cab for more efficient driver selection
**Depends on**: Phase 38 (SUBST for deep paths), Phase 39 (model normalization)
**Requirements**: DRV-01
**Success Criteria** (what must be TRUE):
  1. Dell driver download uses CatalogIndexPC logic to narrow selection before full catalog download
  2. Dell driver download time reduced by avoiding unnecessary full catalog downloads
  3. Build log shows CatalogIndexPC selection process
  4. Pester tests verify CatalogIndexPC parsing and fallback
**Research**: Complete (40-RESEARCH.md — CatalogIndexPC XML schema, XmlReader patterns, fallback strategy)
**Plans**: 3 plans
Plans:
- [x] 40-01-PLAN.md — CatalogIndexPC infrastructure (3 internal helpers + Get-DellDrivers integration + FFUConstants)
- [x] 40-02-PLAN.md — UI-layer CatalogIndexPC + Drivers.json schema extension (SystemId/CabUrl)
- [x] 40-03-PLAN.md — Pester tests for CatalogIndexPC parsing, fallback, schema, caching (48 tests)
**Completed:** 2026-01-29 — Verified (26/26 must-haves)

### Phase 41: Driver Matching, PE Copy, and UI Clarity
**Goal**: Add generic driver fallback, improve PE driver copy reliability, and clarify driver source selection in UI
**Depends on**: Phase 39 (normalization), Phase 40 (Dell stable)
**Requirements**: DRV-05, DRV-06, DRV-07
**Success Criteria** (what must be TRUE):
  1. Generic/family-level fallback attempted when no exact model match found
  2. PE driver copy retries on transient failures with verification logging
  3. UI clearly indicates which driver source is active and why
  4. Pester tests verify fallback, retry, and UI state
**Research**: Unlikely (follows existing codebase patterns)
**Plans**: 3 plans
Plans:
- [x] 41-01-PLAN.md — Family-level driver fallback tier in ApplyFFU.ps1 (DRV-05)
- [x] 41-02-PLAN.md — PE driver injection retry with summary logging (DRV-06)
- [x] 41-03-PLAN.md — Driver source UI status label + Pester tests (DRV-07)
**Completed:** 2026-01-29 — Verified (7/7 must-haves)

### Phase 42: New OEM Manufacturers
**Goal**: Add driver support for 8 new OEM manufacturers
**Depends on**: Phase 39 (normalization), Phase 41 (generic fallback)
**Requirements**: DRV-04
**Success Criteria** (what must be TRUE):
  1. Each new OEM has functional driver download path (catalog, model selection, extraction)
  2. UI Make dropdown includes all 8 new manufacturers
  3. Structured [OEM] prefixed logging for all new manufacturers
  4. Pester tests per OEM verify catalog download and model parsing
**Research**: Complete (42-RESEARCH.md — 8 OEM catalogs, tier classification, extraction patterns)
**Plans**: 8 plans
Plans:
- [x] 42-07-PLAN.md — Infrastructure scaffolding (constants, ValidateSet, config, XAML, switch cases)
- [x] 42-01-PLAN.md — Acer driver support (direct XML catalog, dual CAB/ZIP extraction)
- [x] 42-02-PLAN.md — Dynabook driver support (CAB-to-XML catalog, graceful degradation)
- [x] 42-03-PLAN.md — Panasonic driver support (SCCM CAB + 13-model static fallback)
- [x] 42-04-PLAN.md — Samsung driver support (HTML portal + 20-model Galaxy Book fallback)
- [x] 42-05-PLAN.md — Fujitsu driver support (search input, HTML portal, mixed EXE/ZIP)
- [x] 42-06-PLAN.md — Tier 3 stubs (ASUS, MSI, Getac with manual download guidance)
- [x] 42-08-PLAN.md — Pester tests (87 tests across 3 files for all 8 OEMs + ValidateSet)
**Completed:** 2026-02-02 — Verified (all must-haves + export fix)

### Phase 43: Deployment Improvements and Nice-to-Haves
**Goal**: Improve deployment with multi-disk selection, empty driver handling, Security Platform delay, UniqueId USB, and skip-driver option
**Depends on**: Phase 35 (PPKG quoting — both modify ApplyFFU.ps1)
**Requirements**: DEPLOY-01, DEPLOY-02, DEPLOY-03, NICE-01, NICE-02
**Success Criteria** (what must be TRUE):
  1. Multiple disks present interactive selection menu
  2. Empty driver folders skipped with log message
  3. 30s delay in audit mode for Security Platform
  4. USB uses UniqueId instead of SerialNumber
  5. "Skip driver installation" option available
**Research**: Complete (43-RESEARCH.md -- ApplyFFU.ps1 patterns, Orchestrator.ps1 scope, audit mode placement)
**Plans**: 3 plans
Plans:
- [x] 43-01-PLAN.md -- ApplyFFU.ps1 deployment improvements (DEPLOY-01, DEPLOY-03, NICE-01, NICE-02)
- [x] 43-02-PLAN.md -- Orchestrator.ps1 Security Platform delay (DEPLOY-02)
- [x] 43-03-PLAN.md -- Pester tests for all Phase 43 requirements
**Completed:** 2026-02-02 — Verified (7/7 must-haves)

## Progress

| Milestone | Phases | Plans | Status | Completed |
|-----------|--------|-------|--------|-----------|
| v1.8.0 Codebase Health | 1-10 | 33 | Complete | 2026-01-20 |
| v1.8.1 Bug Fixes | 11-13 | 5 | Complete | 2026-01-20 |
| v1.8.3 VMware UI Settings | 14 | 2 | Complete | 2026-01-21 |
| v1.9.0 Reliability Hardening | 15-25 | 44 | Complete | 2026-01-24 |
| v1.9.1 Build Phase Integration | 26 | 3 | Complete | 2026-01-24 |
| v1.9.2 Smart Config & Bug Fixes | 27-30 | 10 | Complete | 2026-01-25 |
| v1.9.3 OEM Driver Bug Fixes | 31-33 | 5 | Complete | 2026-01-27 |
| v1.10.0 Upstream Cherry-Pick | 34-43 | 31 | Complete | 2026-02-02 |

**Total:** 43 phases, 133 plans (133 complete)

---
*Last updated: 2026-02-02 - Phase 43 complete, milestone v1.10.0 complete*
