# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-05)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** v1.11.0 Readiness Dashboard & Optional Hyper-V — Phase 47 complete, Phase 48 next

## Current Position

**Milestone:** v1.11.0 Readiness Dashboard & Optional Hyper-V
**Phase:** 48 of 48 (Config-Aware Revalidation)
**Plan:** 1 of 4
**Status:** In progress
**Last activity:** 2026-02-06 — Completed 48-01-PLAN.md (Dashboard Helper Functions)

Progress: [███████░░░] 75% (3/4 phases complete, Phase 48: 1/4 plans)

## Roadmap Summary

**v1.11.0 Phases:**
- Phase 45: DISM Resilience Formalization (3 requirements) ✅
- Phase 46: Dashboard Foundation (8 requirements) ✅
- Phase 47: Hypervisor Conditional Logic & Auto-Remediation (9 requirements) ✅
- Phase 48: Config-Aware Revalidation (3 requirements)

**Coverage:** 23/23 requirements mapped ✓

## Shipped Milestones

| Milestone | Status | Phases | Date |
|-----------|--------|--------|------|
| v1.8.0 Codebase Health | SHIPPED | 1-10 (33 plans) | 2026-01-20 |
| v1.8.1 Bug Fixes | SHIPPED | 11-13 (5 plans) | 2026-01-20 |
| v1.8.3 VMware UI Settings | SHIPPED | 14 (2 plans) | 2026-01-21 |
| v1.9.0 Reliability Hardening | SHIPPED | 15-25 (44 plans) | 2026-01-24 |
| v1.9.1 Build Phase Integration | SHIPPED | 26 (3 plans) | 2026-01-24 |
| v1.9.2 Smart Configuration & Bug Fixes | SHIPPED | 27-30 (10 plans) | 2026-01-25 |
| v1.9.3 OEM Driver Bug Fixes | SHIPPED | 31-33 (5 plans) | 2026-01-27 |
| v1.10.0 Upstream Cherry-Pick | SHIPPED | 34-43 (31 plans) | 2026-02-02 |
| Ad-hoc: DISM Resilience | SHIPPED | 44 (1 plan) | 2026-02-02 |

**Total:** 44 phases, 134 plans shipped across 9 milestones

## Decisions Log

Recent decisions affecting current work:

