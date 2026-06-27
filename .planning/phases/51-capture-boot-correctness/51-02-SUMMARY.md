---
phase: 51-capture-boot-correctness
plan: 02
subsystem: imaging, preflight
tags: [FFU.Imaging, FFU.Preflight, bcdboot, ADK, Secure-Boot, CORRECT-03, ThreadJob, PowerShell]

# Dependency graph
requires:
  - plan: 51-01
    provides: FFU.Imaging.psm1 with Add-BootFiles already exported; Test-Phase51Correctness.ps1 with CORRECT-03 placeholder

provides:
  - Add-BootFiles with AdkPath+WindowsArch params using ADK bcdboot exclusively (hard-fail)
  - Test-FFUADK ADK bcdboot.exe preflight check with Secure Boot 2023 remediation
  - Test-Phase51Correctness.ps1 CORRECT-03 assertions (8 new tests, suite 49 total, all green)

affects: [52-driver-grid-ui-fixes, 53-driver-build-deploy-correctness, 54-update-cache-capture-naming]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ADK bcdboot path resolution: Join-Path {AdkPath} Assessment and Deployment Kit\\Deployment Tools\\{amd64|arm64}\\BCDBoot\\bcdboot.exe"
    - "Hard-fail on missing tool: Test-Path guard + throw with actionable -UpdateADK remediation"
    - "Preflight accumulation pattern: $errors/$missingFiles flow through existing New-FFUCheckResult block"
    - "D-13 diagnostic logging: WriteLog resolved bcdboot path before invocation"

key-files:
  modified:
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1
    - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1
    - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1
    - FFUDevelopment/BuildFFUVM.ps1
    - FFUDevelopment/Tests/Test-Phase51Correctness.ps1

key-decisions:
  - "D-09: Add-BootFiles hard-fails (throw) when ADK bcdboot not found -- no silent host fallback"
  - "D-11: BCDBoot leaf folder is PascalCase; arch maps arm64->arm64, all else->amd64 (mirrors FFU.ADK Oscdimg pattern)"
  - "D-12: Test-FFUADK CHECK 5 reuses $archPath already computed at CHECK 4; errors flow through existing result block"
  - "D-13: ADK path logged at Add-BootFiles invocation time; cert-variant caveat recorded in comment"

requirements-completed: [CORRECT-03]

# Metrics
duration: 20min
completed: 2026-06-27
---

# Phase 51 Plan 02: Capture/Boot Correctness (CORRECT-03) Summary

**Add-BootFiles now uses the arch-correct ADK bcdboot.exe exclusively with a hard-fail guard; Test-FFUADK detects a missing ADK bcdboot early with -UpdateADK remediation**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-06-27
- **Tasks:** 3 completed
- **Files modified:** 5 (FFU.Imaging.psm1, FFU.Preflight.psm1, FFU.Preflight.psd1, BuildFFUVM.ps1, Test-Phase51Correctness.ps1)

## Accomplishments

- Extended `Add-BootFiles` (FFU.Imaging.psm1) with mandatory `-AdkPath [string]` and `-WindowsArch [ValidateSet('x86','x64','arm64')]` parameters; resolves bcdboot via `{AdkPath}\Assessment and Deployment Kit\Deployment Tools\{amd64|arm64}\BCDBoot\bcdboot.exe` (BCDBoot PascalCase, arch-aware)
- Hard-fail: `Test-Path` guards the resolved path; if missing, `throw "ADK BCDBoot was not found at '$bcdBootPath'. Install Windows ADK with Deployment Tools or run with -UpdateADK `$true."` — no silent host fallback possible
- Removed bare `Invoke-Process bcdboot ...` host invocation; replaced with `Invoke-Process $bcdBootPath ...`
- D-13 diagnostic: `WriteLog "Adding boot files using ADK bcdboot: $bcdBootPath"` + inline comment documenting the cert-variant caveat (Dec 2024 ADK stages 2011 certs; a future ADK bump is a conscious decision)
- Updated `BuildFFUVM.ps1` Add-BootFiles call (line ~4548) to pass `-AdkPath $adkPath -WindowsArch $WindowsArch` (both already in scope from line ~3217 and param block)
- Added CHECK 5 in `Test-FFUADK` (FFU.Preflight.psm1): reuses `$archPath` already computed at CHECK 4; `Test-Path -PathType Leaf` on the bcdboot.exe path; on miss, appends to `$errors`/`$missingFiles` which the existing pass/fail result block surfaces as a Critical failure with `-UpdateADK $true` remediation
- Bumped `FFU.Preflight.psd1` to 1.7.0 with CORRECT-03 release notes
- Replaced CORRECT-03 placeholder in `Test-Phase51Correctness.ps1` with 8 content-match assertions; suite now 49 tests, all green, exits 0

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend Add-BootFiles to use ADK bcdboot with hard-fail** - `477660f` (feat)
2. **Task 2: Add ADK bcdboot existence check to Test-FFUADK; bump FFU.Preflight to 1.7.0** - `9a11e7e` (feat)
3. **Task 3: Append CORRECT-03 assertions to Test-Phase51Correctness.ps1** - `0727559` (test)

