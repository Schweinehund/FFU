---
phase: 51-capture-boot-correctness
plan: 03
subsystem: build-orchestration
tags: [BuildFFUVM, LTSC, OEM-drivers, driver-dispatch, year-normalization, CORRECT-02, PowerShell]

# Dependency graph
requires:
  - plan: 51-02
    provides: FFU.Imaging Add-BootFiles ADK bcdboot fix; Test-Phase51Correctness.ps1 with CORRECT-02 placeholder

provides:
  - Get-EffectiveDriverWindowsRelease: pure transform normalizing LTSC 2016/2019/2021->10, 2024->11
  - driverWindowsRelease injected at driversJsonPath dispatch (taskArguments) and single-model dispatch (Invoke-BuildPhase OEM calls)
  - Test-Phase51Correctness.ps1 CORRECT-02 assertions: 19 new tests (7 content-match + 12 pure-function table)
  - Suite total: 68 tests, all green, exits 0

affects: [52-driver-grid-ui-fixes, 53-driver-build-deploy-correctness]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Outer-scope $driverWindowsRelease before Invoke-BuildPhase scriptblock (closure capture, Pitfall 5)"
    - "Dedicated normalized var instead of global mutation: $driverWindowsRelease keeps $WindowsRelease load-bearing"
    - "Pure function table tests via local copy in test file (avoids BuildFFUVM.ps1 dot-source side-effects)"

key-files:
  modified:
    - FFUDevelopment/BuildFFUVM.ps1
    - FFUDevelopment/Tests/Test-Phase51Correctness.ps1

key-decisions:
  - "D-14: Mapping 2016/2019/2021->10, 2024->11 gated on $isLTSC (WindowsSKU *LTS* pattern)"
  - "D-15: 2019 collision resolved by *LTS* gate -- Server 2019 (Standard/Datacenter) never remapped"
  - "D-16: Normalize into dedicated $driverWindowsRelease only; global $WindowsRelease never reassigned"
  - "D-17: HP/Microsoft/Lenovo/Dell OEM provider calls now receive $driverWindowsRelease at both dispatch sites"

requirements-completed: [CORRECT-02]

# Metrics
duration: 20min
completed: 2026-06-27
---

# Phase 51 Plan 03: Capture/Boot Correctness (CORRECT-02) Summary

**Get-EffectiveDriverWindowsRelease normalizes LTSC year-based WindowsRelease values to their base release (10/11) for OEM driver dispatch, injected via dedicated $driverWindowsRelease at both dispatch sites without mutating the load-bearing global $WindowsRelease**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-06-27T00:00:00Z (approx)
- **Completed:** 2026-06-27T00:19:19Z
- **Tasks:** 2 completed
- **Files modified:** 2 (BuildFFUVM.ps1, Test-Phase51Correctness.ps1)

## Accomplishments

- Added script-level function `Get-EffectiveDriverWindowsRelease` to `BuildFFUVM.ps1` (upstream `04dfb5f` verbatim): LTSC 2016/2019/2021 -> 10, LTSC 2024 -> 11, Server/non-LTSC pass-through (D-14/D-15). Includes full SYNOPSIS/DESCRIPTION docblock explaining the D-16 mutation prohibition.
- Injected `$driverWindowsRelease` at the **driversJsonPath dispatch site** (~3074): computed before `$taskArguments` hashtable; `WindowsRelease = $driverWindowsRelease` replaces `$WindowsRelease` in the task args (D-16).
- Injected `$driverWindowsRelease` at the **single-model dispatch site** in the OUTER scope BEFORE `Invoke-BuildPhase -Action {}` (Pitfall 5 closure capture); all four OEM provider calls (HP, Microsoft, Lenovo, Dell) now pass `-WindowsRelease $driverWindowsRelease` (D-17).
- Both injection sites include a conditional `WriteLog` that records the normalization only when it occurs (LTSC builds), with no noise for standard builds.
- Global `$WindowsRelease` is untouched throughout: FFU naming, `$releaseToSKUMapping`, MSRT naming, VHDX cache keys, and the Server `$WindowsVersion` switch all continue to use the original value (D-16).
- Replaced CORRECT-02 placeholder in `Test-Phase51Correctness.ps1` with 19 assertions: 7 content-match checks (function definition, `*LTS*` gate, 2016/2019/2021->10 mapping, 2024->11 mapping, both dispatch sites assigned, >=4 OEM calls use `$driverWindowsRelease`, global `$WindowsRelease` not bare-reassigned) and 12 pure-function table tests covering LTSC 2016/2019/2021/2024, Server 2019/2022/2025 (both Standard and Datacenter), non-LTSC client Win10/11, IoT Enterprise LTSC 2024, Enterprise N LTSC 2021.
- Suite total: 68 tests, all green, exits 0.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Get-EffectiveDriverWindowsRelease and inject driverWindowsRelease at both dispatch sites** - `2c1d538` (feat)
2. **Task 2: Append CORRECT-02 assertions to Test-Phase51Correctness.ps1** - `5f7ec21` (test)

## Files Created/Modified

- `FFUDevelopment/BuildFFUVM.ps1` - Added `Get-EffectiveDriverWindowsRelease` script-level function after `Get-WindowsTargetRuntimeState`; injected `$driverWindowsRelease` at both driver dispatch sites (driversJsonPath ~3082 and single-model ~3244); OEM provider calls (HP/Microsoft/Lenovo/Dell) now use `$driverWindowsRelease`
- `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` - CORRECT-02 placeholder replaced with 19 active assertions; header/synopsis/summary updated to include CORRECT-02; suite now 68 tests

## Decisions Made

All decisions were pre-locked in 51-CONTEXT.md via adversarial review and honored exactly:
- D-14: LTSC year mapping 2016/2019/2021->10, 2024->11
- D-15: 2019 collision resolved by `*LTS*` SKU pattern; Server SKUs never remapped
- D-16: Dedicated `$driverWindowsRelease` only; global `$WindowsRelease` never reassigned
- D-17: All four OEM providers (HP/Microsoft/Lenovo/Dell) receive `$driverWindowsRelease` at both dispatch sites

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None. All implemented functionality is complete and wired. BuildFFUVM.ps1 has no placeholder or TODO in the new code. Test-Phase51Correctness.ps1 has no remaining placeholder sections.

## Threat Flags

None beyond the threat model defined in the plan:
- T-51-02A (wrong driver release for LTSC): mitigated by `Get-EffectiveDriverWindowsRelease` + `$driverWindowsRelease` at both dispatch sites
- T-51-02B (clobbering global `$WindowsRelease`): explicitly prevented; global is never reassigned (D-16)
- T-51-02N (pure in-process transform): accepted - no external input, network, secret, or boot-trust surface

## Self-Check: PASSED

- `FFUDevelopment/BuildFFUVM.ps1` -- modified with function and two injection sites (verified via parse check + content-match)
- `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` -- CORRECT-02 section active; 68 tests all green, exits 0
- Task commits verified: `2c1d538` (feat), `5f7ec21` (test) -- both in git log

---
*Phase: 51-capture-boot-correctness*
*Completed: 2026-06-27*
