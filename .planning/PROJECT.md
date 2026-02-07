# FFU Builder - Project Context

## What This Is

FFU Builder is a PowerShell-based Windows deployment tool that creates pre-configured Windows 11 images (FFU format) deployable in under 2 minutes. It features a WPF UI, supports both Hyper-V and VMware Workstation Pro, integrates with OEM driver catalogs (Dell, HP, Lenovo, Microsoft), and includes comprehensive build management capabilities including graceful cancellation, checkpoint/resume, and configuration migration.

## Core Value

Enable rapid, reliable Windows deployment through pre-configured FFU images with minimal manual intervention.

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
- **Readiness Dashboard & Optional Hyper-V** — v1.11.0
  - DISM resilience formalization (startup gate, post-KB validation, graceful degradation)
  - Live pre-flight readiness dashboard on Home tab with 5 grouped categories
  - Hypervisor-conditional checks (Hyper-V optional when VMware selected)
  - One-click auto-remediation for safe issues with reboot confirmation for unsafe
  - Config-aware revalidation on hypervisor change with staleness detection
  - Diagnostics export for support scenarios
  - 48 new Pester tests, 23/23 requirements delivered

### Active

No active milestone. Next milestone TBD.

**Deferred bugs (carry forward):**
- None — expand.exe MSU fallback resolved and working well

### Out of Scope

- Major architectural rewrites — focus on incremental improvements
- Mobile/web UI — desktop WPF application only
- Real-time monitoring dashboard — existing log monitoring adequate
- Module decomposition — deferred due to 12-15x import penalty (see docs/MODULE_DECOMPOSITION.md)

## Context

FFU Builder is a mature codebase with 98.8% PowerShell, 13 modules (11 original + FFU.Checkpoint + FFU.ConfigMigration) totaling ~108,000+ lines of code. Through 10 milestones (v1.0.x → v1.11.0), the project has shipped 150 plans across 48 phases. The v1.11.0 milestone added a live pre-flight readiness dashboard, hypervisor-conditional checks, one-click auto-remediation, and config-aware revalidation with diagnostics export.

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

| Hypervisor-aware preflight | Hyper-V only checked when selected as hypervisor | ✓ Good |
| Readiness dashboard on Home tab | Most impactful user-facing improvement for build confidence | ✓ Good |
| Critical/non-critical check gating | Block on must-haves, warn on nice-to-haves | ✓ Good |
| Auto-check on launch + refresh | Immediate feedback without user action | ✓ Good |
| Auto-remediate safe fixes | Reduce friction for fixable issues | ✓ Good |
| Pipe-delimited dashboard messages | Structured data within FFU.Messaging strings | ✓ Good |
| Separate dashboard poll timer | Independent operation from build poll timer | ✓ Good |
| Cancel-and-restart for hypervisor changes | Stop in-progress job before launching new check run | ✓ Good |
| Static hypervisor-dependent check mapping | 1 Hyper-V, 5 VMware, 14 independent checks | ✓ Good |
| Export returns path not MessageBox | Separation of concerns for testability | ✓ Good |

---
*Last updated: 2026-02-06 after v1.11.0 milestone shipped*
