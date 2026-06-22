---
phase: 50-selective-rebuild-pipeline
reviewed: 2026-06-22T00:00:00Z
depth: deep
files_reviewed: 5
files_reviewed_list:
  - FFUDevelopment/BuildFFUVM.ps1
  - FFUDevelopment/BuildFFUVM_UI.ps1
  - FFUDevelopment/BuildFFUVM_UI.xaml
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1
findings:
  critical: 3
  warning: 4
  info: 2
  total: 9
status: fixed
---

# Phase 50: Code Review Report

**Reviewed:** 2026-06-22
**Depth:** deep (cross-file, call-chain trace)
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 50 adds a selective rebuild pipeline to USB Mode: per-artifact Disposition ComboBoxes (Reuse / Rebuild / Skip) replace the old Include checkboxes, backed by a rebuild execution block in `BuildFFUVM.ps1` and a Disposition config round-trip in `FFUUI.Core.Config.psm1`. The UI tier logic (XAML + Handlers) is structurally sound. The config save/restore round-trip is correct.

The critical defects are all in `BuildFFUVM.ps1`. Two of them share the same root cause: the rebuild reconciliation variables (`$CopyDrivers`, `$CopyAppsISO`, `$AppsISOPath`) that are written inside the new selective rebuild execution block (lines ~1879-1990) are unconditionally overwritten by the pre-existing Step 5 initialisation block (lines ~2032-2060), which runs after the rebuild block. The rebuilt artifacts therefore never reach the USB drive when they are needed most — when the original artifact was absent from the manifest scan.

A third critical issue is that `Invoke-ParallelProcessing` result errors are not inspected, so a total driver download failure silently sets `$CopyDrivers = $true` and proceeds to copy an empty folder.

---

## Critical Issues

### CR-01: Rebuilt `$CopyAppsISO` and `$AppsISOPath` unconditionally clobbered by Step 5 init

**File:** `FFUDevelopment/BuildFFUVM.ps1:1953-1954 vs 2052-2053`

**Issue:**
The rebuild block (lines 1941-1962) sets `$CopyAppsISO = $true` and `$AppsISOPath = $AppsISO` to record that a new ISO was just built. These reconciliation variables are the mechanism by which the rebuilt artifact flows into `New-DeploymentUSB`. However, Step 5's manifest-based initialisation block unconditionally resets them four pages later:

```powershell
# Line 2052-2053 — unconditional reset
$CopyAppsISO = $false
$AppsISOPath = "$FFUDevelopmentPath\Apps\Apps.iso"
if ($null -ne $manifest.AppsISO -and $manifest.AppsISO.Status.ToString() -eq 'Found') {
    $CopyAppsISO = $true
    ...
}
```

The manifest was scanned *before* the rebuild ran, so `$manifest.AppsISO.Status` reflects the pre-rebuild state. If the user triggered a rebuild because AppsISO was Missing, the manifest still says Missing at line 2054, `$CopyAppsISO` remains `$false`, and the freshly built ISO is never copied. The rebuild completes silently but produces no effect.

**Fix:**
Guard the Step 5 init against an already-reconciled rebuild. The cleanest approach uses the existing `$rebuildAppsISO` flag (which stays `$true` on successful rebuild, `$false` on failure):

```powershell
# Lines 2051-2060 — replacement
if (-not $rebuildAppsISO) {
    # Normal init from manifest; skip if rebuild already reconciled these
    $CopyAppsISO = $false
    $AppsISOPath = "$FFUDevelopmentPath\Apps\Apps.iso"
    if ($null -ne $manifest.AppsISO -and $manifest.AppsISO.Status.ToString() -eq 'Found') {
        $CopyAppsISO = $true
        if (-not [string]::IsNullOrWhiteSpace($manifest.AppsISO.FilePath)) {
            $AppsISOPath = $manifest.AppsISO.FilePath
        }
    }
    if (-not $CopyAppsISO) { WriteLog "WARNING: Skipping AppsISO -- not found at $AppsISOPath" }
}
# else: $CopyAppsISO/$AppsISOPath already set correctly by rebuild block above
```

