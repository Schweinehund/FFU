# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-23)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** Phase 18 - FFU.Imaging Reliability

## Current Position

**Milestone:** v1.9.0 Reliability Hardening
**Phase:** 18 of 25 (FFU.Imaging Reliability)
**Plan:** 1 of 5 complete
**Status:** In progress
**Last activity:** 2026-01-24 - Completed 18-01-PLAN.md (Disk Space Pre-Validation)

Progress: Milestone v1.9.0
[###-------] 27% (3/11 phases)

## Completed Phases This Milestone

| Phase | Name | Plans | Date |
|-------|------|-------|------|
| 15 | FFU.Core Reliability | 3/3 | 2026-01-23 |
| 16 | FFU.Hypervisor Reliability | 4/4 | 2026-01-24 |
| 17 | FFU.VM Reliability | 4/4 | 2026-01-24 |

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

## Recent Activity

- 2026-01-24: Executed 18-01-PLAN.md (Disk Space Pre-Validation) - REL-IMG-01
- 2026-01-24: FFU.Imaging v1.1.8, main version v1.8.20, 59 Pester tests
- 2026-01-24: Completed Phase 17 (FFU.VM Reliability) - 4/4 plans, verified
- 2026-01-24: Executed 17-04-PLAN.md (Checkpoint Disk Space Validation) - REL-VM-04
- 2026-01-24: Executed 17-03-PLAN.md (Transient Error Retry) - REL-VM-03
- 2026-01-24: Executed 17-02-PLAN.md (Orphan Detection and Cleanup) - REL-VM-02
- 2026-01-24: Executed 17-01-PLAN.md (VM Creation Diagnostics) - REL-VM-01
- 2026-01-24: FFU.VM v1.0.11, main version v1.8.18, 105 Pester tests
- 2026-01-24: Executed 16-04-PLAN.md (Service Recovery) - REL-HYP-04, Phase 16 complete
- 2026-01-23: Executed 16-03-PLAN.md (Provider Switch Validation) - REL-HYP-03
- 2026-01-23: Executed 16-02-PLAN.md (VM State Detection Reliability) - REL-HYP-02
- 2026-01-23: Executed 16-01-PLAN.md (Provider Detection with Remediation) - REL-HYP-01

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-24
**Stopped at:** Completed 18-01-PLAN.md
**Resume file:** None
**Next action:** Execute 18-02-PLAN.md or next plan in Phase 18

---
*State updated: 2026-01-24*
