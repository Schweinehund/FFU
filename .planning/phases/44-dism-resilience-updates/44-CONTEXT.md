# Phase 44: DISM Resilience in FFU.Updates

## Problem Statement

The `Test-DismReady` function (fltmc-based WIMMount validation) was implemented in v1.9.8 to prevent `DismInitialize 0x80004005` failures. However, it was only applied to FFU.Imaging, FFU.VM, and BuildFFUVM.ps1 orchestrator points. The **FFU.Updates module was completely missed**, leaving the most DISM-intensive part of the build (Windows Update application) entirely unprotected.

## Evidence

User log from 2026-01-28 shows the exact failure pattern:
1. Build starts, Test-DismReady passes at startup
2. Initialize-DISMService passes before update phase
3. CU (KB5078127, 3.7 GB) applies successfully over ~8 minutes
4. WIMMount filter driver breaks/unloads after heavy CU servicing
5. .NET Framework CAB application hangs 10 min then fails: `DismInitialize failed. Error code = 0x80004005`
6. Retry calls Test-MountState which uses Get-WindowsEdition (DISM call) — hangs another 10 min
7. Build fails after ~30 min of unnecessary hanging

## Gap Analysis (from debugger evaluation)

| # | Gap | Severity | Location |
|---|-----|----------|----------|
| 1 | No Test-DismReady in FFU.Updates module | CRITICAL | Add-WindowsPackageWithRetry, Add-WindowsPackageWithUnattend |
| 2 | Retry path uses DISM to validate DISM | CRITICAL | Test-MountState calls Get-WindowsEdition (hangs when WIMMount broken) |
| 3 | No inter-update WIMMount health check | HIGH | Between sequential update applications in orchestrator |
| 4 | Raw Dism.exe /Cleanup-Image call unguarded | MODERATE | BuildFFUVM.ps1 component cleanup |

## Current Fix Coverage: 4/10

The existing Test-DismReady gates protect:
- Build startup (too early — 18+ min before failure)
- Resume re-validation (too early)
- VHDX creation / Expand-WindowsImage (wrong phase — failure is in update phase)
- Cleanup operations (not the failure point)

## Success Criteria

1. Test-DismReady called before each individual update application (not just phase start)
2. Retry path uses fltmc-based check (no DISM dependency) before retrying
3. Test-MountState guarded with Test-DismReady fast-fail
4. Raw Dism.exe calls guarded
5. Auto-repair attempted before failing out
6. Clear remediation messaging if repair fails
7. No more 10-minute hangs when WIMMount is broken
8. All existing Pester tests continue to pass
9. New Pester tests covering the WIMMount check integration points

## Files to Modify

- `FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1` — Primary target
- `FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psd1` — Version bump
- `FFUDevelopment/BuildFFUVM.ps1` — Dism.exe cleanup guard
- `FFUDevelopment/version.json` — Version bump

## Related

- `.planning/debug/resolved/dism-initialize-0x80004005.md` — Original fix session
- Phase 20 (`20-ffu-updates-reliability`) — Earlier reliability work on this module
