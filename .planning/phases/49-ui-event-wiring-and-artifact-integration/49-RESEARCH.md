# Phase 49: UI Event Wiring and Artifact Integration - Research

**Researched:** 2026-03-24
**Domain:** WPF PowerShell UI event wiring, artifact state management, config persistence
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Area A — Artifact Scanning Trigger & UX**
- D-01: Scan triggers on mode switch — `rbUSBMode.Checked` fires scan immediately after tab visibility swap
- D-02: Scanning runs synchronous on UI thread — `Find-FFUArtifacts` does filesystem-only operations (<2s), no ThreadJob/DispatcherTimer needed
- D-03: Per-card status updates — each artifact card's status TextBlock updates individually as results populate: `(scanning...)` → `Found` or `Missing`
- D-04: Rescan button — add `usbRescanArtifacts` Button at top of USB Mode tab for manual re-scan (requires small XAML addition)
- D-05: After scan completes, Browse buttons (`IsEnabled=$true`) and CheckBoxes (`IsEnabled=$true` for Found artifacts) are enabled

**Area B — Browse Override Behavior**
- D-06: Browse overrides scanner — user-browsed path replaces auto-detected path for that artifact
- D-07: Rescan respects overrides — re-scan only updates artifacts with `source='auto'`, preserves `source='user'` paths
- D-08: Internal state tracking per artifact: `source` ('auto' | 'user') and `path` — no visual distinction in UI between auto vs user paths
- D-09: Per-card reset clears override back to auto-detect

**Area C — USB Drive Reuse Strategy**
- D-10: USB drive detection controls duplicated in USB Mode tab — new GroupBox "Target USB Drive" with `usbCheckUSBDrives`, `usbUSBDriveList`, `usbSelectAllDrives` controls
- D-11: Both Build tab and USB tab call the same `Get-USBDrives` function — no shared state between the two sets of controls
- D-12: USB Mode tab is self-contained — user doesn't need to visit the Build tab for any USB Mode operation
- D-13: Requires a XAML addition (~30 lines) to Phase 48's USB Mode tab

**Area D — Mode-Aware Button & State**
- D-14: `btnRun.Content` updates on mode switch: USB Mode idle = "Create USB", Full Build idle = "Build FFU"
- D-15: During execution, `btnRun.Content = "Cancel"` regardless of mode
- D-16: Cancel triggers existing `FFUCancellation` flag pattern — no new cancel mechanism
- D-17: `Reset-FFUUIToIdle` restores button label based on active mode (`rbUSBMode.IsChecked` → "Create USB", else "Build FFU")
- D-18: Active mode persists across restarts via config — read `config.ActiveMode` on startup, set RadioButton.IsChecked, fire mode switch handler

**Area D cont. — Pre-Launch Validation**
- D-19: UI-side validation before launching ThreadJob: (1) FFU and DeployISO must be Found and checked, (2) at least one USB drive selected
- D-20: Show error dialog if validation fails — "Select an FFU file" / "Deploy ISO is required" / "Select a USB drive"
- D-21: Deeper validation (ISO mount test, architecture warnings) runs inside BuildFFUVM.ps1 -USBOnlyMode

**Config Persistence (DISC-03)**
- D-22: On config save: write `ActiveMode` ('FullBuild' | 'USBMode'), write user-browsed artifact paths to `USBMode.Artifacts.{Type}.Path`
- D-23: On config load: restore `ActiveMode` by setting RadioButton.IsChecked, restore user-overridden artifact paths (mark as `source='user'`), then scan fills remaining auto-detect paths
- D-24: Config save stubs in FFUUI.Core.Config.psm1 (lines 166-180, 622-628) must be replaced with actual control reads/writes

**Mode Switch Handler**
- D-25: `rbUSBMode.Checked` handler sequence: (1) collapse 7 Full Build tabs, (2) show `usbModeTab`, (3) select `usbModeTab`, (4) run artifact scan, (5) update `btnRun.Content` to "Create USB"
- D-26: `rbFullBuild.Checked` handler sequence: (1) show 7 Full Build tabs, (2) collapse `usbModeTab`, (3) select first Full Build tab, (4) update `btnRun.Content` to "Build FFU"
- D-27: Tab names for toggling: `tabVMSettings`, `tabWindowsSettings`, `tabUpdates`, `tabApplications`, `tabM365AppsOffice`, `tabDrivers`, `tabBuild`

**Create USB Action**
- D-28: "Create USB" click passes artifact paths and inclusion flags to `BuildFFUVM.ps1 -USBOnlyMode` via ThreadJob — same `Start-ThreadJob` pattern as Full Build
- D-29: Inclusion checkboxes map to copy gates: `usbFFUInclude.IsChecked` → `$CopyFFU`, `usbDriversInclude.IsChecked` → `$CopyDrivers`, etc.
- D-30: User-browsed paths override scanner defaults — passed as parameters or via config to the build script

### Claude's Discretion
- Per-artifact state tracking implementation (hashtable, PSCustomObject, or class)
- Whether Rescan button also re-validates user-overridden paths (recommend yes — verify they still exist)
- Exact XAML layout for the USB drive section in the USB Mode tab
- Error dialog implementation (MessageBox vs WPF custom dialog)
- How to pass user-overridden paths to BuildFFUVM.ps1 -USBOnlyMode (config vs parameters)

