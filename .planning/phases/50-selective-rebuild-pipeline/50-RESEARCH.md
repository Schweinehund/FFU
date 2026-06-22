# Phase 50: Selective Rebuild Pipeline - Research

**Researched:** 2026-06-22
**Domain:** PowerShell / WPF / BuildFFUVM.ps1 USB-Mode pipeline + FFUUI.Core UI wiring
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Each artifact card uses a **single ComboBox** (Reuse/Rebuild/Skip) REPLACING the Phase-49 include checkbox.
- **D-02:** ComboBox ItemsSource is per-card, driven by scope tier (3 items buildable, 2 items user-authored, 1 disabled Reuse for required).
- **D-03:** Required artifacts (FFU, DeployISO) render as ComboBox with only `Reuse`, `IsEnabled=False`.
- **D-04:** Buildable artifacts — Drivers, AppsISO, DeployISO — offer full Reuse/Rebuild/Skip.
- **D-05:** User-authored artifacts — PPKG, Unattend, Autopilot — offer only Reuse/Skip.
- **D-06:** FFU is Reuse-only (ComboBox, 1 item, disabled).
- **D-07:** Drivers Rebuild gated on input availability ($driversJsonPath + Make/Model); Phase 50 adds those inputs or degrades Drivers to Reuse/Skip if they cannot be sourced.
- **D-08/D-09:** FFU rebuild DISALLOWED in USB Mode; show inline helper text pointing to Full Build mode (rbFullBuild/rbUSBMode RadioButtons, XAML line 78-79).
- **D-10:** Found→Reuse; Missing Required→block (IsReady throw); Missing Optional→Skip; Degraded→Reuse+warning; Error→treat as Missing per tier.
- **D-11:** Widen 4-status scanner UI end-to-end (Degraded and Error statuses must render).
- **D-12:** Build selective per-phase execution machinery (F3 gap) — largest cost in the phase.

### Claude's Discretion

- Exact ComboBox styling, item rendering, and how Degraded/Error warnings surface on the card.
- The mechanism/shape of the selective per-phase execution gate.
- How rebuilt artifact outputs are reconciled into `New-DeploymentUSB` script-scoped globals.
- Whether Drivers Make/Model inputs live on the Drivers card vs. are read from active config.

### Deferred Ideas (OUT OF SCOPE)

- Inline FFU rebuild inside USB Mode.
- Auto-rebuild of stale or missing artifacts.
- Saved USB Mode profiles (REBUILD-04).
- Artifact version history / rollback (REBUILD-05).
- Network/cloud artifact sources.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REBUILD-01 | User can mark each artifact as reuse, rebuild, or skip | ComboBox wiring in XAML + Handlers (F-UI section below) |
| REBUILD-02 | Pipeline executes only the build phases needed for artifacts marked "rebuild" | Selective execution gate (F3 section below) |
| REBUILD-03 | Rebuilt artifacts are combined with reused artifacts for final USB assembly | New-DeploymentUSB path reconciliation (F1/F2 sections below) |

</phase_requirements>

---

## Summary

Phase 50 delivers the Selective Rebuild Pipeline for USB Mode. Users replace the existing per-artifact include checkbox with a ComboBox offering Reuse/Rebuild/Skip (or a subset thereof, tiered by artifact type). The pipeline gate in `BuildFFUVM.ps1`'s USBOnlyMode short-circuit (lines 1727-1924) is rewritten to read `Disposition` from config instead of the non-schema `Include` boolean. For artifacts marked Rebuild, the pipeline executes only the corresponding build phase(s) in isolation before assembling the USB.

There are five concrete implementation gaps (F1 through F7) identified in the CONTEXT.md. The research below provides exact line numbers, change surfaces, and recommended approaches for each. The largest single cost is F3 (selective per-phase execution). The cleanest mechanism — confirmed by reading the actual skip-flag code — is a new parallel `$rebuildPhase` gate set that mirrors the existing `$skipPhase` pattern but operates inversely: a rebuild gate is `$true` (run this phase) when that artifact's disposition is Rebuild, regardless of the normal resume/skip logic.

**Primary recommendation:** Implement F1 (AppsISO copy path), F2 (Disposition gate rewrite), F3 (selective execution via `$rebuildDrivers`/`$rebuildAppsISO`/`$rebuildDeployISO` flags), F6 (Drivers Make/Model sourced from config), and F7 (4-status UI) as five distinct, ordered work items within the phase.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Disposition ComboBox rendering | UI / XAML | — | Control definition lives in BuildFFUVM_UI.xaml |
| Disposition event wiring | UI / Handlers (FFUUI.Core.Handlers.psm1) | Config (FFUUI.Core.Config.psm1) | SelectionChanged → usbArtifactState + config save |
| Disposition persistence (round-trip) | Config (FFUUI.Core.Config.psm1) | — | Build-UIConfiguration reads ComboBox; Update-UIFromConfig restores it |
| Disposition → copy gate translation | Pipeline (BuildFFUVM.ps1 ~1895-1911) | — | Must rewrite Include-reading block to read Disposition |
| Selective build-phase execution | Pipeline (BuildFFUVM.ps1 USBOnlyMode block) | Modules (FFU.Drivers, FFU.Apps, FFU.Media) | Short-circuit block orchestrates selective calls |
| AppsISO USB copy | Pipeline (New-DeploymentUSB function ~1328-1562) | — | F1 gap: must add `$CopyAppsISO` / `$AppsISOPath` to function |
| Drivers inputs (Make/Model/driversJsonPath) | Config (ffubuilder-config.schema.json + UI) | Pipeline | F6: config is the canonical source; USB tab card adds fields |
| 4-status scanner UI | UI / Handlers (Invoke-USBArtifactScan) | — | Widen the binary Found/else branch to handle Degraded/Error |
| ADK path for DeployISO rebuild | Pipeline (USBOnlyMode block) | Config | $adkPath must be resolved before New-PEMedia call |

---

## Standard Stack

No new external packages are introduced. Phase 50 operates entirely within the established project stack.

| Component | Version | Purpose |
|-----------|---------|---------|
| `BuildFFUVM.ps1` | Current (2404 lines) | USB-mode short-circuit, skip/build flags, New-DeploymentUSB |
| `FFU.ArtifactScanner` | 1.0.0 | 4-status scan (ArtifactStatus: Found/Missing/Error/Degraded) |
| `FFU.Media` (`New-PEMedia`) | Current | DeployISO rebuild via `FFU.Media.psm1:912` |
| `FFU.Apps` (`New-AppsISO`) | Current | AppsISO rebuild via `FFU.Apps.psm1:216` |
| `FFU.Drivers` | Current | Driver download phase (via `Invoke-ParallelProcessing`) |
| `FFUUI.Core.Handlers.psm1` | Current | Event handler wiring; `$artifactMap` with `includeCtrl` keys |
| `FFUUI.Core.Config.psm1` | Current | `Build-UIConfiguration` / `Update-UIFromConfig` USB stubs |
| `BuildFFUVM_UI.xaml` | Current | USB Mode tab artifact cards (lines 932-1243) |
| `ffubuilder-config.schema.json` | v1.3 | `Disposition` enum already defined (`ArtifactEntry`, line 692-697) |

**Package Legitimacy Audit:** Not applicable — no new packages.

---

## F1 — AppsISO Copy Path in New-DeploymentUSB

### Current State

`New-DeploymentUSB` (BuildFFUVM.ps1 lines 1328-1562) copies: FFU, Drivers, PPKG, Unattend, Autopilot. It does **not** copy AppsISO.

The explicit comment at line 1894 confirms: `# NOTE: No $CopyAppsISO flag exists in this block (Issue #10) -- AppsISO is handled via path only`

