# Roadmap: FFU Builder v1.11.0

## Overview

Transform FFU Builder's Home tab from placeholder text into a live pre-flight readiness dashboard, making Hyper-V optional when VMware is selected. The journey begins with formalizing in-flight DISM resilience patterns, establishes the dashboard UI infrastructure with auto-run validation on launch, adds conditional hypervisor logic with one-click auto-remediation, and concludes with config-aware revalidation for dynamic prerequisite checking.

## Milestones

- ✅ **v1.10.0 Upstream Cherry-Pick** - Phases 34-43 (shipped 2026-02-02)
- ✅ **Ad-hoc DISM Resilience** - Phase 44 (shipped 2026-02-02)
- 🚧 **v1.11.0 Readiness Dashboard & Optional Hyper-V** - Phases 45-48 (in progress)

## Phases

<details>
<summary>✅ Previous Milestones (Phases 1-44) - SHIPPED</summary>

**v1.8.0 Codebase Health:** Phases 1-10 (33 plans) — Tech debt cleanup, bug fixes, security hardening, performance optimization, test coverage, build management features

**v1.8.1 Bug Fixes:** Phases 11-13 (5 plans) — Windows Update preview filtering, VHDX drive letter stability

**v1.8.3 VMware UI Settings:** Phase 14 (2 plans) — VMware configuration UI

**v1.9.0 Reliability Hardening:** Phases 15-25 (44 plans) — Systematic reliability audit with comprehensive error handling

**v1.9.1 Build Phase Integration:** Phase 26 (3 plans) — Invoke-BuildPhase integration for graceful degradation

**v1.9.2 Smart Configuration & Bug Fixes:** Phases 27-30 (10 plans) — VM Host IP dropdown, Apps.iso staleness, disk estimation

**v1.9.3 OEM Driver Bug Fixes:** Phases 31-33 (5 plans) — HP/Dell driver fixes, structured logging

**v1.10.0 Upstream Cherry-Pick:** Phases 34-43 (31 plans) — 60 upstream commits, 8 new OEMs, Dell CatalogIndexPC, SUBST paths

**Ad-hoc DISM Resilience:** Phase 44 (1 plan) — Test-DismReady/Test-DismFunctional implementation

**Total:** 44 phases, 134 plans shipped

</details>

### 🚧 v1.11.0 Readiness Dashboard & Optional Hyper-V (In Progress)

**Milestone Goal:** Transform the Home tab into a pre-flight readiness dashboard and make Hyper-V optional when VMware is available.

**Phase Numbering:**
- Integer phases (45, 46, 47, 48): Planned milestone work
- Decimal phases (e.g., 45.1): Urgent insertions (marked with INSERTED)

---

- [ ] **Phase 45: DISM Resilience Formalization** - Integrate Test-DismReady/Test-DismFunctional into build pipeline
- [ ] **Phase 46: Dashboard Foundation** - Home tab with grouped pre-flight checks and auto-run on launch
- [ ] **Phase 47: Hypervisor Conditional Logic & Auto-Remediation** - Optional Hyper-V with one-click fixes
- [ ] **Phase 48: Config-Aware Revalidation** - Auto-refresh on hypervisor change with staleness detection

## Phase Details

### Phase 45: DISM Resilience Formalization
**Goal**: Build pipeline validates DISM health before all image operations and detects degradation early to prevent cascading failures.

**Depends on**: Nothing (first phase)

**Requirements**: DISM-01, DISM-02, DISM-03

**Success Criteria** (what must be TRUE):
1. Build pipeline calls Test-DismReady before every Mount-WindowsImage and Add-WindowsPackage operation
2. Build pipeline calls Test-DismFunctional after each KB install to detect service degradation
3. Build pipeline skips non-critical DISM operations (WinSxS cleanup) when WIMMount service is broken rather than hanging
4. All DISM operations log clear actionable errors when validation fails
5. User sees "DISM service unavailable - remediation required" messages instead of cryptic 0x800704db errors

