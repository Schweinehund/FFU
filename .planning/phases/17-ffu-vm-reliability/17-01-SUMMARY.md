---
phase: 17
plan: 01
subsystem: FFU.VM
tags: [reliability, diagnostics, cleanup, VM-creation]
requires:
  - phase-16 (FFU.Hypervisor reliability)
provides:
  - Get-VMCreationDiagnostics function
  - Progressive cleanup registration in New-FFUVM
affects:
  - phase-17 plans 02-04 (orphan detection, async startup, graceful shutdown)
tech-stack:
  added: []
  patterns:
    - Error classification and remediation guidance
    - Progressive resource cleanup registration
key-files:
  created:
    - Tests/Unit/FFU.VM.Reliability.Tests.ps1
  modified:
    - FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1
    - FFUDevelopment/Modules/FFU.VM/FFU.VM.psd1
    - FFUDevelopment/version.json
decisions:
  - "Error classification uses pattern matching on common keywords"
  - "TPM errors classified as non-critical (IsCritical = false)"
  - "ResourcesCreated tracking based on failed step for cleanup guidance"
  - "Cleanup registration uses existing FFU.Core infrastructure"
metrics:
  duration: "9 minutes"
  completed: "2026-01-24"
---

# Phase 17 Plan 01: VM Creation Diagnostics Summary

VM creation failure analysis with actionable remediation guidance and progressive cleanup registration.

## One-Liner

Get-VMCreationDiagnostics provides classified error analysis with remediation; New-FFUVM registers cleanup at each step.

## What Was Built

### Get-VMCreationDiagnostics Function

New diagnostic function that analyzes VM creation failures and returns:

| Property | Type | Description |
|----------|------|-------------|
| ErrorType | string | Classified error (AlreadyExists, InsufficientResources, PathNotFound, AccessDenied, HypervisorNotAvailable, TPMConfiguration, DiskError, Unknown) |
| FailedStep | string | Which step failed (CreateVM, ConfigureProcessor, MountISO, ConfigureBoot, ConfigureTPM, StartVM) |
| OriginalError | string | Original exception message |
| Remediation | string | Actionable guidance for fixing the issue |
| IsCritical | bool | False for TPM errors, true for others |
| ResourcesCreated | array | Resources that may need cleanup based on failed step |

### Error Pattern Matching

| Error Pattern | ErrorType | Example Remediation |
|---------------|-----------|---------------------|
| "already exists" | AlreadyExists | Remove-VM -Name 'VMName' -Force |
| "insufficient memory" | InsufficientResources | Close applications or reduce VM memory |
| "cannot find path" | PathNotFound | Create directory or verify path |
| "access denied" | AccessDenied | Run as Administrator |
| "hyper-v not enabled" | HypervisorNotAvailable | Enable-WindowsOptionalFeature |
| "hgs", "guardian", "tpm" | TPMConfiguration | Non-critical, VM works without TPM |
| "vhdx", "disk in use" | DiskError | Check for other VMs using disk |

### New-FFUVM Cleanup Registration

Updated New-FFUVM to register cleanup actions progressively:

1. **After New-VM succeeds**: Register-VMCleanup called
2. **After New-HgsGuardian succeeds**: Register-CleanupAction for guardian + certificates
3. **On success**: Unregister cleanup handlers (VM now managed by caller)
4. **On failure**: Get-VMCreationDiagnostics provides classified error with remediation

### Step Tracking

Each operation sets `$currentStep` variable:
- CreateVM -> ConfigureProcessor -> MountISO -> ConfigureBoot -> ConfigureTPM -> StartVM

## Test Coverage

42 Pester tests covering:

- **Error Classification (11 tests)**: Each error type correctly identified
- **Remediation Content (6 tests)**: Guidance includes expected commands/instructions
- **ResourcesCreated (4 tests)**: Correct resources tracked per failed step
- **Output Properties (3 tests)**: All properties returned correctly
- **Module Exports (3 tests)**: Function exported with correct parameters
- **Edge Cases (3 tests)**: Case-insensitive matching, multiple keywords
- **Integration (4 tests)**: Cleanup functions available from FFU.Core
- **REL-VM-02 tests (8 tests)**: Additional tests for concurrent work

## Verification Results

```
Tests Passed: 42, Failed: 0, Skipped: 0
```

All verification criteria met:
- [x] Get-VMCreationDiagnostics function exists and is exported
- [x] New-FFUVM uses Register-CleanupAction for VM and HGS Guardian
- [x] New-FFUVM calls Get-VMCreationDiagnostics in catch block
- [x] Pester tests pass
- [x] Module imports without errors

## Commits

| Hash | Type | Description |
|------|------|-------------|
| b50de70 | feat | Add Get-VMCreationDiagnostics function |
| 35260f1 | feat | Update New-FFUVM with cleanup registration and diagnostics |
| 371ef9a | test | Add Pester tests for VM creation diagnostics |

## Version Updates

| Component | From | To |
|-----------|------|-----|
| FFU Builder | 1.8.15 | 1.8.16 |
| FFU.VM | 1.0.8 | 1.0.9 |

## REL-VM-01 Requirement Satisfied

- Failed VM creation logs the specific step that failed
- Cleanup runs for all resources created before the failure point
- Error message includes actionable guidance for common failures

## Deviations from Plan

None - plan executed exactly as written.

## Next Steps

Plan 17-02: Orphan Detection and Cleanup (Get-OrphanedVMResources function)
