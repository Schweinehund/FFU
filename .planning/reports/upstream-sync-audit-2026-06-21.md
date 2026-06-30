# Upstream Sync Audit — 2026-06-21

**Purpose:** Catalog of changes made in the upstream FFU project (`rbalsleyMSFT/FFU`, branch `UI`) that are NOT yet implemented (or only partially implemented) in this fork, so nothing is lost as we selectively port.

## Method

- **Fork divergence base:** `1130a830c7e30c102aa7a3d14017f2f49f97ba80` (2025-10-22, "Merge pull request #325 from arwidmark/UI_2510"). All upstream branches share this base.
- **Comparison branch:** `upstream/UI` — the direct continuation of our `UI_2510` lineage. 158 non-merge commits since base (upstream now versioned 2604.1, dated 2026-04-17).
- **Approach:** Feature/behavior comparison, NOT raw diff. The fork heavily refactored the monolithic `BuildFFUVM.ps1` / `BuildFFUVM_UI.ps1` into `FFUDevelopment/Modules/*` and did its own parallel work (Dell refactor → phase 40, 8-OEM support → phase 42, SUBST long paths → phase 38, winget ordering → phase 37, etc.). Verdicts below reflect whether equivalent *functionality* exists in the fork, verified against actual fork code.
- **Refresh command:** `git fetch upstream --prune` then `git log --no-merges 1130a83..upstream/UI`.

Verdict legend: **NOT-IN-FORK** = absent · **PARTIAL** = started/half-done · **ALREADY-IN-FORK** = covered (often as superset) · **INTENTIONAL** = deliberate divergence.

---

## TIER 1 — High impact (correctness bugs → wrong or failed artifacts)

| ID | Upstream commit | Change | Verdict | Notes |
|----|-----------------|--------|---------|-------|
| T1-1 | `5aaa1ad` | Refresh Windows SKU dynamically after fallback image selection | NOT-IN-FORK | Stale `$WindowsSKU` poisons FFU naming, VHDX cache metadata, CU planning. Fork uses legacy `Get-Index` (`FFU.Imaging.psm1`). |
| T1-2 | `d6688de` | 8 new manufacturers — **deploy-time** hardware detection | NOT-IN-FORK | Fork phase 42 added these as **build-time download providers only**. `ApplyFFU.ps1` `Get-SystemIdentityMetadata` + `Find-DriverMappingRule` + `Get-NormalizedManufacturer` still match only Dell/HP/Lenovo/MS. Need Panasonic/Viglen/AZW/ByteSpeed/Getac/Fujitsu/Intel baseboard-SKU arms. |
| T1-3 | `04dfb5f` | Normalize Windows LTSC releases for OEM drivers | NOT-IN-FORK | Dell/HP/Lenovo driver funcs are `ValidateSet(10,11)`; LTSC year (2019/2021/2024) fails. Add year→base-client normalization before OEM driver/model calls. |
| T1-4 | `6c0ee8a` | Use ADK BCDBoot (Secure Boot 2023 cert fix) | NOT-IN-FORK | `Add-BootFiles` (`FFU.Imaging.psm1`) still calls system `bcdboot`; images can fail to boot on devices with updated Secure Boot certs. |
| T1-5 | `96603f0` | Include disk size in VHDX cache validation | NOT-IN-FORK | `VhdxCacheItem` (`BuildFFUVM.ps1`) has no `Disksize`; cache wrongly reused on disk-size change → wrongly-sized image. ~6-line fix. |
| T1-6 | `2a77cf1` | MSI path quoting in msiexec args | NOT-IN-FORK | Win32 apps with spaces in MSI path fail to install. Isolated fix in `Apps/Orchestration/Install-Win32Apps.ps1`. |
| T1-7 | `42b0b0c` | Win10 LTSB/LTSC in-VM Cumulative Update install | NOT-IN-FORK | LTSC builds can't be offline-serviced (Win10 out of support). Larger port: new `Install-LTSCUpdate.ps1` + orchestrator entry + staging path + flags. |

