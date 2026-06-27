---
phase: 51-capture-boot-correctness
plan: 01
subsystem: imaging
tags: [FFU.Imaging, EditionId, DISM, Windows-image-selection, ThreadJob, PowerShell]

# Dependency graph
requires:
  - phase: 50-selective-rebuild-pipeline
    provides: Stable build pipeline (USB Mode, artifact scanner) as foundation for v1.12.0 correctness work

provides:
  - Get-WindowsImageSelection: EditionId-based locale-independent image selection replacing Get-Index
  - Get-ResolvedWindowsSKUFromImage: reverse EditionId->SKU map companion
  - Get-WindowsTargetRuntimeState: runtime state recompute helper for post-selection SKU propagation
  - Caller propagation in BuildFFUVM.ps1: WindowsSKU reassigned after fallback, fixing naming/caching/servicing
  - Test-Phase51Correctness.ps1: content-match test suite with SKU->EditionId map completeness gate

affects: [52-driver-grid-ui-fixes, 53-driver-build-deploy-correctness, 54-update-cache-capture-naming, phase-51-plan-02, phase-51-plan-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "EditionId+InstallationType based image selection (locale-independent, replaces Substring derivation)"
    - "Rich PSCustomObject return from selection functions (ImageIndex/EditionId/ResolvedWindowsSKU)"
    - "ThreadJob-safe auto-select: 1 candidate->auto-select, 2+->WriteLog editions list then throw"
    - "Single-assignment $WindowsSKU propagation: one guarded reassignment fixes all 9 downstream consumers"
    - "Write-TestResult content-match test pattern for FFU module verification"

key-files:
  created:
    - FFUDevelopment/Tests/Test-Phase51Correctness.ps1
  modified:
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1
    - FFUDevelopment/BuildFFUVM.ps1
    - FFUDevelopment/version.json

key-decisions:
  - "D-01: Delete Read-Host/while($true) loop entirely - hangs ThreadJob builds; replace with auto-select or throw"
  - "D-02: Single relevant candidate -> auto-select non-interactively (no prompt)"
  - "D-03: Two or more candidates -> WriteLog full editions list then throw (log-first for ThreadJob reliability)"
  - "D-04: Return rich PSCustomObject from Get-WindowsImageSelection; single guarded $WindowsSKU reassignment at caller fixes all 9 downstream consumers"
  - "D-05: Select by EditionId (primary) then exact ImageName -eq (fallback) then fail - no Substring derivation"
  - "D-06: Complete 24-entry SKU->EditionId map covering all $clientSKUs/$LTSCSKUs/$ServerSKUs entries"
  - "D-07: InstallationType filter for Server Desktop Experience vs Server Core disambiguation"
  - "D-08: Retain exact ImageName -eq fallback as zero-cost salvage for map gaps"

patterns-established:
  - "EditionId selection: Get-WindowsImage -Index N for per-image EditionId/InstallationType reads (proven ArtifactScanner pattern)"
  - "Rich object returns: PSCustomObject with ImageIndex + metadata instead of bare [int]"
  - "SKU propagation: requestedWindowsSKU captured before selection; $WindowsSKU reassigned when ResolvedWindowsSKU non-empty"
  - "Content-match test gates: mandatory token presence assertions prevent silent map regressions"

requirements-completed: [CORRECT-01, CORRECT-04]

# Metrics
duration: 45min
completed: 2026-06-26
---

# Phase 51 Plan 01: Capture/Boot Correctness (CORRECT-01 + CORRECT-04) Summary

**EditionId-based locale-independent image selection (Get-WindowsImageSelection) replacing Get-Index, with ResolvedWindowsSKU propagation fixing FFU naming/caching/servicing after fallback edition selection**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-06-26T23:45:00Z
- **Completed:** 2026-06-26T00:30:00Z
- **Tasks:** 3 completed
- **Files modified:** 5 (psm1, psd1, BuildFFUVM.ps1, version.json, new test file)

## Accomplishments

- Replaced locale-fragile `Get-Index` with `Get-WindowsImageSelection` using EditionId/InstallationType matching — non-English and multi-edition media now selects the correct image index
- Deleted the `Read-Host`/`while($true)` fallback loop that deadlocked ThreadJob builds (CORRECT-01 D-01); replaced with auto-select for 1 candidate, WriteLog+throw for 2+ candidates
- Implemented full 24-entry SKU->EditionId switch covering all `$clientSKUs`/`$LTSCSKUs`/`$ServerSKUs` entries (D-06 map completeness gate enforced by test)
- Added `Get-ResolvedWindowsSKUFromImage` reverse map companion; added `Get-WindowsTargetRuntimeState` helper in BuildFFUVM.ps1
- Single guarded `$WindowsSKU` reassignment at the Get-Index call site propagates the selected edition to all 9 downstream consumers: FFU naming, VHDX cache read/write, and 6 checkpoint sites (D-04)
- New `Test-Phase51Correctness.ps1` suite: 41 tests, all green, map-completeness gate enforced, placeholder sections for Plans 02/03

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite Get-Index as Get-WindowsImageSelection + add Get-ResolvedWindowsSKUFromImage** - `982f858` (feat)
2. **Task 2: Add Get-WindowsTargetRuntimeState and propagate selected edition at caller** - `f4cffb8` (feat)
3. **Task 3: Create Test-Phase51Correctness.ps1 with CORRECT-01/04 + map-completeness gate** - `5d3d54e` (test)

**Plan metadata:** (docs commit at end)

## Files Created/Modified

- `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` - Replaced Get-Index with Get-WindowsImageSelection + added Get-ResolvedWindowsSKUFromImage; v1.4.0
- `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1` - Updated FunctionsToExport, bumped to v1.4.0 with release notes
- `FFUDevelopment/BuildFFUVM.ps1` - Added Get-WindowsTargetRuntimeState; updated Get-Index call site to use Get-WindowsImageSelection with SKU propagation
- `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` - New: 41-test content-match suite with map-completeness gate and CORRECT-03/02 placeholders
- `FFUDevelopment/version.json` - Bumped main version to 1.12.0, FFU.Imaging to 1.4.0

## Decisions Made

All decisions (D-01 through D-08) were pre-locked in 51-CONTEXT.md via adversarial review and honored exactly:
- D-01: Delete interactive loop (no Read-Host anywhere in build path)
- D-02/D-03: Single candidate auto-select; multiple candidates log+throw
- D-04: Rich return object + single $WindowsSKU reassignment at caller
- D-05/D-06/D-07/D-08: EditionId map + InstallationType + exact name fallback

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed em-dash Unicode characters from test file**
- **Found during:** Task 3 (Test file creation)
- **Issue:** Em dashes (U+2014) in comments and strings caused PowerShell 5.1 to generate non-fatal parse warnings due to CP1252 encoding mismatch — comment line was parsed as containing a token (confusing the parser slightly)
- **Fix:** Replaced all em dashes with ASCII hyphens in Test-Phase51Correctness.ps1
- **Files modified:** FFUDevelopment/Tests/Test-Phase51Correctness.ps1
- **Verification:** Test runs clean with no warnings, all 41 tests pass, exits 0
- **Committed in:** 5d3d54e (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - encoding bug in generated test file)
**Impact on plan:** Minor fix to ensure clean PS5.1 execution. No scope creep.

## Issues Encountered

- Module import for FFU.Imaging.psd1 requires Administrator privileges (`#Requires -RunAsAdministrator` in psm1); automated verify adapted to content-match assertions for psd1 exports instead of live module import. Module-load tests in the test file gracefully skip when not running as Administrator.
- PSScriptAnalyzer ran clean on both FFU.Imaging.psm1 and BuildFFUVM.ps1 (0 errors at Severity Error).

## Known Stubs

None - all implemented functionality is complete and wired. The placeholder sections in Test-Phase51Correctness.ps1 for CORRECT-03 and CORRECT-02 are intentional deferred gates, not stubs in the functional code.

## Threat Flags

None beyond the threat model defined in the plan (T-51-01 through T-51-IV all addressed by the implementation).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 51 Plan 02 (CORRECT-03 - ADK bcdboot): FFU.Imaging.psm1 is ready; `Add-BootFiles` can be extended with `AdkPath` and `WindowsArch` params per PATTERNS.md. Test-Phase51Correctness.ps1 has a labelled placeholder section for Plan 02 assertions.
- Phase 51 Plan 03 (CORRECT-02 - LTSC normalization): BuildFFUVM.ps1 is ready for `Get-EffectiveDriverWindowsRelease` injection at the driver dispatch sites.
- Plans 02 and 03 are independent of each other; both depend on this plan (51-01) being complete.
- Human UAT (deferred): correct edition from real non-English ISO; single-edition ISO salvage naming.

---
*Phase: 51-capture-boot-correctness*
*Completed: 2026-06-26*
