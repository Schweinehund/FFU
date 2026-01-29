---
phase: 38-subst-drive-mapping
plan: 01
subsystem: driver-injection
status: complete
tags: [drivers, long-paths, subst, inf-parsing, win32-api]

requires:
  - phase-37: Winget app ordering and dependencies implemented
  - FFU.Core: Base module with WriteLog and error handling
  - FFU.Drivers: OEM driver module foundation

provides:
  - SUBST helper functions: Get-AvailableDriveLetter, New-DriverSubstMapping, Remove-DriverSubstMapping
  - Auto-growing INF buffer: Handles large SourceDisksFiles sections (1KB-64KB)
  - Copy-Drivers improvements: GUID normalization, -LiteralPath, long-path prefix
  - Unicode DllImport: CharSet.Unicode + SetLastError for GetPrivateProfileString/Section

affects:
  - phase-38-02: Will use SUBST helpers for DISM injection loop
  - FFU.Drivers: Enhanced Copy-Drivers reliability
  - BuildFFUVM.ps1: All INF parsing operations now Unicode-aware

tech-stack:
  added:
    - Windows SUBST command: Virtual drive mapping via cmd.exe
    - Win32 GetPrivateProfileString: Unicode charset with auto-growing buffer
  patterns:
    - SUBST drive mapping: Defensive pre-removal, non-blocking cleanup
    - Auto-growing buffer: Start 1KB, double to 64KB max
    - Long-path prefix: \\?\ for Win32 API, NOT for PowerShell cmdlets

key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1: +194 new SUBST functions, Copy-Drivers improvements
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psd1: v1.4.0 -> v1.5.0
    - FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1: Auto-growing buffer in Get-PrivateProfileString
    - FFUDevelopment/Modules/FFU.Core/FFU.Core.psd1: v1.0.23 -> v1.0.24
    - FFUDevelopment/BuildFFUVM.ps1: DllImport with CharSet.Unicode + SetLastError

decisions:
  - decision: Use cmd.exe for SUBST operations (no native PowerShell cmdlet)
    rationale: Windows SUBST is a built-in OS feature, no third-party dependencies
    impact: All SUBST operations call cmd.exe with proper argument escaping
  - decision: Auto-growing buffer starts at 1KB and doubles to 64KB max
    rationale: Balance memory efficiency with large INF support (SourceDisksFiles can be huge)
    impact: Prevents truncation without excessive memory allocation
  - decision: Use \\?\ prefix ONLY for Win32 API calls, NOT PowerShell cmdlets
    rationale: PowerShell cmdlets handle long paths differently, \\?\ prefix breaks them
    impact: $longInfFullName for Get-PrivateProfileString/Section, $infFullName for Copy-Item
  - decision: GUID normalization strips trailing ; comments and extracts token
    rationale: INF files can have ClassGUID={...};comment format that breaks exact matching
    impact: Reliable GUID filtering regardless of INF comment style
  - decision: Replace all Copy-Item -Path with -LiteralPath
    rationale: Prevents wildcard expansion on paths with brackets [, ], *, ?
    impact: Reliable file copy for drivers with special characters in paths
  - decision: SUBST functions return $null with WARNING on failure (non-throwing)
    rationale: Consistent with error handling pattern, allows caller to decide severity
    impact: Caller must check for $null, failures are logged but don't halt execution
  - decision: Pre-add Invoke-DismDriverInjectionWithSubstLoop to exports
    rationale: PowerShell silently ignores export of non-existent functions
    impact: Plan 02 can implement function without touching Export-ModuleMember line

metrics:
  duration: "6.3 minutes"
  tasks_completed: 2
  files_modified: 5
  lines_added: 570
  commits: 2
  tests_run: 107
  tests_passed: 102
  tests_failed: 5

completed: 2026-01-29
---

# Phase 38 Plan 01: SUBST Helpers and INF Parsing Summary

**One-liner:** SUBST drive mapping helpers with auto-growing INF buffer (1KB-64KB) and Copy-Drivers enhancements

## What Was Delivered

### SUBST Helper Functions (FFU.Drivers v1.5.0)

**Get-AvailableDriveLetter**
- Scans drive letters Z->A (reverse alphabetical)
- Returns first unused letter or $null if all 26 in use
- No parameters, simple utility function
- Output: `[char]` drive letter

**New-DriverSubstMapping**
- Creates SUBST virtual drive mapping for long driver paths
- Defensive pre-removal of existing mapping
- Path escaping for cmd.exe (double quotes)
- Returns PSCustomObject with DriveLetter, DriveName, DrivePath
- Non-throwing: returns $null with WARNING on failure
- Parameter: `[string]$SourcePath`

**Remove-DriverSubstMapping**
- Removes SUBST mapping with non-blocking error handling
- Logs WARNING on failure, never throws
- Safe to call even if mapping doesn't exist
- Parameter: `[string]$DriveLetter`

