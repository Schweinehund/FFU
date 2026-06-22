# FFU Builder Fork - Changelog

**Fork Branch:** `feature/improvements-and-fixes`
**Upstream Repository:** https://github.com/rbalsleyMSFT/FFU/tree/UI_2510
**Versioning:** [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.BUILD)

This changelog documents all enhancements and fixes made in this fork, separate from the upstream FFU project.

---

## [1.11.0] - 2026-06-22

### Phase 50: Selective Rebuild Pipeline (REBUILD-01/02/03)

Implements the Selective Rebuild Pipeline for USB Mode, allowing users to control exactly which artifacts are rebuilt versus reused when creating deployment USB drives. Instead of always rebuilding all artifacts from scratch, users can selectively mark individual artifacts as Reuse, Rebuild, or Skip — enabling fast iteration when only one component (e.g., Drivers) has changed.

#### Changes

- **REBUILD-01: Per-artifact disposition ComboBox** — Replaces the binary include checkbox on each USB Mode artifact card with a disposition ComboBox. Item sets are tier-appropriate per artifact type:
  - FFU card: single disabled "Reuse" item + helper text ("To rebuild the OS image, switch to Full Build")
  - WinPE Deploy ISO: Reuse / Rebuild (no Skip — required artifact)
  - Drivers and Applications ISO: Reuse / Rebuild / Skip (full control)
  - Provisioning Package, Unattend.xml, Autopilot Profile: Reuse / Skip
- **REBUILD-02: Selective per-phase rebuild execution** — `New-DeploymentUSB` reads each artifact's Disposition from config and executes only the rebuild phases that are marked Rebuild. Drivers rebuild reuses `Invoke-ParallelProcessing` with the `DownloadDriverByMake` action; AppsISO rebuild copies the ISO from the Apps ISO path; DeployISO rebuild recreates WinPE media. Reused artifacts are copied from their source paths without rebuilding. Rebuilt and reused artifacts combine into the final USB.
- **REBUILD-03: 4-status artifact scanner UI + Disposition config round-trip**
  - `Invoke-USBArtifactScan` renders four status states: Found (Green), Degraded/zero-byte (DarkOrange with warning TextBlock), Error (Red), Missing (Gray)
  - `Build-UIConfiguration` reads `usb{Type}Disposition` ComboBox `SelectedItem.Tag` for all 7 artifact types and persists to config
  - `Update-UIFromConfig` restores Disposition by `ComboBoxItem.Tag` match; `PSObject.Properties.Match('Disposition')` guard provides backward-compatibility with pre-Phase-50 configs
  - `Include` field completely removed from USB artifact save/restore (D-01)
  - `isLoadingConfig` flag prevents `SelectionChanged` from triggering premature scans during config load (Pitfall 3)

#### Testing

- `Tests/Unit/SelectiveRebuild.Tests.ps1` — 30 Pester tests for BuildFFUVM.ps1 Disposition-driven copy gate
- `Tests/Unit/USBOnlyMode.Tests.ps1` — 77 Pester tests for New-DeploymentUSB pipeline
- `Tests/Unit/FFUUI.Core.Handlers.Tests.ps1` — 52 Pester tests for Invoke-USBArtifactScan (4-status rendering)
- `Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1` — 53 Pester tests for Build-UIConfiguration disposition round-trip
- `Tests/Unit/FFU.ArtifactScanner.Tests.ps1` — 63 Pester tests for artifact discovery and metadata
- All 275 Phase 50 tests pass (0 failures)

#### Files Modified

