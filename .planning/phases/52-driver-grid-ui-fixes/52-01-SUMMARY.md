---
phase: 52-driver-grid-ui-fixes
plan: 01
subsystem: FFUUI.Core
tags: [driver-grid, sort, filter, wpf, collectionview, test-scaffold, upstream-port]
dependency_graph:
  requires: [phase-51]
  provides: [DGRID-01-fix, phase-52-test-scaffold]
  affects: [Invoke-ListViewSort, all-sortable-grid-headers]
tech_stack:
  added: []
  patterns:
    - CollectionView filter capture/reapply (b4305a1 upstream)
    - Custom Write-TestResult test framework (Nyquist RED scaffold)
key_files:
  created:
    - FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1
decisions:
  - "DGRID-01 fix applied to SHARED Invoke-ListViewSort (backward compatible; no-filter path unchanged per D-09)"
  - "Test scaffold covers DGRID-01/02/03 with RED assertions for 02/03 (Nyquist bootstrap) — expected until plans 02/03 land"
  - "PSScriptAnalyzer: 11 pre-existing warnings in Shared.psm1; zero new warnings from this plan's changes"
metrics:
  duration_minutes: 20
  completed: "2026-06-28"
  tasks_completed: 2
  files_created: 1
  files_modified: 1
---

# Phase 52 Plan 01: Driver-Grid Wave-0 Scaffold + DGRID-01 Summary

Port upstream b4305a1 (sort-while-filtered preserves filter) into the SHARED `Invoke-ListViewSort` function and create the Phase 52 automated test scaffold covering DGRID-01/02/03 content and logic assertions.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create Test-Phase52DriverGridFixes.ps1 scaffold | 55a816e | FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1 |
| 2 | Port b4305a1 into Invoke-ListViewSort (DGRID-01) | ad76103 | FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1 |

## What Was Built

**Task 1 — Test scaffold (Write-TestResult framework):**
- Header + counters + `Write-TestResult` function verbatim from Test-Phase51Correctness.ps1 pattern.
- DGRID-01 content assertions: `$existingFilter = $null` preamble, `existingCollectionView.*GetDefaultView` capture, `newView.Filter = $existingFilter` reapply.
- DGRID-02 assertions: `-HeaderSelectionAffectsVisibleItemsOnly` switch param, `Update-SelectAllHeaderCheckBoxState` Tag read, `GridViewColumnHeader` wrapper, single opt-in call site count in Initialize.psm1, `allDriverModels` null-guard in Drivers.psm1.
- DGRID-03 assertions: throw wording regex, `-not $USBOnlyMode` guard, line-number > 775 END-block check.
- `Test-DriverSelectionSource-Local` pure-function logic test (local copy; no WPF runtime needed).
- All DGRID-01/02/03 assertions RED at Task 1 commit (expected Nyquist bootstrap).

**Task 2 — b4305a1 port into `Invoke-ListViewSort`:**
Three insertions applied verbatim from upstream diff:
1. Filter-capture preamble inserted after param block — captures `$existingFilter` and `$existingCollectionView` from `CollectionViewSource.GetDefaultView($listView.ItemsSource)`.
2. Item-collection block replaced — when filter is active, enumerates `$existingCollectionView` (visible items only); no-filter path uses `@($currentItemsSource)` or `@($listView.Items)` unchanged (backward compatible).
3. Filter reapplication appended after `$listView.ItemsSource = $newSortedList.ToArray()` — re-acquires `GetDefaultView` on the new source and assigns `$newView.Filter = $existingFilter`.

No other function in `FFUUI.Core.Shared.psm1` was modified. The no-filter sort path is behaviorally identical to the pre-fix code.

## Verification

```
Test run after Task 2:
  DGRID-01: 3/3 PASS
  DGRID-02: 4/7 (3 FAIL — expected RED until plan 02)
  DGRID-03: 0/3 (3 FAIL — expected RED until plan 03)

Module import: pwsh -NoProfile -ExecutionPolicy Bypass -Command
  Import-Module '.\FFUDevelopment\FFUUI.Core\FFUUI.Core.psd1' -Force
  Result: OK

PSScriptAnalyzer: 11 pre-existing findings in Shared.psm1; 0 new findings from this plan's changes.
```

## Deviations from Plan

None — plan executed exactly as written. The three b4305a1 insertions match the PATTERNS.md code verbatim. The test scaffold matches the Test-Phase51Correctness.ps1 framework pattern verbatim.

**Note:** The "GridViewColumnHeader" DGRID-02 content assertion passes before the 42ed281 fix lands because `Add-GridViewColumn` (a different function at line 237) already uses `New-Object System.Windows.Controls.GridViewColumnHeader`. The assertion remains useful as a presence-check for after the 42ed281 port in plan 02. The VALIDATION.md marks 42ed281 alignment as manual UAT only.

## Known Stubs

None — all assertions are wired to real source-file content. The DGRID-02/03 assertions are intentionally RED (Nyquist bootstrap) and will be resolved in plans 02 and 03.

## Threat Flags

None — this plan edits local WPF sort logic and a local test script. No network, auth, file-write of untrusted data, or new external-input path introduced. Per the plan's threat model, risk is minimal.

## Self-Check: PASSED

- [x] `FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1` exists and contains `Write-TestResult`
- [x] `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` contains `existingFilter`, `existingCollectionView`, `newView.Filter = $existingFilter`
- [x] Commit 55a816e exists (Task 1)
- [x] Commit ad76103 exists (Task 2)
- [x] DGRID-01 assertions GREEN in test run
- [x] Module imports cleanly in PS 7
- [x] PSScriptAnalyzer: no new warnings from this plan