## Files Created/Modified

- `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` - Add-BootFiles extended with AdkPath+WindowsArch params, ADK bcdboot resolution, Test-Path guard, hard-fail throw, D-13 diagnostic log; bare host bcdboot call removed
- `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` - Test-FFUADK CHECK 5 added: ADK BCDBoot\bcdboot.exe existence check feeding $errors/$missingFiles
- `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1` - ModuleVersion bumped to 1.7.0 with CORRECT-03 release notes
- `FFUDevelopment/BuildFFUVM.ps1` - Add-BootFiles call at ~4548 updated to pass -AdkPath $adkPath -WindowsArch $WindowsArch
- `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` - CORRECT-03 placeholder replaced with 8 active assertions; $PreflightPsm1/$PreflightPsd1 paths added; summary message updated

## Decisions Made

All decisions were pre-locked in 51-CONTEXT.md via adversarial review and honored exactly:
- D-09: Hard-fail throw on missing ADK bcdboot; no host fallback (silent failure eliminated)
- D-11: BCDBoot leaf folder is PascalCase; arm64 stays arm64, everything else -> amd64 (mirrors FFU.ADK Oscdimg arch pattern)
- D-12: New check reuses $archPath from CHECK 4; errors accumulate into existing result block (no new result-construction code needed)
- D-13: Resolved bcdboot path logged as diagnostic; cert-variant caveat captured in inline comment

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None. All implemented functionality is complete and wired. The CORRECT-02 placeholder in Test-Phase51Correctness.ps1 is an intentional deferred gate for Plan 03.

## Threat Flags

None beyond the threat model defined in the plan (T-51-03A through T-51-03D all addressed):
- T-51-03A (host bcdboot silent cert drift): eliminated by hard-fail and exclusive ADK path use
- T-51-03B (late discovery wasting full build): mitigated by CHECK 5 in Test-FFUADK
- T-51-03C ($adkPath traversal): accepted - registry-sourced, system-protected
- T-51-03D (ADK-version drift): accepted with logging - D-13 comment captures the caveat

## Next Phase Readiness

- Phase 51 Plan 03 (CORRECT-02 - LTSC driver year normalization): independent of this plan; BuildFFUVM.ps1 is ready for `Get-EffectiveDriverWindowsRelease` injection. Test-Phase51Correctness.ps1 has the CORRECT-02 placeholder section.
- Human UAT (deferred): Captured FFU must boot on Secure Boot 2023-cert hardware to confirm the ADK bcdboot path correctly stages 2011-cert boot files.

## Self-Check: PASSED

All modified files confirmed present. All task commits verified in git log:
- `477660f` feat(51-02): extend Add-BootFiles to use ADK bcdboot with hard-fail (CORRECT-03)
- `9a11e7e` feat(51-02): add ADK bcdboot existence check to Test-FFUADK; bump FFU.Preflight to 1.7.0
- `0727559` test(51-02): append CORRECT-03 assertions to Test-Phase51Correctness.ps1

---
*Phase: 51-capture-boot-correctness*
*Completed: 2026-06-27*
