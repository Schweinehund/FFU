---
phase: 37-winget-app-ordering-and-dependencies
plan: 01
subsystem: winget
tags: [powershell, winget, mutex, atomic-writes, deduplication, dependency-metadata]

# Dependency graph
requires:
  - phase: 34-winget-bug-fixes
    provides: JSON mutex safety and MSI path quoting in Add-Win32SilentInstallCommand
provides:
  - Four helper functions (Invoke-WithNamedMutex, Set-FileContentAtomic, Get-WinGetWin32AppsJsonMutexName, Get-WinGetYamlScalarValue)
  - Upgraded Add-Win32SilentInstallCommand with 6 new params, mutex wrapper, atomic writes, three-tier dedup, metadata, SkipRemoveOnFailure
  - Get-Apps override section upgraded to Invoke-WithNamedMutex and Set-FileContentAtomic
  - Export-ModuleMember prepared for Add-Win32DependencySilentInstallCommands (Plan 02)
affects: [37-02 dependency resolution, 37-03 pester tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Invoke-WithNamedMutex wrapper replacing raw System.Threading.Mutex try/finally"
    - "Set-FileContentAtomic temp+rename for crash-safe JSON writes"
    - "SHA256-based mutex name per JSON file path via Get-WinGetWin32AppsJsonMutexName"
    - "Three-tier deduplication: PackageIdentifier, Name, CommandLine+Arguments"
    - "DependencyFor and PackageIdentifier metadata on WinGetWin32Apps.json entries"

key-files:
  modified:
    - "FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1"
    - "Tests/Unit/FFU.Common.Winget.Tests.ps1"

key-decisions:
  - "Replace ALL raw mutex usage with Invoke-WithNamedMutex wrapper (both Add-Win32SilentInstallCommand and Get-Apps override)"
  - "Use & (call operator) for scriptblock invocation in Invoke-WithNamedMutex to inherit parent scope"
  - "Capture scriptblock return value to handle duplicate detection return semantics"
  - "Add Add-Win32DependencySilentInstallCommands to Export-ModuleMember now (silently ignored until Plan 02 defines it)"
  - "Add YAML basename disambiguation as additional fallback for multi-installer resolution"

patterns-established:
  - "Invoke-WithNamedMutex: generic mutex wrapper with timeout, best-effort release, automatic dispose"
  - "Set-FileContentAtomic: temp file + atomic rename with .NET File.Move fallback to Move-Item"
  - "Get-WinGetWin32AppsJsonMutexName: SHA256 hash of path for unique per-file mutex names"

# Metrics
duration: 10min
completed: 2026-01-29
---

# Phase 37 Plan 01: Helper Functions and Add-Win32SilentInstallCommand Upgrade Summary

**Four helper functions and upgraded Add-Win32SilentInstallCommand with mutex wrapper, atomic writes, three-tier dedup, dependency metadata, and SkipRemoveOnFailure guard**

## Performance

- **Duration:** 10 min
- **Started:** 2026-01-29T01:25:20Z
- **Completed:** 2026-01-29T01:35:00Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- Added 4 module-internal helper functions: Get-WinGetWin32AppsJsonMutexName, Invoke-WithNamedMutex, Set-FileContentAtomic, Get-WinGetYamlScalarValue
- Upgraded Add-Win32SilentInstallCommand with 6 new optional parameters (YamlFilePath, BasePathOverride, PackageIdentifier, DependencyFor, SkipRemoveOnFailure, AppFolder now Mandatory)
- Replaced raw System.Threading.Mutex with Invoke-WithNamedMutex wrapper in both Add-Win32SilentInstallCommand and Get-Apps override section
- Replaced Set-Content with Set-FileContentAtomic for crash-safe JSON writes in both locations
- Added three-tier deduplication: PackageIdentifier (primary), Name (existing), CommandLine+Arguments (secondary)
- Added DependencyFor and PackageIdentifier metadata properties to new JSON entries
- Guarded all Remove-Item calls with SkipRemoveOnFailure switch
- Added multi-installer disambiguation by YAML basename match
- Updated Export-ModuleMember to include Add-Win32DependencySilentInstallCommands (Plan 02)
- All 16 existing Pester tests pass (backward compatibility verified)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add 4 helper functions** - `57b200b` (feat) - Get-WinGetWin32AppsJsonMutexName, Invoke-WithNamedMutex, Set-FileContentAtomic, Get-WinGetYamlScalarValue
2. **Task 2: Upgrade Add-Win32SilentInstallCommand** - `472960d` (feat) - 6 new params, mutex wrapper, atomic writes, dedup, metadata, SkipRemoveOnFailure
3. **Task 3: Upgrade Get-Apps override and Export-ModuleMember** - `0ab4418` (feat) - Mutex wrapper in Get-Apps, atomic writes, updated exports

## Files Created/Modified
- `FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1` - Added 4 helper functions, upgraded Add-Win32SilentInstallCommand with new params and internals, upgraded Get-Apps override section, updated Export-ModuleMember
- `Tests/Unit/FFU.Common.Winget.Tests.ps1` - Updated Named Mutex Usage test to validate Invoke-WithNamedMutex wrapper pattern instead of raw WinGetWin32AppsJsonLock string

## Decisions Made
- Replaced ALL raw mutex usage with Invoke-WithNamedMutex wrapper for consistency (both Add-Win32SilentInstallCommand and Get-Apps override)
- Used `& $ScriptBlock` (call operator) in Invoke-WithNamedMutex to inherit parent scope variables
- Captured scriptblock return value to handle `return @{ Added = $false }` inside mutex block (scriptblock `return` only exits scriptblock, not outer function)
- Pre-declared `$appNameToCheck` before Invoke-WithNamedMutex call so it's accessible inside scriptblock
- Added null-guard `if ($null -eq $appsData) { $appsData = @() }` for single-element JSON array edge case

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated Pester test for new mutex pattern**
- **Found during:** Task 3 verification
- **Issue:** Test `Should use named mutex WinGetWin32AppsJsonLock` checked source code for literal string `WinGetWin32AppsJsonLock`, which no longer exists after replacing raw mutex with Invoke-WithNamedMutex wrapper
- **Fix:** Updated test to `Should use named mutex via Invoke-WithNamedMutex wrapper` checking for `Invoke-WithNamedMutex`, `Get-WinGetWin32AppsJsonMutexName`, and `System.Threading.Mutex`
- **Files modified:** Tests/Unit/FFU.Common.Winget.Tests.ps1
- **Commit:** `0ab4418`

---

**Total deviations:** 1 (test update for new mutex pattern)
**Impact on plan:** No scope creep. Test still validates thread-safe mutex usage, just with updated assertion for new wrapper pattern.

## Issues Encountered
None - all tasks executed as planned with backward compatibility maintained.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Helper functions ready for Plan 02 to use (Invoke-WithNamedMutex, Set-FileContentAtomic, Get-WinGetYamlScalarValue)
- Add-Win32SilentInstallCommand accepts all params Plan 02 needs (YamlFilePath, BasePathOverride, PackageIdentifier, DependencyFor, SkipRemoveOnFailure)
- Export-ModuleMember pre-configured for Add-Win32DependencySilentInstallCommands function
- All 16 Pester tests pass as baseline for Plan 03 test additions

---
*Phase: 37-winget-app-ordering-and-dependencies*
*Completed: 2026-01-29*
