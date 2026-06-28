# Phase 52: Driver-Grid UI Fixes - Pattern Map

**Mapped:** 2026-06-28
**Files analyzed:** 6 (1 new, 5 edited)
**Analogs found:** 6 / 6

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1` | test | batch (content-match + logic) | `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` | exact |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` (Invoke-ListViewSort) | utility | event-driven (WPF sort) | self (current pre-fix function at line 501) | self-edit |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` (Add-SelectableGridViewColumn) | utility | event-driven (WPF column builder) | self (current pre-fix function at line 295) | self-edit |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` (Update-SelectAllHeaderCheckBoxState) | utility | event-driven (WPF header state) | self (current pre-fix function at line 415) | self-edit |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1` (Save-DriversJson) | service | CRUD (save selected to JSON) | self (current pre-fix function at line 215) | self-edit |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1` (driver grid call site) | config | request-response | self (current call at line 457) | self-edit |
| `FFUDevelopment/BuildFFUVM.ps1` (PARAMETER VALIDATION throw) | middleware | request-response | self (existing `###PARAMETER VALIDATION` block at line 2606) | self-edit |

---

## Pattern Assignments

### `FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1` (new test file)

**Analog:** `FFUDevelopment/Tests/Test-Phase51Correctness.ps1`

**No Pester `.Tests.ps1` files exist in `FFUDevelopment/Tests/`.** All 13 existing test files use the custom `Write-TestResult` framework. This file MUST follow the same pattern.

**File header pattern** (Test-Phase51Correctness.ps1 lines 1-29):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Phase 52 correctness fixes: DGRID-01, DGRID-02, DGRID-03.

.DESCRIPTION
    Content-match and logic assertions covering:
    - DGRID-01: Filter persists after sort (Invoke-ListViewSort filter-capture preamble)
    - DGRID-02: Save-DriversJson reads allDriverModels master list (not lstDriverModels.Items)
    - DGRID-02: -HeaderSelectionAffectsVisibleItemsOnly switch present; only driver grid opts in
    - DGRID-03: CopyDrivers dependency throw present in END block with USBOnlyMode guard

    Uses the repo's custom Write-TestResult framework (NOT Pester).
    WPF CollectionView visual behaviors (filter-sort coexistence, select-all scope,
    header tri-state, header alignment) are human-UAT only.

.NOTES
    Version: 1.0.0
    Run command: powershell -NoProfile -ExecutionPolicy Bypass -File .\FFUDevelopment\Tests\Test-Phase52DriverGridFixes.ps1
    Human-UAT only (not automated):
      - Filter persists visually after sort (requires live WPF UI)
      - Select-all visible scope under active filter (requires live WPF UI)
      - Header tri-state sync (requires live WPF UI)
      - Header checkbox alignment (requires live visual inspection)
#>

