# Feature Research

**Domain:** USB deployment media creation from pre-existing build artifacts (Windows deployment tooling)
**Researched:** 2026-03-12
**Confidence:** HIGH — based on direct codebase analysis of existing implementation, not speculation

## Context: What Already Exists

This is a subsequent milestone. The following are already implemented and not in scope:

- `New-DeploymentUSB` function with parallel USB formatting via `ForEach-Object -Parallel`
- `USBImagingToolCreator.ps1` standalone script
- Artifact copy flags: `CopyFFU`, `CopyDrivers`, `CopyPPKG`, `CopyUnattend`, `CopyAutopilot`, `CopyAdditionalFFUFiles`
- USB drive selection (model+serial filtering via `USBDriveList` hashtable, `MaxUSBDrives` throttle)
- WinPE deployment ISO mounting and boot partition copying (robocopy)
- Deploy partition content assembly (FFU, Drivers, PPKG, Unattend, Autopilot folders)
- WPF UI with 9 tabs: Home, VM Settings, Windows Settings, Updates, Applications, M365 Apps/Office, Drivers, Build, Monitor
- Config schema with `BuildUSBDrive`, `CopyDrivers`, `CopyPPKG`, `CopyUnattend`, `CopyAutopilot`, `AdditionalFFUFiles`

**The new milestone adds:** A USB Mode that creates deployment USB from existing artifacts without running the full build pipeline.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume this mode has. Missing these makes the mode feel like a half-measure.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Mode toggle (Full Build vs USB Mode) | Users expect a clear top-level switch — not buried in a config flag | LOW | RadioButton or tab-level toggle in WPF; drives visibility of Full Build vs USB Mode panels |
| Auto-detect artifacts from FFUDevelopmentPath | The standard folder structure already has FFU/, Drivers/, PPKG/, Unattend/, Autopilot/ — users expect the tool to find what's there | LOW | `Get-ChildItem` scans on known relative paths; already partially done by `New-DeploymentUSB` for FFU selection |
| Show found artifacts with path and file size | Any deployment tool shows what it found before acting on it | LOW | ListView/DataGrid in WPF; file size from `[System.IO.FileInfo]` |
| Artifact presence/absence status | Users need to know which components are missing before committing to USB creation | LOW | Boolean per-artifact: FFU found, WinPE ISO found, Drivers present, etc. |
| Select which artifacts to include on USB | Not all builds need all artifacts — Autopilot, PPKG, Unattend are optional | LOW | Checkboxes per artifact type, already have UI pattern from Build tab |
| Browse to arbitrary artifact paths | Users store artifacts outside FFUDevelopmentPath — must be able to point at external locations | MEDIUM | OpenFileDialog / FolderBrowserDialog per artifact; WPF pattern is established (5 existing Browse... buttons in UI) |
| WinPE ISO required — block if missing | USB creation fails without a boot partition source — must be a hard blocker with actionable message | LOW | `Test-Path $DeployISO` gate before allowing USB creation to start |
| USB drive detection and selection | Parallel to existing `Get-RemovableDrive` behavior — users expect the same USB picker | LOW | Reuse existing USB drive list UI from Build tab (`lstUSBDrives`, `chkSelectSpecificUSBDrives`) |
| Progress feedback during USB creation | Long-running copy operation requires visible progress | LOW | Reuse existing Monitor tab log streaming; `New-DeploymentUSB` already calls `WriteLog` throughout |
| Config persistence for USB Mode paths | Users don't want to re-enter artifact paths on every session | MEDIUM | Extend config schema with USB Mode artifact path overrides; config migration if schema version bumps |

### Differentiators (Competitive Advantage)

