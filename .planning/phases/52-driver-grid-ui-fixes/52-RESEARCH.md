# Phase 52: Driver-Grid UI Fixes - Research

**Researched:** 2026-06-28
**Domain:** WPF CollectionView filtering/sorting, PowerShell WPF integration, upstream port mapping
**Confidence:** HIGH — all findings verified by `git show` on the actual upstream commits and `grep`/`Read` on current fork source.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**DGRID-03 — CopyDrivers validation (port dc801e9)**
- D-01: Port the throw into CLI BuildFFUVM.ps1 (NOT a UI-only MessageBox). Guards both CLI and UI paths.
- D-02: Fork adaptation (critical): place the throw in the END block AFTER config load (>line 775), NOT in BEGIN (~line 593).
- D-03: Fork adaptation: guard the throw with `-and -not $USBOnlyMode`.
- D-04: Do NOT add a disable/grey-out of the CopyDrivers checkbox. No UI MessageBox pre-check (explicitly excluded).

**DGRID-02 — select-all scope + save path (port f09c989, then 42ed281)**
- D-05: Scope header select-all to VISIBLE/filtered rows via `-HeaderSelectionAffectsVisibleItemsOnly` switch. Driver grid opts in; other five callers do NOT.
- D-06: Port `Update-SelectAllHeaderCheckBoxState` scope change together with D-05.
- D-07: Fix `Save-DriversJson` to read from `$State.Data.allDriverModels` with null-guard fallback.
- D-08: Port 42ed281 (header alignment) AFTER f09c989.

**DGRID-01 — filter + sort coexistence (port b4305a1)**
- D-09: Fix the SHARED `Invoke-ListViewSort` in FFUUI.Core.Shared.psm1. Not a driver-only path. No SortDescriptions rewrite.

**Verification**
- D-10: Inline ports matching upstream. Thin Pester for non-WPF logic (Save-DriversJson source; CopyDrivers throw + USBOnlyMode guard). WPF visual behaviors to manual UAT.
- D-11: verify-app is BLOCKING gate. PSScriptAnalyzer clean. version.json + FFUUI.Core.psd1 bumps + CHANGELOG_FORK entry.

**Implementation order:**
1. b4305a1 (DGRID-01)
2. f09c989 (DGRID-02 switch + Update-SelectAll + save)
3. 42ed281 (DGRID-02 alignment)
4. dc801e9 (DGRID-03)
5. Tests

### Claude's Discretion
- Exact Pester test file placement/naming and UAT script wording — follow existing `Tests/` conventions.
- Whether to add the optional UI MessageBox pre-check for DGRID-03 (not required — user chose "lock all as recommended" without it).

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DGRID-01 | Sorting the driver list while a filter is active keeps the filter applied instead of resetting to all rows | b4305a1 diff verified; Invoke-ListViewSort at line 501 confirmed pre-fix; filter-capture + reapply pattern documented |
| DGRID-02 | Selecting/deselecting drivers while filtered preserves hidden-row selections; select-all header correctly scoped and aligned | f09c989 + 42ed281 diffs verified; Save-DriversJson bug at line 221 confirmed; all 6 call sites in Initialize.psm1 mapped |
| DGRID-03 | UI/CLI prevents invalid CopyDrivers configuration by requiring BuildUSBDrive | dc801e9 diff verified; fork insertion point confirmed at line 2607; USBOnlyMode return path verified to exit at ~2366 (before 2606) |
</phase_requirements>

## Summary

Phase 52 ports four upstream commits from `rbalsleyMSFT/FFU` into the fork's modular architecture. All four upstream commits have been pulled via `git show` and their full diffs inspected. The current fork is verified to be at the **pre-fix state** for all three bugs — no partial application detected.

The dominant risk is line-number drift: the fork's `FFUUI.Core.Shared.psm1` and `BuildFFUVM.ps1` have diverged structurally from the upstream versions (the fork extracted 64 functions into modules, reducing BuildFFUVM.ps1 from ~7,790 to ~2,600 lines). All function content within FFUUI.Core is structurally identical to the upstream pre-fix baseline, so the diffs apply as content edits with corrected fork line numbers.

The single fork-specific adaptation beyond line numbers is `dc801e9`: the throw must target line 2607 in the fork's END block (not the upstream's line 5126), and must include the `-and -not $USBOnlyMode` guard mandated by CONTEXT.md Decision D-03.