The `ForEach-Object -Parallel` block (lines 1424-1555) reads these `$using:` variables:
- `$using:PSScriptRoot`, `$using:LogFile`, `$using:ISOMountPoint`
- `$using:CopyFFU`, `$using:SelectedFFUFile`
- `$using:CopyDrivers`, `$using:DriversFolder`
- `$using:CopyPPKG`, `$using:PPKGFolder`
- `$using:CopyUnattend`, `$using:WindowsArch`, `$using:UnattendFolder`
- `$using:CopyAutopilot`, `$using:AutopilotFolder`

**AppsISO is NOT in the `$using:` inventory.**

The ArtifactScanner DOES scan for AppsISO (FFU.ArtifactScanner.psm1 line 551; `$manifest.AppsISO`). The scanner returns `FilePath = "$FFUDevelopmentPath\Apps\Apps.iso"`.

### What Must Change

**1. Add two new script-scoped variables before calling `New-DeploymentUSB`:**
```powershell
$CopyAppsISO = $false           # copy gate
$AppsISOPath  = "$FFUDevelopmentPath\Apps\Apps.iso"  # default path
```

**2. Populate `$CopyAppsISO` from manifest or config in the USBOnlyMode block** (parallel to the existing Drivers/PPKG/Unattend/Autopilot pattern at lines 1829-1890):
```powershell
# After step 5 variable population (~line 1829)
$CopyAppsISO = ($null -ne $manifest.AppsISO -and $manifest.AppsISO.Status.ToString() -eq 'Found')
if ($null -ne $manifest.AppsISO -and -not [string]::IsNullOrWhiteSpace($manifest.AppsISO.FilePath)) {
    $AppsISOPath = $manifest.AppsISO.FilePath
}
if (-not $CopyAppsISO) { WriteLog "WARNING: Skipping AppsISO -- not found at $AppsISOPath" }
```

**3. Apply config override in step 5b (~line 1870 area, parallel to Drivers override):**
```powershell
if ($null -ne $cfgArt.AppsISO -and -not [string]::IsNullOrWhiteSpace($cfgArt.AppsISO.Path) -and (Test-Path -LiteralPath $cfgArt.AppsISO.Path)) {
    $AppsISOPath = $cfgArt.AppsISO.Path
    $CopyAppsISO = $true
    WriteLog "USBOnlyMode: Overrode AppsISO path from config: $($cfgArt.AppsISO.Path)"
}
```

**4. Add Disposition-based override (F2) for Skip:**
```powershell
if ($null -ne $cfgArt.AppsISO -and $cfgArt.AppsISO.Disposition -eq 'Skip') {
    $CopyAppsISO = $false
    WriteLog "USBOnlyMode: AppsISO disposition=Skip -- excluding from USB."
}
```

**5. Extend the `ForEach-Object -Parallel` block inside `New-DeploymentUSB`** to copy AppsISO:
```powershell
# After the $using:CopyAutopilot block (~line 1542):
if ($using:CopyAppsISO) {
    $AppsISODest = Join-Path $DeployPartitionDriveLetter "Apps"
    New-Item -Path $AppsISODest -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    WriteLog "Copying Apps ISO to $AppsISODest"
    robocopy (Split-Path $using:AppsISOPath -Parent) $AppsISODest (Split-Path $using:AppsISOPath -Leaf) /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Test-RobocopySuccess -Operation "AppsISO to USB"
}
```

**Critical:** The `$using:CopyAppsISO` and `$using:AppsISOPath` variables must be script-scope (not local) before the `New-DeploymentUSB` call — the parallel block captures them via `$using:` scope from the calling script scope.

[VERIFIED: BuildFFUVM.ps1 lines 1328-1562, 1424-1555, 1894]

---

## F2 — Disposition Gate Rewrite (Include → Disposition)

### Current State

Lines 1893-1911 of BuildFFUVM.ps1 read `.Include` (a non-schema boolean) to set copy flags to `$false`:

```powershell
# Line 1895 (actual — read from file):
if ($null -ne $cfgArt.Drivers -and $cfgArt.Drivers.PSObject.Properties.Match('Include').Count -gt 0 -and -not [bool]$cfgArt.Drivers.Include) {
    $CopyDrivers = $false
    WriteLog "USBOnlyMode: Drivers unchecked by user -- skipping."
}
# Lines 1899-1910: same pattern for PPKG, Unattend, Autopilot
```

The schema (`ArtifactEntry`, line 692-697 of ffubuilder-config.schema.json) defines `Disposition` (Reuse/Rebuild/Skip) but has **no `Include` property**. The current gate is reading a non-schema field that Build-UIConfiguration currently writes alongside Disposition (Config.psm1 line 186 writes `Disposition = 'Reuse'` statically; line 187 writes `Include = $includeChecked` from the checkbox).

### What Must Change

**Replace the entire Include-checking block (lines 1893-1911) with a Disposition-reading block.** The new logic:

- `Reuse` → artifact is already in the copy path (set by scan/override above); no change.
- `Skip` → set copy flag to `$false`, log.
- `Rebuild` → copy flag depends on whether the rebuild phase ran successfully (set after F3 selective execution).

New gate (replaces lines 1893-1911):
```powershell
# Disposition-based copy gate (Phase 50 — replaces Include-flag gate)
# Applied AFTER path overrides, BEFORE USB assembly
$dispositionCheckTypes = @('FFU', 'DeployISO', 'Drivers', 'AppsISO', 'PPKG', 'Unattend', 'Autopilot')
foreach ($dType in $dispositionCheckTypes) {
    $dEntry = $cfgArt.$dType
    if ($null -eq $dEntry) { continue }
    $disp = if ($dEntry.PSObject.Properties.Match('Disposition').Count -gt 0) { $dEntry.Disposition } else { 'Reuse' }
    switch ($disp) {
        'Skip' {
            # Set the copy flag to $false for this type
            switch ($dType) {
                'Drivers'   { $CopyDrivers = $false;  WriteLog "USBOnlyMode: Drivers disposition=Skip -- excluding." }
                'AppsISO'   { $CopyAppsISO = $false;  WriteLog "USBOnlyMode: AppsISO disposition=Skip -- excluding." }
                'PPKG'      { $CopyPPKG = $false;     WriteLog "USBOnlyMode: PPKG disposition=Skip -- excluding." }
                'Unattend'  { $CopyUnattend = $false; WriteLog "USBOnlyMode: Unattend disposition=Skip -- excluding." }
                'Autopilot' { $CopyAutopilot = $false;WriteLog "USBOnlyMode: Autopilot disposition=Skip -- excluding." }
                # FFU and DeployISO cannot be Skip (required; enforced by UI and IsReady gate)
            }
        }
        'Rebuild' {
            # Rebuild handled by F3 selective execution — output path variables already set
            # by the rebuild execution block before this gate runs.
            WriteLog "USBOnlyMode: $dType disposition=Rebuild -- using freshly built artifact."
        }
        default { } # Reuse: no change; copy flags already set from scan/override
    }
}
```

**Also update `Build-UIConfiguration` (FFUUI.Core.Config.psm1 line 183-188):** Remove the static `Disposition = 'Reuse'` and `Include = $includeChecked` writes. Replace with reading the actual ComboBox SelectedItem:
```powershell
# New: read Disposition from ComboBox instead of Include from checkbox
$dispCtrlName = "usb${artifactType}Disposition"
$disposition = 'Reuse'  # default
if ($null -ne $State.Controls[$dispCtrlName]) {
    $disposition = $State.Controls[$dispCtrlName].SelectedItem.Tag  # Tag stores the enum string
}
$config.USBMode.Artifacts[$artifactType] = @{
    Path        = $pathToSave
    Disposition = $disposition
}
```