### High-impact bug-fix bundle selected for immediate port (b)
T1-1 (SKU refresh), T1-5 (VHDX disk-size validation), T1-6 (MSI quoting), plus the Defender 30s delay (T2-3) and the USB-detection hardening bundle (T2-2). T1-2/T1-3/T1-4/T1-7 are larger and tracked for follow-up phases.

---

## TIER 2 — Medium impact (robustness / hardware-specific correctness)

| ID | Upstream commit | Change | Verdict | Notes |
|----|-----------------|--------|---------|-------|
| T2-1 | `b2a7ef5` | Robust image index selection by EditionId/InstallationType | NOT-IN-FORK | Fork `Get-Index` uses language-dependent name match + hardcoded index 4; fragile on non-English media. |
| T2-2 | `63ef35a` + `6df32b6` + `417be73` | USB detection hardening: empty-array guard, WMI→CIM, SerialNumber→UniqueId | NOT-IN-FORK | Port as a bundle; fixes multi/duplicate-drive misidentification. `BuildFFUVM.ps1` ~1187-1318, `FFUUI.Core.Config.psm1`. |
| T2-3 | `c6088d9` | 30s delay for Windows Security Platform in `Update-Defender.ps1` | NOT-IN-FORK | One-line `Start-Sleep -Seconds 30` seed; prevents intermittent Defender update failure in audit mode (AppxSVC not ready). |
| T2-4 | `2273cff` | `Threads` parameter for parallel driver-download throttling | NOT-IN-FORK | Fork downloads OEM drivers serially — partly a parallelization feature add. |
| T2-5 | `866fa25` | Surface driver matching via System SKU | PARTIAL | Fork persists SystemId only for Dell/HP/Lenovo; no Surface/MS SKU resolution in DriverMapping.json. |
| T2-6 | `554964f` | Cached download links for MS/Surface drivers | NOT-IN-FORK | `FFUUI.Core.Drivers.Microsoft.psm1` re-scrapes Download Center each call. |
| T2-7 | `7f10811` | Option to retain downloaded ESD files | NOT-IN-FORK | No `RemoveDownloadedESD`/`RetainESD` param/UI toggle; ESD deletion unconditional. Fork has `Get-WindowsESDMetadata` to hook reuse. |
| T2-8 | `27eebeb` + `d349e5e` | OS-scoped update cache folders + prune stale MSUs before servicing | NOT-IN-FORK | Coupled. Fork has flat `$KBPath` + its own `$kbCacheValid` reuse; needs adaptation. |
| T2-9 | `f838ef3` | Param-driven capture naming (remove registry-based FFU naming) | NOT-IN-FORK | Removes ~2 min registry sleep/build; fork still calls `Get-WindowsVersionInfo`. |
| T2-10 | `a8e2ab9` / `a8fecd1` | ADK detection via executable paths | NOT-IN-FORK | `Get-InstalledProgramRegKey` still registry-DisplayName based; fewer false "ADK not found". |
| T2-11 | `a8fecd1` (retrim portion) | `Optimize-Volume -ReTrim` on capture drive | PARTIAL | Fork has `Optimize-FFUCaptureDrive`; just add retrim step → smaller cached VHDX. |

---

## TIER 3 — Device naming / Unattend family (coherent feature group, port together)

| ID | Upstream commit | Change | Verdict | Notes |
|----|-----------------|--------|---------|-------|
| T3-1 | `4a2d8e6` | Flexible `DeviceNamingMode` framework (Template/Prefixes/None params + UI) | NOT-IN-FORK | Foundational; the rest build on it. |
| T3-2 | `38323e6` | `SerialComputerNames` CSV mapping mode + UI editor | PARTIAL | Fork's `ApplyFFU.ps1` already **consumes** `SerialComputerNames.csv` (legacy base). Missing: build-time CSV generation onto USB + UI create/load/save editor + formal naming mode. |
| T3-3 | `f1f1957` | Auto-generate ComputerName in Unattend XML | NOT-IN-FORK | Lets users supply minimal templates without hand-authored ComputerName. |
| T3-4 | `7bd5dec` | Custom unattend XML file path selection (x64/arm64) | NOT-IN-FORK | Fork hardcodes `unattend_x64.xml`/`unattend_arm64.xml` from fixed folder. |
| T3-5 | `1ea1ef6` | `Read-MenuSelection` deployment-menu refactor + `*` ComputerName fallback | NOT-IN-FORK | Skippable prompts. **Reconcile** with fork's own NICE-02 skip-drivers logic, don't overwrite. |
| T3-6 | `82bac17` / `24f10b8` / `6b76f6b` | Prompt naming option / state-tracking fix / label rename | NOT-IN-FORK | Increments on T3-1; port together. |

