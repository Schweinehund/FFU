# Roadmap: FFU Builder

## Milestones

- ✅ **v1.8.0 Codebase Health** - Phases 1-10 (shipped 2026-01-20)
- ✅ **v1.8.1 Bug Fixes** - Phases 11-13 (shipped 2026-01-20)
- ✅ **v1.8.3 VMware UI Settings** - Phase 14 (shipped 2026-01-21)
- ✅ **v1.9.0 Reliability Hardening** - Phases 15-25 (shipped 2026-01-24)
- ✅ **v1.9.1 Build Phase Integration** - Phase 26 (shipped 2026-01-24)
- 🚧 **v1.9.2 Smart Configuration & Bug Fixes** - Phases 27-29 (in progress)

## Phases

- [ ] **Phase 27: Bug Fixes Consolidation** - Document and close committed bug fixes
- [ ] **Phase 28: VM Host IP Dropdown** - Network adapter enumeration and UI dropdown
- [ ] **Phase 29: Smart Apps.iso & Disk Estimation** - Content validation and space calculation

## Phase Details

### 🚧 v1.9.2 Smart Configuration & Bug Fixes (In Progress)

**Milestone Goal:** Improve UI intelligence for network configuration and optimize build efficiency with smart Apps.iso handling.

#### Phase 27: Bug Fixes Consolidation
**Goal**: Document and close the 5 bug fixes already committed this session
**Depends on**: Nothing (documentation phase)
**Requirements**: BUG-01, BUG-02, BUG-03, BUG-04, BUG-05
**Success Criteria** (what must be TRUE):
  1. All 5 bug fixes documented in CHANGELOG_FORK.md
  2. Debug files archived or cleaned up
  3. version.json updated with v1.9.2-bugfixes
**Research**: Unlikely (documentation only)
**Plans**: TBD (estimated 1-2)

Plans:
- [ ] 27-01: Document bug fixes and update changelog
- [ ] 27-02: Archive debug files and update version

#### Phase 28: VM Host IP Dropdown
**Goal**: Replace text field with smart dropdown showing network adapters with context
**Depends on**: Phase 27
**Requirements**: NET-01, NET-02, LOG-01 (partial)
**Success Criteria** (what must be TRUE):
  1. User sees dropdown with format `192.168.1.100 (Ethernet - Intel I219-V)`
  2. User can select "Custom" to enter IP manually
  3. VMware auto-selects best IP if none configured
  4. Pre-flight warns if configured IP not found on host
**Research**: Unlikely (uses existing Get-NetIPAddress patterns)
**Plans**: TBD (estimated 2-3)

Plans:
- [ ] 28-01: Network adapter enumeration function
- [ ] 28-02: UI dropdown implementation with Custom option
- [ ] 28-03: Pre-flight validation and auto-selection logic

#### Phase 29: Smart Apps.iso & Disk Estimation
**Goal**: Optimize Apps.iso rebuilds with content hashing and add disk space estimation
**Depends on**: Phase 27
**Requirements**: ISO-01, ISO-02, ISO-03, DISK-01, DISK-02, LOG-01 (partial)
**Success Criteria** (what must be TRUE):
  1. Apps.iso only rebuilds when content actually changed
  2. User sees clear log message explaining why rebuild occurred or was skipped
  3. Pre-flight shows estimated Apps.iso size and required disk space
  4. Build fails pre-flight if insufficient disk space
**Research**: Unlikely (extends existing staleness detection)
**Plans**: TBD (estimated 3-4)

Plans:
- [ ] 29-01: Content manifest/hash generation for Apps folder
- [ ] 29-02: Smart rebuild logic with hash comparison
- [ ] 29-03: Component-based disk space calculation
- [ ] 29-04: Pre-flight disk space validation and messaging

## Progress

**Execution Order:** 27 → 28 → 29

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 27. Bug Fixes Consolidation | 0/2 | Not started | - |
| 28. VM Host IP Dropdown | 0/3 | Not started | - |
| 29. Smart Apps.iso & Disk Estimation | 0/4 | Not started | - |

---

<details>
<summary>✅ v1.9.1 Build Phase Integration (Phase 26) - SHIPPED 2026-01-24</summary>

### Phase 26: Build Phase Integration
**Goal**: Wrap all BuildFFUVM.ps1 phases with Invoke-BuildPhase for graceful degradation
**Plans**: 3 plans

Plans:
- [x] 26-01: Critical Phases - VHDX, VM, FFU capture wrapped
- [x] 26-02: Non-Critical Phases - 4 phases wrapped with graceful degradation
- [x] 26-03: Pester Tests - 33 tests for phase integration

</details>

<details>
<summary>✅ v1.9.0 Reliability Hardening (Phases 15-25) - SHIPPED 2026-01-24</summary>

See `.planning/milestones/v1.9.0-reliability-hardening.md` for details.
180+ commits, 11 phases, 44 plans.

</details>

<details>
<summary>✅ v1.8.x Milestones (Phases 1-14) - SHIPPED</summary>

See `.planning/milestones/` for archived milestone details.

</details>

---
*Last updated: 2026-01-25 — v1.9.2 roadmap created*
