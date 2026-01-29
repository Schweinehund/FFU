---
phase: 39
plan: 01
subsystem: drivers
tags: [dell, hp, lenovo, systemid, normalization, groupmanifest, platformlist]
depends_on:
  requires: []
  provides:
    - Dell GroupManifest Display CDATA model name normalization
    - SystemId extraction for Dell (regex) and HP (PlatformList.xml 3-tier lookup)
    - MachineType extraction for Lenovo (regex)
    - Get-HPSystemIdFromPlatformList exported function
    - DriverMapping.json schema with optional SystemId/MachineType fields
  affects:
    - Phase 41 (Driver Matching) consumes SystemId/MachineType for matching
    - Phase 42 (New OEM Manufacturers) may add SystemID patterns for additional OEMs
tech_stack:
  added: []
  patterns:
    - GroupManifest Display CDATA extraction with PDK prefix stripping
    - 3-tier matching (exact, alphanumeric-stripped, contains)
    - Per-call hashtable cache for XML lookups
    - Non-throwing extraction with $null fallback
key_files:
  created: []
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.Dell.psm1
    - FFUDevelopment/FFU.Common/FFU.Common.Drivers.psm1
decisions:
  - id: 39-01-01
    description: "Use ReadSubtree() DOM approach in Get-DellDriversModelList instead of sequential CDATA tracking"
    rationale: "Reliable child element access for GroupManifest/Display, matches proven pattern in Save-DellDriversTask"
  - id: 39-01-02
    description: "HP PlatformList.xml cache built inline within Update-DriverMappingJson on first HP entry"
    rationale: "Per-call hashtable cache avoids repeat XML parsing across HP entries in same batch"
  - id: 39-01-03
    description: "Extract Get-HPSystemIdFromPlatformList as a named exported function"
    rationale: "Enables direct test access and reuse outside Update-DriverMappingJson"
  - id: 39-01-04
    description: "Save-DellDriversTask model matching checks GroupManifest, Model/Display, and Brand+Model assembly"
    rationale: "Models listed via GroupManifest normalization must be findable when downloading drivers"
metrics:
  duration: "~5 minutes"
  completed: "2026-01-29"
---

# Phase 39 Plan 01: Model Name Normalization and SystemID Extraction Summary

**One-liner:** Dell GroupManifest Display CDATA normalization with brand dedup, plus build-time SystemID/MachineType extraction for Dell/HP/Lenovo in DriverMapping.json

## What Was Done

### Task 1: Dell Model Name Normalization Using GroupManifest Display CDATA

Refactored `Get-DellDriversModelList` from a sequential CDATA-tracking streaming parser to a `ReadSubtree()` DOM approach per SoftwareComponent. This enables reliable extraction of `GroupManifest/Display` CDATA text as the preferred model name source.

**Normalization logic (upstream commit 667edf3):**
1. If `GroupManifest/Display` exists: strip "PDK Catalog for " prefix (case-insensitive), trim, use as model name
2. Fallback: construct from Brand Display + Model Display with StartsWith dedup
   - If model already starts with brand name (case-insensitive), use model as-is
   - Otherwise prepend brand: `"$brandName $rawModelDisplay"`
3. Log normalization when GroupManifest differs from raw Model/Display

Also updated `Save-DellDriversTask` model matching to check:
- `Model/Display` text (existing behavior)
- `GroupManifest/Display` text with "PDK Catalog for" prefix stripped
- Brand+Model assembly with StartsWith dedup

**Commit:** `4ceaec3`

### Task 2: Build-time SystemID/MachineType Extraction in Update-DriverMappingJson

Added `Get-HPSystemIdFromPlatformList` function with 3-tier matching:
1. **Exact**: Case-insensitive string equality on ProductName
2. **Alphanumeric-stripped**: Both strings reduced to `[A-Za-z0-9]` for fuzzy match
3. **Contains**: Either string contains the other (case-insensitive)

Enhanced `Update-DriverMappingJson` with vendor-specific identifier extraction:
- **Dell**: Regex `\(([^)]+)\)\s*$` extracts parenthesized suffix as SystemId
- **HP**: PlatformList.xml lookup via `Get-HPSystemIdFromPlatformList` with per-call hashtable cache (built once on first HP entry, reused for all subsequent HP entries)
- **Lenovo**: Same regex extracts parenthesized suffix as MachineType
- All identifiers normalized to `.Trim().ToUpperInvariant()`

**DriverMapping.json schema update:**
- Existing: `{ Manufacturer, Model, DriverPath }`
- New: `{ Manufacturer, Model, DriverPath, SystemId?, MachineType? }`
- `SystemId` present for Dell/HP entries (or omitted if extraction failed)
- `MachineType` present for Lenovo entries (or omitted if extraction failed)

**Error handling:** All extraction failures are non-throwing - log warning + set field to `$null`. Build never halts over a missing identifier.

**Commit:** `0228d19`

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

| ID | Decision | Rationale |
|----|----------|-----------|
| 39-01-01 | ReadSubtree() DOM approach for Get-DellDriversModelList | Reliable child element access for GroupManifest/Display, matches proven Save-DellDriversTask pattern |
| 39-01-02 | HP PlatformList.xml cache built inline on first HP entry | Per-call hashtable cache avoids repeat XML parsing across HP entries in same batch |
| 39-01-03 | Extract Get-HPSystemIdFromPlatformList as named exported function | Enables direct test access and reuse outside Update-DriverMappingJson |
| 39-01-04 | Save-DellDriversTask checks GroupManifest, Model/Display, and Brand+Model assembly | Models listed via GroupManifest normalization must be findable when downloading drivers |

## Verification Results

| Check | Result |
|-------|--------|
| Dell module imports | PASS |
| FFU.Common.Drivers module imports | PASS |
| GroupManifest handling in Get-DellDriversModelList | PASS |
| SystemId extraction in Update-DriverMappingJson | PASS |
| Get-HPSystemIdFromPlatformList exists and exported | PASS |
| PSScriptAnalyzer (errors) | PASS - no errors |

## Files Modified

| File | Changes |
|------|---------|
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.Dell.psm1` | Refactored model list extraction to ReadSubtree() with GroupManifest Display CDATA; updated Save-DellDriversTask model matching |
| `FFUDevelopment/FFU.Common/FFU.Common.Drivers.psm1` | Added Get-HPSystemIdFromPlatformList function; enhanced Update-DriverMappingJson with SystemId/MachineType extraction; updated exports |

## Next Phase Readiness

Phase 41 (Driver Matching) can consume the new `SystemId` and `MachineType` fields from DriverMapping.json entries for precise driver matching at deploy-time. The non-throwing pattern ensures graceful degradation to model-name-only matching when identifiers are unavailable.