| Decision | Phase | Rationale |
|----------|-------|-----------|
| Export-DashboardDiagnostics returns path not MessageBox | 48-01 | Separation of concerns for testability - function generates file, caller handles UI confirmation |
| Get-HypervisorDependentChecks uses static mapping | 48-01 | Derived from FFU.Preflight conditional logic, simplifies revalidation scope (1 Hyper-V, 5 VMware, 14 independent) |
| Set-CategoryDimmed uses 0.5 opacity | 48-01 | Standard WPF disabled state convention (50% opacity) with italic "(rechecking...)" text |
| FFUUI.Core.psd1 uses wildcard exports | 48-01 | FunctionsToExport='*' automatically exports new functions, no manifest changes needed |
| Test coverage strategy for Phase 47 | 47-04 | Focus on testable business logic (maps, parsing, formatting), skip WPF-dependent UI tests, validate logic via underlying function tests |
| Version bump strategy Phase 47 | 47-04 | MINOR bumps for FFU.Preflight (1.7.0) and FFUUI.Core (0.2.0) due to new user-facing functions, PATCH bump for main (1.11.2) per versioning policy |
| Failed repair re-enables Fix button for retry | 47-03 | If Invoke-DashboardRemediation returns Succeeded=false, button resets to Fix state with error tooltip |
| GetNewClosure() for scriptblock handlers | 47-03 | Handlers need .GetNewClosure() to capture $script: scope variables in closure |
| Scriptblock handlers in BuildFFUVM_UI.ps1 not module | 47-03 | Handlers need access to $script:uiState, $script:FFUDevelopmentPath, and UI threading (DispatcherTimer, MessageBox) |
| Scriptblock parameter click handler wiring | 47-02 | Fix/Copy buttons wired at creation time via OnFixClick/OnUnsafeFixClick/OnCopyClick params (no post-creation scanning) |
| ADK excluded from auto-fix | 47-02 | ADK failures require manual installer - intentionally NOT in SafeRepairMap |
| Duration precision 1 decimal | 47-02 | Format-CheckDuration uses 1 decimal (1.2s) for cleaner display |
| Extracted repair logic to avoid circular deps | 47-01 | Repair-FFUWimMount copied from Test-FFUWimMount instead of calling it to avoid circular dependency |
| Standardized repair return format | 47-01 | PSCustomObject with Succeeded/Message/DurationMs for consistent dashboard handling |
| MINOR bump FFUUI.Core (0.0.20 -> 0.1.0) for dashboard | 46-05 | Dashboard adds 6 new functions and new UI submodule, warranting MINOR |
| PATCH bump main version (1.11.0 -> 1.11.1) | 46-05 | Per versioning policy, subcomponent change requires minimum PATCH |
| Mock PSCustomObject state for WPF-free testing | 46-04 | Test Update-BuildButtonState logic without WPF dispatcher using settable PSCustomObject properties |
| Pipe-delimited message format for dashboard | 46-03 | Structured data within FFU.Messaging string messages using `\|` delimiter |
| Separate dashboardPollTimer from build pollTimer | 46-03 | Independent operation of dashboard and build polling |
| Live per-check category summary updates | 46-03 | Immediate visual feedback as each check completes rather than batch at end |
| Five refresh re-enable code paths | 46-03 | Every build-completion path re-enables refresh button for robustness |
| Used actual FFU.Preflight check names in category map | 46-02 | VMwareBridgeConfig not VMwareBridgeConfiguration, Configuration not ConfigurationFile |
| Extended category map with 3 additional checks | 46-02 | AppsISODiskSpace, CaptureDiskSpace, DISMCleanup exist in FFU.Preflight |
| Kept FunctionsToExport wildcard pattern | 46-02 | Consistent with existing FFUUI.Core manifest, avoids breaking exports |
| Fixed MinimalExpanderNoHighlightStyle for Header binding | 46-01 | Style had hardcoded text; ContentPresenter needed for dashboard Expanders |
| Dashboard container is StackPanel not Grid | 46-01 | Simpler vertical flow for banner, progress, button, categories |
| Naming convention: exp/txt/pnl + Category + role | 46-01 | Consistent pattern for 5 dashboard categories |
| MINOR version bumps for both modules | 45-03 | Hard-stop behavior change and new WinPE validation features warrant MINOR bumps |
| Main version 1.11.0 (MINOR bump) | 45-03 | First version of v1.11.0 milestone, significant DISM resilience feature set |
| Critical/non-critical check gating | 46-03 | Block build on critical failures, confirm dialog on warnings, allow on all pass |
| Auto-check on launch + refresh | 46-03 | Start-DashboardChecks called before ShowDialog for immediate feedback |
| Auto-remediate safe fixes | 47 | Reduce friction for fixable issues — implemented via Fix button + Invoke-DashboardRemediation |

See PROJECT.md for full decision history.

## Blockers

None.

## Session Continuity

**Last session:** 2026-02-06T18:31:26Z
**Stopped at:** Completed 48-01-PLAN.md (Dashboard Helper Functions)
**Resume file:** None
**Next action:** Continue Phase 48 - Plan 02 (XAML UI Elements)

**Phase 46 Progress (COMPLETE):**
- ✅ 46-01: Home Tab Dashboard XAML Layout (4 min, 2 commits)
- ✅ 46-02: Dashboard Helper Functions (6 min, 2 commits)
- ✅ 46-03: Dashboard UI Wiring (6 min, 3 commits)
- ✅ 46-04: Dashboard Unit Tests (3 min, 1 commit)
- ✅ 46-05: Version Bump, Changelog, Verification (24 min, 1 commit)

**Phase 47 Progress (COMPLETE):**
- ✅ 47-01: Auto-Remediation Repair Functions (4 min, 2 commits)
- ✅ 47-02: Dashboard Remediation UI (8 min, 5 commits)
- ✅ 47-03: XAML + UI Wiring (5 min, 3 commits)
- ✅ 47-04: Testing, Versioning, Documentation (21 min, 3 commits)

**Phase 48 Progress:**
- ✅ 48-01: Dashboard Helper Functions (2 min, 1 commit)

---
*State updated: 2026-02-06 after Phase 48 Plan 01 (3 new dashboard functions for revalidation features)*
