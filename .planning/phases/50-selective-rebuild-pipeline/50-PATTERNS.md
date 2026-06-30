# Phase 50: Selective Rebuild Pipeline - Pattern Map

**Mapped:** 2026-06-22
**Files analyzed:** 7 new/modified files
**Analogs found:** 7 / 7

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `FFUDevelopment/BuildFFUVM.ps1` (USBOnlyMode block + New-DeploymentUSB) | orchestrator | request-response / batch | Self — existing USBOnlyMode block (lines 1727-1924) and skip-flag pattern (lines 2651-2662) | self-extend |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` | UI event handler | event-driven | `$State.Controls.cmbBitsPriority.Add_SelectionChanged` (line 552) + `cmbHypervisorType.Add_SelectionChanged` (line 402) | role-match |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` | config round-trip | CRUD | Self — existing USB artifact `Build-UIConfiguration` block (lines 166-188) and `Update-UIFromConfig` block (lines 639-665) | self-rewrite |
| `FFUDevelopment/BuildFFUVM_UI.xaml` | UI layout | — | Self — existing artifact card XAML (lines 947-997 FFU card; lines 1001-1043 DeployISO card) + VMwareNicType ComboBox in VM tab | self-extend |
| `Tests/Unit/USBOnlyMode.Tests.ps1` | test | — | Self — existing USBOnlyMode.Tests.ps1 (lines 115-163, structural text-search pattern) | self-extend |
| `Tests/Unit/SelectiveRebuild.Tests.ps1` | test (new file) | — | `Tests/Unit/FFU.ArtifactScanner.Tests.ps1` (InModuleScope pattern) + `Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1` (mock State pattern) | role-match |
| `Tests/Unit/FFUUI.Core.Handlers.Tests.ps1` | test | — | Self — existing FFUUI.Core.Handlers.Tests.ps1 mock-State pattern (lines 28-63) | self-extend |

---

## Pattern Assignments

---

### `FFUDevelopment/BuildFFUVM.ps1` — F1: AppsISO copy path in New-DeploymentUSB

**Analog:** Self — `New-DeploymentUSB` parallel block, the `$using:CopyAutopilot` block (lines 1542-1547).

**Closest existing copy-gate pattern** (lines 1497-1502 — Drivers copy; lines 1542-1547 — Autopilot copy):
```powershell
if ($using:CopyDrivers) {
    $DriversPathOnUSB = Join-Path $DeployPartitionDriveLetter "Drivers"
    WriteLog "Copying drivers to $DriversPathOnUSB"
    robocopy $using:DriversFolder $DriversPathOnUSB /E /COPYALL /R:5 /W:5 /J /XF .gitkeep /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Test-RobocopySuccess -Operation "Drivers to USB"
}

if ($using:CopyAutopilot) {
    $AutopilotPathOnUSB = Join-Path $DeployPartitionDriveLetter "Autopilot"
    WriteLog "Copying Autopilot files to $AutopilotPathOnUSB"
    robocopy $using:AutopilotFolder $AutopilotPathOnUSB /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Test-RobocopySuccess -Operation "Autopilot files to USB"
}
```

**Copy-gate variable initialization pattern** (lines 1829-1845 — how $CopyDrivers etc. are set before the parallel block):
```powershell
# Copy gates (per D-05): Found -> $true, Missing -> $false
$CopyDrivers = ($manifest.Drivers.Status.ToString() -eq 'Found')
$CopyPPKG = (@($manifest.PPKGFiles | Where-Object { $_.Status.ToString() -eq 'Found' }).Count -gt 0)
# ...
# Folder paths — MUST be set even when copy gates are $false
if (-not $DriversFolder) { $DriversFolder = "$FFUDevelopmentPath\Drivers" }
if (-not $PPKGFolder)    { $PPKGFolder    = "$FFUDevelopmentPath\PPKG" }
```

**Config path override pattern** (lines 1869-1891 — how config overrides scan results):
```powershell
# Drivers path override
if ($null -ne $cfgArt.Drivers -and
    -not [string]::IsNullOrWhiteSpace($cfgArt.Drivers.Path) -and
    (Test-Path -LiteralPath $cfgArt.Drivers.Path)) {
    $DriversFolder = $cfgArt.Drivers.Path
    $CopyDrivers = $true
    WriteLog "USBOnlyMode: Overrode Drivers path from config: $($cfgArt.Drivers.Path)"
}
```

**Mirror for AppsISO (F1 — new code following same pattern):**
- Add `$CopyAppsISO = $false` and `$AppsISOPath = "$FFUDevelopmentPath\Apps\Apps.iso"` alongside existing variable initializations (after line 1845).
- Add config override block parallel to Drivers override (inside the `if ($null -ne $configData ...)` block after line 1853).
- Add AppsISO copy block inside `New-DeploymentUSB`'s `ForEach-Object -Parallel` (after line 1547), using `$using:CopyAppsISO` and `$using:AppsISOPath` — same `$using:` capture pattern as all other copy blocks. Use `New-Item -ItemType Directory` + `robocopy` (single-file source, so `Split-Path … -Parent` / `Split-Path … -Leaf` like the Unattend file copy at lines 1521-1526, not the folder robocopy style).

---