- `FFUDevelopment/BuildFFUVM.ps1` — Disposition-driven copy gate in USB Mode path
- `FFUDevelopment/BuildFFUVM_UI.ps1` — 7 disposition ComboBoxes in USB Mode tab
- `FFUDevelopment/BuildFFUVM_UI.xaml` — XAML markup for disposition ComboBox controls
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` — Invoke-USBArtifactScan 4-status rendering
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` — Build-UIConfiguration + Update-UIFromConfig disposition round-trip
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1` (v0.0.21 with Phase 50 release notes)
- `FFUDevelopment/version.json` (1.10.3 → 1.11.0)

#### Requirements Closed

- REBUILD-01: Per-artifact Reuse/Rebuild/Skip disposition control
- REBUILD-02: Selective per-phase rebuild execution from cold USB-Mode start
- REBUILD-03: Combined rebuilt + reused artifact assembly into final USB

#### Main version

- **Main version:** 1.10.3 → 1.11.0 (MINOR — new user-facing Selective Rebuild Pipeline feature)

---

## [1.10.2] - 2026-06-21

### Upstream Sync — High-Impact Bug-Fix Bundle

Ported self-contained, high-impact fixes from upstream `rbalsleyMSFT/FFU` (branch `UI`) identified in the 2026-06-21 upstream sync audit (`.planning/reports/upstream-sync-audit-2026-06-21.md`). Larger upstream items (Windows SKU refresh-after-fallback `5aaa1ad`, SerialNumber→UniqueId migration `417be73`, deploy-time 8-OEM detection `d6688de`, LTSC driver normalization `04dfb5f`, ADK BCDBoot `6c0ee8a`, Win10 LTSC in-VM CU `42b0b0c`) were deferred to dedicated phases because they are multi-file refactors and/or config-breaking.

#### Changes

- **MSI path quoting (upstream `2a77cf1`):** Added `Format-MsiArguments` to `Apps/Orchestration/Install-Win32Apps.ps1`. Auto-quotes unquoted `/i <path>.msi` paths in msiexec arguments so Win32 MSI apps with spaces in their path install reliably. Invoked in `Install-Applications` before process dispatch.
- **Disk size in VHDX cache validation (upstream `96603f0`):** Added `[uint64]$Disksize` to `VhdxCacheItem`; cache lookup now rejects a cached VHDX when the requested `Disksize` differs (or is missing/invalid in the cached config), and the save path persists `Disksize`. Prevents silently reusing a wrongly-sized cached image.
- **Defender Windows Security Platform delay (upstream `c6088d9`):** Seed the in-VM Defender update command with `Start-Sleep -Seconds 30` to let AppxSVC / Windows Security Platform finish installing in audit mode before applying Defender updates (prevents intermittent failures).
- **USB detection hardening (upstream `6df32b6`, `63ef35a`):** Replaced deprecated `Get-WmiObject -Class Win32_DiskDrive` with `Get-CimInstance -ClassName Win32_DiskDrive` in `Get-USBDrive`; changed the no-drive guard from `$null -eq $USBDrives` to `$USBDrives.Count -eq 0` so an empty (but non-null) array is correctly treated as "no USB drive found".

#### Testing

- New `Tests/Unit/Upstream.SyncPorts.Tests.ps1` — 15 Pester tests (AST extraction for `Format-MsiArguments` behavior + content verification for the BuildFFUVM.ps1 changes). All pass.
- Modified files parse clean; no new PSScriptAnalyzer **Error**-severity findings.

#### Files Modified

- `FFUDevelopment/Apps/Orchestration/Install-Win32Apps.ps1`
- `FFUDevelopment/BuildFFUVM.ps1`
- `FFUDevelopment/version.json` (1.10.1 → 1.10.2)
- `Tests/Unit/Upstream.SyncPorts.Tests.ps1` (new)
- `.planning/reports/upstream-sync-audit-2026-06-21.md` (new — full backlog)

#### Main version

- **Main version:** 1.10.1 → 1.10.2 (PATCH — bug-fix ports)

---

## [1.10.1] - 2026-03-14

### Phase 46-01: FFU.ArtifactScanner Module - Data Contract and Get-ArtifactMetadata

**Context:** First plan of Phase 46 (FFU.ArtifactScanner Module), which establishes the typed data contract for USB Mode artifact discovery. This module defines the data model consumed by Phase 47 (pipeline), Phase 48 (UI columns), and Phase 49 (controls).

**New module:** `FFU.ArtifactScanner` at `FFUDevelopment/Modules/FFU.ArtifactScanner/`

#### Changes

- **FFU.ArtifactScanner module scaffold:**
  - `Classes/ArtifactScanner.Classes.ps1` — enums and data classes following FFU.Hypervisor/Classes/ pattern
  - `FFU.ArtifactScanner.psm1` — module root with dot-sourced classes and public functions
  - `FFU.ArtifactScanner.psd1` — manifest with RequiredModules (FFU.Core, FFU.Preflight)
- **Data contract enums:** `ArtifactStatus` (Found/Missing/Error/Degraded), `ArtifactType` (FFU/DeployISO/Drivers/PPKG/Unattend/Autopilot/AppsISO)
- **Data contract classes:** `ArtifactFileEntry`, `FFUMetadata`, `ArtifactResult` (constructor initializes Files list), `CompatibilityWarning`, `ArtifactManifest`
- **Get-ArtifactMetadata:** DISM primary via `Get-WindowsImage -ImagePath <ffu>`, filename-parsing fallback when DISM fails or WIMMount unavailable
- **Architecture mapping:** integer 0→x86, 9→x64, 12→arm64 (DISM PE encoding)
- **Factory functions:** `New-ArtifactManifest`, `New-ArtifactResult` for cross-scope class instantiation (Pitfall 4 pattern from FFU.Hypervisor v1.1.4)
- **Stub functions:** `Find-FFUArtifacts`, `Test-ArtifactCompatibility` (full implementation in Plan 46-02)
- **79 Pester tests passing** (`InModuleScope` pattern for PowerShell class/enum tests)
- **Invoke-PesterTests.ps1:** Added `FFU.ArtifactScanner` to `-Module` ValidateSet

#### ThreadJob Compatibility
- `[DateTime]::Now` instead of `Get-Date`
- Safe WriteLog pattern (`if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }`)
- `[Console]::Error.WriteLine()` in module init catch blocks

---

## [1.9.12] - 2026-02-02

### Phase 44-01: DISM Resilience in FFU.Updates (v1.9.12)

**Problem:** The v1.9.8 Test-DismReady (WIMMount filter driver validation) fix was implemented in FFU.Core, FFU.Imaging, FFU.VM, and BuildFFUVM.ps1, but the entire FFU.Updates module—the most DISM-intensive part of the build—was missed. When WIMMount broke mid-build during Windows Update application, DISM operations hung for 10+ minutes before failing, resulting in 30+ minute total hangs across multiple retry attempts.

**Solution:** Added Test-DismReady gates before all Add-WindowsPackage DISM calls in FFU.Updates, implementing fast-fail with auto-repair when WIMMount filter driver is broken.

#### Changes

- **Test-MountState:** Added Test-DismReady check before Get-WindowsEdition (prevents 10-min hang on mount validation)
- **Add-WindowsPackageWithRetry:** Added Test-DismReady gate at top of retry loop (catches inter-update WIMMount failures)
- **Add-WindowsPackageWithRetry retry refresh:** Guarded Get-WindowsEdition refresh call with Test-DismReady (prevents DISM-to-check-DISM anti-pattern)
- **Add-WindowsPackageWithUnattend:** Added Test-DismReady gates at 3 call sites:
  - Direct CAB application (line ~1663)
  - Direct MSU fallback application (line ~1816)
  - Extracted CAB application in foreach loop (line ~1910)
- **BuildFFUVM.ps1 WinSxS cleanup:** Guarded raw Dism.exe /Cleanup-Image call with Test-DismReady (non-critical operation, safe to skip)

#### Testing

- 19 Pester tests covering all DISM resilience integration points
- Tests verify Test-DismReady is called before DISM operations
- Tests verify fast-fail behavior when WIMMount is broken
- Tests verify retry refresh guard prevents hanging

#### Impact

- Eliminates 30+ minute hangs when WIMMount breaks during update application
- Fast-fail provides immediate actionable error message (reboot required)
- Auto-repair attempt before failing (Test-DismReady includes remediation)
- Completes v1.9.8 DISM resilience fixes across all modules
- Closes Test-DismReady coverage gap identified in Phase 44 analysis

#### Module Versions

- **FFU.Updates:** 1.1.0 → 1.2.0
- **Main version:** 1.9.11 → 1.9.12

---

## [1.9.7] - 2026-01-27

### Phase 33: OEM Driver Logging (v1.9.7)
- All OEM driver selection, download, extraction, and error operations now log to FFUDevelopment.log via WriteLog
- Structured [OEM][Model][Operation] prefix format enables grep/filtering of driver log entries
- Dual output pattern preserves Write-Host console visibility for interactive builds
- All error paths include actionable remediation with exception details, build impact, and log file reference
- Phase 31/32 WARNING messages retrofitted with structured prefixes
- Pester tests verify WriteLog usage across all OEM driver code paths (LOG-01 through LOG-06)
- FFU.Drivers module version bumped to 1.4.0

---

## [1.9.2] - 2026-01-25

### Bug Fixes

- **BUG-01: VHD Drive Letter Destabilization After fsutil Flush** (BUILD)
  - **Issue:** Build failed partway through when VHD drive letter became inaccessible after fsutil volume flush
  - **Root Cause:** CIM disk instance becomes stale after fsutil volume flush on VHD/VHDX files. Windows may detach/reattach the virtual disk, invalidating the object reference. All subsequent operations piping through `$disk` fail.
  - **Solution:** Store disk number before fsutil flush, get fresh disk object after flush using `Get-Disk -Number`, with fallback discovery by path/BusType if number lookup fails
  - **Files Modified:**
    - `FFUDevelopment/BuildFFUVM.ps1`
    - `.planning/debug/os-partition-drive-letter-lost.md`
  - **Commit:** b492a16

- **BUG-02: CopyOfficeConfigXML Checkbox Not Persisting** (CONFIG)
  - **Issue:** The "Copy Office Config XML" checkbox reset to default on every UI launch, losing user preference
  - **Root Cause:** Config migration incorrectly treated CopyOfficeConfigXML as deprecated and removed it during config load, causing the checkbox state to reset on every UI launch
  - **Solution:** Remove migration logic that deleted CopyOfficeConfigXML property, remove deprecated flag from schema definition
  - **Files Modified:**
    - `FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1`
    - `FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psd1`
    - `FFUDevelopment/config/ffubuilder-config.schema.json`
  - **Commit:** ceb77eb

- **BUG-03: Config Migration Always Triggered** (CONFIG)
  - **Issue:** UI showed config migration prompt on every launch even after migration completed
  - **Root Cause:** `Get-UIConfig` did not include `configSchemaVersion` in the saved config hashtable. On next load, missing version was treated as "0.0" which always triggered the migration prompt.
  - **Solution:** Add configSchemaVersion to Get-UIConfig output, use Get-FFUConfigSchemaVersion if available with fallback to "1.2"
  - **Files Modified:**
    - `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1`
  - **Commit:** 6d9afde

- **BUG-04: Winget CLI Not Available in Elevated Context** (WINGET)
  - **Issue:** "Check Winget Status" failed even after installation; Winget CLI invisible to elevated admin context
  - **Root Cause (Part 1):** `Add-AppxPackage` without `-AllUsers` installed VCLibs, UIXaml, and WinGet MSIX packages per-user only. Since FFU Builder UI runs elevated, the per-user CLI installation was invisible.
  - **Root Cause (Part 2):** Winget was provisioned system-wide but not registered for the elevated admin account. `Add-AppxPackage -AllUsers` doesn't register for existing users - it only provisions for future users.
  - **Solution (Part 1):** Install Winget CLI packages with `-AllUsers` for system-wide availability
  - **Solution (Part 2):** Two-strategy approach - check if package is provisioned, then use `Add-AppxPackage -RegisterByFamilyName` to instantly register for current user; fall back to download/install if not provisioned
  - **Files Modified:**
    - `FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1`
    - `FFUDevelopment/FFU.Common/FFU.Common.psd1`
    - `FFUDevelopment/FFUUI.Core/FFUUI.Core.Winget.psm1`
    - `FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1`
    - `FFUDevelopment/version.json`
  - **Commits:** bfd6943, f1ad60f

- **BUG-05: Winget Source Package Not Registered for Admin** (WINGET)
  - **Issue:** After BUG-04 fix, winget CLI worked but `winget search` failed with "Data required by the source is missing"
  - **Root Cause:** `Microsoft.Winget.Source_8wekyb3d8bbwe` (the repository index) was not registered for the elevated admin account
  - **Solution:** Extended Install-WingetComponents to register Winget Source package using `Add-AppxPackage -RegisterByFamilyName`, then initialize sources with `winget source reset --force` and update with `winget source update`
  - **Files Modified:**
    - `FFUDevelopment/FFUUI.Core/FFUUI.Core.Winget.psm1`
    - `FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1`
    - `FFUDevelopment/version.json`
  - **Commit:** 38c897c

### Enhancements

- **Intune Proactive Remediation Scripts for Winget** (WINGET)
  - Added detection and remediation scripts for enterprise Winget registration deployment via Intune
  - Scripts handle provisioned vs registered package states, source initialization, and fallback download
  - **Files Created:**
    - `FFUDevelopment/Intune/WingetRemediation/Detect-WingetRegistration.ps1`
    - `FFUDevelopment/Intune/WingetRemediation/Remediate-WingetRegistration.ps1`
    - `FFUDevelopment/Intune/WingetRemediation/README.md`
  - **Commit:** 63461eb

- **KB Article: Winget Registration Troubleshooting** (DOCS)
  - Comprehensive knowledge base article for IT support covering symptoms, diagnostics, resolution procedures, error codes, and FAQ
  - Suitable for publishing as internal KB article or help desk documentation
  - **Files Created:**
    - `FFUDevelopment/Intune/WingetRemediation/KB-Winget-Troubleshooting.md`
  - **Commit:** c338b55

---

## [1.8.12] - 2026-01-23

### Enhancements
- **FFU.Core Error Handling Reliability (REL-CORE-01)** (MODULE)
  - **Objective:** Harden error handling across all FFU.Core functions for improved debuggability
  - **Scope:** Enhanced 12 functions with specific exception types and contextual error messages
  - **Changes:**
    - `Get-Parameters`: Added null input handling, returns empty array for null
    - `Write-VariableValues`: Added scope error handling with nested try/catch
    - `Get-ChildProcesses`: Added CimException handling, ValidateRange for ParentId
    - `Test-Url`: Added WebException, UriFormatException with URL validation
    - `Get-PrivateProfileString/Section`: Added P/Invoke exception handling, file existence validation
    - `New-FFUFileName`: Added ArgumentException for empty template/version/SKU
    - `Export-ConfigFile`: Added IOException, JsonException handling, auto directory creation
    - `Get-CurrentRunManifest`: Added IOException for locked files, JSON parse error handling
    - `Save-RunManifest`: Added IOException handling with directory auto-creation
    - `Set/Clear-DownloadInProgress`: Added IOException with best-effort pattern
  - **Pattern Consistency:**
    - All functions use try/catch with specific exception types
    - Error messages include operation context (file paths, parameters)
    - Safe logging pattern ($function:WriteLog or Write-Verbose fallback)
    - ThreadJob compatible (no Write-Host, Write-Warning without fallback)
  - **Files Modified:**
    - `FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1` - 12 functions enhanced
    - `FFUDevelopment/Modules/FFU.Core/FFU.Core.psd1` - Version 1.0.19, release notes
    - `FFUDevelopment/version.json` - Main version 1.8.12, FFU.Core 1.0.19
  - **Files Created:**
    - `Tests/Unit/FFU.Core.ErrorHandling.Tests.ps1` - 53 tests, 47 pass, 6 skip (external deps)
  - **Test Coverage:** 53 tests verifying error handling patterns

---

## [1.6.3] - 2026-01-08

### Bug Fixes
- **CaptureFFU.ps1 Network Ping Timeout - ICMP Blocked by Firewall** (CAPTURE)
  - **Issue:** WinPE capture failed with "Network failed to become ready within 60 seconds" when host firewall blocks ICMP
  - **Symptoms:** Ping shows "[Request interrupted by user]" and build times out even though network is configured correctly
  - **Root Cause:** `Wait-For-NetworkReady` function required successful ping to host before proceeding, but many corporate firewalls block ICMP while allowing SMB
  - **Solution:** Made ping check non-blocking:
    - Ping failure now generates a warning instead of blocking progress
    - Warning shown only once per boot (via `$script:pingWarningShown` flag)
    - Status message shows "ping blocked/failed" vs "reachable" for diagnostics
    - Proceeds to SMB connection which provides more accurate connectivity status
  - **Files Modified:**
    - `WinPECaptureFFUFiles/CaptureFFU.ps1` - Modified `Wait-For-NetworkReady` function (lines 350-420)
  - **Documentation:**
    - `docs/pending/PENDING-FIX-CaptureFFU-Ping-Timeout.md` - Marked as implemented
  - **Rationale:**
    - Many corporate environments block ICMP but allow SMB
    - SMB connection attempt provides more specific error messages than ping timeout
    - Ping is an optimization, not a hard requirement for FFU capture

---

## [1.6.2] - 2026-01-08

### Bug Fixes
- **VMware REST API Credentials Not Detected After Setup in Enterprise Environments** (UI)
  - **Issue:** After configuring vmrest.exe credentials, UI status still showed "Not configured"
  - **Root Cause:** Button requested UAC elevation (`$psi.Verb = 'runas'`), which with separate admin accounts writes credentials to admin's profile, not logged-in user's profile
  - **Solution:** Removed elevation from credential setup button and added enterprise guidance:
    - Status now shows "Configured (current user)" to clarify per-profile storage
    - Terminal output includes guidance for separate admin account scenarios
    - Dialog message explains enterprise configuration requirements
    - Updated tooltips on XAML controls
    - Added dynamic tooltip showing current username
  - **Files Modified:**
    - `FFUUI.Core/FFUUI.Core.Handlers.psm1` - Removed elevation, added enterprise guidance
    - `FFUUI.Core/FFUUI.Core.Shared.psm1` - Updated status text and dynamic tooltips
    - `BuildFFUVM_UI.xaml` - Updated control tooltips
    - `FFUUI.Core/FFUUI.Core.psd1` - Version bump to 0.0.5
    - `docs/VMWARE_WORKSTATION_GUIDE.md` - Added enterprise environment section

---

## [1.3.5] - 2025-12-11

### Bug Fixes
- **DISM Error 0x800704db "The specified service does not exist" - WIM Mount Failures in ApplyFFU.ps1** (DEPLOY)
  - **Issue:** WIM mount operations in ApplyFFU.ps1 failed with error 0x800704db when deploying drivers from WIM files
  - **Root Cause:** ApplyFFU.ps1 was using ADK `dism.exe /Mount-Image` directly instead of native PowerShell cmdlets:
    1. ADK DISM.exe relies on WIMMount filter driver which can become corrupted by newer ADK versions (10.1.26100.1+)
    2. WIMMount filter was not properly loaded in Filter Manager (`fltmc filters` showed WIMMount missing)
    3. Registry was correct but driver wasn't registered with Filter Manager at altitude 180700
  - **Solution:** Replaced ADK dism.exe calls with native PowerShell DISM cmdlets:
    - Changed `dism.exe /Mount-Image` to `Mount-WindowsImage` cmdlet
    - Changed `dism.exe /Unmount-Image` to `Dismount-WindowsImage` cmdlet
    - Added fallback cleanup using `dism.exe /Cleanup-Mountpoints` for unmount failures
    - PowerShell cmdlets use OS DISM infrastructure which is more reliable than ADK DISM
  - **Files Modified:**
    - `WinPEDeployFFUFiles/ApplyFFU.ps1` - Lines 895-930, replaced dism.exe mount/unmount with PowerShell cmdlets
  - **Files Created:**
    - `Tests/FFU.NativeDISM.Tests.ps1` - 31 comprehensive tests validating native DISM usage
  - **Test Coverage:** 31 new tests covering:
    - Mount operations use native cmdlets
    - Unmount operations use native cmdlets
    - Error handling patterns
    - DISM cmdlet availability
    - No ADK dism.exe mount/unmount usage (regression prevention)
  - **Regression Tests:** Baseline 1321 passed, Post-change 1352 passed (+31 from new tests, 0 regressions)
  - **Related:** This is a more reliable solution than the remediation-based approach in v1.3.2

---

## [1.3.4] - 2025-12-11

### Bug Fixes
- **UI Monitor Tab Still Not Showing Progress After 1.3.3 Fix** (UI)
  - **Issue:** After implementing the WriteLog messaging queue integration in 1.3.3, the Monitor tab STILL only showed "Build started"
  - **Root Cause:** Module scope collision in BuildFFUVM.ps1:
    1. BuildFFUVM_UI.ps1 ThreadJob sets messaging context via `Set-CommonCoreMessagingContext`
    2. BuildFFUVM.ps1 line 641 does `Import-Module "$PSScriptRoot\FFU.Common" -Force`
    3. The `-Force` flag RESETS the script-scoped `$script:CommonCoreMessagingContext` variable to `$null`
    4. All subsequent WriteLog calls have no messaging context, so no messages reach the UI queue
  - **Solution (Defense-in-Depth Pattern):**
    - Added messaging context restoration code in BuildFFUVM.ps1 immediately after FFU.Common import
    - Uses the `$MessagingContext` parameter passed from UI to restore context after `-Force` import
    - Added explanatory comments documenting the root cause and fix for future maintainers
  - **Files Modified:**
    - `BuildFFUVM.ps1` - Added messaging context restoration after FFU.Common import (lines 644-653)
  - **Tests Added:**
    - `Tests/FFU.Common.Core.LogMonitoring.Tests.ps1` - Added 3 new regression tests:
      - Verifies context restoration exists after -Force import
      - Verifies restoration happens AFTER module import
      - Verifies defense-in-depth pattern is documented in comments
  - **Test Coverage:** 23 log monitoring tests total (3 new), all passing
  - **Regression Tests:** Baseline 1321 passed, Post-change 1321 passed (no regressions)

---

## [1.3.3] - 2025-12-11

### Bug Fixes
- **UI Monitor Tab Only Showing "Build started" - Log Entries Not Displayed** (UI)
  - **Issue:** Monitor tab in BuildFFUVM_UI.ps1 only showed "Build started" message, not the actual build progress from FFUDevelopment.log
  - **Root Cause:** Architectural flaw in UI timer logic:
    1. WriteLog function in FFU.Common.Core only wrote to log FILE, not to the FFU.Messaging queue
    2. UI timer had `if/elseif` structure where queue check always evaluated true (queue EXISTS but was empty)
    3. File-reading fallback in `elseif` block never executed because queue always existed
    4. Only `Set-FFUBuildState` calls populated the queue (hence only "Build started" appeared)
  - **Solution:** Integrated WriteLog with FFU.Messaging queue:
    - Added `Set-CommonCoreMessagingContext` function to FFU.Common.Core
    - Modified WriteLog to write to BOTH log file AND messaging queue when context is set
    - Updated ThreadJob scriptblock in BuildFFUVM_UI.ps1 to import FFU.Common.Core and set messaging context
    - Defense-in-depth: Queue writes work even when log file path isn't set
  - **Files Modified:**
    - `FFU.Common/FFU.Common.Core.psm1` - Added Set-CommonCoreMessagingContext, modified WriteLog
    - `FFU.Common/FFU.Common.psd1` - Version bumped to 0.0.5
    - `BuildFFUVM_UI.ps1` - ThreadJob scriptblock imports FFU.Common.Core and sets messaging context
    - `version.json` - Version bumped to 1.3.3, FFU.Common to 0.0.5
  - **Files Created:**
    - `Tests/FFU.Common.Core.LogMonitoring.Tests.ps1` - 20 comprehensive tests
  - **Test Coverage:** 20 new log monitoring tests, all passing
  - **Regression Tests:** Baseline 1300 passed, Post-change 1321 passed (+21 from new tests)

---

## [1.3.2] - 2025-12-11

### Bug Fixes
- **DISM WIM Mount Failure - Error 0x800704DB "The specified service does not exist"** (BUILD)
  - **Issue:** DISM WIM mount operations failed during WinPE media creation with error "The specified service does not exist" (0x800704DB)
  - **Root Cause:** WIM mount filter driver infrastructure (WIMMount service, WOF service, or driver files) missing or not properly registered
  - **Error Location:** `DISM.log` shows failures in `OpenFilterPort`, `FltCommVerifyFilterPresent`, `WIMMountImageHandle`
  - **Solution:** Added comprehensive pre-flight validation with automatic remediation
  - **New Function:** `Test-FFUWimMount` in FFU.Preflight module
    - Validates WIMMount service existence and status
    - Validates WOF (Windows Overlay Filter) service existence
    - Checks Filter Manager (FltMgr) service status
    - Verifies wimmount.sys and wof.sys driver files exist in System32\drivers
    - Optional automatic remediation:
      1. Restart FltMgr service if stopped
      2. Restart WIMMount service if stopped
      3. Re-register WIM mount driver via `rundll32.exe wimmount.dll,WimMountDriver`
  - **Integration:** Automatically runs as part of `Invoke-FFUPreflight` when ADK/WinPE operations are enabled
  - **Files Modified:**
    - `Modules/FFU.Preflight/FFU.Preflight.psm1` - Added Test-FFUWimMount function and Invoke-FFUPreflight integration
    - `Modules/FFU.Preflight/FFU.Preflight.psd1` - Added export, version bumped to 1.0.1
  - **Files Created:**
    - `Tests/Unit/FFU.Preflight.WimMount.Tests.ps1` - 28 comprehensive tests
  - **Test Coverage:** 28 new tests, all passing (3 skipped based on system state)
  - **Regression Tests:** Baseline 1273 passed, Post-change 1300 passed (+27 from new tests)

---

## [1.3.1] - 2025-12-11

### Bug Fixes
- **Configuration Schema Missing Properties Causing Validation Errors** (CONFIG)
  - **Issue:** Pre-flight validation failed with "Unknown property 'X' is not allowed in configuration" for 8 properties
  - **Root Cause:** JSON schema (`ffubuilder-config.schema.json`) had `additionalProperties: false` but was missing legitimate and legacy properties
  - **Properties Fixed:**
    - `AdditionalFFUFiles` - Added as valid array property (was missing from schema)
    - 7 deprecated properties added for backward compatibility:
      - `AppsPath` - Legacy, replaced by FFUDevelopmentPath-based derivation
      - `CopyOfficeConfigXML` - Legacy, replaced by OfficeConfigXMLFile
      - `DownloadDrivers` - Legacy, replaced by Make/Model parameters
      - `InstallWingetApps` - Legacy, replaced by InstallApps/AppListPath
      - `OfficePath` - Legacy, replaced by FFUDevelopmentPath-based derivation
      - `Threads` - Legacy, parallel processing now automatic
      - `Verbose` - Should use -Verbose switch, not config property
  - **Solution:**
    - Added `AdditionalFFUFiles` property with proper array/null type definition
    - Added deprecated properties with `deprecated: true` flag and clear descriptions
    - Added deprecation warning detection in Test-FFUConfiguration
    - Deprecated properties generate warnings (not errors) for graceful migration
  - **Files Modified:**
    - `config/ffubuilder-config.schema.json` - Added missing and deprecated properties
    - `Modules/FFU.Core/FFU.Core.psm1` - Added deprecated property warning in validation
    - `Modules/FFU.Core/FFU.Core.psd1` - Version bumped to 1.0.12
  - **Files Created:**
    - `Tests/Unit/FFU.Core.SchemaCompleteness.Tests.ps1` - 99 tests for schema completeness
  - **Files Deleted:**
    - `Tests/Unit/BuildFFUVM.DismInitialization.Tests.ps1` - Obsolete (functionality moved to FFU.Preflight)
  - **Test Coverage:** 99 new schema completeness tests, all passing
  - **Regression Tests:** 1273 passed, 34 pre-existing failures, 23 skipped

---

## [1.3.0] - 2025-12-11

### Features
- **Comprehensive Pre-Flight Validation System** (ARCHITECTURE)
  - **Issue:** Build failures occurred mid-process due to missing prerequisites, wasting time and resources
  - **Solution:** New FFU.Preflight module with tiered validation architecture
  - **New Module:** FFU.Preflight (v1.0.0) - Pre-flight environment validation
    - **Tier 1 (Critical, Always Run):** Administrator privileges, PowerShell 7.0+, Hyper-V feature
    - **Tier 2 (Feature-Dependent):** Windows ADK, disk space calculation, network connectivity, config file
    - **Tier 3 (Warnings Only):** Windows Defender exclusions
    - **Tier 4 (Pre-Build Cleanup):** DISM mount cleanup, temp directory cleanup, orphaned VHD cleanup
  - **Key Design Decision:** TrustedInstaller running state is NOT checked (it's a demand-start service)
  - **Functions Exported:** 12 functions including Invoke-FFUPreflight, Test-FFUAdministrator, Test-FFUHyperV, etc.
  - **Files Created:**
    - `Modules/FFU.Preflight/FFU.Preflight.psm1` - Main module implementation
    - `Modules/FFU.Preflight/FFU.Preflight.psd1` - Module manifest
    - `Tests/Unit/FFU.Preflight.Tests.ps1` - 58 comprehensive tests
    - `docs/designs/PREFLIGHT-VALIDATION-SYSTEM-DESIGN.md` - Detailed design document
  - **Files Modified:**
    - `BuildFFUVM.ps1` - Integrated preflight validation call, removed redundant Hyper-V check
    - All module .psm1 files - Updated to require PowerShell 7.0
    - All module .psd1 files - Updated PowerShellVersion to '7.0'
  - **Test Coverage:** 58 new tests, all passing

### Breaking Changes
- **PowerShell 7.0+ Required:** All modules and scripts now require PowerShell 7.0 or higher
  - Enables ForEach-Object -Parallel for better performance
  - Provides built-in ThreadJob module
  - Supports ternary operators and null-coalescing
  - Updated `#Requires -Version 7.0` in all .psm1 files
  - Updated `PowerShellVersion = '7.0'` in all .psd1 manifests

