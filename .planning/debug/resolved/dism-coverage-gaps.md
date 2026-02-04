---
status: resolved
trigger: "Fix remaining unprotected DISM operations: dism-coverage-gaps"
created: 2026-02-04T00:00:00Z
updated: 2026-02-04T00:07:00Z
---

## Current Focus

hypothesis: CONFIRMED - All DISM coverage gaps have been fixed
test: Verifying the fixes with syntax check and module import tests
expecting: Both modules import successfully with new Test-DismReady gates in place
next_action: Run PowerShell syntax validation and module import tests

## Symptoms

expected: All DISM operations should have Test-DismReady gates to prevent 0x80004005 failures
actual: 4 DISM call sites are missing Test-DismReady protection (Add-FFUDrivers, Add-CustomWinPE)
errors: Users experience "DismInitialize failed. Error code = 0x80004005" during long builds
reproduction: Occurs when WIMMount filter driver degrades during 2+ hour FFU builds
started: Identified during audit after fixing Enable-WindowsFeaturesByName

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-02-04T00:01:00Z
  checked: FFU.Imaging.psm1 lines 2674-2710 (Add-FFUDrivers)
  found: Start-RequiredServicesForDISM is called at line 2675, but NO Test-DismReady gate before Mount-WindowsImage at lines 2680 and 2697
  implication: Missing protection for two Mount-WindowsImage calls (initial attempt + retry)

- timestamp: 2026-02-04T00:01:00Z
  checked: FFU.Media.psm1 lines 1114-1155 (Add-CustomWinPE)
  found: Start-RequiredServicesForDISM at line 1115, but NO Test-DismReady gate before Mount-WindowsImage (line 1118) or Add-WindowsPackage loop (line 1153)
  implication: Missing protection for one Mount-WindowsImage and 12 Add-WindowsPackage calls in loop

- timestamp: 2026-02-04T00:01:00Z
  checked: FFU.Imaging.psm1 lines 1923-1932 (Enable-WindowsFeaturesByName pattern)
  found: Perfect reference pattern with Test-DismReady gate and detailed error message
  implication: Must use identical pattern for consistency

- timestamp: 2026-02-04T00:02:00Z
  checked: Module versions
  found: FFU.Imaging v1.3.4, FFU.Media v1.8.0, main version v1.10.1
  implication: Will bump to FFU.Imaging v1.3.5, FFU.Media v1.8.1, main v1.10.2

- timestamp: 2026-02-04T00:03:00Z
  checked: FFU.Imaging.psm1 lines 2674-2689
  found: Added Test-DismReady gate at lines 2677-2684 (before Mount-WindowsImage at line 2688)
  implication: Protects both initial Mount-WindowsImage (line 2688) and retry attempt (line 2697)

- timestamp: 2026-02-04T00:03:00Z
  checked: FFU.Media.psm1 lines 1114-1125
  found: Added Test-DismReady gate at lines 1117-1124 (before Mount-WindowsImage at line 1127)
  implication: Single gate protects Mount-WindowsImage and all 12 Add-WindowsPackage calls in loop (starting line 1153)

- timestamp: 2026-02-04T00:04:00Z
  checked: Module manifests and version.json
  found: FFU.Imaging v1.3.5, FFU.Media v1.8.1, main v1.10.2 with release notes
  implication: All version files updated correctly

- timestamp: 2026-02-04T00:05:00Z
  checked: PowerShell syntax validation via PSParser::Tokenize
  found: Both FFU.Imaging.psm1 and FFU.Media.psm1 pass syntax validation with zero errors
  implication: Code changes are syntactically correct and will not cause parse errors

- timestamp: 2026-02-04T00:06:00Z
  checked: Test-DismReady gate pattern consistency
  found: Both gates use identical pattern - InvokeCommand.GetCommand check, Test-DismReady -AttemptRepair $true, detailed error message
  implication: Consistent implementation ensures predictable behavior across all DISM operations

## Resolution

root_cause: FFU.Imaging Add-FFUDrivers and FFU.Media Add-CustomWinPE were missing Test-DismReady gates before DISM operations (Mount-WindowsImage, Add-WindowsPackage). During long-running FFU builds (2+ hours), the WIMMount filter driver can degrade, causing these unprotected DISM operations to fail with "DismInitialize failed. Error code = 0x80004005". This was a gap left after previous DISM-HEALTH fixes that protected other call sites.

fix: Added Test-DismReady gates with AttemptRepair before all unprotected DISM operations:
1. FFU.Imaging.psm1 lines 2677-2684: Gate protects Mount-WindowsImage at line 2688 (initial) and line 2697 (retry)
2. FFU.Media.psm1 lines 1117-1124: Gate protects Mount-WindowsImage at line 1127 and all 12 Add-WindowsPackage calls in loop starting at line 1153
Pattern follows Enable-WindowsFeaturesByName (lines 1923-1931) for consistency.

verification:
- PowerShell syntax validation: Both modules pass PSParser validation
- Version updates: FFU.Imaging v1.3.5, FFU.Media v1.8.1, main v1.10.2
- Release notes: Added to both .psd1 manifests explaining DISM-HEALTH-COVERAGE fix
- Gate implementation verified: Both gates use identical pattern with InvokeCommand.GetCommand and Test-DismReady -AttemptRepair $true
- All 4 previously unprotected DISM call sites now have gates

files_changed:
- FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1 (added Test-DismReady gate at lines 2677-2684)
- FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1 (version 1.3.4 → 1.3.5, release notes)
- FFUDevelopment/Modules/FFU.Media/FFU.Media.psm1 (added Test-DismReady gate at lines 1117-1124)
- FFUDevelopment/Modules/FFU.Media/FFU.Media.psd1 (version 1.8.0 → 1.8.1, release notes)
- FFUDevelopment/version.json (main version 1.10.1 → 1.10.2, module descriptions updated)