### `FFUDevelopment/BuildFFUVM.ps1` — F2: Disposition gate rewrite (replaces Include gate at lines 1893-1911)

**Analog:** Self — the Include-flag gate at lines 1893-1911 (code to DELETE) and the `$cfgArt.Drivers.PSObject.Properties.Match('Include')` property-existence check pattern used throughout.

**Existing Include gate to replace** (lines 1893-1911):
```powershell
# Include flag overrides (D-29) -- user unchecked = don't copy even if Found
# NOTE: No $CopyAppsISO flag exists in this block (Issue #10) -- AppsISO is handled via path only
if ($null -ne $cfgArt.Drivers -and
    $cfgArt.Drivers.PSObject.Properties.Match('Include').Count -gt 0 -and
    -not [bool]$cfgArt.Drivers.Include) {
    $CopyDrivers = $false
    WriteLog "USBOnlyMode: Drivers unchecked by user -- skipping."
}
if ($null -ne $cfgArt.PPKG -and
    $cfgArt.PPKG.PSObject.Properties.Match('Include').Count -gt 0 -and
    -not [bool]$cfgArt.PPKG.Include) {
    $CopyPPKG = $false
    WriteLog "USBOnlyMode: PPKG unchecked by user -- skipping."
}
if ($null -ne $cfgArt.Unattend -and
    $cfgArt.Unattend.PSObject.Properties.Match('Include').Count -gt 0 -and
    -not [bool]$cfgArt.Unattend.Include) {
    $CopyUnattend = $false
    WriteLog "USBOnlyMode: Unattend unchecked by user -- skipping."
}
if ($null -ne $cfgArt.Autopilot -and
    $cfgArt.Autopilot.PSObject.Properties.Match('Include').Count -gt 0 -and
    -not [bool]$cfgArt.Autopilot.Include) {
    $CopyAutopilot = $false
    WriteLog "USBOnlyMode: Autopilot unchecked by user -- skipping."
}
```

**Property-existence check idiom** (used throughout the USBOnlyMode block, e.g. line 1895):
```powershell
$cfgArt.Drivers.PSObject.Properties.Match('Include').Count -gt 0
```
Mirror this exact idiom for `'Disposition'` property existence checks in the new gate.

**New gate replaces lines 1893-1911 entirely.** The switch structure mirrors the existing `if/elseif/else` style used in the include gate, extended to a `foreach` + `switch`:
```powershell
# Disposition-based copy gate (Phase 50 — replaces Include-flag gate at lines 1893-1911)
$dispositionCheckTypes = @('FFU', 'DeployISO', 'Drivers', 'AppsISO', 'PPKG', 'Unattend', 'Autopilot')
foreach ($dType in $dispositionCheckTypes) {
    $dEntry = $cfgArt.$dType
    if ($null -eq $dEntry) { continue }
    $disp = if ($dEntry.PSObject.Properties.Match('Disposition').Count -gt 0) {
        $dEntry.Disposition
    } else { 'Reuse' }
    # Validate enum value (security: malformed config)
    if ($disp -notin @('Reuse', 'Rebuild', 'Skip')) {
        WriteLog "WARNING: Unknown Disposition '$disp' for $dType -- treating as Reuse."
        $disp = 'Reuse'
    }
    switch ($disp) {
        'Skip' {
            switch ($dType) {
                'Drivers'   { $CopyDrivers   = $false; WriteLog "USBOnlyMode: Drivers disposition=Skip -- excluding." }
                'AppsISO'   { $CopyAppsISO   = $false; WriteLog "USBOnlyMode: AppsISO disposition=Skip -- excluding." }
                'PPKG'      { $CopyPPKG      = $false; WriteLog "USBOnlyMode: PPKG disposition=Skip -- excluding." }
                'Unattend'  { $CopyUnattend  = $false; WriteLog "USBOnlyMode: Unattend disposition=Skip -- excluding." }
                'Autopilot' { $CopyAutopilot = $false; WriteLog "USBOnlyMode: Autopilot disposition=Skip -- excluding." }
            }
        }
        'Rebuild' { WriteLog "USBOnlyMode: $dType disposition=Rebuild -- using freshly built artifact." }
        default   { }   # Reuse: no change; copy flags already set from scan/override
    }
}
```

---

### `FFUDevelopment/BuildFFUVM.ps1` — F3: Selective rebuild gate and mini path-init

**Analog:** Self — the skip-flag pattern at lines 2651-2666 (mirrored inversely).

**Skip-flag pattern** (lines 2651-2666 — the resume-forward analog):
```powershell
# === PHASE: Driver Download ===
$skipDriverDownload = $false
if ($script:IsResuming -and (Test-PhaseAlreadyComplete -PhaseName 'DriverDownload' -Checkpoint $script:ResumeCheckpoint)) {
    WriteLog "RESUME: Skipping Driver Download phase - already completed"
    if ($script:ResumedDriversFolder -and (Test-Path $script:ResumedDriversFolder)) {
        $DriversFolder = $script:ResumedDriversFolder
        WriteLog "RESUME: Using drivers folder from checkpoint: $DriversFolder"
    }
    $skipDriverDownload = $true
}

# Gate check later:
if (-not $skipDriverDownload -and $driversJsonPath -and (Test-Path $driversJsonPath) -and ($InstallDrivers -or $CopyDrivers)) {
    WriteLog "Processing drivers from JSON file: $driversJsonPath"
    ...
}
```

