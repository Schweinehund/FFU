---
phase: 42-new-oem-manufacturers
verified: 2026-02-02T14:30:00Z
status: gaps_found
score: 6/8 OEMs functional
gaps:
  - truth: "User can select Dynabook from the Make dropdown and download drivers"
    status: failed
    reason: "Get-DynabookDrivers function exists but is NOT exported due to missing entry in Export-ModuleMember at line 4409 of FFU.Drivers.psm1"
    artifacts:
      - path: "FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1"
        issue: "Export-ModuleMember (line 4409-4426) missing Get-DynabookDrivers - function defined at line 4004 but not exported"
    missing:
      - "Add Get-DynabookDrivers to Export-ModuleMember array in FFU.Drivers.psm1 (after line 4416 Get-AcerDrivers)"
  - truth: "User can select Fujitsu from the Make dropdown and download drivers"
    status: failed
    reason: "Get-FujitsuDrivers function exists but is NOT exported due to missing entry in Export-ModuleMember at line 4409 of FFU.Drivers.psm1"
    artifacts:
      - path: "FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1"
        issue: "Export-ModuleMember (line 4409-4426) missing Get-FujitsuDrivers - function defined at line 3425 but not exported"
    missing:
      - "Add Get-FujitsuDrivers to Export-ModuleMember array in FFU.Drivers.psm1 (after line 4413 Get-DellDrivers)"
---

# Phase 42: New OEM Manufacturers Verification Report

**Phase Goal:** Add driver support for 8 new OEM manufacturers: Acer, Dynabook, Panasonic, Samsung, Fujitsu, ASUS, MSI, and Getac

**Verified:** 2026-02-02T14:30:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | All 8 new OEMs accepted in ValidateSet across 4 locations | ? VERIFIED | FFU.Drivers.psm1 lines 171, 473, 845; BuildFFUVM.ps1 line 343; config schema line 275 all include 12 OEMs |
| 2 | OEM catalog URL constants exist in FFUConstants | ? VERIFIED | ACER_CATALOG_URL (line 538), DYNABOOK_CATALOG_URL (542), SAMSUNG_PORTAL_URL (546), FUJITSU_PORTAL_URL (550), PANASONIC_CATALOG_URL (555) all present |
| 3 | Config schema accepts all 8 new OEMs in Make enum | ? VERIFIED | ffubuilder-config.schema.json line 275 has all 12 OEM values |
| 4 | XAML tooltip lists all supported manufacturers | ? VERIFIED | BuildFFUVM_UI.xaml line 677 includes all 12 OEMs with stub note |
| 5 | Get-ModelsForMake switch handles all 8 new OEMs | ? VERIFIED | FFUUI.Core.Drivers.psm1 lines 57-100 have cases for all 8 new OEMs |
| 6 | User can select Acer and download drivers | ? VERIFIED | Get-AcerDrivers exported, UI module exists (339 lines), function wired |
| 7 | User can select Dynabook and download drivers | ? FAILED | Function exists (line 4004) but NOT in Export-ModuleMember (line 4409) |
| 8 | User can select Panasonic and download drivers | ? VERIFIED | Get-PanasonicDrivers exported, UI module exists, function wired |
| 9 | User can select Samsung and download drivers | ? VERIFIED | Get-SamsungDrivers exported, UI module exists (301 lines), function wired |
| 10 | User can select Fujitsu and download drivers | ? FAILED | Function exists (line 3425) but NOT in Export-ModuleMember (line 4409) |
| 11 | ASUS/MSI/Getac stubs return guidance messages | ? VERIFIED | All 3 stubs return null with proper log messages |
| 12 | Pester tests cover all 8 new OEMs | ? VERIFIED | 3 test files with 1022 total lines covering all OEMs |

**Score:** 10/12 truths verified (6/8 OEMs functional)

### Gaps Summary

**2 of 8 new OEMs are non-functional** due to missing Export-ModuleMember entries:

1. **Dynabook (Tier 1):**
   - Function defined: Line 4004 ?
   - Manifest lists it: Line 73 ?
   - Export-ModuleMember includes it: ? MISSING
   - Fix: Add ''Get-DynabookDrivers'', after line 4416 in Export-ModuleMember array

2. **Fujitsu (Tier 2):**
   - Function defined: Line 3425 ?
   - Manifest lists it: Line 70 ?
   - Export-ModuleMember includes it: ? MISSING
   - Fix: Add ''Get-FujitsuDrivers'', after line 4413 in Export-ModuleMember array

**Root Cause:** FFU.Drivers.psm1 has an explicit Export-ModuleMember statement (lines 4409-4426) that overrides the manifest''s FunctionsToExport. Plans 42-02 and 42-05 updated the manifest but forgot to update the Export-ModuleMember statement.

**Other 6 OEMs work correctly:**
- Acer (Tier 1) ?
- Panasonic (Tier 1) ?
- Samsung (Tier 2) ?
- ASUS (Tier 3 stub) ?
- MSI (Tier 3 stub) ?
- Getac (Tier 3 stub) ?

---

_Verified: 2026-02-02T14:30:00Z_
_Verifier: Claude (gsd-verifier)_
