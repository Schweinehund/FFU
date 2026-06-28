---
phase: 52-driver-grid-ui-fixes
plan: "03"
subsystem: build-orchestrator
tags: [port, parameter-validation, dgrid-03, build-script]
dependency_graph:
  requires: ["52-02"]
  provides: ["DGRID-03 CopyDrivers validation throw in END block"]
  affects: ["FFUDevelopment/BuildFFUVM.ps1"]
tech_stack:
  added: []
  patterns: ["WriteLog + throw error pattern", "END-block post-config parameter validation"]
key_files:
  modified:
    - FFUDevelopment/BuildFFUVM.ps1
decisions:
  - "D-01: throw in CLI BuildFFUVM.ps1 (not a UI MessageBox) — guards both CLI and UI callers"
  - "D-02: placed in END block at line 2608 (after config load ~775) — sees config-merged effective values"
  - "D-03: guarded with -and -not $USBOnlyMode — prevents false rejection of valid USB-only builds"
  - "D-04: no UI MessageBox, no CopyDrivers checkbox grey-out added"
metrics:
  duration_minutes: 5
  completed: "2026-06-28"
  tasks_completed: 1
  files_modified: 1
---

# Phase 52 Plan 03: CopyDrivers Dependency Throw (DGRID-03) Summary

**One-liner:** Port dc801e9 upstream throw blocking CopyDrivers=true/BuildUSBDrive=false into BuildFFUVM.ps1 END block with USBOnlyMode guard, validating config-merged effective values.

## What Was Built

Inserted a 5-line CopyDrivers/BuildUSBDrive dependency validation block into `BuildFFUVM.ps1` at the `###PARAMETER VALIDATION` section in the END block (line 2608), immediately before the existing `#Validate drivers folder` block.

**Inserted block (lines 2608-2612):**
```powershell
#Validate CopyDrivers dependency on BuildUSBDrive
if ($CopyDrivers -and (-not $BuildUSBDrive) -and (-not $USBOnlyMode)) {
    WriteLog "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true"
    throw "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true. Please set -BuildUSBDrive to `$true and try again."
}
```

This covers both CLI users (direct invocation) and UI users (BuildFFUVM_UI.ps1 launches BuildFFUVM.ps1 as a background job).

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Insert CopyDrivers/BuildUSBDrive dependency throw (dc801e9, fork-adapted) | 8741ee8 | FFUDevelopment/BuildFFUVM.ps1 |

## Verification

**All 14 Test-Phase52DriverGridFixes.ps1 assertions PASS (exit 0):**
- DGRID-01: 3/3 assertions green (Invoke-ListViewSort filter-capture — prior plan)
- DGRID-02: 8/8 assertions green (select-all scope + save fix — prior plan)
- DGRID-03: 3/3 assertions green (throw wording, USBOnlyMode guard, line 2610 > 775)

**Script parse check:** `ParseFile` reports no errors.

## Deviations from Plan

None — plan executed exactly as written. The two fork adaptations (D-02: END block placement, D-03: USBOnlyMode guard) were pre-documented in CONTEXT.md and applied verbatim.

## Known Stubs

None. The throw is fully functional and guards the parameter combination on every build invocation.

## Threat Flags

None. The new throw reduces misconfiguration risk by fail-fast rejecting an invalid CopyDrivers/BuildUSBDrive combination before any build side effects occur. No new external input, network, or auth path introduced.

## Self-Check: PASSED

- [x] `FFUDevelopment/BuildFFUVM.ps1` contains throw at line 2610 (> 775, END block)
- [x] Condition: `if ($CopyDrivers -and (-not $BuildUSBDrive) -and (-not $USBOnlyMode))`
- [x] WriteLog wording verbatim from dc801e9
- [x] Throw wording verbatim from dc801e9
- [x] Existing `#Validate drivers folder` block intact at line 2614
- [x] Commit 8741ee8 exists in git log
- [x] All 14 phase tests green
