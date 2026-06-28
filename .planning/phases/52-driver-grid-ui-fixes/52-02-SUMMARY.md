---
phase: 52-driver-grid-ui-fixes
plan: 02
subsystem: FFUUI.Core
tags: [driver-grid, select-all, collectionview, wpf, header-alignment, upstream-port, f09c989, 42ed281]
dependency_graph:
  requires: [phase-52-plan-01]
  provides: [DGRID-02-fix]
  affects: [Add-SelectableGridViewColumn, Update-SelectAllHeaderCheckBoxState, Save-DriversJson, driver-grid-init]
tech_stack:
  added: []
  patterns:
    - Visible-items-only scope via CollectionViewSource.GetDefaultView() enumeration (f09c989)
    - allDriverModels null-guarded master-list read for Save-DriversJson (f09c989)
    - Border/Grid/GridViewColumnHeader alignment wrapper (42ed281)
    - PSObject.Properties guard for safe Tag field read
key_files:
  created: []
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1
decisions:
  - "Port verbatim from f09c989 (switch + scope handlers + Update-SelectAllHeaderCheckBoxState) then 42ed281 (alignment) — strict ordering per D-08"
  - "Exactly ONE Initialize.psm1 call site carries -HeaderSelectionAffectsVisibleItemsOnly (lstDriverModels line 457); other five grids unchanged"
  - "PSScriptAnalyzer: 11 pre-existing warnings in Shared.psm1, 4 in Drivers.psm1, 5 in Initialize.psm1; zero new warnings from this plan"
metrics:
  duration_minutes: 20
  completed: "2026-06-28"
  tasks_completed: 3
  files_created: 0
  files_modified: 3
---

# Phase 52 Plan 02: DGRID-02 Select-All Visible Scope + Header Alignment Summary

Port upstream f09c989 then 42ed281 into the fork: scope the driver-grid select-all header to visible/filtered rows only, fix the save-path data leak in Save-DriversJson, and center the header checkbox via a GridViewColumnHeader alignment wrapper.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Port f09c989 select-all visible scope (Shared.psm1) | 201feaa | FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1 |
| 2 | Port f09c989 Save-DriversJson source + Initialize.psm1 opt-in | 6f8d5ad | FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1, FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1 |
| 3 | Port 42ed281 header checkbox alignment (Shared.psm1) | 553054f | FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1 |

## What Was Built

**Task 1 — f09c989 select-all visible scope (Shared.psm1):**

Four changes to `Add-SelectableGridViewColumn`:
1. Added `[switch]$HeaderSelectionAffectsVisibleItemsOnly` to param block after `[string]$IsSelectedPropertyName`.
2. Added `HeaderSelectionAffectsVisibleItemsOnly = [bool]$HeaderSelectionAffectsVisibleItemsOnly` field to `$headerTagObject` PSCustomObject.
3. Replaced Add_Checked one-liner with scope-aware block: when `$tagData.HeaderSelectionAffectsVisibleItemsOnly` is set, enumerates `CollectionViewSource.GetDefaultView($actualListView.ItemsSource)` (visible/filtered items only); falls back to `@(ItemsSource)` then `@(Items)` when unset.
4. Replaced Add_Unchecked body with identical scope-aware block setting `$false`.

One change to `Update-SelectAllHeaderCheckBoxState`:
- Replaced the `$collectionToInspect` block (lines 423-436) with the f09c989 version that reads `$HeaderCheckBox.Tag.PSObject.Properties['HeaderSelectionAffectsVisibleItemsOnly']` (guarded) and, when set, enumerates the filtered CollectionView instead of `@(ItemsSource)`. The tri-state comparison logic below is unchanged.

**Task 2 — f09c989 Save-DriversJson + Initialize.psm1 opt-in:**

Save-DriversJson (Drivers.psm1 line 221): replaced `$State.Controls.lstDriverModels.Items` read with null-guarded master-list read:
```powershell
$driverSelectionSource = if ($null -ne $State.Data.allDriverModels) { $State.Data.allDriverModels } else { $State.Controls.lstDriverModels.Items }
$selectedDrivers = @($driverSelectionSource | Where-Object { $_.IsSelected })
```
This preserves hidden-row selections when a CollectionView filter is active — the save-path data leak is closed.