---

## TIER 4 — UI overhaul (interlocking; treat as one optional project, NOT piecemeal)

Upstream's Fluent theme + sidebar nav + shared page shell + expandable sections + Home build/release status + column auto-resize + margin pass form one interlocking overhaul that assumes the new shell. Fork still uses a left `TabControl`. Porting individually = high-conflict.

| ID | Upstream commit | Change | Verdict |
|----|-----------------|--------|---------|
| T4-1 | `7678f61` | Modern navigation sidebar + Fluent theme support | NOT-IN-FORK |
| T4-2 | `b28344d` | Convert UI sections to expandable controls | PARTIAL (only `expOptionalFeatures`) |
| T4-3 | `98c1644` / `d6e6287` | Shared page shell + dynamic titles + styling | NOT-IN-FORK |
| T4-4 | `db04455` | Home page build/release status | NOT-IN-FORK |
| T4-5 | `d6361da` | Automatic ListView column resizing | NOT-IN-FORK |
| T4-6 | `aca968c` | UI margins/alignment consistency | NOT-IN-FORK |
| T4-7 | `80147ed` | Windows Media Source (ESD vs ISO radios) | PARTIAL (ISO path exists, no radios) |
| T4-8 | `42ed281` | Header checkbox alignment in grid view | NOT-IN-FORK |
| T4-9 | `eac8be3` | Custom BYO app-list file path in UI | PARTIAL (backend `-UserAppListPath` exists, UI control missing) |

### Standalone UI fixes worth grabbing regardless (not tied to the shell)
| ID | Upstream commit | Change | Verdict |
|----|-----------------|--------|---------|
| T4-S1 | `dc801e9` | Dependency validation for copying drivers (CopyDrivers requires BuildUSBDrive) | NOT-IN-FORK |
| T4-S2 | `b4305a1` | Fix sorting-after-filter breaking the Drivers filter | NOT-IN-FORK |
| T4-S3 | `f09c989` | Scope select-all to visible filtered items | NOT-IN-FORK |

---

## TIER 5 — Low impact (quality of life / hygiene)

| ID | Upstream commit | Change | Verdict |
|----|-----------------|--------|---------|
| T5-1 | `c135ad0` | Capture FFU from host-mounted VHDX on the **InstallApps=$true** path | PARTIAL (fork has only the no-apps branch) |
| T5-2 | `5374163` | Malformed-JSON backup/rebuild fallback during parallel app updates | PARTIAL (fork has mutex + atomic write, not the fallback) |
| T5-3 | `5ca5312` | Allow Office install on ARM64 VMs | NOT-IN-FORK (one-line unblock; experimental upstream) |
| T5-4 | `78212f0` | Experimental VM networking opt-in (`-EnableVMNetworking`) | NOT-IN-FORK |
| T5-5 | `9bacac8` | dirty.txt relative-path creation fix (`BuildFFUVM.ps1` ~2598) | PARTIAL (cleanup side fixed, creation side not) |
| T5-6 | `2d6f6e5` / `5580824` | Silence robocopy / Format-Volume output | NOT-IN-FORK |
| T5-7 | `24c81c2` | Remove redundant Images-dir creation in `USBImagingToolCreator.ps1` | NOT-IN-FORK |
| T5-8 | `422bc33` | Generalized FileBackups schema | PARTIAL (fork has own timestamp-based mechanism) |
| T5-9 | `db22c18` | Simplify products catalog request to amd64 | NOT-IN-FORK (cosmetic; arm64 branch still works) |
| T5-10 | `9a59b9f` / `3cb4003` | Remove Path column / driver-source UI clarity | NOT-IN-FORK (cosmetic) |
| T5-11 | `3d1a586` | Driver-cleanup helper refactor | PARTIAL (fork cleanup inline per-OEM) |
| T5-12 | `11b3e12` | Sanitized human-readable Dell driver name for model list | PARTIAL |