### Improvements
- **TrustedInstaller Service Handling Corrected**
  - **Issue:** Previous code tried to start TrustedInstaller service manually
  - **Root Cause:** TrustedInstaller is a demand-start service; Windows manages its lifecycle
  - **Solution:** Updated Test-DISMServiceHealth and Start-RequiredServicesForDISM to only verify service is not disabled
  - **Files Modified:**
    - `Modules/FFU.Updates/FFU.Updates.psm1` - Test-DISMServiceHealth refactored
    - `Modules/FFU.Imaging/FFU.Imaging.psm1` - Start-RequiredServicesForDISM refactored

---

## [1.2.12] - 2025-12-10

### Bug Fixes
- **FFUMessageLevel Type Not Found at Runtime** (BUILD)
  - **Issue:** Build failed with "Unable to find type [FFUMessageLevel]" at line 742 of BuildFFUVM_UI.ps1
  - **Root Cause:** PowerShell enums defined in modules are NOT automatically exported via `Import-Module`. They require `using module` at parse-time, which has path resolution issues in complex scripts
  - **Solution:** Replace enum type comparisons with string comparisons using `ToString()`
    - Changed `$msg.Level -eq [FFUMessageLevel]::Progress` to `$msg.Level.ToString() -eq 'Progress'`
    - Added explanatory comments documenting why string comparison is required
  - **Files Modified:**
    - `BuildFFUVM_UI.ps1` - Replaced enum references at lines 742 and 808
    - `Tests/Unit/BuildFFUVM_UI.MessagingIntegration.Tests.ps1` - Updated test pattern
  - **Files Created:**
    - `Tests/Unit/BuildFFUVM_UI.EnumTypeAvoidance.Tests.ps1` - 16 tests preventing regression
  - **Test Coverage:** 16 new tests + 48 messaging integration tests, all passing
  - **Regression Tests:** 1156/1213 passing (34 pre-existing failures unrelated to this fix)

