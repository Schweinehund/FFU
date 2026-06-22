---
phase: 50-selective-rebuild-pipeline
plan: "05"
subsystem: BuildFFUVM.ps1 USBOnlyMode pipeline
tags: [usb-mode, selective-rebuild, disposition, drivers, apps-iso, deploy-iso, rebuild-gate]
dependency_graph:
  requires: [50-04]
  provides: [selective-rebuild-execution, USB-Mode-mini-path-init, rebuild-flags, F6-driver-inputs]
  affects: [BuildFFUVM.ps1 USBOnlyMode block, Tests/Unit/USBOnlyMode.Tests.ps1]
tech_stack:
  added: []
  patterns:
    - "Inverted skip-flag gate pattern ($rebuildPhase mirrors $skipPhase, not tied to IsResuming)"
    - "USB-Mode mini path-init (if -not $Var) form before early-return short-circuit"
    - "PSObject.Properties.Match existence check for schema-optional fields"
    - "Existing Invoke-ParallelProcessing DownloadDriverByMake reuse (no hand-rolled loop)"
    - "try/catch non-blocking rebuild with graceful degradation"
    - "Structural Pester IndexOf ordering assertion for BLOCKER-1"
key_files:
  modified:
    - FFUDevelopment/BuildFFUVM.ps1
    - Tests/Unit/USBOnlyMode.Tests.ps1
decisions:
  - "Mini path-init placed before Step 4 (ISO mount check) so rebuild calls have populated variables and rebuilt DeployISO is validated (Pitfall 1 + 6)"
  - "Rebuild flags read $configData.USBMode.Artifacts directly (not through $cfgArt which is set in Step 5b) to allow placement before mount check"
  - "Drivers rebuild reuses Invoke-ParallelProcessing with DownloadDriverByMake task type — no new download loop written"
  - "D-07 degradation: driversJsonPath empty or missing -> log warning + set rebuildDrivers=false + continue"
  - "ADK null-check before New-AppsISO and New-PEMedia; Pitfall 5 mitigated via try/catch + flag reset"
  - "DeployISO rebuild reconciles $DeployISO path; Step 4 uses rebuilt path when rebuildDeployISO ran (Pitfall 6)"
  - "Structural ordering assertion uses IndexOf('$rebuildDrivers') < IndexOf('$dispositionCheckTypes') (BLOCKER-1)"
metrics:
  duration: "~15 minutes"
  completed: "2026-06-22"
  tasks_completed: 2
  files_modified: 2
---

# Phase 50 Plan 05: Selective Rebuild Execution Machinery Summary

**One-liner:** USB-Mode selective per-phase rebuild gates (Drivers/AppsISO/DeployISO) from Disposition=='Rebuild' config, with mini path-init, ADK guards, and BLOCKER-1 structural ordering assertion enforcing rebuild-before-gate.

## Tasks Completed

| # | Task | Commit | Key Changes |
|---|------|--------|-------------|
| 1 | USB-Mode mini path-init, rebuild flags, F6 config sourcing | 5029858 | $rebuildDrivers/$rebuildAppsISO/$rebuildDeployISO gates; mini path-init; driversJsonPath/Make/Model from config |
| 2 | Selective rebuild execution block + ordering assertion | b00c305 | Drivers/AppsISO/DeployISO execution blocks; ADK guards; reconciliation; IndexOf assertion in USBOnlyMode.Tests.ps1 |

## What Changed

### Task 1 — Mini Path-Init, Rebuild Flags, F6 (BuildFFUVM.ps1)

**USB-Mode mini path-init** inserted between Step 3 (manifest warnings) and Step 4 (ISO mount check). Uses `if (-not $Var)` form so user-supplied params are never overridden:
- `$AppsISO = "$FFUDevelopmentPath\Apps\Apps.iso"`
- `$AppsPath = "$FFUDevelopmentPath\Apps"`
- `$DeployISO = "$FFUDevelopmentPath\WinPE_FFU_Deploy_$WindowsArch.iso"`
- `$PEDriversFolder = "$FFUDevelopmentPath\PEDrivers"`
- `$DriversFolder = "$FFUDevelopmentPath\Drivers"`
- `$adkPath` resolved via `Get-ADKPath` wrapped in try/catch (returns $null if ADK absent)

**Rebuild flags** (parallel to `$skip*` pattern but NOT tied to `$script:IsResuming`):
```powershell
$rebuildDrivers   = ($cfgArtEarly.Drivers.Disposition   -eq 'Rebuild')
$rebuildAppsISO   = ($cfgArtEarly.AppsISO.Disposition   -eq 'Rebuild')
$rebuildDeployISO = ($cfgArtEarly.DeployISO.Disposition -eq 'Rebuild')
```
All three use `PSObject.Properties.Match('Disposition')` existence check. FFU/PPKG/Unattend/Autopilot never set Rebuild.

**F6 config sourcing**: if `$driversJsonPath`/`$Make`/`$Model` params are empty, reads them from `$configData.DriversJsonPath`/`.Make`/`.Model` (config is populated before the USBOnlyMode block; normal init at ~2050 is after the return).

### Task 2 — Selective Rebuild Execution Block (BuildFFUVM.ps1 + Tests)

**PHASE 50: Selective Rebuild Execution** block inserted at line ~1872, BEFORE Step 4 (ISO mount check) and BEFORE $dispositionCheckTypes gate (BLOCKER-1 satisfied):

