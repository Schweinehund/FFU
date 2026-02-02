# Project Milestones: FFU Builder

## v1.10.0 Upstream Cherry-Pick (Shipped: 2026-02-02)

**Delivered:** Selectively ported 60 upstream commits into modular architecture — critical bug fixes, 8 new OEM manufacturers, Dell CatalogIndexPC optimization, SUBST long-path reliability, and deployment UX improvements.

**Phases completed:** 34-43 (31 plans total)

**Key accomplishments:**

- Winget reliability overhaul: mutex-protected JSON writes, app ordering enforcement, and Win32 dependency resolution with deduplication
- 8 new OEM manufacturers added (Acer, Dynabook, Panasonic, Samsung, Fujitsu, ASUS, MSI, Getac) with catalog integration
- Dell CatalogIndexPC refactoring achieving 10-30x download reduction (6-15MB vs 160MB) with three-tier fallback
- SUBST virtual drive mapping prevents >260 character path failures during driver operations
- Deployment improvements: multi-disk selection menu, empty driver skip, Security Platform delay, USB UniqueId tracking
- CU skip logic avoids unnecessary 3-4GB cumulative update downloads when ESD version already matches

**Stats:**

- 121 files created/modified
- +28,748 / -401 lines of PowerShell
- 10 phases, 31 plans, 20 requirements
- 6 days (2026-01-28 → 2026-02-02)

**Git range:** `37b96bc` → `d063107`

**What's next:** Define requirements for next improvement cycle

---

## v1.9.3 OEM Driver Bug Fixes (Shipped: 2026-01-27)

**Delivered:** Fix HP and Dell OEM driver bugs and ensure all OEM driver operations use proper file logging.

**Phases completed:** 31-33 (5 plans total)

**Key accomplishments:**

- HP driver extraction exit code 1168 handling (graceful success, not build failure)
- Dell CatalogPC.xml missing scenario with fallback behavior and logging
- Structured OEM driver logging with [OEM][Model][Operation] prefixes across all driver functions
- All driver operations migrated from console-only output to WriteLog file logging
- Static analysis Pester tests verify logging patterns

**Stats:**

- 3 phases, 5 plans, 14 requirements
- 2 days (2026-01-26 → 2026-01-27)

**What's next:** Upstream cherry-pick evaluation and selective port (v1.10.0)

---

## v1.9.2 Smart Configuration & Bug Fixes (Shipped: 2026-01-25)

**Delivered:** Improve UI intelligence for network configuration and optimize build efficiency with smart Apps.iso handling.

**Phases completed:** 27-30 (10 plans total)

**Key accomplishments:**

- Documented and closed 5 session bug fixes (VHD stability, config persistence, Winget CLI issues)
- VM Host IP Address dropdown with network adapter context (format: IP - Adapter - Description)
- VMware auto-selection logic using primary adapter with default gateway
- Apps.iso smart staleness detection with content hashing (skip rebuild when unchanged)
- Component-based disk space estimation with pre-flight validation (fail if insufficient)
- Test-FFUHostIPAddress integration into Invoke-FFUPreflight pipeline (gap closure)

**Stats:**

- 47 commits
- 50 files modified
- +8,620 / -204 lines
- 4 phases, 10 plans, 13 requirements
- 1 day (2026-01-25)

**Git range:** `b12f5f8` → `947f0b8`

**What's next:** Define requirements for next improvement cycle

---

## v1.9.1 Build Phase Integration (Shipped: 2026-01-24)

**Delivered:** Complete graceful degradation integration by wrapping all BuildFFUVM.ps1 build phases with Invoke-BuildPhase for consistent error handling and build resilience.

**Phases completed:** 26 (3 plans total)

**Key accomplishments:**

- Wrapped critical phases (VHDX creation, VM creation, FFU capture) with Invoke-BuildPhase -Critical $true (halt on failure)
- Wrapped non-critical phases (driver download, deployment media, USB creation, FFU cleanup) with -Critical $false (continue on failure)
- Added error aggregation initialization at build start with ThreadJob-safe guard pattern
- Implemented user-friendly warning messages for non-critical failures with actionable guidance
- Created 33 new Pester tests verifying critical vs non-critical behavior and error aggregation
- Established full graceful degradation across all BuildFFUVM.ps1 build phases

