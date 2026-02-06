---
phase: 48-config-aware-revalidation
plan: 03
subsystem: ui-dashboard
tags: [event-handlers, wpf, revalidation, diagnostics, state-management]

# Dependency graph
requires: [48-01, 48-02]
provides:
  - Hypervisor dropdown SelectionChanged handler for auto-revalidation
  - Export Diagnostics button click handler
  - Revalidation state tracking and visual transitions
  - Check result storage for diagnostics export
affects: [48-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GetNewClosure() for scriptblock handler scope capture"
    - "Cancel-and-restart pattern for in-progress job termination"
    - "State tracking with lastHypervisorSelection initialization guard"

key-files:
  created: []
  modified:
    - FFUDevelopment/BuildFFUVM_UI.ps1

key-decisions:
  - "Null guard on lastHypervisorSelection prevents initialization event firing"
  - "Cancel-and-restart cancels in-progress job before launching new check run"
  - "Build guard allows staleness tracking during builds but delays revalidation"
  - "Export button disabled during export to prevent double-click race conditions"

patterns-established:
  - "Revalidation triggers immediately on dropdown change with cancel-and-restart"
  - "Staleness banner appears immediately with em-dash visual separator"
  - "Dimming applied during revalidation, restored on completion or error"

# Metrics
duration: 4min
completed: 2026-02-06
---

# Phase 48 Plan 03: Event Handler Wiring & State Management Summary

**One-liner:** Wired hypervisor SelectionChanged auto-revalidation, Export Diagnostics handler, dimming transitions, and check result storage for config-aware dashboard behavior**

## Performance

- **Duration:** 4 min 12 sec
- **Started:** 2026-02-06T18:35:30Z
- **Completed:** 2026-02-06T18:39:42Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

### Task 1: Revalidation State Tracking & Dimming
- Initialize `dashboardCheckResults` hashtable for diagnostics export (CFG-03)
- Clear check results at start of each check run
- Detect revalidation via `resultsStale` flag and dim Hypervisor category
- Update summary banner to "Rechecking environment..." during revalidation
- Store individual check results with timestamp, category, status, message, remediation, durationMs
- Restore dimming and clear staleness on DASHBOARD_COMPLETE
- Disable build and export buttons during revalidation
- Handle dimming restoration on DASHBOARD_ERROR (error resilience)

### Task 2: SelectionChanged & Export Handlers
- Wire `cmbHypervisorType.Add_SelectionChanged` for auto-revalidation (CFG-01)
- Null guard on `lastHypervisorSelection` prevents initialization event
- Same-value guard prevents duplicate fires on WPF multi-fire events
- Build guard tracks staleness during builds, delays revalidation until build completes
- Cancel-and-restart pattern stops in-progress job before launching new check
- Show staleness banner immediately on hypervisor change
- Wire `btnExportDiagnostics.Add_Click` handler (CFG-03)
- Call `Export-DashboardDiagnostics` and show MessageBox with file path
- Disable button during export to prevent double-click
- Handle export errors with user-facing error dialog

## Task Commits

Each task was committed atomically:

1. **Task 1: Add revalidation state tracking and dimming logic** - `ee48b0d` (feat)
2. **Task 2: Add SelectionChanged and Export Diagnostics handlers** - `4de7085` (feat)

**Plan metadata:** (deferred until STATE.md update)

## Files Modified

- `FFUDevelopment/BuildFFUVM_UI.ps1` - Added 140 lines total
  - Task 1: 50 lines (state tracking, dimming, check result storage)
  - Task 2: 90 lines (SelectionChanged handler 46 lines, Export handler 36 lines, section comments)

## Decisions Made

**1. SelectionChanged Initialization Guard**
- Null check on `lastHypervisorSelection` skips first event fire during WPF initialization
- Prevents unwanted revalidation at app startup
- Tracks index to detect actual user changes vs programmatic changes

**2. Cancel-and-Restart Pattern**
- Stops in-progress job with `Stop-Job` + `Remove-Job` before launching new check
- Clears `currentDashboardJob` reference to prevent stale job accumulation
- Silently handles cleanup errors (job may already be completed)

**3. Build Guard Behavior**
- Detects `isBuilding` flag and skips revalidation during active build
- Still tracks staleness state for banner display when build completes
- Allows user to see "configuration changed" without disrupting build

**4. Export Button State Management**
- Disabled on Start-DashboardChecks (start of every check run)
- Enabled on DASHBOARD_COMPLETE (after first successful check)
- Disabled during export operation to prevent double-click race
- Always re-enabled in finally block for error resilience

**5. Dimming Scope**
- Only dims Hypervisor category (only category with hypervisor-dependent checks)
- Uses `Set-CategoryDimmed` function from Plan 48-01
- Opacity 0.5 + italic "(rechecking...)" text for clear visual feedback
- Restored on both DASHBOARD_COMPLETE and DASHBOARD_ERROR

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation straightforward with existing Phase 46/47 patterns.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready for Plan 48-04 (Testing & Versioning):**
- All CFG-01 (auto-revalidation), CFG-02 (staleness), CFG-03 (diagnostics) requirements implemented
- SelectionChanged handler with proper initialization/same-value guards
- Export handler with error handling and user feedback
- Dimming transitions working for revalidation visual feedback
- Check results stored for diagnostics export

**Integration Points Verified:**
- `Start-DashboardChecks` handles dimming on revalidation start
- `DASHBOARD_CHECK` handler stores results in `dashboardCheckResults`
- `DASHBOARD_COMPLETE` handler restores dimming and enables export button
- `DASHBOARD_ERROR` handler restores dimming on error
- `cmbHypervisorType.Add_SelectionChanged` triggers cancel-and-restart
- `btnExportDiagnostics.Add_Click` calls `Export-DashboardDiagnostics`

**Must-Haves Status (all implemented):**
- ✅ Changing hypervisor cancels in-progress check and restarts
- ✅ Hypervisor category dimmed at 0.5 opacity during revalidation
- ✅ Staleness banner appears immediately on change, disappears on complete
- ✅ Build button disabled during revalidation, re-enabled on completion
- ✅ Export Diagnostics launches function and shows confirmation MessageBox
- ✅ Export button disabled until first check completes
- ✅ SelectionChanged ignores initialization event
- ✅ Summary banner shows "Rechecking..." during revalidation
- ✅ Check results stored in dashboardCheckResults

## Technical Notes

**GetNewClosure() Pattern:**
- Both handlers use `.GetNewClosure()` to capture `$script:uiState` in closure scope
- Established pattern from Phase 47 button handlers
- Required for scriptblocks to access script-level variables in WPF event context

**Staleness Banner Text:**
- Uses Unicode em-dash (`u{2014}`) for visual consistency
- "Hypervisor selection changed — rechecking environment..."
- Clear, actionable message with no elapsed time (checks restart immediately)

**Job Cleanup:**
- `Stop-Job` + `Remove-Job` with `-Force -ErrorAction SilentlyContinue`
- Try-catch wrapper silently handles already-completed jobs
- Sets `currentDashboardJob` to `$null` to prevent reference leaks

**Button State Orchestration:**
- Export button: disabled on start, enabled after DASHBOARD_COMPLETE
- Build button: disabled on start (existing), re-enabled via `Update-BuildButtonState`
- Refresh button: disabled on start (existing), re-enabled on DASHBOARD_COMPLETE

---
*Phase: 48-config-aware-revalidation*
*Completed: 2026-02-06*