Features that make this implementation stand out from a simple "just run the script with flags" workflow.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Per-artifact reuse/rebuild/skip decision | Users can say "reuse this FFU, rebuild the WinPE ISO, skip PPKG" — selective pipeline execution without a full rebuild | HIGH | Requires artifact state tracking, selective Invoke-BuildPhase wiring, and UI to present the three-way choice per artifact |
| Metadata extraction and display | Show FFU Windows version, SKU, architecture, file date — lets user verify they're picking the right image | MEDIUM | FFU metadata: DISM `Get-WindowsImage` on mounted FFU or `dism /get-imageinfo`; WinPE ISO: file timestamp only; Drivers: folder size and model count |
| Cross-artifact compatibility validation | Warn if FFU is x64 but WinPE ISO is arm64 — prevents mismatched deployments | MEDIUM | Architecture extraction from FFU via DISM; architecture from WinPE ISO folder structure (`boot/efi/boot/bootaa64.efi` vs `bootx64.efi`); compare and surface warning |
| Staleness indicator per artifact | Show artifact age relative to a configurable threshold (e.g., "FFU is 47 days old") | LOW | `[DateTime]::Now - [System.IO.FileInfo]::LastWriteTime`; already have Apps.iso staleness detection pattern in FFU.Apps |
| Selective pipeline execution | When user marks an artifact for rebuild, only run the phases needed to produce that artifact — not a full build | HIGH | Requires Invoke-BuildPhase skip logic; checkpoint/resume integration (FFU.Checkpoint already exists); most complex feature in milestone |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Automatic rebuild of stale artifacts | "Just rebuild anything older than N days automatically" | Silently runs the full build pipeline without user confirmation — can take 40+ minutes unexpectedly; masks the intent of USB Mode which is fast path | Show staleness indicator and let user explicitly choose rebuild; never auto-trigger rebuilds |
| Merge/combine multiple FFUs into one USB | "I want all my FFU variants on one drive" | Already handled by `CopyAdditionalFFUFiles` + `AdditionalFFUFiles` array in config; building a separate merge workflow duplicates existing behavior | Use existing `CopyAdditionalFFUFiles` mechanism; surface it in USB Mode UI |
| Cloud/network artifact sources | "Pull the FFU from a file share or Azure Blob" | Introduces authentication complexity, network error states, and partial download recovery — scope explosion for a UI mode change | Document that users should copy artifacts locally first; resilient download is already in FFU.Common.Download for build pipeline |
| Artifact version history / rollback | "Show me the last 3 FFU builds so I can pick" | Requires a build history database not present in the project | File picker showing files sorted by date covers 90% of the use case; AdditionalFFUFiles handles multi-FFU scenarios |
| USB Mode with no WinPE ISO (skip boot partition) | "I just want to put the FFU on a pre-formatted drive" | The USB structure requires a boot partition with WinPE files to function as a deployment tool — skipping it produces a non-bootable drive | If user has a pre-formatted USB, ApplyFFU.ps1 directly is the right tool, not USBImagingToolCreator |

---

## Feature Dependencies

```
Mode Toggle (Full Build vs USB Mode)
    └──gates──> Artifact Scanner (only meaningful in USB Mode)
                    └──feeds──> Artifact Status Display
                    └──feeds──> Per-Artifact Decision UI (reuse/rebuild/skip)
                                    └──requires──> WinPE ISO Required Check (blocking gate)
                                    └──requires──> USB Drive Selection (reuse existing)
                                    └──requires──> Selective Pipeline Execution (if rebuild chosen)
                                                       └──requires──> FFU.Checkpoint (already exists)
                                                       └──requires──> Invoke-BuildPhase (already exists)

Artifact Scanner
    └──auto-detect──> Standard paths (FFUDevelopmentPath/FFU, /Drivers, /PPKG, /Unattend, /Autopilot, /WinPE_*.iso)
    └──enhanced-by──> Browse to Arbitrary Paths (overrides auto-detected paths per artifact)

Metadata Extraction
    └──requires──> Artifact Scanner (must find artifact before extracting metadata)
    └──enhances──> Compatibility Validation (metadata provides arch/version for cross-check)

Config Persistence for USB Mode paths
    └──requires──> Config Migration (FFU.ConfigMigration already exists — just add new fields)
```

### Dependency Notes

- **Mode Toggle gates Artifact Scanner:** The scanner should only run when USB Mode is active — running scans during Full Build adds latency with no user value.
- **WinPE ISO is a hard blocker:** `New-DeploymentUSB` mounts the ISO before the parallel USB loop. Without it the entire operation fails. Must be surfaced as a pre-check, not a runtime error.
- **Selective Pipeline Execution requires Invoke-BuildPhase:** The existing phase wrapper in BuildFFUVM.ps1 provides skip/continue semantics. Selective rebuild hooks into this without new infrastructure.
- **Browse overrides auto-detect:** Per-artifact path overrides from Browse dialogs should not reset when the user switches tabs — store in the USB Mode config state.
- **Metadata extraction is enhancement, not blocker:** USB creation does not depend on metadata being displayed. It can ship without metadata display and add it as a follow-up.

---

## MVP Definition

### Launch With (v1 — v1.11.0)

Minimum viable product: allows USB creation from existing artifacts without a full build.

