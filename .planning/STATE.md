---
gsd_state_version: 1.0
milestone: v1.12.0
milestone_name: Upstream Sync — Correctness, Drivers & Device Naming
status: executing
last_updated: "2026-06-27T00:09:25.821Z"
last_activity: 2026-06-27
progress:
  total_phases: 8
  completed_phases: 0
  total_plans: 4
  completed_plans: 2
  percent: 0
---

# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-25)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** Phase 51 — Capture/Boot Correctness

## Current Position

Phase: 51 (Capture/Boot Correctness) — EXECUTING
Plan: 3 of 4
Status: Ready to execute
Last activity: 2026-06-27

## Shipped Milestones

| Milestone | Status | Phases | Date |
|-----------|--------|--------|------|
| v1.8.0 Codebase Health | SHIPPED | 1-10 (33 plans) | 2026-01-20 |
| v1.8.1 Bug Fixes | SHIPPED | 11-13 (5 plans) | 2026-01-20 |
| v1.8.3 VMware UI Settings | SHIPPED | 14 (2 plans) | 2026-01-21 |
| v1.9.0 Reliability Hardening | SHIPPED | 15-25 (44 plans) | 2026-01-24 |
| v1.9.1 Build Phase Integration | SHIPPED | 26 (3 plans) | 2026-01-24 |
| v1.9.2 Smart Configuration & Bug Fixes | SHIPPED | 27-30 (10 plans) | 2026-01-25 |
| v1.9.3 OEM Driver Bug Fixes | SHIPPED | 31-33 (5 plans) | 2026-01-27 |
| v1.10.0 Upstream Cherry-Pick | SHIPPED | 34-43 (31 plans) | 2026-02-02 |
| Phase 44 DISM Resilience (ad-hoc) | SHIPPED | 44 | 2026-03-12 |
| v1.11.0 USB from Existing Components | SHIPPED | 45-50 (18 plans) | 2026-06-26 |

**Total shipped:** 50 phases, 151 plans across 10 milestones

## Current Milestone: v1.12.0 Upstream Sync (Phases 51-58)

**Goal:** Selectively port the remaining high-value upstream changes into the fork's modular architecture — correctness fixes, driver-grid bug fixes, the device-naming/unattend family, shell-independent UI, and hygiene — while skipping the Fluent shell rewrite and regression-risk ports.

**Scoping basis:** `.planning/reports/upstream-sync-verdict-2026-06-25.md`

| Phase | Goal | Requirements |
|-------|------|--------------|
| 51 Capture/Boot Correctness | No wrong-edition/unbootable/LTSC-failing artifacts (P1 core) | CORRECT-01..04 |
| 52 Driver-Grid UI Fixes | Filter/sort/save-scope correctness + CopyDrivers validation | DGRID-01..03 |
| 53 Driver Build/Deploy Correctness | Surface SKU match, cached MS links, ReTrim, 8-OEM deploy precision | DRVR-01..04 |
| 54 Update Cache & Capture Naming | OS-scoped cache + prune, param-driven FFU naming | CACHE-01..02 |
| 55 Device-Naming Foundation & Migrations | DeviceNamingMode framework + UniqueId, atomic config migrations | NAMING-01, NAMING-07 |
| 56 Device-Naming Consumers & Unattend | Serial CSV, auto ComputerName, custom unattend, surgical menu/`*` | NAMING-02..06 |
| 57 Shell-Independent UI | ESD/ISO radios, expandable sections, ListView resize, BYO app-list | UIX-01..04 |
| 58 Hygiene & Robustness | JSON recovery, dirty.txt path, output silencing, cleanup guards, ESD retain | HYG-01..06 |

**Coverage:** 30/30 requirements mapped ✓

## Accumulated Context

### Decisions

