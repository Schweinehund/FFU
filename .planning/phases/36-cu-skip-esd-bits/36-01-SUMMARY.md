---
phase: 36-cu-skip-esd-bits
plan: 01
subsystem: updates
tags: [powershell, windows-update, esd, version-comparison, bits, vhdx-cache]

# Dependency graph
requires:
  - phase: 20-reliability-hardening
    provides: FFU.Updates module with catalog query retry and cache management
provides:
  - Get-WindowsESDMetadata function for resolving ESD version without downloading
  - Get-KBLink enhanced with Windows version extraction from KB search results
  - CU skip logic comparing ESD version against CU version in BuildFFUVM.ps1
  - VHDX cache tracking for skipped CU updates
affects: [36-cu-skip-esd-bits remaining plans, vhdx-caching, windows-update-workflow]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ESD metadata resolution without download for version comparison"
    - "Global variable propagation for cross-function version data (global:LastKBWindowsVersion)"
    - "Safe version parsing with [version] type and try/catch fallback"
    - "VHDX cache tracking for skipped updates via cachedIncludedUpdateNames"

key-files:
  modified:
    - "FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1"
    - "FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psd1"
    - "FFUDevelopment/BuildFFUVM.ps1"

key-decisions:
  - "Use 4-part version pattern (major.minor.build.revision) for ESD filename parsing instead of 2-part"
  - "Fall back to downloading CU on any version parse failure (safe default behavior)"
  - "Guard CU skip logic with WindowsRelease == 11 and no ISOPath to avoid Windows 10/ISO builds"
  - "Track skipped update names in cachedIncludedUpdateNames for VHDX cache consistency"
  - "Use global:LastKBWindowsVersion for KB version propagation (matches existing global variable pattern)"

patterns-established:
  - "ESD metadata resolution: Download products.cab, parse XML, extract version from filename without downloading ESD"
  - "Version comparison gate: Parse versions with try/catch, compare with [version] -ge, log skip/download decision"

# Metrics
duration: 12min
completed: 2026-01-28
---

# Phase 36 Plan 01: CU Skip + ESD Version Comparison Summary

**ESD version comparison against CU versions to skip unnecessary 3-4GB cumulative update downloads for Windows 11 builds**

## Performance

- **Duration:** 12 min
- **Started:** 2026-01-28T22:40:33Z
- **Completed:** 2026-01-28T22:52:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Get-WindowsESDMetadata function resolves ESD version from products.cab XML without downloading the ESD file
- Get-KBLink extracts Windows version from KB search results via enhanced regex with fallback
- BuildFFUVM.ps1 compares ESD vs CU versions and skips download when ESD >= CU, saving 3-4GB bandwidth
- Skipped update names tracked for VHDX cache consistency so cache matching works correctly
- Version parse failures safely fall back to downloading CU (never breaks builds)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Get-WindowsESDMetadata and enhance Get-KBLink** - `b647e82` (feat) - Note: Changes were already committed as part of prior 36-02 execution that bundled FFU.Updates changes
2. **Task 2: Add CU skip version comparison and VHDX cache tracking** - `858c526` (feat)

## Files Created/Modified
- `FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1` - Added Get-WindowsESDMetadata function; enhanced Get-KBLink with version extraction and KBWindowsVersion return property
- `FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psd1` - Added Get-WindowsESDMetadata to FunctionsToExport
- `FFUDevelopment/BuildFFUVM.ps1` - Added ESD metadata resolution, version comparison, CU skip logic, and VHDX cache tracking for skipped updates

## Decisions Made
- Used 4-part version regex (`\d+\.\d+\.\d+\.\d+`) instead of upstream's 2-part pattern to capture full version like "10.0.26100.1742" for accurate comparison
- Following upstream behavior: equal versions skip CU download (ESD already includes it)
- Using `$global:LastKBWindowsVersion` for version propagation across function boundaries (consistent with existing `$global:LastKBArticleID` pattern)
- Added `KBWindowsVersion` property to all Get-KBLink return objects for structured access

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task 1 already committed in prior session**
- **Found during:** Task 1 staging
- **Issue:** All FFU.Updates changes (Get-WindowsESDMetadata, Get-KBLink enhancements, manifest update) were already committed as `b647e82` by a prior 36-02 execution
- **Fix:** Verified changes matched plan requirements, proceeded to Task 2 without re-committing
- **Files affected:** FFU.Updates.psm1, FFU.Updates.psd1
- **Verification:** All Task 1 verification checks pass against HEAD

---

**Total deviations:** 1 (prior commit contained Task 1 work)
**Impact on plan:** No scope creep. Task 1 work was correct and complete; Task 2 executed fresh.

## Issues Encountered
None - Task 2 implementation followed plan exactly as specified.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- CU skip logic complete and integrated into build pipeline
- ESD metadata resolution available for any future version-aware logic
- VHDX cache tracking maintains consistency when updates are skipped
- Ready for version management (module version bumps) and remaining phase 36 plans

---
*Phase: 36-cu-skip-esd-bits*
*Completed: 2026-01-28*
