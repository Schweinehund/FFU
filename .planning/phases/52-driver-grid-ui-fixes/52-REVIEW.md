---
phase: 52-driver-grid-ui-fixes
reviewed: 2026-06-28T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1
  - FFUDevelopment/BuildFFUVM.ps1
  - FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1
findings:
  critical: 1
  warning: 2
  info: 1
  total: 4
status: issues_found
---

# Phase 52: Code Review Report

**Reviewed:** 2026-06-28
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 52 ports four upstream commits (b4305a1, f09c989, 42ed281, dc801e9) covering filter-persistence during sort, visible-scope select-all, header-checkbox alignment, and the CopyDrivers dependency throw. The mechanical port is largely sound: the filter-predicate is captured before sort, re-applied after reassignment; the `-HeaderSelectionAffectsVisibleItemsOnly` switch is present in `Add-SelectableGridViewColumn` and respected by `Update-SelectAllHeaderCheckBoxState`; exactly one call site in `Initialize.psm1` opts in (the driver grid); `Save-DriversJson` reads from the master `allDriverModels` list with a null-guard fallback; and the CopyDrivers throw is correctly placed in the END block after config load, guarded with `-not $USBOnlyMode`.

One blocker was found: the sort logic when a filter is active is incorrect — it sorts only the visible (filtered) items instead of the full backing list, then assigns those truncated items as the new ItemsSource. The filter predicate is re-applied correctly to the new view, but the new view is backed by an incomplete list. The practical consequence is that clearing the filter after a sort loses the sort order entirely, recovering only because `Search-DriverModels` reassigns from the unchanged `allDriverModels` master list.

Two warnings: a misleading indentation block in the `Add_Unchecked` handler, and an unused computed variable in the test that causes the placement assertion to use a hardcoded sentinel instead of the dynamically-found marker.

---

## Critical Issues

### CR-01: `Invoke-ListViewSort` sorts only filtered items when a filter is active; full-list sort order is lost on filter clear

**File:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1:620-624`

**Issue:** When an active CollectionView filter exists, `$itemsToSort` is populated by enumerating `$existingCollectionView` — which yields only the visible (filter-passing) items — rather than the full `$currentItemsSource` backing list. The sort, selected-items-first grouping, and the new `$newSortedList` therefore contain only visible items. The reassignment at line 714 sets `$listView.ItemsSource` to this truncated array. The filter predicate is re-applied (line 720) correctly, but since every item in the new source already passes the filter, the re-application is a no-op. Hidden items (those that did not pass the filter) are permanently removed from the ListView's ItemsSource.

The master list `$State.Data.allDriverModels` is never modified by `Invoke-ListViewSort`, so data is not permanently lost. `Search-DriverModels` (Drivers.psm1:180-182) detects `lstDriverModels.ItemsSource -ne $State.Data.allDriverModels` and re-assigns the master list on the next filter operation. However, when that recovery occurs the sort order is lost because `allDriverModels` was never reordered. The net user-visible behaviour: sort while filter is active appears to work, but clearing the filter discards the sort order — the opposite of the intent of commit b4305a1.

The root cause: the filter-active branch (lines 620-624) should sort the full backing list, not the filtered view. The filtered view is only needed to know WHICH items are visible so they can be sorted in the correct scope; but the sort itself must operate on the full source.

**Fix:**
```powershell
# Replace lines 618-630 with this to always sort the full backing list:
$currentItemsSource = $listView.ItemsSource
$itemsToSort = @()
if ($null -ne $currentItemsSource) {
    $itemsToSort = @($currentItemsSource)   # Always use the FULL backing list
}
else {
    $itemsToSort = @($listView.Items)
}
```

With this change the re-application of `$existingFilter` at lines 717-721 works correctly: it filters the full sorted list so only matching items are visible, and clearing the filter shows all items in sorted order.

---

## Warnings

### WR-01: `Add_Unchecked` handler body mis-indented, making block boundary ambiguous

**File:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1:366-387`

**Issue:** The outer `if ($senderCheckBoxLocal.IsChecked -eq $false)` block opens at line 361 and closes at line 387. Lines 362-364 (inside the block) are correctly indented at 16 spaces. However lines 366-386 drop back to 12 spaces — the same indentation as the `if` keyword itself. Visually these lines appear to be outside the `if` block when they are actually inside it. PowerShell cares about braces, not indentation, so the runtime behaviour is correct, but any reader or maintainer of the handler faces unnecessary ambiguity about which statements are conditional.

