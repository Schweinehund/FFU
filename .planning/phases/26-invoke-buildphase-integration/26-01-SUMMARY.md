---
phase: 26-invoke-buildphase-integration
plan: 01
subsystem: build-orchestration
tags: [error-handling, graceful-degradation, build-phases, critical-failures]

dependency-graph:
  requires:
    - FFU.Core (Invoke-BuildPhase, Clear-BuildErrors, Add-BuildError)
    - 23-02 (Invoke-BuildPhase implementation)
  provides:
    - Critical phase wrappers for VHDX creation, VM creation, FFU capture
    - Error aggregation initialization at build start
  affects:
    - All future build executions (error handling now via Invoke-BuildPhase)
    - 26-02 (non-critical phase wrappers already implemented)

tech-stack:
  added: []
  patterns:
    - Invoke-BuildPhase wrapper for critical failures
    - ThreadJob-safe guard patterns (InvokeCommand.GetCommand)
    - Error aggregation via Clear-BuildErrors/Add-BuildError

key-files:
  created: []
  modified:
    - FFUDevelopment/BuildFFUVM.ps1

decisions:
  - name: Critical vs Non-Critical designation
    value: VHDX creation, VM creation, FFU capture are Critical; drivers, USB, cleanup are Non-Critical
    rationale: Build cannot produce valid FFU without disk, VM, or capture; other phases can be skipped
  - name: VM startup in separate try/catch
    value: VM creation wrapped in Invoke-BuildPhase, startup remains in try/catch
    rationale: Distinct error messages for creation vs startup failures
  - name: Dual FFU capture wrappers
    value: Both InstallApps and non-InstallApps paths wrapped separately
    rationale: Each path has different parameters and progress messages

metrics:
  duration: 15m
  completed: 2026-01-24
  tests: 0
  pssa-errors: 0
---

# Phase 26 Plan 01: Critical Build Phases with Invoke-BuildPhase Summary

Critical build phases (VHDX/VHD creation, VM creation, FFU capture) wrapped with Invoke-BuildPhase -Critical $true to enable build halting on failure with error aggregation.

## Objective

Wrap critical build phases in BuildFFUVM.ps1 with Invoke-BuildPhase and initialize error aggregation at build start.

## Tasks Completed

| Task | Name | Commit | Key Changes |
|------|------|--------|-------------|
| 1 | Add error aggregation initialization | be56cad* | Clear-BuildErrors call after dirty.txt creation |
| 2 | Wrap VHDX/VHD creation (Critical) | 708da8e | Invoke-BuildPhase -Critical $true around New-ScratchVhd/New-ScratchVhdx |
| 3 | Wrap VM creation (Critical) | a7493d0 | Invoke-BuildPhase -Critical $true around VM configuration and CreateVM |
| 4 | Wrap FFU capture (Critical) | bce3611 | Invoke-BuildPhase -Critical $true around Optimize-FFUCaptureDrive and New-FFU |

*Note: Task 1 was completed as part of the 26-02 plan execution but satisfies 26-01 requirements.

## Technical Changes

### Error Aggregation Initialization (line 2301-2306)

```powershell
# Initialize build error aggregation (REL-BUILD-04)
if ($ExecutionContext.InvokeCommand.GetCommand('Clear-BuildErrors', 'Function')) {
    Clear-BuildErrors
    WriteLog "Build error collector initialized"
}
```

Uses ThreadJob-safe guard pattern to ensure error collector is reset at build start.

### VHDX/VHD Creation Phase (line 3720-3735)

```powershell
$diskCreationResult = Invoke-BuildPhase -PhaseName 'Disk Creation' -Critical $true -Action {
    if ($HypervisorType -eq 'VMware') {
        New-ScratchVhd -VhdPath $VHDXPath -SizeBytes $disksize -Dynamic
    }
    else {
        New-ScratchVhdx -VhdxPath $VHDXPath -SizeBytes $disksize -LogicalSectorSizeBytes $LogicalSectorSizeBytes
    }
}
$vhdxDisk = $diskCreationResult.Result
```

### VM Creation Phase (line 4495-4537)

```powershell
$vmCreationResult = Invoke-BuildPhase -PhaseName 'VM Creation' -Critical $true -Action {
    $vmConfig = New-VMConfiguration ...
    $vm = $script:HypervisorProvider.CreateVM($vmConfig)
    return $vm
}
$FFUVM = $vmCreationResult.Result
```

VM startup (cancellation checkpoint, VM start, polling) remains in separate try/catch for distinct error handling.

### FFU Capture Phase (lines 4865-4896 and 4900-4920)

Both InstallApps and non-InstallApps paths wrapped:

```powershell
$ffuCaptureResult = Invoke-BuildPhase -PhaseName 'FFU Capture' -Critical $true -Action {
    Optimize-FFUCaptureDrive -VhdxPath $VHDXPath
    New-FFU -VMName $FFUVM.Name ...
}
```

## Behavior Changes

| Scenario | Before | After |
|----------|--------|-------|
| VHDX creation fails | Catch block logs, cleanup, throw | Invoke-BuildPhase logs, adds to error aggregator, throws |
| VM creation fails | Catch block logs, cleanup, throw | Invoke-BuildPhase logs, adds to error aggregator, throws |
| FFU capture fails | Catch block logs, cleanup, throw | Invoke-BuildPhase logs, adds to error aggregator, VM cleanup, throws |
| Build errors | Scattered in log | Aggregated via Add-BuildError, summary at end |

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

| Check | Result |
|-------|--------|
| Clear-BuildErrors near dirty.txt | Pass - line 2303-2304 |
| VHDX uses Invoke-BuildPhase -Critical $true | Pass - line 3720 |
| VM uses Invoke-BuildPhase -Critical $true | Pass - line 4495 |
| FFU uses Invoke-BuildPhase -Critical $true | Pass - lines 4865 and 4900 |
| All use Result property | Pass - $diskCreationResult.Result, $vmCreationResult.Result |
| No duplicate try/catch | Pass - original try/catch updated for preparation failures |
| Script parses | Pass - no syntax errors |

## Success Criteria Met

- [x] Clear-BuildErrors called at build start with ThreadJob-safe guard
- [x] VHDX/VHD creation wrapped with Invoke-BuildPhase -Critical $true
- [x] VM creation wrapped with Invoke-BuildPhase -Critical $true
- [x] FFU capture wrapped with Invoke-BuildPhase -Critical $true
- [x] Result values captured and used correctly
- [x] Script parses without syntax errors

## Integration with 26-02

Plan 26-02 (already executed) wrapped non-critical phases:
- Driver Download: Invoke-BuildPhase -Critical $false (line 2565)
- Deployment Media Creation: Invoke-BuildPhase -Critical $false (line 4988)
- USB Drive Creation: Invoke-BuildPhase -Critical $false (line 5046)
- FFU Cleanup: Invoke-BuildPhase -Critical $false (line 5087)

Combined, all major build phases now use Invoke-BuildPhase for consistent error handling.

## Next Phase Readiness

Phase 26 complete. v1.9.1 Build Phase Integration milestone ready for verification and shipping.
