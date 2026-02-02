---
phase: 42-new-oem-manufacturers
plan: 07
subsystem: drivers
tags: [oem, acer, dynabook, panasonic, samsung, fujitsu, asus, msi, getac, driver-catalog]

# Dependency graph
requires:
  - phase: 39-model-normalization
    provides: Update-DriverMappingJson function structure
  - phase: 40-dell-driver-refactoring
    provides: Get-DriverExtractionResult exit code pattern
  - phase: 41-driver-matching
    provides: Get-ModelsForMake switch case pattern
provides:
  - OEM catalog URL constants for Acer, Dynabook, Samsung, Fujitsu in FFU.Constants
  - ValidateSet expansions across 4 locations to accept 8 new OEMs
  - Config schema and XAML UI support for new manufacturers
  - Get-DriverExtractionResult exit code handling for Tier 1/2 OEMs
  - Get-ModelsForMake switch cases (Tier 1/2 placeholder calls, Tier 3 complete stubs)
affects: [42-01-acer, 42-02-dynabook, 42-03-panasonic, 42-04-samsung, 42-05-fujitsu, 42-06-tier3-stubs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tier 1 OEMs (Acer, Dynabook, Panasonic) use catalog-based model lists with DriversFolder cache"
    - "Tier 2 OEMs (Samsung, Fujitsu) use portal HTML parsing with InputBox search"
    - "Tier 3 stubs (ASUS, MSI, Getac) show MessageBox explanation and return empty arrays"

key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psm1
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psd1
    - FFUDevelopment/BuildFFUVM.ps1
    - FFUDevelopment/config/ffubuilder-config.schema.json
    - FFUDevelopment/BuildFFUVM_UI.xaml
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1

key-decisions:
  - "Omit Panasonic catalog URL from constants pending portal access validation (plan 42-03 will add if public URL exists)"
  - "Tier 3 stubs (ASUS, MSI, Getac) are complete implementations requiring no future plans"
  - "Acer and Dynabook require WindowsRelease validation (OS-version-specific catalogs)"
  - "Get-DriverExtractionResult excludes Tier 3 stubs (no driver extraction)"

patterns-established:
  - "OEM catalog URLs follow consistent naming: {OEM}_CATALOG_URL or {OEM}_PORTAL_URL"
  - "Exit code switch blocks use standard patterns: expand.exe (0/1), ZIP (0/1), Windows Installer (0/1603/1618/1641/3010)"
  - "Tier 1 model list functions: Get-{OEM}DriversModelList -WindowsRelease -DriversFolder -Make"
  - "Tier 2 model list functions: Get-{OEM}DriversModelList -ModelSearchTerm -Headers -UserAgent"
  - "Tier 3 stubs: WriteLog WARNING + MessageBox explanation + return @()"

# Metrics
duration: 6min
completed: 2026-02-02
---

# Phase 42 Plan 07: New OEM Infrastructure Summary

**Scaffolding for 8 new OEM manufacturers: catalog constants, ValidateSet expansions, exit code handling, and UI switch cases with Tier 1/2 placeholders and Tier 3 complete stubs**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-02T13:00:34Z
- **Completed:** 2026-02-02T13:06:36Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Added 4 OEM catalog URL constants to FFU.Constants (Acer, Dynabook, Samsung, Fujitsu)
- Expanded ValidateSet in 4 locations to accept new OEMs (Get-DriverExtractionResult, Get-CachedOEMCatalog, Test-DriverDiskSpace, BuildFFUVM.ps1 Make param)
- Updated config schema and XAML tooltip with all 8 new manufacturers
- Added 5 exit code vendor blocks in Get-DriverExtractionResult for Tier 1/2 OEMs
- Added 8 switch cases in Get-ModelsForMake: 5 Tier 1/2 placeholder function calls, 3 Tier 3 complete stubs

## Task Commits

Each task was committed atomically:

1. **Task 1: Add OEM catalog URL constants and expand ValidateSet/config/XAML** - `c386654` (feat)
   - FFU.Constants: 4 new catalog URL constants with comments
   - FFU.Drivers.psm1: 3 ValidateSet expansions (Get-DriverExtractionResult with Tier 1/2, Get-CachedOEMCatalog with Tier 1/2, Test-DriverDiskSpace with all 8)
   - FFU.Drivers.psd1: Updated Description to mention new OEMs and stubs
   - BuildFFUVM.ps1: Expanded Make ValidateSet with all 8 OEMs
   - Config schema: Extended Make enum with all 8 OEMs
   - XAML: Updated Make tooltip with complete manufacturer list and stub note

2. **Task 2: Add exit code cases and Get-ModelsForMake switch cases** - `eb5e0a2` (feat)
   - FFU.Drivers.psm1: 5 new vendor exit code blocks (Acer/Dynabook/Panasonic with expand.exe codes, Samsung with ZIP codes, Fujitsu with Windows Installer codes)
   - FFUUI.Core.Drivers.psm1: 8 new switch cases (Acer/Dynabook/Panasonic call placeholder functions, Samsung/Fujitsu use InputBox search, ASUS/MSI/Getac are complete stubs)
   - Updated WindowsRelease validation to include Acer and Dynabook

## Files Created/Modified
- `FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psm1` - Added ACER_CATALOG_URL, DYNABOOK_CATALOG_URL, SAMSUNG_PORTAL_URL, FUJITSU_PORTAL_URL constants
- `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` - Expanded 3 ValidateSet locations, added 5 exit code vendor blocks
- `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psd1` - Updated Description to mention new OEMs and stubs
- `FFUDevelopment/BuildFFUVM.ps1` - Expanded Make parameter ValidateSet
- `FFUDevelopment/config/ffubuilder-config.schema.json` - Extended Make enum
- `FFUDevelopment/BuildFFUVM_UI.xaml` - Updated Make tooltip with all manufacturers and stub note
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1` - Added 8 switch cases in Get-ModelsForMake, updated WindowsRelease check

## Decisions Made

1. **Omit Panasonic catalog URL from constants**: Plan 42-RESEARCH.md notes Panasonic portal requires access validation. The Panasonic implementation plan (42-03) will add its own constant if a public URL is discovered, or use a hardcoded URL in the function.

2. **Tier 3 stubs are complete implementations**: ASUS, MSI, and Getac switch cases contain full stub logic (WriteLog WARNING, MessageBox explanation, return empty array). No future plan needed for these OEMs - they are ready to use (showing "not yet supported" message to users).

3. **Tier 1/2 function calls reference non-existent functions**: The switch cases for Acer, Dynabook, Panasonic, Samsung, and Fujitsu call functions like `Get-AcerDriversModelList` which do not yet exist. This is intentional - these functions will be created by plans 42-01 through 42-05. If a user selects one of these OEMs before the plan executes, they will get a PowerShell error, which is acceptable during development.

4. **Exit code patterns follow OEM extraction method**:
   - Acer, Dynabook, Panasonic use expand.exe patterns (0 success, 1 warning, default warn)
   - Samsung uses ZIP extraction patterns (0 success, 1 warning, default warn)
   - Fujitsu uses Windows Installer patterns (0/1641/3010 success, 1603/1618 warn, default warn)

5. **WindowsRelease validation updated for Acer and Dynabook**: These OEMs have OS-version-specific catalog entries (like Dell), so the validation check at line 32 now includes them alongside Dell and Lenovo.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. Module imports cleanly after all changes. All verification commands pass.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready for individual OEM implementation plans:**
- Plans 42-01 through 42-06 can now execute (ValidateSet, config, and switch case scaffolding complete)
- Each OEM plan will implement its Get-{OEM}DriversModelList and Get-{OEM}Drivers functions
- Tier 3 stubs (ASUS, MSI, Getac) require no further work

**Blockers:** None

**Notes:**
- Plan 42-08 (Save-{OEM}DriversTask functions) depends on 42-01 through 42-05 completing first
- All 8 OEMs now appear in UI dropdowns and config validation

---
*Phase: 42-new-oem-manufacturers*
*Completed: 2026-02-02*