---

### CR-02: Rebuilt `$CopyDrivers = $true` unconditionally clobbered by Step 5 copy-gates init

**File:** `FFUDevelopment/BuildFFUVM.ps1:1935 vs 2033`

**Issue:**
Same root cause as CR-01. The driver rebuild block (lines 1879-1938) sets `$CopyDrivers = $true` on success. Step 5's manifest-based copy-gate initialisation overwrites it twelve lines before AppsISO:

```powershell
# Line 2033 — unconditional reset
$CopyDrivers = ($manifest.Drivers.Status.ToString() -eq 'Found')
```

The manifest was scanned before the rebuild. If `Drivers` was Missing before the rebuild, `manifest.Drivers.Status` is still 'Missing', so `$CopyDrivers` becomes `$false` and the newly downloaded drivers are not copied to USB. The rebuild silently wasted time downloading drivers it will never use.

**Fix:**
Guard the drivers copy-gate line in Step 5 against a successful rebuild:

```powershell
# Line 2033 — replacement
$CopyDrivers = if ($rebuildDrivers) {
    $true  # rebuild succeeded and reconciled this above; preserve
} else {
    ($manifest.Drivers.Status.ToString() -eq 'Found')
}
```

Alternatively, restructure Step 5 to read all three flags (`$rebuildDrivers`, `$rebuildAppsISO`, `$rebuildDeployISO`) and only call the manifest-based default when the corresponding flag is `$false`.

---

### CR-03: `Invoke-ParallelProcessing` result is never inspected — silent total-download failure sets `$CopyDrivers = $true`

**File:** `FFUDevelopment/BuildFFUVM.ps1:1927-1936`

**Issue:**
The driver rebuild uses `Invoke-ParallelProcessing` and captures its return value in `$parallelResults`, but never examines it:

```powershell
$parallelResults = Invoke-ParallelProcessing -ItemsToProcess $driversToProcess `
    -TaskType 'DownloadDriverByMake' `
    ...
# Reconcile: rebuilt drivers folder is the canonical source
$CopyDrivers = $true                    # set unconditionally
WriteLog "USBOnlyMode: Drivers rebuilt into $DriversFolder"
```

If every single driver download fails (network outage, all URLs stale), `Invoke-ParallelProcessing` still returns (with error items in the result), `$CopyDrivers` is set to `$true`, and the USB assembly proceeds to copy an empty or unchanged `$DriversFolder`. The build log says "Drivers rebuilt" with no indication of the failure.

**Fix:**
Inspect the result before setting `$CopyDrivers`:

```powershell
$parallelResults = Invoke-ParallelProcessing -ItemsToProcess $driversToProcess `
    -TaskType 'DownloadDriverByMake' `
    -TaskArguments $taskArguments `
    -IdentifierProperty 'Model' `
    -WindowObject $null `
    -ListViewControl $null `
    -MainThreadLogPath $LogFile
$successCount = @($parallelResults | Where-Object { $_.Status -eq 'Success' }).Count
$failCount    = $driversToProcess.Count - $successCount
if ($failCount -gt 0) {
    WriteLog "WARNING: $failCount of $($driversToProcess.Count) driver entries failed to download."
}
if ($successCount -gt 0) {
    $CopyDrivers = $true
    WriteLog "USBOnlyMode: $successCount driver entries rebuilt into $DriversFolder"
} else {
    WriteLog "WARNING: All driver downloads failed. Skipping driver copy."
    $rebuildDrivers = $false
}
```

(Adjust the `$_.Status -eq 'Success'` predicate to match the actual field name returned by `Invoke-ParallelProcessing`.)

---

## Warnings

### WR-01: DeployISO `disposition=Rebuild` is non-functional when DeployISO is Missing or Degraded

**File:** `FFUDevelopment/BuildFFUVM.ps1:1784-1789`

