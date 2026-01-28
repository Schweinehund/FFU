# Phase 36 Plan 02: BITS Priority Configuration Summary

**One-liner:** Configurable BITS transfer priority with UI ComboBox, ThreadJob env var propagation, and cascade resolution (param > env > script > default)

## Completed Tasks

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Add Set-BitsTransferPriority and enhance Start-BitsTransferWithRetry | b647e82 | FFU.Common.Core.psm1 |
| 2 | Add BITS Priority UI controls and config integration | 776e901 | BuildFFUVM_UI.xaml, FFUUI.Core.Initialize.psm1, FFUUI.Core.Handlers.psm1, FFUUI.Core.Config.psm1, BuildFFUVM.ps1 |

## What Was Built

### Set-BitsTransferPriority Function (FFU.Common.Core.psm1)
- New function that sets `$script:BitsTransferPriority` and `$env:FFU_BITS_PRIORITY`
- Environment variable ensures ThreadJob propagation (background jobs inherit parent env)
- Full comment-based help with priority level descriptions

### Enhanced Start-BitsTransferWithRetry (FFU.Common.Core.psm1)
- New `-Priority` parameter with `[ValidateSet('Foreground', 'High', 'Normal', 'Low')]`
- Priority resolution cascade: explicit parameter > FFU_BITS_PRIORITY env var > script variable > 'Normal' default
- Priority passed through to both resilient download system and legacy BITS-only path
- Backward compatible: no Priority argument = Normal default behavior unchanged

### XAML ComboBox (BuildFFUVM_UI.xaml)
- Added `cmbBitsPriority` ComboBox in Updates tab after IncludePreviewUpdates checkbox
- Four options: Foreground, High, Normal, Low
- Descriptive tooltip explaining priority levels

### UI Integration
- **Initialize**: Control reference registered, default set to 'Normal' (or from generalDefaults)
- **Handler**: SelectionChanged event calls Set-BitsTransferPriority immediately
- **Config Save**: BitsPriority persisted in JSON config
- **Config Load**: BitsPriority restored from JSON config via Match() pattern

### BuildFFUVM.ps1 Parameter
- New `-BitsPriority` parameter with ValidateSet and 'Normal' default
- Post-config-load initialization calls Set-BitsTransferPriority when non-default
- Config file values auto-flow via existing parameter binding loop (lines 820-858)

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Env var for ThreadJob propagation | ThreadJobs inherit parent process environment; simpler than explicit parameter passing through scriptblock |
| Cascade resolution order | Explicit param > env > script > default follows standard precedence patterns; env var allows external override |
| ComboBox in Updates tab | Thematically groups with update/download settings; BITS priority primarily affects update downloads |
| Default 'Normal' | Maintains backward compatibility; users opt-in to Foreground for speed |

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

1. `Set-BitsTransferPriority` function exists at line 358 - sets both script var and env var
2. `Start-BitsTransferWithRetry` has `-Priority` parameter with cascade at lines 483-494
3. XAML has `cmbBitsPriority` ComboBox with 4 options in Updates tab (line 321)
4. UI handler calls `Set-BitsTransferPriority` on selection change (Handlers line 396)
5. Config save includes BitsPriority (Config line 140), load restores it (Config line 763)
6. BuildFFUVM.ps1 has `-BitsPriority` parameter (line 468) with initialization (line 870)
7. No PSScriptAnalyzer errors in any modified files

## Files Modified

| File | Changes |
|------|---------|
| FFUDevelopment/FFU.Common/FFU.Common.Core.psm1 | Added script var, Set-BitsTransferPriority function, Priority param in Start-BitsTransferWithRetry |
| FFUDevelopment/BuildFFUVM_UI.xaml | Added cmbBitsPriority ComboBox in Updates tab |
| FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1 | Registered control, set default |
| FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1 | Wired SelectionChanged handler |
| FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1 | Added BitsPriority to save/load |
| FFUDevelopment/BuildFFUVM.ps1 | Added -BitsPriority parameter with initialization |

## Metrics

- **Duration:** ~6 minutes
- **Completed:** 2026-01-28
- **Tasks:** 2/2
- **Commits:** 2
