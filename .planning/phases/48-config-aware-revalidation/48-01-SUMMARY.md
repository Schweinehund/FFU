---
phase: 48-config-aware-revalidation
plan: 01
subsystem: ui
tags: [wpf, powershell, dashboard, diagnostics, revalidation]

# Dependency graph
requires:
  - phase: 46-dashboard-foundation
    provides: FFUUI.Core.Dashboard module with 10 core functions
  - phase: 47-hypervisor-conditional-logic-auto-remediation
    provides: FFU.Preflight conditional execution logic for hypervisor checks
provides:
  - Export-DashboardDiagnostics function for support-friendly diagnostics reports
  - Get-HypervisorDependentChecks function identifying hypervisor-specific checks
  - Set-CategoryDimmed function for visual transition states during revalidation
affects: [48-02, 48-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "StringBuilder for efficient diagnostics file generation"
    - "Static check categorization mapping for revalidation scope"
    - "Opacity + FontStyle manipulation for UI transition states"

key-files:
  created: []
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Dashboard.psm1

key-decisions:
  - "Diagnostics export returns file path (separation of concerns for testability)"
  - "Hypervisor check mapping derived from FFU.Preflight conditional logic (1/5/14 split)"
  - "Dimming uses 0.5 opacity + italic font for clear visual feedback"

patterns-established:
  - "Diagnostics file structure: header, system info, module versions, check results, footer"
  - "Check categorization hashtable: HyperV/VMware/Independent keys"
  - "Category dimming paired operations for dim/undim transitions"

# Metrics
duration: 2min
completed: 2026-02-06
---

# Phase 48 Plan 01: Dashboard Helper Functions Summary

**Three new FFUUI.Core.Dashboard functions enable diagnostics export, hypervisor-dependent check identification, and category dimming for Phase 48 revalidation features**

## Performance

- **Duration:** 2 min 13 sec
- **Started:** 2026-02-06T18:29:13Z
- **Completed:** 2026-02-06T18:31:26Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Export-DashboardDiagnostics generates timestamped .txt reports with system info, module versions, and check results
- Get-HypervisorDependentChecks provides static mapping of hypervisor-specific (1 Hyper-V, 5 VMware) vs independent (14) checks
- Set-CategoryDimmed manages visual transition states with 0.5 opacity and italic "(rechecking...)" text

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Export-DashboardDiagnostics, Get-HypervisorDependentChecks, Set-CategoryDimmed to Dashboard module** - `7a0262f` (feat)

**Plan metadata:** (deferred until STATE.md update)

## Files Created/Modified
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Dashboard.psm1` - Added 3 new functions (313 lines added), now exports 13 total functions

## Decisions Made

**1. Export-DashboardDiagnostics returns file path instead of showing MessageBox**
- Rationale: Separation of concerns for testability - function generates file, caller handles UI confirmation
- UI code will call the function and show MessageBox with returned path

**2. Get-HypervisorDependentChecks uses static mapping**
- Derived from FFU.Preflight.psm1 Invoke-FFUPreflight conditional execution logic
- Hypervisor category contains all hypervisor-dependent checks (1 Hyper-V, 5 VMware)
- 14 independent checks run regardless of hypervisor selection
- Simplifies revalidation scope determination

**3. Set-CategoryDimmed uses 0.5 opacity level**
- Standard WPF disabled state convention (50% opacity)
- Visible but clearly inactive
- Pairs with italic "(rechecking...)" text for clear user feedback

**4. FFUUI.Core.psd1 uses wildcard exports - no manifest changes needed**
- `FunctionsToExport = '*'` automatically exports all functions
- Task 2 verification confirmed all 3 new functions available after module import
- No manual manifest updates required

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation straightforward with existing PowerShell patterns.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 02 (XAML UI Elements):
- Export-DashboardDiagnostics ready to wire to "Export Diagnostics" button click handler
- Get-HypervisorDependentChecks ready to determine revalidation scope in hypervisor dropdown SelectionChanged handler
- Set-CategoryDimmed ready to call from Start-DashboardChecks for visual transitions

All functions tested and verified:
- 13 functions exported from FFUUI.Core.Dashboard (10 existing + 3 new)
- Get-HypervisorDependentChecks returns correct counts (1/5/14)
- Zero PSScriptAnalyzer errors
- Full module import successful

---
*Phase: 48-config-aware-revalidation*
*Completed: 2026-02-06*
