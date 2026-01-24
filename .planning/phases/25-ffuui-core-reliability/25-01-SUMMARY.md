---
phase: 25-ffuui-core-reliability
plan: 01
subsystem: UI
tags: [ui-state, error-handling, wpf, state-management]

dependency-graph:
  requires:
    - FFU.Messaging (for Close-FFUMessagingContext)
  provides:
    - FFUUI.Core.StateRecovery module
    - Reset-FFUUIToIdle function
    - Save-FFUUIState function
    - Restore-FFUUIState function
  affects:
    - 25-02 (may use StateRecovery for error display integration)
    - 25-03 (may use StateRecovery for job failure recovery)

tech-stack:
  added: []
  patterns:
    - Centralized state management (single reset function)
    - Defensive null checking (graceful degradation)
    - ShouldProcess support (WhatIf/Confirm)

key-files:
  created:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.StateRecovery.psm1
    - Tests/Unit/FFUUI.Core.StateRecovery.Tests.ps1
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1
    - FFUDevelopment/BuildFFUVM_UI.ps1
    - FFUDevelopment/version.json

decisions:
  - name: Centralized reset function
    value: Single Reset-FFUUIToIdle handles all UI control resets
    rationale: Eliminates scattered ad-hoc reset code, ensures consistency
  - name: Defensive null checks
    value: All control access wrapped in null checks
    rationale: Handles partial UI state gracefully
  - name: ShouldProcess support
    value: Reset-FFUUIToIdle supports -WhatIf and -Confirm
    rationale: PSScriptAnalyzer compliance for state-changing functions

metrics:
  duration: 7m
  completed: 2026-01-24
  tests: 30
  pssa-errors: 0
---

# Phase 25 Plan 01: Centralized UI State Recovery Summary

Centralized UI state recovery via Reset-FFUUIToIdle function, replacing scattered ad-hoc reset code in BuildFFUVM_UI.ps1 error handling paths.

## Objective

Create centralized UI state recovery functions to ensure UI remains consistent after errors.

## Tasks Completed

| Task | Name | Commit | Key Changes |
|------|------|--------|-------------|
| 1 | Create FFUUI.Core.StateRecovery module | e92f570 | 3 functions: Reset-FFUUIToIdle, Save-FFUUIState, Restore-FFUUIState |
| 2 | Integrate StateRecovery into BuildFFUVM_UI.ps1 | d300267 | Replaced ad-hoc reset with centralized calls, manifest v0.0.14 |
| 3 | Create Pester tests for StateRecovery module | 459933a | 30 tests covering normal operation and edge cases |

## Technical Changes

### FFUUI.Core.StateRecovery Module

New module with three functions:

1. **Reset-FFUUIToIdle** - Main reset function
   - Hides progress bar (Visibility = Collapsed, Value = 0)
   - Re-enables build button (IsEnabled = true, Content = "Build FFU")
   - Resets flags (isBuilding = false, isCleanupRunning = false)
   - Sets status text (customizable message, default "Ready")
   - Stops poll timer if running
   - Closes messaging context if exists
   - Clears currentBuildJob reference
   - All operations include null checks for defensive coding

2. **Save-FFUUIState** - Capture state for potential rollback
   - Returns hashtable with all relevant UI state
   - Useful before risky operations

3. **Restore-FFUUIState** - Restore from saved state
   - Applies saved state back to controls
   - Handles missing keys gracefully

### BuildFFUVM_UI.ps1 Integration

Replaced scattered reset code in two locations:

1. **Job completion error handler (line 817):**
   ```powershell
   Reset-FFUUIToIdle -State $script:uiState -StatusMessage "Build failed. Check log for details."
   ```

2. **Pre-job catch block (line 857):**
   ```powershell
   Reset-FFUUIToIdle -State $script:uiState -StatusMessage "Build failed to start."
   ```

This ensures consistent UI state after any error, whether during job setup or job execution.

## Test Coverage

30 Pester tests covering:
- Progress bar reset (visibility, value)
- Build button reset (enabled, content)
- Flag reset (isBuilding, isCleanupRunning)
- Status text (custom message, default)
- Poll timer handling (stop, null)
- Messaging context cleanup
- Null control handling (defensive coding)
- Save/restore cycle
- Integration scenarios

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed PSScriptAnalyzer warnings**
- **Found during:** Task 3 verification
- **Issue:** Empty catch blocks and missing ShouldProcess support
- **Fix:** Added Write-Verbose to catch blocks, added SupportsShouldProcess to Reset-FFUUIToIdle
- **Files modified:** FFUDevelopment/FFUUI.Core/FFUUI.Core.StateRecovery.psm1
- **Commit:** 459933a

## Version Updates

| Component | Old Version | New Version | Change |
|-----------|-------------|-------------|--------|
| FFUUI.Core | 0.0.13 | 0.0.15 | State recovery + external ErrorDisplay |
| FFU Builder | 1.8.36 | 1.8.37 | PATCH for module update |

## Verification Results

| Check | Result |
|-------|--------|
| Module imports | Pass - FFUUI.Core imports cleanly |
| Functions exported | Pass - Reset-FFUUIToIdle, Save-FFUUIState, Restore-FFUUIState |
| Pester tests | Pass - 30/30 tests |
| PSScriptAnalyzer | Pass - 0 warnings/errors |
| Integration check | Pass - Reset-FFUUIToIdle used 3 times in BuildFFUVM_UI.ps1 |

## Success Criteria Met

- [x] FFUUI.Core.StateRecovery.psm1 exists with 3 exported functions
- [x] Reset-FFUUIToIdle handles all UI control resets in one call
- [x] BuildFFUVM_UI.ps1 uses Reset-FFUUIToIdle in error handling paths
- [x] FFUUI.Core.psd1 updated with StateRecovery in NestedModules
- [x] 30 Pester tests pass covering normal and edge cases
- [x] No PSScriptAnalyzer errors

## Next Phase Readiness

Ready for 25-02 (Structured Error Display) which may integrate with StateRecovery for error display + UI reset sequences.