### Auto-Growing INF Buffer (FFU.Core v1.0.24)

**Get-PrivateProfileString Enhancement**
- Replaced fixed 1KB buffer with auto-growing buffer
- Start: 1024 bytes
- Growth: Double buffer size on overflow
- Max: 65536 bytes (64KB)
- Loop exit: charsCopied < capacity-1 OR bufferSize >= maxBufferSize
- Prevents truncation of large SourceDisksFiles sections

**Why This Matters**
- INF files with hundreds of driver files can exceed 1KB
- Old implementation would silently truncate
- New implementation handles up to 64KB sections
- Critical for OEM driver packages with extensive file lists

### Copy-Drivers Improvements (FFU.Drivers v1.5.0)

**Long-Path Prefix**
- Added `$longInfFullName = "\\?\$infFullName"` for Win32 API calls
- Get-PrivateProfileString: uses $longInfFullName
- Get-PrivateProfileSection: uses $longInfFullName
- Copy-Item: uses $infFullName (PowerShell handles long paths differently)
- Split-Path/Join-Path: use $infFullName (no \\?\ prefix)

**GUID Normalization**
- Strips trailing `;` comments from ClassGUID values
- Regex extraction: `\{[0-9A-Fa-f\-]{36}\}`
- Handles format: `{GUID};comment text`
- Enables reliable filtering regardless of INF comment style

**LiteralPath Usage**
- Replaced ALL 6 `Copy-Item -Path` with `Copy-Item -LiteralPath`
- Locations:
  1. INF file copy
  2. Catalog file copy
  3. SourceDisksFiles universal (no comma)
  4. SourceDisksFiles universal (with subdirectory)
  5. SourceDisksFiles arch-specific (no comma)
  6. SourceDisksFiles arch-specific (with subdirectory)
- Prevents wildcard expansion on `[`, `]`, `*`, `?` characters

### DllImport Enhancement (BuildFFUVM.ps1)

**GetPrivateProfileString**
- Before: `[DllImport("kernel32.dll")]`
- After: `[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]`

**GetPrivateProfileSection**
- Before: `[DllImport("kernel32.dll", CharSet = CharSet.Auto)]`
- After: `[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]`

**Impact**
- Explicit Unicode charset (no Auto guessing)
- SetLastError enables detailed error diagnostics
- Consistent with Windows INI file Unicode standard

## Deviations from Plan

None - plan executed exactly as written.

## Technical Decisions

### 1. SUBST Command Approach
**Decision:** Use `cmd.exe /c subst` for all SUBST operations

**Rationale:**
- Windows has no native PowerShell cmdlet for SUBST
- SUBST is built-in OS feature (no dependencies)
- cmd.exe provides consistent cross-version behavior

**Implementation:**
- Defensive pre-removal: `cmd.exe /c subst $driveName /d 2>&1 | Out-Null`
- Create mapping: `cmd.exe /c subst $driveName "$escapedPath"`
- Remove mapping: `cmd.exe /c subst $driveName /d 2>&1 | Out-Null`
- Path escaping: `$escapedPath = $resolvedPath -replace '"', '""'`

### 2. Auto-Growing Buffer Strategy
**Decision:** Start at 1KB, double to 64KB max

**Rationale:**
- Most INF sections fit in 1KB (single allocation)
- Large SourceDisksFiles sections can be 10KB+ (need growth)
- 64KB is sufficient for all known OEM driver packages
- Doubling is efficient (log2 iterations: max 6 for 1KB->64KB)

**Exit Conditions:**
- Success: `charsCopied < capacity-1` (buffer was large enough)
- Max size: `bufferSize >= maxBufferSize` (64KB limit reached)

### 3. Long-Path Prefix Usage
**Decision:** Use `\\?\` ONLY for Win32 API, NOT PowerShell cmdlets

**Rationale:**
- Win32 GetPrivateProfileString/Section: Require long-path prefix for paths >260 chars
- PowerShell Copy-Item: Handles long paths natively, \\?\ breaks relative paths
- Split-Path/Join-Path: Fail with \\?\ prefix

**Implementation Pattern:**
```powershell
$infFullName = $infFiles[$i].FullName
$longInfFullName = "\\?\$infFullName"   # For Win32 API

# Win32 API calls
Get-PrivateProfileString -FileName $longInfFullName ...
Get-PrivateProfileSection -FileName $longInfFullName ...

