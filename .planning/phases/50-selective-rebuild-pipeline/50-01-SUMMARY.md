---
phase: 50-selective-rebuild-pipeline
plan: 01
subsystem: tests
tags: [pester, wave-0, tdd, selective-rebuild, disposition]
dependency_graph:
  requires: []
  provides:
    - "Wave-0 failing tests for Phase 50 behaviors (REBUILD-01, D-10/D-11, F1/F2/F3)"
    - "SelectiveRebuild.Tests.ps1 with ArtifactStatus enum + Build-UIConfiguration round-trip"
    - "USBOnlyMode.Tests.ps1 extended with F1/F2/F3 structural assertions"
    - "FFUUI.Core.Handlers.Tests.ps1 extended with Phase 50 disposition and 4-status"
    - "FFUUI.Core.ConfigValidation.Tests.ps1 extended with Phase 50 Disposition round-trip"
  affects:
    - Tests/Unit/SelectiveRebuild.Tests.ps1 (new)
    - Tests/Unit/USBOnlyMode.Tests.ps1 (extended)
    - Tests/Unit/FFUUI.Core.Handlers.Tests.ps1 (extended)
    - Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1 (extended)
tech_stack:
  added: []
  patterns:
    - "InModuleScope inside It blocks (not Describe-level) — Phase 46 pitfall"
    - "Source text structural assertions via Get-Content -Raw | Should -Match"
    - "Wave-0 TDD scaffolding: RED tests before implementation"
key_files:
  created:
    - Tests/Unit/SelectiveRebuild.Tests.ps1
  modified:
    - Tests/Unit/USBOnlyMode.Tests.ps1
    - Tests/Unit/FFUUI.Core.Handlers.Tests.ps1
    - Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1
decisions:
  - "InModuleScope must be used INSIDE It blocks (not at Describe level) — Describe-level wrapping causes Discovery-phase RuntimeException because the module is not loaded during parse/discovery. Pattern: FFU.ArtifactScanner.Tests.ps1 lines 92-113."
  - "Source-text structural assertions (Should -Match on Get-Content -Raw) chosen for Handlers/Config behavioral tests to avoid WPF runtime dependency in the test environment."
  - "Build-UIConfiguration round-trip tests use Set-ItResult -Skipped when the function is not yet exported — prevents hard failure noise while still registering the test shape for plan 50-02 to make green."
metrics:
  duration: "12 minutes"
  completed: "2026-06-22"
  tasks_completed: 3
  tasks_total: 3
  files_created: 1
  files_modified: 3
---

# Phase 50 Plan 01: Wave-0 Test Scaffolds Summary

**One-liner:** Wave-0 Pester RED scaffolds for Phase 50 selective rebuild — 4 test files, 43 failing behavioral Its and 108 passing structural Its, zero Discovery errors.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create SelectiveRebuild.Tests.ps1 | 634daee | Tests/Unit/SelectiveRebuild.Tests.ps1 (new, 323 lines) |
| 2 | Extend USBOnlyMode.Tests.ps1 with F1/F2/F3 | 319e256 | Tests/Unit/USBOnlyMode.Tests.ps1 (+71 lines) |
| 3 | Extend Handlers + ConfigValidation tests | c075c13 | FFUUI.Core.Handlers.Tests.ps1 (+82 lines), FFUUI.Core.ConfigValidation.Tests.ps1 (+67 lines) |

## Test Coverage Added

### SelectiveRebuild.Tests.ps1 (new — 24 tests)

| Describe | Context | Its | Wave-0 State |
|----------|---------|-----|--------------|
| ArtifactStatus Enum | — | 5 | GREEN (enum already implemented in Phase 46) |
| FFUUI.Core.Handlers 4-status | $artifactMap disposition keys | 4 | RED (plan 50-03) |
| FFUUI.Core.Handlers 4-status | 4-status rendering switch | 5 | RED (plan 50-03) |
| Disposition Config Round-Trip | Build-UIConfiguration source text | 4 | RED (plan 50-02) |
| Disposition Config Round-Trip | Update-UIFromConfig source text | 3 | RED (plan 50-02) |
| Disposition Config Round-Trip | Functional round-trip | 3 | RED/Skip (plan 50-02) |

### USBOnlyMode.Tests.ps1 extensions (13 new tests)

| Context | Its | Wave-0 State |
|---------|-----|--------------|
| F1 — AppsISO Copy Path | 4 | RED (plan 50-04) |
| F2 — Disposition Gate | 3 | RED (plan 50-04) |
| F3 — Selective Rebuild Flags | 6 | RED (plan 50-05) |

### FFUUI.Core.Handlers.Tests.ps1 extensions (9 new tests)

| Context | Its | Wave-0 State |
|---------|-----|--------------|
| Phase 50 $artifactMap disposition keys | 4 | RED (plan 50-03) |
| Phase 50 4-status rendering switch | 5 | RED (plan 50-03) |

### FFUUI.Core.ConfigValidation.Tests.ps1 extensions (8 new tests)

| Context | Its | Wave-0 State |
|---------|-----|--------------|
| Build-UIConfiguration Disposition write | 4 | RED (plan 50-02) |
| Update-UIFromConfig Disposition restore | 4 | RED (plan 50-02) |

## Final Test Run

```
Tests Passed: 108, Failed: 43, Skipped: 2, Inconclusive: 0, NotRun: 0
```

- **108 passing**: All pre-existing tests — no regressions introduced
- **43 failing**: All Wave-0 RED — implementation absent (plans 50-02 through 50-05 make them green)
- **2 skipped**: Build-UIConfiguration not yet exported from FFUUI.Core.Config module
- **Discovery**: CLEAN across all 4 files — no parse errors

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] InModuleScope must be inside It blocks, not at Describe level**

- **Found during:** Task 1 first run — Discovery-phase `RuntimeException: No modules named 'FFU.ArtifactScanner' are currently loaded`
- **Issue:** The plan's 50-PATTERNS.md showed an `InModuleScope 'FFU.ArtifactScanner' { Describe ... }` wrapping. This causes Discovery failure because `BeforeAll` (where the module is imported) has not yet executed when Pester parses the `InModuleScope` Describe wrapper.
- **Fix:** Used `InModuleScope FFU.ArtifactScanner { ... }` INSIDE each `It` block — the established pattern from `FFU.ArtifactScanner.Tests.ps1` lines 92-113.
- **Files modified:** Tests/Unit/SelectiveRebuild.Tests.ps1
- **Commit:** 634daee

## Known Stubs

None — this plan creates test scaffolds only. No production stubs.

## Threat Flags

None — test-only plan. No new network endpoints, auth paths, file access patterns, or schema changes.

## Self-Check: PASSED

- [x] Tests/Unit/SelectiveRebuild.Tests.ps1 exists: FOUND
- [x] Tests/Unit/USBOnlyMode.Tests.ps1 modified with F1/F2/F3 blocks: FOUND
- [x] Tests/Unit/FFUUI.Core.Handlers.Tests.ps1 extended with Phase 50 blocks: FOUND
- [x] Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1 extended with Phase 50 blocks: FOUND
- [x] Commit 634daee exists: VERIFIED
- [x] Commit 319e256 exists: VERIFIED
- [x] Commit c075c13 exists: VERIFIED
- [x] Discovery clean (no parse errors): VERIFIED
- [x] Existing 108 tests still GREEN: VERIFIED
- [x] 43 new tests are RED (Wave-0): VERIFIED