---

## [1.2.11] - 2025-12-10

### Bug Fixes
- **MessagingContext Parameter Not Found** (BUILD)
  - **Issue:** Build failed with "A parameter cannot be found that matches parameter name 'MessagingContext'"
  - **Root Cause:** BuildFFUVM_UI.ps1 was passing `-MessagingContext` to BuildFFUVM.ps1, but the parameter didn't exist
  - **Solution:** Added `-MessagingContext` parameter to BuildFFUVM.ps1
    - Optional parameter with `$null` default for CLI compatibility
    - Type: `[hashtable]` to accept synchronized messaging context
    - Documented in help section and inline comments
  - **Files Modified:**
    - `BuildFFUVM.ps1` - Added MessagingContext parameter to param block and help
  - **Files Created:**
    - `Tests/Unit/BuildFFUVM.MessagingContext.Tests.ps1` - 24 tests validating the fix
  - **Test Coverage:** 24 new tests, all passing
  - **Regression Tests:** 1140/1197 passing (34 pre-existing failures unrelated to this fix)

---

## [1.2.10] - 2025-12-10

### Enhancements
- **Real-Time UI Updates - Issue #14** (ARCHITECTURE)
  - **Issue:** BuildFFUVM_UI.ps1 had 1-second polling delay for log updates, causing sluggish UI feedback
  - **Root Cause:** File-based log polling with 1-second DispatcherTimer interval
  - **Solution:** Hybrid approach with ConcurrentQueue + file backup
  - **New Module:** FFU.Messaging (v1.0.0) - Thread-safe messaging system
    - Uses `System.Collections.Concurrent.ConcurrentQueue[T]` for lock-free messaging
    - Synchronized hashtable for cross-thread state sharing
    - Functions: New-FFUMessagingContext, Write-FFUMessage, Write-FFUProgress, Read-FFUMessages, Request-FFUCancellation, Set-FFUBuildState
    - Throughput: ~12,000+ messages/second
  - **UI Changes:**
    - Timer interval reduced from 1000ms to 50ms (20x faster)
    - Queue-based message reading as primary method
    - File-based reading as fallback for backward compatibility
    - Cancellation via messaging context
  - **Files Created:**
    - `Modules/FFU.Messaging/FFU.Messaging.psm1`
    - `Modules/FFU.Messaging/FFU.Messaging.psd1`
    - `Tests/Unit/BuildFFUVM_UI.MessagingIntegration.Tests.ps1`
  - **Files Modified:**
    - `BuildFFUVM_UI.ps1` - Messaging integration
    - `Tests/Unit/BuildFFUVM.UsingModulePath.Tests.ps1` - Updated for new parameter signature
  - **Test Coverage:** 48 new tests, all passing

