---
phase: 47-usb-mode-pipeline-entry
plan: "01"
subsystem: BuildFFUVM.ps1 pipeline integration
tags: [usb-mode, artifact-scanner, short-circuit, pipeline]
dependency_graph:
  requires: [Phase 46 - FFU.ArtifactScanner module]
  provides: [-USBOnlyMode switch, short-circuit pipeline entry]
  affects: [BuildFFUVM.ps1, Phase 48 UI, Phase 49 event wiring]
tech_stack:
  added: []
  patterns: [TDD (RED->GREEN), AST-based Pester tests, short-circuit pattern]
key_files:
  created:
    - Tests/Unit/USBOnlyMode.Tests.ps1
  modified:
    - FFUDevelopment/BuildFFUVM.ps1
decisions:
  - "Get-USBDrive (not Get-FFUUSBDrives) is the correct function name — returns tuple ($USBDrives, $USBDrivesCount)"
  - "Pre-existing test failure in BuildFFUVM.ParameterValidation.Tests.ps1 (Make ValidateSet) is out of scope — identical before and after changes"
  - "USBOnlyMode param placed as final param (after FFUFileLockRetryDelaySeconds) to minimize diff risk"
metrics:
  duration: "11 minutes"
  completed_date: "2026-03-20"
  tasks_completed: 2
  files_modified: 2
---

# Phase 47 Plan 01: USB Mode Pipeline Entry Summary

**One-liner:** `-USBOnlyMode switch with ArtifactScanner-driven short-circuit block that validates and populates all 14 $using: variables before calling New-DeploymentUSB`

## What Was Built

Added USB-only pipeline entry to BuildFFUVM.ps1 enabling USB deployment media creation from pre-existing build artifacts without running the 40+ minute full build pipeline.

### Changes Made

**FFUDevelopment/BuildFFUVM.ps1 (3 modifications):**

1. **Param block**: Added `[switch]$USBOnlyMode` as the final parameter. No default value expression, no `[FFUConstants]::` reference — ThreadJob parse-time safe.

2. **Module imports**: Added `FFU.ArtifactScanner` import with `-ErrorAction SilentlyContinue` (graceful fallback for PS5.1 full builds, same pattern as FFU.ConfigMigration).

3. **Short-circuit block** (USB-ONLY MODE SHORT-CIRCUIT section): Inserted between checkpoint resume detection block (end of `if (-not $Cleanup)`) and PRE-FLIGHT VALIDATION section. The block:
   - Verifies `Find-FFUArtifacts` is available (PS7 guard)
   - Calls `Find-FFUArtifacts -FFUDevelopmentPath $FFUDevelopmentPath`
   - Validates `$manifest.IsReady` (FFU + DeployISO required — BLOCKING)
   - Logs `$manifest.Warnings` (architecture mismatches — NON-BLOCKING)
   - Pre-validates ISO mountability with `Mount-DiskImage -ImagePath $deployISOPath -PassThru` (BLOCKING before USB writes — satisfies USB-01)
   - Populates all 14 `$using:` variables consumed by `New-DeploymentUSB`'s `ForEach-Object -Parallel` block
   - Calls `Get-USBDrive` (tuple destructure: `$USBDrives, $USBDrivesCount`)
   - Calls `New-DeploymentUSB -CopyFFU -FFUFilesToCopy $SelectedFFUFile`
   - Executes `return` — pre-flight/Hyper-V/ADK checks never execute

**Tests/Unit/USBOnlyMode.Tests.ps1 (new file):**

25 structural Pester 5.x tests covering:
- Parameter Declaration (3 tests): type, no default, no FFUConstants
- Module Import (1 test): SilentlyContinue pattern
- Short-Circuit Block Structure (8 tests): block present, Find-FFUArtifacts call, IsReady check, Mount-DiskImage, error messages, New-DeploymentUSB call, return
- Variable Population (12 tests): all copy gates, folder paths, DeployISO, BuildUSBDrive, SelectedFFUFile
- ThreadJob Parse Compatibility (1 test): zero parse errors

## Test Results

```
Tests Passed: 25, Failed: 0, Skipped: 0
```

All 25 new USBOnlyMode tests pass GREEN.

Pre-existing regression: `BuildFFUVM.ParameterValidation.Tests.ps1 "Make has ValidateSet for OEMs"` fails identically before and after changes (pre-existing, out of scope per deviation rules).

## $using: Variable Coverage (Complete Audit)

| Variable | Source in USBOnlyMode block |
|----------|---------------------------|
| `$PSScriptRoot` | Automatic PowerShell variable |
| `$LogFile` | Already set at line ~1587 |
| `$ISOMountPoint` | Set by New-DeploymentUSB itself (line 1398) |
| `$CopyFFU` | `-CopyFFU` switch passed to New-DeploymentUSB |
| `$SelectedFFUFile` | `@($manifest.FFUFiles | Where-Object Found)` |
| `$CopyDrivers` | `($manifest.Drivers.Status.ToString() -eq 'Found')` |
| `$DriversFolder` | `"$FFUDevelopmentPath\Drivers"` |
| `$CopyPPKG` | `@($manifest.PPKGFiles | Where-Object Found).Count -gt 0` |
| `$PPKGFolder` | `"$FFUDevelopmentPath\PPKG"` |
| `$CopyUnattend` | `@($manifest.UnattendFiles | Where-Object Found).Count -gt 0` |
| `$WindowsArch` | `$primaryFFU.Metadata.Architecture` (fallback: `'x64'`) |
| `$UnattendFolder` | `"$FFUDevelopmentPath\Unattend"` |
| `$CopyAutopilot` | `@($manifest.AutopilotFiles | Where-Object Found).Count -gt 0` |
| `$AutopilotFolder` | `"$FFUDevelopmentPath\Autopilot"` |

## Verification Results

| Check | Result |
|-------|--------|
| Parse (zero errors) | PASS |
| `[switch]$USBOnlyMode` in param block | PASS |
| `FFU.ArtifactScanner.*SilentlyContinue` import | PASS |
| `USBOnlyMode cannot proceed` error message | PASS |
| `ISO cannot be mounted` error message | PASS |
| All 25 Pester tests GREEN | PASS |

## Commits

| Commit | Description |
|--------|-------------|
| `fbea2ff` | test(47-01): add failing Pester test scaffold for USBOnlyMode |
| `ef87377` | feat(47-01): add -USBOnlyMode switch, ArtifactScanner import, and short-circuit block |

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written with one clarification:

**Clarification (not a deviation):** The plan referred to `Get-FFUUSBDrives` but the actual function in BuildFFUVM.ps1 is `Get-USBDrive` (returns tuple `$USBDrives, $USBDrivesCount`). Used the correct function name per code audit. The plan's Task 2 action section noted "Verify its exact return type by reading its definition" — done, and adjusted accordingly.

## Known Stubs

None. The USBOnlyMode block is fully wired: `Find-FFUArtifacts` → validation → variable population → `Get-USBDrive` → `New-DeploymentUSB`. No placeholder values flow to USB assembly.

## Self-Check: PASSED

All created/modified files exist and commits are present.
