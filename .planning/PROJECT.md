# FFU Builder - Project Context

## What This Is

FFU Builder is a PowerShell-based Windows deployment tool that creates pre-configured Windows 11 images (FFU format) deployable in under 2 minutes. It features a WPF UI, supports both Hyper-V and VMware Workstation Pro, integrates with OEM driver catalogs (Dell, HP, Lenovo, Microsoft), and includes comprehensive build management capabilities including graceful cancellation, checkpoint/resume, and configuration migration.

## Core Value

Enable rapid, reliable Windows deployment through pre-configured FFU images with minimal manual intervention.

## Current Milestone: v1.12.0 Upstream Sync — Correctness, Drivers & Device Naming

**Goal:** Selectively port the remaining high-value upstream changes (`rbalsleyMSFT/FFU` branch `UI`) into the fork's modular architecture — correctness fixes that prevent wrong/unbootable artifacts, driver-grid bug fixes, the device-naming/unattend feature family, and shell-independent UI improvements — while skipping the Fluent shell rewrite and anything that would regress fork-specific work.

**Target features:**
- Capture/boot correctness: SKU refresh after fallback, LTSC driver normalization, ADK BCDBoot, robust image-index selection
- Driver/UI bug fixes: sort-after-filter, save-scope data leak, CopyDrivers guard, Surface SKU matching, cached MS driver links, ReTrim
- Update cache + capture naming: OS-scoped cache + stale-MSU prune, param-driven naming, 8-OEM deploy-time precision
- Device-Naming / Unattend family: DeviceNamingMode framework, SerialComputerNames CSV editor, auto ComputerName, custom unattend paths, USB UniqueId migration (config-breaking, atomic)
- Shell-independent UI: ESD/ISO radios, expandable sections, ListView auto-resize, BYO app-list UI control

**Out (this milestone):** Tier-4 Fluent/sidebar shell overhaul (separate future project); regression-risk ports (host-VHDX capture, Dell name sanitization, ARM64 Office, FileBackups schema). Deferred verify-first: Win10 LTSC in-VM CU, experimental VM networking.

**Scoping basis:** `.planning/reports/upstream-sync-verdict-2026-06-25.md` (adversarial review of the 2026-06-21 audit).

## Requirements

### Validated

- Modular architecture with 11 PowerShell modules — v1.0
- WPF-based UI with background job execution — v1.0
- Hyper-V and VMware Workstation Pro support — v1.6.0
- OEM driver integration (Dell, HP, Lenovo, Microsoft) — v1.0
- Pre-flight validation system with tiered checks — v1.3.0
- Thread-safe UI/job messaging via FFU.Messaging — v1.0
- **Tech Debt Cleanup** — v1.8.0
  - Deprecated FFU.Constants properties removed
  - SilentlyContinue usage audited (254 occurrences appropriate)
  - Write-Host replaced with proper logging
  - Legacy logStreamReader removed
  - Param block coupling documented
- **Bug Fixes** — v1.8.0
  - Dell chipset driver extraction hang fixed (30s timeout)
  - Corporate proxy SSL inspection detection (Netskope/zScaler)
  - VHDX auto-expansion for large drivers (>5GB)
  - MSU unattend.xml extraction hardened
- **Security Hardening** — v1.8.0
  - Lenovo PSREF token caching with DPAPI encryption
  - SecureString password flow throughout
  - SHA-256 script integrity verification
- **Performance Optimization** — v1.8.0
  - VHD flush reduced 85% via Write-VolumeCache
  - Event-driven Hyper-V VM monitoring with CIM events
- **Test Coverage** — v1.8.0
  - 535+ Pester tests across VM, drivers, imaging, UI, cleanup, VMware
- **Build Management Features** — v1.8.0
  - Graceful build cancellation with cleanup
  - Progress checkpoint/resume capability
  - Configuration file migration between versions
- **Dependency Resilience** — v1.8.0
  - VMware vmxtoolkit fallback via vmrun/filesystem search
  - Lenovo catalogv2.xml fallback for PSREF API
  - WIMMount enhanced failure detection and recovery
- **Windows Update Preview Filtering** — v1.8.1
  - IncludePreviewUpdates config property with false default
  - UI checkbox for opt-in to preview updates
  - Build script filtering appends "-preview" to exclude GA releases
  - Config migration for existing configs (schema v1.0 → v1.1)
- **VHDX Drive Letter Stability** — v1.8.1
  - Set-OSPartitionDriveLetter utility with GPT type detection
  - Provider mount validation with retry and accessibility verification
  - NoteProperty attachment for drive letter persistence
