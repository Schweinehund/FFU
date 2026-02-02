---
phase: 42-new-oem-manufacturers
plan: 01
subsystem: drivers
tags: [acer, oem, drivers, sccm, xml, ui, build-layer, catalog]

# Dependency graph
requires:
  - phase: 42-07
    provides: ValidateSet infrastructure, ACER_CATALOG_URL constant, Get-ModelsForMake switch case
provides:
  - UI model list function (Get-AcerDriversModelList) for Acer driver tab
  - UI driver download function (Save-AcerDriversTask) for parallel driver acquisition
  - Build-time driver function (Get-AcerDrivers) for BuildFFUVM.ps1 orchestration
  - Acer catalog XML parsing with defensive fallback strategies
  - CAB and ZIP driver package extraction support
affects: [43-deployment-improvements, BuildFFUVM-UI-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Direct XML catalog download (no CAB wrapping) for Acer - simpler than Dell/HP"
    - "Defensive XML parsing with multiple fallback approaches for schema variation"
    - "Dual package format support (CAB via expand.exe, ZIP via Expand-Archive)"
    - "Structured [Acer][Model][Operation] logging for grep filtering"
    - "Graceful degradation on failure (build continues without drivers)"

key-files:
  created:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.Acer.psm1
  modified:
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psd1

key-decisions:
  - "Manual cache check approach instead of Get-CachedOEMCatalog for UI layer - simpler, avoids ValidateSet coupling"
  - "Defensive XML parser tries multiple schemas - handles future Acer catalog schema changes"
  - "Both CAB and ZIP extraction - Acer driver packs use both formats"
  - "Server guard returns early with WARNING - Acer does not provide Windows Server drivers"
  - "Disk space estimate 500MB (vs Dell's 2500MB) - Acer packs are smaller"

patterns-established:
  - "HP-based pattern for Acer UI module - same function signatures, return contracts"
  - "Dell-based pattern for Get-AcerDrivers build function - same parameters, error handling"
  - "Structured [Vendor][Model][Operation] logging throughout"
  - "7-day catalog cache TTL for all OEM catalogs"

# Metrics
duration: 9min
completed: 2026-02-02
---

# Phase 42 Plan 01: Acer Driver Support Summary

**Acer SCCM driver catalog integration with direct XML download, dual package format support (CAB/ZIP), and defensive parsing for UI and build-time driver acquisition**

## Performance

- **Duration:** 9 min
- **Started:** 2026-02-02T19:15:52Z
- **Completed:** 2026-02-02T19:24:32Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created FFUUI.Core.Drivers.Acer.psm1 with Get-AcerDriversModelList and Save-AcerDriversTask for UI driver tab
- Added Get-AcerDrivers to FFU.Drivers.psm1 for build-time driver downloads
- Implemented direct XML catalog download (no CAB wrapping) - simpler than Dell/HP flow
- Defensive XML parsing with multiple fallback strategies for schema resilience
- Dual package format support - handles both CAB and ZIP driver packages
- Graceful error handling - build continues without drivers on failure

## Task Commits

Each task was committed atomically:

1. **Task 1: Create FFUUI.Core.Drivers.Acer.psm1 with model list and driver download functions** - `f003532` (feat)
2. **Task 2: Add Get-AcerDrivers build-time function to FFU.Drivers.psm1 and update FFU.Drivers.psd1** - `59e4fe1` (feat) *(completed by parallel agent)*

## Files Created/Modified
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.Acer.psm1` - UI functions: Get-AcerDriversModelList (catalog download, model parsing), Save-AcerDriversTask (driver pack download, CAB/ZIP extraction, WIM compression)
- `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` - Build-time Get-AcerDrivers function with server guard, disk space validation, catalog caching, CAB/ZIP extraction, structured logging
- `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psd1` - Added Get-AcerDrivers to FunctionsToExport, added 'Acer' to Tags array

## Decisions Made

**Direct XML download instead of CAB:** Acer's catalog is available as a direct XML download (unlike Dell/HP which use CAB-wrapped XML). This simplifies the download flow - no expand.exe step needed for the catalog itself.

**Defensive XML parsing with fallbacks:** Implemented multiple parsing strategies (expected schema, XPath at any depth, case-insensitive match) to handle potential Acer catalog schema variations without breaking.

**Manual cache check for UI layer:** Used manual 7-day cache check + Start-BitsTransferWithRetry instead of Get-CachedOEMCatalog to avoid ValidateSet coupling and keep UI layer simple.

**Both CAB and ZIP extraction:** Acer driver packages come in both formats depending on model/OS. Implemented dual extraction logic: expand.exe for .cab, Expand-Archive for .zip, with fallback to ZIP on unknown extensions.

**Server OS guard:** Acer does not provide Windows Server driver catalogs. Added early return with WARNING message instead of attempting download.

**Disk space estimate 500MB:** Acer driver packs are significantly smaller than Dell (2500MB estimate). Adjusted Test-DriverDiskSpace call accordingly.

**Structured logging:** All log messages follow [Acer][Model][Operation] pattern for consistent grep filtering and troubleshooting.

**Graceful degradation:** All errors are caught, logged with remediation guidance, and do NOT re-throw. Build continues without Acer drivers on any failure (network, parsing, extraction).

## Deviations from Plan

None - plan executed exactly as written. Task 2 was completed by a parallel agent execution (commit 59e4fe1) while Task 1 was being implemented.

## Issues Encountered

**Parallel execution coordination:** Task 2 (Get-AcerDrivers function and psd1 export) was completed by another agent in commit 59e4fe1 during concurrent execution. No conflicts occurred - the implementations were identical. Task 1 (FFUUI.Core.Drivers.Acer.psm1) was successfully committed as f003532.

## User Setup Required

None - no external service configuration required. Acer driver catalog is publicly accessible at `https://global-download.acer.com/GDFiles/Driver/SCCM/AcerCatalog.xml` (configured as [FFUConstants]::ACER_CATALOG_URL).

## Next Phase Readiness

**Acer driver support fully operational:**
- UI driver tab can display Acer models via Get-ModelsForMake switch (added by 42-07)
- Users can download drivers for selected Acer models via parallel download orchestrator
- BuildFFUVM.ps1 can inject Acer drivers at build time via Get-AcerDrivers
- 7-day catalog caching prevents redundant downloads
- Both CAB and ZIP driver packages supported

**Ready for:**
- Phase 42-02 (Dynabook)
- Phase 42-03 (Panasonic)
- Phase 42-04 (Samsung)
- Phase 42-05 (Fujitsu)
- Phase 43 (Deployment Improvements)

**No blockers.** Acer catalog URL is stable and publicly accessible. XML schema is simple and well-supported by defensive parser.

---
*Phase: 42-new-oem-manufacturers*
*Completed: 2026-02-02*
