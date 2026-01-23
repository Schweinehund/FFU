---
phase: 16-ffu-hypervisor-reliability
plan: 01
subsystem: hypervisor
tags: [reliability, remediation, provider-detection, error-handling]

# Dependency tracking
dependency-graph:
  requires:
    - "Phase 15 FFU.Core Reliability"
  provides:
    - "Provider detection with remediation guidance"
    - "ErrorCode classification for Hyper-V and VMware"
    - "Enhanced error messages for hypervisor unavailability"
  affects:
    - "16-02 (VM Lifecycle error handling)"
    - "16-03 (Disk operations error handling)"

# Tech stack
tech-stack:
  added: []
  patterns:
    - "ErrorCode classification pattern"
    - "Remediation array pattern"
    - "StringBuilder for multi-line error formatting"

# File tracking
key-files:
  created:
    - "Tests/Unit/FFU.Hypervisor.ProviderDetection.Tests.ps1"
  modified:
    - "FFUDevelopment/Modules/FFU.Hypervisor/Providers/HyperVProvider.ps1"
    - "FFUDevelopment/Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1"
    - "FFUDevelopment/Modules/FFU.Hypervisor/Public/Get-HypervisorProvider.ps1"
    - "FFUDevelopment/Modules/FFU.Hypervisor/Public/Test-HypervisorAvailable.ps1"
    - "FFUDevelopment/Modules/FFU.Hypervisor/FFU.Hypervisor.psd1"
    - "FFUDevelopment/version.json"

# Decisions made
decisions:
  - id: "error-code-prefix"
    description: "Use HYPERV_ and VMWARE_ prefixes for error codes"
    rationale: "Clear identification of which provider has the issue"
  - id: "remediation-array"
    description: "Return remediation as array, not string"
    rationale: "Multiple steps may be needed, easier to format"
  - id: "error-priority"
    description: "First error code found takes precedence"
    rationale: "Most significant issue should be addressed first"

# Metrics
metrics:
  completed: "2026-01-23"
  duration: "~30 minutes"
  tasks-completed: 3
  tests-added: 32
  tests-passing: 29
  tests-skipped: 3
---

# Phase 16 Plan 01: Provider Detection with Remediation Summary

**One-liner:** Enhanced provider detection with ErrorCode classification and actionable remediation steps for missing/disabled hypervisors.

## What Was Built

Added comprehensive remediation guidance to FFU.Hypervisor provider detection:

### Task 1: Provider GetAvailabilityDetails Enhancement

Enhanced `GetAvailabilityDetails()` on both providers to return actionable remediation:

**HyperVProvider:**
- `ErrorCode`: HYPERV_NOT_INSTALLED, HYPERV_SERVICE_STOPPED, HYPERV_MODULE_MISSING, HYPERV_FEATURE_DISABLED
- `Remediation`: Array of PowerShell commands (Enable-WindowsOptionalFeature, Start-Service, etc.)

**VMwareProvider:**
- `ErrorCode`: VMWARE_NOT_INSTALLED, VMWARE_PATH_INVALID, VMWARE_VMRUN_MISSING, VMWARE_VERSION_OLD
- `Remediation`: Array with download URLs and installation guidance

### Task 2: Enhanced Error Messages

Updated `Get-HypervisorProvider` and `Test-HypervisorAvailable`:

- Auto mode logs why each provider failed before checking next
- Error messages include both ErrorCode and Remediation steps
- Multi-line formatted errors for readability
- Helper functions: `Format-SingleProviderError`, `Format-ProviderUnavailableError`

Example error format:
```
No supported hypervisor available.

Hyper-V (HYPERV_SERVICE_STOPPED):
  - Hyper-V service is not running
  Remediation:
    Start-Service vmms

VMware (VMWARE_NOT_INSTALLED):
  - VMware Workstation Pro not found
  Remediation:
    Download from: https://www.vmware.com/products/workstation-pro.html
```

### Task 3: Provider Detection Tests

Created comprehensive Pester test file (434 lines, 32 tests):
- GetAvailabilityDetails returns Remediation and ErrorCode
- Error codes follow expected patterns (HYPERV_*, VMWARE_*)
- Remediation includes actionable commands
- Test-HypervisorAvailable -Detailed includes new keys

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 66a61a6 | feat | Add Remediation and ErrorCode to provider GetAvailabilityDetails |
| dce7596 | feat | Enhance Get-HypervisorProvider error messages with remediation |
| c547f97 | test | Add provider detection tests for remediation guidance |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] VMInfo.ps1 parser error**
- **Found during:** Task 1 verification
- **Issue:** `GetExpectedStableState` switch statement caused "Not all code path returns value" parser error
- **Fix:** Changed switch pattern to assign to variable first, then return
- **Files modified:** FFUDevelopment/Modules/FFU.Hypervisor/Classes/VMInfo.ps1
- **Commit:** 66a61a6 (included in Task 1)

**2. [Rule 1 - Bug] Variable interpolation syntax error**
- **Found during:** Task 2 verification
- **Issue:** `"Hyper-V$hypervErrorCode:"` caused parser error (colon after variable)
- **Fix:** Changed to `"Hyper-V${hypervErrorCode}:"` with explicit braces
- **Files modified:** FFUDevelopment/Modules/FFU.Hypervisor/Public/Get-HypervisorProvider.ps1
- **Commit:** dce7596

## Verification Results

All verification checks passed:
1. Module loads without errors
2. GetAvailabilityDetails includes Remediation and ErrorCode keys
3. All 29 tests pass (3 appropriately skipped based on system config)

## Test Coverage

| Test Category | Count | Status |
|--------------|-------|--------|
| HyperVProvider.GetAvailabilityDetails | 5 | Pass |
| VMwareProvider.GetAvailabilityDetails | 5 | Pass |
| Get-HypervisorProvider Validate | 3 | 1 Pass, 2 Skip |
| Get-HypervisorProvider Auto | 3 | 2 Pass, 1 Skip |
| Test-HypervisorAvailable Detailed | 5 | Pass |
| Test-HypervisorAvailable Simple | 4 | Pass |
| Error Code Values | 2 | Pass |
| Remediation Content | 5 | Pass |
| **Total** | **32** | **29 Pass, 3 Skip** |

Note: 3 tests skipped because both hypervisors are available on the test system - they test error message format when provider unavailable.

## Version Updates

- FFU.Hypervisor: 1.3.4 -> 1.3.5
- Main version: 1.8.12 -> 1.8.13

## Next Phase Readiness

Ready for:
- **16-02**: VM Lifecycle error handling (builds on error code pattern)
- **16-03**: Disk operations error handling

No blockers identified.
