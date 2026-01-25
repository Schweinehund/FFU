# Roadmap: FFU Builder

## Milestones

- **v1.8.0 Codebase Health** - Phases 1-10 (shipped 2026-01-20)
- **v1.8.1 Bug Fixes** - Phases 11-13 (shipped 2026-01-20)
- **v1.8.3 VMware UI Settings** - Phase 14 (shipped 2026-01-21)
- **v1.9.0 Reliability Hardening** - Phases 15-25 (shipped 2026-01-24)
- **v1.9.1 Build Phase Integration** - Phase 26 (shipped 2026-01-24)
- **v1.9.2 Smart Configuration & Bug Fixes** - Phases 27-30 (shipped 2026-01-25) - [Archive](milestones/v1.9.2-ROADMAP.md)

## Next Milestone

*To be defined with `/gsd:discuss-milestone` and `/gsd:new-milestone`*

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

## Progress

| Milestone | Phases | Plans | Status | Completed |
|-----------|--------|-------|--------|-----------|
| v1.8.0 Codebase Health | 1-10 | 33 | Complete | 2026-01-20 |
| v1.8.1 Bug Fixes | 11-13 | 5 | Complete | 2026-01-20 |
| v1.8.3 VMware UI Settings | 14 | 2 | Complete | 2026-01-21 |
| v1.9.0 Reliability Hardening | 15-25 | 44 | Complete | 2026-01-24 |
| v1.9.1 Build Phase Integration | 26 | 3 | Complete | 2026-01-24 |
| v1.9.2 Smart Config & Bug Fixes | 27-30 | 10 | Complete | 2026-01-25 |

**Total:** 30 phases, 97 plans completed across 6 milestones

---
*Last updated: 2026-01-25 - v1.9.2 milestone shipped*
