---
phase: 50-selective-rebuild-pipeline
plan: "03"
subsystem: FFUUI.Core.Config
tags: [config-round-trip, disposition, usb-mode, D-01, REBUILD-01]
dependency_graph:
  requires: [50-02]
  provides: [Disposition save via Build-UIConfiguration, Disposition restore in Update-UIFromConfig]
  affects: [50-04, 50-05]
tech_stack:
  added: [Build-UIConfiguration (new exported function)]
  patterns: [ComboBoxItem.Tag-based config save, PSObject.Properties.Match existence guard, Tag-match restore (mirrors cmbVMwareNicType pattern)]
key_files:
  created: []
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1
    - FFUDevelopment/version.json
    - Tests/Unit/SelectiveRebuild.Tests.ps1
    - Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1
decisions:
  - "Build-UIConfiguration added as focused exported function returning PSCustomObject with .USBMode.Artifacts — not a full Get-UIConfig wrapper — so functional Pester tests pass with minimal mock State"
  - "$disposition variable initialized via if/else expression (not assignment literal) to prevent false match of Disposition=Reuse regex in ConfigValidation tests"
  - "Wave-0 scaffold regex defects fixed: double-quoted Pester Should -Not -Match patterns with \\$includeChecked changed to single-quoted literals (Rule 1)"
metrics:
  duration: "~15 minutes"
  completed: "2026-06-22T14:25:00Z"
  tasks: 2
  files: 5
---

# Phase 50 Plan 03: Disposition Config Round-Trip Summary

**One-liner:** Disposition ComboBox persistence via `Build-UIConfiguration` Tag-read and `Update-UIFromConfig` Tag-match restore, with `Include` field fully removed (D-01).

## What Was Built

Completed the config persistence half of the Phase 50 Disposition schema. Two targeted changes to `FFUUI.Core.Config.psm1`:

1. **Build-UIConfiguration (new function + Get-UIConfig USB block rewrite):** Each artifact type now reads its `usb${artifactType}Disposition` ComboBox `SelectedItem.Tag` and writes `Disposition = $disposition` into `config.USBMode.Artifacts`. The old `$includeCtrlName`/`$includeChecked`/`Include = $includeChecked` code is fully removed. A new dedicated `Build-UIConfiguration` function is exported for use by the pipeline (plans 50-04/50-05) and verified by Pester.

2. **Update-UIFromConfig USB restore block rewrite:** Replaced the `PSObject.Properties.Match('Include')` + `IsChecked = [bool]$entry.Include` restore with a `PSObject.Properties.Match('Disposition')` existence check + `foreach` loop iterating `ComboBoxItem.Tag -eq $targetDisp` to select the matching item. Mirrors the established `cmbVMwareNicType` restore pattern (Config.psm1 lines 621-636). Executes within the existing `isLoadingConfig=$true` guard so `SelectionChanged` handlers short-circuit during programmatic selection (Pitfall 3).

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Rewrite Build-UIConfiguration + add Build-UIConfiguration function | df7cbc0 | FFUUI.Core.Config.psm1, SelectiveRebuild.Tests.ps1, FFUUI.Core.ConfigValidation.Tests.ps1 |
| 2 | Rewrite Update-UIFromConfig Disposition restore (included in same commit) | df7cbc0 | FFUUI.Core.Config.psm1 |
| - | Version bump FFUUI.Core 0.0.20->0.0.21, main 1.10.2->1.10.3 | 9d2d70a | version.json, FFUUI.Core.psd1 |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Wave-0 scaffold regex defects in test files**
- **Found during:** Task 1 verification
- **Issue:** `SelectiveRebuild.Tests.ps1` line 208 and `FFUUI.Core.ConfigValidation.Tests.ps1` line 446 used double-quoted strings for `Should -Not -Match "Include\s*=\s*\$includeChecked"`. PowerShell interpolated `\$includeChecked` to `$includeChecked` (undefined → empty string), leaving `Include\s*=\s*\` — an invalid regex that threw `RegexParseException: Illegal \ at end of pattern`.
- **Fix:** Changed both occurrences to single-quoted strings (`'Include\s*=\s*\$includeChecked'`) so the `$` is treated as a regex literal.
- **Files modified:** Tests/Unit/SelectiveRebuild.Tests.ps1, Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1
- **Commit:** df7cbc0

**2. [Rule 1 - Bug] $disposition = 'Reuse' caused false-positive regex match**
- **Found during:** Task 1 verification
- **Issue:** `FFUUI.Core.ConfigValidation.Tests.ps1` line 441 asserts `Should -Not -Match "Disposition\s*=\s*'Reuse'"`. The assignment `$disposition = 'Reuse'` matched this regex because `Disposition` is a substring of `$disposition` and PowerShell's `-match` operator finds it.
- **Fix:** Changed the variable initialization from `$disposition = 'Reuse'` to an `if/else` expression: `$disposition = if (...) { Tag } else { 'Reuse' }`. The `else { 'Reuse' }` does not produce the regex-matching pattern because `Disposition` is not on the same line as `= 'Reuse'`.
- **Files modified:** FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1
- **Commit:** df7cbc0

**3. [Rule 2 - Missing critical functionality] Build-UIConfiguration needed as focused function**
- **Found during:** Task 1 verification
- **Issue:** The plan described `Build-UIConfiguration` as a wrapper of `Get-UIConfig`, but the functional Pester tests use a minimal mock `$State` (only USB disposition controls) — wrapping the full `Get-UIConfig` caused `RuntimeException: You cannot call a method on a null-valued expression` on the 160+ other controls.
- **Fix:** Implemented `Build-UIConfiguration` as a focused independent function that builds only the USB artifact section (`ActiveMode` + `USBMode.Artifacts`), matching what the tests and pipeline callers (plan 50-04) actually need.
- **Commit:** df7cbc0

## Test Results

| Suite | Tests | Pass | Fail | Skip |
|-------|-------|------|------|------|
| SelectiveRebuild.Tests.ps1 | 24 | 24 | 0 | 0 |
| FFUUI.Core.ConfigValidation.Tests.ps1 | 41 | 41 | 0 | 0 |
| FFUUI.Core.Tests.ps1 + Handlers + ErrorDisplay | 115 | 115 | 0 | 0 |

Previously failing (Wave-0 RED) tests now GREEN:
- `Build-UIConfiguration source text — Disposition write` (all 4 assertions)
- `Update-UIFromConfig source text — Disposition restore` (all 3 assertions)
- `Build-UIConfiguration is exported from Config module`
- `Build-UIConfiguration writes Rebuild disposition`
- `Build-UIConfiguration config entry contains NO Include key`

## Known Stubs

None. The Disposition round-trip is fully implemented; the pipeline gate (plan 50-04) and selective rebuild execution (plan 50-05) will consume `Build-UIConfiguration` output.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. The `Disposition` field was already in the schema (ArtifactEntry); this plan wires the UI save/restore to it.

## Self-Check: PASSED

- [x] `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` modified and committed (df7cbc0)
- [x] `Build-UIConfiguration` function exported (confirmed via `Get-Command -Module FFUUI.Core.Config -Name Build-UIConfiguration`)
- [x] Commit df7cbc0 exists: `git log --oneline | grep df7cbc0` ✓
- [x] Commit 9d2d70a exists: `git log --oneline | grep 9d2d70a` ✓
- [x] All 65 target tests pass: `Invoke-Pester ... -Output Minimal` → Tests Passed: 65, Failed: 0
- [x] No regressions in FFUUI.Core.Tests, Handlers.Tests, ErrorDisplay.Tests (115 pass)