**Primary recommendation:** Implement in commit order b4305a1 → f09c989 → 42ed281 → dc801e9; use the upstream diff verbatim for content, applying edits at the fork-corrected line numbers documented below.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Filter-sort coexistence (DGRID-01) | Frontend (FFUUI.Core.Shared) | — | CollectionView filter is a WPF view-layer concern; Invoke-ListViewSort lives in the shared UI utilities module |
| Select-all visible scope (DGRID-02 switch) | Frontend (FFUUI.Core.Shared) | — | Header checkbox behavior is UI presentation logic in the shared column builder |
| Save selection from master list (DGRID-02 save) | Frontend (FFUUI.Core.Drivers) | — | Save-DriversJson is driver-specific UI business logic |
| Header alignment (DGRID-02 visual) | Frontend (FFUUI.Core.Shared) | — | WPF layout adjustment in the shared column builder |
| CopyDrivers/BuildUSBDrive validation (DGRID-03) | Build orchestrator (BuildFFUVM.ps1 END) | — | Config-merged parameter validation belongs in the script's PARAMETER VALIDATION block post-config-load; UI calls the script so this covers both paths |

## Standard Stack

No new packages are installed in this phase. All changes are edits to existing PowerShell modules and scripts already present in the fork.

| File | Role | Version |
|------|------|---------|
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` | WPF shared utilities (sort, column builders) | In-repo, no separate package |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1` | Driver-tab UI logic | In-repo |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1` | UI initialization | In-repo |
| `FFUDevelopment/BuildFFUVM.ps1` | Build orchestrator script | In-repo |

## Package Legitimacy Audit

Not applicable — this phase installs no external packages.

## Architecture Patterns

### System Architecture Diagram

```
UI (BuildFFUVM_UI.ps1)
    |
    v
FFUUI.Core.Initialize.psm1
    Add-SelectableGridViewColumn (line 457, lstDriverModels)
    ---> FFUUI.Core.Shared.psm1: Add-SelectableGridViewColumn()
             [gains -HeaderSelectionAffectsVisibleItemsOnly switch via f09c989]
             [header wrapped in Border/Grid/GridViewColumnHeader via 42ed281]
             |
             +---> header CheckBox.Checked/Unchecked handlers
             |         [scope: CollectionView.GetDefaultView() filtered items]
             |
             +---> Update-SelectAllHeaderCheckBoxState()
                       [reads Tag.HeaderSelectionAffectsVisibleItemsOnly]
                       [inspects filtered view when flag is set]

User applies filter (Search-DriverModels in FFUUI.Core.Drivers.psm1)
    |
    v
User clicks column header (Invoke-ListViewSort in FFUUI.Core.Shared.psm1)
    [captures existingFilter from CollectionView before sort]
    [sorts only filtered items when filter active]
    [reassigns ItemsSource, then reapplies captured filter]

User clicks Save (Save-DriversJson in FFUUI.Core.Drivers.psm1 line 221)
    [reads $State.Data.allDriverModels (master list) instead of lstDriverModels.Items]
    [preserves hidden-row selections under active filter]

CLI or UI launches BuildFFUVM.ps1 (END block, post-config-load, line 2607)
    [new throw: CopyDrivers=true AND BuildUSBDrive=false AND not USBOnlyMode]
    [validates config-merged values, not raw CLI args]
```

### Recommended Project Structure

No new files are created. All edits are to existing files:

```
FFUDevelopment/
├── FFUUI.Core/
│   ├── FFUUI.Core.Shared.psm1      # DGRID-01 (Invoke-ListViewSort) + DGRID-02 (Add-SelectableGridViewColumn, Update-SelectAllHeaderCheckBoxState, alignment)
│   ├── FFUUI.Core.Drivers.psm1     # DGRID-02 (Save-DriversJson line 221)
│   └── FFUUI.Core.Initialize.psm1  # DGRID-02 (driver grid opt-in at line 457)
├── BuildFFUVM.ps1                   # DGRID-03 (throw at line 2607)
└── Tests/
    └── Test-Phase52DriverGridFixes.ps1  # new — custom Write-TestResult framework