**Plans**: TBD

Plans:
- [ ] 45-01: TBD during planning

---

### Phase 46: Dashboard Foundation
**Goal**: Home tab displays live pre-flight validation results with grouped status indicators, auto-running on launch without blocking the UI.

**Depends on**: Phase 45

**Requirements**: DASH-01, DASH-02, DASH-03, DASH-04, DASH-05, DASH-06, DASH-07, DASH-08

**Success Criteria** (what must be TRUE):
1. User sees Home tab with grouped pre-flight checks organized by category (System, Hypervisor, Build Tools, Network, Optimization)
2. Each check displays visual status indicator (pass/fail/warning) with color coding (green/yellow/red)
3. Dashboard automatically runs all checks on application launch in background without blocking UI
4. User can click Refresh button to re-run all checks (button is disabled during active builds)
5. Dashboard shows summary status at top ("Ready to Build" or "3 Critical Issues, 2 Warnings")
6. Failed checks display actionable error messages with remediation guidance from FFU.Preflight
7. Dashboard shows progress indication while checks are running (indeterminate progress bar with current check name)
8. Build button is disabled when any critical check fails; non-critical warnings show confirmation dialog

**Plans**: TBD

Plans:
- [ ] 46-01: TBD during planning

---

### Phase 47: Hypervisor Conditional Logic & Auto-Remediation
**Goal**: Hyper-V becomes optional when VMware is selected, and safe pre-flight failures get one-click auto-remediation.

**Depends on**: Phase 46

**Requirements**: HYP-01, HYP-02, HYP-03, HYP-04, HYP-05, REM-01, REM-02, REM-03, REM-04

**Success Criteria** (what must be TRUE):
1. Hyper-V pre-flight checks only execute when Hyper-V is the selected hypervisor in VM Settings
2. VMware pre-flight checks only execute when VMware is the selected hypervisor in VM Settings
3. Build is not blocked by missing Hyper-V when VMware is selected as the hypervisor
4. Dashboard visually hides irrelevant hypervisor checks (shows only selected hypervisor's category)
5. Dashboard displays clear skip message for non-selected hypervisor ("Hyper-V checks skipped — using VMware")
6. User can click a one-click fix button for safe issues (WIMMount repair, DISM cleanup, service restart)
7. Unsafe remediations (e.g., Enable Hyper-V) show a reboot confirmation dialog before executing
8. Failed checks display copy-paste PowerShell commands in a selectable textbox for manual remediation
9. Each completed check displays its duration ("Completed in 1.2s") for transparency

**Plans**: TBD

Plans:
- [ ] 47-01: TBD during planning

---

### Phase 48: Config-Aware Revalidation
**Goal**: Dashboard automatically re-runs relevant checks when hypervisor selection changes and provides diagnostic export capability.

**Depends on**: Phase 47

**Requirements**: CFG-01, CFG-02, CFG-03

**Success Criteria** (what must be TRUE):
1. Dashboard automatically re-runs relevant checks when the hypervisor selection changes in VM Settings
2. Dashboard displays a stale data indicator ("Last checked: 2 minutes ago") when results are older than the last config change
3. User can export all check results to a diagnostics text file for support scenarios
4. Exported diagnostics include check results, timestamps, system information, and remediation actions taken

**Plans**: TBD

Plans:
- [ ] 48-01: TBD during planning

---

## Progress

**Execution Order:**
Phases execute in numeric order: 45 → 46 → 47 → 48

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 45. DISM Resilience Formalization | v1.11.0 | 0/TBD | Not started | - |
| 46. Dashboard Foundation | v1.11.0 | 0/TBD | Not started | - |
| 47. Hypervisor Conditional Logic & Auto-Remediation | v1.11.0 | 0/TBD | Not started | - |
| 48. Config-Aware Revalidation | v1.11.0 | 0/TBD | Not started | - |

---
*Roadmap created: 2026-02-06 for milestone v1.11.0*
*Last updated: 2026-02-06*
