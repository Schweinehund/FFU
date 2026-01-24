# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-23)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** Phase 20 — FFU.Updates Reliability

## Current Position

**Milestone:** v1.9.0 Reliability Hardening
**Phase:** 20 of 25 (FFU.Updates Reliability)
**Plan:** Not started
**Status:** Ready to plan
**Last activity:** 2026-01-24 — Phase 19 complete (verified)

Progress: Milestone v1.9.0
[#####-----] 45% (5/11 phases complete)

## Completed Phases This Milestone

| Phase | Name | Plans | Date |
|-------|------|-------|------|
| 15 | FFU.Core Reliability | 3/3 | 2026-01-23 |
| 16 | FFU.Hypervisor Reliability | 4/4 | 2026-01-24 |
| 17 | FFU.VM Reliability | 4/4 | 2026-01-24 |
| 18 | FFU.Imaging Reliability | 5/5 | 2026-01-24 |
| 19 | FFU.Media Reliability | 4/4 | 2026-01-24 |

## Phase 19 Progress

| Plan | Name | Status | Commit |
|------|------|--------|--------|
| 19-01 | WinPE Media Readiness Check | Complete | 4b009f1 |
| 19-02 | DISM/ADK Error Classification | Complete | 7c45429 |
| 19-03 | ISO Disk Space Pre-Validation | Complete | cab75d6 |
| 19-04 | Architecture Capability Validation | Complete | 4064f7b |

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

## Recent Activity

- 2026-01-24: Completed Phase 19 (FFU.Media Reliability) - 4/4 plans, verified
- 2026-01-24: FFU.Media v1.8.0, main version v1.8.27, 134 FFU.Media reliability Pester tests
- 2026-01-24: Executed 19-03-PLAN.md (ISO Disk Space Pre-Validation) - REL-MED-03
- 2026-01-24: Executed 19-01-PLAN.md (WinPE Media Readiness Check) - REL-MED-01
- 2026-01-24: Executed 19-04-PLAN.md (Architecture Capability Validation) - REL-MED-04
- 2026-01-24: Executed 19-02-PLAN.md (DISM/ADK Error Classification) - REL-MED-02
- 2026-01-24: Completed Phase 18 (FFU.Imaging Reliability) - 5/5 plans, verified
- 2026-01-24: Completed Phase 17 (FFU.VM Reliability) - 4/4 plans, verified
- 2026-01-24: Completed Phase 16 (FFU.Hypervisor Reliability) - 4/4 plans, verified
- 2026-01-23: Completed Phase 15 (FFU.Core Reliability) - 3/3 plans, verified

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-24
**Stopped at:** Completed Phase 19 (FFU.Media Reliability)
**Resume file:** None
**Next action:** Start Phase 20 (FFU.Updates Reliability)

---
*State updated: 2026-01-24*