**Mini path-init pattern** (lines 1840-1845 — how USBOnlyMode already conditionally sets path variables):
```powershell
# Folder paths — MUST be set even when copy gates are $false
if (-not $DriversFolder)   { $DriversFolder   = "$FFUDevelopmentPath\Drivers" }
if (-not $PPKGFolder)      { $PPKGFolder      = "$FFUDevelopmentPath\PPKG" }
if (-not $UnattendFolder)  { $UnattendFolder  = "$FFUDevelopmentPath\Unattend" }
if (-not $AutopilotFolder) { $AutopilotFolder = "$FFUDevelopmentPath\Autopilot" }
```

**New rebuild flag initialization (mirrors skip-flag pattern, inverted logic — insert after mini path-init):**
```powershell
# === PHASE 50: Selective Rebuild Gate ===
# Parallel to $skip* pattern; active on cold USB-Mode start (NOT tied to $script:IsResuming)
$rebuildDrivers   = $false
$rebuildAppsISO   = $false
$rebuildDeployISO = $false
if ($null -ne $cfgArt) {
    $rebuildDrivers   = ($null -ne $cfgArt.Drivers   -and
        $cfgArt.Drivers.PSObject.Properties.Match('Disposition').Count -gt 0 -and
        $cfgArt.Drivers.Disposition   -eq 'Rebuild')
    $rebuildAppsISO   = ($null -ne $cfgArt.AppsISO   -and
        $cfgArt.AppsISO.PSObject.Properties.Match('Disposition').Count -gt 0 -and
        $cfgArt.AppsISO.Disposition   -eq 'Rebuild')
    $rebuildDeployISO = ($null -ne $cfgArt.DeployISO -and
        $cfgArt.DeployISO.PSObject.Properties.Match('Disposition').Count -gt 0 -and
        $cfgArt.DeployISO.Disposition -eq 'Rebuild')
}
```

**Config read pattern for driversJsonPath (F6 — mirrors how $configData.USBMode.Artifacts is accessed at line 1854):**
```powershell
# F6: Source driversJsonPath from config if not supplied as param
if ([string]::IsNullOrWhiteSpace($driversJsonPath) -and
    $null -ne $configData -and
    $configData.PSObject.Properties.Match('DriversJsonPath').Count -gt 0 -and
    -not [string]::IsNullOrWhiteSpace($configData.DriversJsonPath)) {
    $driversJsonPath = $configData.DriversJsonPath
    WriteLog "USBOnlyMode: Using DriversJsonPath from config: $driversJsonPath"
}
```

**Placement:** Insert the mini path-init extension and rebuild flags AFTER line 1845 (end of folder-path defaults) and BEFORE line 1847 (`$DeployISO = $deployISOPath`). Insert the selective rebuild execution block AFTER line 1911 (end of existing Include gate / new Disposition gate) and BEFORE line 1913 (`# Step 6: Detect USB drives`).

---

### `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` — $artifactMap extension + F7 4-status widening + SelectionChanged handlers

**Analog 1:** Self — existing `$artifactMap` at lines 26-34.

**Existing $artifactMap** (lines 26-34 — to be extended; `includeCtrl` key renamed to `dispCtrl`, `tier` and `warnCtrl` keys added):
```powershell
$artifactMap = @{
    FFU       = @{ statusCtrl = 'usbFFUStatus'; pathCtrl = 'usbFFUPath'; sizeCtrl = 'usbFFUSize'; ageCtrl = 'usbFFUAge'; browseCtrl = 'usbFFUBrowse'; includeCtrl = 'usbFFUInclude'; hasMetadata = $true }
    DeployISO = @{ statusCtrl = 'usbDeployISOStatus'; pathCtrl = 'usbDeployISOPath'; sizeCtrl = 'usbDeployISOSize'; ageCtrl = 'usbDeployISOAge'; browseCtrl = 'usbDeployISOBrowse'; includeCtrl = 'usbDeployISOInclude'; hasMetadata = $false }
    Drivers   = @{ statusCtrl = 'usbDriversStatus'; pathCtrl = 'usbDriversPath'; sizeCtrl = 'usbDriversSize'; ageCtrl = 'usbDriversAge'; browseCtrl = 'usbDriversBrowse'; includeCtrl = 'usbDriversInclude'; hasMetadata = $false }
    PPKG      = @{ statusCtrl = 'usbPPKGStatus'; pathCtrl = 'usbPPKGPath'; sizeCtrl = 'usbPPKGSize'; ageCtrl = 'usbPPKGAge'; browseCtrl = 'usbPPKGBrowse'; includeCtrl = 'usbPPKGInclude'; hasMetadata = $false }
    Unattend  = @{ statusCtrl = 'usbUnattendStatus'; pathCtrl = 'usbUnattendPath'; sizeCtrl = 'usbUnattendSize'; ageCtrl = 'usbUnattendAge'; browseCtrl = 'usbUnattendBrowse'; includeCtrl = 'usbUnattendInclude'; hasMetadata = $false }
    Autopilot = @{ statusCtrl = 'usbAutopilotStatus'; pathCtrl = 'usbAutopilotPath'; sizeCtrl = 'usbAutopilotSize'; ageCtrl = 'usbAutopilotAge'; browseCtrl = 'usbAutopilotBrowse'; includeCtrl = 'usbAutopilotInclude'; hasMetadata = $false }
    AppsISO   = @{ statusCtrl = 'usbAppsISOStatus'; pathCtrl = 'usbAppsISOPath'; sizeCtrl = 'usbAppsISOSize'; ageCtrl = 'usbAppsISOAge'; browseCtrl = 'usbAppsISOBrowse'; includeCtrl = 'usbAppsISOInclude'; hasMetadata = $false }
}
```