---

## [1.0.4] - 2025-12-03

### Enhancements
- **Comprehensive Parameter Validation** (BUILD)
  - **Issue:** BuildFFUVM.ps1 had minimal parameter validation, causing late failures with cryptic errors
  - **Solution:** Added validation attributes to 15+ parameters
  - **Validation Types Added:**
    - ValidateScript: Path existence for file/folder parameters
    - ValidatePattern: Regex for ShareName, Username, WindowsVersion
    - ValidateRange: MaxUSBDrives (0-100)
    - ValidateNotNullOrEmpty: FFUPrefix, ShareName, Username, WindowsVersion
    - Array validation: AdditionalFFUFiles (each file validated)
  - Files: `BuildFFUVM.ps1`
  - Test: `Tests/Test-ParameterValidation.ps1` (37 tests)
  - **Full Documentation:** [PARAMETER_VALIDATION_FIX.md](docs/fixes/PARAMETER_VALIDATION_FIX.md)

---

## [1.0.3] - 2025-12-03

### Bug Fixes
- **FFU.VM Module Export Fix** (BUILD)
  - **Root Cause:** Functions defined in .psm1 and listed in .psd1 FunctionsToExport, but NOT included in Export-ModuleMember statement
  - **Symptom:** "Remove-SensitiveCaptureMedia is not recognized as the name of a cmdlet"
  - **Solution:** Added Set-LocalUserAccountExpiry and Remove-SensitiveCaptureMedia to Export-ModuleMember
  - Files: `Modules/FFU.VM/FFU.VM.psm1`
  - Test: `Tests/Test-ModuleExportFix.ps1` (13 tests)
  - **Full Documentation:** [MODULE_EXPORT_FIX.md](docs/fixes/MODULE_EXPORT_FIX.md)

