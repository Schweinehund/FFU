---
phase: 16-ffu-hypervisor-reliability
plan: 04
subsystem: hypervisor
tags: [service-recovery, retry-logic, exponential-backoff, hyper-v, vmware, resilience]

# Dependency graph
requires:
  - phase: 16-ffu-hypervisor-reliability
    provides: plan-02 VM state detection reliability
provides:
  - Test-HypervisorService function for service health monitoring
  - Invoke-WithHypervisorRetry wrapper for automatic retry on service failures
  - Test-IsServiceError for detecting service-related errors
  - Exponential backoff with jitter to avoid hammering
  - Provider methods wrapped with retry logic
  - 29 Pester tests for service recovery scenarios
affects: [ffu.vm, buildffuvm, long-running-builds, service-restart-recovery]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Service health check pattern (Test-HypervisorService returns structured health info)
    - Retry wrapper pattern (wrap operations with automatic retry on transient failures)
    - Exponential backoff with jitter (prevents thundering herd on service recovery)
    - Error classification pattern (Test-IsServiceError distinguishes transient from permanent)

key-files:
  created:
    - FFUDevelopment/Modules/FFU.Hypervisor/Public/Test-HypervisorService.ps1
    - FFUDevelopment/Modules/FFU.Hypervisor/Public/Invoke-WithHypervisorRetry.ps1
    - Tests/Unit/FFU.Hypervisor.ServiceRecovery.Tests.ps1
  modified:
    - FFUDevelopment/Modules/FFU.Hypervisor/Providers/HyperVProvider.ps1
    - FFUDevelopment/Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1
    - FFUDevelopment/Modules/FFU.Hypervisor/FFU.Hypervisor.psm1
    - FFUDevelopment/Modules/FFU.Hypervisor/FFU.Hypervisor.psd1
    - FFUDevelopment/version.json

key-decisions:
  - "Service errors detected by error message pattern matching"
  - "Non-service errors rethrown immediately without retry"
  - "Exponential backoff formula: BaseDelay * 2^(attempt-1) + random jitter"
  - "PreCheckService validates service health before operation (for StartVM)"
  - "StopVM does not use PreCheckService (stopping doesn't need service)"
  - "VMware is considered healthy if vmrun.exe is accessible"

patterns-established:
  - "Wrap critical hypervisor operations with Invoke-WithHypervisorRetry"
  - "Use Test-HypervisorService -WaitForReady before build phases"
  - "Service errors include: RPC failures, vmms unavailable, vmrun connection issues"

# Metrics
duration: 9min
completed: 2026-01-24
---

# Phase 16 Plan 04: Service Recovery Summary

**Automatic recovery from hypervisor service restarts during builds using Test-HypervisorService and Invoke-WithHypervisorRetry**

## Performance

- **Duration:** 9 min
- **Started:** 2026-01-23T23:56:21Z
- **Completed:** 2026-01-24T00:05:22Z
- **Tasks:** 3
- **Files modified:** 9 (3 created, 6 modified)

## Accomplishments

- Created Test-HypervisorService function for checking service health
- Created Invoke-WithHypervisorRetry wrapper with exponential backoff
- Integrated retry logic into both HyperVProvider and VMwareProvider
- Test-IsServiceError classifies errors as service-related or not
- 29 comprehensive Pester tests for service recovery
- FFU.Hypervisor updated to v1.3.8, main version v1.8.15

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Test-HypervisorService Function** - `b910298` (feat)
2. **Task 2: Create Invoke-WithHypervisorRetry Wrapper** - `38db6a6` (feat)
3. **Task 3: Integrate Retry Logic into Providers** - `e1743c4` (feat)

## Files Created

- `FFUDevelopment/Modules/FFU.Hypervisor/Public/Test-HypervisorService.ps1` - Service health check function
  - Returns hashtable with IsHealthy, ServiceStatus, CanRecover, RecoveryAction
  - Hyper-V: checks vmms and vmcompute services
  - VMware: checks vmrun accessibility and VMAuthdService
  - WaitForReady parameter polls until ready or timeout

- `FFUDevelopment/Modules/FFU.Hypervisor/Public/Invoke-WithHypervisorRetry.ps1` - Retry wrapper
  - Automatic retry on service-related errors
  - Exponential backoff: BaseDelay * 2^(attempt-1) + jitter
  - PreCheckService parameter validates before execution
  - Non-service errors rethrown immediately

- `Tests/Unit/FFU.Hypervisor.ServiceRecovery.Tests.ps1` - 29 tests
  - Test-HypervisorService tests for both providers
  - Invoke-WithHypervisorRetry retry logic tests
  - Test-IsServiceError pattern matching tests
  - Module export tests

## Files Modified

- `HyperVProvider.ps1` - Added retry wrapper to StartVM, StopVM, GetVMState
- `VMwareProvider.ps1` - Added retry wrapper to StartVM, StopVM, GetVMState
- `FFU.Hypervisor.psm1` - Export new functions
- `FFU.Hypervisor.psd1` - Version 1.3.8, FunctionsToExport, ReleaseNotes
- `version.json` - Main version 1.8.15, FFU.Hypervisor 1.3.8

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Error detection via pattern matching | Simple and reliable for known error messages |
| Non-service errors not retried | Prevents wasting time on permanent failures |
| Exponential backoff with jitter | Prevents thundering herd on service recovery |
| PreCheckService for StartVM only | StopVM can work even with degraded service |
| VMware healthy = vmrun accessible | VMware doesn't require persistent service |

## Service Error Patterns

### Hyper-V Service Errors
- "Virtual Machine Management Service"
- "vmms"
- "RPC server is unavailable"
- "The service has not been started"

### VMware Service Errors
- "Unable to connect"
- "vmrun"
- "Process not found"
- "Connection refused"

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- PowerShell string interpolation with colon after variable required `$($var):` syntax
- Pester skip conditions evaluated at discovery time, not runtime (BeforeAll scope)
- ScriptBlock variables need Global scope for cross-scope access in tests

## Next Phase Readiness

- Service recovery is now automatic for all provider operations
- Long-running builds will survive service restarts
- Ready for further reliability improvements
- All success criteria met:
  - [x] Test-HypervisorService checks service health for both providers
  - [x] Invoke-WithHypervisorRetry automatically retries on service interruptions
  - [x] Critical provider methods wrapped with retry logic
  - [x] Exponential backoff with jitter prevents hammering
  - [x] Clear error messages when recovery fails
  - [x] New functions exported from module
  - [x] Test coverage exists for service recovery scenarios
  - [x] Existing functionality not broken (no regression)

---
*Phase: 16-ffu-hypervisor-reliability*
*Completed: 2026-01-24*