- **Reliability Hardening** — v1.9.0
  - Consistent try/catch error handling across all 11 modules
  - Actionable error messages with remediation steps throughout pipeline
  - Self-healing for transient failures (network, disk, service restarts)
  - Graceful degradation pattern (Invoke-BuildPhase wrapper)
  - UI structured error display, job failure context extraction, state recovery
  - Config validation at load time preventing invalid builds
  - WinPE script reliability for constrained environments
  - 45+ test files with ~1,385 new Pester tests
- **Build Phase Integration** — v1.9.1
  - All BuildFFUVM.ps1 phases wrapped with Invoke-BuildPhase
  - Critical phases (VHDX, VM, FFU capture) halt on failure
  - Non-critical phases (drivers, USB, cleanup) continue on failure with warnings
  - Error aggregation across all phases with final build summary
  - 33 new Pester tests for phase integration verification
- **Smart Configuration & Bug Fixes** — v1.9.2
  - Consolidated 5 session bug fixes (VHD stability, config persistence, Winget CLI issues)
  - VM Host IP Address dropdown with network adapter context
  - VMware auto-selection logic using primary adapter with default gateway
  - Apps.iso smart staleness detection with content hashing
  - Component-based disk space estimation with pre-flight validation
  - Test-FFUHostIPAddress integration into Invoke-FFUPreflight pipeline
  - 75+ new Pester tests for network, Apps.iso, and disk estimation
- **OEM Driver Bug Fixes** — v1.9.3
  - HP driver extraction exit code 1168 handling (graceful success)
  - Dell CatalogPC.xml missing with fallback behavior
  - Structured OEM driver logging with [OEM][Model][Operation] prefixes
  - All driver operations use WriteLog (not console-only output)
- **Upstream Cherry-Pick** — v1.10.0
  - Mutex-protected Winget JSON writes preventing parallel corruption
  - App ordering enforcement and Win32 dependency resolution with deduplication
  - PPKG xcopy path quoting fix with Copy-Item fallback
  - CU skip logic (avoid 3-4GB downloads when ESD already matches)
  - ESD BITS transfer with configurable priority
  - SUBST virtual drive mapping for >260 char path reliability
  - Model name normalization removing duplicate brand prefixes
  - SystemID/MachineType extraction for HP, Dell, Lenovo
  - Dell CatalogIndexPC refactoring (10-30x download reduction)
  - Family-level driver fallback with decision trail logging
  - PE driver copy retry on transient failures
  - Driver source selection UI clarity label
  - 8 new OEM manufacturers (Acer, Dynabook, Panasonic, Samsung, Fujitsu, ASUS, MSI, Getac)
  - Multi-disk interactive selection menu for deployment
  - Empty driver folder auto-skip during deployment
  - 30-second Security Platform delay in audit mode
  - USB UniqueId identification and skip-driver option
- **USB from Existing Components** — v1.11.0
  - Config schema v1.3 with additive migration (ActiveMode + USBMode.Artifacts, 7 artifact types)
  - FFU.ArtifactScanner module — typed data contracts, Find-FFUArtifacts, Get-ArtifactMetadata (DISM + filename fallback), Test-ArtifactCompatibility
  - `-USBOnlyMode` pipeline entry — short-circuits the build and assembles a USB directly
  - UI mode toggle (Full Build / USB Mode) with USB tab, 7 artifact cards, browse dialogs, USB drive selection
  - Selective rebuild — per-artifact Reuse/Rebuild/Skip disposition drives selective per-phase rebuild; legacy Include field removed for schema-native Disposition enum
  - ⚠ Artifact discovery/validation display (DISC-01, VALID-01→04) implemented but GUI verification deferred (see next milestone)

### Active

- **v1.12.0 Upstream Sync** — see Current Milestone above; requirements in `.planning/REQUIREMENTS.md`, scoping in `.planning/reports/upstream-sync-verdict-2026-06-25.md`

**Carry-forward (not in v1.12.0 scope):**
- USB Mode GUI UAT (Phase 49 + 50) and DISC-01/VALID-01→04 verification — still deferred pending USB Mode changes (this milestone is upstream sync, not USB Mode work); re-run as one full test pass when those land
- expand.exe fails on large MSU files (fallback works — explicitly out of scope)

### Out of Scope

- Major architectural rewrites — focus on incremental improvements
- Mobile/web UI — desktop WPF application only
- Real-time monitoring dashboard — existing log monitoring adequate
- Module decomposition — deferred due to 12-15x import penalty (see docs/MODULE_DECOMPOSITION.md)

## Context

