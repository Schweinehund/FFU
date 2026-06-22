---
phase: 50-selective-rebuild-pipeline
plan: "04"
subsystem: BuildFFUVM.ps1 USBOnlyMode pipeline
tags: [usb-mode, selective-rebuild, disposition, apps-iso, copy-gate]
dependency_graph:
  requires: [50-01]
  provides: [AppsISO-copy-path, Disposition-gate]
  affects: [BuildFFUVM.ps1 USBOnlyMode block, New-DeploymentUSB parallel block]
tech_stack:
  added: []
  patterns:
    - "$using: variable capture in ForEach-Object -Parallel"
    - "PSObject.Properties.Match existence check for schema-optional fields"
    - "Disposition enum validation (V5 input control)"
key_files:
  modified:
    - FFUDevelopment/BuildFFUVM.ps1
decisions:
  - "F1: $CopyAppsISO/$AppsISOPath set from manifest.AppsISO.Status and FilePath, with config override (mirrors Drivers pattern)"
  - "F2: $dispositionCheckTypes foreach+switch replaces Include-flag gate; FFU/DeployISO never Skip (D-03, D-10)"
  - "Disposition enum validation forces unknown values to Reuse with a WriteLog warning (T-50-07 V5 control)"
  - "Disposition gate placed inside $configData block to remain adjacent to config overrides; plan 05 inserts selective rebuild execution above this gate"
metrics:
  duration: "~15 minutes"
  completed: "2026-06-22"
  tasks_completed: 2
  files_modified: 1
---

# Phase 50 Plan 04: AppsISO Copy Path + Disposition Gate Summary

**One-liner:** AppsISO added to New-DeploymentUSB parallel copy via $CopyAppsISO/$AppsISOPath $using: pair; Include-flag gate replaced with Disposition enum validation gate reading schema-native field.

## Tasks Completed

| # | Task | Commit | Key Changes |
|---|------|--------|-------------|
| 1 | F1 — AppsISO copy path to New-DeploymentUSB | 877798f | $CopyAppsISO/$AppsISOPath vars + robocopy block in parallel loop |
| 2 | F2 — Disposition gate replaces Include gate | 877798f | $dispositionCheckTypes foreach+switch; enum validation; no Include refs remain |

Both tasks were committed together as a single atomic change to BuildFFUVM.ps1.

## What Changed

### F1 — AppsISO Copy Path (REBUILD-03)

**In the USBOnlyMode variable-population block** (after the existing folder-path defaults):
- Added `$CopyAppsISO = $false` and `$AppsISOPath = "$FFUDevelopmentPath\Apps\Apps.iso"` as script-scope variables.
- Populated `$CopyAppsISO = $true` and `$AppsISOPath` from `$manifest.AppsISO` when status is 'Found' and FilePath is non-empty.
- Added WARNING log when AppsISO not found (consistent with other optional artifact warnings).

**In the config override block** (Step 5b, after Autopilot override):
- Added AppsISO path override block: when `$cfgArt.AppsISO.Path` is non-empty and Test-Path succeeds, sets `$AppsISOPath` and `$CopyAppsISO = $true` with WriteLog.

**In New-DeploymentUSB ForEach-Object -Parallel block** (after the $using:CopyAutopilot block):
- Added `if ($using:CopyAppsISO)` block that creates Apps destination folder, robocopies the single ISO file using Split-Path Parent/Leaf (single-file form, not folder /E form), then calls Test-RobocopySuccess.
- Uses only ThreadJob-safe idioms: WriteLog, no Get-Command, no Get-Date, no Write-Host.

### F2 — Disposition Gate (REBUILD-02)

**Replaced the entire Include-flag block** (4 separate if-blocks reading PSObject.Properties.Match('Include')) with a single `$dispositionCheckTypes` foreach+switch:
- Array covers all 7 artifact types: FFU, DeployISO, Drivers, AppsISO, PPKG, Unattend, Autopilot.
- Reads `.Disposition` with PSObject.Properties.Match existence check (defaults to 'Reuse' for old configs without the field).
- Validates against `@('Reuse', 'Rebuild', 'Skip')` allow-list; unknown values → WriteLog warning + force Reuse (T-50-07 V5 control).
- Skip branch only flips $CopyDrivers/$CopyAppsISO/$CopyPPKG/$CopyUnattend/$CopyAutopilot — FFU and DeployISO have no Skip case (D-03, D-10).
- Rebuild branch logs a message; the execution block will be inserted by plan 50-05.
- Obsolete "No $CopyAppsISO flag exists" comment removed.

## Test Results

```
Invoke-Pester -Path 'Tests/Unit/USBOnlyMode.Tests.ps1' -Output Minimal
Tests Passed: 34, Failed: 4, Skipped: 0
```

- **F1 Context (4 tests): ALL GREEN** — $CopyAppsISO declared, $AppsISOPath declared, $using:CopyAppsISO in parallel block, $using:AppsISOPath in parallel block.
- **F2 Context (3 tests): ALL GREEN** — No Include gate remains, dispositionCheckTypes present, PSObject.Properties.Match('Disposition') present.
- **F3 Context (4+2 tests): RED as expected** — $rebuildDrivers/$rebuildAppsISO/$rebuildDeployISO and selective rebuild block are plan 50-05 work; intentionally kept RED.
- **All 32 pre-existing tests: PASSED** — no regressions.

BuildFFUVM.ps1 AST parse: CLEAN (0 parse errors).

No `PSObject.Properties.Match('Include')` references remain anywhere in BuildFFUVM.ps1.

## Deviations from Plan

None — plan executed exactly as written.

The two tasks (F1 variable init + parallel block copy; F2 gate replacement) were implemented as described in the plan action blocks. The AppsISO path override and Disposition gate were placed inside the `$configData` block as specified. The gate leaves a comment explaining that plan 50-05 will insert the selective rebuild execution block above it.

## Threat Surface Scan

No new network endpoints, auth paths, or file access patterns introduced beyond what the plan's threat model covers:

| Mitigated Threat | Control Applied |
|------------------|-----------------|
| T-50-07: Malformed Disposition string | `$disp -notin @('Reuse','Rebuild','Skip')` → force Reuse with WriteLog |
| T-50-08: Path traversal via $AppsISOPath | Test-Path gate before $CopyAppsISO=true; robocopy uses Split-Path (literal paths, no shell concat) |

## Known Stubs

None. The Rebuild branch in the Disposition gate logs a message and defers to plan 50-05. This is intentional and documented in a comment in the code.

## Self-Check: PASSED

- [x] FFUDevelopment/BuildFFUVM.ps1 modified and committed at 877798f
- [x] 877798f exists in git log: confirmed
- [x] F1 tests (4/4) GREEN
- [x] F2 tests (3/3) GREEN
- [x] F3 tests (6/6) RED (expected — plan 50-05)
- [x] No regressions in 32 pre-existing tests
- [x] AST parse clean
- [x] No Include property match references remaining in BuildFFUVM.ps1