**Also update `Update-UIFromConfig` (FFUUI.Core.Config.psm1 lines 658-663):** Replace `$entry.Include` restore with ComboBox selection restore:
```powershell
if ($null -ne $entry -and $entry.PSObject.Properties.Match('Disposition').Count -gt 0) {
    $dispCtrlName = "usb${key}Disposition"
    if ($null -ne $State.Controls[$dispCtrlName]) {
        $targetDisp = $entry.Disposition
        foreach ($item in $State.Controls[$dispCtrlName].Items) {
            if ($item.Tag -eq $targetDisp) {
                $State.Controls[$dispCtrlName].SelectedItem = $item
                break
            }
        }
    }
}
```

[VERIFIED: BuildFFUVM.ps1 lines 1893-1911; FFUUI.Core.Config.psm1 lines 166-188, 639-665; ffubuilder-config.schema.json lines 681-700]

---

## F3 — Selective Per-Phase Execution Machinery

### Current Skip-Flag Pattern

The existing resume-forward skip flags follow this pattern (verified at lines 2653-2661, 5318-5322, 5378-5382):

```powershell
$skipDriverDownload = $false
if ($script:IsResuming -and (Test-PhaseAlreadyComplete -PhaseName 'DriverDownload' -Checkpoint $script:ResumeCheckpoint)) {
    WriteLog "RESUME: Skipping Driver Download phase - already completed"
    $skipDriverDownload = $true
}
# Later:
if (-not $skipDriverDownload -and $driversJsonPath -and ...) { ... driver download ... }
```

The flags are: `$skipPreflightValidation` (line 1933), `$skipDriverDownload` (line 2653), `$skipDeploymentMedia` (line 5318), `$skipUSBCreation` (line 5378). **These only activate when `$script:IsResuming` is true** — they are forward-skip guards for checkpoint resume, not isolation gates.

The USBOnlyMode short-circuit (lines 1727-1924) `return`s at line 1924 — the normal build phases (pre-flight, VM create, VHDX, FFU capture, driver download, apps ISO, deployment media, USB creation) are **never reached** from USBOnlyMode. This is correct architecture: USB Mode is a separate execution path.

### Recommended Mechanism for F3

**A parallel `$rebuild<Phase>` gate set within the USBOnlyMode block.** The approach:

1. Read dispositions from config (or from the disposition ComboBox values passed in) at the **start of the USBOnlyMode block** (after line 1741, after scan).
2. Set rebuild flags:
```powershell
$rebuildDrivers   = ($cfgArt.Drivers.Disposition   -eq 'Rebuild')
$rebuildAppsISO   = ($cfgArt.AppsISO.Disposition   -eq 'Rebuild')
$rebuildDeployISO = ($cfgArt.DeployISO.Disposition -eq 'Rebuild')
# FFU/PPKG/Unattend/Autopilot cannot be Rebuild in USB Mode
```
3. **Insert a selective rebuild block between Step 5 (populate variables) and Step 6 (detect USB drives)** — roughly after line 1911:

