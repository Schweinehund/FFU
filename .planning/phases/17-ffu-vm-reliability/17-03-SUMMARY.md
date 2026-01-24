---
phase: 17
plan: 03
subsystem: FFU.VM
tags: [reliability, retry, transient-errors, exponential-backoff]
requires:
  - phase-17 plan 01 (VM creation diagnostics)
  - phase-16 plan 04 (Invoke-WithHypervisorRetry pattern)
provides:
  - Test-IsTransientVMError function
  - Invoke-VMOperationWithRetry wrapper
affects:
  - phase-17 plans 04 (checkpoint disk space validation)
  - Any code using VM disk operations
tech-stack:
  added: []
  patterns:
    - Transient error detection via pattern matching
    - Exponential backoff with jitter
    - Integration with hypervisor service retry
key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1
    - FFUDevelopment/Modules/FFU.VM/FFU.VM.psd1
    - Tests/Unit/FFU.VM.Reliability.Tests.ps1
    - FFUDevelopment/version.json
decisions:
  - "Transient patterns checked after permanent patterns (permanent takes precedence)"
  - "Unknown errors default to NOT transient (fail fast principle)"
  - "Base delay of 2s for VM operations (lower than hypervisor service 5s)"
  - "MaxRetries default 3, matching hypervisor retry pattern"
metrics:
  duration: "12 minutes"
  completed: "2026-01-24"
---

# Phase 17 Plan 03: Transient Error Retry Summary

Automatic retry logic for VM operations that handles transient failures with exponential backoff.

## One-Liner

Test-IsTransientVMError classifies errors as transient/permanent; Invoke-VMOperationWithRetry wraps operations with exponential backoff.

## What Was Built

### Test-IsTransientVMError Function

Classifies VM operation errors to determine if retry is appropriate:

| Error Category | Pattern Examples | Classification | Rationale |
|----------------|------------------|----------------|-----------|
| Disk busy | disk.*busy | Transient | Temporary resource contention |
| File locked | file.*locked, file.*in use | Transient | Another process temporarily holding file |
| Network timeout | network.*timeout, operation timed out | Transient | Network glitch, service restart |
| RPC issues | rpc.*unavailable, rpc.*server.*busy | Transient | Service temporarily unavailable |
| Sharing violation | sharing violation | Transient | File system contention |
| Device not ready | device is not ready | Transient | Disk initialization in progress |
| Already exists | already exists | Permanent | Logic error, not time-dependent |
| Not found | does not exist, not found | Permanent | Missing resource |
| Insufficient memory | insufficient memory, out of memory | Permanent | Resource constraint |
| Disk full | disk full, insufficient disk space | Permanent | Capacity limit |
| Invalid parameter | invalid parameter, invalid argument | Permanent | Bad input |
| Feature unavailable | hyper-v.*not enabled, not supported | Permanent | Missing capability |

### Invoke-VMOperationWithRetry Function

Wraps VM operations with automatic retry for transient errors:

```powershell
Invoke-VMOperationWithRetry -OperationName 'Dismount VHDX' -ScriptBlock {
    Dismount-VHD -Path $vhdxPath -ErrorAction Stop
}
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ScriptBlock | scriptblock | (required) | Operation to execute |
| OperationName | string | 'VM operation' | Name for logging |
| MaxRetries | int | 3 | Maximum retry attempts |
| BaseDelaySeconds | int | 2 | Base delay for exponential backoff |
| UseHypervisorRetry | switch | $false | Also check service errors |
| Provider | string | 'HyperV' | Hypervisor provider for service check |

**Behavior:**

1. Execute ScriptBlock
2. On error, check if transient via Test-IsTransientVMError
3. If UseHypervisorRetry, also check Test-IsServiceError from FFU.Hypervisor
4. Permanent error: throw immediately (no retry)
5. Transient error: calculate delay with exponential backoff + jitter
6. Retry up to MaxRetries times
7. Build attempt history for debugging on final failure

**Delay Calculation:**

```
delay = BaseDelaySeconds * (2 ^ (attempt - 1)) + jitter
jitter = random(0, baseDelay * 0.3)
```

| Attempt | Base Delay | With Jitter (max) |
|---------|------------|-------------------|
| 1 | 2s | 2.6s |
| 2 | 4s | 5.2s |
| 3 | 8s | 10.4s |

## Test Coverage

35 Pester tests for REL-VM-03:

**Test-IsTransientVMError Classification (19 tests):**
- Transient patterns: disk busy, file locked, file in use, network timeout, RPC unavailable, sharing violation, device not ready, operation timed out
- Permanent patterns: already exists, not found, insufficient memory, disk full, invalid parameter, out of memory, Hyper-V not enabled
- Edge cases: empty message, unknown errors, case insensitivity

**Invoke-VMOperationWithRetry Function (13 tests):**
- Function export and parameter verification
- Successful execution returns result
- Permanent errors fail immediately without retry
- Original error message preserved

**Module Export Verification (3 tests):**
- Function exported from FFU.VM
- ErrorMessage parameter exists
- Boolean return type

## Verification Results

```
Tests Passed: 77, Failed: 0, Skipped: 0
```

All verification criteria met:
- [x] Test-IsTransientVMError function exists and is exported
- [x] Disk busy/locked errors classified as transient
- [x] Already exists/not found errors classified as permanent
- [x] Invoke-VMOperationWithRetry function exists and is exported
- [x] Retry wrapper uses exponential backoff with jitter
- [x] Permanent errors fail immediately without retry
- [x] Pester tests pass for all REL-VM-03 scenarios

## Commits

| Hash | Type | Description |
|------|------|-------------|
| b8b3cf5 | feat | Add transient error detection and retry for VM operations |
| d7ba39e | test | Add Pester tests for transient error retry logic |

## Version Updates

| Component | From | To |
|-----------|------|-----|
| FFU Builder | 1.8.16 | 1.8.17 |
| FFU.VM | 1.0.9 | 1.0.11 |

## REL-VM-03 Requirement Satisfied

- Disk busy errors trigger automatic retry with backoff
- File locked errors retry up to 3 times before failing
- Network timeout errors are retried with exponential backoff
- Permanent errors (VM not found, invalid parameter) fail immediately without retry

## Deviations from Plan

None - plan executed exactly as written.

## Next Steps

Plan 17-04: Checkpoint Disk Space Validation (Test-CheckpointDiskSpace function)
