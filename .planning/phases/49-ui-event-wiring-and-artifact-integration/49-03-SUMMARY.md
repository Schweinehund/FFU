---
phase: 49-ui-event-wiring-and-artifact-integration
plan: "03"
subsystem: FFUUI.Core.Config + FFUUI.Core.StateRecovery + BuildFFUVM_UI
tags: [usb-mode, config-persistence, state-recovery, button-labels, disc-03, d-22, d-23, d-29]
dependency_graph:
  requires: [49-01]
  provides: [config-round-trip, mode-aware-button-labels]
  affects: [FFUUI.Core.Config.psm1, FFUUI.Core.StateRecovery.psm1, BuildFFUVM_UI.ps1]
tech_stack:
  added: []
  patterns: [config-load-ordering, isLoadingConfig-guard, mode-aware-labels]
key_files:
  created: []
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.StateRecovery.psm1
    - FFUDevelopment/BuildFFUVM_UI.ps1
decisions:
  - "Artifact paths loaded BEFORE ActiveMode RadioButton set (Pitfall 5 avoidance) — USB Mode Checked handler fires during IsChecked assignment, so user paths must be pre-loaded in usbArtifactState before scan triggers"
  - "isLoadingConfig guard wraps BOTH Update-UIFromConfig call sites (Issue #15) — manual load via dialog AND auto-load on startup"
  - "Only user-source paths persisted to config (source='user') — auto-detected paths re-scanned on next load; avoids stale paths from moved media"
  - "Mode switch handlers in FFUUI.Core.Handlers.psm1 not changed — they already set correct labels per Plan 01"
metrics:
  duration_minutes: 8
  completed_date: "2026-03-24"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
---

# Phase 49 Plan 03: Config Persistence and Mode-Aware Button Labels Summary

**One-liner:** Config round-trip persists USB Mode state (ActiveMode + user artifact paths + include flags) with correct load ordering, and all button reset paths use mode-aware 'Create USB'/'Build FFU' labels.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace config save/load stubs with real USB Mode persistence | 7c62949 | FFUUI.Core.Config.psm1 |
| 2 | Mode-aware button label at all hardcoded locations | 734e457 | FFUUI.Core.StateRecovery.psm1, BuildFFUVM_UI.ps1 |

## What Was Built

### Task 1: Config Save/Load Stubs Replaced

**Build-UIConfiguration (save):**
- Reads `$State.Controls.rbUSBMode.IsChecked` to determine `ActiveMode` value ('USBMode' or 'FullBuild')
- Iterates all 7 artifact types (FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO)
- Saves path only when `source -eq 'user'` — auto-detected paths are not persisted (they re-scan on load)
- Saves `Include = [bool]$State.Controls[usb{Type}Include].IsChecked` per artifact (D-29 mechanism for Plan 04)
- `Disposition = 'Reuse'` default — Phase 50 will add rebuild/skip options

**Update-UIFromConfig (load):**
- Loads USBMode.Artifacts paths BEFORE setting `rbUSBMode.IsChecked = $true` (Pitfall 5 avoidance)
- Sets `$State.Data.usbArtifactState[KEY].source = 'user'` for loaded paths
- Updates path TextBlock immediately so paths show during subsequent scan
- Restores include checkbox states from config
- Sets `rbUSBMode.IsChecked = $true` AFTER paths loaded (fires Checked event which triggers scan with pre-loaded paths)

**isLoadingConfig guard (Issue #15):**
- Wraps BOTH Update-UIFromConfig call sites (line ~460 manual load, line ~1377 auto-load)
- After guard clears, explicit `Invoke-USBArtifactScan` fires if USB Mode was restored
- Prevents premature scan during config load (scan sees `isLoadingConfig = $true` and skips)

### Task 2: Mode-Aware Button Labels

Three hardcoded `btnRun.Content = "Build FFU"` assignments replaced with mode-aware checks:

1. **FFUUI.Core.StateRecovery.psm1 Reset-FFUUIToIdle** — checks `$State.Controls.rbUSBMode.IsChecked`
2. **BuildFFUVM_UI.ps1 cancel/no-config path** (~line 347) — same pattern with `$script:uiState.Controls.rbUSBMode`
3. **BuildFFUVM_UI.ps1 job success handler** (~line 842) — same mode-aware check

Pattern used at all 3 locations:
```powershell
$isUSBMode = $null -ne $State.Controls.rbUSBMode -and $State.Controls.rbUSBMode.IsChecked
$State.Controls.btnRun.Content = if ($isUSBMode) { 'Create USB' } else { 'Build FFU' }
```

`btnRun.Content = "Cancel"` assignment is unchanged — applies correctly to both modes per D-15.

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

- `usbArtifactState` referenced in Config save/load: PASS
- `source -eq 'user'` filter in save path: PASS
- `ActiveMode -eq 'USBMode'` in load comparison: PASS
- `rbUSBMode.IsChecked` at save and load locations: PASS
- `isLoadingConfig` at both call sites (lines 468, 1379): PASS
- `Include` flag persisted and restored: PASS
- Zero hardcoded `btnRun.Content = "Build FFU"` in StateRecovery.psm1: PASS
- Zero hardcoded `btnRun.Content = "Build FFU"` in BuildFFUVM_UI.ps1: PASS
- `Create USB` string in StateRecovery.psm1: PASS
- 2+ mode-aware `if ($isUSBMode)` blocks in BuildFFUVM_UI.ps1: PASS (2 instances)

## Known Stubs

None — all stubs from Plan 45/48 replaced with real implementations.

## Self-Check: PASSED

- `D:\claude\FFUBuilder\FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1` — modified (stubs replaced)
- `D:\claude\FFUBuilder\FFUDevelopment\FFUUI.Core\FFUUI.Core.StateRecovery.psm1` — modified (mode-aware label)
- `D:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM_UI.ps1` — modified (2 mode-aware label locations)
- Commit 7c62949 — feat(49-03): replace config save/load stubs with real USB Mode persistence
- Commit 734e457 — feat(49-03): mode-aware button labels at all hardcoded locations