---

## ALREADY IN FORK — do NOT port (covered, often as superset)

BITS-for-ESD (`7948201`), BITS priority (`8229aa7`) + HTTP fallback (`e67590d`), winget dependency ordering (`ad35a0b`), AppList order (`b2352e3`), Win32 JSON regen (`25fe902`), ESD-version CU skip (`86d122a`), xcopy PPKG quoting (`1836721`), SUBST long-path injection (`44aa4d3`, phase 38), skip-driver-install (`e076e9f`), generic driver fallback (`beb48e5`), restrict-to-known-OEMs (`fc4a71f`), TTL OEM catalog cache (`02e429d`), Dell CatalogIndexPC refactor (`66a9026`/`658c57e`/`4ce9183`, phase 40), SystemId/MachineType tracking (`89601ef`, phase 39), HP SystemId (`de80ac5`), model-name standardization (`2350653`), driver injection resilience (`7231f62`), PE driver-copy buffer fix (`ed5b7f6`, phase 38), skip empty driver folders (`19081a2`), interactive multi-disk selection (`3524d02`), native WinPE package add (`0607cf5`).

## INTENTIONAL DIVERGENCE — do NOT port

- `1feed40` Run builds in pwsh process for reliable cancel — fork deliberately uses `Start-ThreadJob` for credential inheritance (see CLAUDE.md "Why ThreadJob?").
- `667edf3` (GroupManifest Display CDATA) and parts of `11b3e12` target upstream's old `Get-DellLatestDriverPackages` / full-`CatalogPC.cab` path, which the fork **replaced** with CatalogIndexPC — porting would regress.
- `93c4679` Remove Surface-specific validation — no-op for fork (never had the gate).

---

## Progress

| Tier 1/2 ID | Status | Notes |
|-----------|--------|--------------|
| T1-6 MSI quoting | **DONE** v1.10.2 | `Format-MsiArguments` ported verbatim (`2a77cf1`) |
| T1-5 VHDX disk-size validation | **DONE** v1.10.2 | `96603f0` |
| T2-3 Defender 30s delay | **DONE** v1.10.2 | `c6088d9` |
| T2-2a USB WMI→CIM | **DONE** v1.10.2 | `6df32b6` (2 USB calls; OS call already CIM in fork) |
| T2-2b USB empty-array guard | **DONE** v1.10.2 | `63ef35a` |
| T2-2c USB SerialNumber→UniqueId | **DEFERRED** | `417be73` — config-breaking, 5 files; needs own phase + config migration |
| T1-1 SKU refresh-after-fallback | **DEFERRED** | `5aaa1ad` — 227-line refactor, 3 new functions; own phase + tests |
| T1-2 8-OEM deploy detection | Backlog | `d6688de` — extend ApplyFFU `Get-SystemIdentityMetadata`/`Find-DriverMappingRule` |
| T1-3 LTSC driver normalization | Backlog | `04dfb5f` |
| T1-4 ADK BCDBoot | Backlog | `6c0ee8a` |
| T1-7 Win10 LTSC in-VM CU | Backlog | `42b0b0c` |

**Pre-existing unrelated test failure noted during this work:** `Tests/Unit/BuildFFUVM.ParameterValidation.Tests.ps1` → "Make has ValidateSet for OEMs" expects only `Microsoft/Dell/HP/Lenovo` but the committed phase-42 `Make` ValidateSet already lists 12 OEMs. Stale test from phase 42 (present on HEAD, not caused by the sync ports). Should be updated under phase 42 verification.

*Audit generated 2026-06-21. Refresh with `git fetch upstream --prune && git log --no-merges 1130a83..upstream/UI`.*