```

### Anti-Patterns to Avoid

- **DO NOT apply `-HeaderSelectionAffectsVisibleItemsOnly` to any caller other than line 457 (lstDriverModels).** The other five callers (lstWingetResults line 489, lstApplications line 645, lstAppsScriptVariables line 668, lstUSBDrives line 730, lstAdditionalFFUs line 792) must retain full-list behavior — the switch is purely opt-in and caller-specific.
- **DO NOT place the DGRID-03 throw in the BEGIN block** (~line 593). BEGIN runs before config load (~line 775); the throw would fire on CLI args only, not config-merged values.
- **DO NOT omit the USBOnlyMode guard** on the DGRID-03 throw even though USBOnlyMode returns at ~line 2366 before reaching line 2607. The guard is mandated by CONTEXT.md Decision D-03.
- **DO NOT re-call `Search-DriverModels` after sort** as a naive filter re-apply. `Search-DriverModels` resets `ItemsSource` back to `allDriverModels` (Drivers.psm1 lines 180-182), silently undoing the sort.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WPF CollectionView filter capture | Custom filter-tracking dict | `[System.Windows.Data.CollectionViewSource]::GetDefaultView()` + `.Filter` property | Already used by Search-DriverModels; upstream b4305a1 uses identical API |
| Visible-items enumeration | Manual foreach with IsVisible check | Iterate `CollectionViewSource.GetDefaultView()` directly (WPF enumerates only passing-filter items) | CollectionView enumerator skips filtered-out items — this is the documented contract |
| Header layout customization | XAML style resources | Inline WPF object graph (Border > Grid > GridViewColumnHeader) | Consistent with the project's code-behind-only WPF construction pattern |

## Precise Porting Map

### DGRID-01: b4305a1 — Invoke-ListViewSort filter-capture

**Target:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1`
**Function:** `Invoke-ListViewSort` starting at **line 501**
**Current fork state:** Pre-fix. Lines 537-544 read from `ItemsSource` directly with no filter awareness.
**Drift from upstream:** None in function content — structurally identical to upstream pre-fix baseline.

**Changes (verbatim from b4305a1 diff, at fork line numbers):**

1. **Insert filter-capture preamble** after `param(...)` block (after line 506, before the `$State.Flags` check at line 508):
   ```powershell
   # Preserve any active CollectionView filter so sorting does not reset a filtered driver model list
   $existingFilter = $null
   $existingCollectionView = $null
   if ($null -ne $listView.ItemsSource) {
       $existingCollectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
       if ($null -ne $existingCollectionView -and $existingCollectionView.Filter) {
           $existingFilter = $existingCollectionView.Filter
       }
   }
   ```

2. **Replace item-collection block** (fork lines 537-545 — "Get items from ItemsSource or Items collection"):
   ```powershell
   # Build the set of items to sort, enumerating the filtered view if a filter is active
   $currentItemsSource = $listView.ItemsSource
   $itemsToSort = @()
   if ($null -ne $existingCollectionView -and $null -ne $existingFilter) {
       foreach ($vItem in $existingCollectionView) {
           $itemsToSort += $vItem
       }
   }
   elseif ($null -ne $currentItemsSource) {
       $itemsToSort = @($currentItemsSource)
   }
   else {
       $itemsToSort = @($listView.Items)
   }
   ```

3. **Append filter reapplication** after the final `$listView.ItemsSource = $newSortedList.ToArray()` (after fork line 629):
   ```powershell
   # Reapply preserved filter to maintain the user's filtered view
   if ($null -ne $existingFilter) {
       $newView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
       if ($null -ne $newView) {
           $newView.Filter = $existingFilter
       }
   }
   ```

4. **Cosmetic**: Strip verbose comments per upstream diff (optional — do not block on this).

**Callers of Invoke-ListViewSort:** All grids that have sortable column headers. The no-filter path (when `$existingFilter` is null) is UNCHANGED — backward compatible.

---

### DGRID-02: f09c989 — Select-all scope + save fix

**Part A: Add-SelectableGridViewColumn switch and Tag update**
**Target:** `FFUUI.Core.Shared.psm1`, function at **line 295**

1. **Add switch to param block** (after `[string]$IsSelectedPropertyName = "IsSelected"` at line 306):
   ```powershell
   [switch]$HeaderSelectionAffectsVisibleItemsOnly
   ```

2. **Update `$headerTagObject`** (lines 321-324 — replace existing PSCustomObject literal):
   ```powershell
   $headerTagObject = [PSCustomObject]@{
       PropertyName                           = $IsSelectedPropertyName
       ListViewControl                        = $ListView
       HeaderSelectionAffectsVisibleItemsOnly = [bool]$HeaderSelectionAffectsVisibleItemsOnly
   }
   ```

3. **Replace Add_Checked handler body** (lines 333-337 — replace the existing `$collectionToUpdate = if...` one-liner with the scope-aware block):
   ```powershell
   # Select either visible view items only (filtered scope) or the full backing list.
   $collectionToUpdate = @()
   if ($tagData.HeaderSelectionAffectsVisibleItemsOnly -and $null -ne $actualListView.ItemsSource) {
       $collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($actualListView.ItemsSource)
       if ($null -ne $collectionView) {
           foreach ($visibleItem in $collectionView) {
               $collectionToUpdate += $visibleItem
           }
       }
   }
   elseif ($null -ne $actualListView.ItemsSource) {
       $collectionToUpdate = @($actualListView.ItemsSource)
   }
   elseif ($actualListView.HasItems) {
       $collectionToUpdate = @($actualListView.Items)
   }

   if ($collectionToUpdate.Count -gt 0) {
       foreach ($item in $collectionToUpdate) { $item.$($localPropertyName) = $true }
       $actualListView.Items.Refresh()
   }
   ```