FFU Builder is a mature codebase with 98.8% PowerShell, 14 modules (11 original + FFU.Checkpoint + FFU.ConfigMigration + FFU.ArtifactScanner) totaling ~90,000+ lines of code. Through 10 milestones (v1.8.0 → v1.11.0), the project has shipped 151 plans across 50 phases. The most recent milestone, v1.11.0 USB from Existing Components, added a second UI mode that assembles a deployable USB from pre-existing artifacts and selectively rebuilds only what the user marks — skipping the 40+ minute full build. Its GUI UAT was deferred at close pending a further round of USB Mode changes.

Key files:
- `BuildFFUVM.ps1` — Core build orchestrator
- `BuildFFUVM_UI.ps1` — WPF UI host
- `ApplyFFU.ps1` — Deployment script (heavily modified in v1.10.0)
- `Orchestrator.ps1` — Deployment orchestration
- `Modules/` — 13 specialized modules
- `FFU.Common/` — Shared utilities (Winget, Downloads, Drivers)
- `FFUUI.Core/` — UI framework
- `Drivers/Providers/` — OEM driver implementations (now 12 manufacturers)

## Constraints

- **Backward Compatibility**: Config file changes must support migration
- **PowerShell 5.1+**: Must work in Windows PowerShell and PowerShell 7+
- **No Breaking Changes**: Existing workflows must continue to function
- **Test-Driven**: Changes must include or update relevant tests

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Comprehensive improvement scope | Address all concern categories in single initiative | Shipped |
| YOLO mode workflow | Fast iteration, auto-approve execution | Shipped |
| Module decomposition deferred | 12-15x import performance penalty | Documented |
| CIM events for Hyper-V | Modern standard, PowerShell Core compatible | Shipped |
| Write-VolumeCache for flush | Native cmdlet guarantees completion | ~85% faster |
| DPAPI for token caching | Automatic encryption on Windows | Shipped |
| SHA-256 for script integrity | Industry standard, native PowerShell support | Shipped |
| UI auto-resumes, CLI prompts | Appropriate for each context | Shipped |
| 7-day catalog cache TTL | Reduces network traffic for Lenovo | Shipped |
| Place IncludePreviewUpdates after UpdatePreviewCU | Logical grouping with update settings | ✓ Good |
| Apply -preview exclusion to search query | Microsoft Update Catalog supports negative keywords | ✓ Good |
| UpdatePreviewCU explicit request NOT filtered | User intent should be respected | ✓ Good |
| GPT type for OS partition detection | More reliable than labels which can change | ✓ Good |
| Default preferred drive letter to W | Consistent with New-OSPartition | ✓ Good |
| NoteProperty for drive letter attachment | Maintains backward compatibility | ✓ Good |
| Retry with exponential backoff for mounts | Handles transient disk operation failures | ✓ Good |
| Selective cherry-pick vs rebase | Keep modular architecture, port only valuable changes | ✓ Good |
| Mutex for Winget JSON writes | Prevents parallel corruption without file locks | ✓ Good |
| CatalogIndexPC for Dell drivers | 10-30x download reduction vs full catalog | ✓ Good |
| SUBST virtual drive for long paths | Avoids >260 char failures without LongPathsEnabled | ✓ Good |
| Tier 3 stubs for ASUS/MSI/Getac | Manual download guidance until catalogs available | ✓ Good |
| Multi-disk menu with Format-Table | Clear disk identification prevents accidental wipes | ✓ Good |
| Security Platform delay in Orchestrator | More maintainable than unattend.xml approach | ✓ Good |
| BusType USB detection with fallback chain | Modern disk-level detection more reliable | ✓ Good |
| Config schema first (Phase 45) in v1.11.0 | HIGH migration cost if deferred — saved configs need it | ✓ Good |
| FFU.ArtifactScanner as isolated module | Define data contract before UI/pipeline consumers | ✓ Good |
| Disposition enum replaces legacy Include flag | Schema-native per-artifact reuse/rebuild/skip | ✓ Good |
| Selective rebuild deferred to last phase (50) | Highest complexity, depends on all prior phases | ✓ Good |
| Defer USB Mode GUI UAT at v1.11.0 close | Upcoming USB Mode changes will invalidate test runs | — Pending |

---
*Last updated: 2026-06-25 — started milestone v1.12.0 Upstream Sync (Correctness, Drivers & Device Naming). Scope set via adversarial review of the 2026-06-21 upstream audit (`.planning/reports/upstream-sync-verdict-2026-06-25.md`): ~30 PORT/ADAPT items across 5 work groups; Fluent shell deferred to a separate project; regression-risk ports skipped.*