param(
    [switch]$Verbose
)
```

**Write-TestResult helper + counters** (Test-Phase51Correctness.ps1 lines 31-59 — verbatim, use in every test file):
```powershell
$script:PassCount = 0
$script:FailCount = 0
$script:TestResults = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Passed   = $Passed
        Message  = $Message
    }

    if ($Passed) {
        $script:PassCount++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    }
    else {
        $script:FailCount++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "         $Message" -ForegroundColor Yellow
        }
    }
}
```

**Setup block pattern** (Test-Phase51Correctness.ps1 lines 63-79):
```powershell
# =============================================================================
# Setup
# =============================================================================
$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$SharedPsm1   = Join-Path $FFUDevelopmentPath "FFUUI.Core\FFUUI.Core.Shared.psm1"
$DriversPsm1  = Join-Path $FFUDevelopmentPath "FFUUI.Core\FFUUI.Core.Drivers.psm1"
$InitPsm1     = Join-Path $FFUDevelopmentPath "FFUUI.Core\FFUUI.Core.Initialize.psm1"
$BuildScript  = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"

Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Phase 52 Driver-Grid UI Fixes - DGRID-01 / DGRID-02 / DGRID-03" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
```

**Section banner pattern** (Test-Phase51Correctness.ps1 line 84):
```powershell
Write-Host "DGRID-01: Invoke-ListViewSort filter-capture preamble" -ForegroundColor Yellow
Write-Host ""
```

**Content-match assertion pattern** (Test-Phase51Correctness.ps1 lines 89-110 — use try/catch + Get-Content -Raw):
```powershell
try {
    $sharedContent = Get-Content -Path $SharedPsm1 -Raw -ErrorAction Stop

    $hasFilterCapture = $sharedContent -match '\$existingFilter\s*=\s*\$null'
    Write-TestResult -TestName "Shared.psm1 has filter-capture preamble (\$existingFilter = \$null)" -Passed $hasFilterCapture `
        -Message "$(if (-not $hasFilterCapture) { 'Filter-capture preamble missing from Invoke-ListViewSort (b4305a1 not ported)' })"

    $hasCollectionViewCapture = $sharedContent -match 'existingCollectionView.*GetDefaultView'
    Write-TestResult -TestName "Shared.psm1 captures CollectionView before sort" -Passed $hasCollectionViewCapture `
        -Message "$(if (-not $hasCollectionViewCapture) { 'GetDefaultView capture missing from Invoke-ListViewSort' })"

    $hasFilterReapply = $sharedContent -match 'newView\.Filter\s*=\s*\$existingFilter'
    Write-TestResult -TestName "Shared.psm1 reapplies captured filter after sort" -Passed $hasFilterReapply `
        -Message "$(if (-not $hasFilterReapply) { 'Filter reapplication missing after ItemsSource reassignment' })"
}
catch {
    Write-TestResult -TestName "Read FFUUI.Core.Shared.psm1" -Passed $false -Message $_.Exception.Message
}
```

**Pure-function logic test pattern** (Test-Phase51Correctness.ps1 lines 432-465 — local copy of pure function for isolated testing):
```powershell
# Local copy of pure logic — mirrors Save-DriversJson source selection verbatim
# so tests stay valid even without WPF runtime
function Test-DriverSelectionSource-Local {
    param([object]$allDriverModels, [object]$lstItems)
    $driverSelectionSource = if ($null -ne $allDriverModels) { $allDriverModels } else { $lstItems }
    return $driverSelectionSource
}

$selectionTests = @(
    @{ allDriverModels = @('A','B','C'); lstItems = @('X'); Expected = @('A','B','C'); Label = 'allDriverModels non-null: reads master list (D-07)' }
    @{ allDriverModels = $null;          lstItems = @('X'); Expected = @('X');         Label = 'allDriverModels null: falls back to lstItems (D-07 null guard)' }
)
foreach ($tc in $selectionTests) {
    $result = Test-DriverSelectionSource-Local -allDriverModels $tc.allDriverModels -lstItems $tc.lstItems
    $passed = ($result -join ',') -eq ($tc.Expected -join ',')
    Write-TestResult -TestName $tc.Label -Passed $passed `
        -Message "$(if (-not $passed) { "Expected '$($tc.Expected -join ',')', got '$($result -join ',')'" })"
}
```

**Summary + exit code pattern** (Test-Phase51Correctness.ps1 lines 472-487 — verbatim):
```powershell
# =============================================================================
# Test Summary
# =============================================================================
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Total Tests : $($script:PassCount + $script:FailCount)" -ForegroundColor White
Write-Host "Passed      : $script:PassCount" -ForegroundColor Green
Write-Host "Failed      : $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($script:FailCount -eq 0) {
    Write-Host "All Phase 52 tests passed. DGRID-01, DGRID-02, DGRID-03 implementation verified." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "CRITICAL: $($script:FailCount) test(s) failed. Review output above." -ForegroundColor Red
    exit 1
}
```

---

### `FFUUI.Core.Shared.psm1` — `Invoke-ListViewSort` (DGRID-01, b4305a1)

**Source file:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1`
**Function start:** line 501
**Edit type:** Three insertions; no deletions outside the replaced block.

**Current item-collection block to REPLACE** (lines 537-545 — the pre-fix code with no filter awareness):
```powershell
    # Get items from ItemsSource or Items collection
    $currentItemsSource = $listView.ItemsSource
    $itemsToSort = @()
    if ($null -ne $currentItemsSource) {
        $itemsToSort = @($currentItemsSource)
    }
    else {
        $itemsToSort = @($listView.Items)
    }
```

**Insertion 1 — filter-capture preamble:** INSERT after `param(...)` closing `}` (after line 506, before the `$State.Flags` check at line 508):
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

