---
phase: 42-new-oem-manufacturers
plan: 06
subsystem: drivers
tags: [oem-drivers, tier3-stubs, asus, msi, getac, ui, build-layer]
requires:
  - phase: 42
    plan: 07
    provides: OEM infrastructure (ValidateSet, constants, switch cases)
provides:
  - ASUS driver stub implementations (UI + build-layer)
  - MSI driver stub implementations (UI + build-layer)
  - Getac driver stub implementations (UI + build-layer)
affects:
  - phase: 42
    plan: 08
    reason: Integration testing will verify all Tier 3 stubs work correctly
tech-stack:
  added: []
  patterns:
    - Tier 3 stub pattern for OEMs without official catalogs
    - Empty array returns for model lists
    - Failure PSCustomObject returns for download tasks
    - Structured [OEM][Model] logging with manual download URLs
decisions:
  - decision: Tier 3 stubs are complete implementations (not placeholders)
    rationale: ASUS has no official catalog, MSI requires SDK auth, Getac uses proprietary CLI
    alternatives: Reverse-engineer ASUS API (unstable), integrate MSI SDK (auth barrier), use Getac CLI (Windows-only tool)
    impact: Users must manually download drivers for these OEMs
  - decision: Include manual download URLs in all log messages
    rationale: Clear user guidance when automation unavailable
    alternatives: Generic "not supported" message (less helpful)
    impact: Users know where to get drivers manually
  - decision: Use same parameter signatures as functional OEM drivers
    rationale: Build script dispatch expects consistent calling convention
    alternatives: Minimal parameters (breaks dispatch compatibility)
    impact: Stubs can be called by existing infrastructure without modification
key-files:
  created:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.ASUS.psm1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.MSI.psm1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.Getac.psm1
  modified:
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psd1
duration: 5 minutes
completed: 2026-02-02
---

# Phase 42 Plan 06: ASUS, MSI, and Getac Tier 3 Stubs Summary

**One-liner:** Complete stub implementations for three Tier 3 OEMs without official enterprise driver catalogs (ASUS, MSI, Getac), returning empty/null results with clear manual download guidance.

## What Was Built

Created complete stub implementations for three Tier 3 OEMs that lack automated driver download capabilities:

### UI Layer Stubs (3 new modules)
- **FFUUI.Core.Drivers.ASUS.psm1**: Get-ASUSDriversModelList (empty array) + Save-ASUSDriversTask (failure result)
- **FFUUI.Core.Drivers.MSI.psm1**: Get-MSIDriversModelList (empty array) + Save-MSIDriversTask (failure result)
- **FFUUI.Core.Drivers.Getac.psm1**: Get-GetacDriversModelList (empty array) + Save-GetacDriversTask (failure result)

### Build Layer Stubs (3 new functions in FFU.Drivers.psm1)
- **Get-ASUSDrivers**: Returns $null with WARNING log (no official catalog available)
- **Get-MSIDrivers**: Returns $null with WARNING log (SDK requires authentication)
- **Get-GetacDrivers**: Returns $null with WARNING log (requires SmartUpdate CLI)

### Module Exports
Updated FFU.Drivers.psd1:
- FunctionsToExport: Added Get-ASUSDrivers, Get-MSIDrivers, Get-GetacDrivers
- Description: Added mention of stub support
- Tags: Added ASUS, MSI, Getac

## Stub Behavior Specification