- [ ] Mode toggle in WPF UI — "Full Build" vs "USB Mode" at top of Build tab or as a tab — controls panel visibility
- [ ] Artifact scanner — auto-detect from FFUDevelopmentPath standard locations on mode activation
- [ ] Artifact status display — list found/missing artifacts with path and file size
- [ ] Per-artifact include/exclude checkboxes — maps directly to existing `CopyFFU`, `CopyDrivers`, `CopyPPKG`, `CopyUnattend`, `CopyAutopilot` flags
- [ ] Browse-to-path overrides per artifact — OpenFileDialog for FFU/.iso, FolderBrowserDialog for Drivers/PPKG/Unattend/Autopilot
- [ ] WinPE ISO required pre-check — blocking validation before USB creation starts, with actionable message
- [ ] USB drive selection reuse — same `lstUSBDrives` control from Build tab
- [ ] Wire through to existing `New-DeploymentUSB` — USB Mode is a thin configuration layer over the existing assembly function

### Add After Validation (v1.x)

- [ ] Artifact metadata display (FFU: Windows version/SKU/arch, WinPE ISO: file date, Drivers: model count) — add when users ask "what version is this FFU?"
- [ ] Cross-artifact compatibility validation (arch mismatch warning) — add when users report deploying wrong-arch combinations
- [ ] Staleness indicators — add when users ask how to know if their artifacts are current
- [ ] Config persistence for USB Mode artifact path overrides — add when users report re-entering paths every session

### Future Consideration (v2+)

- [ ] Selective pipeline execution (rebuild individual artifacts) — high complexity, requires deep Invoke-BuildPhase integration; defer until USB Mode adoption validates the need
- [ ] Saved USB Mode profiles (named configurations per deployment scenario) — defer until users demonstrate multi-profile workflows

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Mode toggle | HIGH | LOW | P1 |
| Artifact scanner (auto-detect) | HIGH | LOW | P1 |
| Artifact status display | HIGH | LOW | P1 |
| Per-artifact include/exclude | HIGH | LOW | P1 |
| Browse-to-arbitrary-paths | HIGH | LOW-MEDIUM | P1 |
| WinPE ISO pre-check (blocking gate) | HIGH | LOW | P1 |
| USB drive selection (reuse existing) | HIGH | LOW | P1 |
| Wire to New-DeploymentUSB | HIGH | LOW | P1 |
| Metadata extraction and display | MEDIUM | MEDIUM | P2 |
| Compatibility validation (arch) | MEDIUM | MEDIUM | P2 |
| Staleness indicators | LOW | LOW | P2 |
| Config persistence for paths | MEDIUM | MEDIUM | P2 |
| Selective pipeline execution | HIGH | HIGH | P3 |
| Saved USB Mode profiles | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for v1.11.0 launch — the mode is not viable without these
- P2: Should have — add in follow-up patches if v1.11.0 slips
- P3: Nice to have — future milestone

---

## Implementation Dependencies on Existing Code

| New Feature | Depends On (Existing) | Status |
|-------------|----------------------|--------|
| Mode toggle | WPF tab/panel visibility logic in FFUUI.Core | Exists — established pattern |
| Artifact scanner | `Get-ChildItem` on known paths, `Test-Path` | Trivial — no new infrastructure |
| Browse-to-path | OpenFileDialog / FolderBrowserDialog | 5 existing Browse... buttons in UI (pattern established) |
| WinPE ISO pre-check | `$DeployISO` variable, `Test-Path` | `DeployISO` already resolved at line 1842 of BuildFFUVM.ps1 |
| USB drive selection | `lstUSBDrives`, `chkSelectSpecificUSBDrives` controls | Exists in Build tab — may need to share or duplicate control references |
| Wire to New-DeploymentUSB | `New-DeploymentUSB` function at line 1315 of BuildFFUVM.ps1 | Exists — needs USB Mode to set correct parameters and skip build phases |
| Config persistence | `FFU.ConfigMigration`, config schema | Schema extension is straightforward; migration is a known pattern |
| Metadata extraction | DISM `Get-WindowsImage` | Available; potentially slow for large FFUs — consider async or caching |

---

## Sources

- Direct codebase analysis: `BuildFFUVM.ps1` lines 1155-1549 (`Get-RemovableDrive`, `New-DeploymentUSB`)
- Direct codebase analysis: `USBImagingToolCreator.ps1` (standalone USB creation)
- Direct codebase analysis: `BuildFFUVM_UI.xaml` (existing tab structure, control names)
- Direct codebase analysis: `config/ffubuilder-config.schema.json` (existing artifact config properties)
- Direct codebase analysis: `FFUUI.Core/FFUUI.Core.Config.psm1` (`USBDriveList` loading/saving)
- Project context: `.planning/PROJECT.md` (v1.11.0 milestone goals)

---
*Feature research for: USB from Existing Components — FFU Builder v1.11.0*
*Researched: 2026-03-12*
