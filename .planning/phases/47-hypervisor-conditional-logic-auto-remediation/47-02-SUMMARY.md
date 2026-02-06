---
phase: 47-hypervisor-conditional-logic-auto-remediation
plan: 02
subsystem: ui
tags: [wpf, dashboard, remediation, powershell, ffuui-core]

# Dependency graph
requires:
  - phase: 46-dashboard-foundation
    provides: Dashboard UI infrastructure, Update-DashboardCheckUI function, category panels
provides:
  - Safe repair function mapping (WimMount, DISMState, DISMCleanup, Network)
  - Unsafe remediation mapping with confirmation details (HyperV)
  - Fix button rendering with inline green/amber buttons
  - Details expander with PowerShell command extraction and Copy button
  - Duration display appended to check messages
  - Hypervisor info banner visibility management
  - Scriptblock-based click handler wiring (no post-creation scanning)
affects: [47-03, 48-config-aware-revalidation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Scriptblock parameter injection for WPF event handler wiring at creation time"
    - "Regex-based remediation text parsing to extract PowerShell commands from FIX section"
    - "Safe vs unsafe repair classification via separate hashtable maps"

key-files:
  created: []
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Dashboard.psm1

key-decisions:
  - "Fix button wired at creation time via OnFixClick/OnUnsafeFixClick scriptblock parameters (eliminates post-creation button discovery)"
  - "Details expander shows extracted PowerShell commands in monospace TextBox with Copy button"
  - "ADK check explicitly excluded from SafeRepairMap (no auto-fix - requires manual installer)"
  - "Extract-PowerShellCommands returns full remediation text as fallback if regex parsing fails"

patterns-established:
  - "Safe repair map: check name -> repair function name (string) for dashboard lookup"
  - "Unsafe remediation map: check name -> confirmation details hashtable with Command, RequiresReboot, ConfirmMessage, SuccessMessage"
  - "Duration formatting: Format-CheckDuration converts milliseconds to ' (X.Xs)' with 1 decimal precision"
  - "PowerShell command extraction: Parse FIX section, filter indented lines (4+ spaces), skip comments"

# Metrics
duration: 8min
completed: 2026-02-06
---

# Phase 47 Plan 02: Dashboard Remediation UI Summary

**Dashboard module enhanced with Fix buttons for safe/unsafe repairs, Details expanders with copy-paste PowerShell commands, duration display (X.Xs), and hypervisor info banner management**

## Performance

- **Duration:** 8 min (7m 52s actual)
- **Started:** 2026-02-06T16:30:28Z
- **Completed:** 2026-02-06T16:38:19Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- Safe repair map (WimMount, DISMState, DISMCleanup, Network) and unsafe remediation map (HyperV with reboot confirmation) added to dashboard module
- Update-DashboardCheckUI creates inline Fix buttons (green for safe, amber for unsafe) wired via scriptblock parameters at creation time
- Details expander with monospace PowerShell command TextBox and Copy button for all failed checks
- Duration appended to every check message as "(1.2s)" format
- Update-HypervisorCategoryVisibility and Invoke-DashboardRemediation functions for info banner and repair execution
- Extract-PowerShellCommands helper parses FIX section from remediation text, returns executable command lines

## Task Commits

Each task was committed atomically:

1. **Task 1: Add repair/remediation mappings and helper functions** - `665d201` (feat)
   - SafeRepairMap: WimMount -> Repair-FFUWimMount, DISMState -> Repair-FFUDismState, DISMCleanup -> Invoke-FFUDISMCleanup, Network -> Repair-FFUNetwork
   - UnsafeRemediationMap: HyperV with confirmation message, command, reboot flag
   - Extract-PowerShellCommands: Regex-based FIX section parser
   - Format-CheckDuration: Convert milliseconds to "(X.Xs)" string

2. **Task 2: Enhance Update-DashboardCheckUI with Fix button, Details expander, duration, and scriptblock parameters** - `497acb9` (feat)
   - Added DurationMs, OnFixClick, OnUnsafeFixClick, OnCopyClick scriptblock parameters
   - Append duration to message via Format-CheckDuration
   - Create green Fix button for SafeRepairMap checks, amber Fix... button for UnsafeRemediationMap checks
   - Show "Fix available" indicator (blue italic) for previously declined unsafe fixes
   - Replace remediation Expander with Details expander containing monospace TextBox + Copy button
   - Wire all button handlers at creation time via scriptblock parameters
   - ADK check explicitly excluded from Fix button (not in SafeRepairMap)

3. **Task 3: Add Update-HypervisorCategoryVisibility and Invoke-DashboardRemediation, update exports** - `092463e` (feat)
   - Update-HypervisorCategoryVisibility: Manages info banner text ("Validating for: Hyper-V -- VMware checks skipped")
   - Invoke-DashboardRemediation: Executes safe repairs, tracks duration, handles DISMCleanup special case (FFUDevelopmentPath parameter)
   - Get-SafeRepairMap and Get-UnsafeRemediationMap: Expose script-scoped maps for BuildFFUVM_UI.ps1 click handler wiring
   - Updated Export-ModuleMember to include all 4 new public functions

**Regex fix:** `9438866` (fix) - Improved Extract-PowerShellCommands regex pattern to correctly capture commands after FIX section header, added PSScriptAnalyzer suppressions for internal helper function

## Files Created/Modified

- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Dashboard.psm1` - Enhanced with 4 new public functions (Update-HypervisorCategoryVisibility, Invoke-DashboardRemediation, Get-SafeRepairMap, Get-UnsafeRemediationMap), 2 internal helpers (Extract-PowerShellCommands, Format-CheckDuration), 2 script-scoped maps (SafeRepairMap, UnsafeRemediationMap), and enhanced Update-DashboardCheckUI with Fix button, Details expander, duration display, and scriptblock parameter wiring

## Decisions Made

1. **Scriptblock parameter injection for click handlers**: Fix, Fix..., and Copy buttons are wired at creation time via -OnFixClick, -OnUnsafeFixClick, -OnCopyClick parameters. This eliminates the need for post-creation button discovery/scanning by BuildFFUVM_UI.ps1 (Plan 03 will pass the scriptblocks when calling Update-DashboardCheckUI).

2. **ADK excluded from auto-fix**: ADK failures require manual installer execution (can't be scripted reliably). The check is intentionally NOT in SafeRepairMap, so no Fix button appears for ADK failures.

3. **Regex fallback behavior**: Extract-PowerShellCommands returns the full remediation text as a single-item array if regex parsing fails. This ensures the Details expander always has content to display, even for unexpected remediation formats.

4. **Duration precision**: Format-CheckDuration uses 1 decimal place (1.2s) instead of 2 decimals (1.23s) for cleaner display while maintaining sufficient precision for user transparency.

## Deviations from Plan

None - plan executed exactly as written.

Regex fix in commit 9438866 was a correction during verification (not a deviation from plan) - the initial regex pattern didn't match the actual New-FFURemediationBlock format because it expected text immediately after "=== FIX ===" but the actual format includes a header line ("Run these PowerShell commands (as Administrator):"). The fix changed the pattern from `'(?s)=== FIX ===.*?\n\n(.*?)'` to `'(?s)=== FIX ===\s+(.*?)'` to correctly capture the FIX section including the header.

## Issues Encountered

None - implementation proceeded smoothly. Verification tests confirmed all functionality working as expected:
- All 4 new functions exported and importable
- DurationMs parameter exists on Update-DashboardCheckUI
- SafeRepairMap contains expected 4 checks (WimMount, DISMState, DISMCleanup, Network)
- UnsafeRemediationMap contains HyperV with confirmation message and reboot flag
- Extract-PowerShellCommands correctly extracts 2 commands from sample remediation text
- No PSScriptAnalyzer errors (suppressions added for internal helper function)

## User Setup Required

None - no external service configuration required. This plan enhances the dashboard UI module only.

## Next Phase Readiness

Dashboard module is ready for Plan 03 (XAML + UI Wiring):
- All remediation UI logic functions implemented and exported
- SafeRepairMap and UnsafeRemediationMap accessible via getter functions
- Scriptblock parameter approach documented for Plan 03 click handler implementation
- Extract-PowerShellCommands verified with sample remediation text

Blockers: None. Plan 03 can proceed immediately.

Concerns: Plan 03 will need to:
1. Add borderHypervisorInfo and txtHypervisorInfo controls to XAML
2. Wire OnFixClick, OnUnsafeFixClick, OnCopyClick scriptblocks in BuildFFUVM_UI.ps1 Start-DashboardChecks function
3. Pass DurationMs from check results when calling Update-DashboardCheckUI
4. Call Update-HypervisorCategoryVisibility before starting checks

---
*Phase: 47-hypervisor-conditional-logic-auto-remediation*
*Completed: 2026-02-06*
