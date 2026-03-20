# Phase 47: USB Mode Pipeline Entry - Research

**Researched:** 2026-03-20
**Domain:** PowerShell pipeline integration — BuildFFUVM.ps1 short-circuit code path, ArtifactManifest data contract, $using: variable population
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** New `-USBOnlyMode [switch]` parameter added to BuildFFUVM.ps1 param block — explicit switch, not inferred from config
- **D-02:** Live scan via `Find-FFUArtifacts -FFUDevelopmentPath $FFUDevelopmentPath` at execution time — no saved manifest file, no `-ArtifactManifestPath` parameter
- **D-03:** Short-circuit code path after module imports (~line 1600): scan → validate → populate variables → jump directly to USB creation. Does NOT fall through 3,000 lines of gated build phases
- **D-04:** Reuse `New-DeploymentUSB` as-is with no wrapper — populate the existing script-scoped gate variables from manifest before calling
- **D-05:** Copy gates (`$CopyDrivers`, `$CopyPPKG`, `$CopyUnattend`, `$CopyAutopilot`) driven by manifest artifact status: `Found` → `$true`, `Missing` → `$false`
- **D-06:** Disposition (Reuse/Rebuild/Skip) is Phase 50's concern — Phase 47 ignores it entirely
- **D-07:** Missing optional artifacts (Drivers, PPKG, Autopilot, Unattend, AppsISO) log a warning via WriteLog ("Skipping {type} — not found at {path}") and set copy gate to `$false`
- **D-08:** `$WindowsArch` populated from primary FFU metadata: `$manifest.FFUFiles[0].Metadata.Architecture`
- **D-09:** `$SelectedFFUFile` populated with all Found FFU file paths from manifest (supports multi-FFU via existing array handling in New-DeploymentUSB)
- **D-10:** Three-step validation sequence before any USB writes:
  1. `$manifest.IsReady` check — FFU + DeployISO must be Found (BLOCKING)
  2. Deploy ISO mountable — test with `Mount-DiskImage` before touching USB drives (BLOCKING, satisfies USB-01)
  3. Log all `$manifest.Warnings` — architecture mismatches, staleness info (NON-BLOCKING)