Initialize.psm1 line 457 (lstDriverModels ONLY): appended `-HeaderSelectionAffectsVisibleItemsOnly` to the driver-grid's `Add-SelectableGridViewColumn` call. The other five call sites (lstWingetResults:489, lstApplications:645, lstAppsScriptVariables:668, lstUSBDrives:730, lstAdditionalFFUs:792) are unchanged.

**Task 3 — 42ed281 header checkbox alignment (Shared.psm1):**

Three changes applied verbatim from upstream 42ed281:
1. Added `$headerCheckBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center` after the existing HorizontalAlignment line.
2. Inserted alignment wrapper after Add_Unchecked's closing `})` and before `$State.Controls[...]`: a `Border` (Padding 12,0,0,0 + Stretch) containing a `Grid` (Stretch) containing the `$headerCheckBox`, all wrapped in a `GridViewColumnHeader` with zeroed Padding/Margin and Stretch content alignment.
3. Replaced `$selectableColumn.Header = $headerCheckBox` with `$selectableColumn.Header = $selectableHeader`.

## Verification

```
Test run after all tasks:
  DGRID-01: 3/3 PASS
  DGRID-02: 7/7 PASS (all assertions GREEN)
  DGRID-03: 0/3 FAIL (expected RED until plan 03)

Total: 11/14 PASS (3 DGRID-03 failures are plan 03 scope — expected)

Module import: pwsh + Add-Type PresentationFramework,PresentationCore,WindowsBase
  Import-Module FFUUI.Core.psd1 -Force
  Result: OK
  (Get-Command Add-SelectableGridViewColumn).Parameters.ContainsKey('HeaderSelectionAffectsVisibleItemsOnly') → True

PSScriptAnalyzer:
  Shared.psm1: 11 findings (all pre-existing; 0 new)
  Drivers.psm1: 4 findings (all pre-existing; 0 new)
  Initialize.psm1: 5 findings (all pre-existing; 0 new)

Opt-in gate: exactly 1 Initialize.psm1 call site carries -HeaderSelectionAffectsVisibleItemsOnly (grep verified)
```

## Deviations from Plan

None — plan executed exactly as written. All three tasks applied upstream content verbatim at fork-corrected line numbers per PATTERNS.md.

**Note on Unchecked handler indentation:** The scope-aware block inside `Add_Unchecked` is at 12-space indentation while the outer `if ($senderCheckBoxLocal.IsChecked -eq $false)` guard is also at 12-space indent. This is a cosmetic discrepancy carried over from the pre-existing guard in the original code; it matches the PSReviewUnusedParameter/PSUseShouldProcessForStateChangingFunctions pre-existing patterns and does not introduce a new PSScriptAnalyzer finding.

## Known Stubs

None — all implementations wire real WPF objects and real state paths. No placeholder data or TODO markers introduced.

## Threat Flags

None — changes are WPF UI state (local CheckBox IsSelected flags) and a local JSON write reading from in-memory master list. No new network, auth, or external input path introduced. Per plan threat model T-52-02 (accepted) and T-52-03 (accepted).

## Self-Check: PASSED

- [x] Shared.psm1 declares `[switch]$HeaderSelectionAffectsVisibleItemsOnly` in `Add-SelectableGridViewColumn` param block
- [x] Shared.psm1 `$headerTagObject` carries `HeaderSelectionAffectsVisibleItemsOnly` field
- [x] Shared.psm1 Add_Checked and Add_Unchecked handlers enumerate `CollectionViewSource.GetDefaultView()` when switch is set
- [x] Shared.psm1 `Update-SelectAllHeaderCheckBoxState` reads `HeaderSelectionAffectsVisibleItemsOnly` via PSObject.Properties guard
- [x] Shared.psm1 constructs `GridViewColumnHeader` wrapper; `$selectableColumn.Header = $selectableHeader`
- [x] Drivers.psm1 `Save-DriversJson` reads `$State.Data.allDriverModels` with null-guard fallback
- [x] Initialize.psm1 exactly ONE call site (lstDriverModels:457) carries `-HeaderSelectionAffectsVisibleItemsOnly`; lines 489/645/668/730/792 unchanged
- [x] Commit 201feaa exists (Task 1)
- [x] Commit 6f8d5ad exists (Task 2)
- [x] Commit 553054f exists (Task 3)
- [x] DGRID-02 assertions: all 7 GREEN in test run
- [x] Module imports cleanly with WPF assemblies loaded
- [x] PSScriptAnalyzer: 0 new findings from this plan's changes