### Deferred Ideas (OUT OF SCOPE)
- Per-artifact disposition controls (Reuse/Rebuild/Skip) — Phase 50: Selective Rebuild Pipeline
- Artifact version history or rollback selection — Future (REBUILD-05)
- Network/cloud artifact sources — Out of scope per REQUIREMENTS.md
- Auto-rebuild stale artifacts — Out of scope per REQUIREMENTS.md
- USB Mode profiles (named configurations) — Future (REBUILD-04)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DISC-02 | User can browse to arbitrary file/folder paths for each artifact type | Invoke-BrowseAction already supports OpenFile/Folder dialogs; 7 Browse buttons exist in XAML (usbFFUBrowse, usbDeployISOBrowse, usbDriversBrowse, usbPPKGBrowse, usbUnattendBrowse, usbAutopilotBrowse, usbAppsISOBrowse); per-artifact `source` state tracks override |
| DISC-03 | User-specified artifact paths persist across sessions via config | Config schema v1.3 already has USBMode.Artifacts.{Type}.Path fields; stubs in Build-UIConfiguration (lines 166-180) and Update-UIFromConfig (lines 622-628) are ready to replace |
| USB-02 | USB Mode reuses existing USB drive detection and selection | Get-USBDrives function in FFUUI.Core.psm1 (line 362) returns the same drive objects; btnCheckUSBDrives handler pattern fully reusable; XAML needs ~30-line USB drive GroupBox added to usbModeTab |
| USB-03 | User can select which artifacts to include on the USB (per-artifact checkboxes) | 7 include CheckBoxes exist in XAML (usbFFUInclude through usbAppsISOInclude); IsChecked state maps to copy gates passed to BuildFFUVM.ps1 -USBOnlyMode |
</phase_requirements>

## Summary

Phase 49 wires all 46 named controls in the USB Mode tab (delivered by Phase 48) to working code-behind logic. The work divides into five delivery areas: (1) mode switch handler that toggles tab visibility and triggers artifact scanning, (2) per-artifact card updates driven by `Find-FFUArtifacts` results, (3) Browse button handlers that override auto-detected paths, (4) USB drive detection duplicated to the USB Mode tab, and (5) config persistence completing the stubs left in Phase 45.

The primary implementation vehicle is `FFUUI.Core.Handlers.psm1` — new handlers for `rbUSBMode`, `rbFullBuild`, 7 Browse buttons, a Rescan button, and the USB drive check button all wire into the existing `Register-EventHandlers` function. The `btnRun` handler in `BuildFFUVM_UI.ps1` gains a USB Mode branch that launches `BuildFFUVM.ps1 -USBOnlyMode` via the same `Start-ThreadJob` pattern already used for Full Build. `Reset-FFUUIToIdle` in `FFUUI.Core.StateRecovery.psm1` needs a one-line mode-aware fix so it restores "Create USB" instead of always "Build FFU". Config stubs in `FFUUI.Core.Config.psm1` lines 166-180 and 622-628 are replaced with real reads and writes.

The XAML requires two additions: (1) a `usbRescanArtifacts` Button at the top of usbModeTab (per D-04), and (2) a "Target USB Drive" GroupBox (~30 lines, per D-10/D-13) replicating the Build tab's USB drive section with `usb`-prefixed control names.

**Primary recommendation:** Implement in four sequential plans — (1) XAML additions + mode switch handler, (2) artifact scan integration + browse handlers, (3) USB drive detection + "Create USB" ThreadJob launch, (4) config persistence.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFUUI.Core.Handlers.psm1 | project | Central event handler registration | All existing handlers live here; Register-EventHandlers is the single wiring entry point |
| FFUUI.Core.Shared.psm1 | project | Invoke-BrowseAction, dialog helpers | Unified browse function — handles Folder/OpenFile/SaveFile; already imported |
| FFUUI.Core.Config.psm1 | project | Build-UIConfiguration / Update-UIFromConfig | Config round-trip; stubs at lines 166-180 and 622-628 await Phase 49 implementation |
| FFUUI.Core.StateRecovery.psm1 | project | Reset-FFUUIToIdle | Centralized idle reset; needs mode-awareness fix at line 143 |
| FFU.ArtifactScanner module | 1.0.0 | Find-FFUArtifacts — filesystem scan returning ArtifactManifest | Already imported in BuildFFUVM_UI.ps1's module chain via FFUUI.Core; returns typed results |
| BuildFFUVM_UI.ps1 | project | btnRun dual-mode handler, ThreadJob launch | USB Mode branch added here alongside Full Build branch |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| FFU.Messaging | project | Request-FFUCancellation, messaging context | Reused unchanged for Cancel path in USB Mode |
| System.Windows.MessageBox | .NET WPF | Error dialogs for pre-launch validation | D-20: simple OK dialogs for missing FFU, missing DeployISO, no USB drive selected |

## Architecture Patterns

### Recommended File Change Map
```
FFUDevelopment/
├── BuildFFUVM_UI.xaml             # +Rescan button + USB drive GroupBox in usbModeTab
├── BuildFFUVM_UI.ps1              # +USB Mode branch in btnRun handler
├── FFUUI.Core/
│   ├── FFUUI.Core.Handlers.psm1  # +rbUSBMode/rbFullBuild + 7 browse + rescan + USB drive handlers
│   ├── FFUUI.Core.Config.psm1    # Replace stubs at lines 166-180 and 622-628
│   └── FFUUI.Core.StateRecovery.psm1  # Mode-aware button label in Reset-FFUUIToIdle
└── Tests/Unit/
    └── Phase49.Tests.ps1          # New Pester tests
```