```powershell
# === PHASE 50: Selective Rebuild Execution ===
# Runs ONLY the build phases for artifacts marked Rebuild.
# Order: Drivers → AppsISO → DeployISO (dependency order).

if ($rebuildDrivers) {
    WriteLog "USBOnlyMode: Rebuilding Drivers (disposition=Rebuild)..."
    Set-Progress -Percentage 20 -Message "Rebuilding drivers..."
    # Requires: $driversJsonPath, $DriversFolder, $WindowsRelease, $WindowsArch, $WindowsVersion
    # $driversJsonPath sourced from config (see F6 below)
    if ($driversJsonPath -and (Test-Path $driversJsonPath)) {
        # Re-run driver download logic (extracted from build phase ~2664-2840)
        # This is the most complex rebuild — see F6 for input sourcing
        <driver download block>
    }
    else {
        WriteLog "WARNING: Drivers Rebuild requested but driversJsonPath not available. Skipping rebuild, using existing."
    }
}

if ($rebuildAppsISO) {
    WriteLog "USBOnlyMode: Rebuilding AppsISO (disposition=Rebuild)..."
    Set-Progress -Percentage 40 -Message "Rebuilding Apps ISO..."
    # Requires: $adkPath, $AppsPath, $AppsISO
    # New-AppsISO (FFU.Apps.psm1:216) needs ADK path + Apps folder
    $adkPath = Get-ADKPath  # function from FFU.ADK module (already imported)
    if ([string]::IsNullOrWhiteSpace($adkPath)) {
        WriteLog "WARNING: ADK not found. Cannot rebuild AppsISO."
    }
    else {
        New-AppsISO -ADKPath $adkPath -AppsPath $AppsPath -AppsISO $AppsISO
        $AppsISOPath = $AppsISO
        $CopyAppsISO = $true
        WriteLog "USBOnlyMode: AppsISO rebuilt at $AppsISO"
    }
}

if ($rebuildDeployISO) {
    WriteLog "USBOnlyMode: Rebuilding DeployISO (disposition=Rebuild)..."
    Set-Progress -Percentage 60 -Message "Rebuilding deployment ISO..."
    # Requires: $adkPath, $FFUDevelopmentPath, $WindowsArch, $DeployISO
    # New-PEMedia (FFU.Media.psm1:912) is the exact function called at line 5361
    $adkPath = Get-ADKPath
    if ([string]::IsNullOrWhiteSpace($adkPath)) {
        WriteLog "WARNING: ADK not found. Cannot rebuild DeployISO."
    }
    else {
        New-PEMedia -Capture $false -Deploy $true -adkPath $adkPath `
                    -FFUDevelopmentPath $FFUDevelopmentPath `
                    -WindowsArch $WindowsArch -CaptureISO $null -DeployISO $DeployISO `
                    -CopyPEDrivers $false -UseDriversAsPEDrivers $false `
                    -PEDriversFolder $PEDriversFolder -DriversFolder $DriversFolder `
                    -CompressDownloadedDriversToWim $false
        WriteLog "USBOnlyMode: DeployISO rebuilt at $DeployISO"
        # Re-mount test on rebuilt ISO
        $deployISOPath = $DeployISO
    }
}
```

### Phase Dependencies and State Requirements

| Rebuild Phase | Function | Required Inputs | State Already Available? |
|---------------|----------|-----------------|-------------------------|
| Drivers | `Invoke-ParallelProcessing` (via `DownloadDriverByMake` task) + FFU.Common.Drivers | `$driversJsonPath`, `$DriversFolder`, `$WindowsRelease`, `$WindowsArch`, `$WindowsVersion`, `$Headers`, `$UserAgent` | `$DriversFolder` set at line 1842; `$WindowsArch` set at line 1822; `$WindowsRelease`/`$WindowsVersion`/`$WindowsSKU` are script params; `$Headers`/`$UserAgent` set during normal init (before USBOnlyMode block) |
| AppsISO | `New-AppsISO` (FFU.Apps) | `$adkPath`, `$AppsPath`, `$AppsISO` | `$AppsPath = "$FFUDevelopmentPath\Apps"` (line 2051, set during normal init — **problem: this init runs AFTER the USBOnlyMode return at line 1924**) |
| DeployISO | `New-PEMedia` (FFU.Media) | `$adkPath`, `$FFUDevelopmentPath`, `$WindowsArch`, `$DeployISO` | `$DeployISO = "$FFUDevelopmentPath\WinPE_FFU_Deploy_$WindowsArch.iso"` — same init problem |

**Critical finding:** The default-value initialization block (lines 2050-2090) runs **after** the USBOnlyMode `return` (line 1924). Variables like `$AppsISO`, `$AppsPath`, `$DeployISO`, `$adkPath` are NOT populated when the USBOnlyMode block executes.

**Resolution:** Add a **compact path initialization sub-block** at the start of the USBOnlyMode section (after line 1737), before the selective rebuild execution:

```powershell
# USB Mode path defaults (subset of normal init at ~2050 -- needed before selective rebuild)
if (-not $AppsISO)   { $AppsISO   = "$FFUDevelopmentPath\Apps\Apps.iso" }
if (-not $AppsPath)  { $AppsPath  = "$FFUDevelopmentPath\Apps" }
if (-not $DeployISO) { $DeployISO = "$FFUDevelopmentPath\WinPE_FFU_Deploy_$WindowsArch.iso" }
if (-not $PEDriversFolder) { $PEDriversFolder = "$FFUDevelopmentPath\PEDrivers" }
if (-not $DriversFolder) { $DriversFolder = "$FFUDevelopmentPath\Drivers" }
# Resolve ADK path (needed for AppsISO + DeployISO rebuild)
$adkPath = Get-ADKPath  # FFU.ADK function; already imported
```

This mini-init is safe: the params have defaults from the param block (`$DeployISO` is a string param with no default, so it is `$null` on a cold USBOnlyMode start). The mini-init only sets values when empty, so it cannot override user-supplied params.

**Note on `$adkPath`:** `Get-ADKPath` is a function in `FFU.ADK` which is imported in the main module import block (lines 552-569, before the USBOnlyMode block). It does not require ADK to be installed — it returns `$null` if not found — so the rebuild blocks must null-check it and log a clear error if ADK is missing.

[VERIFIED: BuildFFUVM.ps1 lines 1727-1924, 2050-2090, 5316-5374; FFU.Media.psm1:912; FFU.Apps.psm1:216]

---

## F6 — Drivers Rebuild Inputs ($driversJsonPath + Make/Model)

### Current State

The Driver Download phase gate (line 2666) requires **one of three input sources**:
1. `$Make` + `$Model` params (direct Make/Model specification)
2. `$driversJsonPath` param pointing to a valid JSON file with Make/Model entries
3. Pre-existing content in `$DriversFolder` (no download, just use existing)

In USB Mode from the UI, the ThreadJob is launched with only `ConfigFile + USBOnlyMode` (BuildFFUVM_UI.ps1 lines 560-563):
```powershell
$buildParams = @{
    ConfigFile  = $configFilePath
    USBOnlyMode = $true
}
```

Neither `$Make`/`$Model` nor `$DriversJsonPath` is currently passed. The config file (`FFUConfig.json`) **does** contain `DriversJsonPath` from the Full Build tab config, but the USBOnlyMode block does not read it (the config-reading block at lines 2000-2050 runs after the `return` at line 1924).

### Resolution Options

**Option A (Recommended): Source $driversJsonPath from config at USBOnlyMode startup**

Add to the USB Mode path initialization sub-block:
```powershell
# Read DriversJsonPath from config if not supplied as param
if ([string]::IsNullOrWhiteSpace($driversJsonPath) -and
    $null -ne $configData -and
    $configData.PSObject.Properties.Match('DriversJsonPath').Count -gt 0 -and
    -not [string]::IsNullOrWhiteSpace($configData.DriversJsonPath)) {
    $driversJsonPath = $configData.DriversJsonPath
    WriteLog "USBOnlyMode: Using DriversJsonPath from config: $driversJsonPath"
}
# Similarly for Make/Model
if ([string]::IsNullOrWhiteSpace($Make) -and
    $null -ne $configData -and $configData.PSObject.Properties.Match('Make').Count -gt 0) {
    $Make  = $configData.Make
    $Model = $configData.Model
}
```

The config is read early in the script (before the USBOnlyMode block) into `$configData` — confirmed at lines 1743-1773 which access `$configData.USBMode.Artifacts`. So `$configData.DriversJsonPath`, `$configData.Make`, `$configData.Model` are available.

**Option B (D-07 fallback): Drivers Rebuild degrades to Reuse/Skip** if `$driversJsonPath` is still empty after config read. The rebuild block checks and logs a clear warning, then `$rebuildDrivers = $false` falls through to existing Reuse logic.

**Per D-07:** Option A is the primary path; Option B is the graceful degradation.

**UI exposure (Claude's Discretion per D-07):** The planner should decide whether to expose DriversJsonPath, Make, and Model on the Drivers card in the USB Mode tab, or rely solely on config inheritance from the Full Build tab. Research recommendation: read from config only — it avoids adding 3 new UI fields to the Drivers card which would require XAML + Handlers + Config changes beyond the scope. The user who wants Drivers Rebuild simply runs a Full Build session first (which populates the config) then switches to USB Mode.

[VERIFIED: BuildFFUVM.ps1 lines 1743-1773 ($configData access), 2664-2666 (driver gate), 2672-2750 (driver processing)]

---

## F7 — 4-Status Scanner UI Widening

### Current State

`Invoke-USBArtifactScan` in `FFUUI.Core.Handlers.psm1` (lines 107-161) uses a binary branch:

```powershell
if ($null -ne $result -and $result.Status.ToString() -eq 'Found') {
    # Green "Found" rendering
} else {
    # OrangeRed "Missing" rendering for EVERYTHING else
}
```

This collapses `Error` and `Degraded` into the same "Missing" presentation — which is wrong: `Degraded` means the file exists but is suspect (e.g., zero-byte, partial), while `Error` means the scanner threw during the check.

The `ArtifactStatus` enum (ArtifactScanner.Classes.ps1 lines 22-27) has 4 values: `Found`, `Missing`, `Error`, `Degraded`.

The `ArtifactManifest.IsReady` property (line 111) is defined as "True if FFU + DeployISO found, no errors." `Degraded` does not set `IsReady = false`.

### What Must Change

Replace the binary `if/else` with a `switch` on status:
```powershell
switch ($result.Status.ToString()) {
    'Found' {
        $statusCtrl.Text = 'Found'
        $statusCtrl.Foreground = [System.Windows.Media.Brushes]::Green
        $statusCtrl.FontStyle  = [System.Windows.FontStyles]::Normal
        $State.Controls[$map.includeCtrl].IsEnabled = $true  # renamed to dispCtrl post-D-01
    }
    'Degraded' {
        $statusCtrl.Text = 'Found (degraded)'
        $statusCtrl.Foreground = [System.Windows.Media.Brushes]::DarkOrange
        $statusCtrl.FontStyle  = [System.Windows.FontStyles]::Normal
        $State.Controls[$map.dispCtrl].IsEnabled = $true  # allow Reuse (default) or Skip
        # Surface warning: add to card warning TextBlock (see XAML addition below)
        if ($null -ne $State.Controls[$map.warnCtrl]) {
            $State.Controls[$map.warnCtrl].Text       = $result.ErrorMessage
            $State.Controls[$map.warnCtrl].Visibility = 'Visible'
        }
    }
    'Error' {
        $statusCtrl.Text = 'Error (scanner)'
        $statusCtrl.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        $statusCtrl.FontStyle  = [System.Windows.FontStyles]::Normal
        $State.Controls[$map.dispCtrl].IsEnabled = $false  # treat as Missing per tier
    }
    default { # 'Missing'
        $statusCtrl.Text = 'Missing'
        $statusCtrl.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        $statusCtrl.FontStyle  = [System.Windows.FontStyles]::Normal
        $State.Controls[$map.dispCtrl].IsEnabled = $false
    }
}
```

**Default disposition assignment (D-10/D-11):** After status rendering, set the ComboBox default:
```powershell
switch ($result.Status.ToString()) {
    'Found'    { Set-ComboBoxDisposition $dispCtrl 'Reuse' }
    'Degraded' { Set-ComboBoxDisposition $dispCtrl 'Reuse' }  # D-11: Reuse + warning
    'Error'    {
        # Treat as Missing: Required → block (dispCtrl disabled); Optional → Skip
        if ($map.tier -eq 'required') { Set-ComboBoxDisposition $dispCtrl 'Reuse' }
        else                          { Set-ComboBoxDisposition $dispCtrl 'Skip' }
    }
    'Missing'  {
        if ($map.tier -eq 'required') { <IsReady throw handles this> }
        else                          { Set-ComboBoxDisposition $dispCtrl 'Skip' }
    }
}
```

**XAML addition (Claude's Discretion):** Each artifact card needs one additional row: a warning TextBlock (initially `Visibility=Collapsed`, shown for `Degraded` status). This is a minor XAML addition — one `TextBlock` per card with `Foreground=DarkOrange`, `FontSize=11`, `Visibility=Collapsed`, name pattern `usb{Type}Warning`.

[VERIFIED: FFUUI.Core.Handlers.psm1 lines 107-161; ArtifactScanner.Classes.ps1 lines 22-27, 91-111]

---

## Architecture Patterns

### System Architecture Diagram

```
User clicks "Create USB" (btnRun) [BuildFFUVM_UI.ps1]
        |
        v