**Stats:**

- 14 commits
- 12 files modified
- 2,412 lines added, 120 lines modified
- 1 phase, 3 plans, 4 requirements
- 1 day (2026-01-24)

**Git range:** `be56cad` → `0f63e43`

**What's next:** Define requirements for next improvement cycle

---

## v1.9.0 Reliability Hardening (Shipped: 2026-01-24)

**Delivered:** Systematic reliability audit of all modules and scripts to bulletproof the FFU build pipeline with comprehensive error handling, actionable messages, and self-healing capabilities.

**Phases completed:** 15-25 (44 plans total)

**Key accomplishments:**

- Implemented consistent try/catch error handling across all 11 modules with specific exception types
- Added actionable error messages with remediation steps throughout the pipeline
- Created self-healing capabilities for transient failures (network, disk, service restarts)
- Built graceful degradation pattern for build phases (Invoke-BuildPhase wrapper)
- Enhanced UI with structured error display, job failure context extraction, and state recovery
- Added comprehensive config validation at load time preventing invalid builds
- Implemented WinPE script reliability for constrained environment handling
- Created 45+ test files with ~1,385 new Pester tests for reliability features

**Stats:**

- 180+ commits
- ~127,474 lines of PowerShell (total codebase)
- 11 phases, 44 plans, 44 requirements
- 2 days (2026-01-23 → 2026-01-24)

**Git range:** `5d0da52` → `efd10d6`

**What's next:** Integrate Invoke-BuildPhase into BuildFFUVM.ps1 for full graceful degradation

---

## v1.8.1 Bug Fixes (Shipped: 2026-01-20)

**Delivered:** Critical bug fixes for Windows Update preview filtering and VHDX drive letter stability discovered during v1.8.0 testing.

**Phases completed:** 11-13 (5 plans total)

**Key accomplishments:**

- Added Windows Update preview filtering with config schema, UI checkbox, and build script exclusion logic (GA releases only by default)
- Implemented config migration to add `IncludePreviewUpdates=false` default for existing configs (schema v1.0 → v1.1)
- Created `Set-OSPartitionDriveLetter` utility function with GPT type detection and retry logic for guaranteed drive letter assignment
- Enhanced Hyper-V and VMware providers with mount validation, accessibility verification, and NoteProperty drive letter attachment
- Fixed UI default initialization gap ensuring fresh launches initialize `IncludePreviewUpdates` checkbox correctly

**Stats:**

- 31 files created/modified
- 62,055 lines of PowerShell
- 3 phases, 5 plans, 7 requirements
- 1 day (2026-01-20)

**Git range:** `065910e` → `bd7c593`

**What's next:** Define requirements for next improvement cycle

---

## v1.8.0 Codebase Health (Shipped: 2026-01-20)

**Delivered:** Comprehensive codebase improvement addressing tech debt, critical bugs, security hardening, performance optimization, test coverage, and three new features for build management.

**Phases completed:** 1-10 (33 plans total)

**Key accomplishments:**

- Removed deprecated FFU.Constants properties and cleaned up Write-Host usage across modules
- Fixed Dell driver extraction hang, corporate proxy SSL inspection detection, and VHDX auto-expansion for large drivers
- Added Lenovo PSREF token caching with DPAPI encryption, SecureString password flow, and SHA-256 script integrity verification
- Optimized VHD flush by 85% using Write-VolumeCache and added event-driven Hyper-V VM monitoring
- Created 535+ Pester tests covering VM, drivers, imaging, UI handlers, cleanup, VMware, cancellation, checkpoint, and migration
- Implemented graceful build cancellation with cleanup, progress checkpoint/resume, and configuration file migration

**Stats:**

- 153 files created/modified
- 61,795 lines of PowerShell
- 10 phases, 33 plans, 26 requirements
- 4 days from 2026-01-17 to 2026-01-20

**Git range:** `0f105e1` → `a64f07c`

**What's next:** Define requirements for next improvement cycle

---