### Pattern 1: Mode Switch Handler (rbUSBMode.Checked)
**What:** RadioButton Checked event that toggles tab visibility, triggers scan, updates button label
**When to use:** D-25 sequence — must run in this order to avoid brief UI flicker

```powershell
# Source: FFUUI.Core.Handlers.psm1 — Register-EventHandlers
$State.Controls.rbUSBMode.Add_Checked({
    param($eventSource, $routedEventArgs)
    $window = [System.Windows.Window]::GetWindow($eventSource)
    $localState = $window.Tag

    # (1) Collapse Full Build tabs
    $fullBuildTabNames = @('tabVMSettings','tabWindowsSettings','tabUpdates',
                           'tabApplications','tabM365AppsOffice','tabDrivers','tabBuild')
    foreach ($name in $fullBuildTabNames) {
        if ($null -ne $localState.Controls[$name]) {
            $localState.Controls[$name].Visibility = 'Collapsed'
        }
    }

    # (2) Show + (3) select usbModeTab
    $localState.Controls.usbModeTab.Visibility = 'Visible'
    $localState.Controls.MainTabControl.SelectedItem = $localState.Controls.usbModeTab

    # (4) Run artifact scan (synchronous — <2s filesystem scan)
    Invoke-USBArtifactScan -State $localState

    # (5) Update button label
    $localState.Controls.btnRun.Content = 'Create USB'
})
```

### Pattern 2: Artifact Scan Function (Invoke-USBArtifactScan)
**What:** Wrapper around Find-FFUArtifacts that updates per-card TextBlocks and enables controls
**When to use:** Called from mode switch handler and Rescan button; respects `source='user'` overrides per D-07

```powershell
function Invoke-USBArtifactScan {
    param([PSCustomObject]$State)

    # Pre-condition: FFUDevelopmentPath must be set
    $ffuDevPath = $State.Controls.txtFFUDevPath.Text
    if ([string]::IsNullOrWhiteSpace($ffuDevPath) -or -not (Test-Path -LiteralPath $ffuDevPath)) {
        WriteLog 'USBArtifactScan: FFUDevelopmentPath not set or does not exist. Skipping scan.'
        return
    }

    # Show (scanning...) on all cards that are not user-overridden
    # ... set status TextBlocks to '(scanning...)'

    $manifest = Find-FFUArtifacts -FFUDevelopmentPath $ffuDevPath

    # Update each card: status, path, size, age, FFU metadata (if applicable)
    # For artifacts with source='user': skip path update, only update status if file still exists
    Update-USBArtifactCards -State $State -Manifest $manifest
}
```

### Pattern 3: Browse Handler (per artifact)
**What:** 7 handlers wired to usbFFUBrowse...usbAppsISOBrowse; each calls Invoke-BrowseAction with appropriate Type/Filter
**When to use:** D-06 — browse result stored in $State.Data.usbArtifactState[type].path + source='user'

```powershell
# Source: FFUUI.Core.Handlers.psm1 — existing pattern from lines 364-372
$State.Controls.usbFFUBrowse.Add_Click({
    param($eventSource, $routedEventArgs)
    $window = [System.Windows.Window]::GetWindow($eventSource)
    $localState = $window.Tag
    $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title 'Select FFU Image' -Filter 'FFU files (*.ffu)|*.ffu'
    if ($selectedPath) {
        $localState.Data.usbArtifactState.FFU.path   = $selectedPath
        $localState.Data.usbArtifactState.FFU.source = 'user'
        $localState.Controls.usbFFUPath.Text         = $selectedPath
        # Update status, enable include checkbox
    }
})
```

### Pattern 4: Per-Artifact State Hashtable
**What:** `$State.Data.usbArtifactState` — hashtable keyed by artifact type, each entry has `path` and `source`
**When to use:** Initialized when USB Mode first activates; persisted to config on save

```powershell
# Initialized in BuildFFUVM_UI.ps1 alongside $script:uiState initialization
$script:uiState.Data.usbArtifactState = @{
    FFU       = @{ path = $null; source = 'auto' }
    DeployISO = @{ path = $null; source = 'auto' }
    Drivers   = @{ path = $null; source = 'auto' }
    PPKG      = @{ path = $null; source = 'auto' }
    Unattend  = @{ path = $null; source = 'auto' }
    Autopilot = @{ path = $null; source = 'auto' }
    AppsISO   = @{ path = $null; source = 'auto' }
}
```

### Pattern 5: Mode-Aware Reset-FFUUIToIdle
**What:** Replace hardcoded "Build FFU" at line 143 with a mode-aware check
**When to use:** Called from all error/completion paths in BuildFFUVM_UI.ps1

```powershell
# FFUUI.Core.StateRecovery.psm1 line 143 — replace:
#   $State.Controls.btnRun.Content = "Build FFU"
# With:
$isUSBMode = $null -ne $State.Controls.rbUSBMode -and $State.Controls.rbUSBMode.IsChecked
$State.Controls.btnRun.Content = if ($isUSBMode) { 'Create USB' } else { 'Build FFU' }
```