**Insertion 2 — filter-aware item collection:** REPLACE lines 537-545 with:
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

**Current final assignment** (lines 628-629 — read_first anchor, append after line 629):
```powershell
    $listView.ItemsSource = $null
    $listView.ItemsSource = $newSortedList.ToArray()
```

**Insertion 3 — filter reapplication:** APPEND after line 629 (after the final `$listView.ItemsSource = $newSortedList.ToArray()`):
```powershell
    # Reapply preserved filter to maintain the user's filtered view
    if ($null -ne $existingFilter) {
        $newView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
        if ($null -ne $newView) {
            $newView.Filter = $existingFilter
        }
    }
```

---

### `FFUUI.Core.Shared.psm1` — `Add-SelectableGridViewColumn` (DGRID-02, f09c989 + 42ed281)

**Source file:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1`
**Function start:** line 295

**Current param block** (lines 296-307 — add switch after line 306):
```powershell
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView,
        [Parameter(Mandatory)]
        [psobject]$State,
        [Parameter(Mandatory)]
        [string]$HeaderCheckBoxKeyName,
        [Parameter(Mandatory)]
        [double]$ColumnWidth,
        [string]$IsSelectedPropertyName = "IsSelected"
    )
```
ADD after `[string]$IsSelectedPropertyName = "IsSelected"` (line 306):
```powershell
        [switch]$HeaderSelectionAffectsVisibleItemsOnly
```

**Current `$headerTagObject`** (lines 321-324 — replace this PSCustomObject literal):
```powershell
    $headerTagObject = [PSCustomObject]@{
        PropertyName    = $IsSelectedPropertyName
        ListViewControl = $ListView 
    }
```
REPLACE WITH:
```powershell
    $headerTagObject = [PSCustomObject]@{
        PropertyName                           = $IsSelectedPropertyName
        ListViewControl                        = $ListView
        HeaderSelectionAffectsVisibleItemsOnly = [bool]$HeaderSelectionAffectsVisibleItemsOnly
    }
```

**Current `Add_Checked` handler body** (lines 333-337 — the one-liner to replace):
```powershell
            $collectionToUpdate = if ($null -ne $actualListView.ItemsSource) { $actualListView.ItemsSource } else { $actualListView.Items }
            if ($null -ne $collectionToUpdate) {
                foreach ($item in $collectionToUpdate) { $item.$($localPropertyName) = $true }
                $actualListView.Items.Refresh()
            }
```
REPLACE WITH (scope-aware block, sets `$true`):
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

**Current `Add_Unchecked` handler body** (lines 347-352 — the one-liner to replace):
```powershell
                $collectionToUpdate = if ($null -ne $actualListView.ItemsSource) { $actualListView.ItemsSource } else { $actualListView.Items }
                if ($null -ne $collectionToUpdate) {
                    foreach ($item in $collectionToUpdate) { $item.$($localPropertyName) = $false }
                    $actualListView.Items.Refresh()
                }
```
REPLACE WITH (scope-aware block, sets `$false`):
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

**42ed281 — Header checkbox alignment (apply AFTER f09c989):**

ADD `$headerCheckBox.VerticalAlignment` after the existing `$headerCheckBox.HorizontalAlignment` line (~line 318 post-f09c989):
```powershell
    $headerCheckBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
```

After the `Add_Unchecked` handler closing `})` and BEFORE `$State.Controls[$HeaderCheckBoxKeyName] = $headerCheckBox` (currently line 355), INSERT the alignment wrapper:
```powershell
    # Wrap the header checkbox in a stretched container so it centers the same way as row cells.
    $headerBorder = New-Object System.Windows.Controls.Border
    $headerBorder.Padding = New-Object System.Windows.Thickness(12, 0, 0, 0)
    $headerBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
    $headerBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch

    $headerGrid = New-Object System.Windows.Controls.Grid
    $headerGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
    $headerGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
    $headerGrid.Children.Add($headerCheckBox) | Out-Null
    $headerBorder.Child = $headerGrid

    $selectableHeader = New-Object System.Windows.Controls.GridViewColumnHeader
    $selectableHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Stretch
    $selectableHeader.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Stretch
    $selectableHeader.Padding = New-Object System.Windows.Thickness(0)
    $selectableHeader.Margin = New-Object System.Windows.Thickness(0)
    $selectableHeader.Content = $headerBorder
