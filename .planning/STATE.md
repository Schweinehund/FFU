# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-28)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** Milestone v1.10.0 Upstream Cherry-Pick — COMPLETE

## Current Position

**Milestone:** v1.10.0 Upstream Cherry-Pick
**Phase:** 43 of 43 (Deployment Improvements and Nice-to-Haves) - VERIFIED
**Plan:** 3 of 3 complete
**Status:** All 10 phases verified, all 20 v1 requirements complete, milestone ready for audit
**Last activity:** 2026-02-02 — Phase 43 verified and complete

Progress: ██████████ 100% (31 of 31 plans complete across 10 phases)

## Shipped Milestones

| Milestone | Status | Phases | Date |
|-----------|--------|--------|------|
| v1.8.0 Codebase Health | SHIPPED | 1-10 (33 plans) | 2026-01-20 |
| v1.8.1 Bug Fixes | SHIPPED | 11-13 (5 plans) | 2026-01-20 |
| v1.8.3 VMware UI Settings | SHIPPED | 14 (2 plans) | 2026-01-21 |
| v1.9.0 Reliability Hardening | SHIPPED | 15-25 (44 plans) | 2026-01-24 |
| v1.9.1 Build Phase Integration | SHIPPED | 26 (3 plans) | 2026-01-24 |
| v1.9.2 Smart Configuration & Bug Fixes | SHIPPED | 27-30 (10 plans) | 2026-01-25 |
| v1.9.3 OEM Driver Bug Fixes | SHIPPED | 31-33 (5 plans) | 2026-01-27 |

**Total:** 33 phases, 102 plans shipped across 7 milestones

## v1.10.0 Phases

| Phase | Goal | Requirements | Status |
|-------|------|-------------|--------|
| 34: Winget Bug Fixes | JSON safety + MSI path quoting | BUGFIX-01, BUGFIX-03 | ✓ Verified (3/3 plans) |
| 35: PPKG Path Quoting | xcopy space handling | BUGFIX-02 | ✓ Verified (1/1 plan) |
| 36: CU Skip + ESD BITS | Version comparison + BITS downloads | BUGFIX-04, DL-01 | ✓ Verified (3/3 plans) |
| 37: Winget Ordering | App ordering + dependency handling | WINGET-01, WINGET-02 | ✓ Verified (3/3 plans) |
| 38: SUBST Drive Mapping | Long path reliability | PATH-01 | ✓ Complete (2/2 plans) |
| 39: Model Normalization | Brand dedup + SystemID | DRV-02, DRV-03 | ✓ Complete (2/2 plans) |
| 40: Dell Refactoring | CatalogIndexPC logic | DRV-01 | ✓ Verified (3/3 plans) |
| 41: Driver Matching + UI | Fallback, PE copy, UI clarity | DRV-05, DRV-06, DRV-07 | ✓ Verified (3/3 plans) |
| 42: New OEM Manufacturers | 8 new OEMs | DRV-04 | ✓ Verified (8/8 plans) |
| 43: Deployment Improvements | Multi-disk, empty drivers, delay | DEPLOY-01..03, NICE-01..02 | ✓ Verified (3/3 plans) |

## Decisions Log

| Phase | Decision | Rationale | Impact |
|-------|----------|-----------|--------|
| 43-01 | Multi-disk menu shows Number, Model, SizeGB, Index columns for clear disk identification | Prevents accidental wrong-disk wipes with comprehensive display | ApplyFFU.ps1 Get-HardDrive uses Format-Table with 4 columns following FFU file selection pattern |
| 43-01 | USB detection uses Get-Disk BusType='USB' as primary, falls back to volume-based detection for compatibility | Modern disk-level detection more reliable than volume properties | Primary: BusType filter, Fallback 1: Removable volumes, Fallback 2: Fixed "Deploy" label |
| 43-01 | UniqueId logged for USB disks (when available) to create audit trail of deployment media | Enables tracking which physical USB drives were used for deployments | Logged via Get-PhysicalDisk for each USB disk detected via BusType |
| 43-01 | Empty folder check uses recursive .inf file search (handles nested OEM driver structures) | Prevents DISM 0x80070057 errors on empty paths | Get-ChildItem -Recurse -Include *.inf checks before injection |
| 43-01 | Skip-drivers prompt appears before any driver detection to avoid unnecessary processing | Optional deployment feature with early-exit optimization | Y/N prompt bypasses both DriverMapping.json and manual selection |
| 43-01 | VM detection logic completely unchanged (Index 0, SCSILogicalUnit 0) to preserve existing behavior | Hyper-V VM deployments have specific disk requirements | Get-HardDrive VM path untouched to maintain compatibility |
| 43-02 | Implement delay directly in Orchestrator.ps1 rather than unattend.xml | More maintainable, visible to users, easier to adjust | Orchestrator.ps1 has 30-second Security Platform delay with countdown display before app installations |

## Blockers

None.

## Session Continuity

**Last session:** 2026-02-02
**Stopped at:** Phase 43 verified and complete — milestone v1.10.0 ready for audit
**Resume file:** None
**Next action:** Audit milestone v1.10.0 (/gsd:audit-milestone)

---
*State updated: 2026-02-02 after Phase 43 verification complete*