### Pattern 6: USB Mode ThreadJob Launch in btnRun
**What:** New branch in the existing btnRun Add_Click handler; launches -USBOnlyMode via Start-ThreadJob
**When to use:** D-28 — after pre-launch validation passes (D-19/D-20)

```powershell
# BuildFFUVM_UI.ps1 — inside existing btnRun handler, before current "start a new build" block
$isUSBMode = $script:uiState.Controls.rbUSBMode.IsChecked
if ($isUSBMode) {
    # Pre-launch validation (D-19)
    $ffuState      = $script:uiState.Data.usbArtifactState.FFU
    $deployState   = $script:uiState.Data.usbArtifactState.DeployISO
    $selectedDrives = @($script:uiState.Controls.usbUSBDriveList.Items | Where-Object { $_.IsSelected })

    if ($null -eq $ffuState.path) {
        [System.Windows.MessageBox]::Show('Select an FFU file before creating USB.', 'Validation', 'OK', 'Warning') | Out-Null
        return
    }
    if ($null -eq $deployState.path) {
        [System.Windows.MessageBox]::Show('Deploy ISO is required.', 'Validation', 'OK', 'Warning') | Out-Null
        return
    }
    if ($selectedDrives.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select a USB drive.', 'Validation', 'OK', 'Warning') | Out-Null
        return
    }

    # Launch USB Mode ThreadJob (same pattern as Full Build)
    $config = Get-UIConfig -State $script:uiState
    $usbParams = @{
        ConfigFile  = $script:uiState.Data.lastConfigFilePath
        USBOnlyMode = $true
    }
    # ... Start-ThreadJob + DispatcherTimer (reuse existing Full Build structure)
    $btnRun.Content = 'Cancel'
    $script:uiState.Flags.isBuilding = $true
    return
}
# ... existing Full Build path follows
```

### Pattern 7: Config Stub Replacement
**What:** Replace stubs in Build-UIConfiguration and Update-UIFromConfig with actual control reads/writes
**When to use:** D-22/D-23/D-24 — config save/load for ActiveMode and artifact paths

```powershell
# Build-UIConfiguration (FFUUI.Core.Config.psm1) — replace lines 166-180:
$config.ActiveMode = if ($State.Controls.rbUSBMode.IsChecked) { 'USBMode' } else { 'FullBuild' }
$config.USBMode = @{
    Artifacts = @{
        FFU       = @{ Path = $State.Data.usbArtifactState.FFU.path; Disposition = 'Reuse' }
        DeployISO = @{ Path = $State.Data.usbArtifactState.DeployISO.path; Disposition = 'Reuse' }
        Drivers   = @{ Path = $State.Data.usbArtifactState.Drivers.path; Disposition = 'Reuse' }
        PPKG      = @{ Path = $State.Data.usbArtifactState.PPKG.path; Disposition = 'Reuse' }
        Unattend  = @{ Path = $State.Data.usbArtifactState.Unattend.path; Disposition = 'Reuse' }
        Autopilot = @{ Path = $State.Data.usbArtifactState.Autopilot.path; Disposition = 'Reuse' }
        AppsISO   = @{ Path = $State.Data.usbArtifactState.AppsISO.path; Disposition = 'Reuse' }
    }
}

# Update-UIFromConfig (lines 622-628) — replace stub:
if ($ConfigContent.PSObject.Properties.Match('ActiveMode').Count -gt 0) {
    if ($ConfigContent.ActiveMode -eq 'USBMode') {
        $State.Controls.rbUSBMode.IsChecked = $true
        # rbUSBMode.Checked event fires automatically, triggering mode switch + scan
    }
}
if ($ConfigContent.PSObject.Properties.Match('USBMode').Count -gt 0 -and
    $null -ne $ConfigContent.USBMode.Artifacts) {
    foreach ($key in @('FFU','DeployISO','Drivers','PPKG','Unattend','Autopilot','AppsISO')) {
        $entry = $ConfigContent.USBMode.Artifacts.$key
        if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace($entry.Path)) {
            $State.Data.usbArtifactState[$key].path   = $entry.Path
            $State.Data.usbArtifactState[$key].source = 'user'
        }
    }
}
```

