---
phase: 19-ffu-media-reliability
plan: 02
subsystem: media
tags: [dism, adk, error-classification, remediation, wimount, troubleshooting]

# Dependency graph
requires:
  - phase: 18-ffu-imaging-reliability
    provides: Pattern for error classification with structured remediation
provides:
  - Get-ADKToolFailureRemediation function for DISM/ADK error classification
  - $script:DISMErrorRemediation table with 6 known error patterns
  - 42 Pester tests for error classification (REL-MED-02)
affects: [winpe-creation, dism-operations, adk-tools, error-handling]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Error classification via pattern matching (HResult codes)
    - Structured remediation output (ErrorCode, ErrorName, Message, Remediation, IsKnown)
    - Module-scoped lookup table for known error patterns
    - Generic fallback for unknown errors with original error preserved

key-files:
  created:
    - Tests/Unit/FFU.Media.Reliability.Tests.ps1
  modified:
    - FFUDevelopment/Modules/FFU.Media/FFU.Media.psm1
    - FFUDevelopment/Modules/FFU.Media/FFU.Media.psd1
    - FFUDevelopment/version.json

key-decisions:
  - "Error classification uses regex pattern matching for HResult codes"
  - "Unknown errors include original error message in remediation"
  - "ToolName parameter defaults to DISM but accepts custom values"
  - "Each known error has Code, ShortMessage, and detailed Remediation"

patterns-established:
  - "Use Get-ADKToolFailureRemediation to classify DISM/ADK errors"
  - "Error patterns are module-scoped for fast lookup"
  - "IsKnown boolean enables callers to handle known vs unknown errors differently"

# Metrics
duration: 6min
completed: 2026-01-24
---

# Phase 19 Plan 02: DISM/ADK Error Classification Summary

**DISM/ADK error classification with Get-ADKToolFailureRemediation returning structured remediation for 6 known error patterns**

## Performance

- **Duration:** 6 min
- **Started:** 2026-01-24T04:08:30Z
- **Completed:** 2026-01-24T04:14:30Z
- **Tasks:** 3
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- Created Get-ADKToolFailureRemediation function for DISM/ADK error classification
- $script:DISMErrorRemediation table with 6 known error patterns
- Each pattern includes specific, actionable remediation steps
- Unknown errors get generic troubleshooting guidance with original error preserved
- 42 Pester tests for error classification (REL-MED-02)
- FFU.Media updated to v1.5.0, main version v1.8.24

## Task Commits

Each task was committed atomically:

1. **Task 1: Add DISM error pattern table and function** - `fd95b91` (feat)
   - $script:DISMErrorRemediation with 6 known error patterns
   - Get-ADKToolFailureRemediation function with pattern matching
   - Function exported from FFU.Media module

2. **Task 2: Add REL-MED-02 Pester tests** - `ef3da77` (test)
   - 42 tests covering function export, output structure, all error patterns
   - Tests for ToolName customization, case sensitivity, partial matching

3. **Task 3: Update version and commit** - `a706fe0` (chore)
   - FFU.Media v1.5.0, main version v1.8.24
   - Release notes for REL-MED-02

## Functions Added

### Get-ADKToolFailureRemediation

Classifies DISM/ADK errors and returns remediation guidance.

```powershell
$result = Get-ADKToolFailureRemediation -ErrorMessage 'Error 0x800704DB: The specified service does not exist'
if ($result.IsKnown) {
    Write-Host "Known error: $($result.ErrorName)"
    Write-Host $result.Remediation
} else {
    Write-Host "Unknown error - generic troubleshooting"
}
```

**Parameters:**
- ErrorMessage: The error message to classify (mandatory)
- ToolName: Tool that generated the error (default: 'DISM')

**Output:**
- ErrorCode: Matched HResult code or 'Unknown'
- ErrorName: Classification name (ServiceNotExist, AccessDenied, etc.)
- Message: Brief description
- Remediation: Detailed fix steps
- ToolName: The tool that generated the error
- IsKnown: Boolean indicating if error matched a known pattern

## Known Error Patterns

| Code | Name | Description |
|------|------|-------------|
| 0x800704DB | ServiceNotExist | WIMMount service not available |
| 0x80070005 | AccessDenied | Access denied during DISM operation |
| 0x800F081F | SourceNotFound | Required source files not found |
| 0xc1510114 | MountCorrupted | WIM mount point is corrupted |
| 0x800700b7 | AlreadyMounted | WIM file is already mounted |
| 0x80070070 | DiskFull | Insufficient disk space |

## Files Modified

- `FFU.Media.psm1` - Added $script:DISMErrorRemediation table and Get-ADKToolFailureRemediation function
- `FFU.Media.psd1` - Version 1.5.0, added to FunctionsToExport, ReleaseNotes
- `FFU.Media.Reliability.Tests.ps1` - Created with 42 REL-MED-02 tests
- `version.json` - Main version 1.8.24, FFU.Media description update

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Error classification via pattern matching | Simple regex match for HResult codes is reliable |
| Unknown errors preserve original message | Enables debugging even for unrecognized errors |
| ToolName parameter with default | Allows reuse for oscdimg, copype, etc. |
| Module-scoped lookup table | Fast access without repeated parsing |

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- Error classification ready for integration into existing error handlers
- Get-ADKToolFailureRemediation can be called from:
  - Invoke-CopyPEWithRetry (on copype failures)
  - New-WinPEMediaNative (on Mount-WindowsImage failures)
  - New-PEMedia (on any DISM operation failures)
- Ready for next plan in Phase 19
- All success criteria met:
  - [x] Get-ADKToolFailureRemediation function exported from FFU.Media
  - [x] 6 known error patterns with specific remediation
  - [x] Unknown errors return generic guidance with original error text
  - [x] 20+ Pester tests pass for REL-MED-02 (42 tests)
  - [x] FFU.Media version bumped to 1.5.0
  - [x] Changes committed to git

---
*Phase: 19-ffu-media-reliability*
*Completed: 2026-01-24*
