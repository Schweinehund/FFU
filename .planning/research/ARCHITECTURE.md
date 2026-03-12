# Architecture Research

**Domain:** USB from Existing Components mode — FFU Builder WPF application
**Researched:** 2026-03-12
**Confidence:** HIGH (derived from direct codebase analysis)

## Standard Architecture

### System Overview — Current (v1.10.0)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        WPF UI Layer                                      │
│  BuildFFUVM_UI.ps1 + BuildFFUVM_UI.xaml (90KB)                          │
│  ┌──────┐ ┌────────┐ ┌──────────┐ ┌───────┐ ┌────────┐ ┌────────────┐  │
│  │ Home │ │VM Sett │ │ Win Sett │ │Updates│ │  Build │ │  Monitor   │  │
│  └──────┘ └────────┘ └──────────┘ └───────┘ └────────┘ └────────────┘  │
│  (Collects config → $buildParams → passes ConfigFile path to job)       │
├─────────────────────────────────────────────────────────────────────────┤
│                    ThreadJob / Start-Job Boundary                        │
│  ConcurrentQueue messaging (FFU.Messaging) ← 50ms DispatcherTimer       │
├─────────────────────────────────────────────────────────────────────────┤
│                    Build Orchestrator Layer                               │
│  BuildFFUVM.ps1 (2,404 lines) — sequential phase execution              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │  Pre-flight  │ │ Driver Dwld  │ │ VHDX Create  │ │  VM Create   │   │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘   │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │  FFU Capture │ │ Deploy Media │ │ USB Creation │ │   Cleanup    │   │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘   │
├─────────────────────────────────────────────────────────────────────────┤
│                      Module Layer (13 modules)                            │
│  FFU.Core  FFU.VM  FFU.Imaging  FFU.Media  FFU.Drivers  FFU.Preflight   │
│  FFU.ADK   FFU.Apps  FFU.Updates  FFU.Messaging  FFU.Hypervisor         │
│  FFU.Checkpoint  FFU.ConfigMigration                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                      Artifact Storage Layer                               │
│  FFU/     Drivers/   PPKG/   Autopilot/   unattend/   PEDrivers/        │
│  FFU/*.ffu  WinPE deploy .iso   WinPE capture .iso                      │
└─────────────────────────────────────────────────────────────────────────┘
```

### System Overview — Target (v1.11.0 USB Mode Added)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        WPF UI Layer                                      │
│  ┌──────────────────────────────┬──────────────────────────────────────┐ │
│  │     FULL BUILD MODE (tabs)   │     USB MODE (new tab/panel)         │ │
│  │  Home/VM/Windows/Updates/    │  Artifact Scanner panel              │ │
│  │  Apps/Drivers/Build/Monitor  │  Reuse / Rebuild / Skip per artifact │ │
│  │                              │  Selective pipeline execution toggle │ │
│  └──────────────────────────────┴──────────────────────────────────────┘ │
│  Mode Toggle control (RadioButton or ToggleButton at top level)          │
├─────────────────────────────────────────────────────────────────────────┤
│                    ThreadJob / Start-Job Boundary                        │
│  ConcurrentQueue messaging — same pattern, both modes use it            │
├─────────────────────────────────────────────────────────────────────────┤
│                    Build Orchestrator Layer                               │
│  BuildFFUVM.ps1 — gains -USBOnlyMode switch + -ArtifactManifest param  │
│  NEW: Invoke-USBOnlyPipeline — skips full build, runs selective phases  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                     │
│  │ Artifact     │ │ Selective    │ │ USB Creation │  (existing function) │
│  │ Scan+Validate│ │ Rebuild      │ │ (reused)     │                     │
│  └──────────────┘ └──────────────┘ └──────────────┘                     │
├─────────────────────────────────────────────────────────────────────────┤
│                 NEW Module: FFU.ArtifactScanner                          │
│  Find-FFUArtifacts  Test-ArtifactCompatibility  Get-ArtifactMetadata    │
│  New-ArtifactManifest  Invoke-SelectivePipeline                         │
├─────────────────────────────────────────────────────────────────────────┤
│                      Existing Module Layer                                │
│  (all 13 modules unchanged — selectively called by new pipeline)        │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Current Responsibility | Change for v1.11.0 |
|-----------|----------------------|--------------------|
| `BuildFFUVM_UI.ps1` | Collects config, launches ThreadJob calling BuildFFUVM.ps1 | Add mode-aware launch path; USB Mode passes ArtifactManifest instead of full config |
| `BuildFFUVM_UI.xaml` | ~90KB XAML defining all tabs | Add mode toggle + USB Mode tab (new `TabItem` or `StackPanel` panel toggled visible) |
| `BuildFFUVM.ps1` | Runs all 8 sequential build phases | Gain early exit to USB-only pipeline when `-USBOnlyMode` switch set |
| `New-DeploymentUSB` | Already in BuildFFUVM.ps1 — partitions USB, copies files using `$using:` vars | No logic change; receives artifact paths from manifest instead of live build vars |
| `Get-USBDrive` | Discovers USB drives | No change |
| `FFU.Preflight` | Pre-flight environment validation | USB Mode should invoke reduced preflight (no Hyper-V, ADK, WIMMount checks) |
| `FFU.Media` | Creates WinPE deployment ISO | Invoked only if deploy ISO rebuild requested |
| `FFU.Drivers` | Downloads OEM drivers | Invoked only if driver rebuild requested |
| `FFU.ArtifactScanner` | **NEW** | Full responsibility: scan, validate, metadata extraction, manifest creation |
| Config schema | JSON config + migration | New `USBMode` section needed (artifact paths, reuse/rebuild/skip flags) |

## Recommended Project Structure (New Files)

```
FFUDevelopment/
├── BuildFFUVM.ps1                    # Modified: +USBOnlyMode switch, +ArtifactManifest param
├── BuildFFUVM_UI.ps1                 # Modified: mode toggle logic, USB mode launch path
├── BuildFFUVM_UI.xaml                # Modified: mode toggle control + USB Mode tab content
├── Modules/
│   └── FFU.ArtifactScanner/          # NEW module
│       ├── FFU.ArtifactScanner.psd1  # Manifest, requires FFU.Core
│       └── FFU.ArtifactScanner.psm1  # Scan/validate/manifest functions
├── config/
│   └── ffubuilder-config.schema.json # Modified: USBMode section added
└── Tests/
    └── Unit/
        └── FFU.ArtifactScanner.Tests.ps1  # NEW tests
```

### Structure Rationale

- **FFU.ArtifactScanner as new module:** Artifact scanning is a distinct concern with no dependencies on build-time state. Isolating it as a module enables independent testing and keeps BuildFFUVM.ps1 from growing larger. Follows the existing module pattern (psd1+psm1, requires FFU.Core).
- **USB drive functions remain in BuildFFUVM.ps1:** The existing comment at line 1152 explains why — `New-DeploymentUSB` uses `ForEach-Object -Parallel` with many `$using:` references to script-scope variables. Moving it would require significant refactoring. USB Mode reuses this function exactly as-is.
- **Mode toggle in XAML, not a separate window:** The existing WPF window has a side tab strip. Adding a "USB Mode" tab maintains the existing navigation pattern. A top-level mode toggle (e.g., `RadioButton` group) hides/shows the relevant tabs for each mode.

## Architectural Patterns

### Pattern 1: Artifact Manifest as Contract Between UI and Pipeline

**What:** The USB Mode UI collects artifact decisions (paths + reuse/rebuild/skip for each artifact type) into a structured manifest object. This manifest is serialized to a temp JSON file and passed to BuildFFUVM.ps1 as an `-ArtifactManifest` parameter, mirroring how ConfigFile works today.

**When to use:** Decouples UI from pipeline — the UI does not need to know which build phases to call; the pipeline reads the manifest and decides.

**Trade-offs:** Extra serialization step. Pro: clean boundary, testable manifest structure, no new params needed in ThreadJob call pattern.

**Example:**
```powershell
# Manifest structure produced by FFU.ArtifactScanner
[PSCustomObject]@{
    FFUPath         = "C:\FFUDevelopment\FFU\Win11_Pro_x64_20251201.ffu"
    FFUAction       = "Reuse"    # Reuse | Rebuild | Skip
    DeployISOPath   = "C:\FFUDevelopment\WinPE_Deploy.iso"
    DeployISOAction = "Reuse"
    DriversPath     = "C:\FFUDevelopment\Drivers"
    DriversAction   = "Rebuild"
    PPKGPath        = "C:\FFUDevelopment\PPKG\config.ppkg"
    PPKGAction      = "Reuse"
    AutopilotPath   = $null
    AutopilotAction = "Skip"
    UnattendPath    = "C:\FFUDevelopment\unattend\unattend_x64.xml"
    UnattendAction  = "Reuse"
    WindowsArch     = "x64"      # Extracted from FFU metadata
    WindowsVersion  = "24H2"     # Extracted from FFU metadata
}
```

### Pattern 2: Selective Pipeline via Phase Skip Flags

**What:** BuildFFUVM.ps1 already has skip-phase logic for checkpoint/resume (e.g., `$skipDriverDownload`, `$skipDeploymentMedia`, `$skipUSBCreation`). USB Mode reuses this same mechanism — the `-ArtifactManifest` param sets skip flags at the top of the script, then execution falls through to USB Creation with appropriate artifacts pre-resolved.

**When to use:** Avoids duplicating the build phase infrastructure. USB Mode is effectively a checkpoint-resume where almost all phases are "already complete."

**Trade-offs:** BuildFFUVM.ps1 already has 2,404 lines. Adding USB Mode entry logic increases complexity slightly. Mitigation: the entry logic is a short early-exit block (< 50 lines) that sets skip flags and resolves paths.

**Example:**
```powershell
# Near top of BuildFFUVM.ps1, after module imports
if ($USBOnlyMode -and $ArtifactManifest) {
    $manifest = Get-Content $ArtifactManifest | ConvertFrom-Json
    $skipDriverDownload     = ($manifest.DriversAction -ne 'Rebuild')
    $skipDeploymentMedia    = ($manifest.DeployISOAction -ne 'Rebuild')
    $skipFFUCapture         = $true
    $skipVMSetup            = $true
    $skipVHDXCreation       = $true
    $DeployISO              = $manifest.DeployISOPath
    $DriversFolder          = $manifest.DriversPath
    $CopyDrivers            = ($manifest.DriversAction -ne 'Skip')
    $CopyAutopilot          = ($manifest.AutopilotAction -ne 'Skip')
    # ... resolve all artifact paths from manifest
}
```

### Pattern 3: Reduced Preflight for USB Mode

**What:** The existing `Invoke-FFUPreflight` runs ~15 checks including Hyper-V availability, ADK installation, WIMMount driver, and WinPE architecture. USB Mode does not need most of these. A new `-Mode` parameter on `Invoke-FFUPreflight` (or a separate `Invoke-USBModePreflight` function in FFU.ArtifactScanner) runs only relevant checks: disk space for USB copy, USB drive detection, and artifact path existence.

**When to use:** USB Mode runs on machines that may not be Hyper-V hosts. Failing on Hyper-V/ADK checks creates false blockers.

**Trade-offs:** Modifying `Invoke-FFUPreflight` risks regression. Preferred: add a thin `Invoke-USBModePreflight` in FFU.ArtifactScanner that calls only the safe subset of existing check functions from FFU.Preflight.

## Data Flow

### USB Mode Flow

```
User opens app in USB Mode
    ↓
UI: Scan FFUDevelopment folder (or browse path)
    ↓ calls FFU.ArtifactScanner: Find-FFUArtifacts
Artifact list displayed with metadata (size, date, arch, version)
    ↓
User sets Reuse/Rebuild/Skip per artifact
    ↓
UI: Validate choices (FFU.ArtifactScanner: Test-ArtifactCompatibility)
    e.g., warn if DeployISO arch != FFU arch
    ↓
User clicks "Build USB"
    ↓
UI: New-ArtifactManifest → write to temp JSON
    ↓
UI: Launch ThreadJob → BuildFFUVM.ps1 -USBOnlyMode -ArtifactManifest $tempPath
    ↓
BuildFFUVM.ps1: read manifest → set skip flags → resolve artifact paths
    ↓
[Optional] Invoke-USBModePreflight (disk space, USB drive check)
    ↓
[Conditional] Rebuild phases (drivers, deploy ISO) — only if Action=Rebuild
    ↓
USB Creation phase: New-DeploymentUSB (existing function, unchanged)
    ↓
FFU.Messaging → UI Monitor tab updates (same as full build)
```

### Artifact Scanning Flow

```
Find-FFUArtifacts -RootPath $FFUDevelopmentPath
    ↓
Check standard locations:
  FFU/*.ffu          → list with LastWriteTime, size
  FFU/*.iso          → deploy ISO candidates
  Drivers/           → driver folder presence + OEM subdirs
  PPKG/*.ppkg        → provisioning packages
  Autopilot/*.json   → Autopilot profiles
  unattend/unattend_*.xml → unattend files
    ↓
Get-ArtifactMetadata per FFU file:
  Mount FFU → read install.wim → DISM Get-WindowsImage
  Extract: ImageName, Architecture, Version, SPLevel
  Unmount immediately (no modification)
    ↓
Return structured ArtifactCatalog object
```

### State Management in USB Mode

```
UI-side state (same $script:uiState pattern):
  uiState.Data.currentMode       = "USB" | "FullBuild"
  uiState.Data.artifactCatalog   = [ArtifactCatalog] from scanner
  uiState.Data.artifactManifest  = [ArtifactManifest] user decisions

Pipeline-side state:
  Same $script:IsResuming pattern — USB Mode acts like "fully resumed" build
  Skip flags set immediately from manifest, no checkpoint files written
```

## Integration Points

### Modified Files — Explicit List

| File | Modification Type | What Changes |
|------|------------------|--------------|
| `BuildFFUVM_UI.xaml` | Modified | Add mode toggle RadioButtons at top of XAML. Add `TabItem Header="USB Mode"` containing artifact scanner ListView + per-artifact action ComboBoxes. Existing tabs gain `IsEnabled` binding to mode. |
| `BuildFFUVM_UI.ps1` | Modified | Mode toggle event handler. USB Mode tab: scan button handler, artifact display, manifest creation. Modified `btnRun` click handler: branches on current mode to launch USB pipeline or existing full build. |
| `BuildFFUVM.ps1` | Modified | Add `-USBOnlyMode` switch and `-ArtifactManifest` string params to param block. Add manifest-reading block (~50 lines) after module imports. No changes to existing phase code — only new skip flags set. |
| `config/ffubuilder-config.schema.json` | Modified | Add optional `USBMode` section with ArtifactManifest path and mode flag. Required for config persistence between sessions. |

### New Files — Explicit List

| File | Purpose |
|------|---------|
| `Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psd1` | Module manifest, RequiredModules: FFU.Core |
| `Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1` | Scanning, validation, metadata extraction, manifest creation |
| `Tests/Unit/FFU.ArtifactScanner.Tests.ps1` | Pester 5.x tests for scanner functions |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| UI ↔ ArtifactScanner | Direct function call in UI thread (not ThreadJob) | Scanning is read-only, fast enough for UI thread; no need for background job |
| UI ↔ BuildFFUVM.ps1 (USB mode) | Same ThreadJob + ConfigFile/ArtifactManifest JSON pattern as full build | Consistent with existing architecture |
| ArtifactScanner ↔ FFU.Core | Direct module dependency (RequiredModules) | WriteLog, error handling patterns |
| ArtifactScanner ↔ FFU.Imaging | Optional: FFU metadata extraction may call DISM functions | Only if Get-ArtifactMetadata needs DISM; alternative: use DISM.exe directly |
| New-DeploymentUSB ↔ Manifest | Via BuildFFUVM.ps1 script-scope variables (existing $using: pattern) | No change to New-DeploymentUSB needed — it reads `$DeployISO`, `$CopyDrivers`, etc. which are set by manifest-reading block |

### Key Constraint: $using: Variables in New-DeploymentUSB

`New-DeploymentUSB` runs its inner loop with `ForEach-Object -Parallel`, capturing parent-scope variables via `$using:`. These variables are set at BuildFFUVM.ps1 script scope. The manifest-reading block must populate the same variable names that `New-DeploymentUSB` already reads:

```
$DeployISO        → $using:DeployISO
$DriversFolder    → $using:DriversFolder  (note: called DriversFolder in ForEach block)
$CopyDrivers      → $using:CopyDrivers
$CopyPPKG         → $using:CopyPPKG
$PPKGFolder       → $using:PPKGFolder
$CopyUnattend     → $using:CopyUnattend
$UnattendFolder   → $using:UnattendFolder
$CopyAutopilot    → $using:CopyAutopilot
$AutopilotFolder  → $using:AutopilotFolder
$WindowsArch      → $using:WindowsArch
```

This is the critical integration point. The manifest-reading block must set all these variables, or `New-DeploymentUSB` silently skips copying optional files.

## Suggested Build Order

Dependencies drive this order — each item must be complete before the next can be tested end-to-end.

| Step | Component | Depends On | Rationale |
|------|-----------|-----------|-----------|
| 1 | `FFU.ArtifactScanner` module (core functions) | FFU.Core (existing) | Foundation — everything else needs the scanner. Can be built and tested in isolation with mock filesystem. |
| 2 | `FFU.ArtifactScanner` metadata extraction | FFU.ArtifactScanner core | Potentially complex (DISM FFU mount) — validate approach early, separate from UI. |
| 3 | Config schema: add `USBMode` section | Nothing | Trivial standalone change. Required before UI or pipeline reads/writes config. |
| 4 | `BuildFFUVM.ps1`: add `-USBOnlyMode` + manifest-reading block | FFU.ArtifactScanner (for manifest structure), config schema | Sets up pipeline contract. Can be tested CLI-only before any UI work. |
| 5 | XAML: mode toggle + USB Mode tab skeleton | Nothing code-dependent | Pure XAML, can be developed in parallel with steps 1-4 once structure is agreed. |
| 6 | `BuildFFUVM_UI.ps1`: mode toggle handler + scanner invocation | XAML (step 5), FFU.ArtifactScanner (step 1) | Wires scanner into UI. |
| 7 | `BuildFFUVM_UI.ps1`: manifest creation + USB Mode launch | Steps 4, 6 | Final end-to-end integration: UI → manifest → pipeline → USB. |
| 8 | Reduced preflight for USB Mode | FFU.ArtifactScanner or FFU.Preflight | Polish step — prevents false pre-flight failures on non-Hyper-V machines. |
| 9 | Tests | All above | Pester tests for FFU.ArtifactScanner + integration tests for manifest → pipeline flow. |

## Anti-Patterns

### Anti-Pattern 1: Creating a Second Entry-Point Script

**What people do:** Create `BuildUSBFromExisting.ps1` as a parallel orchestrator to `BuildFFUVM.ps1`.

**Why it's wrong:** Duplicates the USB creation logic (Get-USBDrive, New-DeploymentUSB), the messaging setup, module import sequence, and error handling infrastructure. Two scripts diverge immediately as either gets bug fixes. The existing comment at line 1152 of BuildFFUVM.ps1 explicitly documents why USB functions must stay in-script.

**Do this instead:** Add `-USBOnlyMode` switch to BuildFFUVM.ps1. The USB Mode execution path is ~50 lines of manifest-reading code plus skip flags — the rest of the script's infrastructure is reused unchanged.

### Anti-Pattern 2: Moving New-DeploymentUSB to a Module

**What people do:** Extract `New-DeploymentUSB` and `Get-USBDrive` into `FFU.USB` module for cleanliness.

**Why it's wrong:** `New-DeploymentUSB` uses `ForEach-Object -Parallel` with numerous `$using:` variables referencing script-scope state from BuildFFUVM.ps1. Module encapsulation breaks this pattern — the `$using:` vars would reference the module's scope, not the caller's. The existing ARCHITECTURE comment at line 1152 documents this exact constraint.

**Do this instead:** Leave these functions in BuildFFUVM.ps1. The manifest-reading block sets the required script-scope variables before `New-DeploymentUSB` is called.

### Anti-Pattern 3: Running Artifact Scanning in a Background Job

**What people do:** Launch `Find-FFUArtifacts` in a ThreadJob to keep UI responsive.

**Why it's wrong:** Artifact scanning is `Get-ChildItem` over a local directory — sub-second for typical FFUDevelopment paths. Adding ThreadJob plumbing adds complexity with no benefit. FFU metadata extraction (DISM mount) may take 5-10 seconds but only runs on user request.

**Do this instead:** Run `Find-FFUArtifacts` synchronously in the UI event handler. For FFU metadata extraction specifically, use a dedicated async call (Dispatcher.InvokeAsync or a targeted background job) only for that step, with a progress indicator.

### Anti-Pattern 4: Reimplementing USB Creation Logic

**What people do:** Write new partition/format/copy logic in FFU.ArtifactScanner for the "USB from existing" case.

**Why it's wrong:** `New-DeploymentUSB` (lines 1315-1549 of BuildFFUVM.ps1) is mature, parallel-capable, handles multiple drives, has robocopy retry logic, ISO mount/unmount lifecycle, error handling, and cleanup registration. It was heavily updated in v1.9.x and v1.10.0.

**Do this instead:** Route USB Mode through the existing `New-DeploymentUSB` function by setting the required script-scope variables from the artifact manifest.

## Scaling Considerations

This is a desktop tool with at most a handful of concurrent users (one build per machine). Scaling is not relevant. The relevant "scale" question is: how many USB drives can be written in parallel?

| USB Drives | Architecture Note |
|------------|------------------|
| 1-5 drives | Default: `$MaxUSBDrives = 5`, `ForEach-Object -Parallel -ThrottleLimit 5` |
| 6+ drives | User sets `MaxUSBDrives = 0` to process all discovered drives |

USB Mode does not change this behavior — it inherits the same parallel USB creation capability.

## Sources

- `BuildFFUVM.ps1` — lines 1150-1553 (USB function block with architectural comment)
- `BuildFFUVM.ps1` — lines 5086-5220 (PHASE: Deployment Media, PHASE: USB Creation)
- `BuildFFUVM_UI.ps1` — lines 560-660 (ThreadJob launch pattern, buildParams construction)
- `BuildFFUVM_UI.xaml` — lines 820-906 (USB Drive section XAML structure)
- `Modules/FFU.Preflight/FFU.Preflight.psm1` — function list (15 check functions)
- `.planning/PROJECT.md` — v1.11.0 milestone requirements
- `config/ffubuilder-config.schema.json` — existing USB-related config properties

---
*Architecture research for: FFU Builder v1.11.0 — USB from Existing Components*
*Researched: 2026-03-12*
