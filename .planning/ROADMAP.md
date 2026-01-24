# Roadmap: FFU Builder

## Milestones

- v1.8.0 Codebase Health - Phases 1-10 (shipped 2026-01-20)
- v1.8.1 Bug Fixes - Phases 11-13 (shipped 2026-01-20)
- v1.8.3 VMware UI Settings - Phase 14 (shipped 2026-01-21)
- v1.9.0 Reliability Hardening - Phases 15-25 (shipped 2026-01-24)
- **v1.9.1 Build Phase Integration** - Phase 26 (in progress)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

### v1.9.1 Build Phase Integration

- [ ] **Phase 26: Invoke-BuildPhase Integration** - Wrap all BuildFFUVM.ps1 phases with graceful degradation

## Phase Details

### Phase 26: Invoke-BuildPhase Integration

**Goal**: Integrate Invoke-BuildPhase wrapper into BuildFFUVM.ps1 to enable full graceful degradation across all build phases
**Depends on**: Phase 23 (created Invoke-BuildPhase function)
**Requirements**: 4 requirements (INT-BUILD-01 through INT-BUILD-04)
**Success Criteria** (what must be TRUE):
  1. All build phases in BuildFFUVM.ps1 wrapped with Invoke-BuildPhase
  2. Non-critical phase failures (e.g., USB media creation) allow build to continue
  3. Critical phase failures (e.g., VM creation) halt build appropriately
  4. All errors from all phases aggregated in final build summary
**Research**: Not needed (function already exists and tested)
**Plans:** 3 plans

Plans:
- [ ] 26-01-PLAN.md - Critical phases + error aggregation initialization
- [ ] 26-02-PLAN.md - Non-critical phases (USB, deployment media, cleanup)
- [ ] 26-03-PLAN.md - Pester tests for phase integration

**Details:**
The Invoke-BuildPhase function was created in Phase 23 (23-02-PLAN.md) but was not integrated into BuildFFUVM.ps1 to wrap all build phases. This phase completes that integration to enable full graceful degradation.

Key integration points in BuildFFUVM.ps1:
- VM creation phase (critical)
- Disk creation phase (critical)
- Deployment media creation phase (non-critical)
- USB media creation phase (non-critical)
- FFU cleanup phase (non-critical)

## Progress

**Execution Order:**
Phase 26 is a focused single-phase milestone.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 26. Invoke-BuildPhase Integration | 0/3 | Planned | - |

---
*Created: 2026-01-24 for v1.9.1 Build Phase Integration*