---

## [1.0.2] - 2025-12-03

### Bug Fixes
- **DISM Error 0x80070228 - Enhanced Fix with Direct CAB Application** (BUILD)
  - **Root Cause:** UUP packages trigger Windows Update Agent to download content, fails on offline images
  - **Solution:** Extract CAB files from MSU and apply directly - bypasses UpdateAgent
  - Files: `FFU.Updates.psm1`
  - Test: `Tests/Test-CheckpointUpdateFix.ps1` (12 tests)
  - **Full Documentation:** [CHECKPOINT_UPDATE_0x80070228_FIX.md](docs/fixes/CHECKPOINT_UPDATE_0x80070228_FIX.md)
  - Reference: https://learn.microsoft.com/en-us/answers/questions/3855149/

---

## [1.0.1] - 2025-12-03 (Superseded by 1.0.2)

### Bug Fixes
- **DISM Error 0x80070228 - Initial Fix Attempt** (BUILD)
  - Initial fix using isolated MSU directory approach
  - Prevented multi-MSU conflicts but didn't fully address UUP download issue
  - Superseded by 1.0.2 which uses direct CAB application

---

## [1.0.0] - 2025-12-03

### Major Features

#### Modular Architecture (2025-11-20)
Complete refactoring of monolithic `BuildFFUVM.ps1` into 9 specialized modules:

