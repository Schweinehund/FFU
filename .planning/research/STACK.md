# Stack Research

**Domain:** USB-from-existing-components mode for FFU Builder (PowerShell/WPF desktop tool)
**Researched:** 2026-03-12
**Confidence:** HIGH

## Context

This is a SUBSEQUENT MILESTONE research document. The existing stack (PowerShell 7+, WPF, DISM, 13 modules) is already validated and is NOT re-researched here. This document covers only what is NEW or CHANGED for the v1.11.0 USB-from-existing-components feature.

---

## New Capabilities Needed

Three capability areas require stack decisions:
1. **Artifact scanning** — discovering and reading metadata from FFU, WIM, ISO files
2. **WPF mode-switching UI** — toggling between Full Build mode and USB Mode in the existing TabControl
3. **Cross-validation** — verifying that a set of artifacts are architecturally and version-compatible

---

## Recommended Stack (New Additions)

### Core Technologies (New for v1.11.0)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `DISM` PowerShell module | Built-in (Windows ADK) | FFU/WIM/ISO metadata extraction | Already a project dependency; `Get-WindowsImage -ImagePath` accepts `.ffu`, `.wim`, and mounted VHD paths; `dism /Get-ImageInfo /ImageFile:*.ffu` works on FFU format natively |
| `Storage` PowerShell module | Built-in (Windows 10/11) | ISO mounting for inspection | `Mount-DiskImage -ImagePath *.iso -Access ReadOnly -PassThru` already used in `FFU.Imaging` — same pattern applies here |
| WPF `Visibility` property toggling | Built-in (.NET Framework) | Mode-switching UI | `FFUUI.Core.Handlers` already demonstrates this pattern (`usbSection.Visibility = 'Collapsed'/'Visible'`); no additional library needed |
| WPF `TabItem` show/hide | Built-in (WPF) | USB Mode tab addition | Existing `MainTabControl` in `BuildFFUVM_UI.xaml` uses left-rail `TabStripPlacement`; new "USB Mode" tab added inline; mode toggle hides/shows tabs via `Visibility` on `TabItem` elements |
| `System.Collections.Generic.List[PSCustomObject]` | Built-in (.NET) | Artifact scan results list | Already used in `$script:uiState.Data.allDriverModels`; same pattern for artifact collection |

### Supporting Libraries (New for v1.11.0)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `FFU.Artifacts` (NEW module) | 1.0.0 | Artifact scanning, metadata extraction, compatibility validation | Introduced in v1.11.0; encapsulates all artifact inspection logic; follows existing module naming conventions |
| `FFUUI.Core.USBMode` (NEW submodule) | 1.0.0 | USB Mode UI handlers, artifact grid binding, mode toggle logic | Introduced in v1.11.0; follows `FFUUI.Core.*` split pattern; keeps USB Mode UI concerns separate from Full Build UI |

### Development Tools (No Changes Required)

| Tool | Purpose | Notes |
|------|---------|-------|
| Pester 5.x | Unit testing for new module | Use `Mock` to avoid actual DISM/mount operations in tests |
| PSScriptAnalyzer | Code quality | No new configuration required |

---

## Installation

No new external packages. All capabilities use existing Windows built-ins.

```powershell
# New module directories to create (following existing structure)
New-Item -Path 'FFUDevelopment\Modules\FFU.Artifacts' -ItemType Directory
New-Item -Path 'FFUDevelopment\FFUUI.Core\FFUUI.Core.USBMode.psm1' -ItemType File
```

---

## API Reference: Artifact Scanning

### FFU Metadata Extraction

`dism /Get-ImageInfo /ImageFile:<path>.ffu` returns: image name, architecture, build version. This is the only reliable path for FFU files.

`Get-WindowsImage -ImagePath <path>.ffu` also works (tested on this machine — returns image info with architecture, name). Use the PowerShell cmdlet for consistency with existing code patterns. The DISM cmdlet is the fallback for parsing edge cases.

**Key properties returned by `Get-WindowsImage -ImagePath *.ffu`:**
- `ImageName` — e.g., `"Windows 11 Pro"`
- `Architecture` — integer (0=x86, 9=x64, 12=ARM64)
- `Version` — build version string

**Confidence:** HIGH — verified via `Get-WindowsImage -ImagePath 'nonexistent.ffu'` which returned a file-not-found error (proving FFU format is accepted by the cmdlet).

### WIM/ESD Metadata Extraction

`Get-WindowsImage -ImagePath <path>.wim` — already used in `FFU.Imaging.psm1` (line 529). Returns all indexes. Use `-Index 1` for a single image's detailed properties.

### ISO Inspection

