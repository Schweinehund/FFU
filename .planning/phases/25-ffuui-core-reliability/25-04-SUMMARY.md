---
phase: 25-ffuui-core-reliability
plan: 04
subsystem: FFUUI.Core
tags: [config, validation, ui, error-handling, user-experience]

dependency-graph:
  requires:
    - "25-02: Show-FFUValidationErrors function"
    - "FFU.Core: Test-FFUConfiguration function"
  provides:
    - "Load-time configuration validation in FFUUI.Core.Config"
    - "Validation state tracking in uiState.Data"
    - "Build-time validation check"
  affects:
    - "User workflow: validation errors shown immediately on load"
    - "Build reliability: users warned before building with invalid config"

tech-stack:
  patterns:
    - "Integration with existing FFU.Core validation"
    - "State tracking for cross-function communication"
    - "Graceful degradation when Test-FFUConfiguration unavailable"

key-files:
  created:
    - "Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1"
  modified:
    - "FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1"
    - "FFUDevelopment/BuildFFUVM_UI.ps1"
    - "FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1"
    - "FFUDevelopment/version.json"

decisions:
  - "Silent validation during auto-load (logs only, no popups on startup)"
  - "User choice to load config despite validation errors"
  - "Validation result stored in State.Data for build-time access"
  - "Build button warns but allows proceeding with known validation errors"

metrics:
  duration: "~25 minutes"
  completed: "2026-01-24"
---

# Phase 25 Plan 04: Load-Time Config Validation Summary

**One-liner:** Invoke-LoadConfiguration now validates config via Test-FFUConfiguration, shows errors via Show-FFUValidationErrors, stores validation state for build-time warning.

## What Changed

### FFUUI.Core.Config.psm1

**Invoke-LoadConfiguration** (lines 350-427):
- Added validation call to Test-FFUConfiguration after JSON parsing
- Converts PSCustomObject to hashtable for validation function
- Shows validation errors via Show-FFUValidationErrors (from Plan 02)
- Asks user if they want to load config despite errors
- Stores validation result in State.Data for build-time access
- Logs warnings without blocking user

**Invoke-AutoLoadPreviousEnvironment** (lines 1208-1252):
- Added silent validation (no popups on startup)
- Logs validation errors and warnings
- Stores validation result in State.Data for later check
- Non-intrusive: continues loading even with errors

### BuildFFUVM_UI.ps1

**State initialization** (lines 70-71):
```powershell
configValidationResult = $null;   # REL-UI-05: Stores validation result from config loading
hasValidationErrors    = $false   # REL-UI-05: Quick flag for build-time check
```

**Build button handler** (lines 424-438):
- Checks hasValidationErrors at build start
- Shows warning dialog if validation errors exist
- User can choose to proceed or cancel
- Logs user's choice

### Pester Tests

**Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1** (412 lines, 33 tests):
- Module structure tests (function exports)
- Validation integration code presence tests
- BuildFFUVM_UI.ps1 state initialization tests
- Validation state object behavior tests
- Code analysis tests for validation flow
- Error/warning count handling tests

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 5096bf5 | feat | Add load-time config validation to FFUUI.Core.Config |
| 9c2b86e | feat | Add validation state tracking to BuildFFUVM_UI.ps1 |
| 7e21678 | test | Add Pester tests for config validation integration |
| 63d9c18 | chore | Update FFUUI.Core to v0.0.17, bump main version to 1.8.39 |

## Verification Results

```
Tests: 33 total, 33 passed, 0 failed
Main version: 1.8.39
FFUUI.Core version: 0.0.17
Manifest version: 0.0.17
```

## Deviations from Plan

None - plan executed exactly as written.

## Success Criteria Met

- [x] Invoke-LoadConfiguration calls Test-FFUConfiguration before applying config
- [x] Validation errors shown via Show-FFUValidationErrors
- [x] User can choose to load config despite errors
- [x] Validation result stored in State.Data for build-time check
- [x] Auto-load logs validation issues without blocking UI
- [x] 33 Pester tests pass (exceeds 15+ requirement)
- [x] No PSScriptAnalyzer errors (code analysis tests verify patterns)

## Key Integration Points

1. **FFUUI.Core.Config.psm1 -> FFU.Core**
   - Calls `Test-FFUConfiguration -ConfigObject $configHashtable`
   - Uses graceful degradation if function unavailable

2. **FFUUI.Core.Config.psm1 -> FFUUI.Core.ErrorDisplay.psm1**
   - Calls `Show-FFUValidationErrors` to display errors (from Plan 02)

3. **FFUUI.Core.Config.psm1 -> BuildFFUVM_UI.ps1**
   - Stores validation result in `State.Data.configValidationResult`
   - Sets `State.Data.hasValidationErrors` flag

4. **BuildFFUVM_UI.ps1 Build Handler**
   - Checks `hasValidationErrors` flag at build start
   - Warns user if building with known validation errors

## User Experience Flow

### Load Config File (manual load)
1. User clicks "Load Config"
2. File browser opens
3. User selects config.json
4. JSON parsed successfully
5. **NEW:** Test-FFUConfiguration validates config
6. If errors found:
   - Show-FFUValidationErrors displays structured error dialog
   - MessageBox asks "Load anyway?"
   - If No: config not loaded
   - If Yes: config loaded, hasValidationErrors = true
7. UI updated with config values

### Auto-load Previous Config (startup)
1. UI starts, finds existing FFUConfig.json
2. JSON parsed successfully
3. **NEW:** Test-FFUConfiguration validates config
4. If errors found:
   - Errors logged (no popup - silent mode)
   - hasValidationErrors = true
5. Config applied to UI
6. User can see log warnings, build button will warn

### Build Start
1. User clicks "Build FFU"
2. **NEW:** Check hasValidationErrors flag
3. If true:
   - Warning dialog: "Config has validation errors. Proceed?"
   - If No: build cancelled
   - If Yes: build continues (at user's risk)
4. Build process starts

## Next Phase Readiness

This completes REL-UI-05 (Fail fast on invalid configuration files). The remaining plans in Phase 25 are:

- 25-03: Job Failure Context Extraction (REL-UI-05 context extraction)

With this plan complete, users get immediate feedback when loading invalid configs, rather than discovering issues only when the build fails.