```

**Current column header assignment** (line 359 — replace to use `$selectableHeader`):
```powershell
    $selectableColumn.Header = $headerCheckBox
```
REPLACE WITH:
```powershell
    $selectableColumn.Header = $selectableHeader
```

---

### `FFUUI.Core.Shared.psm1` — `Update-SelectAllHeaderCheckBoxState` (DGRID-02, f09c989)

**Source file:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1`
**Function start:** line 415

**Current `$collectionToInspect` block to REPLACE** (lines 423-436 — the pre-fix code with no filter awareness):
```powershell
    $collectionToInspect = $null
    if ($null -ne $ListView.ItemsSource) {
        $collectionToInspect = @($ListView.ItemsSource)
    }
    elseif ($ListView.HasItems) {
        # Check if Items collection has items and ItemsSource is null
        $collectionToInspect = @($ListView.Items)
    }

    # If no items to inspect (either ItemsSource was null and Items was empty, or ItemsSource was empty)
    if ($null -eq $collectionToInspect -or $collectionToInspect.Count -eq 0) {
        $HeaderCheckBox.IsChecked = $false
        return
    }
```
REPLACE WITH:
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

The rest of the function (selectedCount comparison, tri-state assignment) is UNCHANGED.

---

### `FFUUI.Core.Drivers.psm1` — `Save-DriversJson` (DGRID-02, f09c989)

**Source file:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1`
**Function start:** line 215

**Current bug line** (line 221 — exact text to replace):
```powershell
    $selectedDrivers = @($State.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected })
```
REPLACE WITH:
```powershell
    # Save from the master model list so filtered-out selected rows are preserved.
    $driverSelectionSource = if ($null -ne $State.Data.allDriverModels) { $State.Data.allDriverModels } else { $State.Controls.lstDriverModels.Items }
    $selectedDrivers = @($driverSelectionSource | Where-Object { $_.IsSelected })
```

Context anchor (line 220 — read_first verification):
```powershell
    WriteLog "Save-DriversJson function called."
```

---

### `FFUUI.Core.Initialize.psm1` — driver grid call site (DGRID-02, f09c989)

**Source file:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1`

**Current call at line 457** (exact text to replace):
```powershell
    Add-SelectableGridViewColumn -ListView $State.Controls.lstDriverModels -State $State -HeaderCheckBoxKeyName "chkSelectAllDriverModels" -ColumnWidth 70
```
REPLACE WITH:
```powershell
    # Add the selectable column and scope header select-all to visible filtered rows.
    Add-SelectableGridViewColumn -ListView $State.Controls.lstDriverModels -State $State -HeaderCheckBoxKeyName "chkSelectAllDriverModels" -ColumnWidth 70 -HeaderSelectionAffectsVisibleItemsOnly
```

**The five callers that must NOT be changed** (lines 489, 645, 668, 730, 792):
```powershell
    Add-SelectableGridViewColumn -ListView $State.Controls.lstWingetResults -State $State -HeaderCheckBoxKeyName "chkSelectAllWingetResults" -ColumnWidth 60
    # ... and four more — none gets -HeaderSelectionAffectsVisibleItemsOnly
```

---

### `BuildFFUVM.ps1` — CopyDrivers dependency validation (DGRID-03, dc801e9 fork-adapted)

**Source file:** `FFUDevelopment/BuildFFUVM.ps1`

**Anchor context** (lines 2605-2609 — read_first to confirm insertion point):
```powershell
Set-Progress -Percentage 2 -Message "Validating parameters..."
###PARAMETER VALIDATION

#Validate drivers folder
if ($InstallDrivers -or $CopyDrivers) {
```

Line 2606 is `###PARAMETER VALIDATION`. Line 2607 is blank. Line 2608 is `#Validate drivers folder`. The new throw block inserts as the FIRST item after `###PARAMETER VALIDATION`, between lines 2606 and 2608.

