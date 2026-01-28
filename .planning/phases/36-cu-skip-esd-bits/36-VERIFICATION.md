---
phase: 36-cu-skip-esd-bits
verified: 2026-01-28T23:30:00Z
status: passed
score: 4/4 must-haves verified
re_verification: false
---

# Phase 36: CU Skip Logic and ESD BITS Downloads Verification Report

**Phase Goal:** Skip CU downloads when ESD version already matches/exceeds CU version, and switch ESD downloads to BITS transfer
**Verified:** 2026-01-28T23:30:00Z
**Status:** PASSED
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Build skips CU download when ESD version equals or exceeds available CU | VERIFIED | BuildFFUVM.ps1 lines 3431-3496: Full version comparison with [version] -ge operator, clearing cuUpdateInfos/cupUpdateInfos and setting UpdateLatestCU=$false when ESD >= CU |
| 2 | Build log shows explicit message explaining CU skip with version comparison result | VERIFIED | BuildFFUVM.ps1 line 3448: WriteLog with ESD version, skip reason (matches/is newer than), CU KB ID, and CU version. Line 3463 logs when CU IS needed. |
| 3 | ESD downloads use BITS transfer with progress logging | VERIFIED | FFU.Updates.psm1 line 597-598: Start-BitsTransferWithRetry for ESD downloads. Priority cascade at FFU.Common.Core.psm1 lines 483-495. UI ComboBox at BuildFFUVM_UI.xaml line 321 allows priority selection. |
| 4 | Pester tests verify CU skip version comparison logic and BITS transfer integration | VERIFIED | FFU.Updates.CUSkip.Tests.ps1 (578 lines, 28 tests) covers equal/newer/older/parse-failures/null. FFU.Common.BitsPriority.Tests.ps1 (390 lines, 22 tests) covers cascade/env-var/init. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1 | Get-WindowsESDMetadata + Get-KBLink version extraction | VERIFIED | Get-WindowsESDMetadata at line 277 (165 lines). Get-KBLink enhanced at line 703 with global:LastKBWindowsVersion. |
| FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psd1 | Get-WindowsESDMetadata exported | VERIFIED | Listed in FunctionsToExport at line 43. |
| FFUDevelopment/BuildFFUVM.ps1 | CU skip logic + VHDX cache tracking + BitsPriority param | VERIFIED | ESD metadata at lines 3326-3342. Version comparison at lines 3431-3496. VHDX cache at lines 3537-3539. BitsPriority param at line 468. |
| FFUDevelopment/FFU.Common/FFU.Common.Core.psm1 | Set-BitsTransferPriority + priority cascade | VERIFIED | Set-BitsTransferPriority at line 358. Priority cascade in Start-BitsTransferWithRetry at lines 483-494. Script-level init at lines 17-21. |
| FFUDevelopment/BuildFFUVM_UI.xaml | BITS Priority ComboBox | VERIFIED | cmbBitsPriority at line 321, 4 options, descriptive tooltip. |
| FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1 | Control init + defaults | VERIFIED | Registered at line 174, defaults at lines 382-386. |
| FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1 | SelectionChanged handler | VERIFIED | Handler at lines 396-409 calls Set-BitsTransferPriority. |
| FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1 | Config save/load | VERIFIED | Save at line 140, load at lines 763-764 with PSObject property check. |
| Tests/Unit/FFU.Updates.CUSkip.Tests.ps1 | CU skip tests | VERIFIED | 578 lines, 28 test cases. No stubs or TODOs. |
| Tests/Unit/FFU.Common.BitsPriority.Tests.ps1 | BITS priority tests | VERIFIED | 390 lines, 22 test cases. No stubs or TODOs. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| FFU.Updates.psm1 | BuildFFUVM.ps1 | Get-WindowsESDMetadata returns Version | WIRED | Called at line 3333, Version checked at 3334 |
| FFU.Updates.psm1 | BuildFFUVM.ps1 | global:LastKBWindowsVersion | WIRED | Set at line 708, read at lines 3378/3387 |
| FFU.Common.Core.psm1 | BuildFFUVM.ps1 | FFU_BITS_PRIORITY env var | WIRED | Set at line 393, checked at line 873 |
| FFUUI.Core.Handlers | FFU.Common.Core | Set-BitsTransferPriority call | WIRED | Handler at line 403 calls function |
| FFUUI.Core.Config | BuildFFUVM_UI.xaml | BitsPriority persistence | WIRED | Save at line 140, load at line 764 |
| CUSkip Tests | FFU.Updates | Module scope + AST verification | WIRED | Imports module, uses AST for unexported function |
| BitsPriority Tests | FFU.Common.Core | Direct function testing | WIRED | Imports module, calls Set-BitsTransferPriority |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| BUGFIX-04: Skip CU when ESD version >= CU | SATISFIED | None |
| DL-01: ESD downloads use BITS transfer | SATISFIED | None |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | - | - | - | No TODO/FIXME/placeholder/stub patterns in any Phase 36 artifacts |

### Human Verification Required

### 1. UI ComboBox Visual Appearance

**Test:** Launch BuildFFUVM_UI.ps1, navigate to Updates tab, verify BITS Priority ComboBox
**Expected:** ComboBox shows Foreground/High/Normal/Low with Normal as default
**Why human:** Cannot verify visual layout programmatically

### 2. End-to-End CU Skip in Live Build

**Test:** Run Windows 11 build where ESD version >= available CU
**Expected:** Log shows skip message with both versions; CU download is skipped
**Why human:** Requires live network access to Microsoft Update Catalog

### 3. BITS Priority Effect on Downloads

**Test:** Set priority to Foreground, run build with downloads
**Expected:** Log shows "BITS transfer priority: Foreground"; downloads proceed
**Why human:** Speed depends on network conditions

### Gaps Summary

No gaps found. All four success criteria verified. 50 total Pester tests (28 CU skip + 22 BITS priority). All artifacts substantive, properly wired, and following codebase patterns.

---

_Verified: 2026-01-28T23:30:00Z_
_Verifier: Claude (gsd-verifier)_
