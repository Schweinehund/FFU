---
phase: 38-subst-drive-mapping
verified: 2026-01-29T20:30:00Z
status: passed
score: 12/12 must-haves verified
---

# Phase 38: SUBST Drive Mapping for Long Paths Verification Report

**Phase Goal:** Map a SUBST virtual drive during driver operations to prevent long path failures (>260 chars)
**Verified:** 2026-01-29T20:30:00Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Driver extraction uses SUBST-mapped drive to keep paths below 260 characters | ✓ VERIFIED | Invoke-DismDriverInjectionWithSubstLoop in FFU.Drivers.psm1 (line 745-901), walks up paths >240 chars and maps via SUBST |
| 2 | SUBST mapping cleaned up after operations, even on failure | ✓ VERIFIED | ApplyFFU.ps1 lines 935-938, 1004-1007 use finally blocks; FFU.Drivers.psm1 lines 890-898 cleanup in finally |
| 3 | Build log shows SUBST creation and removal | ✓ VERIFIED | WriteLog "[SUBST] Mapping", "[SUBST] Removing" at lines 652, 725, 790, 862, 892 in FFU.Drivers.psm1 and ApplyFFU.ps1 |

**Score:** 3/3 truths verified

### Required Artifacts (Plan 38-01)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| FFU.Drivers/FFU.Drivers.psm1 | SUBST helper functions + Copy-Drivers improvements | ✓ VERIFIED | Lines 548-741: 3 SUBST functions; Lines 2388-2393: GUID normalization; 6 Copy-Item -LiteralPath calls |
| FFU.Core/FFU.Core.psm1 | Auto-growing buffer in Get-PrivateProfileString | ✓ VERIFIED | Lines 318-341: bufferSize 1KB->64KB loop with maxBufferSize=65536 |
| BuildFFUVM.ps1 | DllImport with CharSet.Unicode | ✓ VERIFIED | Lines 1550, 1559: CharSet = CharSet.Unicode, SetLastError = true |

### Required Artifacts (Plan 38-02)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| FFU.Drivers/FFU.Drivers.psm1 | Invoke-DismDriverInjectionWithSubstLoop function | ✓ VERIFIED | Lines 745-901: INF scan, deduplicate, walk-up >240 chars, sequential SUBST loop |
| FFU.Imaging/FFU.Imaging.psm1 | SUBST integration in New-FFU | ✓ VERIFIED | Lines 2702-2714: Calls Invoke-DismDriverInjectionWithSubstLoop with fallback |
| WinPEDeployFFUFiles/ApplyFFU.ps1 | SUBST for WIM and folder injection | ✓ VERIFIED | Lines 918-938 (WIM), 977-1008 (folder): SUBST mapping with Get-Command checks and finally cleanup |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| New-DriverSubstMapping | Get-AvailableDriveLetter | calls to find available letter | ✓ VERIFIED | FFU.Drivers.psm1 line 634 |
| New-DriverSubstMapping | cmd.exe /c subst | creates virtual drive mapping | ✓ VERIFIED | FFU.Drivers.psm1 lines 650, 657 |
| Get-PrivateProfileString | Win32.Kernel32 | auto-growing buffer loop | ✓ VERIFIED | FFU.Core.psm1 lines 324-339 |
| FFU.Imaging New-FFU | Invoke-DismDriverInjectionWithSubstLoop | replaces Add-WindowsDriver | ✓ VERIFIED | FFU.Imaging.psm1 lines 2703-2704 |
| ApplyFFU.ps1 | New-DriverSubstMapping | maps driver folder | ✓ VERIFIED | ApplyFFU.ps1 lines 922, 983 |
| Invoke-DismDriverInjectionWithSubstLoop | Remove-DriverSubstMapping | cleanup in finally | ✓ VERIFIED | FFU.Drivers.psm1 lines 890-898 |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| PATH-01 | ✓ SATISFIED | None |

### Anti-Patterns Found

