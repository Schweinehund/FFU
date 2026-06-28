# Requirements: FFU Builder — v1.12.0 Upstream Sync

**Defined:** 2026-06-25
**Core Value:** Enable rapid, reliable Windows deployment through pre-configured FFU images with minimal manual intervention.
**Scoping basis:** `.planning/reports/upstream-sync-verdict-2026-06-25.md` (adversarial review of the 2026-06-21 upstream audit). Each requirement notes its upstream item ID / commit and review verdict.

## v1.12.0 Requirements

### Capture/Boot Correctness (P1)

- [x] **CORRECT-01**: When the user's exact Windows SKU isn't present and they pick a fallback image, the resulting FFU is named, cached, and serviced as the *selected* edition — not the originally-requested one *(T1-1 `5aaa1ad`, PORT)*
- [x] **CORRECT-02**: User can download OEM drivers for LTSC builds (2019/2021/2024) without the driver step failing on a release-year validation error *(T1-3 `04dfb5f`, PORT)*
- [x] **CORRECT-03**: Captured images boot on devices with updated Secure Boot 2023 certificates because boot files are written with the ADK's BCDBoot rather than the host's *(T1-4 `6c0ee8a`, PORT)*
- [x] **CORRECT-04**: The correct Windows edition is captured from non-English and multi-edition media by selecting the image index via EditionId/InstallationType instead of a localized name substring *(T2-1 `b2a7ef5`, PORT)*

### Driver Build/Deploy Correctness (P2)