### Anti-Patterns to Avoid
- **Firing rbUSBMode.IsChecked = $true during config load without guard:** The Checked event triggers `Find-FFUArtifacts` which accesses the filesystem. If `txtFFUDevPath` is empty at load time (config loads before control values are set), the scan aborts. The scan function must null-check the path and log gracefully.
- **Hardcoding "Build FFU" in Reset-FFUUIToIdle:** Line 143 of FFUUI.Core.StateRecovery.psm1 is the only existing hardcode — two additional hardcodes exist in BuildFFUVM_UI.ps1 at lines 332 and 413 (inside cancel cleanup polling), and at line 827 (job success handler). The STATE.md audit note confirms all three must be found and fixed.
- **Calling Find-FFUArtifacts without importing FFU.ArtifactScanner:** This module is imported in BuildFFUVM.ps1 but the UI host (BuildFFUVM_UI.ps1) does not currently import it. The scan happens on the UI thread — the module must be imported in BuildFFUVM_UI.ps1 at startup (or lazily before first scan call).
- **Passing user-browsed paths to -USBOnlyMode without saving to config first:** The USBOnlyMode short-circuit in BuildFFUVM.ps1 currently uses `Find-FFUArtifacts` to discover paths itself. User-overridden paths must reach the build script either via explicit parameters or by saving config first. Saving config first (same approach as Full Build uses Get-UIConfig before launching) is the simpler path.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File/folder open dialogs | Custom WPF OpenFileDialog wrapper | `Invoke-BrowseAction -Type 'OpenFile'` / `'Folder'` | Already handles all three dialog types; filter syntax; handles null when user cancels |
| USB drive enumeration | Custom WMI queries | `Get-USBDrives` (FFUUI.Core.psm1 line 362) | Returns pre-shaped hashtable with IsSelected, Model, SerialNumber, Size, DriveIndex — exactly what the ListView expects |
| Artifact filesystem scan | Custom Get-ChildItem loops | `Find-FFUArtifacts -FFUDevelopmentPath $path` | Handles WIMMount gate, FFU metadata extraction, age calculation, multi-file types (PPKG/Unattend/Autopilot arrays), ArtifactManifest data contract |
| Background job launch | Custom runspace or job creation | `Start-ThreadJob` + `DispatcherTimer` pattern | ThreadJob preserves network credentials; DispatcherTimer pattern already debugged with 50ms polling, cancellation, error surface |
| Config round-trip | Direct JSON file writes | `Build-UIConfiguration` / `Update-UIFromConfig` + `Set-UIValue` | These functions handle null checks, type transforms, missing-key guards, and write to the correct config path |

**Key insight:** All infrastructure for this phase is already written and debugged. Phase 49 is purely wiring — connecting existing functions to existing XAML controls via the existing event handler pattern.

## Common Pitfalls

### Pitfall 1: FFU.ArtifactScanner Not Available in UI Host
**What goes wrong:** `Find-FFUArtifacts` call fails with "The term 'Find-FFUArtifacts' is not recognized" at runtime when user switches to USB Mode
**Why it happens:** `FFU.ArtifactScanner` is imported in `BuildFFUVM.ps1` but NOT in `BuildFFUVM_UI.ps1`. The scan runs on the UI thread in the UI host process.
**How to avoid:** Add import of `FFU.ArtifactScanner` to the module import block in `BuildFFUVM_UI.ps1` (lines 102-106). Use the same conditional pattern: check if module path exists first, then import with `-ErrorAction SilentlyContinue` and handle the unavailable case gracefully.
**Warning signs:** `Find-FFUArtifacts` works during `-USBOnlyMode` builds but throws in UI on first mode switch.

### Pitfall 2: Mode Switch Event Fires During Config Load (Infinite Loop Risk)
**What goes wrong:** Setting `rbUSBMode.IsChecked = $true` during `Update-UIFromConfig` fires the `Checked` event, which calls `Invoke-USBArtifactScan`, which reads `txtFFUDevPath.Text` — but config load hasn't populated that control yet (config loading order dependency).
**Why it happens:** WPF RadioButton fires `Checked` synchronously when `IsChecked` is set in code.
**How to avoid:** Two options: (a) initialize `usbArtifactState` from config data BEFORE setting `IsChecked`, so the scan uses pre-loaded paths; (b) add a `$State.Flags.isLoadingConfig` guard in the scan function that short-circuits when config is actively loading. Option (b) is cleaner for config load ordering independence.
**Warning signs:** Scan runs with empty path immediately on config load; status shows "(scanning...)" then "Not scanned" because path was empty.

### Pitfall 3: Cancel Flow Hardcoded Button Labels
**What goes wrong:** After USB Mode build completes or is cancelled, button reverts to "Build FFU" instead of "Create USB"
**Why it happens:** The STATE.md explicitly flags this audit: lines 332, 413, 827 of `BuildFFUVM_UI.ps1` and line 143 of `FFUUI.Core.StateRecovery.psm1` all hardcode `btnRun.Content = "Build FFU"`. Only Reset-FFUUIToIdle (line 143) gets the mode-aware fix automatically if implemented correctly. The three in BuildFFUVM_UI.ps1 are raw assignments that bypass Reset-FFUUIToIdle.
**How to avoid:** Audit all `btnRun.Content = ` assignments across both files. Replace each with the mode-aware pattern. Consider extracting a `Set-RunButtonToIdleLabel` helper function.
**Warning signs:** User in USB Mode cancels a build, button shows "Build FFU", clicking it launches a Full Build instead of USB Mode.

### Pitfall 4: usbArtifactState Not Initialized Before Register-EventHandlers Runs
**What goes wrong:** Browse handlers reference `$localState.Data.usbArtifactState.FFU.path` but the key doesn't exist yet, causing NullReferenceException
**Why it happens:** `$script:uiState.Data` is a hashtable initialized at line 61 of `BuildFFUVM_UI.ps1`. `usbArtifactState` must be added there, not lazily in the handler.
**How to avoid:** Add `usbArtifactState = @{ FFU = @{...}; ... }` to the `Data = @{...}` block in BuildFFUVM_UI.ps1 at startup (alongside `allDriverModels`, `pollTimer`, etc.).
**Warning signs:** NullReferenceException on first Browse button click before any scan has run.

