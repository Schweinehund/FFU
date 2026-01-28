---
phase: 34-winget-bug-fixes-and-json-safety
plan: 02
subsystem: app-management
tags: [winget, json, path-quoting, msi, exe, processinfo]

# Dependency graph
requires:
  - phase: 34-01
    provides: "Mutex protection for WinGetWin32Apps.json writes"
provides:
  - "Properly quoted EXE and MSI installer paths in WinGetWin32Apps.json"
  - "ProcessStartInfo-compatible path handling for apps with spaces in folder names"
affects: [34-03, deployment, app-installation]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Backtick-escaped quotes for ProcessStartInfo.FileName paths", ".Trim() for dynamic string building"]

key-files:
  created: []
  modified: ["FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1"]

key-decisions:
  - "Wrap EXE CommandLine paths in backtick-escaped quotes for ProcessStartInfo compatibility"
  - "Add .Trim() to MSI Arguments to handle empty silent switch edge case"

patterns-established:
  - "Path quoting pattern: Use backtick-escaped quotes (`\"`$var`\"``) for paths passed to ProcessStartInfo.FileName"
  - "String concatenation with .Trim() to handle optional trailing parameters"

# Metrics
duration: 2min
completed: 2026-01-28
---

# Phase 34 Plan 02: MSI Path Quoting Summary

**Fixed EXE and MSI installer paths with backtick-escaped quotes, eliminating "file not found" errors for app folders containing spaces**

## Performance

- **Duration:** 2 minutes 21 seconds
- **Started:** 2026-01-28T20:12:28Z
- **Completed:** 2026-01-28T20:14:49Z
- **Tasks:** 2 (1 implementation + 1 verification)
- **Files modified:** 1

## Accomplishments
- EXE installer paths properly quoted for ProcessStartInfo.FileName execution
- MSI installer paths properly quoted in msiexec Arguments with .Trim() for edge cases
- Default installer paths properly quoted for fallback scenarios
- Verified JSON serialization preserves quotes correctly

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix EXE and MSI path quoting in Add-Win32SilentInstallCommand** - `06e19a8` (fix)
2. **Task 2: Verify JSON serialization preserves quotes correctly** - No commit (verification-only task)

**Plan metadata:** Pending (to be committed with SUMMARY.md and STATE.md updates)

## Files Created/Modified
- `FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1` - Added backtick-escaped quotes to EXE, MSI, and default installer paths; added .Trim() to MSI Arguments

## Decisions Made

**Decision 1: Backtick-escaped quotes for all path types**
- **Rationale:** ProcessStartInfo.FileName requires quoted paths when they contain spaces. Using backtick-escaped quotes (`\"`$var`\"`) ensures the literal quote characters survive variable expansion and JSON serialization.

**Decision 2: .Trim() on MSI Arguments**
- **Rationale:** When $silentInstallSwitch is empty, the MSI Arguments string would have trailing whitespace. Adding .Trim() handles this edge case cleanly.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation was straightforward. The quoting pattern worked as expected with ProcessStartInfo and JSON serialization.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 34-03 (Pester tests for path quoting scenarios).

**Technical notes:**
- The quoting pattern is compatible with how Install-Win32Apps.ps1 uses ProcessStartInfo
- For EXE: FileName receives the quoted path directly
- For MSI: FileName = "msiexec", Arguments receives quoted path in /i parameter
- JSON serialization preserves the backtick-escaped quotes correctly

**No blockers or concerns.**

---
*Phase: 34-winget-bug-fixes-and-json-safety*
*Completed: 2026-01-28*