- **D-11:** Architecture mismatch (FFU vs Deploy ISO) is warn-and-continue, not blocking — per Phase 46 decision (scanner informs, doesn't gatekeep)
- **D-12:** ISO mount failure produces actionable error message including expected path and suggestion to run full build — halts before any USB writes (satisfies success criterion 2)
- **D-13:** Pre-flight checks (Hyper-V, ADK, disk space) skipped entirely — not relevant to USB assembly, handled naturally by the short-circuit code path

### Claude's Discretion

- Exact placement of the short-circuit block within BuildFFUVM.ps1 (after module imports, before build phases)
- How to handle `$LogFile` initialization for USBOnlyMode (may need a subset of the normal init)
- Whether to add a `$resolvedUSBThrottle` calculation or reuse the existing one
- ISO mount/dismount cleanup pattern within the validation step

### Deferred Ideas (OUT OF SCOPE)

- Disposition-based copy gating (Reuse/Rebuild/Skip) — Phase 50: Selective Rebuild Pipeline
- Per-artifact path overrides from UI browse dialogs — Phase 49: UI Event Wiring
- Config-driven auto-detection of USBOnlyMode — not needed, explicit switch is clearer
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| USB-01 | USB Mode blocks USB creation if WinPE deployment ISO is missing with actionable message | D-10 step 2: Mount-DiskImage test before USB writes; D-12: actionable error message pattern identified. `New-DeploymentUSB` already throws "Deployment ISO not found: $DeployISO" at line 5217 — USBOnlyMode must replicate this as a pre-validation step BEFORE calling New-DeploymentUSB. |
| USB-04 | USB Mode assembles selected artifacts into deployable USB via existing New-DeploymentUSB | D-04: direct call with no wrapper. All 14 `$using:` variables audited and mapped to manifest fields. `New-DeploymentUSB` is called at line 5213 with `-CopyFFU -FFUFilesToCopy $ffuFilesToCopy`. USBOnlyMode block must set the same script-scoped variables before calling. |
</phase_requirements>

## Summary

Phase 47 is a pipeline integration task. The goal is to give BuildFFUVM.ps1 a `-USBOnlyMode` switch that scans for artifacts via FFU.ArtifactScanner (Phase 46), validates them, and calls the existing `New-DeploymentUSB` function — bypassing all 3,000+ lines of build logic. All components exist and are stable. No new modules, no UI changes, no new helper functions beyond the short-circuit block itself.

The dominant challenge is ensuring every variable consumed by `New-DeploymentUSB`'s `ForEach-Object -Parallel` block (14 `$using:` references) is correctly populated from the manifest before the function is called. This is not speculative — every reference has been audited against the actual source code at lines 1411–1542. The manifest data contract from Phase 46 maps cleanly to all 14 variables.

The second challenge is correct placement of the short-circuit block. It must come AFTER all module imports (line ~1000) so FFU.ArtifactScanner is available, and AFTER `$LogFile` initialization (line 1587) so WriteLog works, but BEFORE the pre-flight validation block (line 1713) so that Hyper-V/ADK checks are never executed.

**Primary recommendation:** Insert the short-circuit block at approximately line 1600, between the checkpoint resume detection block (ends ~1705) and the pre-flight validation block (begins at line 1712). Add `Import-Module "FFU.ArtifactScanner"` to the module import list at line ~999. Add `-USBOnlyMode [switch]` to the param block with no default value (switch default is always `$false`).

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFU.ArtifactScanner | 1.0.0 | Discover artifacts, return ArtifactManifest | Phase 46 output — the defined data contract for this phase |
| FFU.Core | 1.0.9 | WriteLog, Invoke-BuildPhase, error handling | Foundation module already imported in BuildFFUVM.ps1 |
| FFU.Preflight | 1.0.0 | Required by FFU.ArtifactScanner (via RequiredModules) | Already imported at line 999 |
| Mount-DiskImage | built-in | ISO mountability pre-validation | Already used by New-DeploymentUSB at line 1398 |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Start-ThreadJob | built-in | Pester test: parse-time failure verification | Required by success criterion 4 — Pester test must launch via ThreadJob |
| FFU.Messaging | built-in | Set-Progress calls for USBOnlyMode progress | If MessagingContext is present (UI launch scenario) |

**Installation:**

No new packages needed. FFU.ArtifactScanner module is already present at:
`FFUDevelopment\Modules\FFU.ArtifactScanner\`

It requires PowerShell 7.0 (declared in its `.psd1`). BuildFFUVM.ps1 already runs on PS7 when launched from the UI.

## Architecture Patterns

### Recommended Project Structure

No new files or folders. All changes are within:

```
FFUDevelopment/
├── BuildFFUVM.ps1                   # param block: add -USBOnlyMode; body: add short-circuit block + module import
├── Modules/FFU.ArtifactScanner/     # Already exists — add Import-Module line to BuildFFUVM.ps1
└── Tests/Test-USBOnlyMode.ps1       # New Pester-style test (success criterion 4)
```

### Pattern 1: Switch Parameter in Param Block

**What:** Adding a `[switch]$USBOnlyMode` to the existing param block.

**When to use:** Explicit mode switches that must be available from both CLI and UI background job launch.

**Rules:**
- No default value needed — switch is `$false` by default
- No `[FFUConstants]::` expression in the default (per CLAUDE.md param block coupling rule)
- Declare after `$NoResume` switch (line 562) for logical grouping with other mode-control switches

**Example:**
```powershell
# Source: BuildFFUVM.ps1 param block, modeled after $NoResume and $Cleanup patterns (lines 524, 562)
[Parameter(Mandatory = $false)]
[switch]$USBOnlyMode
```

### Pattern 2: Short-Circuit Block (Early Return)

**What:** An `if ($USBOnlyMode)` block placed after all module imports and log initialization but before pre-flight. The block scans, validates, populates script-scoped variables, calls `New-DeploymentUSB`, and then returns to exit the script early.

**When to use:** Mode-specific code path that must bypass all downstream logic.

**Placement (verified against actual line numbers):**
- After: checkpoint resume detection block (ends ~line 1705)
- Before: `$skipPreflightValidation = $false` (line 1713)
- After: `$LogFile` set and `Set-CommonCoreLogPath` called (lines 1587-1597)
- After: FFU.ArtifactScanner import (to be added at ~line 1000)

**Pattern skeleton:**
```powershell
# Source: modeled after $Cleanup early-exit pattern (line 524) and $skipPreflightValidation gate (line 1713)
if ($USBOnlyMode) {
    WriteLog "USBOnlyMode: Starting USB-only assembly path"
    Set-Progress -Percentage 5 -Message "Scanning for deployment artifacts..."

    # Step 1: Scan artifacts
    $manifest = Find-FFUArtifacts -FFUDevelopmentPath $FFUDevelopmentPath

    # Step 2: Validate readiness (BLOCKING)
    if (-not $manifest.IsReady) {
        # Actionable error per D-12
        $missingTypes = @()
        $ffuFound = $manifest.FFUFiles | Where-Object { $_.Status.ToString() -eq 'Found' }
        if (-not $ffuFound -or @($ffuFound).Count -eq 0) { $missingTypes += 'FFU file' }
        if ($manifest.DeployISO.Status.ToString() -ne 'Found') { $missingTypes += 'WinPE deployment ISO' }
        throw "USBOnlyMode cannot proceed: missing required artifacts: $($missingTypes -join ', '). Run a full build first to generate these artifacts."
    }

    # Step 3: Log manifest warnings (NON-BLOCKING)
    foreach ($warning in $manifest.Warnings) {
        WriteLog "WARNING: $($warning.Message)"
    }

    # Step 4: ISO mountability pre-validation (BLOCKING — satisfies USB-01)
    $deployISOPath = $manifest.DeployISO.FilePath
    WriteLog "USBOnlyMode: Verifying ISO is mountable: $deployISOPath"
    try {
        $testMount = Mount-DiskImage -ImagePath $deployISOPath -PassThru -ErrorAction Stop
        Dismount-DiskImage -ImagePath $deployISOPath | Out-Null
        WriteLog "USBOnlyMode: ISO mountability verified"
    }
    catch {
        throw "USBOnlyMode: WinPE deployment ISO cannot be mounted: $deployISOPath. Error: $($_.Exception.Message). Run a full build to recreate the ISO."
    }

    # Step 5: Populate $using: variables from manifest
    # (see $using: variable population section below)

    # Step 6: Populate DeployISO and gate variables
    $DeployISO = $deployISOPath
    $BuildUSBDrive = $true

    # Step 7: Detect USB drives
    $USBDrives, $USBDrivesCount = Get-FFUUSBDrives
    if ($USBDrivesCount -eq 0) {
        throw "USBOnlyMode: No USB drives detected. Connect a USB drive and retry."
    }

    # Step 8: Call New-DeploymentUSB
    Set-Progress -Percentage 10 -Message "Assembling USB drive(s)..."
    New-DeploymentUSB -CopyFFU -FFUFilesToCopy $SelectedFFUFile

    Set-Progress -Percentage 100 -Message "USB assembly complete."
    WriteLog "USBOnlyMode: USB assembly complete."
    return
}
```

### Pattern 3: $using: Variable Population from Manifest

**What:** Setting the 14 script-scoped variables that `New-DeploymentUSB`'s `ForEach-Object -Parallel` block reads via `$using:` before calling the function.

**Complete $using: audit (verified against lines 1411-1542):**

| $using: Variable | Line | Source in Manifest | Notes |
|-----------------|------|-------------------|-------|
| `$PSScriptRoot` | 1415 | Built-in PS automatic variable | No action needed — always populated |
| `$LogFile` | 1416 | Already set at line 1587 | No action needed |
| `$ISOMountPoint` | 1464-1465 | Set internally by New-DeploymentUSB from `$DeployISO` | Set `$DeployISO = $manifest.DeployISO.FilePath` |
| `$CopyFFU` | 1469 | Always `$true` for USBOnlyMode (FFU present per IsReady check) | Pass `-CopyFFU` switch to New-DeploymentUSB |
| `$SelectedFFUFile` | 1469-1479 | All Found FFU paths from manifest | `$SelectedFFUFile = @($manifest.FFUFiles | Where-Object { $_.Status.ToString() -eq 'Found' } | Select-Object -ExpandProperty FilePath)` |
| `$CopyDrivers` | 1484 | `$manifest.Drivers.Status.ToString() -eq 'Found'` | D-05 |
| `$DriversFolder` | 1487 | `$manifest.Drivers.FilePath` (folder path) or default `"$FFUDevelopmentPath\Drivers"` | Required even when $CopyDrivers is false (variable must exist) |
| `$CopyPPKG` | 1491 | Any PPKG with Found status | `@($manifest.PPKGFiles | Where-Object { $_.Status.ToString() -eq 'Found' }).Count -gt 0` |
| `$PPKGFolder` | 1494 | Default `"$FFUDevelopmentPath\PPKG"` | Required even when $CopyPPKG is false |
| `$CopyUnattend` | 1498 | Any Unattend with Found status | `@($manifest.UnattendFiles | Where-Object { $_.Status.ToString() -eq 'Found' }).Count -gt 0` |
| `$WindowsArch` | 1503-1510 | `$manifest.FFUFiles[0].Metadata.Architecture` | D-08; fallback to `'x64'` if metadata null |
| `$UnattendFolder` | 1504-1517 | Default `"$FFUDevelopmentPath\Unattend"` | Required even when $CopyUnattend is false |
| `$CopyAutopilot` | 1529 | Any Autopilot with Found status | `@($manifest.AutopilotFiles | Where-Object { $_.Status.ToString() -eq 'Found' }).Count -gt 0` |
| `$AutopilotFolder` | 1532 | Default `"$FFUDevelopmentPath\Autopilot"` | Required even when $CopyAutopilot is false |

**Critical insight:** `$DriversFolder`, `$PPKGFolder`, `$UnattendFolder`, and `$AutopilotFolder` MUST be set even when their corresponding `$Copy*` gate is `$false`. The `$using:` resolution in the parallel block happens before the `if ($using:CopyDrivers)` guard is evaluated; an unset variable resolves to `$null` without error but could cause issues. The path initialization block at lines 1864-1867 sets these as defaults for the full build path — USBOnlyMode needs to replicate just these four assignments.

**$WindowsArch population (D-08) — edge cases:**
- Primary FFU has Metadata with DISM source: use `$manifest.FFUFiles[0].Metadata.Architecture` directly
- Primary FFU has Metadata with Filename source: architecture may be `'Unknown'` — fall back to `'x64'` and log warning
- Primary FFU has null Metadata: fall back to `'x64'` and log warning

**$SelectedFFUFile note:** New-DeploymentUSB already handles both single-string and array forms at lines 1469-1482. Since USBOnlyMode calls with `-FFUFilesToCopy $SelectedFFUFile`, the array path at line 1470-1476 applies when multiple FFUs are found.

### Pattern 4: ISO Mountability Pre-Validation

**What:** `Mount-DiskImage` test before any USB drive is touched.

**Why:** D-10 step 2 requires this as BLOCKING. `New-DeploymentUSB` already mounts the ISO at line 1398, but USBOnlyMode must validate mountability BEFORE calling the function so the error is reported before any USB partitioning begins.

**Cleanup requirement:** The test mount must be dismounted immediately after verification. If the validation throws after mount but before dismount, a cleanup handler is needed. Use the `Register-ISOCleanup` pattern already in `New-DeploymentUSB` at line 1402, or use try/finally:

```powershell
# Source: pattern from New-DeploymentUSB lines 1397-1402
$testMounted = $false
try {
    $testMount = Mount-DiskImage -ImagePath $deployISOPath -PassThru -ErrorAction Stop
    $testMounted = $true
    Dismount-DiskImage -ImagePath $deployISOPath | Out-Null
    $testMounted = $false
    WriteLog "USBOnlyMode: ISO mountability verified"
}
catch {
    if ($testMounted) {
        Dismount-DiskImage -ImagePath $deployISOPath -ErrorAction SilentlyContinue | Out-Null
    }
    throw "USBOnlyMode: WinPE deployment ISO cannot be mounted: $deployISOPath. ..."
}
```

### Pattern 5: Module Import Addition

**What:** FFU.ArtifactScanner must be imported in BuildFFUVM.ps1 before the short-circuit block executes.

**Where:** Line ~999, after `Import-Module "FFU.Preflight"` (FFU.ArtifactScanner requires FFU.Preflight per its `RequiredModules` declaration in the `.psd1`).

```powershell
# Source: FFU.ArtifactScanner.psd1 RequiredModules: FFU.Core + FFU.Preflight
# Import after FFU.Preflight to satisfy RequiredModules at line 999
Import-Module "FFU.ArtifactScanner" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
```

**PS7 requirement:** `FFU.ArtifactScanner.psd1` declares `PowerShellVersion = '7.0'`. BuildFFUVM.ps1 is called from the UI via `Start-ThreadJob` which runs in the same PowerShell session. When invoked from a PS5.1 session directly, this import will fail. Research recommendation: add `-ErrorAction SilentlyContinue` and log a warning if import fails, then skip the short-circuit block with a message like "USBOnlyMode requires PowerShell 7.0+".

### Anti-Patterns to Avoid

- **Wrapping New-DeploymentUSB:** D-04 is explicit — no wrapper. Populate script-scoped variables directly.
- **Using $function: drive with hyphenated function names:** `Test-FFUWimMount`, `Find-FFUArtifacts` etc. require `Get-Command` try/catch or direct call (per STATE.md Phase 46 decisions). The short-circuit block calls `Find-FFUArtifacts` directly — no availability check needed since it is imported at module load.
- **[FFUConstants]:: in param default:** Success criterion 5 is explicit. `-USBOnlyMode` is a switch with no default expression at all.
- **Setting $USBDrives before USBDrive detection:** `Get-FFUUSBDrives` returns the USB drive list. This is a real device operation — must happen in the short-circuit block, not inferred from manifest.
- **Relying on $skipPreflightValidation:** The short-circuit block exits via `return` before the pre-flight gate is even reached. Do not set `$skipPreflightValidation = $true` and continue normal flow — that would still execute 3,000 lines of gated build phases.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Artifact discovery | Custom file scanning logic | `Find-FFUArtifacts -FFUDevelopmentPath $FFUDevelopmentPath` | Phase 46 module handles all 7 artifact types, WIMMount gate, DISM metadata, compatibility warnings |
| USB drive detection | `Get-Disk` / `Get-PhysicalDisk` filter logic | `Get-FFUUSBDrives` (exported from FFU.Core or BuildFFUVM.ps1 inline) | Existing function already handles removable media detection correctly |
| USB assembly | Custom robocopy orchestration | `New-DeploymentUSB -CopyFFU -FFUFilesToCopy $arr` | Complete implementation at lines 1315-1549 including parallel processing, robocopy, volume renaming |
| ISO validation | Custom WMI/COM ISO parsing | `Mount-DiskImage -PassThru` then immediate `Dismount-DiskImage` | Standard PowerShell cmdlet — already used at line 1398 |
| Architecture fallback | Re-implementing filename parsing | `$manifest.FFUFiles[0].Metadata.Architecture` (fallback to 'x64') | Get-MetadataFromFilename is internal to FFU.ArtifactScanner; use the Metadata property already populated |

**Key insight:** Every required primitive already exists and is tested. Phase 47 is pure integration — correct variable mapping from manifest to existing function, not new capability.

## Common Pitfalls

### Pitfall 1: $using: Variable Not Set in Parallel Block
**What goes wrong:** `New-DeploymentUSB` uses `ForEach-Object -Parallel` internally. If any of the 14 `$using:` variables are not set as script-scoped variables before calling the function, they silently resolve to `$null`. `$CopyDrivers` being `$null` evaluates as `$false` (no error), but `$DriversFolder` being `$null` causes `robocopy $null ...` to fail with a misleading error.

**Why it happens:** The 14 `$using:` variables are set by the full build pipeline's path initialization block at lines 1829-1867. USBOnlyMode bypasses this block entirely.

**How to avoid:** Set all 14 variables explicitly in the USBOnlyMode block. The 4 folder path variables (`$DriversFolder`, `$PPKGFolder`, `$UnattendFolder`, `$AutopilotFolder`) must be set to their default paths even when their corresponding `$Copy*` gate is `$false`.

**Warning signs:** Robocopy errors with empty source path, or `$null` path exceptions in the parallel block.

### Pitfall 2: $WindowsArch from Metadata Is 'Unknown'
**What goes wrong:** `Get-ArtifactMetadata` falls back to filename parsing when DISM is unavailable. The Architecture field may be `'Unknown'` if the filename doesn't match expected patterns.

**Why it happens:** `New-DeploymentUSB` uses `$using:WindowsArch` at lines 1503-1510 to decide which `unattend_x64.xml` or `unattend_arm64.xml` to copy. If `$WindowsArch = 'Unknown'`, neither `if ($using:WindowsArch -eq 'x64')` nor `elseif ($using:WindowsArch -eq 'arm64')` branch executes — but no error is thrown, unattend is silently not copied.

**How to avoid:** D-08 specifies using the metadata architecture. Add a fallback: if metadata architecture is null, empty, or 'Unknown', default to `'x64'` and log a warning per D-07 pattern.

**Warning signs:** USB drive assembled without Unattend.xml when `$CopyUnattend` is `$true`.

### Pitfall 3: PS5.1 Import of FFU.ArtifactScanner
**What goes wrong:** `FFU.ArtifactScanner.psd1` declares `PowerShellVersion = '7.0'`. If BuildFFUVM.ps1 is invoked from a PS5.1 session and `-ErrorAction Stop` is used, the entire script fails at the import line.

**Why it happens:** FFU.ArtifactScanner uses `ForEach-Object -Parallel` syntax (PS7 feature) internally.

**How to avoid:** Use `-ErrorAction SilentlyContinue` for the FFU.ArtifactScanner import, same as the optional FFU.ConfigMigration import at line 1003-1005. If the module isn't loaded and `-USBOnlyMode` is set, throw a descriptive error: "USBOnlyMode requires PowerShell 7.0 or later. Current version: $($PSVersionTable.PSVersion)".

**Warning signs:** Import-Module failure halting the script when PS5.1 is used for a normal full build (not USBOnlyMode).

### Pitfall 4: $manifest.FFUFiles[0] When Zero FFU Found
**What goes wrong:** If `$manifest.IsReady` is `$false` because no FFU was found, `$manifest.FFUFiles[0]` still returns the single Missing ArtifactResult (the scanner always creates a placeholder). Accessing `.Metadata.Architecture` on a Missing result returns `$null.Architecture` which throws "You cannot call a method on a null-valued expression."

**Why it happens:** The `Find-FFUArtifacts` function always populates `$manifest.FFUFiles` with at least one entry (a Missing placeholder if no FFUs found). The IsReady check (D-10 step 1) blocks before variable population, but the architecture population code must guard against null Metadata.

**How to avoid:** Populate `$WindowsArch` AFTER the `$manifest.IsReady` validation step. At that point, at least one Found FFU is guaranteed. Still guard with: `if ($manifest.FFUFiles[0].Metadata -and $manifest.FFUFiles[0].Metadata.Architecture -ne 'Unknown') { ... } else { $WindowsArch = 'x64' }`.

**Warning signs:** "You cannot call a method on a null-valued expression" at the $WindowsArch assignment line.

### Pitfall 5: DeployISO Path vs $DeployISO Variable
**What goes wrong:** `New-DeploymentUSB` (line 1397) uses the script-scoped `$DeployISO` variable directly (`WriteLog "Mounting deployment ISO: $DeployISO"`). It does not accept a parameter for the ISO path. USBOnlyMode must set `$DeployISO = $manifest.DeployISO.FilePath` before calling the function.

**Why it happens:** `New-DeploymentUSB` has no `-ISOPath` parameter — it relies on script-scoped variable access.

**How to avoid:** Always set `$DeployISO` explicitly in the USBOnlyMode block from the manifest. The pre-validation ISO mount test should use the same `$deployISOPath` variable.

**Warning signs:** `New-DeploymentUSB` mounts a different path than the pre-validated one.

### Pitfall 6: $USBDrivesCount Variable Not Set
**What goes wrong:** `New-DeploymentUSB` uses `$USBDrivesCount` at line 1406 directly from script scope, not as a parameter. If USBOnlyMode doesn't call `Get-FFUUSBDrives` to populate both `$USBDrives` and `$USBDrivesCount`, the function fails at the throttle calculation.

**Why it happens:** Same script-scoped variable access pattern as `$DeployISO` — `New-DeploymentUSB` relies on outer scope variables.

**How to avoid:** Call `$USBDrives, $USBDrivesCount = Get-FFUUSBDrives` in the USBOnlyMode block before calling `New-DeploymentUSB`. Also set `$resolvedUSBThrottle = if ($MaxUSBDrives -gt 0) { [math]::Min($MaxUSBDrives, $USBDrivesCount) } else { $USBDrivesCount }` since this is computed at line 1408 inside the function (it reads `$MaxUSBDrives` from outer scope, which IS a parameter — that one is safe).

### Pitfall 7: Short-Circuit Block Placed Before $LogFile Initialization
**What goes wrong:** If the `if ($USBOnlyMode)` block is placed before `$LogFile` is set (line 1587) and `Set-CommonCoreLogPath` is called (line 1592), then `WriteLog` writes to the wrong path or fails silently.

**Why it happens:** `$LogFile` initialization happens inside a `if (-not $LogFile)` guard at line 1587. That line is in the PROCESS block of the script (actually the END block at line 689). The short-circuit block must be placed AFTER line 1597.

**How to avoid:** Place the short-circuit block between the checkpoint resume detection block (~line 1705) and `$skipPreflightValidation = $false` (line 1713). At that point `$LogFile` is set, `Set-CommonCoreLogPath` has been called, and all modules are imported.

## Code Examples

### ArtifactManifest Data Access (verified against Phase 46 output)

```powershell
# Source: FFU.ArtifactScanner.psm1 Find-FFUArtifacts return structure
$manifest = Find-FFUArtifacts -FFUDevelopmentPath $FFUDevelopmentPath

# IsReady: FFU found + DeployISO found + no errors
$manifest.IsReady        # [bool]

# FFU files - always at least one entry (Missing placeholder if none found)
$manifest.FFUFiles       # [ArtifactResult[]] sorted newest-first
$manifest.FFUFiles[0].Status.ToString()          # 'Found', 'Missing', or 'Error'
$manifest.FFUFiles[0].FilePath                   # full path to .ffu file
$manifest.FFUFiles[0].Metadata.Architecture     # 'x64', 'arm64', 'x86', 'Unknown', or null
$manifest.FFUFiles[0].IsPrimary                 # $true for first (newest) FFU

# DeployISO - single result
$manifest.DeployISO.Status.ToString()           # 'Found' or 'Missing'
$manifest.DeployISO.FilePath                    # full path to .iso file

# Optional artifacts - arrays, always at least one Missing placeholder entry
$manifest.Drivers.Status.ToString()            # 'Found' or 'Missing' (single result, not array)
$manifest.Drivers.FilePath                     # folder path when Found
$manifest.PPKGFiles[0].Status.ToString()       # check first entry
$manifest.UnattendFiles[0].Status.ToString()   # check first entry
$manifest.AutopilotFiles[0].Status.ToString()  # check first entry

# Warnings (architecture mismatch, etc.)
foreach ($warning in $manifest.Warnings) {
    WriteLog "WARNING: $($warning.Message)"
}
```

### Copy Gate Population Pattern (D-05)

```powershell
# Source: D-05 decision — Found -> $true, Missing -> $false
$CopyDrivers   = ($manifest.Drivers.Status.ToString() -eq 'Found')
$CopyPPKG      = ((@($manifest.PPKGFiles  | Where-Object { $_.Status.ToString() -eq 'Found' })).Count -gt 0)
$CopyUnattend  = ((@($manifest.UnattendFiles | Where-Object { $_.Status.ToString() -eq 'Found' })).Count -gt 0)
$CopyAutopilot = ((@($manifest.AutopilotFiles | Where-Object { $_.Status.ToString() -eq 'Found' })).Count -gt 0)

# Log warnings for missing optional artifacts (D-07)
$optionalChecks = @(
    @{ Name = 'Drivers';   Gate = $CopyDrivers;   Path = "$FFUDevelopmentPath\Drivers" }
    @{ Name = 'PPKG';      Gate = $CopyPPKG;      Path = "$FFUDevelopmentPath\PPKG" }
    @{ Name = 'Unattend';  Gate = $CopyUnattend;  Path = "$FFUDevelopmentPath\Unattend" }
    @{ Name = 'Autopilot'; Gate = $CopyAutopilot; Path = "$FFUDevelopmentPath\Autopilot" }
)
foreach ($check in $optionalChecks) {
    if (-not $check.Gate) {
        WriteLog "USBOnlyMode: Skipping $($check.Name) — not found at $($check.Path)"
    }
}
```

### $WindowsArch Population with Fallback (D-08)

```powershell
# Source: D-08 decision + Pitfall 2 mitigation
$primaryFFU = $manifest.FFUFiles | Where-Object { $_.IsPrimary -eq $true } | Select-Object -First 1
if ($null -eq $primaryFFU) {
    $primaryFFU = $manifest.FFUFiles | Where-Object { $_.Status.ToString() -eq 'Found' } | Select-Object -First 1
}

$WindowsArch = 'x64'  # default fallback
if ($null -ne $primaryFFU -and $null -ne $primaryFFU.Metadata) {
    $arch = $primaryFFU.Metadata.Architecture
    if (-not [string]::IsNullOrEmpty($arch) -and $arch -ne 'Unknown') {
        $WindowsArch = $arch
    }
    else {
        WriteLog "USBOnlyMode: FFU architecture unknown or unavailable — defaulting to x64"
    }
}
else {
    WriteLog "USBOnlyMode: FFU metadata not available — defaulting WindowsArch to x64"
}
```

### $SelectedFFUFile Population (D-09)

```powershell
# Source: D-09 decision + New-DeploymentUSB array handling at lines 1469-1482
$foundFFUPaths = @($manifest.FFUFiles |
    Where-Object { $_.Status.ToString() -eq 'Found' } |
    Select-Object -ExpandProperty FilePath)

# $SelectedFFUFile must be set as script-scoped before calling New-DeploymentUSB
# The function reads it via $using:SelectedFFUFile in the parallel block
$SelectedFFUFile = $foundFFUPaths
```

### ThreadJob Parse-Time Test Pattern (Success Criterion 4)

```powershell
# Source: modeled after Test-SyntaxCheck.ps1 and Test-ModuleFunctionExports.ps1 patterns
# Purpose: verify BuildFFUVM.ps1 -USBOnlyMode does not cause parse-time failures

Describe 'BuildFFUVM USBOnlyMode ThreadJob parse-time test' {
    It 'launches via Start-ThreadJob without parse-time failures' {
        $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
        if ($env:PSModulePath -notlike "*$modulesPath*") {
            $env:PSModulePath = "$modulesPath;$env:PSModulePath"
        }
        $buildScript = Join-Path $PSScriptRoot '..\..\BuildFFUVM.ps1'
        $job = Start-ThreadJob -ScriptBlock {
            param($script, $modPath)
            $env:PSModulePath = "$modPath;$env:PSModulePath"
            # Parse only — do not execute (use Parser::ParseFile)
            $errors = $null
            $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors)
            return $errors.Count
        } -ArgumentList $buildScript, $modulesPath
        $result = $job | Wait-Job | Receive-Job
        $job | Remove-Job
        $result | Should -Be 0
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual ISO path construction (`"$FFUDevelopmentPath\WinPE_FFU_Deploy_$WindowsArch.iso"`) | Manifest-provided path from scanner | Phase 46 → Phase 47 | Path comes from actual file system scan, not parameter inference |
| USB creation only from full build pipeline | USB creation from manifest via `-USBOnlyMode` | Phase 47 | Decouples USB assembly from build steps |

**Deprecated/outdated:**
- None for this phase — adding new capability, not replacing existing functionality.

## Open Questions

1. **Get-FFUUSBDrives function location**
   - What we know: `$USBDrives, $USBDrivesCount = ...` is used at line 1311 end and USB detection is at lines ~1200-1313. The function `Get-USBDrives` or similar must be defined somewhere in BuildFFUVM.ps1 or FFU.Core.
   - What's unclear: The exact function name exported by FFU.Core or defined inline. The CONTEXT.md references `Get-FFUUSBDrives` but this needs verification against the actual function name.
   - Recommendation: During plan execution, grep BuildFFUVM.ps1 for `USBDrive` function definitions before writing the short-circuit block. If the function is inline (not exported from a module), call it directly within the USBOnlyMode block.

2. **$Messaging context for Set-Progress in USBOnlyMode**
   - What we know: `Set-Progress` calls are used throughout the build (line 5185) and work correctly when `$MessagingContext` is provided by the UI.
   - What's unclear: Whether the USBOnlyMode block needs a `Set-Progress` wrapper or can use direct WriteLog.
   - Recommendation: Include `Set-Progress` calls in the USBOnlyMode block — they are no-ops when `$MessagingContext` is null (CLI usage), so there is no downside.

3. **PS5.1 USBOnlyMode behavior**
   - What we know: FFU.ArtifactScanner requires PS7.0. The import should use `-ErrorAction SilentlyContinue`.
   - What's unclear: Whether there is a PS5.1 fallback for artifact scanning or whether USBOnlyMode is documented as PS7-only.
   - Recommendation: Treat USBOnlyMode as PS7-only. If FFU.ArtifactScanner import fails, throw a clear error if `-USBOnlyMode` was requested; otherwise continue silently (full build path works in PS5.1 without this module).

## Validation Architecture

> `workflow.nyquist_validation` is absent from `.planning/config.json` — treating as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Custom PS1 test scripts (project convention — no Pester config file found) |
| Config file | None — tests run via direct invocation |
| Quick run command | `pwsh -File "D:\claude\FFUBuilder\FFUDevelopment\Tests\Test-SyntaxCheck.ps1"` |
| Full suite command | `pwsh -Command "Get-ChildItem 'D:\claude\FFUBuilder\FFUDevelopment\Tests\Test-*.ps1' | ForEach-Object { & $_.FullName }"` |

**Note:** The project uses custom PS1 test scripts rather than Pester `.Tests.ps1` files. Success criterion 4 specifies a "Pester test" — this should be written as a Pester `.Tests.ps1` file consistent with the `test_requirements.test_framework: "Pester 5.x"` in `config.json`, placed at `FFUDevelopment/Tests/`. The project has no existing `.Tests.ps1` files but config.json declares Pester 5.x as the standard.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| USB-01 | USBOnlyMode halts with actionable message when DeployISO missing | unit | `Invoke-Pester Tests/Test-USBOnlyMode.Tests.ps1 -Output Minimal` | Wave 0 |
| USB-04 | USBOnlyMode assembles USB via New-DeploymentUSB when artifacts present | unit (mocked) | `Invoke-Pester Tests/Test-USBOnlyMode.Tests.ps1 -Output Minimal` | Wave 0 |
| SC-4 | BuildFFUVM.ps1 -USBOnlyMode survives Start-ThreadJob parse without failures | parse/smoke | `Invoke-Pester Tests/Test-USBOnlyMode.Tests.ps1 -Output Minimal` | Wave 0 |
| SC-5 | No param block default uses [FFUConstants]:: | static analysis | `pwsh -File Tests/Test-SyntaxCheck.ps1` — manual review of param block | Partial (SyntaxCheck exists, pattern check is manual) |

### Sampling Rate

- **Per task commit:** `pwsh -File "D:\claude\FFUBuilder\FFUDevelopment\Tests\Test-SyntaxCheck.ps1"`
- **Per wave merge:** Full test suite + `Invoke-Pester Tests/Test-USBOnlyMode.Tests.ps1`
- **Phase gate:** All tests green + verify-app agent invocation before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `Tests/Test-USBOnlyMode.Tests.ps1` — covers USB-01 (missing ISO error), USB-04 (variable mapping to New-DeploymentUSB), SC-4 (ThreadJob parse-time test), SC-5 ($using: completeness)

## Sources

### Primary (HIGH confidence)

- BuildFFUVM.ps1 lines 1315-1549 — New-DeploymentUSB complete implementation, all 14 `$using:` references audited
- BuildFFUVM.ps1 lines 1585-1597 — $LogFile initialization and Set-CommonCoreLogPath call (placement constraint for short-circuit block)
- BuildFFUVM.ps1 lines 973-1005 — module import block (FFU.ArtifactScanner import location)
- BuildFFUVM.ps1 lines 1707-1715 — pre-flight skip pattern ($skipPreflightValidation = $false) — placement upper bound
- BuildFFUVM.ps1 lines 5184-5226 — existing USB creation gate (pattern for $BuildUSBDrive, $skipUSBCreation)
- FFU.ArtifactScanner.psm1 — Find-FFUArtifacts return structure, ArtifactManifest schema
- FFU.ArtifactScanner.Classes.ps1 — ArtifactStatus enum values, ArtifactManifest typed properties
- FFU.ArtifactScanner.psd1 — PowerShellVersion = '7.0', RequiredModules = FFU.Core + FFU.Preflight
- .planning/phases/47-usb-mode-pipeline-entry/47-CONTEXT.md — all locked decisions D-01 through D-13
- .planning/STATE.md — Phase 46 accumulated decisions (class cross-scope, @($null) null-filter pattern)
- .planning/config.json — test_requirements.test_framework = "Pester 5.x"

### Secondary (MEDIUM confidence)

- BuildFFUVM.ps1 lines 1829-1867 — path initialization defaults (verified as template for USBOnlyMode folder variable assignments)
- CLAUDE.md — param block coupling rule (no [FFUConstants]:: in param defaults), ThreadJob compatibility requirements

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all components exist and are verified by reading actual source code
- Architecture: HIGH — $using: variable audit is line-by-line against actual code; placement constraints are verified against actual line numbers
- Pitfalls: HIGH — every pitfall is derived from actual code inspection, not speculation
- Open questions: LOW — function name verification for Get-FFUUSBDrives needed at plan execution time

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable phase — no fast-moving dependencies)