### Pitfall 5: Config Load Order — ActiveMode Before Artifact Paths
**What goes wrong:** Config load sets `rbUSBMode.IsChecked = $true` before restoring user-overridden paths from USBMode.Artifacts, so the triggered scan overwrites paths with auto-detected values
**Why it happens:** `Update-UIFromConfig` processes keys sequentially; if ActiveMode is set first and fires the scan, user overrides haven't been loaded into `usbArtifactState` yet.
**How to avoid:** In `Update-UIFromConfig`, load USBMode.Artifacts paths into `$State.Data.usbArtifactState` (marking them `source='user'`) BEFORE setting `rbUSBMode.IsChecked`. The scan function checks `source` before overwriting — so pre-loaded user paths survive the scan trigger.
**Warning signs:** User-specified paths reset to auto-detected values every time config is loaded.

### Pitfall 6: USBOnlyMode Build Script Gets Default Artifact Paths
**What goes wrong:** User browses to a custom FFU path, launches "Create USB", but the build uses the auto-detected path because user override wasn't communicated to BuildFFUVM.ps1
**Why it happens:** Phase 47's USBOnlyMode short-circuit calls `Find-FFUArtifacts` internally with only `FFUDevelopmentPath`. It has no mechanism for path overrides.
**How to avoid:** Before launching the ThreadJob, call `Get-UIConfig` (which now includes USBMode artifact paths via the fixed stubs) and save config to the temp config path. BuildFFUVM.ps1 receives the config file; its USBOnlyMode block uses `Find-FFUArtifacts` results, which use `FFUDevelopmentPath` — but the user-override paths should be injected as explicit parameters OR the USBOnlyMode block should check for config-provided path overrides. The simplest approach: save config to file first (same as Full Build does), pass `-ConfigFile` to BuildFFUVM.ps1, and extend the USBOnlyMode block to read `USBMode.Artifacts.{Type}.Path` from config when non-null.
**Warning signs:** User overrides ignored silently; build uses wrong artifact.

## Code Examples

### Control Name Inventory (46 named controls in usbModeTab)

From XAML lines 932-1243 (verified by read):

| Control Name | Type | Initial State |
|---|---|---|
| `usbFFUInclude` | CheckBox | IsEnabled=False, IsChecked=True |
| `usbFFUStatus` | TextBlock | Text="(scanning...)" |
| `usbFFUPath` | TextBlock | Text="(not scanned)" |
| `usbFFUBrowse` | Button | IsEnabled=False |
| `usbFFUSize` | TextBlock | Text="--" |
| `usbFFUAge` | TextBlock | Text="--" |
| `usbFFUVersion` | TextBlock | Text="--" |
| `usbFFUSKU` | TextBlock | Text="--" |
| `usbFFUArch` | TextBlock | Text="--" |
| `usbDeployISOInclude` | CheckBox | IsEnabled=False, IsChecked=True |
| `usbDeployISOStatus` | TextBlock | Text="(scanning...)" |
| `usbDeployISOPath` | TextBlock | Text="(not scanned)" |
| `usbDeployISOBrowse` | Button | IsEnabled=False |
| `usbDeployISOSize` | TextBlock | Text="--" |
| `usbDeployISOAge` | TextBlock | Text="--" |
| `usbDriversInclude` | CheckBox | IsEnabled=False, IsChecked=False |
| `usbDriversStatus` | TextBlock | Text="(scanning...)" |
| `usbDriversPath` | TextBlock | Text="(not scanned)" |
| `usbDriversBrowse` | Button | IsEnabled=False |
| `usbDriversSize` | TextBlock | Text="--" |
| `usbDriversAge` | TextBlock | Text="--" |
| `usbPPKGInclude` | CheckBox | IsEnabled=False, IsChecked=False |
| `usbPPKGStatus` | TextBlock | Text="(scanning...)" |
| `usbPPKGPath` | TextBlock | Text="(not scanned)" |
| `usbPPKGBrowse` | Button | IsEnabled=False |
| `usbPPKGSize` | TextBlock | Text="--" |
| `usbPPKGAge` | TextBlock | Text="--" |
| `usbUnattendInclude` | CheckBox | IsEnabled=False, IsChecked=False |
| `usbUnattendStatus` | TextBlock | Text="(scanning...)" |
| `usbUnattendPath` | TextBlock | Text="(not scanned)" |
| `usbUnattendBrowse` | Button | IsEnabled=False |
| `usbUnattendSize` | TextBlock | Text="--" |
| `usbUnattendAge` | TextBlock | Text="--" |
| `usbAutopilotInclude` | CheckBox | IsEnabled=False, IsChecked=False |
| `usbAutopilotStatus` | TextBlock | Text="(scanning...)" |
| `usbAutopilotPath` | TextBlock | Text="(not scanned)" |
| `usbAutopilotBrowse` | Button | IsEnabled=False |
| `usbAutopilotSize` | TextBlock | Text="--" |
| `usbAutopilotAge` | TextBlock | Text="--" |
| `usbAppsISOInclude` | CheckBox | IsEnabled=False, IsChecked=False |
| `usbAppsISOStatus` | TextBlock | Text="(scanning...)" |
| `usbAppsISOPath` | TextBlock | Text="(not scanned)" |
| `usbAppsISOBrowse` | Button | IsEnabled=False |
| `usbAppsISOSize` | TextBlock | Text="--" |
| `usbAppsISOAge` | TextBlock | Text="--" |