**Replacement: rename `includeCtrl` to `dispCtrl`; add `tier` and `warnCtrl`** (each entry gets `dispCtrl = 'usb{Type}Disposition'`, `tier = 'required'|'buildable'|'user-authored'`, `warnCtrl = 'usb{Type}Warning'`).

**Analog 2 (binary Found/else to replace):** Self — lines 113-157 (the `if ($null -ne $result -and $result.Status.ToString() -eq 'Found') { ... } else { ... }` block).

**Existing binary branch** (lines 113-157):
```powershell
if ($null -ne $result -and $result.Status.ToString() -eq 'Found') {
    $artState.path = $result.FilePath
    if ($null -ne $statusCtrl) {
        $statusCtrl.Text = 'Found'
        $statusCtrl.Foreground = [System.Windows.Media.Brushes]::Green
        $statusCtrl.FontStyle = [System.Windows.FontStyles]::Normal
    }
    ...
    if ($null -ne $State.Controls[$map.includeCtrl]) { $State.Controls[$map.includeCtrl].IsEnabled = $true }
} else {
    $artState.path = $null
    if ($null -ne $statusCtrl) {
        $statusCtrl.Text = 'Missing'
        $statusCtrl.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        $statusCtrl.FontStyle = [System.Windows.FontStyles]::Normal
    }
    ...
    if ($null -ne $State.Controls[$map.includeCtrl]) { $State.Controls[$map.includeCtrl].IsEnabled = $false }
}
```
Replace with a `switch` on `$result.Status.ToString()` adding `'Degraded'` (DarkOrange, enable dispCtrl, show warnCtrl) and `'Error'` (OrangeRed, disable dispCtrl) cases. Change all `$map.includeCtrl` references to `$map.dispCtrl`.

**Analog 3 (SelectionChanged idiom):** `$State.Controls.cmbBitsPriority.Add_SelectionChanged` (lines 552-565) and `$State.Controls.cmbVMSwitchName.Add_SelectionChanged` (lines 414-430) — both show the established three-line idiom:
```powershell
$State.Controls.cmbBitsPriority.Add_SelectionChanged({
    param($eventSource, $selectionChangedEventArgs)
    $window = [System.Windows.Window]::GetWindow($eventSource)
    $localState = $window.Tag
    $selectedPriority = $localState.Controls.cmbBitsPriority.SelectedItem
    ...
})
```

**New SelectionChanged handler (per-artifact, mirrors above idiom):**
```powershell
$State.Controls.usbDriversDisposition.Add_SelectionChanged({
    param($eventSource, $selectionChangedEventArgs)
    $window = [System.Windows.Window]::GetWindow($eventSource)
    $localState = $window.Tag
    # Guard: isLoadingConfig flag (established pattern — Handlers.psm1 line 20)
    if ($localState.Flags.isLoadingConfig) { return }
    if ($selectionChangedEventArgs.AddedItems.Count -eq 0) { return }
    $selectedTag = $eventSource.SelectedItem.Tag
    $localState.Data.usbArtifactState['Drivers'].disposition = $selectedTag
})
```
Repeat for each artifact type (FFU, DeployISO, AppsISO, PPKG, Unattend, Autopilot). Required artifacts (FFU, DeployISO) have `IsEnabled=False` ComboBoxes so their handlers fire only on programmatic selection during config load (the `isLoadingConfig` guard suppresses that).

**isLoadingConfig guard pattern** (line 20 — already established):
```powershell
if ($State.Flags.isLoadingConfig) {
    if ($function:WriteLog) { WriteLog 'USBArtifactScan: Config loading in progress. Deferring scan.' }
    return
}
```

**User-path re-verify pattern for dispCtrl** (lines 94-99 — existing path that also touches `includeCtrl`, now `dispCtrl`):
```powershell
if ($null -ne $State.Controls[$map.includeCtrl]) { $State.Controls[$map.includeCtrl].IsEnabled = $true }
// and
if ($null -ne $State.Controls[$map.includeCtrl]) { $State.Controls[$map.includeCtrl].IsEnabled = $false }
```
Change `$map.includeCtrl` to `$map.dispCtrl` at all occurrences (lines 94, 99, 125, 150).

---

### `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` — Build-UIConfiguration + Update-UIFromConfig rewrite

**Analog:** Self — existing USB artifact save block (lines 166-188) and restore block (lines 639-665).

