---
phase: 20
plan: 02
subsystem: ffu-updates
tags: [updates, integrity, validation, reliability, msu, download]

dependency_graph:
  requires: ["20-01"]
  provides: ["Test-MSUIntegrity", "MSU download validation"]
  affects: ["FFU.Updates", "Save-KB"]

tech_stack:
  added: []
  patterns: ["SHA-256 hash validation", "structured result pattern", "automatic retry"]

key_files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1
    - FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psd1
    - Tests/Unit/FFU.Updates.Reliability.Tests.ps1

decisions:
  - decision: "Use internal helper function Invoke-ValidatedDownload in Save-KB"
    rationale: "Encapsulates download-validate-retry pattern, avoids code duplication"
    alternatives_considered: ["Inline validation at each download point"]

metrics:
  duration: "~15 minutes"
  completed: "2026-01-24"
---

# Phase 20 Plan 02: MSU Download Integrity Validation Summary

**REL-UPD-02: MSU Download Validation - SHA-256 integrity check with automatic re-download on corruption**

## One-liner

Test-MSUIntegrity function validates MSU/CAB file existence, size, and optional SHA-256 hash; Save-KB automatically re-downloads corrupted files (up to 2 retries).

## What Was Done

### Task 1: Test-MSUIntegrity Function
Added comprehensive MSU file validation function to FFU.Updates:
- File existence check (early return on missing)
- Empty file detection (0 bytes = corruption indicator)
- Minimum size validation (default 1MB threshold)
- Optional expected size validation
- Optional SHA-256 hash verification (Base64 format)
- Returns structured result: `{ Valid, FilePath, Errors, FileSize, ActualHash }`

**Key code pattern (from Get-ProductsCab):**
```powershell
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$fs = [System.IO.File]::OpenRead($FilePath)
$hashBytes = $sha256.ComputeHash($fs)
$actualHashB64 = [Convert]::ToBase64String($hashBytes)
```

### Task 2: Save-KB Integration
Integrated validation into Save-KB with automatic re-download:
- Added `MaxValidationRetries` parameter (default: 2)
- Created `Invoke-ValidatedDownload` internal helper function
- Applied to all download paths (x64, arm64, x86, architecture-agnostic)
- Deletes corrupted files before re-download
- Logs validation status with file size
- REL-UPD-02 comment markers throughout

### Task 3: Pester Tests
Added 29 tests covering REL-UPD-02:
- 16 tests for Test-MSUIntegrity function behavior
- 8 tests for Save-KB integration
- 5 tests for documentation compliance
- Updated module version checks

## Key Artifacts

| File | Change |
|------|--------|
| `FFU.Updates.psm1` | +Test-MSUIntegrity function, +Invoke-ValidatedDownload in Save-KB |
| `FFU.Updates.psd1` | v1.0.6, FunctionsToExport includes Test-MSUIntegrity |
| `FFU.Updates.Reliability.Tests.ps1` | +29 REL-UPD-02 tests |

## Verification Results

```
Tests Passed: 29, Failed: 0, Skipped: 0
Duration: 5.46s
```

All success criteria met:
- Test-MSUIntegrity validates file existence, size, and optional hash
- Save-KB validates downloads and re-downloads on failure (up to 2 retries)
- All REL-UPD-02 Pester tests pass

## Commits

| Hash | Message |
|------|---------|
| bd14760 | feat(20-02): integrate Test-MSUIntegrity into Save-KB with re-download |
| 4dcb858 | test(20-02): add REL-UPD-02 Pester tests for MSU integrity validation |

## Deviations from Plan

### Implementation Approach
**Task 2 deviation:** Instead of adding inline validation at each download point (as suggested in plan), implemented `Invoke-ValidatedDownload` helper function inside Save-KB.

- **Reason:** Reduces code duplication, encapsulates download-validate-retry pattern
- **Impact:** Cleaner code, single point of maintenance
- **Aligned with:** DRY principle

## Next Phase Readiness

No blockers. REL-UPD-02 completes the FFU.Updates reliability improvements:
- REL-UPD-01: Catalog query retry (complete)
- REL-UPD-02: MSU download validation (this plan)
- REL-UPD-03: Update application isolation (complete)

Phase 20 may be marked complete after this plan.