**XAML controls NOT yet present (require XAML additions in Plan 1):**
- `usbRescanArtifacts` Button (D-04)
- `usbCheckUSBDrives` Button (D-10)
- `usbUSBDriveList` ListView (D-10)
- `usbSelectAllDrives` CheckBox (D-10)

### ArtifactManifest Properties (verified from FFU.ArtifactScanner.psm1)

```powershell
# ArtifactManifest properties relevant to UI updates:
$manifest.FFUFiles       # Array of ArtifactResult — IsPrimary, Status, FilePath, FileSizeBytes, AgeDays, Metadata
$manifest.DeployISO      # Single ArtifactResult — Status, FilePath, FileSizeBytes, AgeDays
$manifest.Drivers        # Single ArtifactResult — Status, FilePath, FileSizeBytes, AgeDays
$manifest.PPKGFiles      # Array of ArtifactResult
$manifest.UnattendFiles  # Array of ArtifactResult
$manifest.AutopilotFiles # Array of ArtifactResult
$manifest.AppsISO        # Single ArtifactResult — Status, FilePath, FileSizeBytes, AgeDays
$manifest.IsReady        # bool — true when FFU Found + DeployISO Found

# ArtifactResult.Metadata (FFU only — FFUMetadata class):
$ffuResult.Metadata.WindowsVersion   # e.g., "23H2"
$ffuResult.Metadata.SKU               # e.g., "Pro"
$ffuResult.Metadata.Architecture      # e.g., "x64"

# Status values (ArtifactStatus enum — compare as .ToString()):
# 'Found', 'Missing', 'Partial', 'Unknown'

# Format helpers for UI display:
$sizeGB = '{0:F2} GB' -f ($result.FileSizeBytes / 1GB)
$ageText = if ($result.AgeDays -eq 0) { 'Today' }
           elseif ($result.AgeDays -eq 1) { '1 day ago' }
           else { "$($result.AgeDays) days ago" }
```

### Invoke-BrowseAction Filters Per Artifact Type

```powershell
# Source: FFUUI.Core.Shared.psm1 line 826 — Invoke-BrowseAction signature
# Type = 'OpenFile' | 'Folder' | 'SaveFile'

# FFU: single .ffu file
Invoke-BrowseAction -Type 'OpenFile' -Title 'Select FFU Image' -Filter 'FFU files (*.ffu)|*.ffu'

# DeployISO: single .iso file
Invoke-BrowseAction -Type 'OpenFile' -Title 'Select WinPE Deploy ISO' -Filter 'ISO files (*.iso)|*.iso'

# Drivers: folder
Invoke-BrowseAction -Type 'Folder' -Title 'Select Drivers Folder'

# PPKG: single .ppkg file
Invoke-BrowseAction -Type 'OpenFile' -Title 'Select Provisioning Package' -Filter 'PPKG files (*.ppkg)|*.ppkg'

# Unattend: single .xml file
Invoke-BrowseAction -Type 'OpenFile' -Title 'Select Unattend.xml' -Filter 'XML files (*.xml)|*.xml'

# Autopilot: single .json file
Invoke-BrowseAction -Type 'OpenFile' -Title 'Select Autopilot Profile' -Filter 'JSON files (*.json)|*.json'

# AppsISO: single .iso file
Invoke-BrowseAction -Type 'OpenFile' -Title 'Select Applications ISO' -Filter 'ISO files (*.iso)|*.iso'
```

### Existing Button Label Hardcodes That Need Mode-Awareness (STATE.md audit)

| Location | Line (approx) | Current Value | Fix Required |
|---|---|---|---|
| FFUUI.Core.StateRecovery.psm1 | 143 | `"Build FFU"` | Replace with mode-aware check |
| BuildFFUVM_UI.ps1 (cancel cleanup poll complete) | 413 | `"Build FFU"` | Replace with mode-aware check |
| BuildFFUVM_UI.ps1 (no config found, cancel path) | 332 | `"Build FFU"` | Replace with mode-aware check |
| BuildFFUVM_UI.ps1 (job success handler) | 827 | `"Build FFU"` | Replace with mode-aware check |

### USBOnlyMode Build Script — What It Needs From UI

The current Phase 47 USBOnlyMode block (BuildFFUVM.ps1 lines 1726-1830) calls `Find-FFUArtifacts` internally. To honor user-browsed paths, one of two approaches works:

**Approach A (recommended — simpler):** Save config to file before launching ThreadJob (same as Full Build). Extend USBOnlyMode block to check `$config.USBMode.Artifacts.FFU.Path` etc. and use them when non-null, skipping auto-detect for those artifact types.

**Approach B:** Pass explicit `-FFUPath`, `-DeployISOPath`, `-DriversPath` etc. parameters to BuildFFUVM.ps1. This requires adding new parameters to the already-large param block.

Approach A is preferred because it reuses the existing config save mechanism and the config schema already has the fields.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Full Build tabs always visible | Tab visibility controlled by mode toggle | Phase 48 | Tab names documented in D-27 |
| No USB Mode in config | ActiveMode + USBMode.Artifacts section in schema | Phase 45 | Config stubs ready |
| ArtifactScanner not in project | FFU.ArtifactScanner module with Find-FFUArtifacts | Phase 46 | Direct integration target for phase 49 |
| USBOnlyMode not in build script | -USBOnlyMode switch in BuildFFUVM.ps1 | Phase 47 | ThreadJob launch pattern established |
| USB Mode tab doesn't exist | usbModeTab with 46 named controls | Phase 48 | All controls ready to wire |

