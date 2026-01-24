---
phase: 18
plan: 03
subsystem: FFU.Imaging
tags: [reliability, retry, transient-errors, exponential-backoff, dism, mount]
requires:
  - phase-18 plan 01 (disk space pre-validation)
  - phase-17 plan 03 (Test-IsTransientVMError pattern)
provides:
  - Test-IsTransientImagingError function
  - Invoke-ImagingOperationWithRetry wrapper
affects:
  - FFU mount operations in New-FFU
  - WIM mount operations
  - Any future imaging operations needing retry
tech-stack:
  added: []
  patterns:
    - Transient error detection via pattern matching
    - Permanent error patterns take precedence over transient
    - Exponential backoff with jitter
    - HResult code classification
    - DISM cleanup integration for mount operations
key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1
    - Tests/Unit/FFU.Imaging.Reliability.Tests.ps1
    - FFUDevelopment/version.json
decisions:
  - "Permanent patterns checked FIRST (takes precedence over transient)"
  - "Unknown errors default to NOT transient (fail fast principle)"
  - "Base delay of 3s for imaging operations (slightly higher than VM ops)"
  - "MaxRetries default 3, matching VM and hypervisor retry patterns"
  - "DISM cleanup optional via RunDismCleanupOnRetry switch"
  - "HResult codes supported for reliable error classification"
  - "ERROR_DISK_FULL is NOT transient - user must free space"
metrics:
  duration: "15 minutes"
  completed: "2026-01-24"
---

# Phase 18 Plan 03: WIM Mount Resilience Summary

Transient error retry for imaging operations with exponential backoff and DISM cleanup.

## One-Liner

Test-IsTransientImagingError classifies errors as transient/permanent; Invoke-ImagingOperationWithRetry wraps operations with exponential backoff and optional DISM cleanup.

## What Was Built

### Test-IsTransientImagingError Function

Classifies imaging operation errors to determine if retry is appropriate:

| Error Category | Pattern Examples | Classification | Rationale |
|----------------|------------------|----------------|-----------|
| Sharing violation | sharing violation | Transient | File in use by another process temporarily |
| File in use | file.*in use, file.*locked | Transient | Another process temporarily holding file |
| Drive in use | drive.*in use | Transient | Disk operation in progress |
| Device not ready | device is not ready | Transient | Disk initialization in progress |
| Device disconnected | device is not connected | Transient | Mount lost, can reconnect |
| Path mounted | path is already mounted | Transient | Stale mount point, cleanup needed |
| RPC issues | rpc.*unavailable | Transient | Service temporarily unavailable |
| Network timeout | network.*timeout | Transient | Network glitch |
| Directory not empty | directory is not empty | Transient | Mount cleanup needed |
| Not found | not found, does not exist | Permanent | Missing resource |
| Access denied | access is denied | Permanent | Permission issue |
| Invalid parameter | invalid parameter/argument | Permanent | Bad input |
| Registry corrupt | registry.*corrupt | Permanent | Error 1009, data corruption |
| Element not found | element not found | Permanent | Error 1168 |
| Not valid disk | not a valid disk | Permanent | Disk format issue |

**HResult Code Support:**

| HResult | Error | Classification |
|---------|-------|----------------|
| 0x80070020 | ERROR_SHARING_VIOLATION | Transient |
| 0x8007048F | ERROR_INVALID_ADDRESS | Transient |
| 0x80070005 | ERROR_ACCESS_DENIED | Transient (for mounts) |
| 0x80070070 | ERROR_DISK_FULL | NOT transient |

### Invoke-ImagingOperationWithRetry Function

Wraps imaging operations with automatic retry for transient errors:

```powershell
Invoke-ImagingOperationWithRetry -OperationName 'Mount Windows Image' -ScriptBlock {
    Mount-WindowsImage -ImagePath $ffuFile -Index 1 -Path $mountPath -ErrorAction Stop
} -RunDismCleanupOnRetry
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ScriptBlock | scriptblock | (required) | Operation to execute |
| OperationName | string | 'imaging operation' | Name for logging |
| MaxRetries | int | 3 | Maximum retry attempts |
| BaseDelaySeconds | int | 3 | Base delay for exponential backoff |
| RunDismCleanupOnRetry | switch | $false | Run DISM /Cleanup-Mountpoints before retry |

**Behavior:**

1. Execute ScriptBlock
2. On error, check if transient via Test-IsTransientImagingError
3. Permanent error: throw immediately (no retry)
4. Transient error: calculate delay with exponential backoff + jitter
5. If RunDismCleanupOnRetry: run `dism.exe /Cleanup-Mountpoints`
6. Retry up to MaxRetries times
7. Build attempt history for debugging on final failure

**Delay Calculation:**

```
delay = BaseDelaySeconds * (2 ^ (attempt - 1)) + jitter
jitter = random(0, baseDelay * 0.3)
```

| Attempt | Base Delay | With Jitter (max) |
|---------|------------|-------------------|
| 1 | 3s | 3.9s |
| 2 | 6s | 7.8s |
| 3 | 12s | 15.6s |

## Test Coverage

41 Pester tests for REL-IMG-04:

**Test-IsTransientImagingError Classification (27 tests):**
- Transient patterns: sharing violation, file in use, file locked, drive in use, device not ready, path already mounted, RPC unavailable, directory not empty, cannot access, device not connected
- Permanent patterns: not found, does not exist, access is denied, invalid parameter, invalid argument, registry corrupt, element not found, not a valid disk
- HResult: 0x80070020 (sharing violation)
- Edge cases: empty string, unknown errors, case insensitivity, permanent precedence

**Invoke-ImagingOperationWithRetry Function (14 tests):**
- Function export and parameter verification
- Successful execution returns result
- Complex object return support
- Permanent errors fail immediately without retry
- Original error message preserved
- Custom MaxRetries and BaseDelaySeconds acceptance

## Verification Results

```
Tests Passed: 121, Failed: 0, Skipped: 0
```

All verification criteria met:
- [x] Test-IsTransientImagingError function exists and is exported
- [x] Sharing violation and drive in use errors classified as transient
- [x] File not found and invalid parameter errors classified as permanent
- [x] Invoke-ImagingOperationWithRetry function exists and is exported
- [x] Retry wrapper uses exponential backoff with jitter
- [x] Permanent errors fail immediately without retry
- [x] RunDismCleanupOnRetry parameter triggers dism.exe /Cleanup-Mountpoints
- [x] Pester tests pass for all REL-IMG-04 scenarios

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 1e0f940 | feat | Add transient error retry functions (included with REL-IMG-03) |

Note: The REL-IMG-04 functions were committed together with REL-IMG-03 in a previous execution.

## Version Updates

| Component | From | To |
|-----------|------|-----|
| FFU Builder | 1.8.21 | 1.8.22 |
| FFU.Imaging | 1.1.9 | 1.2.0 |

## REL-IMG-04 Requirement Satisfied

- Sharing violations trigger automatic retry with backoff
- File locked/in use errors retry up to 3 times before failing
- Device not ready errors are retried with exponential backoff
- Permanent errors (not found, invalid parameter) fail immediately without retry
- Optional DISM cleanup runs before each retry attempt
- HResult codes provide reliable error classification

## Deviations from Plan

None - plan executed exactly as written. Functions were implemented following the pattern from FFU.VM module's Test-IsTransientVMError and Invoke-VMOperationWithRetry.

## Next Steps

Plan 18-04: Diskpart Error Recovery (REL-IMG-05)