4. **Replace Add_Unchecked handler body** (lines 347-352 — same pattern, sets `$false`):
   ```powershell
   # Clear either visible view items only (filtered scope) or the full backing list.
   $collectionToUpdate = @()
   if ($tagData.HeaderSelectionAffectsVisibleItemsOnly -and $null -ne $actualListView.ItemsSource) {
       $collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($actualListView.ItemsSource)
       if ($null -ne $collectionView) {
           foreach ($visibleItem in $collectionView) {
               $collectionToUpdate += $visibleItem
           }
       }
   }
   elseif ($null -ne $actualListView.ItemsSource) {
       $collectionToUpdate = @($actualListView.ItemsSource)
   }
   elseif ($actualListView.HasItems) {
       $collectionToUpdate = @($actualListView.Items)
   }

   if ($collectionToUpdate.Count -gt 0) {
       foreach ($item in $collectionToUpdate) { $item.$($localPropertyName) = $false }
       $actualListView.Items.Refresh()
   }
   ```

**Part B: Update-SelectAllHeaderCheckBoxState scope awareness**
**Target:** `FFUUI.Core.Shared.psm1`, function at **line 415**

Replace the existing `$collectionToInspect` block (lines 423-436) with:
```powershell
# Determine whether this header should evaluate only visible (filtered) rows.
$inspectVisibleItemsOnly = $false
if ($null -ne $HeaderCheckBox.Tag -and $null -ne $HeaderCheckBox.Tag.PSObject.Properties['HeaderSelectionAffectsVisibleItemsOnly']) {
    $inspectVisibleItemsOnly = [bool]$HeaderCheckBox.Tag.HeaderSelectionAffectsVisibleItemsOnly
}

# Build the collection to inspect based on scope (visible view vs full source).
$collectionToInspect = @()
if ($inspectVisibleItemsOnly -and $null -ne $ListView.ItemsSource) {
    $collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($ListView.ItemsSource)
    if ($null -ne $collectionView) {
        foreach ($visibleItem in $collectionView) {
            $collectionToInspect += $visibleItem
        }
    }
}
elseif ($null -ne $ListView.ItemsSource) {
    $collectionToInspect = @($ListView.ItemsSource)
}
elseif ($ListView.HasItems) {
    $collectionToInspect = @($ListView.Items)
}

# If no items are available in the selected scope, force unchecked.
if ($collectionToInspect.Count -eq 0) {
    $HeaderCheckBox.IsChecked = $false
    return
}
```
Also update the `$totalItemCount` line to remove the trailing comment (cosmetic).

**Part C: Save-DriversJson source fix**
**Target:** `FFUUI.Core.Drivers.psm1`, **line 221**

Replace:
```powershell
$selectedDrivers = @($State.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected })
```
With:
```powershell
# Save from the master model list so filtered-out selected rows are preserved.
$driverSelectionSource = if ($null -ne $State.Data.allDriverModels) { $State.Data.allDriverModels } else { $State.Controls.lstDriverModels.Items }
$selectedDrivers = @($driverSelectionSource | Where-Object { $_.IsSelected })
```

**Part D: Initialize.psm1 driver grid opt-in**
**Target:** `FFUUI.Core.Initialize.psm1`, **line 457**

Change:
```powershell
Add-SelectableGridViewColumn -ListView $State.Controls.lstDriverModels -State $State -HeaderCheckBoxKeyName "chkSelectAllDriverModels" -ColumnWidth 70
```
To:
```powershell
# Add the selectable column and scope header select-all to visible filtered rows.
Add-SelectableGridViewColumn -ListView $State.Controls.lstDriverModels -State $State -HeaderCheckBoxKeyName "chkSelectAllDriverModels" -ColumnWidth 70 -HeaderSelectionAffectsVisibleItemsOnly
```

**DO NOT change:** lines 489, 645, 668, 730, 792 (lstWingetResults, lstApplications, lstAppsScriptVariables, lstUSBDrives, lstAdditionalFFUs) — these keep full-list behavior.

---

### DGRID-02: 42ed281 — Header checkbox alignment

