---
phase: 52-driver-grid-ui-fixes
plan: "04"
subsystem: versioning
tags: [version-bump, changelog, verify-app, dgrid-01, dgrid-02, dgrid-03, ffuui-core]
dependency_graph:
  requires: ["52-01", "52-02", "52-03"]
  provides: ["FFUUI.Core 0.0.22", "main-version 1.12.1", "DGRID-01/02/03 changelog", "phase-52-complete"]
  affects: ["FFUUI.Core.psd1", "version.json", "ApplyFFU.ps1", "CHANGELOG_FORK.md"]
tech_stack:
  added: []
  patterns:
    - Synchronized version bump (psd1 + version.json + ApplyFFU.ps1 hardcoded + CHANGELOG)
key_files:
  created: []
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1
    - FFUDevelopment/version.json
    - FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1
    - CHANGELOG_FORK.md
decisions:
  - "FFUUI.Core bumped PATCH: 0.0.21 → 0.0.22 (3 bug fixes: DGRID-01/02/03)"
  - "Main version bumped PATCH: 1.12.0 → 1.12.1 (subcomponent version change per CLAUDE.md versioning policy)"
  - "CHANGELOG uses v1.12.1 heading format (per RESEARCH.md format spec)"
  - "verify-app BLOCKING gate PASSED: 14/14 phase tests green, 0 new PSScriptAnalyzer findings, FFUUI.Core v0.0.22 imports cleanly"
metrics:
  duration_minutes: 10
  completed: "2026-06-28"
  tasks_completed: 2
  files_created: 0
  files_modified: 4
---

# Phase 52 Plan 04: Version Bumps + Verify-App Gate Summary

**One-liner:** Synchronized version bump FFUUI.Core 0.0.21→0.0.22 / main 1.12.0→1.12.1 across four touchpoints with CHANGELOG entry; verify-app BLOCKING gate passed (14/14 phase tests green, 0 new PSScriptAnalyzer errors, module imports cleanly at v0.0.22).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Version bumps + CHANGELOG_FORK entry | 379a66f | FFUUI.Core.psd1, version.json, ApplyFFU.ps1, CHANGELOG_FORK.md |
| 2 | Run phase test + verify-app BLOCKING gate | (no source edits) | — |

## What Was Built

**Task 1 — Synchronized version bump across four touchpoints:**

1. `FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1` — `ModuleVersion` 0.0.21 → 0.0.22; release notes added summarizing all DGRID-01/02/03 fixes (filter-sort coexistence, select-all visible scope, save-path master-list read, header alignment, CopyDrivers/BuildUSBDrive validation throw).

2. `FFUDevelopment/version.json` — main `version` 1.12.0 → 1.12.1; `modules.FFUUI.Core.version` 0.0.21 → 0.0.22; `buildDate` updated to 2026-06-28; module description updated to reflect Phase 52 driver-grid fixes.

3. `FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1` — hardcoded `$version = '1.12.0'` → `'1.12.1'` at line 560 (runs in WinPE without access to version.json — per CLAUDE.md versioning policy).

4. `CHANGELOG_FORK.md` — new `## v1.12.1 - 2026-06-28` section inserted at the top of changelog entries, with `### Fixed` bullets for all five DGRID fix ports (DGRID-01 b4305a1; DGRID-02 f09c989 save + select-all scope; DGRID-02 42ed281 alignment; DGRID-03 dc801e9 fork-adapted).

**Version-check command output:** `OK` (main=1.12.1, FFUUI.Core json=0.0.22, psd1=0.0.22, ApplyFFU match=True, CHANGELOG match=True).

**Task 2 — verify-app BLOCKING gate (verification-only; no source edits):**

Ran the project's phase test and targeted verification checks per CLAUDE.md D-11 and RESEARCH.md D-11 (targeted tests, not full env-dependent suite):

```
Test-Phase52DriverGridFixes.ps1 output:
  DGRID-01: 3/3 PASS (filter-capture preamble, CollectionView capture, filter reapply)
  DGRID-02: 8/8 PASS (switch param, Tag read, GridViewColumnHeader, single opt-in call site, allDriverModels reference, null-guard, logic tests x2)
  DGRID-03: 3/3 PASS (throw wording, USBOnlyMode guard, END block line > 775)
  Total: 14/14 PASS — exit 0

PSScriptAnalyzer (files modified by plan 04):
  FFUUI.Core.psd1: 4 findings (all pre-existing: PSUseBOMForUnicodeEncodedFile, PSUseToExportFieldsInManifest x3)
  ApplyFFU.ps1: 82 findings (all pre-existing: PSAvoidUsingWriteHost x75, PSUseShouldProcessForStateChangingFunctions x2, PSUseSingularNouns x2)
  NEW findings from this plan: 0

Module import:
  pwsh + Add-Type PresentationFramework/PresentationCore/WindowsBase
  Import-Module FFUUI.Core.psd1 -Force → Get-Module FFUUI.Core v0.0.22: OK

BuildFFUVM.ps1 parse:
  [System.Management.Automation.Language.Parser]::ParseFile → 0 parse errors: OK
```

## Verification

All acceptance criteria met:
- `FFUUI.Core.psd1 ModuleVersion` = `0.0.22` (verified via `Import-PowerShellDataFile`)
- `version.json` main `version` = `1.12.1`, `modules.FFUUI.Core.version` = `0.0.22`, `buildDate` = `2026-06-28`
- `ApplyFFU.ps1` line 560 reads `$version = '1.12.1'`
- `CHANGELOG_FORK.md` has `## v1.12.1` `### Fixed` section naming DGRID-01, DGRID-02, DGRID-03
- Version-check command prints `OK`
- `Test-Phase52DriverGridFixes.ps1` exits 0 (14/14 PASS)
- PSScriptAnalyzer: 0 new errors on modified files
- FFUUI.Core v0.0.22 imports cleanly

## Deviations from Plan

None — plan executed exactly as written.

**Cosmetic note:** The CHANGELOG_FORK.md existing entries use `## [X.Y.Z] - date` format but the plan task action and RESEARCH.md format spec both call for `## vX.Y.Z - date`. The `## v1.12.1` format was applied as specified; the RESEARCH.md SELECT-STRING pattern `'v1\.12\.1'` confirmed the match.

## Known Stubs

None — all four version touchpoints are fully wired and consistent (1.12.1 / 0.0.22). No placeholder values.

## Threat Flags

None — version metadata edits and a read-only verification gate. No new network, auth, untrusted-input, or code behavior path introduced. Per plan threat model T-52-05 (accepted).

## Self-Check: PASSED

- [x] `FFUUI.Core.psd1` `ModuleVersion` = `0.0.22`
- [x] `FFUUI.Core.psd1` release notes contain DGRID-01/02/03 descriptions
- [x] `version.json` `version` = `1.12.1`
- [x] `version.json` `modules.FFUUI.Core.version` = `0.0.22`
- [x] `version.json` `buildDate` = `2026-06-28`
- [x] `ApplyFFU.ps1` line 560 reads `$version = '1.12.1'`
- [x] `CHANGELOG_FORK.md` contains `## v1.12.1` with `### Fixed` bullets for DGRID-01/02/03
- [x] Version-check command output: `OK`
- [x] `Test-Phase52DriverGridFixes.ps1` exits 0 — 14/14 PASS
- [x] PSScriptAnalyzer: 0 new findings on modified files
- [x] FFUUI.Core v0.0.22 imports cleanly
- [x] BuildFFUVM.ps1 parse: 0 errors
- [x] Commit 379a66f exists (Task 1)
