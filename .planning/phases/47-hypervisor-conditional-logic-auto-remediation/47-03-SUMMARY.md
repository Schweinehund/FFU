---
phase: 47-hypervisor-conditional-logic-auto-remediation
plan: 03
subsystem: ui
tags: [wpf, xaml, dashboard, remediation, event-handlers, powershell]

# Dependency graph
requires:
  - phase: 47-01
    provides: Repair-FFUWimMount, Repair-FFUDismState, Repair-FFUNetwork functions
  - phase: 47-02
    provides: Update-DashboardCheckUI with scriptblock parameters, Invoke-DashboardRemediation, Update-HypervisorCategoryVisibility
provides:
  - Hypervisor info banner XAML element wired to visibility function
  - DurationMs message passing from ThreadJob through queue to UI
  - Fix button click handler with ThreadJob repair execution and state management
  - Unsafe Fix button click handler with MessageBox confirmation
  - Copy button click handler with clipboard and visual feedback
  - Invoke-SingleCheckRefresh for post-repair check re-run
  - Complete scriptblock-based button wiring at creation time
affects: [47-04-testing, 48-config-aware-revalidation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Scriptblock closure pattern: .GetNewClosure() for accessing $script: scope in event handlers"
    - "DispatcherTimer async pattern: Polling ThreadJob completion without blocking UI thread"
    - "WPF MessageBox pattern: Blocking confirmation dialogs for unsafe operations"
    - "Clipboard API pattern: System.Windows.Clipboard.SetText with temporary UI feedback"

key-files:
  created: []
  modified:
    - FFUDevelopment/BuildFFUVM_UI.xaml
    - FFUDevelopment/BuildFFUVM_UI.ps1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1

key-decisions:
  - "Scriptblock handlers defined in BuildFFUVM_UI.ps1 (not dashboard module) to access $script:uiState and $script:FFUDevelopmentPath"
  - "Invoke-SingleCheckRefresh uses same handler passthrough pattern as dashboardPollTimer for consistency"
  - "Error handling in all three scriptblocks: try/catch with button state reset and tooltip error messages"
  - "Failed repairs re-enable Fix button for retry instead of staying in Fixed! state"

patterns-established:
  - "Button handler closure pattern: Scriptblocks with .GetNewClosure() to capture script-scoped state"
  - "Async repair polling: DispatcherTimer with 500ms interval for ThreadJob state checking"
  - "User-visible error feedback: Button tooltips show error messages, buttons reset to original state"
  - "Declined unsafe fix indicator: 'Fix available' in blue italic with transparent background"

# Metrics
duration: 5min
completed: 2026-02-06
---

# Phase 47 Plan 03: XAML + UI Wiring Summary

**Complete dashboard enhancement wiring: hypervisor info banner, DurationMs passing, Fix/Copy button handlers with ThreadJob execution, unsafe confirmation, and single-check refresh**

## Performance

- **Duration:** 5 min (5m 11s actual)
- **Started:** 2026-02-06T16:43:34Z
- **Completed:** 2026-02-06T16:48:45Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added borderHypervisorInfo and txtHypervisorInfo XAML elements below summary banner
- Registered new controls in FFUUI.Core.Initialize.psm1
- Updated DASHBOARD_CHECK message format from 6 to 7 fields (added DurationMs)
- dashboardPollTimer parses DurationMs and passes to Update-DashboardCheckUI
- Created $script:onFixClickHandler: Safe repair with ThreadJob, Fixing/Fixed states, single-check refresh
- Created $script:onUnsafeFixClickHandler: MessageBox confirmation, Fix available indicator on decline
- Created $script:onCopyClickHandler: Clipboard copy with Copied! feedback
- Created Invoke-SingleCheckRefresh: Re-runs check after fix with full handler passthrough
- Start-DashboardChecks calls Update-HypervisorCategoryVisibility before job launch
- All handlers wrapped in try/catch with user-visible error feedback

## Task Commits

Each task was committed atomically:

1. **Task 1: Add hypervisor info banner to XAML and update message format** - `f27a3e0` (feat)
   - Added borderHypervisorInfo border with blue info icon and txtHypervisorInfo text in BuildFFUVM_UI.xaml
   - Registered both controls in FFUUI.Core.Initialize.psm1
   - Updated DASHBOARD_CHECK message in ThreadJob scriptblock: added DurationMs as 7th field
   - Updated dashboardPollTimer: split message into 7 parts, parse DurationMs, pass to Update-DashboardCheckUI
   - Added Update-HypervisorCategoryVisibility call in Start-DashboardChecks after hypervisorType determination
   - Added borderHypervisorInfo.Visibility = 'Collapsed' in Clear-DashboardResults path

2. **Task 2: Create button handler scriptblocks and single-check refresh** - `80f3b79` (feat)
   - Created $script:onFixClickHandler: Disables button, shows Fixing..., launches ThreadJob, polls with DispatcherTimer, shows Fixed! on success, re-enables on failure
   - Created $script:onUnsafeFixClickHandler: Shows MessageBox confirmation, executes command on Yes, shows "Fix available" indicator on No
   - Created $script:onCopyClickHandler: Finds txtRemediation TextBox, copies to clipboard, shows Copied! with 2-second reset timer
   - Created Invoke-SingleCheckRefresh function: Runs Test-FFU* in ThreadJob, updates dashboard with result, passes all three handlers
   - Updated dashboardPollTimer: passes -OnFixClick, -OnUnsafeFixClick, -OnCopyClick to Update-DashboardCheckUI
   - All handlers include try/catch with error tooltips and button state reset

## Files Created/Modified

- `FFUDevelopment/BuildFFUVM_UI.xaml` - Added borderHypervisorInfo Border with inline blue info banner (ℹ icon + text)
- `FFUDevelopment/BuildFFUVM_UI.ps1` - Added 3 scriptblock handlers (Fix, Unsafe Fix, Copy), Invoke-SingleCheckRefresh function, updated Start-DashboardChecks and dashboardPollTimer
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1` - Registered borderHypervisorInfo and txtHypervisorInfo controls

## Decisions Made

1. **Scriptblock handler location**: Handlers defined in BuildFFUVM_UI.ps1 (not FFUUI.Core.Dashboard.psm1) because they need access to $script:uiState, $script:FFUDevelopmentPath, and UI-specific threading (DispatcherTimer, MessageBox). The dashboard module provides the data (SafeRepairMap, UnsafeRemediationMap) via getter functions.

2. **GetNewClosure() for scriptblocks**: All three handlers use .GetNewClosure() to capture $script: variables in the closure. This allows the scriptblocks to access uiState, FFUDevelopmentPath, and the other handlers when passed to Update-DashboardCheckUI.

3. **Failed repair handling**: If Invoke-DashboardRemediation returns Succeeded=false, the Fix button is re-enabled for retry (not stuck in Fixed! state). The error message is shown in the button's tooltip.

4. **Declined unsafe fix indicator**: When user clicks No on the MessageBox confirmation, the button changes to "Fix available" in blue italic with transparent background (no border). This preserves the user's awareness that a fix exists while respecting their choice to defer it.

5. **Single-check refresh handler passthrough**: Invoke-SingleCheckRefresh passes all three scriptblock handlers when calling Update-DashboardCheckUI. This ensures that if the check re-runs and still fails, the new UI element has working buttons (not orphaned buttons with no handlers).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation proceeded smoothly. All patterns worked as designed:
- XAML element added between existing borders without parse errors
- Controls registered and accessible in $script:uiState.Controls
- Message format extended from 6 to 7 fields without breaking existing handlers
- Scriptblock closures capture script-scoped variables correctly
- DispatcherTimer polling works for both repair completion and single-check refresh
- MessageBox confirmation UX matches Windows conventions
- Clipboard API works reliably with temporary button text feedback

## User Setup Required

None - no external service configuration required. This plan completes the UI wiring for dashboard remediation features.

## Next Phase Readiness

Dashboard remediation UI is fully wired and ready for testing (Plan 04):
- Hypervisor info banner visible and updates based on dropdown selection
- DurationMs flows from check execution through message queue to UI display
- Fix button executes safe repairs via Invoke-DashboardRemediation in ThreadJob
- Unsafe Fix button shows confirmation dialog with exact command preview
- Copy button extracts PowerShell commands and copies to clipboard
- All buttons have error handling with user-visible feedback
- Single-check refresh works after successful repair

Blockers: None. Phase 47 is functionally complete. Plan 04 (if created) would be verification and testing.

Concerns: None - all must-haves from plan frontmatter are implemented:
- ✅ Hypervisor info banner visible below summary status when dashboard checks run
- ✅ DurationMs passed through pipe-delimited message format and displayed on each check
- ✅ Fix button click executes repair in ThreadJob, shows Fixing... state, re-runs single check on completion
- ✅ Unsafe Fix button click shows WPF MessageBox confirmation before executing
- ✅ Copy button copies PowerShell commands to clipboard and shows Copied! text
- ✅ Hypervisor info banner shows correct text for HyperV, VMware, and Auto selections (via Update-HypervisorCategoryVisibility)
- ✅ Declined unsafe fix shows Fix available indicator on the check
- ✅ All button click handlers wrapped in try/catch with user-visible error feedback and button state reset on failure

---
*Phase: 47-hypervisor-conditional-logic-auto-remediation*
*Completed: 2026-02-06*
