---
phase: 23
plan: 02
subsystem: FFU.Core
tags: [phase-wrapper, graceful-degradation, reliability, error-handling]

dependency-graph:
  requires:
    - Phase 23-01 (Build Error Aggregation) - Add-BuildError for error collection
  provides:
    - Invoke-BuildPhase wrapper for consistent phase execution
    - Graceful degradation for non-critical phase failures
    - Pre-execution cancellation check integration
  affects:
    - Phase 23 plans 03-04 (BuildFFUVM.ps1 integration)
    - Any code wrapping build phases

tech-stack:
  added: []
  patterns:
    - ThreadJob-safe command availability check (InvokeCommand.GetCommand)
    - PSCustomObject for structured result
    - Severity-based error classification via Critical parameter

file-tracking:
  created:
    - Tests/Unit/FFU.Core.PhaseExecution.Tests.ps1 (487 lines, 43 tests)
  modified:
    - FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1 (added Invoke-BuildPhase)
    - FFUDevelopment/Modules/FFU.Core/FFU.Core.psd1 (v1.0.22)
    - FFUDevelopment/version.json (v1.8.35)

decisions:
  - id: critical-default-true
    context: "Default behavior for phase failures"
    choice: "Critical=true by default"
    rationale: "Safe default - phases fail the build unless explicitly marked non-critical"

  - id: invokecommand-getcommand
    context: "How to check function availability in ThreadJob"
    choice: "$ExecutionContext.InvokeCommand.GetCommand for function checks"
    rationale: "ThreadJob-safe pattern established in FFU.Core v1.0.18"

  - id: structured-result-object
    context: "What to return from phase execution"
    choice: "PSCustomObject with Success, Skipped, Cancelled, Error, Result"
    rationale: "Enables callers to inspect outcome and take appropriate action"

metrics:
  duration: "7 minutes"
  completed: 2026-01-24
---

# Phase 23 Plan 02: Phase Wrapper with Continue-on-Failure Summary

**One-liner:** Invoke-BuildPhase function wraps phase execution with critical/non-critical classification, enabling graceful degradation where USB/deployment media failures don't stop VHDX/FFU creation.

## What Was Built

Implemented REL-BUILD-01 requirement for phase-level error handling with graceful degradation. The Invoke-BuildPhase function wraps any build phase in consistent try/catch handling, with the ability to mark phases as non-critical to allow builds to continue despite failures in optional outputs.

### Function Added

| Function | Purpose |
|----------|---------|
| `Invoke-BuildPhase` | Wraps phase execution with cancellation check, error collection, and graceful degradation |

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PhaseName` | string | (required) | Display name for logging and error messages |
| `Action` | scriptblock | (required) | The phase logic to execute |
| `Critical` | bool | `$true` | When true, failure stops build; when false, logs warning and continues |
| `MessagingContext` | hashtable | `$null` | Optional UI messaging context for cancellation checks |

### Return Value

```powershell
[PSCustomObject]@{
    Success   = $false  # True if phase completed without error
    Skipped   = $false  # Reserved for future skip logic
    Cancelled = $false  # True if cancelled via UI
    Error     = $null   # Exception that caused failure
    Result    = $null   # Return value from Action scriptblock
}
```

### Usage Pattern

```powershell
# Critical phases (default) - failure stops build
Invoke-BuildPhase -PhaseName 'Create VHDX' -Action {
    New-VHD -Path $vhdxPath -SizeBytes 50GB
}

# Non-critical phases - failure logs warning but continues
$result = Invoke-BuildPhase -PhaseName 'Create USB Media' -Action {
    Create-USBDeploymentMedia -Path $usbPath
} -Critical $false

if (-not $result.Success) {
    Write-Output "USB creation skipped due to: $($result.Error.Message)"
}

# At build end, check for any critical failures
$summary = Get-BuildErrorSummary
if ($summary.HasCritical) {
    throw "Build failed with $($summary.CriticalCount) critical errors"
}
```

### Integration with Error Aggregation

Invoke-BuildPhase automatically calls Add-BuildError on failure:
- Critical=true failures are added with Severity='Critical'
- Critical=false failures are added with Severity='Warning'

This enables end-of-build summary reporting showing ALL issues encountered.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| ca96db7 | feat | Add Invoke-BuildPhase for graceful degradation |
| 0024b9c | test | Add 43 Pester tests for Invoke-BuildPhase |
| cebd9c6 | chore | Update FFU.Core v1.0.22 and main version 1.8.35 |

## Test Coverage

43 comprehensive Pester tests in `Tests/Unit/FFU.Core.PhaseExecution.Tests.ps1`:

- **Basic Execution**: Success path, result handling, null/array returns (8 tests)
- **Critical Phase Failures**: Throw behavior, error collector integration (6 tests)
- **Non-Critical Phase Failures**: No throw, graceful degradation (7 tests)
- **Mixed Phases**: Multiple phase error accumulation (3 tests)
- **Phase Naming**: Special characters, spaces in names (4 tests)
- **Result Object Structure**: Property validation (2 tests)
- **Integration**: Build error aggregation compatibility (3 tests)
- **Parameter Validation**: Required params, null handling (6 tests)
- **Exception Types**: Various .NET exception handling (3 tests)
- **Real-World Simulation**: Typical build scenario (1 test)

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

Plan 23-03 (Checkpoint Resume Integration) can now use Invoke-BuildPhase to wrap phases with checkpoint support:

```powershell
# Example: Wrapping driver download with checkpoint
$result = Invoke-BuildPhase -PhaseName 'Driver Download' -Action {
    $checkpoint = Get-BuildCheckpoint -Phase 'DriverDownload'
    if ($checkpoint) {
        Resume-DriverDownload -Checkpoint $checkpoint
    } else {
        Start-DriverDownload -Model $model
    }
} -Critical $false
```

### Blockers

None.

### Dependencies Met

- Invoke-BuildPhase exported from FFU.Core
- Integration with Add-BuildError confirmed working
- ThreadJob-safe patterns verified
- 43 Pester tests passing
