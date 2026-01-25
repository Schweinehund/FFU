# Roadmap: FFU Builder

## Milestones

- **v1.8.0 Codebase Health** - Phases 1-10 (shipped 2026-01-20)
- **v1.8.1 Bug Fixes** - Phases 11-13 (shipped 2026-01-20)
- **v1.8.3 VMware UI Settings** - Phase 14 (shipped 2026-01-21)
- **v1.9.0 Reliability Hardening** - Phases 15-25 (shipped 2026-01-24)
- **v1.9.1 Build Phase Integration** - Phase 26 (shipped 2026-01-24)
- **v1.9.2 Smart Configuration & Bug Fixes** - Phases 27-30 (shipped 2026-01-25) - [Archive](milestones/v1.9.2-ROADMAP.md)
- 🚧 **v1.9.3 OEM Driver Bug Fixes** - Phases 31-33 (in progress)

## Current Milestone

### 🚧 v1.9.3 OEM Driver Bug Fixes (Phases 31-33)

**Milestone Goal:** Fix HP and Dell OEM driver bugs and ensure all OEM driver operations use proper file logging.

- [ ] **Phase 31: HP Driver Fix** - Handle exit code 1168 gracefully with actionable logging
- [ ] **Phase 32: Dell Driver Fix** - Handle missing CatalogPC.xml with fallback and logging
- [ ] **Phase 33: OEM Driver Logging** - Audit all OEM driver paths for proper WriteLog usage

## Phases

<details>
<summary>v1.9.2 Smart Configuration & Bug Fixes (Phases 27-30) - SHIPPED 2026-01-25</summary>

- [x] Phase 27: Bug Fixes Consolidation (2/2 plans) - completed 2026-01-25
- [x] Phase 28: VM Host IP Dropdown (3/3 plans) - completed 2026-01-25
- [x] Phase 29: Smart Apps.iso & Disk Estimation (4/4 plans) - completed 2026-01-25
- [x] Phase 30: Wire VM Host IP Pre-flight (1/1 plan) - completed 2026-01-25

See [milestones/v1.9.2-ROADMAP.md](milestones/v1.9.2-ROADMAP.md) for details.

</details>

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

## Phase Details

### Phase 31: HP Driver Fix
**Goal**: HP driver extraction handles exit code 1168 gracefully without failing the build
**Depends on**: Nothing (independent fix)
**Requirements**: HP-01, HP-02, HP-03, HP-04
**Success Criteria** (what must be TRUE):
  1. HP driver extraction completes without failing the build when exit code 1168 occurs
  2. Build log shows specific exit code and remediation steps when HP extraction fails
  3. Pester tests verify exit code 1168 handling and actionable error messages
**Research**: Unlikely (known bug, known fix pattern)
**Plans**: TBD

### Phase 32: Dell Driver Fix
**Goal**: Dell driver download handles missing CatalogPC.xml without failing the build
**Depends on**: Nothing (independent fix)
**Requirements**: DELL-01, DELL-02, DELL-03, DELL-04
**Success Criteria** (what must be TRUE):
  1. Dell driver download completes without failing the build when CatalogPC.xml is missing
  2. Build log shows failure reason and fallback action taken for Dell catalog issues
  3. Pester tests verify CatalogPC.xml missing scenario and fallback behavior
**Research**: Unlikely (known bug, known fix pattern)
**Plans**: TBD

### Phase 33: OEM Driver Logging
**Goal**: All OEM driver operations use proper file logging (WriteLog) instead of console-only output
**Depends on**: Phase 31, Phase 32 (audits logging across fixed code paths)
**Requirements**: LOG-01, LOG-02, LOG-03, LOG-04, LOG-05, LOG-06
**Success Criteria** (what must be TRUE):
  1. OEM driver selection, download, extraction, and injection all log to FFUDevelopment.log via WriteLog
  2. All OEM driver error paths include actionable remediation messages in log output
  3. Pester tests verify logging goes through WriteLog, not Write-Host or direct console output
**Research**: Unlikely (audit and replace pattern)
**Plans**: TBD

## Progress

| Milestone | Phases | Plans | Status | Completed |
|-----------|--------|-------|--------|-----------|
| v1.8.0 Codebase Health | 1-10 | 33 | Complete | 2026-01-20 |
| v1.8.1 Bug Fixes | 11-13 | 5 | Complete | 2026-01-20 |
| v1.8.3 VMware UI Settings | 14 | 2 | Complete | 2026-01-21 |
| v1.9.0 Reliability Hardening | 15-25 | 44 | Complete | 2026-01-24 |
| v1.9.1 Build Phase Integration | 26 | 3 | Complete | 2026-01-24 |
| v1.9.2 Smart Config & Bug Fixes | 27-30 | 10 | Complete | 2026-01-25 |
| v1.9.3 OEM Driver Bug Fixes | 31-33 | TBD | In progress | - |

**Total:** 30 phases, 97 plans completed across 6 milestones + 3 new phases in progress

---
*Last updated: 2026-01-25 - v1.9.3 roadmap created*
