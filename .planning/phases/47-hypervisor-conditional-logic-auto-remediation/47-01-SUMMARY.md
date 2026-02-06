---
phase: 47-hypervisor-conditional-logic-auto-remediation
plan: 01
subsystem: preflight
tags: [auto-remediation, repair-functions, dashboard, wimmount, dism, network, powershell]

# Dependency graph
requires:
  - phase: 46-dashboard-foundation
    provides: Dashboard UI infrastructure for displaying check results and Fix button
provides:
  - Repair-FFUWimMount: Standalone repair function for WIMMount filter driver issues
  - Repair-FFUDismState: Standalone repair wrapper for DISM RestoreHealth
  - Repair-FFUNetwork: Standalone repair for DNS cache clear + connectivity verification
  - Auto-remediation API: Consistent PSCustomObject return format (Succeeded, Message, DurationMs)
affects: [47-02-dashboard-fix-button, 47-03-check-repair-links, preflight-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Repair function pattern: [CmdletBinding()], [OutputType([PSCustomObject])], returns Succeeded/Message/DurationMs"
    - "Extracted repair logic: Proven strategies from existing Test-FFU* functions made independently callable"
    - "Dashboard-callable repairs: Functions designed for one-click remediation without test context"

key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1
    - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1

key-decisions:
  - "Extracted WIMMount repair logic from Test-FFUWimMount to avoid circular dependency in dashboard calls"
  - "Used proven 6-step repair sequence (registry, service, filter load) from existing auto-repair code"
  - "Standardized return format: PSCustomObject with Succeeded, Message, DurationMs for consistent dashboard handling"
  - "Network repair combines DNS cache clear with connectivity test (www.microsoft.com:443)"

patterns-established:
  - "Repair functions are self-contained: No Test-FFU* dependencies, can be called independently"
  - "Duration tracking: All repairs use Stopwatch for performance visibility in dashboard"
  - "Error handling: All operations wrapped in try/catch, never throw exceptions to caller"

# Metrics
duration: 4min
completed: 2026-02-06
---

# Phase 47 Plan 01: Auto-Remediation Repair Functions Summary

**Three standalone repair functions extracted from existing validation logic for dashboard one-click remediation with consistent PSCustomObject return format**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-06T16:28:24Z
- **Completed:** 2026-02-06T16:32:45Z
- **Tasks:** 2 (combined in single commit)
- **Files modified:** 2

## Accomplishments
- Created Repair-FFUWimMount extracting proven 6-step repair sequence from Test-FFUWimMount
- Created Repair-FFUDismState wrapper for DISM RestoreHealth operation
- Created Repair-FFUNetwork combining DNS cache clear with connectivity verification
- All functions return consistent PSCustomObject format for dashboard consumption

## Task Commits

Both tasks committed atomically:

1. **Tasks 1-2: Create and export repair functions** - `6950da4` (feat)

## Files Created/Modified
- `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` - Added three repair functions with proper comment-based help, [CmdletBinding()], [OutputType([PSCustomObject])]
- `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1` - Added Repair-FFUWimMount, Repair-FFUDismState, Repair-FFUNetwork to FunctionsToExport array

## Decisions Made

**Repair Logic Extraction Strategy:**
- Extracted WIMMount repair from Test-FFUWimMount lines 2120-2260 instead of calling Test-FFUWimMount
- Rationale: Avoid circular dependency when dashboard calls Repair-FFUWimMount which would then call Test-FFUWimMount
- Approach: Copy proven repair strategies (registry, service start via sc.exe, filter load via fltmc)

**Return Format Standardization:**
- All repair functions return PSCustomObject with exactly three properties: Succeeded (bool), Message (string), DurationMs (int)
- Rationale: Dashboard Fix button needs consistent format for success/failure handling
- Implementation: Stopwatch for duration tracking, descriptive messages including actions attempted

**Network Repair Scope:**
- Repair-FFUNetwork combines Clear-DnsClientCache with Test-NetConnection to www.microsoft.com:443
- Rationale: DNS cache issues are most common network problem, connectivity test verifies fix worked
- Limitation: Cannot fix adapter/routing issues, but provides clear failure message

## Deviations from Plan

None - plan executed exactly as written. All three repair functions implemented with proven strategies from existing code.

## Issues Encountered

None - extraction from existing Test-FFUWimMount repair logic was straightforward, all functions pass PSScriptAnalyzer validation.

## User Setup Required

None - no external service configuration required. Functions are server-side PowerShell operating on local system.

## Next Phase Readiness

**Ready for Plan 02 (Dashboard Fix Button Integration):**
- All three repair functions exported from FFU.Preflight module
- Consistent return format enables simple success/failure UI handling
- Functions are independently callable without validation context

**Ready for Plan 03 (Check-Repair Links):**
- Repair functions use same repair logic as Test-FFU* auto-remediation
- WIMMount repair proven to work from existing Test-FFUWimMount usage
- DISM and Network repairs use standard cmdlets (dism.exe, Clear-DnsClientCache, Test-NetConnection)

**Blockers:** None

**Concerns:** None - repairs use proven strategies from production code

---
*Phase: 47-hypervisor-conditional-logic-auto-remediation*
*Completed: 2026-02-06*