### UI Layer Functions
**Get-*DriversModelList:**
- Takes no mandatory parameters (stubs don't need DriversFolder/Make)
- Logs WARNING with OEM-specific reason
- Logs manual download URL
- Returns @() (empty array)

**Save-*DriversTask:**
- Takes standard parameter signature (DriverItemData, DriversFolder, WindowsArch, WindowsRelease, ProgressQueue, CompressToWim, PreserveSourceOnCompress)
- Extracts $modelName and $identifier from DriverItemData
- Logs WARNING with [OEM][Model] prefix and reason
- Updates ProgressQueue status to "Not supported (stub)" if queue provided
- Returns PSCustomObject with Success=$false, DriverPath=$null

### Build Layer Functions
**Get-*Drivers:**
- Takes standard parameter signature (DriversFolder, Make, Model, WindowsArch, WindowsRelease, FFUDevelopmentPath)
- Logs WARNING with [OEM][$Model] prefix and reason
- Logs manual download URL with [OEM][$Model] prefix
- Returns $null

## OEM-Specific Details

| OEM | Reason for Stub | Manual URL |
|-----|----------------|-----------|
| ASUS | No official enterprise catalog (only reverse-engineered APIs) | https://www.asus.com/support/ |
| MSI | SDK requires authentication, gaming hardware focus | https://www.msi.com/support |
| Getac | Proprietary SmartUpdate CLI tool only | https://www.getac.com/en/support/ |

## Testing Results

### Module Import Test
- FFU.Drivers module imports successfully with all dependencies
- All three new functions available via Get-Command
- Module exports verified in psd1

### Existing Test Suite
- 101/107 tests passed
- 6 failures pre-existing (not related to this plan)
- No new test failures introduced

## Integration Points

### Plan 42-07 Wiring (Already Complete)
- Get-ModelsForMake switch: Cases for ASUS, MSI, Getac call Get-*DriversModelList
- FFU.Common.Parallel DownloadDriverByMake switch: Cases call Save-*DriversTask
- BuildFFUVM.ps1 dispatch: Cases call Get-*Drivers

### Plan 42-08 Integration Testing (Next)
- Will verify stub behavior with UI interactions
- Will confirm WARNING logs appear correctly
- Will validate empty model lists display properly

## Commits

| Commit | Description | Files |
|--------|-------------|-------|
| fc08be1 | UI stub modules (ASUS, MSI, Getac) | FFUUI.Core.Drivers.*.psm1 (3 files) |
| 59e4fe1 | Build-layer stub functions | FFU.Drivers.psm1, FFU.Drivers.psd1 |

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

**Plan 42-08 (Integration Testing):**
- All Tier 3 stubs ready for UI testing
- WARNING logs can be verified in FFUDevelopment.log
- Empty model lists ready for UI display testing

**Blockers:** None

**Concerns:** None - stubs are intentionally complete implementations (no future work needed for these OEMs unless official catalogs become available)

## Manual Verification Steps (for Plan 42-08)

1. **UI Model List Test:**
   - Select ASUS/MSI/Getac from Make dropdown
   - Verify model dropdown remains empty
   - Verify FFUDevelopment.log shows WARNING with manual URL

2. **Build Script Test:**
   - Run build with Make=ASUS/MSI/Getac
   - Verify build continues without error
   - Verify WARNING logs appear with manual download URLs
   - Verify build completes (skips driver download)

3. **Parallel Download Test:**
   - Attempt parallel driver download with ASUS/MSI/Getac
   - Verify progress queue receives "Not supported (stub)" status
   - Verify download result shows Success=$false

## Technical Notes

### Design Pattern: Tier 3 Stub
This pattern applies to any OEM without an official enterprise driver catalog:

1. **UI Layer:** Return empty model list immediately (no network calls)
2. **Build Layer:** Return $null immediately (no network calls)
3. **Logging:** Use structured [OEM][Model] prefix with clear reason and manual URL
4. **Parameter Compatibility:** Accept all standard parameters even if unused
5. **Non-Blocking:** Never throw exceptions - log WARNING and return gracefully

### Why These Are Complete (Not Placeholders)
- **ASUS:** Only reverse-engineered API exists - unstable and undocumented
- **MSI:** SDK requires developer authentication - not suitable for open-source tool
- **Getac:** SmartUpdate CLI is proprietary Windows-only tool - can't be automated via PowerShell

Future implementations possible only if official catalogs become available.

## Lessons Learned

**Stub Parameter Signatures Must Match Functional Implementations:**
- Build script dispatch uses consistent calling convention across all OEM functions
- UI parallel processing expects same parameter set for all Save-*DriversTask functions
- Accepting unused parameters is preferable to breaking compatibility

**User Guidance in Logs is Critical:**
- Manual download URLs in every WARNING message
- OEM-specific reasons (not generic "not supported")
- [OEM][Model] prefix enables log filtering

**Complete Stubs Prevent Future Confusion:**
- Clearly documented as complete implementations (not TODO items)
- No "coming soon" messaging that creates false expectations
- Explicit documentation of why automation unavailable (technical barriers, not just missing work)
