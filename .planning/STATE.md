# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-23)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** Phase 25 FFUUI.Core Reliability - IN PROGRESS

## Current Position

**Milestone:** v1.9.0 Reliability Hardening
**Phase:** 25 of 25 (FFUUI.Core Reliability) - IN PROGRESS
**Plan:** 3 of 4 (Job Failure Context Extraction complete)
**Status:** In progress
**Last activity:** 2026-01-24 - Completed 25-03-PLAN.md (REL-UI-05)

Progress: Milestone v1.9.0
[##########] 95% (10.5/11 phases complete)

## Completed Phases This Milestone

| Phase | Name | Plans | Date |
|-------|------|-------|------|
| 15 | FFU.Core Reliability | 3/3 | 2026-01-23 |
| 16 | FFU.Hypervisor Reliability | 4/4 | 2026-01-24 |
| 17 | FFU.VM Reliability | 4/4 | 2026-01-24 |
| 18 | FFU.Imaging Reliability | 5/5 | 2026-01-24 |
| 19 | FFU.Media Reliability | 4/4 | 2026-01-24 |
| 20 | FFU.Updates Reliability | 4/4 | 2026-01-24 |
| 21 | FFU.Drivers Reliability | 4/4 | 2026-01-24 |
| 22 | FFU.Preflight Reliability | 4/4 | 2026-01-24 |
| 23 | BuildFFUVM.ps1 Reliability | 4/4 | 2026-01-24 |
| 24 | WinPE Scripts Reliability | 4/4 | 2026-01-24 |

## Phase 25 Progress (IN PROGRESS)

| Plan | Name | Status | Commit |
|------|------|--------|--------|
| 25-01 | Centralized UI State Recovery | Complete | 459933a |
| 25-02 | Structured Error Display | Complete | caa4316 |
| 25-03 | Job Failure Context Extraction | Complete | 2b796b4 |
| 25-04 | Load-Time Config Validation | Pending | - |

## Completed Milestones

| Milestone | Status | Phases | Date |
|-----------|--------|--------|------|
| v1.8.0 Codebase Health | SHIPPED | 1-10 (33 plans) | 2026-01-20 |
| v1.8.1 Bug Fixes | SHIPPED | 11-13 (5 plans) | 2026-01-20 |
| v1.8.3 VMware UI Settings | SHIPPED | 14 (2 plans) | 2026-01-21 |

## Decisions Made

| Decision | Context | Date |
|----------|---------|------|
| Phase-per-module structure | Systematic coverage ensures nothing missed | 2026-01-23 |
| Proactive hardening approach | No specific failures driving this - comprehensive improvement | 2026-01-23 |
| 44 specific requirements | Concrete, testable requirements derived from audit scope | 2026-01-23 |
| Use x-common-values in schema | Standard JSON Schema doesn't have property for common values | 2026-01-23 |
| Typo detection via case+prefix | Covers most common typo patterns (case errors, partial names) | 2026-01-23 |
| ErrorCode prefix pattern | HYPERV_/VMWARE_ prefixes for clear provider identification | 2026-01-23 |
| Remediation as array | Multiple steps may be needed, easier to format | 2026-01-23 |
| Transient states not final | Starting/Stopping/Saving/Restoring should not be treated as stable | 2026-01-23 |
| VMware 5s race window | VMware process may not be detectable for 5s after StartVM | 2026-01-23 |
| Confidence levels for VMware | High/Medium/Low based on detection method reliability | 2026-01-23 |
| Exponential backoff with jitter | Prevents thundering herd on service recovery | 2026-01-24 |
| Service errors via pattern matching | Simple and reliable for known error messages | 2026-01-24 |
| Non-service errors not retried | Prevents wasting time on permanent failures | 2026-01-24 |
| Running VMs block switch | Explicit stop required before provider switch | 2026-01-23 |
| VHD format cross-compatible | VHD works on both Hyper-V and VMware | 2026-01-23 |
| TPM warning not blocker | VMware vTPM requires encryption but deployment works | 2026-01-23 |
| Error classification via pattern matching | Simple keyword matching for common VM creation errors | 2026-01-24 |
| TPM errors non-critical | VMs work without TPM, only some features limited | 2026-01-24 |
| Progressive cleanup registration | Register cleanup immediately after resource creation | 2026-01-24 |
| Transient vs permanent error classification | Pattern-match disk busy/locked as transient, exists/not-found as permanent | 2026-01-24 |
| Unknown errors fail fast | Default to NOT transient for unknown errors | 2026-01-24 |
| VM retry base delay 2s | Lower than hypervisor service 5s since VM ops are faster | 2026-01-24 |
| Checkpoint margin default 100% | Worst case: checkpoint can grow to full VHDX size | 2026-01-24 |
| Dynamic VHDX uses max size | Better to overestimate than fail mid-operation | 2026-01-24 |
| Orphan = files appearing during op | Simple and reliable detection of partial checkpoint files | 2026-01-24 |
| Default 10% safety margin | Conservative for typical imaging operations | 2026-01-24 |
| System.IO.DriveInfo over Get-Volume | No dependency on Storage module, works cross-platform | 2026-01-24 |
| int64 for byte calculations | Avoids overflow with large values (100TB+) | 2026-01-24 |
| Partition state comprehensive | Capture count, sizes, types, drive letters, timestamp | 2026-01-24 |
| Expected change enum | PartitionAdded, PartitionRemoved, DriveLetterAssigned, SizeChanged, None | 2026-01-24 |
| Imaging retry base delay 3s | Slightly higher than VM ops since imaging is slower | 2026-01-24 |
| DISM cleanup optional switch | RunDismCleanupOnRetry for mount operations only | 2026-01-24 |
| HResult codes for imaging errors | More reliable than message patterns for known codes | 2026-01-24 |
| ERROR_DISK_FULL not transient | User must free space, retry won't help | 2026-01-24 |
| 100% space margin for FFU capture | Dynamic VHDX FFU can be as large as max size | 2026-01-24 |
| VHDX integrity via Get-VHD | Simple check that confirms VHDX is accessible for retry | 2026-01-24 |
| Partial FFU cleanup on failure | Register-CleanupAction removes partial file automatically | 2026-01-24 |
| Structured readiness result | FailureReason + Remediation enables programmatic handling | 2026-01-24 |
| DISM error classification via HResult | Regex pattern matching for error codes is reliable | 2026-01-24 |
| Unknown errors preserve original message | Enables debugging even for unrecognized errors | 2026-01-24 |
| RuntimeInformation.ProcessArchitecture for host detection | Cross-platform compatible host architecture detection | 2026-01-23 |
| ADK folder mapping: x64 -> amd64 | ADK uses 'amd64' folder for x64 architecture tools | 2026-01-23 |
| Pre-validation before DISM cleanup | Fail fast on missing architecture before expensive cleanup | 2026-01-23 |
| InvokeCommand.GetCommand for ThreadJob | Use $ExecutionContext.InvokeCommand.GetCommand for function availability | 2026-01-23 |
| Invoke-CatalogQueryWithRetry internal | Helper function not exported, used by Get-ProductsCab internally | 2026-01-24 |
| Metadata lookup reduced retries | MaxRetries 2 for non-critical metadata (3 for main search) | 2026-01-24 |
| Catalog retry jitter 0-3s | Prevents thundering herd on service recovery | 2026-01-24 |
| AllowEmptyCollection for updates | Edge case: empty updates array should return success result | 2026-01-24 |
| Continue-by-default after failures | One update failure should not block others | 2026-01-24 |
| StopOnCriticalFailure optional | Users can opt-in to halt on critical failures | 2026-01-24 |
| Invoke-ValidatedDownload internal helper | Encapsulates download-validate-retry pattern in Save-KB | 2026-01-24 |
| MaxValidationRetries default 2 | Two re-download attempts before giving up on corrupted file | 2026-01-24 |
| Cache naming with underscores | products_{arch}_{version}.cab - filesystem-safe | 2026-01-24 |
| JSON metadata file | .meta file alongside cached cab for human-readable tracking | 2026-01-24 |
| 24h default cache staleness | Products.cab rarely changes more than daily | 2026-01-24 |
| Reuse Test-MSUIntegrity for cache | MinimumSizeBytes=0 since products.cab can be small | 2026-01-24 |
| Exit code classification vendor-specific | HP/Lenovo/Dell/Microsoft have different exit code semantics | 2026-01-24 |
| Reboot codes (1641, 3010) are Success | Extraction completed, reboot is irrelevant for image builds | 2026-01-24 |
| Unknown exit codes default to Warn | Continue-by-default for unrecognized exit codes | 2026-01-24 |
| ${DriverName} syntax for messages | Prevents PowerShell parser confusion with colons | 2026-01-24 |
| 7-day OEM catalog cache staleness | OEM catalogs update weekly at most | 2026-01-24 |
| Stale cache as network fallback | When network fails, use stale cache with warning | 2026-01-24 |
| New-FFURemediationBlock inline | Use inline invocation instead of pre-computed variable (linter conflicts) | 2026-01-24 |
| Get-CachedOEMCatalog internal function | Not exported, used only by OEM driver functions | 2026-01-24 |
| 4x driver extraction multiplier | OEM packages extract to 3-4x compressed size | 2026-01-24 |
| Disk space warning-only | Continue-by-default for driver operations | 2026-01-24 |
| VHDX expansion hint for large sets | Users can expand VHDX before driver injection | 2026-01-24 |
| FltMgr restart as last resort | Filter Manager restart disruptive but may clear stuck filter states | 2026-01-24 |
| WimMount retry MaxRetries 3, BaseDelay 2s | Balance between quick success and not waiting too long | 2026-01-24 |
| Three severity levels (Critical/Warning/Info) | Clear distinction between build blockers, potential issues, and optional improvements | 2026-01-24 |
| Only Critical failures block builds | Warning/Info issues displayed for awareness but don't prevent builds | 2026-01-24 |
| Script-scope error collector | Matches CleanupRegistry pattern, available across module functions | 2026-01-24 |
| Existing implementation reuse | Document Phase 8 work as satisfying 23-03 requirements | 2026-01-24 |
| Critical=true default for Invoke-BuildPhase | Safe default - phases fail build unless explicitly marked non-critical | 2026-01-24 |
| Structured result object | PSCustomObject with Success, Skipped, Cancelled, Error, Result enables inspection | 2026-01-24 |
| Error summary before cleanup | Users need to see all errors before resources are cleaned up | 2026-01-24 |
| Severity colors Red/Yellow/Cyan | Standard console color conventions for error display | 2026-01-24 |
| WMI disk query for WinPE | Get-CimInstance Win32_DiskDrive instead of Get-Disk (Storage module not in WinPE) | 2026-01-24 |
| Virtual disk pattern match | Model -notmatch 'Virtual\|VMware' catches both Hyper-V and VMware VMs | 2026-01-24 |
| Fail-fast before diskpart | Validate disk before any partition manipulation begins | 2026-01-24 |
| Write-Host for warnings | Write-Host with colors for consistent console formatting instead of Write-Warning | 2026-01-24 |
| Run-Sysprep.ps1 only critical | Other scripts optional, but Sysprep required for FFU generalization | 2026-01-24 |
| Full paths in error messages | Users debugging failed builds need exact expected locations | 2026-01-24 |
| Start-Transcript for CaptureFFU | Captures ALL console output to network share for post-mortem debugging | 2026-01-24 |
| Add-Content for Orchestrator log | Incremental logging survives crashes, partial logs preserved | 2026-01-24 |
| W: for CaptureFFU, D: for Orchestrator | Network share and Apps ISO are the only persistent storage in WinPE | 2026-01-24 |
| Graceful logging failures | Logging failures produce warnings but never abort actual work | 2026-01-24 |
| 128MB critical memory threshold | DISM capture may fail below this, warn but continue | 2026-01-24 |
| 20GB critical disk threshold | Fail-fast for network share disk space | 2026-01-24 |
| 60GB warning disk threshold | Continue with warning for low disk space | 2026-01-24 |
| Memory warns, disk critical throws | Memory low can still work, disk full cannot | 2026-01-24 |
| Centralized UI reset function | Single Reset-FFUUIToIdle handles all UI control resets after errors | 2026-01-24 |
| Defensive null checks in UI | All control access wrapped in null checks for graceful degradation | 2026-01-24 |
| Plural function name for validation | Show-FFUValidationErrors plural - handles multiple validation errors | 2026-01-24 |
| InModuleScope for test mocking | InModuleScope allows proper mocking of internal module functions | 2026-01-24 |
| Severity header format | Use [Severity] prefix in message body for clear indication | 2026-01-24 |
| PSObject parameter type for testability | Use PSObject instead of Job type to allow mock objects in Pester tests | 2026-01-24 |
| Priority-based error extraction | Check MessagingContext first as richest structured error source | 2026-01-24 |
| Error type classification via pattern matching | Regex patterns for DISM/Hyper-V/Network/Disk/Permission errors | 2026-01-24 |

## Recent Activity

- 2026-01-24: Completed 25-03-PLAN.md (Job Failure Context Extraction) - REL-UI-05, 57 tests, FFUUI.Core v0.0.16
- 2026-01-24: Completed 25-02-PLAN.md (Structured Error Display) - REL-UI-04, 45 tests, FFUUI.Core v0.0.15
- 2026-01-24: Completed 25-01-PLAN.md (Centralized UI State Recovery) - REL-UI-03, 30 tests, FFUUI.Core v0.0.14
- 2026-01-24: Completed Phase 24 (WinPE Scripts Reliability) - 4/4 plans, 141 Pester tests
- 2026-01-24: Completed 24-04-PLAN.md (Resource Exhaustion Handling) - REL-WINPE-04, 40 tests
- 2026-01-24: Completed 24-03-PLAN.md (Log Preservation Enhancement) - REL-WINPE-03, 45 tests
- 2026-01-24: Completed 24-02-PLAN.md (Orchestrator Dependency Detection) - REL-WINPE-02, 35 tests
- 2026-01-24: Completed 24-01-PLAN.md (CaptureFFU Disk Validation) - REL-WINPE-01, 21 tests
- 2026-01-24: Completed 23-04-PLAN.md (Termination Cleanup Enhancement) - REL-BUILD-02/04/05, 30 tests, v1.8.36
- 2026-01-24: Completed Phase 23 (BuildFFUVM.ps1 Reliability) - 4/4 plans
- 2026-01-24: Completed 23-02-PLAN.md (Phase Wrapper with Continue-on-Failure) - REL-BUILD-01, 43 tests, FFU.Core v1.0.22
- 2026-01-24: Completed 23-03-PLAN.md (Checkpoint Resume Integration) - REL-BUILD-03, requirements already met by Phase 8
- 2026-01-24: Completed 23-01-PLAN.md (Build Error Aggregation) - REL-BUILD-04, 42 tests, FFU.Core v1.0.21
- 2026-01-24: Completed 22-01-PLAN.md (Enhanced Prerequisite Detection) - REL-PRE-01, 30 tests, FFU.Preflight v1.3.0
- 2026-01-24: Completed 22-03-PLAN.md (WIMMount Repair Resilience) - REL-PRE-03, 22 tests, retry with exponential backoff
- 2026-01-24: Completed Phase 22 (FFU.Preflight Reliability) - 4/4 plans, FFU.Preflight v1.3.0
- 2026-01-24: Completed 22-02-PLAN.md (Remediation Steps Quality) - REL-PRE-02, 21 new tests
- 2026-01-24: Completed 22-04-PLAN.md (Severity Classification) - REL-PRE-04
- 2026-01-24: Completed 21-04-PLAN.md (Driver Injection Verification) - REL-DRV-04, 19 Pester tests, disk space validation
- 2026-01-24: Completed Phase 21 (FFU.Drivers Reliability) - 4/4 plans, FFU.Drivers v1.1.0
- 2026-01-24: Completed 21-03-PLAN.md (Catalog Fallback Sources) - REL-DRV-03, catalog caching
- 2026-01-24: Completed 21-02-PLAN.md (Vendor-Specific Extraction Error Handling) - REL-DRV-02, 23 Pester tests
- 2026-01-24: Executed 21-01-PLAN.md (Driver Download Retry) - REL-DRV-01/02, 38 Pester tests
- 2026-01-24: Completed Phase 20 (FFU.Updates Reliability) - 4/4 plans, FFU.Updates v1.1.0
- 2026-01-24: Completed Phase 19 (FFU.Media Reliability) - 4/4 plans, FFU.Media v1.8.0
- 2026-01-24: Completed Phase 18 (FFU.Imaging Reliability) - 5/5 plans, FFU.Imaging v1.3.0
- 2026-01-24: Completed Phase 17 (FFU.VM Reliability) - 4/4 plans
- 2026-01-24: Completed Phase 16 (FFU.Hypervisor Reliability) - 4/4 plans
- 2026-01-23: Completed Phase 15 (FFU.Core Reliability) - 3/3 plans

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-24
**Stopped at:** Completed 25-03-PLAN.md (Job Failure Context Extraction)
**Resume file:** None
**Next action:** Execute 25-04-PLAN.md (Load-Time Config Validation)

---
*State updated: 2026-01-24*