| Module | Functions | Purpose |
|--------|-----------|---------|
| FFU.Core | 18 | Core functionality, configuration, session tracking |
| FFU.Constants | - | Centralized configuration values |
| FFU.ADK | 8 | Windows ADK management and validation |
| FFU.Apps | 5 | Application management, Office deployment |
| FFU.Drivers | 5 | OEM driver management (Dell, HP, Lenovo, Microsoft) |
| FFU.Imaging | 15 | DISM operations, partitioning, FFU creation |
| FFU.Media | 4 | WinPE media creation |
| FFU.Updates | 8 | Windows Update handling, KB downloads |
| FFU.VM | 10 | Hyper-V VM lifecycle management |

**Metrics:**
- Original: 7,790 lines
- After: 2,404 lines (69% reduction)
- Functions extracted: 64
- 100% backward compatible

**Documentation:** `docs/summaries/MODULARIZATION_PHASE2-4_SUMMARY.md`

#### UI Version Display (2025-12-03)
- Added version display in window title bar
- Added About tab with version, build date, and project info
- Files: `BuildFFUVM_UI.ps1`, `BuildFFUVM_UI.xaml`, `FFUUI.Core.Initialize.psm1`
- Design: `docs/designs/UI-VERSION-DISPLAY-DESIGN.md`

#### Credential Security Improvements (2025-12-03)
- Added 4-hour account expiry failsafe for temporary FFU user
- Added SecureString disposal after credential use
- Added sensitive media cleanup function
- Added comprehensive security documentation to CaptureFFU.ps1
- Files: `FFU.VM.psm1`, `BuildFFUVM.ps1`, `CaptureFFU.ps1`
- Test: `Tests/Test-CredentialSecurity.ps1`

---

### Bug Fixes (November 2025)

#### Critical Fixes

| Fix | Date | Description | Documentation |
|-----|------|-------------|---------------|
| PowerShell TelemetryAPI Error | 2025-11-24 | Fixed PS7 "Could not load type TelemetryAPI" with .NET DirectoryServices | [POWERSHELL_CROSSVERSION_FIX.md](docs/fixes/POWERSHELL_CROSSVERSION_FIX.md) |
| Empty ShortenedWindowsSKU | 2025-11-24 | Fixed "Cannot bind argument" error with graceful fallback | [SHORTENED_SKU_INITIALIZATION_FIX_SUMMARY.md](docs/fixes/SHORTENED_SKU_INITIALIZATION_FIX_SUMMARY.md) |
| Set-CaptureFFU Missing | 2025-11-23 | Implemented missing function for WinPE capture | [SET_CAPTUREFFU_FIX_SUMMARY.md](docs/fixes/SET_CAPTUREFFU_FIX_SUMMARY.md) |
| MSU Extraction Error | 2025-11-23 | Fixed expand.exe failures with enhanced error handling | [MSU_PACKAGE_FIX_SUMMARY.md](docs/fixes/MSU_PACKAGE_FIX_SUMMARY.md) |
| Filter Parameter Null | 2025-11-22 | Fixed null error in FFU.Updates module | [FILTER_PARAMETER_FIX_SUMMARY.md](docs/fixes/FILTER_PARAMETER_FIX_SUMMARY.md) |
| copype WIM Mount Failures | 2025-11-17 | Added DISM cleanup and retry logic | [COPYPE_WIM_MOUNT_FIX.md](docs/fixes/COPYPE_WIM_MOUNT_FIX.md) |
| WinPE boot.wim Creation | 2025-11-07 | Added ADK pre-flight validation | [WINPE_BOOTWIM_CREATION_FIX.md](docs/fixes/WINPE_BOOTWIM_CREATION_FIX.md) |

#### High Priority Fixes

