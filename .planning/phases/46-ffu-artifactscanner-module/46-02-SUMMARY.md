---
phase: 46-ffu-artifactscanner-module
plan: "02"
subsystem: FFU.ArtifactScanner
tags:
  - new-module
  - artifact-discovery
  - scanner
  - compatibility-check
  - pester-tdd
dependency_graph:
  requires:
    - FFU.ArtifactScanner (plan 46-01 scaffold)
    - FFU.Core (RequiredModules, WriteLog)
    - FFU.Preflight (optional, Test-FFUWimMount)
  provides:
    - Find-FFUArtifacts: full implementation scanning 7 artifact types
    - Test-ArtifactCompatibility: architecture mismatch detection
    - Complete FFU.ArtifactScanner module (all 5 public functions implemented)
  affects:
    - Phase 47 (pipeline reads ArtifactManifest from Find-FFUArtifacts)
    - Phase 48 (UI columns bind to ArtifactResult properties)
    - Phase 49 (controls use per-artifact ArtifactResult)
tech_stack:
  added: []
  patterns:
    - "[CompatibilityWarning[]] typed local variable to prevent @($null) coercion in typed property assignment"
    - "Get-Command in try/catch for hyphenated function availability check (ThreadJob compatible)"
    - "@($result | Where-Object {$null -ne $_}) null-filter pattern for typed array assignment"
    - "Sort-Object LastWriteTime -Descending for newest-first FFU IsPrimary selection"
    - "Drivers AgeDays from newest file LastWriteTime, not folder timestamp"
key_files:
  created:
    - .planning/phases/46-ffu-artifactscanner-module/46-02-SUMMARY.md
  modified:
    - FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1
    - Tests/Unit/FFU.ArtifactScanner.Tests.ps1
decisions:
  - "Get-Command try/catch used instead of $function: drive for hyphenated function (Test-FFUWimMount) availability check — $function:Test-FFUWimMount is invalid PowerShell syntax"
  - "@($result | Where-Object) null-filter pattern required to prevent [CompatibilityWarning[]] typed array from coercing empty to @($null)"
  - "Typed [CompatibilityWarning[]]$warnings local variable in Test-ArtifactCompatibility prevents unboxing issues on return"
  - "All 7 scanners wrapped in individual try/catch blocks for graceful degradation per RESEARCH.md Pattern 3"
metrics:
  duration: "~46 minutes"
  completed_date: "2026-03-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 2
  tests_written: 42
  tests_passing: 121
---

# Phase 46 Plan 02: FFU.ArtifactScanner - Find-FFUArtifacts and Test-ArtifactCompatibility Summary

**One-liner:** Full Find-FFUArtifacts implementation scanning all 7 artifact types with WIMMount gate, IsPrimary selection, graceful degradation, and Test-ArtifactCompatibility architecture mismatch detection.

## What Was Built

### Find-FFUArtifacts (Full Implementation)

Replaced the stub with complete implementation:

1. **WIMMount gate** — Calls `Test-FFUWimMount` once at start, caches `$wimMountAvailable` bool. Uses `Get-Command` in try/catch (not `$function:` drive) because hyphenated function names are invalid in the `$function:` provider syntax.