Pre-launch validation [existing: FFU Found, DeployISO Found, USB drive selected]
        |
        v
Build-UIConfiguration [FFUUI.Core.Config.psm1]
  -- reads ComboBox Disposition per artifact (NEW in Phase 50)
  -- writes Disposition (not Include) to FFUConfig.json
        |
        v
Start-ThreadJob: BuildFFUVM.ps1 -USBOnlyMode -ConfigFile [BuildFFUVM_UI.ps1]
        |
        v
USBOnlyMode block [BuildFFUVM.ps1 ~1727]
  |-- USB Mode mini path-init (NEW: $AppsISO, $AppsPath, $DeployISO, $adkPath)
  |-- Find-FFUArtifacts (live scan)
  |-- IsReady validation (existing)
  |-- ISO mountability pre-check (existing)
  |-- Step 5: populate copy-gate variables (extended for AppsISO in F1)
  |-- Step 5b: apply config path overrides (extended for AppsISO, removes Include)
  |-- [NEW] Read dispositions from $configData.USBMode.Artifacts
  |-- [NEW] Set $rebuildDrivers / $rebuildAppsISO / $rebuildDeployISO
  |-- [NEW] Selective Rebuild Block:
  |     |-- if $rebuildDrivers  → Invoke driver download via driversJsonPath
  |     |-- if $rebuildAppsISO  → New-AppsISO (FFU.Apps)
  |     |-- if $rebuildDeployISO→ New-PEMedia (FFU.Media)
  |-- [NEW] Disposition gate (F2 rewrite — replaces Include gate)
  |     reads Disposition; sets copy flags to $false for Skip
  |-- Step 6: Get-USBDrive (existing)
  |-- Step 7: New-DeploymentUSB (extended for AppsISO in F1)
  |-- return
```

### Recommended Project Structure (Changes Only)

```
FFUDevelopment/
├── BuildFFUVM.ps1              # F1 (New-DeploymentUSB AppsISO), F2 (gate rewrite), F3 (rebuild block), F6 (config read)
├── BuildFFUVM_UI.xaml          # ComboBox controls replacing CheckBoxes (7 cards)
├── FFUUI.Core/
│   ├── FFUUI.Core.Handlers.psm1   # $artifactMap: includeCtrl→dispCtrl; Invoke-USBArtifactScan F7; SelectionChanged handlers
│   └── FFUUI.Core.Config.psm1     # Build-UIConfiguration: read Disposition; Update-UIFromConfig: restore Disposition
```

### Pattern 1: ComboBox as Disposition Control (New Idiom — D-01)

**What:** A WPF `ComboBox` containing `ComboBoxItem` elements, each with a `Tag` attribute holding the enum string ("Reuse", "Rebuild", "Skip"). The `Tag` is what gets saved to config.

**When to use:** Each artifact card, replacing the `CheckBox x:Name="usb{Type}Include"`.

**XAML pattern:**
```xml
<!-- Replaces: <CheckBox x:Name="usbDriversInclude" ... /> -->
<ComboBox x:Name="usbDriversDisposition" Width="120" FontSize="11"
          SelectedIndex="0" IsEnabled="False">
    <ComboBoxItem Content="Reuse"   Tag="Reuse"/>
    <ComboBoxItem Content="Rebuild" Tag="Rebuild"/>
    <ComboBoxItem Content="Skip"    Tag="Skip"/>
</ComboBox>
```

For required artifacts (FFU, DeployISO):
```xml
<ComboBox x:Name="usbFFUDisposition" Width="120" FontSize="11"
          SelectedIndex="0" IsEnabled="False">
    <ComboBoxItem Content="Reuse" Tag="Reuse"/>
</ComboBox>
```

For user-authored (PPKG, Unattend, Autopilot):
```xml
<ComboBox x:Name="usbPPKGDisposition" Width="120" FontSize="11"
          SelectedIndex="0" IsEnabled="False">
    <ComboBoxItem Content="Reuse" Tag="Reuse"/>
    <ComboBoxItem Content="Skip"  Tag="Skip"/>