**Drivers rebuild** (`if ($rebuildDrivers)`):
- Logs start message and data-loss warning (Pitfall 7)
- D-07 degradation: if driversJsonPath empty/missing → log warning + `$rebuildDrivers = $false` + continue
- Parses driversJsonPath JSON into `$driversToProcess` list (same structure as full-build phase ~2789-2733)
- Calls `Invoke-ParallelProcessing -ItemsToProcess $driversToProcess -TaskType 'DownloadDriverByMake'` with same `$taskArguments` hashtable shape
- On success: `$CopyDrivers = $true`

**AppsISO rebuild** (`if ($rebuildAppsISO)`):
- ADK null-check: if `$adkPath` empty → log warning + `$rebuildAppsISO = $false`
- Calls `New-AppsISO -ADKPath $adkPath -AppsPath $AppsPath -AppsISO $AppsISO` (wrapped in try/catch)
- Reconciles: `$AppsISOPath = $AppsISO`, `$CopyAppsISO = $true`

**DeployISO rebuild** (`if ($rebuildDeployISO)`):
- ADK null-check: if `$adkPath` empty → log warning + `$rebuildDeployISO = $false`
- Calls `New-PEMedia -Capture $false -Deploy $true -adkPath $adkPath ...` with full param set from reference call site 5404-5409 (wrapped in try/catch)
- Reconciles `$DeployISO` to rebuilt path; Step 4 `$deployISOPath` resolves to rebuilt ISO when rebuild ran (Pitfall 6)

**BLOCKER-1 structural assertion** added to `USBOnlyMode.Tests.ps1` F3 Context:
```powershell
$rebuildIdx = $scriptContent.IndexOf('$rebuildDrivers')
$gateIdx    = $scriptContent.IndexOf('$dispositionCheckTypes')
$rebuildIdx | Should -BeLessThan $gateIdx
```
With guards that both indexes are >= 0.

## Test Results

```
Invoke-Pester -Path 'Tests/Unit/USBOnlyMode.Tests.ps1'
Tests Passed: 39, Failed: 0, Skipped: 0
```

- **All F1 tests (4/4):** GREEN (from plan-04; no regression)
- **All F2 tests (3/3):** GREEN (from plan-04; no regression)
- **All F3 tests (7/7):** GREEN (plan-05 work; previously 6/6 RED + 1 ordering assertion)
  - `$rebuildDrivers =` declared: GREEN
  - `$rebuildAppsISO =` declared: GREEN
  - `$rebuildDeployISO =` declared: GREEN
  - `if ($rebuildDrivers)` execution block: GREEN
  - `New-AppsISO` called: GREEN
  - `New-PEMedia` called: GREEN
  - Ordering assertion (`IndexOf($rebuildDrivers) < IndexOf($dispositionCheckTypes)`): GREEN
- **All 32 pre-existing tests:** No regressions
- **AST parse:** CLEAN (0 errors)
- **FFU.Apps.Tests.ps1 / FFU.Media.Tests.ps1 failures (52):** Pre-existing before this plan (confirmed via git stash test); caused by RequiredModules not loadable in CI environment; not caused by this plan's changes.

## Ordering Verification

| Item | Line in BuildFFUVM.ps1 |
|------|------------------------|
| `$rebuildDrivers` (first occurrence) | 1822 |
| `$dispositionCheckTypes` (gate) | 2118 |
| Delta | +296 lines — BLOCKER-1 satisfied |

DeployISO rebuild runs at ~line 1960-1990 (before Step 4 at ~2000) — Pitfall 6 satisfied.

## Deviations from Plan

None — plan executed exactly as written.

The two tasks were implemented as described in the plan action blocks. The mini path-init and rebuild flags were placed before the ISO mount check (Step 4) to satisfy both Pitfall 6 and BLOCKER-1. The $cfgArtEarly local variable reads `$configData.USBMode.Artifacts` directly (rather than waiting for `$cfgArt` in Step 5b) to enable early placement.

## Known Stubs

None. All rebuild blocks call real project functions (Invoke-ParallelProcessing, New-AppsISO, New-PEMedia). No placeholder data or TODO stubs remain.

## Threat Surface Scan

| Mitigated Threat | Control Applied |
|------------------|-----------------|
| T-50-10: Rebuild must not execute arbitrary artifacts | Only three fixed trusted build functions reachable (New-AppsISO, New-PEMedia, Invoke-ParallelProcessing DownloadDriverByMake); no VM/VHDX/OS machinery called |
| T-50-11: Disposition=='Rebuild' from config | `PSObject.Properties.Match('Disposition') -and .Disposition -eq 'Rebuild'` exact comparison; plan-04 enum validation already normalizes unknown values before this gate |
| T-50-12: ADK missing / driver path missing | null-check $adkPath + Test-Path $driversJsonPath; flag set false + warning on failure; USB assembly continues without blocked artifact |
| T-50-13: $driversJsonPath path injection | Consumed by existing hardened driver-download machinery; reused as-is (accepted) |

## Self-Check: PASSED

- [x] FFUDevelopment/BuildFFUVM.ps1 modified and committed (Task 1: 5029858, Task 2: b00c305)
- [x] Tests/Unit/USBOnlyMode.Tests.ps1 modified and committed (b00c305)
- [x] 5029858 exists in git log: confirmed
- [x] b00c305 exists in git log: confirmed
- [x] All 39 USBOnlyMode tests GREEN (7 new F3 tests, 32 pre-existing)
- [x] AST parse clean: 0 errors
- [x] No regressions in pre-existing tests
- [x] BLOCKER-1: $rebuildDrivers (line 1822) < $dispositionCheckTypes (line 2118)
- [x] Pitfall 6: DeployISO rebuild (~line 1960) precedes Step 4 ISO mount check (~line 2000)
- [x] No PSObject.Properties.Match('Include') references remain (plan-04 confirmed; no new ones added)