2. **7 private scanner sections** — each wrapped in individual try/catch for graceful degradation:
   - `FFU files`: Scans `$FFUDevelopmentPath\FFU\*.ffu`, sorted newest-first. Calls `Get-ArtifactMetadata` per file (wrapped in try/catch). Marks first as `IsPrimary = $true`.
   - `Deploy ISO`: Checks both `WinPE_FFU_Deploy_x64.iso` and `WinPE_FFU_Deploy_arm64.iso` in root. First found wins.
   - `Drivers`: Checks `$FFUDevelopmentPath\Drivers\` exists. `FileCount` and `TotalSizeBytes` from `Get-ChildItem -Recurse -File`. `AgeDays` from newest file `LastWriteTime`, not folder timestamp.
   - `PPKG files`: Scans `PPKG\*.ppkg`. Each file gets an `ArtifactResult`.
   - `Unattend files`: Checks specifically for `unattend_x64.xml` and `unattend_arm64.xml` per BuildFFUVM.ps1 lines 1504-1515.
   - `Autopilot files`: Scans `Autopilot\*.json` per BuildFFUVM.ps1 line 2107.
   - `Apps.iso`: Checks `Apps\Apps.iso` existence and size. No ISO mount.

3. **Readiness summary** — `FoundCount`, `MissingCount`, `ErrorCount` across all result arrays. `IsReady = FFU found AND ISO found AND ErrorCount == 0`.

4. **Automatic compatibility check** — Calls `Test-ArtifactCompatibility -Manifest $manifest` and assigns result to `$manifest.Warnings` with null-filtering.

### Test-ArtifactCompatibility (Full Implementation)

- Extracts FFU architecture from primary FFU result's `Metadata.Architecture`
- Extracts ISO architecture from filename via regex `WinPE_FFU_Deploy_(.+)\.iso`
- Returns `[CompatibilityWarning]` with `Severity='Warning'`, descriptive message with both arch names, `AffectedArtifacts = @('FFU', 'DeployISO')`
- Returns empty array when either architecture is unknown/null (no spurious warnings)

### Tests Added (42 new tests)

Pester describe blocks added:
- `Find-FFUArtifacts - Empty Directory` (11 tests): All 7 artifact types return Missing, IsReady=false, BasePath/ScanTimestamp set
- `Find-FFUArtifacts - All Artifacts Present` (15 tests): Found status for each type, IsPrimary marking, Metadata populated, AgeDays, IsReady=true, FoundCount
- `Find-FFUArtifacts - Multiple FFU Files` (3 tests): Both discovered, exactly one IsPrimary, newest marked primary
- `Find-FFUArtifacts - Drivers AgeDays from Newest File` (1 test): Confirms Pitfall 6 implementation
- `Find-FFUArtifacts - Graceful Degradation` (2 tests): No throw on metadata failure, result still returned
- `Test-ArtifactCompatibility - Architecture Match` (2 tests): No warnings for x64/x64 and arm64/arm64
- `Test-ArtifactCompatibility - Architecture Mismatch` (4 tests): Warning for arm64 FFU / x64 ISO; message content, severity, AffectedArtifacts
- `Test-ArtifactCompatibility - Missing Artifacts` (2 tests): Empty array when FFU missing, empty when ISO missing
- `Find-FFUArtifacts - Compatibility Integration` (2 tests): End-to-end Warnings populated on mismatch, empty on match

**Total: 121/121 tests passing** (79 from plan 46-01 + 42 new)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] $function:Test-FFUWimMount invalid syntax for hyphenated function names**
- **Found during:** Task 1 implementation (module load failure)
- **Issue:** PowerShell's `$function:` drive uses the identifier as a variable name; hyphens are not valid in variable names so `$function:Test-FFUWimMount` causes parse error
- **Fix:** Used `Get-Command -Name 'Test-FFUWimMount' -ErrorAction Stop` in try/catch block to safely check function availability
- **Files modified:** `FFU.ArtifactScanner.psm1`
- **Commit:** 551f448

**2. [Rule 1 - Bug] Typed array property assignment produces @($null) for empty result**
- **Found during:** Task 2 test execution (Warnings count assertion fails with @($null))
- **Issue:** When `Test-ArtifactCompatibility` returns typed `[CompatibilityWarning[]]@()` and this gets assigned to `$manifest.Warnings` (also `[CompatibilityWarning[]]`), PowerShell's type coercion can produce `@($null)` rather than `@()` in certain scope contexts
- **Fix:** Applied `@($result | Where-Object { $null -ne $_ })` null-filter pattern before assignment; used typed `[CompatibilityWarning[]]$warnings` local variable in `Test-ArtifactCompatibility` return
- **Files modified:** `FFU.ArtifactScanner.psm1`
- **Commit:** 551f448

## Module Exports Verified

All 5 public functions exported:
- `Find-FFUArtifacts` — full implementation
- `Get-ArtifactMetadata` — implemented in plan 46-01
- `Test-ArtifactCompatibility` — full implementation
- `New-ArtifactManifest` — factory function from plan 46-01
- `New-ArtifactResult` — factory function from plan 46-01

## Self-Check: PASSED

Files verified present:
- FOUND: FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1
- FOUND: Tests/Unit/FFU.ArtifactScanner.Tests.ps1
- FOUND: .planning/phases/46-ffu-artifactscanner-module/46-02-SUMMARY.md

Commits verified:
- bf2d88c: test(46-02): add failing tests for Find-FFUArtifacts and Test-ArtifactCompatibility
- 551f448: feat(46-02): implement Find-FFUArtifacts with 7 artifact scanners and Test-ArtifactCompatibility

Tests: 121/121 passing