**Existing save block** (lines 166-188 — to replace `Include` write with `Disposition` read):
```powershell
# USB Mode fields (D-22, D-29) -- write ActiveMode, user-browsed artifact paths, and include flags
$config.ActiveMode = if ($null -ne $State.Controls.rbUSBMode -and $State.Controls.rbUSBMode.IsChecked) { 'USBMode' } else { 'FullBuild' }
$config.USBMode = @{ Artifacts = @{} }
foreach ($artifactType in @('FFU', 'DeployISO', 'Drivers', 'PPKG', 'Unattend', 'Autopilot', 'AppsISO')) {
    $artState = $State.Data.usbArtifactState[$artifactType]
    $pathToSave = $null
    if ($null -ne $artState -and $artState.source -eq 'user' -and -not [string]::IsNullOrWhiteSpace($artState.path)) {
        $pathToSave = $artState.path
    }
    # Read include checkbox state (D-29) -- Plan 04 reads these at ThreadJob launch
    $includeCtrlName = "usb${artifactType}Include"
    $includeChecked = $true  # default to included
    if ($null -ne $State.Controls[$includeCtrlName]) {
        $includeChecked = [bool]$State.Controls[$includeCtrlName].IsChecked
    }
    $config.USBMode.Artifacts[$artifactType] = @{
        Path        = $pathToSave
        Disposition = 'Reuse'     # <-- currently hardcoded! Phase 50 reads from ComboBox
        Include     = $includeChecked
    }
}
```

**Replacement pattern for lines 177-188** (read from ComboBox Tag instead of checkbox IsChecked):
```powershell
    $dispCtrlName = "usb${artifactType}Disposition"
    $disposition  = 'Reuse'  # default
    if ($null -ne $State.Controls[$dispCtrlName] -and
        $null -ne $State.Controls[$dispCtrlName].SelectedItem) {
        $disposition = $State.Controls[$dispCtrlName].SelectedItem.Tag
    }
    $config.USBMode.Artifacts[$artifactType] = @{
        Path        = $pathToSave
        Disposition = $disposition
        # Include field removed — Disposition is the canonical field
    }
```

**Existing restore block** (lines 639-665 — to replace `Include` restore with `Disposition` ComboBox selection):
```powershell
# Restore include checkbox state (D-29)
if ($null -ne $entry -and $entry.PSObject.Properties.Match('Include').Count -gt 0) {
    $includeCtrlName = "usb${key}Include"
    if ($null -ne $State.Controls[$includeCtrlName]) {
        $State.Controls[$includeCtrlName].IsChecked = [bool]$entry.Include
    }
}
```

**ComboBox restore analog** (lines 621-636 — `cmbVMwareNicType` restore is the exact same pattern needed for disposition ComboBoxes):
```powershell
# Load VMware NIC Type selection (e1000e/vmxnet3/e1000)
if ($ConfigContent.PSObject.Properties.Match('VMwareNicType').Count -gt 0) {
    $vmwareNicType = $ConfigContent.VMwareNicType
    if ($null -ne $State.Controls.cmbVMwareNicType -and -not [string]::IsNullOrWhiteSpace($vmwareNicType)) {
        # Find the ComboBoxItem with matching Tag value
        $itemToSelect = $null
        foreach ($item in $State.Controls.cmbVMwareNicType.Items) {
            if ($item -is [System.Windows.Controls.ComboBoxItem] -and $item.Tag -eq $vmwareNicType) {
                $itemToSelect = $item
                break
            }
        }
        if ($null -ne $itemToSelect) {
            $State.Controls.cmbVMwareNicType.SelectedItem = $itemToSelect
            WriteLog "LoadConfig: Set VMwareNicType to '$vmwareNicType'."
        }
    }
}
```

**Replacement pattern for lines 657-663** (mirror cmbVMwareNicType Tag-based restore exactly):
```powershell
    # Restore disposition ComboBox state (Phase 50 — replaces Include checkbox restore)
    if ($null -ne $entry -and $entry.PSObject.Properties.Match('Disposition').Count -gt 0) {
        $dispCtrlName = "usb${key}Disposition"
        if ($null -ne $State.Controls[$dispCtrlName]) {
            $targetDisp = $entry.Disposition
            foreach ($item in $State.Controls[$dispCtrlName].Items) {
                if ($item -is [System.Windows.Controls.ComboBoxItem] -and $item.Tag -eq $targetDisp) {
                    $State.Controls[$dispCtrlName].SelectedItem = $item
                    break
                }
            }
        }
    }
```

**Ordering note:** The `isLoadingConfig` guard must be `$true` during `Update-UIFromConfig`. The guard is already set at the top of `Update-UIFromConfig` (per established Phase 49 pattern). The ComboBox restore fires `SelectionChanged` during restore; the handler's `if ($localState.Flags.isLoadingConfig) { return }` (line 20 analog in Handlers.psm1) suppresses state writes during load.

---

### `FFUDevelopment/BuildFFUVM_UI.xaml` — CheckBox-to-ComboBox swap on 7 artifact cards

**Analog 1 (XAML Card layout):** Self — FFU card (lines 947-997), DeployISO card (lines 1001-1043). Both show the full card row structure: RowDefinitions, Row 0 CheckBox StackPanel, Row 1 Status, Row 2 Path+Browse, Row 3 Size+Age, Row 4 metadata (FFU only).

**Existing Row 0 CheckBox pattern** (line 958-960):
```xml
<!-- Row 0: Label + Include checkbox -->
<StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,5">
    <CheckBox x:Name="usbFFUInclude" Content="FFU Image" FontWeight="Bold" FontSize="13" IsEnabled="False" IsChecked="True" VerticalAlignment="Center"/>
</StackPanel>
```