**Target:** `FFUUI.Core.Shared.psm1`, inside `Add-SelectableGridViewColumn`
**Depends on:** f09c989 must be applied first (42ed281 builds on f09c989's header region).

**Change 1:** Add `VerticalAlignment` to `$headerCheckBox` (after the existing HorizontalAlignment line, ~fork line 318 post-f09c989):
```powershell
$headerCheckBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
```

**Change 2:** After the `Add_Unchecked` handler closing `})` and BEFORE `$State.Controls[$HeaderCheckBoxKeyName] = $headerCheckBox`, insert the alignment wrapper and explicit header:
```powershell
# Wrap the header checkbox in a stretched container so it centers the same way as row cells.
# Apply a small left inset to mirror the Fluent ListViewItem content padding used by data rows.
$headerBorder = New-Object System.Windows.Controls.Border
$headerBorder.Padding = New-Object System.Windows.Thickness(12, 0, 0, 0)
$headerBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
$headerBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch

$headerGrid = New-Object System.Windows.Controls.Grid
$headerGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
$headerGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
$headerGrid.Children.Add($headerCheckBox) | Out-Null
$headerBorder.Child = $headerGrid

# Use an explicit GridViewColumnHeader so we can remove the default header padding
# and control the checkbox alignment explicitly.
$selectableHeader = New-Object System.Windows.Controls.GridViewColumnHeader
$selectableHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Stretch
$selectableHeader.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Stretch
$selectableHeader.Padding = New-Object System.Windows.Thickness(0)
$selectableHeader.Margin = New-Object System.Windows.Thickness(0)
$selectableHeader.Content = $headerBorder
```

**Change 3:** Replace `$selectableColumn.Header = $headerCheckBox` with `$selectableColumn.Header = $selectableHeader`.

---

### DGRID-03: dc801e9 — CopyDrivers dependency validation (fork-adapted)

**Target:** `FFUDevelopment/BuildFFUVM.ps1`
**Insertion point:** After **line 2606** (`###PARAMETER VALIDATION`), before **line 2607** (current `#Validate drivers folder` which becomes line 2613 after insertion).

**Upstream content (verbatim from dc801e9):**
```powershell
#Validate CopyDrivers dependency on BuildUSBDrive
if ($CopyDrivers -and (-not $BuildUSBDrive)) {
    WriteLog "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true"
    throw "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true. Please set -BuildUSBDrive to `$true and try again."
}
```

**Fork adaptation (Decision D-03):** Add `-and -not $USBOnlyMode` guard:
```powershell
#Validate CopyDrivers dependency on BuildUSBDrive
if ($CopyDrivers -and (-not $BuildUSBDrive) -and (-not $USBOnlyMode)) {
    WriteLog "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true"
    throw "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true. Please set -BuildUSBDrive to `$true and try again."
}
```

**Why the guard is belt-and-suspenders (verified):** The USBOnlyMode block (lines 1869-2366) exits with `return` at approximately line 2366. This `return` precedes the `###PARAMETER VALIDATION` block at line 2606, so USBOnlyMode builds never reach the throw. However, CONTEXT.md Decision D-03 mandates the guard regardless, and it is safe to include.

**Why END block (verified):** Config file is loaded at line 775 inside the END block. The throw at line 2607 (also END block) therefore sees config-merged values, not raw CLI args only. The BEGIN block ends at line 694.

## Common Pitfalls

### Pitfall 1: Applying the switch to non-driver-grid callers
**What goes wrong:** If `-HeaderSelectionAffectsVisibleItemsOnly` is added to lstWingetResults, lstApplications, lstAppsScriptVariables, lstUSBDrives, or lstAdditionalFFUs, their select-all header would stop affecting hidden items during search — unexpected behavior change for unrelated grids.
**Why it happens:** The switch is global; there are 6 call sites in Initialize.psm1 (lines 457, 489, 645, 668, 730, 792).
**How to avoid:** Only line 457 (lstDriverModels) gets the switch. Grep Initialize.psm1 for `Add-SelectableGridViewColumn` and verify exactly one line has `-HeaderSelectionAffectsVisibleItemsOnly`.
**Warning signs:** Other tabs' select-all behavior breaks during filter.

### Pitfall 2: Placing the DGRID-03 throw in the BEGIN block
**What goes wrong:** BEGIN runs before config load (~line 775). A user running with a config file where CopyDrivers=true/BuildUSBDrive=false would see the throw fire on the raw param defaults (which default to $false), not the effective config-merged values.
**Why it happens:** The fork has a BEGIN block (lines 591-694) with cross-parameter validation — it looks like the natural place for a dependency throw.
**How to avoid:** Insert at line 2607 in the END block, immediately after `###PARAMETER VALIDATION` (line 2606) and before `#Validate drivers folder`.
**Warning signs:** throw fires incorrectly when running with a config file.

