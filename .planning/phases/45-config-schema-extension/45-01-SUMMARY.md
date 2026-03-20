---
phase: 45-config-schema-extension
plan: 01
subsystem: FFU.ConfigMigration
tags: [config-migration, schema-versioning, usb-mode, tdd]
dependency_graph:
  requires: []
  provides: [config-schema-v1.3, activemode-migration, usbmode-artifacts-migration]
  affects: [FFU.ConfigMigration, config-loading-pipeline]
tech_stack:
  added: []
  patterns: [additive-migration-block, tdd-red-green]
key_files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1
    - FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psd1
    - Tests/Unit/FFU.ConfigMigration.Tests.ps1
    - Tests/Unit/FFU.ConfigMigration.Integration.Tests.ps1
decisions:
  - "v1.3 migration is purely additive — no keys removed, full partial-object guards"
  - "CopyOfficeConfigXML pre-existing test inconsistency fixed: module preserves property, tests updated to match"
  - "Change count assertions updated to include all additive defaults (IncludePreviewUpdates + VMwareSettings + ActiveMode + USBMode)"
metrics:
  duration: 12m
  completed: 2026-03-20
  tasks_completed: 2
  files_modified: 4
---

# Phase 45 Plan 01: v1.3 Config Migration Summary

**One-liner:** v1.3 config migration adding ActiveMode='FullBuild' default and USBMode.Artifacts section with 7 artifact types (FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO) via additive migration blocks in FFU.ConfigMigration.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add v1.3 migration tests and update version assertions (RED) | 62b72cb | Tests/Unit/FFU.ConfigMigration.Tests.ps1, Tests/Unit/FFU.ConfigMigration.Integration.Tests.ps1 |
| 2 | Implement v1.3 migration blocks and bump version constant (GREEN) | cf72c1f | FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1, FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psd1 + updated tests |

## What Was Built

### FFU.ConfigMigration.psm1 Changes

1. **Version constant bumped:** `$script:CurrentConfigSchemaVersion = "1.2"` → `"1.3"`

2. **New migration block — ActiveMode (v1.3):** Inserts `ActiveMode = 'FullBuild'` if not present, logging a change description.

3. **New migration block — USBMode defaults (v1.3):** Three-path guard:
   - If `USBMode` missing: creates full section with 7 artifact entries
   - If `USBMode` exists but `Artifacts` missing: fills in all 7 artifact entries
   - If `USBMode.Artifacts` exists but missing individual types: fills in only the missing types

Each artifact entry: `@{ Path = $null; Disposition = 'Reuse' }`

### FFU.ConfigMigration.psd1 Changes

- `ModuleVersion` bumped from `'1.1.1'` to `'1.2.0'`
- `ReleaseNotes` updated with v1.2.0 entry describing the v1.3 schema migration

### Test Changes

**FFU.ConfigMigration.Tests.ps1:**
- Updated `'returns "1.2" as current version'` → `'returns "1.3" as current version'`
- Updated `Test-FFUConfigVersion` "current version" tests to use `configSchemaVersion = '1.3'`
- Updated `Invoke-FFUConfigMigration` output assertions from `'1.2'` → `'1.3'`
- Updated "already at target version" and "no migration needed" config fixtures to v1.3
- Updated change count assertions (+2 for ActiveMode and USBMode defaults)
- Added new `Describe 'v1.3 Migration'` block with 9 `It` blocks
- Fixed pre-existing CopyOfficeConfigXML tests (property is preserved, not removed)
- Fixed WARNING count test (only DownloadDrivers generates WARNING)

**FFU.ConfigMigration.Integration.Tests.ps1:**
- Updated all `'1.0'` version assertions to `'1.3'`
- Updated "current version" tests to use `configSchemaVersion = '1.3'`
- Updated "already-migrated" config fixture to include full v1.3 structure
- Fixed pre-existing CopyOfficeConfigXML test
- Fixed CLI change count test (6 changes, not 2)
- Fixed "Returns valid result structure" to allow changes > 0

## Test Results

| Metric | Value |
|--------|-------|
| Tests passed | 111 / 111 |
| Tests failed | 0 |
| New test cases added | 9 (v1.3 Migration describe block) |

## Success Criteria Verification

- [x] `Get-FFUConfigSchemaVersion` returns "1.3"
- [x] v1.2 config migrates with `ActiveMode=FullBuild` and all 7 `USBMode.Artifacts` entries
- [x] Legacy config (no version) reaches v1.3
- [x] Already-v1.3 config produces zero changes
- [x] Backup file created before migration when `-CreateBackup` used (per D-16)
- [x] All Pester tests pass (111/111, both unit and integration)
- [x] Module manifest version is 1.2.0

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing CopyOfficeConfigXML test inconsistencies**
- **Found during:** Task 2 (GREEN phase test run)
- **Issue:** Unit and integration tests expected `CopyOfficeConfigXML` to be removed by migration, but the module code (with comment "CopyOfficeConfigXML was incorrectly marked deprecated but is still actively used") explicitly preserves it. This caused 8 pre-existing test failures.
- **Fix:** Updated all CopyOfficeConfigXML test cases to assert the property is PRESERVED (matching the actual module behavior). Updated WARNING count from 2 to 1 (only DownloadDrivers generates WARNING). Updated CLI change count test from 2 to 6 (all additive defaults now counted).
- **Files modified:** Tests/Unit/FFU.ConfigMigration.Tests.ps1, Tests/Unit/FFU.ConfigMigration.Integration.Tests.ps1
- **Commit:** cf72c1f

## Known Stubs

None. The migration is fully implemented. USBMode.Artifacts stubs in `Get-UIConfig` and `Update-UIFromConfig` (FFUUI.Core.Config.psm1) are deferred to the next plan in this phase per the plan's scope.

## Self-Check: PASSED