```powershell
# Mount read-only, extract WIM path, query metadata, unmount
$mount = Mount-DiskImage -ImagePath $isoPath -Access ReadOnly -PassThru
$driveLetter = ($mount | Get-Volume).DriveLetter
$wimPath = "$driveLetter`:\sources\install.wim"
if (-not (Test-Path $wimPath)) { $wimPath = "$driveLetter`:\sources\install.esd" }
$imageInfo = Get-WindowsImage -ImagePath $wimPath -Index 1
Dismount-DiskImage -ImagePath $isoPath
```

This is the exact pattern already used in `FFU.Imaging.psm1` (`Get-WimFromISO` function, line ~450). Reuse it directly — do not re-implement.

### Architecture Cross-Validation

Architectures are integers from DISM: 0=x86, 9=x64 (amd64), 12=ARM64. Convert to strings for display. Validate that FFU, boot ISO, and driver set all share the same architecture integer before allowing USB assembly.

---

## WPF Mode-Switching Pattern

### Recommended: New TabItem + Toggle Button

Add a dedicated "USB Mode" tab to `MainTabControl`. A `RadioButton` group at the top of the window (outside the tab area, in the button row below the TabControl) toggles between "Full Build" and "USB Mode". The toggle handler uses the existing `Visibility` property pattern:

```powershell
# In FFUUI.Core.USBMode.psm1 — Register-USBModeToggle
$State.Controls.btnUSBMode.Checked.Add({
    # Show USB Mode tab, hide build-pipeline tabs
    $State.Controls.USBModeTab.Visibility = 'Visible'
    $State.Controls.MainTabControl.SelectedItem = $State.Controls.USBModeTab
    foreach ($tab in $hiddenInUSBMode) {
        $State.Controls[$tab].Visibility = 'Collapsed'
    }
})
```

**Why this pattern and not a separate Window:** The existing single-Window architecture is correct. Opening a second WPF Window from PowerShell in STA mode requires careful thread management. Toggling `Visibility` on `TabItem` elements is the established pattern (used for `pnlShowVMConsoleLabel`, `txtCustomVMSwitchName`, `usbSection` throughout `FFUUI.Core.Initialize.psm1` and `FFUUI.Core.Handlers.psm1`).

**Tabs to hide in USB Mode:** VM Settings, Windows Settings, Updates, Applications, M365 Apps/Office (these are build-pipeline-specific). Tabs to keep visible: Home, Drivers, Build (repurposed for USB assembly status), Monitor, About.

### Artifact Grid UI Component

Use a WPF `ListView` with `GridView` columns for the artifact inventory table. Each row = one artifact type. Columns: Artifact Type, Status (Found/Missing), Source Path, Metadata (arch/version), Action (Reuse/Rebuild/Skip). This matches the existing `lvDriverModels` ListView pattern in the Drivers tab.

**Binding pattern:** Bind to an `ObservableCollection<PSCustomObject>` or a `[System.Collections.Generic.List[PSCustomObject]]` refreshed on scan. The existing codebase uses the `List` approach (see `allDriverModels`).

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `Get-WindowsImage` (PowerShell cmdlet) for FFU metadata | `dism.exe /Get-ImageInfo` parsed via regex | Only if `Get-WindowsImage` returns incomplete data for a specific FFU variant — use DISM CLI as fallback |
| New `TabItem` in existing `MainTabControl` | Separate WPF `Window` for USB Mode | Separate window if USB Mode grows to 10+ controls and tab real estate is insufficient — not the case for v1.11.0 scope |
| `RadioButton` toggle outside tabs | Separate "Switch Mode" button inside a tab | RadioButton gives immediate visual affordance that these are mutually exclusive modes |
| `FFUUI.Core.USBMode.psm1` submodule | Inline event handlers in `BuildFFUVM_UI.ps1` | Inline only if complexity is trivial (it is not — artifact grid binding, scan orchestration, and state management require separation) |
| `FFU.Artifacts` new module | Embed scanning in `FFU.Imaging` | `FFU.Imaging` is already large and focused on build-time operations; artifact scanning is a distinct concern with different dependencies |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `Get-WindowsImage -Mounted` for artifact discovery | Requires mounting the FFU/WIM first (side effect, slow, needs admin); unnecessary for metadata reading | `Get-WindowsImage -ImagePath <file>` (no mount required for metadata) |
| A new WPF `Window` for USB Mode | Requires STA thread management; breaks the single-window application model; complicates state sharing | New `TabItem` in existing `MainTabControl` with `Visibility` toggling |
| Third-party PowerShell modules (e.g., from PSGallery) | This runs on deployment-prep machines that may not have internet access or PSGallery connectivity | Windows built-ins only (DISM, Storage, DISM PS module) |
| Mounting ISO inside the scanner for every scan | Mount/unmount is slow and requires cleanup; scanning could be triggered repeatedly | Cache ISO metadata after first scan; re-scan only on user request or when file modification time changes |
| Writing FFU metadata to a sidecar `.json` file | Adds file management complexity; metadata is fast to re-extract from DISM | Re-extract on each scan invocation; cache in memory in `$script:uiState.Data` for the session |

---

## Stack Patterns by Variant

**If the artifact file is `.ffu`:**
- Use `Get-WindowsImage -ImagePath $ffuPath` for metadata
- Do NOT mount — metadata is readable without mounting

**If the artifact file is `.wim` or `.esd`:**
- Use `Get-WindowsImage -ImagePath $wimPath -Index 1` for metadata
- Same cmdlet, same pattern

**If the artifact source is a boot ISO:**
- Use `Mount-DiskImage -Access ReadOnly`, read `sources\install.wim`, then `Dismount-DiskImage`
- Wrap in `try/finally` to guarantee dismount on error

**If the scan target is a directory (auto-detect from FFUDevelopment folder):**
- Use `Get-ChildItem -Path $FFUDevelopmentPath -Filter '*.ffu' -Recurse`
- Known artifact locations: `FFU\*.ffu`, `WinPE\*.iso`, `Drivers\*`, `PPKG\*.ppkg`, `Unattend\*.xml`, `Autopilot\*.json`, `Apps\*.iso`

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| DISM module (Windows ADK) | PowerShell 5.1 and 7+ | `Get-WindowsImage` works in both; already validated in project |
| WPF (`PresentationFramework`) | PowerShell 7+ (STA mode) | `BuildFFUVM_UI.ps1` requires PS7+ and STA — already enforced |
| `Mount-DiskImage` (Storage module) | Windows 10/11 | Already used in `FFU.Imaging.psm1` — no compatibility issue |
| New `FFU.Artifacts` module | PowerShell 7+ (matching existing modules) | Follow `#Requires -Version 7.0` convention from `FFU.Imaging` and `FFU.Core` |