No blocking anti-patterns detected. Code follows established patterns.


## Detailed Verification

### Plan 38-01 Must-Haves

1. **Get-AvailableDriveLetter scans Z->A via Get-PSDrive** - ✓ VERIFIED
   - Lines 576-583 in FFU.Drivers.psm1
   - ASCII loop from 90 (Z) down to 65 (A)
   - Returns first unused letter or $null
   - Uses Get-PSDrive -PSProvider FileSystem

2. **New-DriverSubstMapping maps folder with defensive pre-removal** - ✓ VERIFIED
   - Lines 590-689 in FFU.Drivers.psm1
   - Line 650: Defensive pre-removal cmd.exe /c subst /d
   - Line 654: Path escaping for cmd.exe
   - Line 657: Create mapping
   - Returns PSCustomObject with DriveLetter, DriveName, DrivePath

3. **Remove-DriverSubstMapping unmaps with non-blocking error handling** - ✓ VERIFIED
   - Lines 692-741 in FFU.Drivers.psm1
   - try/catch wrapper logs WARNING but never throws
   - Safe to call even if mapping does not exist

4. **Get-PrivateProfileString auto-growing buffer 1KB-64KB** - ✓ VERIFIED
   - Lines 318-341 in FFU.Core.psm1
   - bufferSize starts at 1024, max 65536
   - while loop doubles buffer until success or max
   - Exit condition: charsCopied < capacity-1

5. **DllImport specifies CharSet = CharSet.Unicode** - ✓ VERIFIED
   - Lines 1550, 1559 in BuildFFUVM.ps1
   - Both GetPrivateProfileString and GetPrivateProfileSection
   - Include SetLastError for diagnostics

6. **Copy-Drivers normalizes ClassGUID** - ✓ VERIFIED
   - Lines 2388-2399 in FFU.Drivers.psm1
   - Strips trailing ; comments
   - Regex extraction of GUID token

7. **Copy-Drivers uses -LiteralPath for all Copy-Item calls** - ✓ VERIFIED
   - 6 occurrences in FFU.Drivers.psm1
   - Prevents wildcard expansion on special characters

### Plan 38-02 Must-Haves

1. **Invoke-DismDriverInjectionWithSubstLoop complete** - ✓ VERIFIED
   - Lines 745-901 in FFU.Drivers.psm1
   - INF scanning, path walk-up, deduplication, sequential SUBST loop
   - Fallback to direct Add-WindowsDriver when no drive letters
   - finally cleanup always executes

2. **FFU.Imaging New-FFU uses SUBST loop** - ✓ VERIFIED
   - Lines 2702-2714 in FFU.Imaging.psm1
   - Get-Command check for backward compatibility
   - Fallback to direct Add-WindowsDriver if function not available

3. **ApplyFFU.ps1 folder-based injection uses SUBST with try/finally** - ✓ VERIFIED
   - Lines 977-1008 in ApplyFFU.ps1
   - Get-Command check for WinPE compatibility
   - Fallback to direct path with WARNING
   - finally block cleanup guaranteed

4. **Build log shows SUBST messages** - ✓ VERIFIED
   - Multiple WriteLog "[SUBST]" calls throughout codebase

5. **SUBST mapping always cleaned up in finally blocks** - ✓ VERIFIED
   - FFU.Drivers.psm1 lines 890-898
   - ApplyFFU.ps1 lines 935-938, 1004-1007

## Version Updates

| Module | Before | After | Type | Notes |
|--------|--------|-------|------|-------|
| FFU.Drivers.psd1 | 1.4.0 | 1.5.0 | MINOR | New public functions |
| FFU.Core.psd1 | 1.0.23 | 1.0.24 | PATCH | Enhanced Get-PrivateProfileString |
| FFU.Imaging.psd1 | 1.3.2 | 1.3.3 | PATCH | SUBST integration |

---

**Verified:** 2026-01-29T20:30:00Z
**Verifier:** Claude (gsd-verifier)