**Issue:**
The `IsReady` gate at line 1784 throws if `$manifest.DeployISO.Status != 'Found'`. The `IsReady` flag is computed by `FFU.ArtifactScanner` as `isoFound = (manifest.DeployISO.Status -eq 'Found')` — a Degraded status evaluates to false. This means that when the user selects `disposition=Rebuild` for a Missing or Degraded DeployISO, the process aborts at line 1789 before the rebuild block at line 1964 ever executes. The Rebuild ComboBox option is visually available (enabled by the Degraded scan path) but silently non-functional.

The feature requirement for the `required-buildable` tier (DeployISO can be Rebuilt) collides with the existing IsReady guard that was designed for the non-rebuild path.

**Fix:**
Before the IsReady gate, check whether a DeployISO rebuild is requested and skip the DeployISO-specific part of the gate in that case:

```powershell
# Step 2: Validate readiness
$deployISORebuildRequested = (
    $null -ne $configData?.USBMode?.Artifacts?.DeployISO -and
    $configData.USBMode.Artifacts.DeployISO.Disposition -eq 'Rebuild'
)

if (-not $manifest.IsReady) {
    $missingTypes = @()
    $ffuFound = @($manifest.FFUFiles | Where-Object { $_.Status.ToString() -eq 'Found' })
    if ($ffuFound.Count -eq 0) { $missingTypes += 'FFU file' }
    if (-not $deployISORebuildRequested -and $manifest.DeployISO.Status.ToString() -ne 'Found') {
        $missingTypes += 'WinPE deployment ISO'
    }
    if ($missingTypes.Count -gt 0) {
        throw "USBOnlyMode cannot proceed: missing required artifacts: $($missingTypes -join ', '). ..."
    }
}
```

This is a design-level fix; any approach must be deliberate about when the rebuild option can bypass the guard.

---

### WR-02: Config-restored Disposition not propagated to `usbArtifactState` in-memory

**File:** `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1:666-677`

**Issue:**
`Update-UIFromConfig` restores the saved Disposition by setting `$State.Controls[$dispCtrlName].SelectedItem`, but the `SelectionChanged` handler for these ComboBoxes short-circuits when `isLoadingConfig = $true` (by design, per the Pitfall 3 guard). This means `$State.Data.usbArtifactState[$key].disposition` is never updated during config load — it retains the default `'Reuse'` set at `usbArtifactState` initialisation in `BuildFFUVM_UI.ps1:388-394`.

After load, the in-memory `usbArtifactState[type].disposition` disagrees with the ComboBox's visual state. Any code path that reads `disposition` from `usbArtifactState` (rather than reading the ComboBox control directly) will use the wrong value.

`Get-UIConfig` and `Build-UIConfiguration` both read from the ComboBox control directly (`$State.Controls[$dispCtrlName].SelectedItem.Tag`), so the save path is not currently affected. However, the in-memory `disposition` field exposed on `usbArtifactState` is stale after a config load, which is a latent bug for any future code that relies on it.

**Fix:**
After setting `SelectedItem` in `Update-UIFromConfig`, also write to `usbArtifactState`:

```powershell
$State.Controls[$dispCtrlName].SelectedItem = $item
# Also sync in-memory state (SelectionChanged is suppressed by isLoadingConfig)
if ($null -ne $State.Data.usbArtifactState -and
    $null -ne $State.Data.usbArtifactState[$key]) {
    $State.Data.usbArtifactState[$key].disposition = $targetDisp
}
WriteLog "LoadConfig: Set usb${key}Disposition to '$targetDisp'."
```

---

### WR-03: `$using:AppsISOPath` path used in `ForEach-Object -Parallel` may be a directory path rather than a file path when `$AppsISO` contains just a folder

**File:** `FFUDevelopment/BuildFFUVM.ps1:1553`

**Issue:**
The AppsISO copy block inside the `ForEach-Object -Parallel` uses:

```powershell
robocopy (Split-Path $using:AppsISOPath -Parent) $AppsISODest (Split-Path $using:AppsISOPath -Leaf) /J ...
```