## Open Questions

1. **How does -USBOnlyMode receive user-overridden artifact paths?**
   - What we know: USBOnlyMode currently uses `Find-FFUArtifacts -FFUDevelopmentPath` with no path override mechanism. The config schema has `USBMode.Artifacts.{Type}.Path` fields.
   - What's unclear: Whether to extend USBOnlyMode to read from config, or extend USBOnlyMode to accept explicit path parameters.
   - Recommendation: Approach A (save config first, extend USBOnlyMode to check config paths). This avoids expanding the param block and reuses the existing config round-trip.

2. **Should Rescan also re-validate user-overridden paths?**
   - What we know: D-07 says rescan preserves user paths. D-09 says per-card reset clears back to auto.
   - What's unclear: Whether rescan silently re-checks if user-overridden paths still exist.
   - Recommendation: Yes — verify existence on rescan and update status to "Missing (user path)" if file/folder no longer found, while keeping `source='user'`. This prevents silent "file moved" failures.

3. **Config load triggering scan before FFUDevPath is populated**
   - What we know: `Update-UIFromConfig` sets `rbUSBMode.IsChecked` which fires scan; config load sequence isn't guaranteed to set `txtFFUDevPath` before RadioButtons.
   - Recommendation: Add `$State.Flags.isLoadingConfig = $true` guard around the entire `Update-UIFromConfig` block; scan function checks flag and defers scan until after load completes. A post-load Dispatcher.BeginInvoke can then fire the initial scan.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Pester 5.x |
| Config file | Tests/Unit/Invoke-PesterTests.ps1 |
| Quick run command | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFUUI.Core'` |
| Full suite command | `.\Tests\Unit\Invoke-PesterTests.ps1` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DISC-02 | Browse handlers update usbArtifactState.source='user' and path TextBlock | Unit | `Invoke-Pester -Path Tests\Unit\Phase49.Tests.ps1 -Tag BrowseHandler` | No — Wave 0 |
| DISC-03 | Build-UIConfiguration writes ActiveMode and artifact paths; Update-UIFromConfig restores them | Unit | `Invoke-Pester -Path Tests\Unit\Phase49.Tests.ps1 -Tag ConfigPersistence` | No — Wave 0 |
| USB-02 | usbCheckUSBDrives handler populates usbUSBDriveList from Get-USBDrives | Unit (mock) | `Invoke-Pester -Path Tests\Unit\Phase49.Tests.ps1 -Tag USBDriveDetection` | No — Wave 0 |
| USB-03 | Include CheckBox states map correctly to copy gate parameters | Unit | `Invoke-Pester -Path Tests\Unit\Phase49.Tests.ps1 -Tag IncludeFlags` | No — Wave 0 |

### Sampling Rate
- **Per task commit:** `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFUUI.Core'`
- **Per wave merge:** `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/Unit/Phase49.Tests.ps1` — covers all 4 requirement test cases above
- [ ] Mock patterns for `Find-FFUArtifacts`, `Get-USBDrives`, `Invoke-BrowseAction` (WPF-free unit tests)

## Sources

### Primary (HIGH confidence)
- Direct code read: `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` — handler registration patterns, btnCheckUSBDrives handler, browse patterns
- Direct code read: `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` lines 826-878 — Invoke-BrowseAction signature and type options
- Direct code read: `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` lines 155-220 and 622-630 — stub locations
- Direct code read: `FFUDevelopment/FFUUI.Core/FFUUI.Core.StateRecovery.psm1` — Reset-FFUUIToIdle, hardcoded "Build FFU" at line 143
- Direct code read: `FFUDevelopment/BuildFFUVM_UI.ps1` lines 50-90 (state init), 209-851 (btnRun handler with all hardcodes), 332, 413, 827
- Direct code read: `FFUDevelopment/BuildFFUVM_UI.xaml` lines 932-1243 — all 46 named controls in usbModeTab with initial states
- Direct code read: `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1` — Find-FFUArtifacts signature, ArtifactManifest properties
- Direct code read: `FFUDevelopment/BuildFFUVM.ps1` lines 1726-1830 — USBOnlyMode short-circuit block
- Direct code read: `FFUDevelopment/config/ffubuilder-config.schema.json` lines 653-700 — ActiveMode + USBMode.Artifacts schema
- Direct read: `.planning/STATE.md` — audit note confirming btnRun.Content hardcode locations

### Secondary (MEDIUM confidence)
- `.planning/phases/49-ui-event-wiring-and-artifact-integration/49-CONTEXT.md` — all 30 locked decisions D-01 through D-30
- `.planning/REQUIREMENTS.md` — DISC-02, DISC-03, USB-02, USB-03 traceability

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all referenced functions read directly from source
- Architecture: HIGH — all XAML controls and event patterns verified from actual files
- Pitfalls: HIGH — pitfalls derived from direct code inspection, not heuristics (FFU.ArtifactScanner import gap confirmed, hardcode locations confirmed from STATE.md + source)
- Config persistence: HIGH — stubs read directly at exact line numbers, schema fields verified

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (stable codebase — no external dependencies)