### Pitfall 3: Naive filter re-application via Search-DriverModels
**What goes wrong:** `Search-DriverModels` (Drivers.psm1 lines 180-182) resets `ItemsSource` back to the full `allDriverModels` list before applying the CollectionView filter. Calling it as a post-sort step silently undoes the sort.
**Why it happens:** Search-DriverModels is the established filter entry point, so it looks reusable.
**How to avoid:** Capture and reapply the raw filter predicate (`.Filter` property) as done in b4305a1 — bypass Search-DriverModels entirely.

### Pitfall 4: Enumerating `$listView.ItemsSource` vs iterating `CollectionViewSource.GetDefaultView()`
**What goes wrong:** `@($listView.ItemsSource)` returns ALL items regardless of any active CollectionView filter. The filter is applied only when iterating via `[System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)`.
**Why it happens:** `ItemsSource` is the backing collection; the CollectionView is the filtered/sorted view over it — two different objects.
**How to avoid:** For visible-items-only scope, always use `GetDefaultView()` enumerator. For full-list scope, use `@($listView.ItemsSource)`.

### Pitfall 5: 42ed281 without f09c989 applied first
**What goes wrong:** 42ed281 adds `$headerCheckBox.VerticalAlignment` and replaces `$selectableColumn.Header = $headerCheckBox`. If applied to the pre-f09c989 code, the `$selectableHeader` variable references the old headerCheckBox object without the Tag's `HeaderSelectionAffectsVisibleItemsOnly` field — alignment works but scope logic is absent.
**How to avoid:** Apply in strict order: b4305a1 → f09c989 → 42ed281 → dc801e9.

## Runtime State Inventory

Not applicable — this is a code-only port phase with no rename, no data migration, and no stored-state changes.

## Code Examples

### Pattern: CollectionView filter capture and reapply (b4305a1)
```powershell
# Source: git show b4305a1 (rbalsleyMSFT/FFU upstream)
$existingFilter = $null
$existingCollectionView = $null
if ($null -ne $listView.ItemsSource) {
    $existingCollectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
    if ($null -ne $existingCollectionView -and $existingCollectionView.Filter) {
        $existingFilter = $existingCollectionView.Filter
    }
}
# ... sort logic ...
$listView.ItemsSource = $null
$listView.ItemsSource = $newSortedList.ToArray()
if ($null -ne $existingFilter) {
    $newView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
    if ($null -ne $newView) { $newView.Filter = $existingFilter }
}
```

### Pattern: Visible-items-only scope via CollectionView enumeration (f09c989)
```powershell
# Source: git show f09c989 (rbalsleyMSFT/FFU upstream)
$collectionToUpdate = @()
if ($tagData.HeaderSelectionAffectsVisibleItemsOnly -and $null -ne $actualListView.ItemsSource) {
    $collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($actualListView.ItemsSource)
    if ($null -ne $collectionView) {
        foreach ($visibleItem in $collectionView) {
            $collectionToUpdate += $visibleItem
        }
    }
}
elseif ($null -ne $actualListView.ItemsSource) {
    $collectionToUpdate = @($actualListView.ItemsSource)
}
elseif ($actualListView.HasItems) {
    $collectionToUpdate = @($actualListView.Items)
}
```

### Pattern: allDriverModels null-guard for Save-DriversJson (f09c989)
```powershell
# Source: git show f09c989 (rbalsleyMSFT/FFU upstream)
$driverSelectionSource = if ($null -ne $State.Data.allDriverModels) { $State.Data.allDriverModels } else { $State.Controls.lstDriverModels.Items }
$selectedDrivers = @($driverSelectionSource | Where-Object { $_.IsSelected })
```

