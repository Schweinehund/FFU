---
phase: 23
plan: 01
subsystem: FFU.Core
tags: [error-handling, reliability, build-errors, aggregation]

dependency-graph:
  requires:
    - Phase 15 (FFU.Core Reliability) - cleanup registry pattern
  provides:
    - Build error aggregation functions for collecting all build failures
    - Error severity classification (Critical, Warning, Info)
    - Summary reporting for end-of-build diagnostics
  affects:
    - Phase 23 plans 02-04 (BuildFFUVM.ps1 integration)
    - UI error reporting improvements

tech-stack:
  added: []
  patterns:
    - ThreadJob-safe logging ($function:WriteLog fallback)
    - Script-scope List for error accumulation
    - PSCustomObject for structured error data

file-tracking:
  created:
    - Tests/Unit/FFU.Core.BuildErrors.Tests.ps1 (567 lines, 42 tests)
  modified:
    - FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1 (added 4 functions)
    - FFUDevelopment/Modules/FFU.Core/FFU.Core.psd1 (v1.0.21)
    - FFUDevelopment/version.json (v1.8.34)

decisions:
  - id: script-scope-collector
    context: "Where to store accumulated errors during build"
    choice: "Script-scope List[PSCustomObject] in FFU.Core"
    rationale: "Matches existing CleanupRegistry pattern, available across module functions"

  - id: three-severity-levels
    context: "How to classify error importance"
    choice: "Critical, Warning, Info"
    rationale: "Clear distinction between build blockers, potential issues, and informational items"

  - id: threadjob-safe-logging
    context: "How to log errors in ThreadJob contexts"
    choice: "$function:WriteLog check with Write-Verbose fallback"
    rationale: "Established pattern from FFU.Core v1.0.17-1.0.18"

metrics:
  duration: "15 minutes"
  completed: 2026-01-24
---

# Phase 23 Plan 01: Build Error Aggregation Summary

**One-liner:** Four FFU.Core functions (Add-BuildError, Get-BuildErrorSummary, Clear-BuildErrors, Write-BuildErrorSummary) for accumulating ALL build errors instead of failing on first.

## What Was Built

Implemented REL-BUILD-04 requirement for build error aggregation. Previously, builds would fail on the first error encountered. Now, errors can be collected throughout the entire build process and summarized at the end, allowing users to see all issues in a single run.

### Functions Added

| Function | Purpose |
|----------|---------|
| `Add-BuildError` | Accumulates errors with Phase, Message, Severity, Exception, Timestamp |
| `Get-BuildErrorSummary` | Returns summary with TotalCount, CriticalCount, WarningCount, InfoCount, HasCritical, Errors |
| `Clear-BuildErrors` | Resets collector for new builds |
| `Write-BuildErrorSummary` | Formats and logs summary with severity prefixes ([CRITICAL], [WARNING], [INFO]) |

### Error Data Structure

Each accumulated error contains:
- **Timestamp**: DateTime when error occurred
- **Phase**: Build phase name (e.g., 'DriverDownload', 'UpdatesDownload')
- **Message**: Descriptive error message
- **Severity**: Critical (build blocker), Warning (potential issue), or Info (informational)
- **Exception**: Optional original exception object

### Usage Pattern

```powershell
# During build phases
try {
    Download-Drivers
}
catch {
    Add-BuildError -Phase 'DriverDownload' -Message $_.Exception.Message -Severity Warning -Exception $_.Exception
    # Continue to next phase instead of stopping
}

# At build end
$summary = Get-BuildErrorSummary
Write-BuildErrorSummary -Summary $summary

if ($summary.HasCritical) {
    throw "Build failed with $($summary.CriticalCount) critical errors"
}
```

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 2e3f166 | feat | Add build error aggregation functions to FFU.Core |
| 7b3a9ac | test | Add 42 Pester tests for build error aggregation |
| d39caff | chore | Update FFU.Core v1.0.21 and main version 1.8.34 |

## Test Coverage

42 comprehensive Pester tests in `Tests/Unit/FFU.Core.BuildErrors.Tests.ps1`:

- **Add-BuildError**: Error entry properties, accumulation, parameter validation (13 tests)
- **Get-BuildErrorSummary**: Empty state, severity counting, HasCritical flag, Errors array (10 tests)
- **Clear-BuildErrors**: Clearing behavior, safety, state reset (4 tests)
- **Write-BuildErrorSummary**: Basic functionality, output formatting (9 tests)
- **Integration**: Real-world scenarios, multi-phase errors, decision making (6 tests)

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

Plan 23-02 (Phase Wrapper with Continue-on-Failure) can now use these error aggregation functions to implement graceful degradation:

```powershell
# In Invoke-BuildPhase wrapper
catch {
    Add-BuildError -Phase $PhaseName -Message $_.Exception.Message `
        -Severity $(if ($Critical) { 'Critical' } else { 'Warning' }) `
        -Exception $_.Exception

    if ($Critical) {
        throw  # Re-throw for trap handler
    }
    # Non-critical phases continue
}
```

### Blockers

None.

### Dependencies Met

- FFU.Core module available and tested
- Error aggregation pattern established
- ThreadJob-safe logging confirmed working