**Analog 2 (ComboBox with Tag items):** VMware NIC Type ComboBox elsewhere in the XAML (pattern used by `cmbVMwareNicType` in VM Settings tab — `ComboBoxItem Tag=` pattern is established). The disposition ComboBox follows the same `Tag=` idiom.

**Replacement Row 0 structure (all non-FFU cards):**
```xml
<StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,5">
    <TextBlock Text="{artifact label}" FontWeight="Bold" FontSize="13"
               VerticalAlignment="Center" Margin="0,0,8,0"/>
    <ComboBox x:Name="usb{Type}Disposition" Width="120" FontSize="11"
              SelectedIndex="0" IsEnabled="False" VerticalAlignment="Center">
        <!-- Items per tier (see CONTEXT D-02 / UI-SPEC Copywriting Contract) -->
    </ComboBox>
</StackPanel>
```

**FFU card Row 0 (adds helper text — D-09):**
```xml
<StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,3">
    <TextBlock Text="FFU Image" FontWeight="Bold" FontSize="13"
               VerticalAlignment="Center" Margin="0,0,8,0"/>
    <ComboBox x:Name="usbFFUDisposition" Width="120" FontSize="11"
              SelectedIndex="0" IsEnabled="False" VerticalAlignment="Center">
        <ComboBoxItem Content="Reuse" Tag="Reuse"/>
    </ComboBox>
</StackPanel>
<!-- FFU helper text (D-09) — always visible -->
<TextBlock Text="To rebuild the OS image, switch to Full Build"
           FontSize="11" Foreground="#888888" FontStyle="Italic"
           Margin="0,0,0,5"/>
```

**Warning TextBlock row (D-11 — add to EVERY card as the new last row):**
```xml
<TextBlock x:Name="usb{Type}Warning" Grid.Row="{last+1}"
           Text="" FontSize="11" Foreground="DarkOrange"
           Visibility="Collapsed" TextWrapping="Wrap"
           Margin="20,0,0,3"/>
```
Add matching `<RowDefinition Height="Auto"/>` to `<Grid.RowDefinitions>`. For FFU card (gets both helper text row AND warning row), add two new RowDefinitions.

**Spacing reference from existing cards** (lines 980-986 — metadata row margins):
```xml
Margin="20,0,0,3"   <!-- card internal indent for all metadata rows -->
Margin="0,10"       <!-- Separator between cards -->
Margin="5"          <!-- Card Grid outer margin -->
```

---

### `Tests/Unit/USBOnlyMode.Tests.ps1` — Extend with structural tests for F1/F2/F3

**Analog:** Self — existing structural text-search pattern at lines 115-163.

**Established test idiom** (lines 116-117 — check a variable is set from manifest):
```powershell
It 'Sets $CopyDrivers from manifest Drivers status' {
    $scriptContent | Should -Match '\$CopyDrivers\s*=.*manifest\.Drivers\.Status'
}
```

**New tests to add** (mirror this exact `Should -Match` pattern):
```powershell
Context 'F1 — AppsISO Copy Path' {
    It 'Declares $CopyAppsISO variable in USBOnlyMode block' {
        $scriptContent | Should -Match '\$CopyAppsISO\s*='
    }
    It 'Declares $AppsISOPath variable in USBOnlyMode block' {
        $scriptContent | Should -Match '\$AppsISOPath\s*='
    }
    It 'New-DeploymentUSB parallel block contains $using:CopyAppsISO guard' {
        $scriptContent | Should -Match '\$using:CopyAppsISO'
    }
    It 'New-DeploymentUSB parallel block contains $using:AppsISOPath' {
        $scriptContent | Should -Match '\$using:AppsISOPath'
    }
}

Context 'F2 — Disposition Gate' {
    It 'Does not contain Include-flag gate (replaced by Disposition gate)' {
        $scriptContent | Should -Not -Match 'PSObject\.Properties\.Match\(.Include.\)'
    }
    It 'Contains Disposition-based gate foreach loop' {
        $scriptContent | Should -Match 'dispositionCheckTypes'
    }
    It 'Contains Disposition property existence check' {
        $scriptContent | Should -Match "PSObject\.Properties\.Match\('Disposition'\)"
    }
}

Context 'F3 — Selective Rebuild Flags' {
    It 'Declares $rebuildDrivers flag' {
        $scriptContent | Should -Match '\$rebuildDrivers\s*='
    }
    It 'Declares $rebuildAppsISO flag' {
        $scriptContent | Should -Match '\$rebuildAppsISO\s*='
    }
    It 'Declares $rebuildDeployISO flag' {
        $scriptContent | Should -Match '\$rebuildDeployISO\s*='
    }
    It 'Contains if ($rebuildDrivers) selective rebuild block' {
        $scriptContent | Should -Match 'if\s*\(\$rebuildDrivers\)'
    }
    It 'Calls New-AppsISO inside $rebuildAppsISO block' {
        $scriptContent | Should -Match 'New-AppsISO'
    }
    It 'Calls New-PEMedia inside $rebuildDeployISO block' {
        $scriptContent | Should -Match 'New-PEMedia'
    }
}
```