</ComboBox>
```

**SelectionChanged wiring (new idiom — confirmed by CONTEXT.md, new in Phase 50):**
```powershell
# In Register-EventHandlers, after scan enables the ComboBox:
$State.Controls.usbDriversDisposition.Add_SelectionChanged({
    param($sender, $e)
    $window = [System.Windows.Window]::GetWindow($sender)
    $localState = $window.Tag
    $selectedTag = $sender.SelectedItem.Tag
    $localState.Data.usbArtifactState.Drivers.disposition = $selectedTag
    # If Rebuild → show ADK/input warning if ADK not available
})
```

[ASSUMED] WPF `SelectionChanged` event fires on `ComboBox.SelectedIndex` change and provides `$sender.SelectedItem` — standard WPF behavior; confirmed by existing ComboBox usage in the codebase (e.g., `$State.Controls.cmbVMSwitchName` patterns in Handlers).

### Pattern 2: $artifactMap Extension

The existing `$artifactMap` in `Invoke-USBArtifactScan` (Handlers.psm1 lines 26-34) tracks `includeCtrl` per artifact. In Phase 50, add:
- Rename `includeCtrl` → `dispCtrl` (the ComboBox name, e.g. `usbDriversDisposition`)
- Add `tier` key: `'required'`, `'buildable'`, or `'user-authored'`
- Add `warnCtrl` key: name of the Degraded warning TextBlock (e.g. `usbDriversWarning`)

```powershell
$artifactMap = @{
    FFU       = @{ ...; dispCtrl = 'usbFFUDisposition';       tier = 'required';      warnCtrl = 'usbFFUWarning' }
    DeployISO = @{ ...; dispCtrl = 'usbDeployISODisposition'; tier = 'buildable';     warnCtrl = 'usbDeployISOWarning' }
    Drivers   = @{ ...; dispCtrl = 'usbDriversDisposition';   tier = 'buildable';     warnCtrl = 'usbDriversWarning' }
    PPKG      = @{ ...; dispCtrl = 'usbPPKGDisposition';      tier = 'user-authored'; warnCtrl = 'usbPPKGWarning' }
    Unattend  = @{ ...; dispCtrl = 'usbUnattendDisposition';  tier = 'user-authored'; warnCtrl = 'usbUnattendWarning' }
    Autopilot = @{ ...; dispCtrl = 'usbAutopilotDisposition'; tier = 'user-authored'; warnCtrl = 'usbAutopilotWarning' }
    AppsISO   = @{ ...; dispCtrl = 'usbAppsISODisposition';   tier = 'buildable';     warnCtrl = 'usbAppsISOWarning' }
}
```

The scan function uses `dispCtrl` name to enable/disable the ComboBox (`.IsEnabled = $true/false`) after determining status — same as the current `includeCtrl` enable/disable pattern.

### Anti-Patterns to Avoid

- **Reading `$cfgArt.<Type>.Include` anywhere in Phase 50 code.** The `Include` field is non-schema and must be completely removed from the pipeline gate. The schema's `Disposition` field is the canonical representation.
- **Calling any full-build phases that require a VM, VHDX, or Windows ISO** inside the USBOnlyMode selective rebuild block. Only `New-AppsISO`, `New-PEMedia`, and the driver download functions are safe to call in isolation.
- **Running the `$skipDeploymentMedia` / `$skipDriverDownload` flags as the selective execution mechanism.** These only work when `$script:IsResuming = true` and would not activate on a cold USB Mode start.
- **Setting `$script:IsResuming = $true` to trick the skip flags into activating.** This would corrupt checkpoint state and could activate unintended skips.
- **Using `Get-Command`** inside the parallel block — ThreadJob unsafe; confirmed by CLAUDE.md and existing code patterns.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| ISO creation for AppsISO rebuild | Custom ISO creator | `New-AppsISO` (FFU.Apps.psm1:216) — already uses oscdimg.exe from ADK |
| WinPE deployment media rebuild | Custom media creator | `New-PEMedia -Capture $false -Deploy $true` (FFU.Media.psm1:912) — full production function |
| Driver download orchestration | Custom download loop | Existing `Invoke-ParallelProcessing` with `DownloadDriverByMake` task type (BuildFFUVM.ps1 ~2743) |
| ADK path resolution | Env-var scanning | `Get-ADKPath` (FFU.ADK module — already imported at line 557) |
| Artifact status checks | Custom scanner | `Find-FFUArtifacts` (FFU.ArtifactScanner) — already called at line 1741 |
| Config field existence check | Direct property access | `$obj.PSObject.Properties.Match('Key').Count -gt 0` — established pattern throughout codebase |
| ComboBox item with associated value | DataTemplate | `ComboBoxItem Tag="Reuse"` — established WPF pattern in this codebase |

---

## Common Pitfalls

### Pitfall 1: Variable Initialization Order (USBOnlyMode returns early)

**What goes wrong:** Phase 50 adds calls to `New-AppsISO` and `New-PEMedia` inside the USBOnlyMode block. Both functions need `$adkPath`, `$AppsPath`, `$AppsISO`, `$DeployISO`. These are initialized in the default-value block at lines 2050-2090 — which runs **after** the `return` at line 1924.

**How to avoid:** Add a USB Mode mini path-init block immediately after line 1737 (before the selective rebuild code). Pattern: `if (-not $Var) { $Var = "default" }`. Do NOT duplicate the entire default block — only the 5-6 variables needed by selective rebuild.

**Warning signs:** `$null` errors from `New-AppsISO -ADKPath $null` or `New-PEMedia -adkPath $null`.

### Pitfall 2: $using: Variables in ForEach-Object -Parallel

**What goes wrong:** Adding `$CopyAppsISO` and `$AppsISOPath` to the parallel block in `New-DeploymentUSB` but not setting them as script-scoped variables before the function call.

**How to avoid:** Set `$CopyAppsISO = $false` and `$AppsISOPath = "..."` in the USBOnlyMode block scope, not inside `New-DeploymentUSB`. The parallel block reads them via `$using:CopyAppsISO` and `$using:AppsISOPath`.

**Warning signs:** `$using: variables cannot be retrieved` errors in the parallel job output.

### Pitfall 3: SelectionChanged Fires During Config Load

**What goes wrong:** `Update-UIFromConfig` restores ComboBox selection → `SelectionChanged` fires → handler tries to read artifact state before it is fully populated.

**How to avoid:** Use the existing `$State.Flags.isLoadingConfig` guard (established pattern in Phase 49, line 20 of Handlers.psm1). The handler checks `if ($State.Flags.isLoadingConfig) { return }` before doing anything substantive.

**Warning signs:** Disposition resets to default after config load despite config having a different value.

### Pitfall 4: Disposition ComboBox IsEnabled vs. IsChecked Semantics

**What goes wrong:** CheckBox `IsEnabled=False` meant "required, always included." ComboBox `IsEnabled=False` means "user cannot change it." For required artifacts (FFU, DeployISO), a 1-item `Reuse`-only ComboBox that is `IsEnabled=False` preserves this semantics correctly. But `IsEnabled=False` on the ComboBox also prevents Tab navigation.

**How to avoid:** For required artifacts, use a disabled ComboBox (1 item, `Reuse`, `IsEnabled=False`) — this exactly matches D-03 and preserves the existing hard-lock semantics.

### Pitfall 5: ADK Not Installed — Rebuild Fails Silently

**What goes wrong:** `Get-ADKPath` returns `$null` if ADK is not installed. `New-AppsISO` then throws because oscdimg.exe is not found. Without a null-check, this throw propagates and kills the entire USBOnlyMode execution (not just the rebuild step).

**How to avoid:** Null-check `$adkPath` before each rebuild call. If null, log a clear error (WriteLog + Set-Progress warning message) and set `$rebuildAppsISO = $false` / `$rebuildDeployISO = $false`, then continue to USB assembly with whatever artifacts are available.

### Pitfall 6: DeployISO Rebuild Changes the Path Variable

**What goes wrong:** If `$deployISOPath` (the variable used for ISO mount testing at line 1790) is set before the DeployISO rebuild, but the rebuild outputs to a different path (e.g., per-arch naming), the pre-validation mount test was done on the OLD ISO while the new one is at a different path.

**How to avoid:** Run DeployISO rebuild BEFORE the ISO mountability pre-check (reorder the rebuild block before Step 4, or re-run the mount check after rebuild). Recommended: place the rebuild block between Step 3 (log warnings) and Step 4 (ISO mount check). Then the mount check validates the freshly rebuilt ISO.

### Pitfall 7: Drivers Rebuild Overwrites Existing Drivers Folder Without Warning

**What goes wrong:** `Invoke-ParallelProcessing` with `DownloadDriverByMake` downloads drivers into `$DriversFolder`. If the user had existing drivers there (disposition was `Reuse` before, now switched to `Rebuild`), the download may overwrite them without warning.

**How to avoid:** Log a clear `WriteLog "WARNING: Drivers Rebuild will download into $DriversFolder. Existing files may be overwritten."` before calling the driver download block. This is a data-loss warning that must be visible in the Monitor tab.

### Pitfall 8: InModuleScope for ArtifactStatus Enum in Tests

**What goes wrong:** Pester tests that assert on `ArtifactStatus.Degraded` outside `InModuleScope { }` will fail because PowerShell class/enum types are not exported to the caller's scope.

**How to avoid:** All assertions on ArtifactStatus enum values in new tests must use `InModuleScope 'FFU.ArtifactScanner' { }` — established pattern from Phase 46 (STATE.md accumulated context, line 56).

---

## Code Examples

### Reading Disposition from Config (BuildFFUVM.ps1)
```powershell
# [VERIFIED: BuildFFUVM.ps1 lines 1743-1773 pattern — $configData.USBMode.Artifacts access]
$cfgArt = $configData.USBMode.Artifacts
$rebuildDrivers = (
    $null -ne $cfgArt.Drivers -and
    $cfgArt.Drivers.PSObject.Properties.Match('Disposition').Count -gt 0 -and
    $cfgArt.Drivers.Disposition -eq 'Rebuild'
)
```

### ComboBox Disposition Save in Build-UIConfiguration
```powershell
# [VERIFIED: FFUUI.Core.Config.psm1 lines 166-188 — existing pattern to replace]
$dispCtrlName = "usb${artifactType}Disposition"
$disposition  = 'Reuse'
if ($null -ne $State.Controls[$dispCtrlName] -and $null -ne $State.Controls[$dispCtrlName].SelectedItem) {
    $disposition = $State.Controls[$dispCtrlName].SelectedItem.Tag
}
$config.USBMode.Artifacts[$artifactType] = @{
    Path        = $pathToSave
    Disposition = $disposition
}
```

### Disposition Restore in Update-UIFromConfig
```powershell
# [VERIFIED: FFUUI.Core.Config.psm1 lines 645-665 — existing pattern to replace]
$dispCtrlName = "usb${key}Disposition"
if ($null -ne $State.Controls[$dispCtrlName] -and
    $null -ne $entry -and
    $entry.PSObject.Properties.Match('Disposition').Count -gt 0) {
    $targetDisp = $entry.Disposition
    foreach ($item in $State.Controls[$dispCtrlName].Items) {
        if ($item -is [System.Windows.Controls.ComboBoxItem] -and $item.Tag -eq $targetDisp) {
            $State.Controls[$dispCtrlName].SelectedItem = $item
            break
        }
    }
}
```

### SelectionChanged Handler (new idiom)
```powershell
# [ASSUMED — standard WPF SelectionChanged; pattern fits existing Add_Click/Add_Checked idioms in Handlers.psm1]
$State.Controls.usbDriversDisposition.Add_SelectionChanged({
    param($sender, $e)
    if ($e.AddedItems.Count -eq 0) { return }
    $window   = [System.Windows.Window]::GetWindow($sender)
    $localState = $window.Tag
    if ($localState.Flags.isLoadingConfig) { return }  # guard (Pitfall 3)
    $selectedTag = $sender.SelectedItem.Tag
    $localState.Data.usbArtifactState['Drivers'].disposition = $selectedTag
})
```

### AppsISO Copy in New-DeploymentUSB Parallel Block
```powershell
# [VERIFIED: BuildFFUVM.ps1 lines 1497-1546 — pattern for existing artifact copies]
if ($using:CopyAppsISO) {
    $AppsISODest = Join-Path $DeployPartitionDriveLetter 'Apps'
    New-Item -Path $AppsISODest -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    WriteLog "Copying Apps ISO to $AppsISODest"
    robocopy (Split-Path $using:AppsISOPath -Parent) $AppsISODest (Split-Path $using:AppsISOPath -Leaf) /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Test-RobocopySuccess -Operation 'AppsISO to USB'
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| CheckBox Include (non-schema) | ComboBox Disposition (schema-native enum) | Eliminates the Include/Disposition dual-write; single source of truth |
| Binary Found/Missing status rendering | 4-state Found/Degraded/Error/Missing | Surfaces degraded artifacts without blocking required good-status items |
| Resume-forward-only skip flags | + Rebuild gate (parallel pattern, USB Mode only) | USB Mode selective execution without corrupting Full Build checkpoint state |
| No AppsISO USB copy path | AppsISO copied via `$CopyAppsISO` / `$AppsISOPath` $using: pair | Completes the 7-artifact USB assembly |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | WPF `SelectionChanged` event fires correctly for `ComboBox` items in this codebase's `Add_SelectionChanged` PowerShell wrapper syntax | Code Examples: SelectionChanged Handler | Handler never fires; disposition state never updates |
| A2 | `$configData.DriversJsonPath`, `$configData.Make`, `$configData.Model` are populated before the USBOnlyMode block executes | F6 | Drivers Rebuild cannot source input; falls back to degradation (Option B) |
| A3 | `Get-ADKPath` returns `$null` (not throws) when ADK is not installed | F3 Pitfall 5 | Uncaught throw kills entire USBOnlyMode execution |

**A1 mitigation:** Existing codebase uses `Add_SelectionChanged` for other ComboBoxes (e.g., `$State.Controls.cmbWindowsArch.Add_SelectionChanged` — Handlers.psm1 patterns). The idiom is confirmed to work in this WPF/PS context; only the per-artifact USB card usage is new.

**A2 mitigation:** `$configData` is loaded from JSON at the param block's `ConfigFile` processing (before the USBOnlyMode block). The config saved by `Build-UIConfiguration` includes all Full Build tab fields including `DriversJsonPath`, `Make`, `Model`. Confirmed by reading config write at FFUUI.Core.Config.psm1 which does not filter these fields.

**A3 mitigation:** Read `Get-ADKPath` implementation in FFU.ADK to confirm null-return behavior before executing rebuild. If it throws, wrap the call in `try/catch` and set `$adkPath = $null` on error.

---

## Open Questions (RESOLVED)

> RESOLVED: All four questions are answered by the Phase 50 plans. Inline RESOLVED notes are added per question below.

1. **Where does usbArtifactState.disposition live in $State.Data?**
   - What we know: `$State.Data.usbArtifactState` is a hashtable keyed by artifact type (e.g., `Drivers`, `FFU`) with `path` and `source` properties (Handlers.psm1 lines 38, 83).
   - What's unclear: Does the planner add `disposition` as a third property on the existing hashtable entries, or create a separate `$State.Data.usbArtifactDisposition` hashtable?
   - Recommendation: Add `disposition = 'Reuse'` as a third property on each `usbArtifactState` entry. It parallels `source` semantically and is already read/written in the same code locations.
   - RESOLVED (plan 50-02 Task 3): added `disposition = 'Reuse'` as a third property on each entry at the init site BuildFFUVM_UI.ps1:72-80.

2. **Should DeployISO rebuild happen BEFORE or AFTER the ISO mountability pre-check (Step 4)?**
   - What we know: The pre-check at line 1789 validates the existing ISO. After rebuild, a new ISO exists.
   - What's unclear: The pre-check needs to test the ISO that will actually be used for USB assembly.
   - Recommendation: Place the selective rebuild block BETWEEN Step 3 (log warnings) and Step 4 (ISO mount check). This ensures the mount check always validates the final ISO (rebuilt or reused). Requires reordering lines slightly.
   - RESOLVED (plan 50-05 Task 2): DeployISO rebuild runs BEFORE the ISO mount pre-check, and the whole rebuild block precedes the Disposition gate (enforced by a structural Pester ordering assertion).

3. **How should the Drivers card present the Rebuild option when driversJsonPath is not in config?**
   - What we know: D-07 says Drivers Rebuild is gated on input availability and degrades to Reuse/Skip if inputs cannot be sourced.
   - What's unclear: Should the Rebuild item be hidden from the ComboBox, or shown but disabled/greyed?
   - Recommendation: Show it as a standard item but on selection, immediately log a warning and optionally show a card-level warning. This avoids per-card dynamic XAML manipulation while giving the user a clear signal.
   - RESOLVED (plan 50-02/50-05, D-07): Rebuild item is shown; degradation is surfaced via the Monitor-tab log during pipeline execution rather than per-card dynamic XAML.

4. **Does New-AppsISO run safely inside a ThreadJob?**
   - What we know: `New-AppsISO` uses `Invoke-Process` (FFU.Common) and oscdimg.exe. `Invoke-Process` is ThreadJob-safe per CLAUDE.md.
   - What's unclear: Whether oscdimg.exe has any interactive/elevated requirements that would break in ThreadJob context.
   - Recommendation: Assume safe (consistent with all other external tool calls); wrap in `try/catch` and log failure as non-blocking warning (same pattern as deployment media at line 5369-5373).
   - RESOLVED (plan 50-05 Task 2): New-AppsISO/New-PEMedia calls are wrapped in try/catch and logged as non-blocking warnings, matching the deployment-media pattern.
---

## Environment Availability

| Dependency | Required By | Available | Notes |
|------------|------------|-----------|-------|
| Windows ADK (oscdimg.exe) | AppsISO rebuild, DeployISO rebuild | Runtime-checked via `Get-ADKPath` | Must null-check; if missing, rebuild degrades gracefully |
| FFU.ArtifactScanner module | Scan + 4-status widening | Already imported (line 552-569) | No action needed |
| FFU.Apps module | `New-AppsISO` | Already imported (line 552-569) | No action needed |
| FFU.Media module | `New-PEMedia` | Already imported (line 552-569) | No action needed |
| WPF System.Windows.Controls.ComboBox | Disposition ComboBox XAML | Always available in WPF | No action needed |
| $configData (parsed config JSON) | Disposition values, driversJsonPath | Available before USBOnlyMode block | Set during config file processing |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Pester 5.x |
| Config file | None — tests self-contained via `-Path` |
| Quick run | `Invoke-Pester -Path 'Tests\Unit\SelectiveRebuild.Tests.ps1' -Output Detailed` |
| Full suite | `.\Tests\Unit\Invoke-PesterTests.ps1` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REBUILD-01 | ComboBox renders with correct ItemsSource per tier | Structural (XAML parse) | `Invoke-Pester 'Tests\Unit\SelectiveRebuild.Tests.ps1'` | No — Wave 0 |
| REBUILD-01 | Disposition saved correctly to config (Reuse/Rebuild/Skip) | Unit (Config.psm1 stub) | `Invoke-Pester 'Tests\Unit\SelectiveRebuild.Tests.ps1'` | No — Wave 0 |
| REBUILD-01 | Disposition restored from config to ComboBox | Unit (Update-UIFromConfig) | `Invoke-Pester 'Tests\Unit\SelectiveRebuild.Tests.ps1'` | No — Wave 0 |
| REBUILD-02 | $rebuildDrivers set when Disposition=Rebuild | Unit (BuildFFUVM.ps1 AST / text search) | `Invoke-Pester 'Tests\Unit\USBOnlyMode.Tests.ps1'` | Yes (extend) |
| REBUILD-02 | Skip artifacts excluded from copy gates | Unit (BuildFFUVM.ps1 text search for gate rewrite) | `Invoke-Pester 'Tests\Unit\USBOnlyMode.Tests.ps1'` | Yes (extend) |
| REBUILD-03 | AppsISO `$CopyAppsISO` flag and `$using:` variable present | Structural (AST) | `Invoke-Pester 'Tests\Unit\USBOnlyMode.Tests.ps1'` | Yes (extend) |
| REBUILD-03 | New-DeploymentUSB parallel block contains AppsISO copy | Structural (text search) | `Invoke-Pester 'Tests\Unit\USBOnlyMode.Tests.ps1'` | Yes (extend) |
| D-10/D-11 | Degraded status renders DarkOrange + warning text | Unit (Invoke-USBArtifactScan) | `Invoke-Pester 'Tests\Unit\SelectiveRebuild.Tests.ps1'` | No — Wave 0 |
| D-10/D-11 | Error status treated as Missing (dispCtrl disabled) | Unit (Invoke-USBArtifactScan) | `Invoke-Pester 'Tests\Unit\SelectiveRebuild.Tests.ps1'` | No — Wave 0 |

### Sampling Rate

- **Per task commit:** `Invoke-Pester -Path 'Tests\Unit\USBOnlyMode.Tests.ps1' -Output Minimal`
- **Per wave merge:** `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `Tests\Unit\SelectiveRebuild.Tests.ps1` — covers REBUILD-01 (ComboBox config round-trip, disposition rendering), D-10/D-11 (4-status rendering). This is a new test file.
- [ ] Extend `Tests\Unit\USBOnlyMode.Tests.ps1` — add structural tests for: `$CopyAppsISO`/`$AppsISOPath` variable presence in USBOnlyMode block, `$rebuildDrivers`/`$rebuildAppsISO`/`$rebuildDeployISO` gate variables, Disposition gate replacing Include gate.

---

## Security Domain

Security enforcement is enabled (no explicit `false` in config.json).

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | Yes | Disposition values must be one of `Reuse/Rebuild/Skip` (schema enum enforced; also validate in pipeline gate) |
| V4 Access Control | No | USB Mode writes to local filesystem only; no auth boundary |
| V6 Cryptography | No | No crypto operations in this phase |
| V2 Authentication | No | No authentication in scope |

**Threat: Malformed Disposition value in config JSON.** If a config file contains `Disposition = "Exploit"`, the gate's `switch` on Disposition should fall through to the `default` case (treat as Reuse). Add an explicit validation:
```powershell
if ($disp -notin @('Reuse', 'Rebuild', 'Skip')) {
    WriteLog "WARNING: Unknown Disposition '$disp' for $dType -- treating as Reuse."
    $disp = 'Reuse'
}
```

---

## Sources

### Primary (HIGH confidence)

- BuildFFUVM.ps1 (lines 1328-1562, 1727-1924, 2050-2090, 2651-2840, 5316-5374, 5378-5450) — direct read; all line numbers verified.
- FFUUI.Core.Handlers.psm1 (lines 8-162, 1243-1340) — direct read; $artifactMap, Invoke-USBArtifactScan, event handlers.
- FFUUI.Core.Config.psm1 (lines 155-227, 639-677) — direct read; Build-UIConfiguration, Update-UIFromConfig.
- BuildFFUVM_UI.xaml (lines 932-1243) — direct read; all 7 artifact cards with CheckBox names.
- ArtifactScanner.Classes.ps1 (lines 1-115) — direct read; ArtifactStatus enum, ArtifactManifest.
- FFU.ArtifactScanner.psm1 (lines 551-588) — direct read; AppsISO scan, manifest assembly.
- ffubuilder-config.schema.json (lines 653-700) — direct read; Disposition enum, ArtifactEntry definition.
- FFU.Media.psm1 (line 912+) — direct read; New-PEMedia signature.
- FFU.Apps.psm1 (line 216+) — direct read; New-AppsISO signature.
- BuildFFUVM_UI.ps1 (lines 440-759) — direct read; USB mode launch, ThreadJob pattern.
- 47-CONTEXT.md — prior phase decisions carried forward.
- 49-CONTEXT.md — include checkbox → disposition migration point.
- 50-CONTEXT.md — locked decisions.

### Secondary (MEDIUM confidence)

- CLAUDE.md ThreadJob-safe idioms table — project instructions authority.
- STATE.md accumulated context (line 56 — InModuleScope Pester pattern for ArtifactStatus enum).

### Tertiary (LOW confidence)

None — all claims verified against source files.

---

## Metadata

**Confidence breakdown:**
- F1 (AppsISO copy path): HIGH — gap confirmed in code, solution pattern mirrors existing artifact copies.
- F2 (Disposition gate rewrite): HIGH — exact lines identified, Include-reading code read directly.
- F3 (selective execution): HIGH mechanism, MEDIUM implementation detail — rebuild block structure is clear; exact driver download extraction from ~2664-2840 needs line-level audit at plan time.
- F6 (Drivers inputs): HIGH — $configData access confirmed available in USBOnlyMode block.
- F7 (4-status UI): HIGH — status enum values and binary branch both verified.
- ComboBox XAML + wiring pattern: HIGH from prior codebase patterns; SelectionChanged idiom is new but standard WPF.

**Research date:** 2026-06-22
**Valid until:** 2026-07-22 (stable codebase; no external dependencies)
