# Phase 15 Plan 02: Actionable Config Errors Summary

**Completed:** 2026-01-23

## One-liner

Enhanced Test-FFUConfiguration with "To fix:" guidance, typo detection, and example values for all validation error types.

## Changes Made

### Task 1: Enhance Test-FFUConfiguration error messages
- Added `Get-ExampleValue` helper function to generate fix suggestions based on schema
- Added `Find-SimilarPropertyName` helper for typo detection (case-insensitive and prefix matching)
- Enhanced unknown property detection with similar name suggestions
- Type validation now shows example of correct format with "To fix:" guidance
- Enum validation lists all valid values and suggests first option
- Range validation shows valid range with fix guidance
- Pattern validation provides context-specific examples (VMName, WindowsVersion, etc.)

**Note:** Task 1 was already committed as part of 15-01 plan execution. Verified implementation is correct.

### Task 2: Enhance schema with descriptions
- Added `x-common-values` to Memory property (4GB, 8GB, 16GB, 32GB byte values)
- Added `x-common-values` to Disksize property (30GB, 50GB, 100GB, 200GB byte values)
- Added `x-example` to VMHostIPAddress showing expected format (192.168.1.100)
- Added `x-example` to WindowsVersion showing 24H2 format
- Enhanced WindowsSKU description with common choices guidance

### Task 3: Add tests for actionable error messages
- Added 9 new tests tagged with 'Actionable' for error message verification:
  - Invalid enum value includes valid options and fix guidance
  - Type mismatch includes example of correct format
  - Unknown property suggests similar property name (typo detection)
  - Range violation (below minimum) shows valid range and fix guidance
  - Range violation (above maximum) shows valid range and fix guidance
  - Pattern violation shows expected format
  - Unknown property without similar name suggests removal
  - Type mismatch boolean shows true/false guidance
  - All errors in multi-error config have fix guidance
- Updated existing range tests for new "out of range" message format
- Fixed invalid JSON test (PowerShell 7 accepts trailing commas)

## Files Modified

| File | Changes |
|------|---------|
| `FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1` | Enhanced Test-FFUConfiguration with actionable errors (Task 1 - already present) |
| `FFUDevelopment/config/ffubuilder-config.schema.json` | Added x-common-values and x-example hints |
| `Tests/Unit/FFU.Core.ConfigValidation.Tests.ps1` | Added 9 actionable error tests, updated 6 existing tests |

## Verification

```
=== Final Verification for 15-02 ===

1. Error messages include 'To fix:' guidance:
   Enum error has 'To fix:': True
2. Invalid enum shows valid options:
   Has 'Valid values:': True
3. Type mismatch shows example:
   Error has 'To fix:': True
4. Unknown property typo detection:
   Error has 'Did you mean': True
5. Running Pester tests...
   Tests Passed: 49/49
   Tests Failed: 0

=== ALL SUCCESS CRITERIA MET ===
```

## Commits

| Hash | Message |
|------|---------|
| 19f4701 | feat(15-02): enhance config schema with x-example hints and common values |
| 0c67c4d | test(15-02): add tests for actionable config validation error messages |

## Example Error Messages

### Before (old format)
```
Property 'Processors' value 0 is less than minimum 1
```

### After (actionable format)
```
Property 'Processors' value 0 is out of range (below minimum).
Valid range: 1 to 64
To fix: Change "Processors": 0 to "Processors": 1 (or higher)
```

### Typo Detection
```
Unknown property 'WindowsSKU2' is not allowed in configuration.
Did you mean 'WindowsSKU'? (property names are case-sensitive)
To fix: Change "WindowsSKU2" to "WindowsSKU" in your config file.
```

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Use `x-common-values` custom schema property | Standard JSON Schema doesn't have a property for common values; x- prefix is conventional for extensions |
| Detect similar property names via case-insensitive and prefix matching | Covers most common typo patterns (case errors, partial names) |
| Show first enum value as suggested fix | Provides concrete example rather than just listing options |

## Next Plan Readiness

- All success criteria met
- 49/49 tests passing
- Ready for 15-03 (Config migration/upgrade paths)

## Duration

~10 minutes