# PowerShell cmdlets
Copy-Item -LiteralPath $infFullName ...
Split-Path -Path $infFullName
```

### 4. GUID Normalization
**Decision:** Strip `;` comments and extract GUID token via regex

**Rationale:**
- INF files use format: `ClassGUID={GUID};optional comment`
- Direct string comparison fails when comment is present
- Comment content varies by driver package
- GUID token is always `{36-char-hex-with-dashes}`

**Algorithm:**
1. Split on `;` to remove comment
2. Trim whitespace
3. Regex match `\{[0-9A-Fa-f\-]{36}\}` to extract GUID
4. Compare extracted GUID against filter list

### 5. LiteralPath for All Copy Operations
**Decision:** Use `-LiteralPath` instead of `-Path` for all Copy-Item calls

**Rationale:**
- Driver file paths can contain `[`, `]` characters (array syntax in PowerShell)
- `-Path` interprets these as wildcards, causing copy failures
- `-LiteralPath` treats paths as literal strings (no wildcard expansion)
- Example problematic path: `C:\Drivers\[Network]\driver.sys`

**Impact:**
- All 6 Copy-Item calls in Copy-Drivers now use `-LiteralPath`
- No functional change for normal paths
- Fixes edge cases with special characters

## Next Phase Readiness

**Phase 38-02 Dependencies Met:**
- ✅ SUBST helper functions available
- ✅ Get-AvailableDriveLetter: Find unused drive letters
- ✅ New-DriverSubstMapping: Create mappings with error handling
- ✅ Remove-DriverSubstMapping: Clean up mappings safely
- ✅ Invoke-DismDriverInjectionWithSubstLoop: Pre-exported (will be implemented in 38-02)

**No Blockers**
- All functions export correctly
- Module version bumps complete
- No breaking changes to existing code
- Pester tests confirm no regressions (102/107 passing, 5 pre-existing failures)

## Testing Summary

**FFU.Drivers Module Tests**
- Total: 107 tests
- Passed: 102 ✅
- Failed: 5 (pre-existing test issues, not related to changes)
- Failures: ThreadJob logging pattern checks in internal functions

**Verification Checks**
- ✅ FFU.Drivers module imports cleanly
- ✅ FFU.Core module imports cleanly
- ✅ New functions exported: Get-AvailableDriveLetter, New-DriverSubstMapping, Remove-DriverSubstMapping
- ✅ AST check confirms auto-growing buffer: `maxBufferSize` keyword present
- ✅ Parameters verified: New-DriverSubstMapping has SourcePath, Remove-DriverSubstMapping has DriveLetter
- ✅ No PSScriptAnalyzer errors

## Commits

1. **2d2f12b** - `feat(38-01): add SUBST helper functions and Unicode DllImport`
   - Added 3 SUBST helper functions to FFU.Drivers.psm1
   - Updated Export-ModuleMember and FunctionsToExport
   - FFU.Drivers.psd1 version: 1.4.0 -> 1.5.0
   - BuildFFUVM.ps1 DllImport: Added CharSet.Unicode + SetLastError

2. **5dec5f9** - `feat(38-01): auto-growing INF buffer and Copy-Drivers improvements`
   - Get-PrivateProfileString: Auto-growing buffer 1KB-64KB
   - Copy-Drivers: \\?\ long-path prefix for Win32 API calls
   - Copy-Drivers: GUID normalization with comment stripping
   - Copy-Drivers: All 6 Copy-Item calls use -LiteralPath
   - FFU.Core.psd1 version: 1.0.23 -> 1.0.24

## Metrics

- **Execution time:** 6.3 minutes
- **Files modified:** 5
- **Lines added:** ~570
- **Functions added:** 3 (Get-AvailableDriveLetter, New-DriverSubstMapping, Remove-DriverSubstMapping)
- **Module versions bumped:** 2 (FFU.Drivers 1.5.0, FFU.Core 1.0.24)
- **Copy-Item calls fixed:** 6 (-Path -> -LiteralPath)
- **Tests run:** 107
- **Tests passed:** 102 (95% pass rate)

## Known Limitations

**SUBST Drive Letter Availability**
- Only 26 letters available (A-Z)
- If all letters in use, New-DriverSubstMapping returns $null
- Caller must handle null case (fallback to original path or fail)
- Unlikely scenario: typical systems use 3-5 drive letters

**64KB Buffer Maximum**
- Auto-growing buffer caps at 64KB
- Extremely large INF sections (>64KB) will still truncate
- No known OEM driver packages exceed this limit
- Can be increased if needed (update $maxBufferSize)

**SUBST Mapping Persistence**
- SUBST mappings are per-session (not persistent across reboots)
- Cleanup required on build completion or error
- Plan 02 will implement proper cleanup in DISM injection loop

## References

- **Plan:** `.planning/phases/38-subst-drive-mapping/38-01-PLAN.md`
- **Context:** `.planning/phases/38-subst-drive-mapping/38-CONTEXT.md`
- **Research:** `.planning/phases/38-subst-drive-mapping/38-RESEARCH.md`
- **Upstream issue:** PATH-01 (Long path reliability for driver injection)