**Insert at line 2607** (between `###PARAMETER VALIDATION` and `#Validate drivers folder`):
```powershell
#Validate CopyDrivers dependency on BuildUSBDrive
if ($CopyDrivers -and (-not $BuildUSBDrive) -and (-not $USBOnlyMode)) {
    WriteLog "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true"
    throw "-CopyDrivers is set to `$true, but -BuildUSBDrive is not set to `$true. Please set -BuildUSBDrive to `$true and try again."
}
```

**Why END block (not BEGIN):** BEGIN ends at line 694. Config load is at line 775 (inside END). The throw at ~2607 is inside END and sees config-merged values, not raw CLI args.

**Why `-and -not $USBOnlyMode` guard:** Per CONTEXT.md Decision D-03. Although USBOnlyMode returns at ~line 2366 (before 2606), the guard is belt-and-suspenders as mandated.

---

## Shared Patterns

### Custom Write-TestResult Framework
**Source:** `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` and `FFUDevelopment/Tests/Test-DriverValidationMessages.ps1`
**Apply to:** `Test-Phase52DriverGridFixes.ps1` (new test file)

The framework is identical in both analogs:
- Script-scoped counters: `$script:PassCount`, `$script:FailCount`, `$script:TestResults`
- `Write-TestResult` with `[PASS]` Green / `[FAIL]` Red + Yellow message
- `try { Get-Content -Path $x -Raw -ErrorAction Stop; ... } catch { Write-TestResult ... -Passed $false -Message $_.Exception.Message }`
- Section banners: `Write-Host "SECTION TITLE" -ForegroundColor Yellow`
- Dividers: `Write-Host ("=" * 70) -ForegroundColor Cyan`
- Exit: `exit 0` (all pass) / `exit 1` (any fail)

### CollectionView Filter Capture/Reapply Pattern
**Source:** Upstream b4305a1 (verbatim per RESEARCH.md)
**Apply to:** `Invoke-ListViewSort` in `FFUUI.Core.Shared.psm1`

```powershell
$existingCollectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
if ($null -ne $existingCollectionView -and $existingCollectionView.Filter) {
    $existingFilter = $existingCollectionView.Filter
}
# ... sort ...
$listView.ItemsSource = $newSortedList.ToArray()
$newView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
if ($null -ne $newView) { $newView.Filter = $existingFilter }
```

### Visible-Items-Only Enumeration Pattern
**Source:** Upstream f09c989 (verbatim per RESEARCH.md)
**Apply to:** `Add-SelectableGridViewColumn` (Checked/Unchecked handlers) and `Update-SelectAllHeaderCheckBoxState` in `FFUUI.Core.Shared.psm1`

```powershell
$collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($actualListView.ItemsSource)
if ($null -ne $collectionView) {
    foreach ($visibleItem in $collectionView) {
        $collectionToUpdate += $visibleItem
    }
}
```

Iterating the CollectionView directly (not `@($listView.ItemsSource)`) is the critical distinction — CollectionView enumerator skips filtered-out items.

### WriteLog + throw Error Pattern
**Source:** `FFUDevelopment/BuildFFUVM.ps1` lines 2611-2613 (existing driver validation)
**Apply to:** DGRID-03 throw

```powershell
WriteLog "error message here"
throw "error message here. Please <action> and try again."
```

---

## No Analog Found

None — all files have exact or self-edit analogs.

---

## Metadata

**Analog search scope:** `FFUDevelopment/Tests/`, `FFUDevelopment/FFUUI.Core/`, `FFUDevelopment/BuildFFUVM.ps1`
**Files scanned:** 13 test files (Glob confirmed all use custom framework, zero Pester `.Tests.ps1` files); 4 source files (Read confirmed pre-fix state at all documented line numbers)
**Pattern extraction date:** 2026-06-28

**Line number confidence (HIGH — verified by Read):**
- `Add-SelectableGridViewColumn`: 295 (function), 306 (last param), 321-324 (`$headerTagObject`), 333-337 (Checked handler body), 347-352 (Unchecked handler body), 355 (`$State.Controls[...]`), 359 (`$selectableColumn.Header`)
- `Update-SelectAllHeaderCheckBoxState`: 415 (function), 423-436 (`$collectionToInspect` block)
- `Invoke-ListViewSort`: 501 (function), 537-545 (item-collection block), 628-629 (final ItemsSource assignment)
- `Save-DriversJson`: 215 (function), 221 (bug line)
- `Initialize.psm1`: 457 (driver grid call site, confirmed pre-fix text)
- `BuildFFUVM.ps1`: 2606 (`###PARAMETER VALIDATION`), 2608 (`#Validate drivers folder`) — insert between them

## PATTERN MAPPING COMPLETE
