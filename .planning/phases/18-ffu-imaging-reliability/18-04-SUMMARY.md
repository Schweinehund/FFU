---
phase: 18-ffu-imaging-reliability
plan: 04
subsystem: imaging
tags: [ffu-capture, vhdx-preservation, cleanup-registration, pre-validation, reliability]

# Dependency graph
requires:
  - phase: 18-01
    provides: Test-DiskSpaceForOperation for space validation with safety margin
provides:
  - Test-FFUCaptureReadiness function for pre-capture validation
  - Invoke-SafeFFUCapture function with cleanup registration and VHDX integrity verification
  - 21 Pester tests for REL-IMG-03
affects: [ffu-capture, vhdx-recovery, build-reliability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Pre-capture validation pattern (validate VHDX state, space, output path before capture)
    - Cleanup registration pattern (Register-CleanupAction for partial FFU on failure)
    - VHDX integrity verification (Get-VHD after failure to confirm retry is safe)
    - 100% space margin for dynamic VHDX (worst case: FFU can be as large as max size)

key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1
    - Tests/Unit/FFU.Imaging.Reliability.Tests.ps1
    - FFUDevelopment/version.json

key-decisions:
  - "100% space margin for dynamic VHDX - FFU can be as large as max size"
  - "VHDX integrity verified via Get-VHD after capture failure"
  - "Partial FFU cleanup registered immediately on capture start"
  - "Readiness check returns structured result with FailureReason and Remediation"

patterns-established:
  - "Pre-validate VHDX not attached before FFU capture"
  - "Register cleanup for partial files immediately when starting long operations"
  - "Verify source integrity after failure to confirm retry is safe"

# Metrics
duration: 6min
completed: 2026-01-24
---

# Phase 18 Plan 04: FFU Capture Recovery Summary

**Safe FFU capture with VHDX preservation on failure - Test-FFUCaptureReadiness and Invoke-SafeFFUCapture with cleanup registration and integrity verification**

## Performance

- **Duration:** 6 min
- **Started:** 2026-01-24T02:43:29Z
- **Completed:** 2026-01-24T02:49:30Z
- **Tasks:** 3
- **Files modified:** 4 (0 created, 4 modified)

## Accomplishments

- Created Test-FFUCaptureReadiness function for pre-capture validation
- Validates: VHDX exists, VHDX not attached, sufficient disk space, output path writable
- Returns structured result with Ready status, FailureReason, Message, Remediation
- Created Invoke-SafeFFUCapture wrapper with cleanup registration
- Partial FFU automatically deleted on capture failure via Register-CleanupAction
- VHDX integrity verified after failure using Get-VHD to confirm retry is safe
- Uses Test-DiskSpaceForOperation with 100% margin (dynamic VHDX worst case)
- 21 Pester tests for capture readiness and safety (121 total REL-IMG tests)
- FFU.Imaging updated to v1.2.0, main version v1.8.22

## Task Commits

Each task was committed atomically:

1. **Task 1-2: Add Test-FFUCaptureReadiness and Invoke-SafeFFUCapture** - `1e0f940` (feat)
   - Test-FFUCaptureReadiness validates VHDX state, space, output path
   - Invoke-SafeFFUCapture registers cleanup for partial FFU
   - VHDX integrity verified after capture failure
2. **Task 3: Add REL-IMG-03 Pester tests and update version** - `f9ab994` (test)
   - 21 tests for capture readiness and safety
   - FFU.Imaging v1.2.0, main version v1.8.22

## Functions Added

### Test-FFUCaptureReadiness

Pre-capture validation that ensures all prerequisites are met.

```powershell
$result = Test-FFUCaptureReadiness -VHDXPath 'C:\VM\disk.vhdx' -OutputFFUPath 'D:\FFU\output.ffu'
if (-not $result.Ready) {
    Write-Error "$($result.Message)`nRemediation: $($result.Remediation)"
}
```

**Parameters:**
- VHDXPath: Path to source VHDX file
- OutputFFUPath: Path for FFU output
- SpaceMarginPercent: Space margin (default 100% for dynamic VHDX)

**Output:**
- Ready: Boolean
- FailureReason: VHDXNotFound, VHDXAttached, InsufficientSpace, OutputPathNotWritable
- Message: Human-readable status
- Remediation: Actionable guidance
- SourceSizeGB, AvailableSpaceGB (when ready)

### Invoke-SafeFFUCapture

FFU capture wrapper with cleanup registration and VHDX integrity verification.

```powershell
$result = Invoke-SafeFFUCapture -VHDXPath 'C:\VM\disk.vhdx' -OutputFFUPath 'D:\FFU\output.ffu' `
    -DandISetEnv 'C:\ADK\env.bat' -PhysicalDriveNumber 2
if ($result.Success) {
    Write-Host "FFU created: $($result.FFUPath) ($($result.SizeGB) GB)"
}
```

**Parameters:**
- VHDXPath: Source VHDX for integrity verification
- OutputFFUPath: FFU output path
- DandISetEnv: Path to ADK environment setup script
- PhysicalDriveNumber: Mounted VHDX physical drive number
- FFUName, FFUDescription: FFU metadata
- SkipReadinessCheck: Skip pre-capture validation

**Output:**
- Success: Boolean
- FFUPath: Path to created FFU
- SizeBytes, SizeGB: FFU file size

## Files Modified

- `FFU.Imaging.psm1` - Added Test-FFUCaptureReadiness and Invoke-SafeFFUCapture in REL-IMG-03 region
- `FFU.Imaging.psd1` - Version 1.2.0, FunctionsToExport, ReleaseNotes
- `FFU.Imaging.Reliability.Tests.ps1` - Added 21 REL-IMG-03 tests (121 total)
- `version.json` - Main version 1.8.22, FFU.Imaging v1.2.0, updated description

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| 100% space margin default | Dynamic VHDX FFU can be as large as max size |
| VHDX integrity via Get-VHD | Simple check that confirms VHDX is accessible for retry |
| Cleanup registered immediately | Ensures partial FFU always cleaned up on failure |
| Structured result with FailureReason | Enables programmatic error handling by callers |

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- FFU capture recovery ready for integration into New-FFU function
- Test-FFUCaptureReadiness can be called before capture to validate prerequisites
- Invoke-SafeFFUCapture provides safety wrapper for DISM capture operations
- Ready for next plan in Phase 18
- All success criteria met:
  - [x] Test-FFUCaptureReadiness validates VHDX exists, not attached, sufficient space, writable output
  - [x] Invoke-SafeFFUCapture registers cleanup for partial FFU file
  - [x] VHDX integrity verified after capture failure
  - [x] Readiness check uses Test-DiskSpaceForOperation with 100% margin
  - [x] 15+ Pester tests pass for REL-IMG-03 (21 tests)
  - [x] FFU.Imaging version bumped to 1.2.0
  - [x] Changes committed to git

---
*Phase: 18-ffu-imaging-reliability*
*Completed: 2026-01-24*
