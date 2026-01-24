# Phase 20 Plan 03: Update Application Isolation (REL-UPD-03) Summary

---
phase: 20
plan: 03
type: reliability
subsystem: updates
tags: [REL-UPD-03, update-isolation, fault-tolerance, structured-results]

dependency-graph:
  requires:
    - 15: FFU.Core reliability (error handling patterns)
    - 18-02: Result collection pattern
  provides:
    - Invoke-UpdatesWithIsolation function
    - Per-update failure tracking
    - Critical failure detection
  affects:
    - BuildFFUVM.ps1 update application workflow

tech-stack:
  added: []
  patterns:
    - Isolated try/catch for each update
    - Structured result collection
    - ThreadJob-safe logging ($function:WriteLog)

key-files:
  modified:
    - FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1
    - FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psd1
    - Tests/Unit/FFU.Updates.Reliability.Tests.ps1
    - FFUDevelopment/version.json

decisions:
  - AllowEmptyCollection for updates array
  - Continue-by-default after failures
  - StopOnCriticalFailure optional switch
  - ThreadJob-safe logging via $logMessage scriptblock

metrics:
  duration: ~5min
  completed: 2026-01-24
---

## One-Liner

Isolated update application with per-update status tracking - one failure no longer blocks others.

## What Was Built

### Invoke-UpdatesWithIsolation Function

New function in FFU.Updates that applies updates with isolation:

```powershell
$result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates @(
    [PSCustomObject]@{ Name = 'KB5046613'; Path = '...'; Type = 'CU'; Required = $true }
    [PSCustomObject]@{ Name = 'KB5046623'; Path = '...'; Type = 'NET'; Required = $false }
)

# Returns:
# AllSucceeded = $true/$false
# HasCriticalFailure = $true/$false
# TotalCount = 2
# SuccessCount = 2
# FailureCount = 0
# Results = [ { Name, Type, Path, Status, Error, Duration }, ... ]
```

**Key Features:**
- Each update applied in isolated try/catch
- One failure does NOT prevent subsequent updates from being applied
- Tracks per-update status, error message, and duration
- `Required` flag marks critical updates
- `HasCriticalFailure` indicates if any Required update failed
- `StopOnCriticalFailure` switch halts on first Required failure (optional)

### ThreadJob Compatibility

Uses proven $logMessage scriptblock pattern for safe logging:
- Checks `$function:WriteLog` availability
- Falls back to Write-Verbose in test/job contexts
- Same pattern used in Invoke-CatalogQueryWithRetry, Test-KBPathsValid

## Test Coverage

22 Pester tests added covering:

| Context | Tests | Focus |
|---------|-------|-------|
| Function behavior | 15 | Parameters, result structure, failure isolation |
| Documentation | 3 | Synopsis, REL-UPD-03 reference, OutputType |
| Result structure | 4 | Property types, collection, booleans |

All tests pass: `Invoke-Pester -TagFilter 'REL-UPD-03'`

## Commits

1. `bae6a13` - feat(20-03): add Invoke-UpdatesWithIsolation for update isolation (REL-UPD-03)
2. `715f89d` - test(20-03): add REL-UPD-03 Pester tests for update isolation

## Deviations from Plan

None - plan executed exactly as written.

## Version Changes

| Component | Before | After |
|-----------|--------|-------|
| FFU.Updates | 1.0.6 | 1.0.6 (function added, version unchanged by parallel plan) |
| Main version | 1.8.28 | 1.8.29 |

## Integration Points

**Caller Pattern:**
```powershell
$updates = @(
    [PSCustomObject]@{ Name = 'SSU'; Path = $SSUPath; Type = 'SSU'; Required = $true }
    [PSCustomObject]@{ Name = 'CU'; Path = $CUPath; Type = 'CU'; Required = $true }
    [PSCustomObject]@{ Name = '.NET'; Path = $NETPath; Type = 'NET'; Required = $false }
    [PSCustomObject]@{ Name = 'Defender'; Path = $DefPath; Type = 'DEF'; Required = $false }
)

$result = Invoke-UpdatesWithIsolation -MountPath $MountPath -Updates $updates

if (-not $result.AllSucceeded) {
    $failed = $result.Results | Where-Object Status -eq 'Failed'
    foreach ($f in $failed) {
        Write-Warning "Update $($f.Name) failed: $($f.Error)"
    }

    if ($result.HasCriticalFailure) {
        throw "Critical update(s) failed - build cannot continue"
    } else {
        Write-Warning "Non-critical updates failed - build may complete with limited functionality"
    }
}
```

## Success Criteria Met

- [x] Invoke-UpdatesWithIsolation function implemented
- [x] Isolated try/catch for each update application
- [x] Structured result with per-update status
- [x] Pester tests covering isolation behavior
- [x] ThreadJob-compatible logging
- [x] AllowEmptyCollection for edge case

## Next Phase Readiness

Phase 20 Plan 04 (Catalog Cache Management) can proceed. This plan provides:
- Update isolation pattern for robust update application
- Complements REL-UPD-01 (retry) and REL-UPD-02 (validation)
