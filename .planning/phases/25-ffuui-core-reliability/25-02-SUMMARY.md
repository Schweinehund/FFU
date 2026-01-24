---
phase: 25-ffuui-core-reliability
plan: 02
subsystem: ui-error-display
tags: [wpf, error-handling, messagebox, remediation, validation]

dependency-graph:
  requires: []
  provides: [structured-error-display, validation-error-display, remediation-formatting]
  affects: [BuildFFUVM_UI.ps1, FFUUI.Core.Handlers.psm1]

tech-stack:
  added: []
  patterns: [error-formatting, remediation-block-pattern]

key-files:
  created:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.ErrorDisplay.psm1
    - Tests/Unit/FFUUI.Core.ErrorDisplay.Tests.ps1
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1

decisions:
  - id: DEC-2502-01
    title: Plural function name for validation errors
    choice: Keep Show-FFUValidationErrors plural
    reason: Function handles multiple validation errors, plural noun is accurate
    alternatives: [Show-FFUValidationError singular]

  - id: DEC-2502-02
    title: Global variable for test mocking
    choice: Use InModuleScope for mocking instead of global variables
    reason: InModuleScope allows proper mocking of internal module functions
    alternatives: [Global variable capture, Mock at test file level]

  - id: DEC-2502-03
    title: Severity header format
    choice: Use [Severity] prefix in message body
    reason: Clear visual indicator of error severity level
    alternatives: [Icon only, No prefix, Custom symbols]

metrics:
  duration: 20m
  completed: 2026-01-24
---

# Phase 25 Plan 02: Structured Error Display Summary

Structured error display functions with severity, remediation guidance, and actionable messaging.

## Objective

Create FFUUI.Core.ErrorDisplay module to replace generic MessageBox errors with actionable error dialogs that tell the user what went wrong, why it happened, and what they can do to fix it.

## Completed Tasks

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Create FFUUI.Core.ErrorDisplay module | 38bf9d8 | FFUUI.Core.ErrorDisplay.psm1 |
| 2 | Update FFUUI.Core manifest | 57893b1 | FFUUI.Core.psd1 |
| 3 | Create Pester tests | caa4316 | FFUUI.Core.ErrorDisplay.Tests.ps1 |

## Technical Implementation

### Show-FFUError Function

Main error display function with structured parameters:

```powershell
Show-FFUError -Severity 'Error' -Title 'Build Failed' -Description 'DISM operation failed' `
    -Remediation @('Check disk space', 'Verify admin rights', 'Restart and retry') `
    -LogPath 'C:\FFUDevelopment\Logs\build.log' `
    -ErrorRecord $_ `
    -Details @{ 'Operation' = 'Mount-WindowsImage' }
```

**Message Format:**
```
[Error] Build Failed

DISM operation failed

--- DETAILS ---
  Operation: Mount-WindowsImage

=== WHAT TO DO ===
  1. Check disk space
  2. Verify admin rights
  3. Restart and retry

--- LOG FILE ---
Check log file: C:\FFUDevelopment\Logs\build.log

--- TECHNICAL DETAILS ---
Exception: Access denied
Stack Trace: at...
```

### Show-FFUValidationErrors Function

Validation-specific error display:

```powershell
Show-FFUValidationErrors -Errors @('Invalid path', 'Missing field') `
    -Warnings @('Deprecated option') `
    -ConfigPath 'C:\config.json'
```

**Message Format:**
```
The following errors were found:

  (X) Invalid path
  (X) Missing field

Additionally, the following warnings were found:

  (!) Deprecated option

Config file: C:\config.json
```

### MessageBox Icon Selection

| Severity | Icon | Use Case |
|----------|------|----------|
| Critical | Error | Build-blocking failures |
| Error | Error | Operation failures |
| Warning | Warning | Non-blocking issues |
| Info | Information | Informational messages |

## Deviations from Plan

None - plan executed exactly as written.

## Test Coverage

**45 Pester tests covering:**

- Module import and function exports (5 tests)
- Severity validation (5 tests)
- Message content (11 tests)
- MessageBox icon selection (4 tests)
- Validation error display (9 tests)
- Format-FFUErrorMessage (6 tests)
- Return values (2 tests)
- Severity header formatting (4 tests)

All tests use InModuleScope for proper mocking of internal Show-MessageBox function.

## Version Changes

| Component | Old Version | New Version | Notes |
|-----------|-------------|-------------|-------|
| FFUUI.Core | 0.0.14 | 0.0.15 | Added ErrorDisplay module |

## Verification Results

- Module imports without error
- Show-FFUError, Show-FFUValidationErrors exported
- 45/45 Pester tests pass
- PSScriptAnalyzer: 0 warnings/errors
- Message includes WHAT TO DO section

## Next Phase Readiness

**Ready for 25-03:** Background Job Communication Reliability
- ErrorDisplay module provides foundation for displaying job errors
- Remediation format consistent with FFU.Preflight patterns
- No blockers identified

## Files Created

1. **FFUUI.Core.ErrorDisplay.psm1** (417 lines)
   - Show-FFUError: Main structured error display
   - Show-FFUValidationErrors: Validation-specific display
   - Format-FFUErrorMessage: Internal message formatter
   - Show-MessageBox: Internal wrapper for mocking

2. **FFUUI.Core.ErrorDisplay.Tests.ps1** (528 lines)
   - Comprehensive test coverage
   - Uses InModuleScope for mocking
   - Tests all severity levels, message content, icons

## Addresses Requirements

- **REL-UI-04**: Error messages contain actionable information with remediation steps
- Consistent with FFU.Preflight remediation block pattern (New-FFURemediationBlock)