| Fix | Date | Description | Documentation |
|-----|------|-------------|---------------|
| Log Monitoring Failure | 2025-11-24 | Fixed UI log path null with defense-in-depth | [LOG_MONITORING_FIX_SUMMARY.md](docs/fixes/LOG_MONITORING_FIX_SUMMARY.md) |
| WriteLog Empty String | 2025-11-24 | Fixed parameter binding errors | [WRITELOG_PATH_VALIDATION_FIX.md](docs/fixes/WRITELOG_PATH_VALIDATION_FIX.md) |
| FFU Constants Module | 2025-11-24 | Centralized configuration (Quick Win #4) | [FFUCONSTANTS_FIX_SUMMARY.md](docs/fixes/FFUCONSTANTS_FIX_SUMMARY.md) |
| cmd.exe Path Quoting | 2025-11-24 | Fixed 'C:\Program' not recognized errors | [CMD_PATH_QUOTING_FIX.md](docs/fixes/CMD_PATH_QUOTING_FIX.md) |
| FFU Optimization Error 1167 | 2025-11-24 | Fixed "Device Not Connected" with scratch dir | [FFU_OPTIMIZATION_ERROR_1167_FIX.md](docs/fixes/FFU_OPTIMIZATION_ERROR_1167_FIX.md) |
| Expand-WindowsImage 0x8007048F | 2025-11-24 | Fixed VHDX creation failures with retry | [EXPAND_WINDOWSIMAGE_FIX.md](docs/fixes/EXPAND_WINDOWSIMAGE_FIX.md) |
| Get-Office Null Path | 2025-11-21 | Added required parameters | [DEFENDER_ORCHESTRATION_FIX_SUMMARY.md](docs/fixes/DEFENDER_ORCHESTRATION_FIX_SUMMARY.md) |
| New-AppsISO Null Path | 2025-11-21 | Added required parameters | [DEFENDER_ORCHESTRATION_FIX_SUMMARY.md](docs/fixes/DEFENDER_ORCHESTRATION_FIX_SUMMARY.md) |

---

### Bug Fixes (October 2025)

#### BITS and Download Fixes

| Fix | Date | Description | Documentation |
|-----|------|-------------|---------------|
| BITS Authentication 0x800704DD | 2025-10-24 | Fixed in background jobs | `ISSUE_BITS_AUTHENTICATION.md` |
| Multi-Method Download Fallback | 2025-10-24 | Added fallback system for BITS failures | `FALLBACK_SYSTEM_SUMMARY.md` |
| ESD Download Timeout | 2025-10-26 | Fixed timeout and WinPE mount failures | `ESD_DOWNLOAD_FIX.md` |
| Boolean Coercion Bug | 2025-10-24 | Fixed in Save-KB and Lenovo driver download | `CRITICAL_BUG_FIX_EDGE.md` |

#### DISM and Imaging Fixes

| Fix | Date | Description | Documentation |
|-----|------|-------------|---------------|
| DISM Service Timing | 2025-10-30 | Enhanced initialization timing | `DISM_SERVICE_TIMING_ENHANCEMENT.md` |
| DISM Service Dependency | 2025-10-29 | Fixed service dependency error | `DISM_SERVICE_FIX.md` |
| MSU Unattend.xml Extraction | 2025-10-29 | Fixed Issue #301 | `MSU_UNATTEND_FIX.md` |
| WinPE Mount Failures | 2025-10-26 | Fixed mount failures | `WINPE_MOUNT_FIX.md` |

---

### Enhancements

#### Architecture Improvements
- **Foundational Classes** (2025-10-24): Added FFUConfiguration, FFUConstants, FFULogger, FFUNetworkConfiguration, FFUPaths, FFUPreflightValidator
- **Proxy Support** (2025-10-24): Comprehensive proxy detection and configuration
- **Error Handling Standardization**: Consistent patterns across all modules
- **Cross-Version Compatibility**: Works in both PS5.1 and PS7+

#### Documentation
- 25+ detailed fix summaries in `docs/fixes/`
- 6 analysis documents in `docs/analysis/`
- 3 implementation plans in `docs/plans/`
- Executive summary: `docs/summaries/EXECUTIVE_SUMMARY_WEEK_2025-11-20.md`
- Architecture evaluation: `docs/summaries/ARCHITECTURE_ISSUES_PRIORITIZED.md`

#### Testing
- 38+ test scripts created
- 200+ individual test cases
- 100% pass rate maintained
- Categories: Unit, Integration, Syntax Validation, UI Integration

---

## Pre-Fork Changes (Upstream)

The following are notable changes from the upstream repository before this fork:

### 2509.1 UI Preview (September-October 2025)
- Windows 11 25H2 mapping
- JSON output standardization
- Multi-FFU USB build support
- Exit-code overrides for Winget apps
- Restore defaults feature
- Dynamic PE drivers option
- Auto-loading previous configuration

### 2507.1 UI Preview (July 2025)
- Complete UI overhaul
- Winget app support
- ARM64 support
- Configuration file support
- VHDX caching support
- Custom FFU naming

See `ChangeLog.md` for complete upstream history.

---

## Quick Reference

### Files Modified (This Fork)

**Core Scripts:**
- `BuildFFUVM.ps1` - Main orchestrator (reduced from 7,790 to 2,404 lines)
- `BuildFFUVM_UI.ps1` - WPF UI host (version display added)
- `BuildFFUVM_UI.xaml` - UI definition (About tab added)
- `Create-PEMedia.ps1` - WinPE media creator
- `USBImagingToolCreator.ps1` - USB tool generator
- `CaptureFFU.ps1` - FFU capture script (security documentation)
- `ApplyFFU.ps1` - FFU deployment script

**New Modules:**
- `Modules/FFU.Core/` - Core functionality
- `Modules/FFU.Constants/` - Configuration constants
- `Modules/FFU.ADK/` - ADK management
- `Modules/FFU.Apps/` - Application management
- `Modules/FFU.Drivers/` - Driver management
- `Modules/FFU.Imaging/` - Imaging operations
- `Modules/FFU.Media/` - Media creation
- `Modules/FFU.Messaging/` - Thread-safe UI/job messaging (v1.2.10)
- `Modules/FFU.Updates/` - Update handling
- `Modules/FFU.VM/` - VM lifecycle

**Common Modules:**
- `FFU.Common/FFU.Common.Core.psm1`
- `FFU.Common/FFU.Common.Winget.psm1`
- `FFUUI.Core/FFUUI.Core.*.psm1`

### Test Coverage

| Category | Test Files | Pass Rate |
|----------|------------|-----------|
| Module Integration | 8 | 100% |
| UI Integration | 3 | 100% |
| Syntax Validation | 5 | 100% |
| Unit Tests | 15+ | 100% |
| Fix Verification | 7+ | 100% |

### Known Remaining Issues

See `docs/summaries/ARCHITECTURE_ISSUES_PRIORITIZED.md` for:
- 4 Medium priority issues for future improvement
- Recommended enhancements

---

## Contributing

When making changes to this fork:

1. **Determine version increment:**
   - MAJOR (X.0.0): Breaking changes
   - MINOR (0.X.0): New features
   - BUILD (0.0.X): Bug fixes

2. **Update version:**
   - Edit `$script:FFUBuilderVersion` in `BuildFFUVM_UI.ps1`
   - Update "Current Version" in `CLAUDE.md`

3. **Document the change:**
   - Add entry to this changelog
   - Update Version History table in `CLAUDE.md`
   - Create detailed summary in `docs/fixes/` if applicable

4. **Create tests:**
   - Add test script in `Tests/`
   - Verify 100% pass rate

---

*Last Updated: 2026-01-25*