`Split-Path -Parent` on `"C:\FFUDevelopment\Apps\Apps.iso"` returns `"C:\FFUDevelopment\Apps"`. `Split-Path -Leaf` returns `"Apps.iso"`. This is correct when `$AppsISOPath` is a full file path. However, if `$AppsISOPath` is assigned a value that ends with a directory separator or is itself a directory (possible if a malformed config `Path` value passes the `Test-Path` check without being a file), `Split-Path -Parent` will return the grandparent and `Split-Path -Leaf` will return the folder name, causing robocopy to copy the wrong content silently (robocopy exits 0-7 for partial copies).

**Fix:**
Add a `Test-Path -PathType Leaf` guard before setting `$CopyAppsISO = $true` in the path-override block (line 2110-2112), and validate inside the parallel block:

```powershell
# In path-override block (line 2109 context):
if ($null -ne $cfgArt.AppsISO -and
    -not [string]::IsNullOrWhiteSpace($cfgArt.AppsISO.Path) -and
    (Test-Path -LiteralPath $cfgArt.AppsISO.Path -PathType Leaf)) {  # was -not PathType check
    $AppsISOPath = $cfgArt.AppsISO.Path
    $CopyAppsISO = $true
    ...
}
```

---

### WR-04: `driversJsonPath` access inside `ForEach-Object -Parallel` driver-rebuild is not Try/Catch guarded; JSON parse errors abort the USB Mode run

**File:** `FFUDevelopment/BuildFFUVM.ps1:1894`

**Issue:**
The driver rebuild reads and parses the JSON file without error handling:

```powershell
$jsonData = Get-Content -Path $driversJsonPath -Raw | ConvertFrom-Json
```

If the file exists but is malformed JSON, `ConvertFrom-Json` throws a terminating error. Because there is no `try/catch` wrapping this block (the `try` only wraps the entire `if ($rebuildAppsISO)` and `if ($rebuildDeployISO)` blocks, not `if ($rebuildDrivers)`), the error propagates uncaught, terminates USB Mode, and the user sees a cryptic JSON parse error instead of a graceful degradation message.

**Fix:**
Wrap the JSON read in a try/catch consistent with the AppsISO and DeployISO rebuild patterns:

```powershell
try {
    $jsonData = Get-Content -Path $driversJsonPath -Raw | ConvertFrom-Json
}
catch {
    WriteLog "WARNING: Failed to parse DriversJson at $driversJsonPath : $($_.Exception.Message). Degrading to Reuse."
    $rebuildDrivers = $false
    # fall through — $CopyDrivers was set from manifest earlier and remains valid
}
if ($rebuildDrivers) {
    foreach ($makeEntry in $jsonData.PSObject.Properties) { ... }
}
```

---

## Info

### IN-01: `$parallelResults` variable assigned but name is misleading — conveys no information about individual failures

**File:** `FFUDevelopment/BuildFFUVM.ps1:1927`

**Issue:**
The `$parallelResults = Invoke-ParallelProcessing ...` assignment at line 1927 captures the return value but the variable is not used again. This is partly addressed by CR-03. However, the variable name itself is misleading in an advisory sense: nothing in the surrounding code uses the results, giving a false impression that the call is fire-and-forget.

**Fix:** Address via CR-03 (inspect results). If the result inspection is deferred, rename to `$null = Invoke-ParallelProcessing ...` until the result is properly consumed.

---

### IN-02: `Start-Sleep -Seconds 30` prepended to `$installDefenderCommand` via magic constant with a TODO comment

**File:** `FFUDevelopment/BuildFFUVM.ps1:3396-3399`

**Issue:**
A 30-second hardcoded delay is prepended to the Defender installer script with a comment admitting it is a workaround:

```powershell
# Long-term solution would be the check for AppxSVC being started, but for now the 30 second sleep seems to work consistently
$installDefenderCommand = "Start-Sleep -Seconds 30`r`n"
```

This is a magic number with documented technical debt. It will become a silent reliability problem if the system is faster (wasted time) or slower (AppxSVC not ready in 30s) than the test environment.

**Fix:** Extract to a named constant (e.g., `$DefenderInstallDelaySeconds = 30`) with a comment, and log the delay at runtime. Track the AppxSVC service-check implementation as a separate work item.

---

_Reviewed: 2026-06-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