---

### `Tests/Unit/SelectiveRebuild.Tests.ps1` — New file covering REBUILD-01 and D-10/D-11

**Analog 1:** `Tests/Unit/FFU.ArtifactScanner.Tests.ps1` (lines 1-48) — for module import pattern and `InModuleScope` usage (needed for `ArtifactStatus` enum assertions).

**Module import pattern** (ArtifactScanner.Tests.ps1 lines 27-44):
```powershell
BeforeAll {
    $testDir  = Split-Path $PSCommandPath -Parent
    $testsDir = Split-Path $testDir -Parent
    $repoRoot = Split-Path $testsDir -Parent
    $modulePath = Join-Path $repoRoot 'FFUDevelopment\Modules\FFU.ArtifactScanner\FFU.ArtifactScanner.psd1'

    $modulesDir = Join-Path $repoRoot 'FFUDevelopment' | Join-Path -ChildPath 'Modules'
    if ($env:PSModulePath -notlike "*$modulesDir*") {
        $env:PSModulePath = "$modulesDir;$env:PSModulePath"
    }
    Import-Module $modulePath -Force -ErrorAction Stop
}
```

**Analog 2:** `Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1` (lines 40-55) — for mock State object pattern, especially `New-MockState` helper:
```powershell
function New-MockState {
    [PSCustomObject]@{
        FFUDevelopmentPath = 'C:\FFUDevelopment'
        Controls           = @{
            txtFFUDevPath = [PSCustomObject]@{ Text = 'C:\FFUDevelopment' }
        }
        Data               = @{
            configValidationResult = $null
            hasValidationErrors    = $false
            lastConfigFilePath     = $null
        }
    }
}
```

**InModuleScope pattern** (from `FFU.ArtifactScanner.Tests.ps1` — required for enum value assertions):
```powershell
InModuleScope 'FFU.ArtifactScanner' {
    It 'ArtifactStatus has Degraded value' {
        [ArtifactStatus]::Degraded | Should -Be 'Degraded'
    }
}
```

**Config round-trip test structure** (new — mirrors ConfigValidation Tests pattern of mocking controls and asserting on hashtable output):
```powershell
Describe 'Disposition Config Round-Trip' -Tag 'Unit', 'SelectiveRebuild' {
    BeforeAll {
        # Import Config module (no WPF runtime required for unit tests on hashtable logic)
        $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        Import-Module (Join-Path $projectRoot 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1') -Force
        function global:WriteLog { param([string]$Message) }
    }

    Context 'Build-UIConfiguration writes Disposition from ComboBox Tag' {
        It 'Writes Rebuild disposition when ComboBox SelectedItem.Tag is Rebuild' {
            $state = [PSCustomObject]@{
                Controls = @{
                    rbUSBMode = [PSCustomObject]@{ IsChecked = $true }
                    usbDriversDisposition = [PSCustomObject]@{
                        SelectedItem = [PSCustomObject]@{ Tag = 'Rebuild' }
                    }
                    # ... other required controls
                }
                Data = @{
                    usbArtifactState = @{
                        Drivers = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Rebuild' }
                        # ... other types
                    }
                }
            }
            $config = Build-UIConfiguration -State $state
            $config.USBMode.Artifacts['Drivers'].Disposition | Should -Be 'Rebuild'
        }
    }
}
```

**File header pattern** (mirrors `_Template.Tests.ps1` lines 1-22):
```powershell
#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Pester 5.x tests for Phase 50 Selective Rebuild Pipeline

.DESCRIPTION
    Tests covering:
    - REBUILD-01: ComboBox Disposition config round-trip (save + restore)
    - D-10/D-11: 4-status scanner UI rendering (Found/Degraded/Error/Missing)
    - ArtifactStatus enum coverage for new Degraded and Error values
#>
```

---

## Shared Patterns

### PSObject.Properties.Match existence check
**Source:** `BuildFFUVM.ps1` USBOnlyMode block lines 1895, 1899, 1903, 1907
**Apply to:** All new Disposition-reading code in BuildFFUVM.ps1 and Config.psm1
```powershell
$obj.PSObject.Properties.Match('Disposition').Count -gt 0
```
Use this instead of direct property access whenever reading config properties that might not exist (e.g., old configs without `Disposition`).

### isLoadingConfig guard
**Source:** `FFUUI.Core.Handlers.psm1` line 20-22 (Invoke-USBArtifactScan) + per-handler guard
**Apply to:** Every new `Add_SelectionChanged` handler for disposition ComboBoxes
```powershell
if ($localState.Flags.isLoadingConfig) { return }
```
This prevents disposition state corruption when `Update-UIFromConfig` programmatically sets `SelectedItem`.

### $using: scope for parallel block variables
**Source:** `BuildFFUVM.ps1` lines 1477-1546 (ForEach-Object -Parallel block)
**Apply to:** `$CopyAppsISO` and `$AppsISOPath` variables for the F1 AppsISO copy
All variables accessed inside `ForEach-Object -Parallel` must be set as script-scope variables BEFORE the function call, captured via `$using:VariableName` inside the parallel block.