### Pattern: CopyDrivers dependency throw with fork guard (dc801e9 + D-03)
```powershell
# Source: git show dc801e9 + fork adaptation (CONTEXT.md D-03)
if ($CopyDrivers -and (-not $BuildUSBDrive) -and (-not $USBOnlyMode)) {
    WriteLog "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true"
    throw "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true. Please set -BuildUSBDrive to `$true and try again."
}
```

## Validation Architecture

> `workflow.nyquist_validation` is absent from `.planning/config.json` — treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Custom Write-TestResult framework (NOT Pester — all existing Tests/Test-Phase*.ps1 files use this pattern) |
| Config file | None — standalone script |
| Quick run command | `powershell -NoProfile -ExecutionPolicy Bypass -File .\FFUDevelopment\Tests\Test-Phase52DriverGridFixes.ps1` |
| Full suite command | Same — phase test is self-contained |

**Note on Pester vs custom framework:** CONTEXT.md D-10 says "thin Pester" for non-WPF logic. However, the project's actual test files (Test-Phase51Correctness.ps1, Test-DriverValidationMessages.ps1, all others in FFUDevelopment/Tests/) uniformly use the custom `Write-TestResult` framework — no Pester `.Tests.ps1` files exist in the Tests/ directory. Per CONTEXT.md D-10 "exact test file placement/naming — follow existing Tests/ conventions," the custom framework is the correct pattern. The planner should use the custom framework in `Test-Phase52DriverGridFixes.ps1`.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| DGRID-01 | Filter persists after sort (WPF CollectionView) | Manual UAT only | N/A | WPF CollectionView is not headlessly testable; requires live UI |
| DGRID-01 | Filter-capture preamble present in source | Content match | `powershell ... Test-Phase52DriverGridFixes.ps1` | Source regex on FFUUI.Core.Shared.psm1 |
| DGRID-02 | Save-DriversJson reads allDriverModels when non-null | Content match + logic | `powershell ... Test-Phase52DriverGridFixes.ps1` | Verify line 221 replacement; optionally mock with PSCustomObject |
| DGRID-02 | select-all visible scope under filter | Manual UAT only | N/A | Requires live WPF UI with active filter |
| DGRID-02 | Header tri-state desyncs correctly | Manual UAT only | N/A | Requires live WPF UI |
| DGRID-02 | Header checkbox alignment | Manual UAT only | N/A | Visual inspection |
| DGRID-02 | Switch present in param block; only driver grid opts in | Content match | `powershell ... Test-Phase52DriverGridFixes.ps1` | Grep Shared.psm1 for switch; grep Initialize.psm1 for all 6 call sites |
| DGRID-03 | Throw fires: CopyDrivers=true, BuildUSBDrive=false, USBOnlyMode=false | Source regex + logic | `powershell ... Test-Phase52DriverGridFixes.ps1` | Regex for throw wording in BuildFFUVM.ps1; optional logic mock |
| DGRID-03 | Throw suppressed when USBOnlyMode=true | Source regex | `powershell ... Test-Phase52DriverGridFixes.ps1` | Verify `-not $USBOnlyMode` guard present |
| DGRID-03 | Throw is in END block after config load | Line-number check | `powershell ... Test-Phase52DriverGridFixes.ps1` | Assert throw line > 775 (config load) |

### Sampling Rate

- **Per task commit:** `powershell -NoProfile -ExecutionPolicy Bypass -File .\FFUDevelopment\Tests\Test-Phase52DriverGridFixes.ps1`
- **Per wave merge:** Same (all automated checks are in the single test file)
- **Phase gate:** All automated checks green + verify-app BLOCKING gate + manual UAT before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1` — covers automated assertions for DGRID-01/02/03 (content-match and logic tests). Does not exist yet — must be created in Wave 0 (or as a dedicated Wave 1 task before implementation tasks).

### Manual UAT Scenarios (not automatable)

These require a running instance of the FFU Builder UI:

1. **DGRID-01:** Open Drivers tab, type a search term to filter, click a column header to sort — verify rows remain filtered (no reset to full list).
2. **DGRID-02 select-all scope:** With filter active, click the header checkbox — verify only visible rows get selected/deselected; hidden rows retain their previous state.
3. **DGRID-02 tri-state:** With 3 rows visible (1 selected, 2 unselected), click the header — verify it selects all 3; click header again — verify it deselects all 3. Deselect one visible row — verify header goes indeterminate.
4. **DGRID-02 save under filter:** Select 2 rows in full list, apply filter (hiding one selected row), click Save — verify saved JSON includes the hidden selected row.
5. **DGRID-02 alignment:** Open Drivers tab — verify the header checkbox is horizontally centered and vertically aligned with the row checkboxes.
6. **DGRID-03 UI:** Set CopyDrivers=true and BuildUSBDrive=false in the UI, attempt to start build — verify clear error message (thrown by BuildFFUVM.ps1, surfaced to UI log).

## Version and Changelog Mechanics

### Files to bump

