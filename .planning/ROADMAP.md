# Roadmap: FFU Builder

## Milestones

- **v1.8.0 Codebase Health** - Phases 1-10 (shipped 2026-01-20)
- **v1.8.1 Bug Fixes** - Phases 11-13 (shipped 2026-01-20)
- **v1.8.3 VMware UI Settings** - Phase 14 (shipped 2026-01-21)
- **v1.9.0 Reliability Hardening** - Phases 15-25 (shipped 2026-01-24)
- **v1.9.1 Build Phase Integration** - Phase 26 (shipped 2026-01-24)
- **v1.9.2 Smart Configuration & Bug Fixes** - Phases 27-30 (gap closure in progress)

## Phases

- [x] **Phase 27: Bug Fixes Consolidation** - Document and close committed bug fixes ✓
- [x] **Phase 28: VM Host IP Dropdown** - Network adapter enumeration and UI dropdown ✓
- [x] **Phase 29: Smart Apps.iso & Disk Estimation** - Content validation and space calculation ✓
- [x] **Phase 30: Wire VM Host IP Pre-flight Validation** - Integrate Test-FFUHostIPAddress into pre-flight pipeline ✓

## Phase Details

### v1.9.2 Smart Configuration & Bug Fixes (Gap Closure)

**Milestone Goal:** Improve UI intelligence for network configuration and optimize build efficiency with smart Apps.iso handling.

#### Phase 27: Bug Fixes Consolidation
**Goal**: Document and close the 5 bug fixes already committed this session
**Depends on**: Nothing (documentation phase)
**Requirements**: BUG-01, BUG-02, BUG-03, BUG-04, BUG-05
**Success Criteria** (what must be TRUE):
  1. All 5 bug fixes documented in CHANGELOG_FORK.md
  2. Debug files archived or cleaned up
  3. version.json updated with v1.9.2
**Research**: None (documentation only)
**Plans**: 2 plans

Plans:
- [x] 27-01-PLAN.md - Document bug fixes in CHANGELOG_FORK.md ✓
- [x] 27-02-PLAN.md - Archive debug files and update version.json ✓

#### Phase 28: VM Host IP Dropdown
**Goal**: Replace text field with smart dropdown showing network adapters with context
**Depends on**: Phase 27
**Requirements**: NET-01, NET-02, LOG-01 (partial)
**Success Criteria** (what must be TRUE):
  1. User sees dropdown with format `192.168.1.100 (Ethernet - Intel I219-V)`
  2. User can select "Custom" to enter IP manually
  3. VMware auto-selects best IP if none configured
  4. Pre-flight warns if configured IP not found on host
**Research**: Complete (28-RESEARCH.md)
**Plans**: 3 plans

Plans:
- [x] 28-01-PLAN.md — Network adapter enumeration function (Get-HostNetworkAdapters) ✓
- [x] 28-02-PLAN.md — UI dropdown implementation with Custom option ✓
- [x] 28-03-PLAN.md — Pre-flight validation and auto-selection logic ✓

#### Phase 29: Smart Apps.iso & Disk Estimation
**Goal**: Optimize Apps.iso rebuilds with content hashing and add disk space estimation
**Depends on**: Phase 27
**Requirements**: ISO-01, ISO-02, ISO-03, DISK-01, DISK-02, LOG-01 (partial)
**Success Criteria** (what must be TRUE):
  1. Apps.iso only rebuilds when content actually changed
  2. User sees clear log message explaining why rebuild occurred or was skipped
  3. Pre-flight shows estimated Apps.iso size and required disk space
  4. Build fails pre-flight if insufficient disk space
**Research**: Complete (29-RESEARCH.md)
**Plans**: 4 plans

Plans:
- [x] 29-01-PLAN.md — Content manifest/hash generation (New-AppsContentManifest, Get-AppsContentManifest) ✓
- [x] 29-02-PLAN.md — Smart rebuild logic with hash comparison (Test-AppsISOStaleness) ✓
- [x] 29-03-PLAN.md — Component-based disk space calculation (Get-AppsISODiskEstimate) ✓
- [x] 29-04-PLAN.md — Pre-flight disk space validation (Test-FFUAppsISODiskSpace, Pester tests) ✓

#### Phase 30: Wire VM Host IP Pre-flight Validation
**Goal**: Integrate Test-FFUHostIPAddress into the pre-flight pipeline to complete NET-02 requirement
**Depends on**: Phase 28 (function already exists)
**Requirements**: NET-02 (complete)
**Gap Closure**: Closes integration gap from v1.9.2-MILESTONE-AUDIT.md
**Success Criteria** (what must be TRUE):
  1. Invoke-FFUPreflight accepts VMHostIPAddress parameter
  2. Invoke-FFUPreflight calls Test-FFUHostIPAddress when VMware and IP configured
  3. BuildFFUVM.ps1 passes VMHostIPAddress to Invoke-FFUPreflight
  4. Pre-flight shows warning (not failure) when IP not found on host
**Research**: None (implementation path clear from audit)
**Plans**: 1 plan

Plans:
- [x] 30-01-PLAN.md — Wire Test-FFUHostIPAddress into Invoke-FFUPreflight and BuildFFUVM.ps1 ✓

## Progress

**Execution Order:** 27 -> 28 -> 29 -> 30

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 27. Bug Fixes Consolidation | 2/2 | Complete ✓ | 2026-01-25 |
| 28. VM Host IP Dropdown | 3/3 | Complete ✓ | 2026-01-25 |
| 29. Smart Apps.iso & Disk Estimation | 4/4 | Complete ✓ | 2026-01-25 |
| 30. Wire VM Host IP Pre-flight | 1/1 | Complete ✓ | 2026-01-25 |

---

<details>
<summary>v1.9.1 Build Phase Integration (Phase 26) - SHIPPED 2026-01-24</summary>

### Phase 26: Build Phase Integration
**Goal**: Wrap all BuildFFUVM.ps1 phases with Invoke-BuildPhase for graceful degradation
**Plans**: 3 plans

Plans:
- [x] 26-01: Critical Phases - VHDX, VM, FFU capture wrapped
- [x] 26-02: Non-Critical Phases - 4 phases wrapped with graceful degradation
- [x] 26-03: Pester Tests - 33 tests for phase integration

</details>

<details>
<summary>v1.9.0 Reliability Hardening (Phases 15-25) - SHIPPED 2026-01-24</summary>

See `.planning/milestones/v1.9.0-reliability-hardening.md` for details.
180+ commits, 11 phases, 44 plans.

</details>

<details>
<summary>v1.8.x Milestones (Phases 1-14) - SHIPPED</summary>

See `.planning/milestones/` for archived milestone details.

</details>

---
*Last updated: 2026-01-25 — All phases complete, milestone ready for audit*