A secondary consequence: the guard `if ($senderCheckBoxLocal.IsChecked -eq $false)` is itself redundant in an `Add_Unchecked` handler (the event only fires when `IsChecked` becomes `$false`), but the indentation bug makes it appear the guard wraps only the first three lines and that the bulk of the handler is unconditional.

**Fix:** Re-indent lines 366-386 from 12 spaces to 16 spaces to match the enclosing `if` block. Additionally, consider removing the redundant `if ($senderCheckBoxLocal.IsChecked -eq $false)` guard, or if it is retained for defensive programming, leave a comment explaining why.

```powershell
$headerCheckBox.Add_Unchecked({
    param($senderCheckBoxLocal, $eventArgsUncheckedLocal)
    if ($senderCheckBoxLocal.IsChecked -eq $false) {
        $tagData = $senderCheckBoxLocal.Tag
        $localPropertyName = $tagData.PropertyName
        $actualListView = $tagData.ListViewControl

        # Clear either visible view items only (filtered scope) or the full backing list.
        $collectionToUpdate = @()
        if ($tagData.HeaderSelectionAffectsVisibleItemsOnly -and $null -ne $actualListView.ItemsSource) {
            ...
        }
        ...
    }
})
```

---

### WR-02: Test computes `$configLoadLine` but asserts against hardcoded `775` — assertion is weaker than intended

**File:** `FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1:216-234`

**Issue:** The test locates the `###PARAMETER VALIDATION` marker in BuildFFUVM.ps1 and stores the result in `$configLoadLine` (lines 216-221). The intent, stated in the comment on line 215, is to verify the throw comes after config load. However the assertion (line 233) ignores `$configLoadLine` entirely and uses the hardcoded literal `775` instead:

```powershell
$throwAfterConfigLoad = ($throwLine -gt 775)
```

The actual `###PARAMETER VALIDATION` marker is near line 2606. The assertion only proves the throw is somewhere past line 775 in the END block; it does not prove the throw is after the parameter-validation marker. A future refactoring that moved the throw to, say, line 800 (before config load but after line 775) would pass the test while being incorrectly placed. The computed `$configLoadLine` variable is set but never read — this is a latent dead-variable.

**Fix:**
```powershell
# Replace line 233:
$throwAfterConfigLoad = ($configLoadLine -gt 0 -and $throwLine -gt $configLoadLine)
# Update the Write-TestResult description to match:
Write-TestResult -TestName "BuildFFUVM.ps1 CopyDrivers throw is after ###PARAMETER VALIDATION marker (line $throwLine > $configLoadLine)" `
    -Passed $throwAfterConfigLoad `
    -Message "$(if (-not $throwAfterConfigLoad) { "Throw at line $throwLine, marker at line $configLoadLine. May be before parameter validation." })"
```

---

## Info

### IN-01: Programmatic `$HeaderCheckBox.IsChecked = $false` in `Update-SelectAllHeaderCheckBoxState` triggers `Add_Unchecked` and causes a redundant refresh

**File:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1:503-505 and 520-521`

**Issue:** `Update-SelectAllHeaderCheckBoxState` sets `$HeaderCheckBox.IsChecked = $false` when `selectedCount -eq 0` (or when `collectionToInspect` is empty). This programmatic write fires the `Unchecked` WPF event, which invokes the `Add_Unchecked` handler registered in `Add-SelectableGridViewColumn`. The handler iterates visible items and sets `IsSelected = $false` on each, then calls `$actualListView.Items.Refresh()`. Since `selectedCount` is already 0 at this point, all items are already deselected — the handler is iterating and writing back values that are unchanged, then triggering an unnecessary UI refresh.

This is not a correctness bug: the redundant write is idempotent and the extra refresh has no visible side-effect. It does, however, create a re-entrant call chain on every "last item deselected" event (item click → `Update-SelectAllHeaderCheckBoxState` → `Add_Unchecked` → iterate all items → `Refresh()`), which may become noticeable with large lists.

**Fix (optional):** Suppress the `Unchecked` handler during programmatic state updates by detaching/reattaching the handler around the assignment, or by adding a guard flag:

```powershell
# In Update-SelectAllHeaderCheckBoxState, before setting IsChecked = $false:
$HeaderCheckBox.Tag.SuppressUncheckedHandler = $true
$HeaderCheckBox.IsChecked = $false
$HeaderCheckBox.Tag.SuppressUncheckedHandler = $false

# In Add_Unchecked handler, add early-exit check:
if ($tagData.SuppressUncheckedHandler) { return }
```

Alternatively, document the redundant-refresh as an accepted trade-off.

---

_Reviewed: 2026-06-28_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