| File | Field | Current | Target | Rule |
|------|-------|---------|--------|------|
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1` | `ModuleVersion` | `0.0.21` | `0.0.22` | PATCH: UI module bug fixes |
| `FFUDevelopment/version.json` | `version` (main) | `1.12.0` | `1.12.1` | PATCH: any subcomponent version change requires main PATCH bump |
| `FFUDevelopment/version.json` | `FFUUI.Core.version` | `0.0.21` | `0.0.22` | Match .psd1 |
| `FFUDevelopment/version.json` | `buildDate` | — | current date | Per versioning policy |

**BuildFFUVM.ps1:** This is a script, not a module — it has no .psd1. Its changes are covered by the main version bump. The script does not hardcode a version; it reads from `version.json` at runtime.

**Note:** `WinPEDeployFFUFiles/ApplyFFU.ps1` hardcodes `$version` — per CLAUDE.md, this must be updated when the main version changes. Target: `1.12.1`.

### CHANGELOG_FORK.md entry format (follow existing pattern)

```
## v1.12.1 - [date]
### Fixed
- DGRID-01: Sorting the driver list while a filter is active now preserves the filter (port b4305a1)
- DGRID-02: Selecting/deselecting drivers under a filter and saving now preserves hidden-row selections (port f09c989)
- DGRID-02: Header select-all checkbox correctly scoped to visible/filtered rows only for the driver grid (port f09c989)
- DGRID-02: Header checkbox alignment fixed — now centers consistently with row checkboxes (port 42ed281)
- DGRID-03: CLI and UI now throw a clear error when CopyDrivers=true but BuildUSBDrive=false (port dc801e9, fork-adapted with USBOnlyMode guard)
```

## Open Questions

1. **ApplyFFU.ps1 version update requirement**
   - What we know: CLAUDE.md says to update `$version` in `WinPEDeployFFUFiles/ApplyFFU.ps1` when main version changes.
   - What's unclear: Whether this file exists at the expected path and whether the planner should treat it as a task or a note in the version bump task.
   - Recommendation: Include as a sub-item of the version bump task; grep for the file to confirm path before execution.

2. **verify-app scope for WPF changes**
   - What we know: verify-app runs PSScriptAnalyzer + Pester (or custom tests) + module import. WPF behavior is not verified headlessly.
   - What's unclear: Whether verify-app has any WPF smoke test or relies entirely on syntax/import checks for UI changes.
   - Recommendation: Treat verify-app as gating syntax/import correctness; route WPF behavior to the manual UAT scenarios above.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| git (upstream remote) | Reading commit diffs | Already used | — | N/A |
| PowerShell 5.1+ | Executing build/tests | Confirmed (Windows 10) | 5.1 / 7+ | — |
| PSScriptAnalyzer | Post-implementation verify-app | Assumed present | — | Install via Install-Module |
| FFUUI.Core module | Module import check | In-repo | 0.0.21 | — |

## Security Domain

Not applicable — this phase contains no authentication, session management, access control, cryptography, or network communication changes. All changes are UI logic (WPF state) and build-script parameter validation.

## Sources

### Primary (HIGH confidence)
- `git show b4305a1` — full diff, `Invoke-ListViewSort` filter-fix; content verified line-by-line against fork
- `git show f09c989` — full diff, `Add-SelectableGridViewColumn` switch + `Update-SelectAllHeaderCheckBoxState` + `Save-DriversJson` fix; all three files' diffs verified
- `git show 42ed281` — full diff, header alignment wrapper; verified as 25-line insertion
- `git show dc801e9` — full diff, 6-line throw insertion; fork placement verified at line 2607
- `Read FFUUI.Core.Shared.psm1` — confirmed pre-fix state for all three functions; confirmed precise line numbers (Add-SelectableGridViewColumn: 295, Update-SelectAllHeaderCheckBoxState: 415, Invoke-ListViewSort: 501)
- `Read FFUUI.Core.Drivers.psm1` — confirmed Save-DriversJson bug at line 221 (`lstDriverModels.Items`)
- `grep Initialize.psm1 Add-SelectableGridViewColumn` — confirmed 6 call sites (457, 489, 645, 668, 730, 792)
- `grep BuildFFUVM.ps1` — confirmed BEGIN (591), END (696), config load (775), USBOnlyMode block (1869-2366), PARAMETER VALIDATION (2606)

### Secondary (MEDIUM confidence)
- CONTEXT.md decisions D-01 through D-11 — locked by adversarial design review; used as authoritative constraints throughout

### Tertiary (LOW confidence — no unverified claims)
None.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `WinPEDeployFFUFiles/ApplyFFU.ps1` must be updated to `$version = '1.12.1'` | Version Mechanics | File may have moved or naming may differ — grep to confirm before editing |
| A2 | verify-app relies on PSScriptAnalyzer + import checks for WPF changes (no headless WPF smoke test) | Validation Architecture | If verify-app has a WPF check, it may catch additional issues — treat as bonus |

## Metadata

**Confidence breakdown:**
- Porting map: HIGH — all verified from `git show` + live fork grep
- Line numbers: HIGH — confirmed from `Read` + `grep` on current fork files
- Version mechanics: HIGH — verified from version.json + FFUUI.Core.psd1 + CLAUDE.md rules
- Test architecture: HIGH — verified from all existing Tests/*.ps1 files (custom framework pattern)
- USBOnlyMode return path: HIGH — verified by reading lines 1869-2380 in BuildFFUVM.ps1; return at ~2366

**Research date:** 2026-06-28
**Valid until:** 2026-07-28 (stable codebase; fork is under active development — re-verify line numbers if any other phase touches the same files before implementation)
