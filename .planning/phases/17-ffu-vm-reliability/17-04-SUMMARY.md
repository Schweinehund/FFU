---
phase: 17-ffu-vm-reliability
plan: 04
subsystem: vm
tags: [checkpoint, disk-space, validation, avhdx, orphan-cleanup, hyper-v, pre-flight]

# Dependency graph
requires:
  - phase: 17-ffu-vm-reliability
    provides: plan-01 VM creation diagnostics
provides:
  - Test-CheckpointDiskSpace function for disk space pre-validation
  - New-FFUVMCheckpoint wrapper with pre-validation and cleanup
  - Automatic orphaned AVHDX file cleanup on checkpoint failure
  - Structured error output with remediation guidance
  - 29 Pester tests for checkpoint disk space scenarios
affects: [checkpoint-operations, vm-lifecycle, disk-management]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Pre-validation pattern (validate resources before operation)
    - Structured result object (HasSufficientSpace, AvailableGB, RequiredGB, Message, Remediation)
    - Orphan cleanup pattern (track files before, compare after, cleanup new ones)
    - Disk space margin calculation (VHDX size * margin percentage)

key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1
    - FFUDevelopment/Modules/FFU.VM/FFU.VM.psd1
    - Tests/Unit/FFU.VM.Reliability.Tests.ps1
    - FFUDevelopment/version.json

key-decisions:
  - "Default margin is 100% (2x VHDX size) for worst-case scenario"
  - "Dynamic VHDX uses maximum size for calculation, not current size"
  - "Orphan detection compares AVHDX list before/after operation"
  - "Disk full error detected by 0x80070070 code or keyword matching"
  - "SkipDiskCheck parameter allows bypass when space is known"

patterns-established:
  - "Pre-validate disk space before disk-heavy operations"
  - "Use Test-CheckpointDiskSpace before Checkpoint-VM"
  - "Track file state before operation for cleanup purposes"
  - "Include remediation guidance in error messages"

# Metrics
duration: 8min
completed: 2026-01-24
---

# Phase 17 Plan 04: Checkpoint Disk Space Validation Summary

**Pre-validation of disk space for checkpoint operations with automatic orphan cleanup using Test-CheckpointDiskSpace and New-FFUVMCheckpoint**

## Performance

- **Duration:** 8 min
- **Started:** 2026-01-24T01:30:13Z
- **Completed:** 2026-01-24T01:38:13Z
- **Tasks:** 3
- **Files modified:** 4 (0 created, 4 modified)

## Accomplishments

- Created Test-CheckpointDiskSpace function for validating disk space before checkpoint operations
- Created New-FFUVMCheckpoint wrapper around Checkpoint-VM with pre-validation
- Automatic cleanup of orphaned AVHDX files when checkpoint fails
- Structured output object with HasSufficientSpace, AvailableGB, RequiredGB, Message, Remediation
- 29 Pester tests for checkpoint disk space validation (REL-VM-04)
- FFU.VM updated to v1.0.11, main version v1.8.18

## Task Commits

Each task was committed atomically:

1. **Task 1-2: Add checkpoint disk space validation functions** - `dba5f6d` (feat)
   - Test-CheckpointDiskSpace with ByVMName and ByPath parameter sets
   - New-FFUVMCheckpoint wrapper with pre-validation and orphan cleanup
2. **Task 3: Add REL-VM-04 Pester tests** - `5d06a98` (test)
   - 16 tests for Test-CheckpointDiskSpace
   - 7 tests for New-FFUVMCheckpoint
   - 6 tests for module code verification

## Functions Added

### Test-CheckpointDiskSpace

Validates disk space before checkpoint operation.

```powershell
$check = Test-CheckpointDiskSpace -VMName 'FFU-Build' -MarginPercent 50
if (-not $check.HasSufficientSpace) {
    throw $check.Message
}
```

**Parameters:**
- VMName: VM to check (ByVMName parameter set)
- VHDXPath: Direct path to VHDX (ByPath parameter set)
- MarginPercent: Space margin (default 100 = 2x)
- RequiredSpaceGB: Override calculated requirement

**Output:**
- HasSufficientSpace: Boolean
- AvailableGB: Available space
- RequiredGB: Required space
- Drive: Drive letter checked
- Message: Human-readable status
- Remediation: Fix guidance (when insufficient)

### New-FFUVMCheckpoint

Creates checkpoint with pre-validation and cleanup.

```powershell
New-FFUVMCheckpoint -VMName 'FFU-Build' -SnapshotName 'Before-Apps'
```

**Parameters:**
- VMName: VM to checkpoint (mandatory)
- SnapshotName: Checkpoint name (default: timestamp)
- MarginPercent: Space validation margin (default 100)
- SkipDiskCheck: Bypass validation

**Features:**
- Pre-validates disk space before operation
- Tracks AVHDX files before checkpoint
- Cleans up orphaned files on failure
- Enhanced error messages for disk full (0x80070070)

## Files Modified

- `FFU.VM.psm1` - Added Test-CheckpointDiskSpace and New-FFUVMCheckpoint functions
- `FFU.VM.psd1` - Version 1.0.11, FunctionsToExport, ReleaseNotes
- `FFU.VM.Reliability.Tests.ps1` - Added 29 REL-VM-04 tests
- `version.json` - Main version 1.8.18, FFU.VM description update

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Default 100% margin | Worst-case: checkpoint can grow to full VHDX size |
| Dynamic VHDX uses max size | Better to overestimate than fail mid-operation |
| ByVMName + ByPath parameter sets | Flexibility for different use cases |
| Orphan = files appearing during operation | Simple and reliable detection method |
| Disk full via error code or keywords | Covers different Hyper-V error formats |

## Error Handling

### Disk Full Detection
```
- 0x80070070 (ERROR_DISK_FULL)
- "disk full"
- "not enough.*space"
```

### Enhanced Error Messages
```
Checkpoint failed: Disk full. Available: 10.5 GB on C:\.
Free up space and retry, or move VM to a larger drive.
```

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- Checkpoint operations now validate disk space
- Failed checkpoints automatically clean up orphaned files
- Ready for next plan in Phase 17
- All success criteria met:
  - [x] Checkpoint creation validates disk space before starting
  - [x] Insufficient disk space produces actionable error message
  - [x] Orphaned AVHDX files are cleaned up after failed checkpoint
  - [x] Error message includes required vs available space
  - [x] Test-CheckpointDiskSpace function exported
  - [x] New-FFUVMCheckpoint function exported
  - [x] Tests validate disk space checking and checkpoint wrapper
  - [x] REL-VM-04 requirement satisfied

---
*Phase: 17-ffu-vm-reliability*
*Completed: 2026-01-24*
