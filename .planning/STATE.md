# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-28)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** Milestone v1.10.0 Upstream Cherry-Pick

## Current Position

**Milestone:** v1.10.0 Upstream Cherry-Pick
**Phase:** 36 of 43 (CU Skip + ESD BITS) - COMPLETE
**Plan:** 3 of 3 complete (36-01, 36-02, 36-03)
**Status:** Phase complete
**Last activity:** 2026-01-28 — Completed 36-03-PLAN.md

Progress: ███░░░░░░░ 29% (8 of 28 plans complete across 10 phases)

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

**Total:** 33 phases, 102 plans shipped across 7 milestones

## v1.10.0 Phases

| Phase | Goal | Requirements | Status |
|-------|------|-------------|--------|
| 34: Winget Bug Fixes | JSON safety + MSI path quoting | BUGFIX-01, BUGFIX-03 | Verified (3/3 plans) |
| 35: PPKG Path Quoting | xcopy space handling | BUGFIX-02 | Verified (1/1 plan) |
| 36: CU Skip + ESD BITS | Version comparison + BITS downloads | BUGFIX-04, DL-01 | Complete (3/3 plans) |
| 37: Winget Ordering | App ordering + dependency handling | WINGET-01, WINGET-02 | Pending |
| 38: SUBST Drive Mapping | Long path reliability | PATH-01 | Pending |
| 39: Model Normalization | Brand dedup + SystemID | DRV-02, DRV-03 | Pending |
| 40: Dell Refactoring | CatalogIndexPC logic | DRV-01 | Pending |
| 41: Driver Matching + UI | Fallback, PE copy, UI clarity | DRV-05, DRV-06, DRV-07 | Pending |
| 42: New OEM Manufacturers | 8 new OEMs | DRV-04 | Pending |
| 43: Deployment Improvements | Multi-disk, empty drivers, delay | DEPLOY-01..03, NICE-01..02 | Pending |

## Decisions Log

| Phase | Decision | Rationale | Impact |
|-------|----------|-----------|--------|
| 34-01 | Use same named mutex (WinGetWin32AppsJsonLock) across Add-Win32SilentInstallCommand and Get-Apps | Both functions write to WinGetWin32Apps.json requiring cross-function synchronization | Prevents race conditions between parallel downloads and AppList.json overrides |
| 34-01 | Add duplicate detection inside Add-Win32SilentInstallCommand lock | Multiple parallel downloads might try to add same app simultaneously | Prevents duplicate entries without caller-level deduplication |
| 34-01 | Re-read JSON inside Get-Apps lock | File content may change between Test-Path and write | Prevents lost updates when multiple operations modify JSON |
| 34-02 | Use backtick-escaped quotes for all installer paths (EXE, MSI, default) | ProcessStartInfo.FileName requires quoted paths when they contain spaces | Eliminates "file not found" errors for apps in folders with spaces |
| 34-02 | Add .Trim() to MSI Arguments string concatenation | Empty $silentInstallSwitch would result in trailing whitespace | Produces clean Arguments strings for all MSI scenarios |
| 34-03 | Test sequential writes instead of parallel writes | PowerShell 5.1 lacks ForEach-Object -Parallel (PS7+ only) | Sequential writes adequately validate JSON corruption prevention and mutex behavior |
| 34-03 | Normalize JSON single-object deserialization | ConvertFrom-Json returns single object when array has one element | Pattern `if ($apps -isnot [array]) { $apps = @($apps) }` enables consistent test assertions |
| 34-03 | Create New-TestAppFolder helper function | 11 tests need app folders with installers and YAML | DRY principle reduces duplication and improves test maintainability |
| 35-01 | Use backtick-escaped quotes for xcopy PPKG paths consistent with Phase 34 | Codebase consistency with Phase 34 quoting pattern | Eliminates "file not found" for PPKG files with spaces |
| 35-01 | Copy-Item as fallback for xcopy failures | Copy-Item handles spaces natively without quoting | Resilient file copy when xcopy fails for any reason |
| 35-01 | PPKG copy failure is non-blocking | PPKG is optional and should not halt deployment | Deployment continues with WARNING when PPKG copy fails |
| 35-01 | WARNING includes source, destination, and error | Field diagnosis without access to full logs | Users can troubleshoot PPKG failures from console output |
| 36-01 | Use 4-part version regex for ESD filename parsing | Full version (10.0.26100.1742) enables accurate comparison vs CU versions | Correct skip/download decisions based on precise version matching |
| 36-01 | Fall back to downloading CU on version parse failure | Safe default ensures builds never miss needed updates due to parsing errors | Robustness - parse failures degrade gracefully |
| 36-01 | Guard CU skip with WindowsRelease == 11 and no ISOPath | ESD metadata only applies to Windows 11 MCT downloads, not ISO or Win10 | Prevents incorrect skip attempts on unsupported build types |
| 36-01 | Track skipped update names in cachedIncludedUpdateNames | VHDX cache matching must account for updates implicitly included in ESD | Cache consistency when CU is skipped due to version match |
| 36-02 | Use env var FFU_BITS_PRIORITY for ThreadJob propagation | ThreadJobs inherit parent process env; simpler than explicit parameter passing | Priority set in UI automatically available in background build job |
| 36-02 | Priority cascade: param > env > script > default | Standard precedence pattern; allows external override via env var | Backward compatible - no Priority param = Normal default |
| 36-03 | Module scope invocation for Get-WindowsESDMetadata tests | PS 7.5 export issue prevents direct Get-Command; function exists in module internal scope | Tests verify function through module scope and AST analysis |
| 36-03 | AST verification for function structure | When direct mocking is impractical, verify code structure via AST parsing | Validates regex patterns, return types, error handling without invoking |

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-28
**Stopped at:** Completed 36-03-PLAN.md (Phase 36 complete)
**Resume file:** None
**Next action:** Execute Phase 37 (Winget Ordering)

---
*State updated: 2026-01-28 after 36-03 complete*