- v1.12.0 roadmap: Device-Naming family kept in two tightly-ordered phases — Phase 55 (NAMING-01 framework + NAMING-07 UniqueId, both config-schema migrations landing atomically) before Phase 56 (NAMING-02/03/04/05/06 consumers that depend on the framework). NAMING-06 ported surgically to preserve the fork's NICE-02 skip-drivers logic.
- v1.12.0 roadmap: P1 correctness (CORRECT-01..04) is the first phase (51) — must-ship core; all later phases depend on it.
- v1.12.0 roadmap: Phases 52/53/54/57/58 are largely independent of one another (all depend only on Phase 51) — eligible for parallel planning per config.json.
- Phase 44: DISM auto-repair (fltmc filters check, registry repair, service restart) implemented as ad-hoc work outside milestone
- v1.11.0: Config schema first (HIGH cost if deferred — saved configs require migration)
- v1.11.0: FFU.ArtifactScanner as isolated module (defines data contract before UI or pipeline work)
- v1.11.0: Cancel/reset mode-awareness addressed in Phase 49 (auditing lines 332, 413, 827 of BuildFFUVM_UI.ps1 and line 35 of FFUUI.Core.StateRecovery.psm1)
- v1.11.0: Selective rebuild (Phase 50) deferred until end — highest complexity, depends on all prior phases
- [Phase 46]: InModuleScope required for all PowerShell class/enum assertions in Pester — module types not exported to caller scope (Pitfall 4 from 46-RESEARCH.md)
- [Phase 46]: Architecture regex uses (?:^|[^a-z]) anchors not \b word boundary — underscore is a word character so \b fails with FFU filename patterns like Windows11_23H2_x64_Pro.ffu
- [Phase 46]: Get-Command try/catch used for hyphenated function availability (Test-FFUWimMount) — $function: drive syntax invalid for hyphenated names
- [Phase 46]: @($result | Where-Object) null-filter pattern required before typed array assignment to prevent @($null) coercion in typed PowerShell class properties
- [Phase 45]: v1.3 migration is purely additive - ActiveMode=FullBuild and USBMode.Artifacts with 7 types injected via #region blocks
- [Phase 45]: ActiveMode and USBMode added to JSON schema root properties with ArtifactEntry definition; stubs in FFUUI.Core.Config.psm1 ensure config round-trip; fallback version updated to 1.3
- [Phase 47-usb-mode-pipeline-entry]: Get-USBDrive (not Get-FFUUSBDrives) is the correct function — returns tuple ($USBDrives, $USBDrivesCount)
- [Phase 48]: RadioButton GroupName=ActiveMode aligns with config schema field from Phase 45; rbFullBuild IsChecked=True matches FullBuild default
- [Phase 48-02]: usbModeTab Visibility=Collapsed by default; required artifact CheckBoxes IsChecked=True (FFU, DeployISO); optional CheckBoxes IsChecked=False; all 46 named controls use usb{ArtifactType}{Property} convention for Phase 49 wiring
- [Phase 49]: Typed WPF Brushes/FontStyles used exclusively in Invoke-USBArtifactScan — no bare strings to avoid WPF type conversion failures
- [Phase 49]: isLoadingConfig flag added to uiState.Flags to guard Invoke-USBArtifactScan from premature scan during config load
- [Phase 49]: 7 inline browse handlers chosen over shared helper to match established Add_Click pattern; usbDriveObjects parallel array stores drive PSCustomObjects for USB creation time lookup
- [Phase 49]: Config load ordering: artifact paths loaded BEFORE ActiveMode RadioButton set to prevent premature scan overwriting user paths (Pitfall 5)
- [Phase 49]: USB Mode branch placed after validation-errors check, before Full Build path, returns to skip Full Build
- [Phase 49]: DispatcherTimer Tick handler copied verbatim from Full Build for mode-agnostic polling
- [Phase 49-05]: Pre-build validation "Build canceled" messages (lines 451, 785-879) left as-is — they occur before USB mode is relevant; cancel/cleanup paths (lines 345, 417) made mode-aware
- [Phase ?]: Phase 50-05: Rebuild execution block placed before ISO mount check;  reads configData directly for early placement before Step 4; Invoke-ParallelProcessing DownloadDriverByMake reused for Drivers rebuild (no new loop)
- [Phase ?]: [Phase 51-01]: Get-WindowsImageSelection uses EditionId (primary) then exact ImageName -eq (fallback) then auto-select or throw
- [Phase 51-02]: Add-BootFiles hard-fails (throw) when ADK bcdboot not found at {AdkPath}\...\BCDBoot\bcdboot.exe — no silent host bcdboot fallback; arch maps arm64->arm64, all else->amd64
- [Phase 51-02]: Test-FFUADK CHECK 5 reuses $archPath from CHECK 4; errors/missingFiles feed existing result block; no new result-construction code needed
- [Phase 51-02]: ADK bcdboot path logged at Add-BootFiles time (D-13); cert-variant caveat (Dec 2024 ADK stages 2011 certs) documented in inline comment

