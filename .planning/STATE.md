# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-28)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** Milestone v1.10.0 Upstream Cherry-Pick

## Current Position

**Milestone:** v1.10.0 Upstream Cherry-Pick
**Phase:** 40 of 43 (Dell Refactoring) - IN PROGRESS
**Plan:** 2 of 3 complete (40-02)
**Status:** Phase 40 in progress — UI-layer CatalogIndexPC complete
**Last activity:** 2026-01-29 — Completed 40-02-PLAN.md

Progress: █████░░░░░ 57% (16 of 28 plans complete across 10 phases)

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
| 36: CU Skip + ESD BITS | Version comparison + BITS downloads | BUGFIX-04, DL-01 | ✓ Verified (3/3 plans) |
| 37: Winget Ordering | App ordering + dependency handling | WINGET-01, WINGET-02 | ✓ Verified (3/3 plans) |
| 38: SUBST Drive Mapping | Long path reliability | PATH-01 | ✓ Complete (2/2 plans) |
| 39: Model Normalization | Brand dedup + SystemID | DRV-02, DRV-03 | ✓ Complete (2/2 plans) |
| 40: Dell Refactoring | CatalogIndexPC logic | DRV-01 | In Progress (2/3 plans) |
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
| 37-01 | Replace all raw mutex with Invoke-WithNamedMutex wrapper | Cleaner pattern with timeout, best-effort release, automatic dispose | Consistent mutex handling across Add-Win32SilentInstallCommand and Get-Apps |
| 37-01 | Use SHA256-based mutex name per JSON file path | Different JSON files get different mutexes; replaces hardcoded lock name | Correct cross-process synchronization for multiple JSON files |
| 37-01 | Three-tier deduplication: PackageIdentifier, Name, CommandLine+Args | Names vary with architecture suffixes; PackageIdentifier is canonical | Correct dedup for dependencies with architecture variants |
| 37-01 | Capture scriptblock return to handle duplicate detection | return inside scriptblock exits scriptblock, not outer function | Prevents function continuing after duplicate-skip return |
| 37-01 | Pre-add Add-Win32DependencySilentInstallCommands to Export-ModuleMember | PowerShell silently ignores export of non-existent functions | Prevents Plan 02 from needing to touch same Export-ModuleMember line |
| 37-02 | Reorder logic inside Get-Apps (not extracted) | Match upstream placement per CONTEXT.md | Single location for ordering logic |
| 37-02 | Dependencies slot before parent via IsDependency=0 in stable sort | DependencyFor marker enables grouping deps with their parent | Correct install order: deps before dependent apps |
| 37-02 | Dependency failure is WARNING only | Build should not fail due to optional dependency processing | Robustness - main app installs regardless of dep processing failure |
| 37-02 | Architecture suffix normalization via regex | App names include (x64) etc but AppList.json uses plain names | Correct matching between WinGetWin32Apps.json entries and AppList.json |
| 37-03 | Module scope invocation for testing non-exported functions | Helper functions are internal (not exported) but need test coverage | Enables comprehensive testing without exposing implementation details |
| 37-03 | Background runspace for mutex contention testing | Raw Threads lack PowerShell runspace; need cross-thread mutex test | Correct mutex timeout verification without crashes |
| 37-03 | Inline reorder algorithm simulation in tests | Get-Apps has too many external dependencies (WinGet, network) for unit tests | Tests verify ordering logic directly without integration dependencies |
| 38-01 | Use cmd.exe for SUBST operations (no native PowerShell cmdlet) | Windows has no native PowerShell SUBST cmdlet; cmd.exe provides consistent behavior | All SUBST operations call cmd.exe with proper argument escaping |
| 38-01 | Auto-growing buffer starts at 1KB and doubles to 64KB max | Balance memory efficiency with large INF support (SourceDisksFiles can be huge) | Prevents truncation without excessive memory allocation; handles all known OEM packages |
| 38-01 | Use \\?\ prefix ONLY for Win32 API calls, NOT PowerShell cmdlets | PowerShell cmdlets handle long paths differently; \\?\ prefix breaks them | $longInfFullName for Get-PrivateProfileString/Section, $infFullName for Copy-Item |
| 38-01 | GUID normalization strips trailing ; comments and extracts token | INF files can have ClassGUID={...};comment format that breaks exact matching | Reliable GUID filtering regardless of INF comment style |
| 38-01 | Replace all Copy-Item -Path with -LiteralPath | Prevents wildcard expansion on paths with brackets [, ], *, ? | Reliable file copy for drivers with special characters in paths |
| 38-01 | SUBST functions return $null with WARNING on failure (non-throwing) | Consistent with error handling pattern, allows caller to decide severity | Caller must check for $null, failures are logged but don't halt execution |
| 38-01 | Pre-add Invoke-DismDriverInjectionWithSubstLoop to exports | PowerShell silently ignores export of non-existent functions | Plan 02 can implement function without touching Export-ModuleMember line |
| 38-02 | Sequential SUBST loop with single drive letter reuse | Minimize resource consumption; simpler than parallel | Drive letter Z mapped/unmapped multiple times per build |
| 38-02 | WinPE compatibility via Get-Command checks | ApplyFFU.ps1 runs in minimal environment; FFU.Drivers may not be loaded | SUBST operations optional; script works with or without module |
| 38-02 | INF scanning with folder deduplication | Parent folders with /Recurse cover children | Typical reduction: 50-100 folders -> 5-10 folders for SUBST operations |
| 38-02 | Path walk-up for 240+ char paths | SUBST target path has ~240 char limit | Algorithm walks up to parent until path fits SUBST limit |
| 39-01 | ReadSubtree() DOM approach for Get-DellDriversModelList | Reliable child element access for GroupManifest/Display | Matches proven Save-DellDriversTask pattern, enables GroupManifest extraction |
| 39-01 | HP PlatformList.xml cache built inline on first HP entry | Per-call hashtable avoids repeat XML parsing | Single parse per Update-DriverMappingJson call for all HP entries |
| 39-01 | Extract Get-HPSystemIdFromPlatformList as named exported function | Enables direct test access and reuse | Function available for tests and future consumers outside Update-DriverMappingJson |
| 39-01 | Save-DellDriversTask checks GroupManifest, Model/Display, and Brand+Model assembly | Models listed via GroupManifest normalization must match at download time | Prevents model mismatch between list and download phases |
| 39-02 | MatchPrecision scoring (2=SystemID, 1=ModelName) for multi-tier match sorting | Simple numeric precedence for Sort-Object | Prefers exact SystemID matches over fuzzy model-name matches |
| 39-02 | Extract functions from ApplyFFU.ps1 via AST for Pester testing | WinPE deploy script is not a module; AST extraction provides testable definitions | Enables unit testing of non-module script functions without executing script-level code |
| 39-02 | Use Set-ItResult -Skipped for module-dependent tests | Pester 5.x evaluates -Skip at discovery before BeforeAll runs | Runtime skip ensures module availability is correctly detected |
| 40-01 | Use CatalogIndexPC as primary catalog source for Windows client Dell drivers | Reduces download size from 160MB (CatalogPC.cab) to 5-10MB (index) + 1-5MB (model cab) = 10-30x bandwidth reduction | Bandwidth savings significant for corporate environments with hundreds of builds |
| 40-01 | Three-tier fallback: CatalogIndexPC → CatalogPC.cab → graceful failure | Ensures builds never break due to Dell URL changes or schema differences | Defense-in-depth for production reliability |
| 40-01 | Delete model-specific cab files after extraction to XML | Saves disk space (1-5MB per model) - cache is managed at index level | Disk space more valuable than re-extraction time (rarely needed) |
| 40-02 | Duplicate CatalogIndexPC helper functions in UI layer | Matches existing pattern where UI and build layers have independent implementations | UI cannot import FFU.Drivers.psm1 due to build-layer dependencies |
| 40-02 | SystemId and CabUrl are optional in Drivers.json | Models from CatalogPC.cab fallback lack these fields | Enables silent upgrade path for old Drivers.json files without breaking changes |
| 40-02 | Use PSObject.Properties check before accessing SystemId/CabUrl | Handles models without these properties gracefully (no errors, defaults to $null) | Cleaner than try/catch, preserves other error visibility |

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-29
**Stopped at:** Completed 40-02-PLAN.md
**Resume file:** None
**Next action:** Continue Phase 40 Plan 03 (Dell Refactoring - Save-DellDriversTask integration)

---
*State updated: 2026-01-29 after Plan 40-02 complete (UI-layer CatalogIndexPC support)*