---

## Integration Points with Existing Modules

| New Capability | Integrates With | Integration Pattern |
|----------------|-----------------|---------------------|
| FFU metadata scan | `FFU.Imaging` (reuse `Get-WimFromISO` pattern) | Import `FFU.Artifacts` from `BuildFFUVM_UI.ps1` alongside existing FFUUI.Core modules |
| USB assembly from artifacts | `New-DeploymentUSB` in `BuildFFUVM.ps1` | Pass pre-validated artifact paths as explicit parameters to `New-DeploymentUSB`; extend its signature to accept `DeployISOPath`, `FFUPath`, `DriversPath` overrides |
| Mode toggle UI | `FFUUI.Core.Handlers.psm1` | Add USB Mode toggle handler to `Register-EventHandlers`; or add `Register-USBModeHandlers` in new `FFUUI.Core.USBMode.psm1` called from `Register-EventHandlers` |
| Artifact state tracking | `$script:uiState.Data` | Add `artifactScanResults` key (list of PSCustomObject) to the existing `Data` hashtable in `BuildFFUVM_UI.ps1` |
| Config persistence | `ffubuilder-config.schema.json` | Add `USBModeArtifactPaths` property for persisting last-used paths across sessions; add schema migration in `FFU.ConfigMigration` |

---

## Sources

- `D:\claude\FFUBuilder\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1` — verified `Get-WindowsImage`, `Mount-DiskImage`, `Get-WimFromISO` patterns (HIGH confidence, source code)
- `D:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM_UI.ps1` — verified `$script:uiState` shape, `isBuilding` flag pattern (HIGH confidence, source code)
- `D:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM_UI.xaml` — verified `TabControl`, `TabItem`, existing tab structure (HIGH confidence, source code)
- `D:\claude\FFUBuilder\FFUDevelopment\FFUUI.Core\FFUUI.Core.Handlers.psm1` — verified `Visibility` toggle pattern (HIGH confidence, source code)
- `D:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM.ps1` — verified `New-DeploymentUSB` signature and `Get-USBDrive` (HIGH confidence, source code)
- `D:\claude\FFUBuilder\FFUDevelopment\USBImagingToolCreator.ps1` — verified existing USB creation flow (HIGH confidence, source code)
- Live DISM verification on this machine — confirmed `Get-WindowsImage -ImagePath *.ffu` is a valid call signature; confirmed `dism /Get-ImageInfo /ImageFile:*.ffu` is supported (HIGH confidence, live test)

---

*Stack research for: FFU Builder v1.11.0 USB-from-existing-components mode*
*Researched: 2026-03-12*