- [ ] **DRVR-01**: User can auto-match Microsoft Surface drivers by System SKU rather than relying on an exact model-name string match *(T2-5 `866fa25`, PORT)*
- [ ] **DRVR-02**: Microsoft/Surface driver download links are cached so builds don't break or stall when the live download page changes or a proxy blocks the scrape *(T2-6 `554964f`, PORT)*
- [ ] **DRVR-03**: Captured FFU/cached VHDX is reclaimed to minimum size via `Optimize-Volume -ReTrim` before compaction, producing a smaller deployable artifact *(T2-11 `a8fecd1`, PORT)*
- [ ] **DRVR-04**: At deploy time, the 8 newer OEMs (Panasonic, Getac, Fujitsu, etc.) are matched with SystemID-level precision, not only the model-name fallback *(T1-2 `d6688de`, ADAPT — fork's 3-tier fallback already works; this adds the precision tier)*

### Driver-Grid UI Fixes (P2)

- [x] **DGRID-01**: Sorting the driver list while a filter is active keeps the filter applied instead of resetting to all rows *(T4-S2 `b4305a1`, PORT — live bug)*
- [x] **DGRID-02**: Selecting/deselecting drivers while filtered, then saving, preserves selections for filtered-out (hidden) rows; the select-all header checkbox is correctly aligned *(T4-S3 `f09c989` + T4-8 `42ed281`, PORT — save-path data leak)*
- [x] **DGRID-03**: The UI prevents an invalid CopyDrivers configuration by requiring BuildUSBDrive when CopyDrivers is enabled *(T4-S1 `dc801e9`, PORT)*

### Update Cache & Capture Naming (P2)

- [ ] **CACHE-01**: Update packages are cached per-OS and stale/cross-OS MSUs are pruned before servicing, so an image is never serviced with a leftover update from a different release *(T2-8 `27eebeb`+`d349e5e`, PORT)*
- [ ] **CACHE-02**: FFU file naming is driven by build parameters, avoiding the offline registry-hive read (and its ~2 min of sleeps) while preserving the existing CBS/CSI corruption guards and DisplayVersion derivation *(T2-9 `f838ef3`, ADAPT)*

### Device Naming & Unattend (P2 — atomic family, includes config migration)

- [ ] **NAMING-01**: User can choose a device-naming mode (Template / Prefixes / Serial mapping / Prompt / None) via a unified DeviceNamingMode framework, with config schema migration for existing configs *(T3-1 `4a2d8e6`, ADAPT — foundation)*
- [ ] **NAMING-02**: User can author, load, and save a SerialComputerNames CSV in the UI, and the builder stages it onto the USB for serial→name mapping at deploy time *(T3-2 `38323e6`, ADAPT — completes the deploy-side consumer the fork already ships)*
- [ ] **NAMING-03**: A ComputerName is auto-generated into the Unattend XML when the user supplies a minimal template, instead of the deploy step throwing on a missing element *(T3-3 `f1f1957`, PORT)*
- [ ] **NAMING-04**: User can select a custom Unattend XML file path per architecture (x64/arm64), wired through both the USB-copy and audit-mode injection paths *(T3-4 `7bd5dec`, ADAPT)*
- [ ] **NAMING-05**: The DeviceNamingMode UI tracks state/defaults correctly and uses clear labels (prompt option, serial-mapping labels) *(T3-6 `82bac17`/`24f10b8`/`6b76f6b`, ADAPT — folded into NAMING-01/02)*
- [ ] **NAMING-06**: Deployment menu prompts are skippable via a shared Read-MenuSelection helper and unattend supports the `*` default-name fallback — ported surgically so the fork's NICE-02 skip-drivers logic is preserved *(T3-5 `1ea1ef6`, ADAPT — surgical)*
- [ ] **NAMING-07**: USB drives are identified by UniqueId instead of SerialNumber, eliminating mis-selection of duplicate/blank-serial drives, with config migration for stored identifiers *(T2-2c `417be73`, ADAPT — config-breaking)*

### Shell-Independent UI (P2/P3)

- [ ] **UIX-01**: User can choose the Windows media source (download ESD vs supply ISO) via radio buttons that toggle the relevant fields *(T4-7 `80147ed`, ADAPT — backend already wired)*
- [ ] **UIX-02**: Dense option sections (General Build Options, USB Drive Options, Post-Build Cleanup) are collapsible via expandable controls *(T4-2 `b28344d`, ADAPT)*
- [ ] **UIX-03**: ListView columns resize automatically to fit content/window width *(T4-5 `d6361da`, ADAPT)*
- [ ] **UIX-04**: User can select a custom (BYO) app-list file path in the UI, exposing the existing `-UserAppListPath` backend capability *(T4-9 `eac8be3`, ADAPT — UI control only)*

### Hygiene & Robustness (P3)

- [ ] **HYG-01**: A corrupt `WinGetWin32Apps.json` from an interrupted prior run is backed up and rebuilt rather than aborting the build *(T5-2 `5374163`, ADAPT — catch/backup only; fork already has mutex+atomic write)*
- [ ] **HYG-02**: The `dirty.txt` marker is created at an absolute path so the dirty-environment check works regardless of current working directory (ThreadJob/UI contexts) *(T5-5 `9bacac8`, PORT)*
- [ ] **HYG-03**: Robocopy and Format-Volume calls in the USB tooling and cache paths run without spamming console/log output *(T5-6 `2d6f6e5`/`5580824`, ADAPT)*
- [ ] **HYG-04**: Redundant Images-directory creation is removed from `USBImagingToolCreator.ps1` *(T5-7 `24c81c2`, PORT)*
- [ ] **HYG-05**: Per-OEM driver folder cleanup uses a shared helper that guards against deleting outside the drivers tree or the drivers root *(T5-11 `3d1a586`, ADAPT)*
- [ ] **HYG-06**: User can opt to retain downloaded ESD files for reuse across builds instead of having them deleted unconditionally *(T2-7 `7f10811`, ADAPT)*

## Future Requirements (deferred — verify-first)

### Deferred Upstream Items

- **LTSC-01**: Win10 LTSB/LTSC in-VM Cumulative Update install — port only after confirming the fork's offline LTSC servicing actually fails on 1607/1809 *(T1-7 `42b0b0c`, DEFER)*
- **VMNET-01**: Experimental opt-in VM networking for Hyper-V builds (`-EnableVMNetworking`) *(T5-4 `78212f0`, DEFER — experimental)*

## Out of Scope

| Feature | Reason |
|---------|--------|
| Tier-4 Fluent theme + sidebar nav + page shell + Home status (T4-1/T4-3/T4-4/T4-6) | Interlocking rewrite vs the fork's TabControl XAML; near-zero standalone value, high conflict. Separate future project (user-confirmed 2026-06-25). |
| Host-VHDX capture on InstallApps path (T5-1 `c135ad0`) | Would regress the fork's hardened VM-WinPE + VMware capture architecture and credential sanitization. |
| Sanitized Dell driver name via old catalog path (T5-12 `11b3e12`) | Targets the deprecated `Get-DellLatestDriverPackages`/`CatalogPC.cab` path the fork replaced with CatalogIndexPC — would regress. |
| Office install on ARM64 VMs (T5-3 `5ca5312`) | Fork intentionally gates this off for stability (no internet in build VM). |
| Generalized FileBackups schema (T5-8 `422bc33`) | Fork's `.session`/checkpoint mechanism already covers the substance; 549-line conflicting change. |
| Threads param for parallel driver download (T2-4 `2273cff`) | Pure performance, no correctness gain. |
| ADK detection via executable paths (T2-10 `a8e2ab9`) | Fork's ADK detection is already exe/path-based with on-disk verification. |
| amd64-only products catalog request (T5-9 `db22c18`) | Fork's arch branch works; upstream change is an unverified assumption. |
| Remove Path column / driver-source clarity (T5-10 `9a59b9f`/`3cb4003`) | Cosmetic; defer to any future UI-polish work. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORRECT-01 | Phase 51 | Complete |
| CORRECT-02 | Phase 51 | Complete |
| CORRECT-03 | Phase 51 | Complete |
| CORRECT-04 | Phase 51 | Complete |
| DGRID-01 | Phase 52 | Complete |
| DGRID-02 | Phase 52 | Complete |
| DGRID-03 | Phase 52 | Complete |
| DRVR-01 | Phase 53 | Pending |
| DRVR-02 | Phase 53 | Pending |
| DRVR-03 | Phase 53 | Pending |
| DRVR-04 | Phase 53 | Pending |
| CACHE-01 | Phase 54 | Pending |
| CACHE-02 | Phase 54 | Pending |
| NAMING-01 | Phase 55 | Pending |
| NAMING-07 | Phase 55 | Pending |
| NAMING-02 | Phase 56 | Pending |
| NAMING-03 | Phase 56 | Pending |
| NAMING-04 | Phase 56 | Pending |
| NAMING-05 | Phase 56 | Pending |
| NAMING-06 | Phase 56 | Pending |
| UIX-01 | Phase 57 | Pending |
| UIX-02 | Phase 57 | Pending |
| UIX-03 | Phase 57 | Pending |
| UIX-04 | Phase 57 | Pending |
| HYG-01 | Phase 58 | Pending |
| HYG-02 | Phase 58 | Pending |
| HYG-03 | Phase 58 | Pending |
| HYG-04 | Phase 58 | Pending |
| HYG-05 | Phase 58 | Pending |
| HYG-06 | Phase 58 | Pending |

**Coverage:**
- v1.12.0 requirements: 30 total
- Mapped to phases: 30 ✓ (Phases 51-58)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-25*
*Last updated: 2026-06-25 after roadmap creation — all 30 requirements mapped to Phases 51-58, 100% coverage*
