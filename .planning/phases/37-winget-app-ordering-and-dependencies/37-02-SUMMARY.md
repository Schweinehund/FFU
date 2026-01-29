---
phase: 37-winget-app-ordering-and-dependencies
plan: 02
subsystem: winget
tags: [powershell, winget, dependency-resolution, install-ordering, stable-sort, yaml]

# Dependency graph
requires:
  - phase: 37-01
    provides: Helper functions (Invoke-WithNamedMutex, Set-FileContentAtomic, Get-WinGetYamlScalarValue, Get-WinGetWin32AppsJsonMutexName) and upgraded Add-Win32SilentInstallCommand with dependency metadata params
provides:
  - Add-Win32DependencySilentInstallCommands function for automatic dependency discovery
  - Get-Application hooks for dependency processing (fresh and pre-downloaded paths)
  - Get-Apps post-download reorder logic enforcing AppList.json installation order
  - Dependency-aware stable sort with architecture suffix normalization
  - Full install manifest logging before installation begins
affects: [37-03 pester tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dependencies/ subfolder discovery with Get-ChildItem -Filter *.yaml"
    - "3-key stable sort: OrderKey, IsDependency, OriginalIndex for deterministic ordering"
    - "Architecture suffix normalization via regex: \\s+\\((x86|x64|arm64)\\)$"
    - "DependencyFor marker for dependency-parent grouping in install queue"
    - "Fail-safe reorder with try/catch warn-and-proceed pattern"

key-files:
  modified:
    - "FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1"

key-decisions:
  - "Reorder logic lives inside Get-Apps (not extracted to separate function) per CONTEXT.md"
  - "Dependencies slot before parent app via IsDependency=0 (deps) vs 1 (apps) in stable sort"
  - "Unknown/unmatched entries pushed to end with [int]::MaxValue orderKey"
  - "Dependency failure is WARNING only - does not fail the build"
  - "Pre-downloaded app path also processes dependencies for consistency"

patterns-established:
  - "Post-download reorder pattern: build order map -> index entries -> stable sort -> reassign priorities -> atomic write"
  - "Dependency discovery pattern: scan Dependencies/*.yaml -> extract PackageIdentifier -> call Add-Win32SilentInstallCommand with DependencyFor"

# Metrics
duration: 4min
completed: 2026-01-29
---

# Phase 37 Plan 02: Dependency Resolution and Post-Download Reorder Summary

**Add-Win32DependencySilentInstallCommands function for automatic dependency discovery, Get-Application hooks, and Get-Apps post-download reorder logic enforcing AppList.json installation order with dependency-aware stable sort**

## Performance

- **Duration:** 4 min
- **Started:** 2026-01-29T01:34:14Z
- **Completed:** 2026-01-29T01:38:26Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Added Add-Win32DependencySilentInstallCommands function that discovers Dependencies/ subfolder, processes each *.yaml manifest, extracts PackageIdentifier, and calls Add-Win32SilentInstallCommand with dependency parameters (DependencyFor, PackageIdentifier, SkipRemoveOnFailure)
- Hooked dependency processing into Get-Application fresh download path (after main app Add-Win32SilentInstallCommand, with warning on failure)
- Hooked dependency processing into Get-Application pre-downloaded path (both arch-subfolder and non-arch-subfolder variants)
- Added post-download reorder section to Get-Apps after override section
- Reorder builds desiredOrderMap from AppList.json winget entries, normalizes names by stripping architecture suffixes, and applies 3-key stable sort (OrderKey, IsDependency, OriginalIndex)
- Dependencies sort before their parent app via DependencyFor marker (IsDependency=0 < 1)
- Unknown/unmatched entries pushed to end of install queue ([int]::MaxValue)
- Reorder detects if changes are needed before writing (skips no-op reorder)
- Per-app old->new priority logging during reorder
- Full install manifest with dependency markers logged before installation begins
- Reorder failure is non-blocking (warn and proceed with current order)
- All 32 existing Pester tests pass (backward compatibility verified)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add dependency resolution function and hook into Get-Application** - `bd05b7d` (feat) - Add-Win32DependencySilentInstallCommands function, Get-Application hooks for fresh and pre-downloaded paths
2. **Task 2: Add post-download reorder logic to Get-Apps** - `a6060df` (feat) - desiredOrderMap, 3-key stable sort, priority reassignment, install manifest logging, fail-safe try/catch

## Files Created/Modified
- `FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1` - Added Add-Win32DependencySilentInstallCommands function (WINGET-02), Get-Application dependency hooks (fresh + pre-downloaded paths), Get-Apps post-download reorder section (WINGET-01)

## Decisions Made
- Reorder logic placed inside Get-Apps per CONTEXT.md (not extracted to separate function)
- Dependencies slot before parent via IsDependency=0 vs 1 in 3-key stable sort
- Unknown/unmatched entries get [int]::MaxValue orderKey (pushed to end of queue)
- Architecture suffixes stripped with regex `\s+\((x86|x64|arm64)\)$` for name normalization
- DependencyFor value used as baseName for order matching (instead of dependency's own name)
- Dependency processing failure is WARNING only (does not fail the build or affect main app result)
- Pre-downloaded app path also calls dependency processing for completeness
- allFailed tracking: returns error code 5 only if ALL dependencies failed

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None - all tasks executed as planned with backward compatibility maintained.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both WINGET-01 (install ordering) and WINGET-02 (dependency resolution) features are implemented
- Ready for Plan 37-03 (Pester tests) to add comprehensive test coverage
- All 32 existing Pester tests pass as baseline for Plan 03 test additions
- New function Add-Win32DependencySilentInstallCommands is exported and testable

---
*Phase: 37-winget-app-ordering-and-dependencies*
*Completed: 2026-01-29*