### Window.Tag state retrieval in SelectionChanged handlers
**Source:** `FFUUI.Core.Handlers.psm1` lines 402-410, 414-430, 433-453 (cmbHypervisorType, cmbVMSwitchName, cmbVMHostIPAddress handlers)
**Apply to:** All new disposition ComboBox SelectionChanged handlers
```powershell
$window = [System.Windows.Window]::GetWindow($eventSource)
$localState = $window.Tag
```
This is the established pattern to retrieve `$State` inside WPF event handlers. Never capture `$State` via closure — closures in PS5.1 don't capture outer scope reliably in WPF event context.

### WriteLog conditional call in non-exported context
**Source:** `FFUUI.Core.Handlers.psm1` line 15
**Apply to:** Any new helper functions added to Handlers.psm1 (e.g., `Set-ComboBoxDisposition`)
```powershell
if ($function:WriteLog) { WriteLog "message" }
```

### Config array iteration
**Source:** `FFUUI.Core.Config.psm1` lines 171-188 (Build-UIConfiguration) and lines 645-664 (Update-UIFromConfig)
**Apply to:** Disposition save and restore loops — both already iterate `@('FFU', 'DeployISO', 'Drivers', 'PPKG', 'Unattend', 'Autopilot', 'AppsISO')` and use `$artifactType` / `$key` respectively. Phase 50 changes only the inner body of each loop.

### Text-search structural test idiom
**Source:** `Tests/Unit/USBOnlyMode.Tests.ps1` lines 115-163
**Apply to:** All new structural tests in USBOnlyMode.Tests.ps1
```powershell
$scriptContent = Get-Content -Path $scriptPath -Raw   # in BeforeAll
It 'test name' {
    $scriptContent | Should -Match '\$VariableName\s*='
}
```

---

## No Analog Found

No files in Phase 50 are without a codebase analog. Every new pattern mirrors an existing one:

| File | Pattern | Analog Location |
|------|---------|----------------|
| Selective rebuild flags ($rebuildDrivers etc.) | Inverted skip-flag | BuildFFUVM.ps1 lines 2651-2661 |
| ComboBox disposition handlers | SelectionChanged wiring | Handlers.psm1 lines 402-565 |
| ComboBox Tag-based restore | Item.Tag restore | Config.psm1 lines 621-636 (cmbVMwareNicType) |
| 4-status switch rendering | Widened from binary if/else | Handlers.psm1 lines 113-157 |

---

## Metadata

**Analog search scope:** `FFUDevelopment/BuildFFUVM.ps1`, `FFUDevelopment/FFUUI.Core/`, `FFUDevelopment/BuildFFUVM_UI.xaml`, `Tests/Unit/`, `FFUDevelopment/Modules/FFU.ArtifactScanner/`
**Files scanned:** 12 source files read directly
**Pattern extraction date:** 2026-06-22

### Key line reference index

| File | Lines | Content |
|------|-------|---------|
| BuildFFUVM.ps1 | 1727-1924 | Full USBOnlyMode block |
| BuildFFUVM.ps1 | 1328-1562 | New-DeploymentUSB function |
| BuildFFUVM.ps1 | 1828-1845 | Copy-gate variable init (Step 5) |
| BuildFFUVM.ps1 | 1851-1911 | Config override + Include gate (Step 5b) — F2 DELETE target |
| BuildFFUVM.ps1 | 1893-1911 | Include-flag block to replace with Disposition gate |
| BuildFFUVM.ps1 | 1497-1547 | Existing artifact copy blocks (robocopy pattern) |
| BuildFFUVM.ps1 | 2651-2666 | skip-flag + driver gate pattern (F3 analog) |
| FFUUI.Core.Handlers.psm1 | 26-34 | $artifactMap (extend: includeCtrl→dispCtrl + tier + warnCtrl) |
| FFUUI.Core.Handlers.psm1 | 107-161 | Binary Found/else scan result branch (F7 widen to switch) |
| FFUUI.Core.Handlers.psm1 | 402-430 | cmbHypervisorType + cmbVMSwitchName SelectionChanged (handler idiom) |
| FFUUI.Core.Handlers.psm1 | 552-565 | cmbBitsPriority SelectionChanged (simpler handler, closest analog) |
| FFUUI.Core.Config.psm1 | 166-188 | Build-UIConfiguration USB artifact save (replace Include→Disposition) |
| FFUUI.Core.Config.psm1 | 621-636 | cmbVMwareNicType Tag-based restore (exact analog for disposition restore) |
| FFUUI.Core.Config.psm1 | 639-665 | Update-UIFromConfig USB artifact restore (replace Include checkbox) |
| BuildFFUVM_UI.xaml | 947-997 | FFU card XAML (Row 0 CheckBox to replace) |
| BuildFFUVM_UI.xaml | 1001-1043 | DeployISO card XAML (Row 0 CheckBox to replace) |
| ArtifactScanner.Classes.ps1 | 22-27 | ArtifactStatus enum (Found/Missing/Error/Degraded) |
| ArtifactScanner.Classes.ps1 | 59-83 | ArtifactResult class (ErrorMessage field for Degraded warning) |
| Tests/Unit/USBOnlyMode.Tests.ps1 | 115-163 | Structural text-search test pattern |
| Tests/Unit/FFU.ArtifactScanner.Tests.ps1 | 27-48 | Module import + InModuleScope enum test pattern |
| Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1 | 40-55 | Mock State object pattern |
