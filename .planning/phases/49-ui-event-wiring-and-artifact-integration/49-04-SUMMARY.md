---
phase: 49-ui-event-wiring-and-artifact-integration
plan: "04"
subsystem: ui
tags: [wpf, usb-mode, threadjob, config-persistence, pester]

requires:
  - phase: 49-01
    provides: Invoke-USBArtifactScan, usbArtifactState initialization, status UI wiring
  - phase: 49-02
    provides: Browse handlers for all 7 artifact types, usbCheckUSBDrives handler
  - phase: 49-03
    provides: Build-UIConfiguration writes USBMode.Artifacts with Include flags, Update-UIFromConfig loads artifact paths with isLoadingConfig guard

provides:
  - USB Mode branch in btnRun click handler with 3-gate pre-launch validation
  - Full ThreadJob structure for USB creation (module imports, messaging, error handling)
  - Config save before ThreadJob launch (D-29 include flags flow to BuildFFUVM.ps1)
  - BuildFFUVM.ps1 USBOnlyMode reads user-specified paths and include flags from configData
  - Phase49 Pester test scaffold covering 6 requirement areas

affects: [phase-50, usb-mode-pipeline, BuildFFUVM_UI, BuildFFUVM]

tech-stack:
  added: []
  patterns:
    - "USB Mode branch: check $isUSBMode before Full Build path, return after USB launch to skip Full Build"
    - "ThreadJob ScriptBlock replication: identical structure to Full Build for mode-agnostic polling"
    - "Config path pattern: Join-Path config.FFUDevelopmentPath '\config\FFUConfig.json' (not hardcoded)"
    - "configData.USBMode.Artifacts pattern in BuildFFUVM.ps1 (not $config)"
    - "Include flag override ordering: path override first, then include=false can zero the gate"

key-files:
  created:
    - Tests/Unit/Phase49.Tests.ps1
  modified:
    - FFUDevelopment/BuildFFUVM_UI.ps1
    - FFUDevelopment/BuildFFUVM.ps1

key-decisions:
  - "USB Mode branch placed after validation-errors check, before Full Build path, returns to skip Full Build"
  - "DispatcherTimer Tick handler copied verbatim from Full Build — mode-agnostic polling works for both"
  - "Config path override logged in Step 1b, applied in Step 5b (after copy flags set from manifest)"
  - "No CopyAppsISO variable used — AppsISO handled via path only (Issue #10)"
  - "isLoadingConfig guard on both Build-UIConfiguration call sites verified by Pester test"

patterns-established:
  - "USB Mode validation: 3 gates (FFU Found+checked, DeployISO Found+checked, USB drive selected)"
  - "ThreadJob for USB creation: identical ScriptBlock structure to Full Build with -USBOnlyMode flag"
  - "Config override: Test-Path -LiteralPath guard before accepting any user-specified path"

requirements-completed: [USB-02, USB-03]

duration: 35min
completed: 2026-03-24
---

# Phase 49 Plan 04: USB Mode Launch Branch and Config Override Summary

**btnRun USB Mode branch with full ThreadJob structure launches BuildFFUVM.ps1 -USBOnlyMode; config include flags flow to copy gates; Phase49 Pester scaffold covers 6 requirement areas.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-03-24T22:00:00Z
- **Completed:** 2026-03-24T22:35:00Z
- **Tasks:** 2 of 2
- **Files modified:** 3 (BuildFFUVM_UI.ps1, BuildFFUVM.ps1, Phase49.Tests.ps1 new)

## Accomplishments

- Added USB Mode branch to btnRun handler: 3-gate pre-launch validation (FFU Found+checked, DeployISO Found+checked, USB drive selected), config save, full ThreadJob ScriptBlock, DispatcherTimer polling
- Extended BuildFFUVM.ps1 USBOnlyMode block to honor user-specified artifact paths and include/exclude flags from configData.USBMode.Artifacts
- Created Phase49.Tests.ps1 with 6 tagged Contexts, 20 tests covering browse state, config persistence order, USB drive detection, include flags, WPF type correctness, and mode-aware button labels

## Task Commits

1. **Task 1: btnRun USB Mode branch with pre-launch validation and ThreadJob launch** - `5a10a94` (feat)
2. **Task 2: Pester test scaffold for Phase 49 requirements** - `0ffdf3a` (test)

## Files Created/Modified

- `FFUDevelopment/BuildFFUVM_UI.ps1` - USB Mode branch added before Full Build path (~200 lines: validation, config save, ScriptBlock, DispatcherTimer, ThreadJob launch)
- `FFUDevelopment/BuildFFUVM.ps1` - USBOnlyMode extended with Step 1b (logging overrides) and Step 5b (applying config path overrides and include flags)
- `Tests/Unit/Phase49.Tests.ps1` - New: 272 lines, 20 tests across 6 tagged Contexts

## Deviations from Plan

None — plan executed exactly as written. All critical issues (#5, #6, #7, #8, #10, #14) addressed per plan specification.

## Self-Check

Files exist:
- FFUDevelopment/BuildFFUVM_UI.ps1 — modified
- FFUDevelopment/BuildFFUVM.ps1 — modified
- Tests/Unit/Phase49.Tests.ps1 — created

Commits exist:
- 5a10a94 — feat(49-04): add USB Mode branch to btnRun handler with full ThreadJob structure
- 0ffdf3a — test(49-04): add Phase49 Pester test scaffold

## Self-Check: PASSED