### Research Flags for Planning

- Phase 53 (DRVR-04): Audit ApplyFFU.ps1 deploy-time 3-tier fallback before adding SystemID precision tier — must NOT regress the existing model-name fallback for the 8 newer OEMs (NICE work from v1.10.0).
- Phase 54 (CACHE-02): Capture-naming change must preserve the two `Start-Sleep 60` CBS/CSI corruption guards and replicate the hive DisplayVersion derivation logic — these are documented guards, not removable.
- Phase 55 (NAMING-01/07): Both carry config-schema migrations — follow the v1.11.0 additive-migration precedent (Phase 45) and FFU.ConfigMigration; ensure migration is atomic so a partially-migrated config never occurs.
- Phase 56 (NAMING-06): Read-MenuSelection / `*` fallback port is surgical — verify the fork's NICE-02 skip-drivers logic in ApplyFFU.ps1 / Orchestrator is preserved.
- Phase 51 (CORRECT-01): SKU refresh after fallback touches naming, caching, and servicing paths — trace all three consumers of the requested-vs-selected edition.

### Blockers

None.

### Deferred Verification (carry forward)

- **Phase 50 Human UAT (4 items) — DEFERRED 2026-06-25.** All 4 GUI tests in `50-HUMAN-UAT.md` (ComboBox tier rendering, config round-trip, degraded-artifact rendering, end-to-end selective rebuild) were never executed. Deferred by user decision: upcoming USB Mode changes are expected to invalidate these scenarios, so they will be re-run as a single full test pass when those changes are ready. NOTE: v1.12.0 is upstream-sync work (not USB Mode changes), so this remains deferred — do not pull into v1.12.0 verification scope.

## Deferred Items

Items acknowledged and deferred at v1.11.0 milestone close on 2026-06-26. Most are the USB Mode GUI testing the user chose to defer until the next round of USB Mode changes is ready for a single full test pass; Phase 42/48 verification gaps and the 2 todos are pre-existing tech debt unrelated to v1.11.0. None of these are in v1.12.0 scope (upstream sync, not USB Mode).

| Category | Item | Status |
|----------|------|--------|
| uat | Phase 49 (49-HUMAN-UAT.md) | partial — 3 pending scenarios |
| uat | Phase 50 (50-HUMAN-UAT.md) | deferred — 4 scenarios, re-run as one pass |
| verification | Phase 49 (49-VERIFICATION.md) | human_needed |
| verification | Phase 50 (50-VERIFICATION.md) | human_needed |
| verification | Phase 42 (42-VERIFICATION.md) | gaps_found (pre-existing, v1.10.0) |
| verification | Phase 48 (48-VERIFICATION.md) | gaps_found (placeholders wired in Phase 49) |
| todo | 2026-03-12-evaluate-frontend-architecture-alternatives | pending |
| todo | 2026-03-12-upstream-sync-check-for-new-commits | addressed — v1.12.0 ports the audited backlog |

**Requirement gaps (implemented, verification deferred):** DISC-01, VALID-01, VALID-02, VALID-03, VALID-04 — USB Mode GUI verification, not in v1.12.0 scope; pull in alongside future USB Mode work.

## Session Continuity

Last session: 2026-06-27T00:09:25.807Z
Stopped at: Phase 51 Plan 02 complete
Resume file: None
Next action: Execute Phase 51 Plan 03 (CORRECT-02 - LTSC driver year normalization)

---
*State updated: 2026-06-25 — v1.12.0 roadmap created, 8 phases (51-58), 30 requirements mapped*

## Performance Metrics

| Phase | Plan | Duration | Notes |
|-------|------|----------|-------|
| Phase 50 P01 | 720 | 3 tasks | 4 files |
| Phase 50 P03 | 15 | 2 tasks | 5 files |
| Phase 50 P05 | 876 | 2 tasks | 2 files |
| Phase 50 P06 | 8 | 3 tasks | 3 files |
| Phase 51 P01 | 45 | 3 tasks | 5 files |
| Phase 51 P02 | 20 | 3 tasks | 5 files |

## Operator Next Steps

- Plan Phase 51 (Capture/Boot Correctness) with /gsd-plan-phase 51
- Phases 52/53/54/57/58 depend only on Phase 51 and are eligible for parallel planning per config.json
