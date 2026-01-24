# Roadmap: FFU Builder

## Milestones

- v1.8.0 Codebase Health - Phases 1-10 (shipped 2026-01-20)
- v1.8.1 Bug Fixes - Phases 11-13 (shipped 2026-01-20)
- v1.8.3 VMware UI Settings - Phase 14 (shipped 2026-01-21)
- **v1.9.0 Reliability Hardening** - Phases 15-25 (in progress)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

### v1.9.0 Reliability Hardening

- [x] **Phase 15: FFU.Core Reliability** - Error handling, configuration, session tracking ✓
- [x] **Phase 16: FFU.Hypervisor Reliability** - Provider detection, state handling, service recovery ✓
- [ ] **Phase 17: FFU.VM Reliability** - VM lifecycle, cleanup, retry logic
- [ ] **Phase 18: FFU.Imaging Reliability** - Disk operations, partitions, mount/dismount
- [ ] **Phase 19: FFU.Media Reliability** - WinPE creation, ADK tools, ISO generation
- [ ] **Phase 20: FFU.Updates Reliability** - Update catalog, MSU handling, caching
- [ ] **Phase 21: FFU.Drivers Reliability** - OEM downloads, extraction, fallbacks
- [ ] **Phase 22: FFU.Preflight Reliability** - Pre-flight checks, remediation, WIMMount
- [ ] **Phase 23: BuildFFUVM.ps1 Reliability** - Orchestration, cancellation, cleanup
- [ ] **Phase 24: WinPE Scripts Reliability** - CaptureFFU, orchestrator, in-VM scripts
- [ ] **Phase 25: FFUUI.Core Reliability** - Error display, job failures, state consistency

## Phase Details

### Phase 15: FFU.Core Reliability
**Goal**: Harden core module with consistent error handling, actionable logging, and recovery capabilities
**Depends on**: Nothing (first phase of milestone)
**Requirements**: REL-CORE-01, REL-CORE-02, REL-CORE-03, REL-CORE-04
**Success Criteria** (what must be TRUE):
  1. All FFU.Core functions use try/catch with specific exception types
  2. Configuration errors produce messages that tell user exactly what to fix
  3. Session state can be recovered after unexpected PowerShell termination
  4. Invalid credentials trigger clear authentication guidance
**Research**: Unlikely (familiar module, established patterns)
**Plans:** 3 plans
Plans:
- [x] 15-01-PLAN.md - Error handling hardening (REL-CORE-01) ✓
- [x] 15-02-PLAN.md - Actionable configuration errors (REL-CORE-02) ✓
- [x] 15-03-PLAN.md - Session recovery and credential validation (REL-CORE-03, REL-CORE-04) ✓

### Phase 16: FFU.Hypervisor Reliability
**Goal**: Make hypervisor abstraction layer resilient to missing providers, state transitions, and service issues
**Depends on**: Phase 15 (uses FFU.Core error utilities)
**Requirements**: REL-HYP-01, REL-HYP-02, REL-HYP-03, REL-HYP-04
**Success Criteria** (what must be TRUE):
  1. Missing Hyper-V or VMware detected gracefully with installation guidance
  2. VM state queries handle "transitioning" states without false errors
  3. Switching between providers doesn't corrupt config or leave orphaned VMs
  4. Hyper-V/VMware service restart during build triggers automatic retry
**Research**: Unlikely (established provider pattern)
**Plans:** 4 plans
Plans:
- [x] 16-01-PLAN.md - Provider detection with actionable guidance (REL-HYP-01) ✓
- [x] 16-02-PLAN.md - Transient VM state handling (REL-HYP-02) ✓
- [x] 16-03-PLAN.md - Provider switching validation (REL-HYP-03) ✓
- [x] 16-04-PLAN.md - Service recovery and automatic retry (REL-HYP-04) ✓

### Phase 17: FFU.VM Reliability
**Goal**: Make VM operations robust against failures at any point with automatic cleanup and retry
**Depends on**: Phase 16 (uses hypervisor providers)
**Requirements**: REL-VM-01, REL-VM-02, REL-VM-03, REL-VM-04
**Success Criteria** (what must be TRUE):
  1. Failed VM creation logs exactly why and cleans up partial resources
  2. Ctrl+C during VM creation doesn't leave orphaned VMs, VHDs, or switches
  3. Transient disk/network errors retry automatically with backoff
  4. Running out of disk during checkpoint produces clear message and cleanup
**Research**: Unlikely (existing retry patterns to extend)
**Plans:** 4 plans
Plans:
- [ ] 17-01-PLAN.md - VM creation diagnostics and cleanup registration (REL-VM-01)
- [ ] 17-02-PLAN.md - Orphan detection and comprehensive cleanup (REL-VM-02)
- [ ] 17-03-PLAN.md - Transient error retry logic (REL-VM-03)
- [ ] 17-04-PLAN.md - Checkpoint disk space validation (REL-VM-04)

### Phase 18: FFU.Imaging Reliability
**Goal**: Make imaging operations fault-tolerant with space checks, validation, and interrupt recovery
**Depends on**: Phase 17 (uses VM module)
**Requirements**: REL-IMG-01, REL-IMG-02, REL-IMG-03, REL-IMG-04, REL-IMG-05
**Success Criteria** (what must be TRUE):
  1. Disk operations check and report space requirements before starting
  2. Partition changes verify before/after state to catch silent failures
  3. Failed FFU capture leaves VHDX intact for retry (not corrupted)
  4. Mount operations retry on "drive in use" and similar transient errors
  5. Large FFU operations can resume from checkpoint after interruption
**Research**: Likely (resume capability may need new patterns)
**Plans**: TBD

### Phase 19: FFU.Media Reliability
**Goal**: Make WinPE media creation reliable with dependency validation and clear failure remediation
**Depends on**: Phase 15 (uses FFU.Core)
**Requirements**: REL-MED-01, REL-MED-02, REL-MED-03, REL-MED-04
**Success Criteria** (what must be TRUE):
  1. WinPE creation validates ADK, tools, and paths before any work starts
  2. DISM/ADK failures include "try this to fix" guidance
  3. ISO creation estimates size and checks disk space early
  4. Architecture auto-detection validated against actual hardware capabilities
**Research**: Unlikely (existing validation patterns)
**Plans**: TBD

### Phase 20: FFU.Updates Reliability
**Goal**: Make Windows Update integration resilient to network issues, bad packages, and cache corruption
**Depends on**: Phase 15 (uses FFU.Core)
**Requirements**: REL-UPD-01, REL-UPD-02, REL-UPD-03, REL-UPD-04
**Success Criteria** (what must be TRUE):
  1. Catalog queries retry on timeout/failure with progressive backoff
  2. Corrupted MSU downloads detected and re-downloaded automatically
  3. One bad update doesn't block installation of other updates
  4. Stale or corrupted catalog cache triggers transparent refresh
**Research**: Unlikely (existing download resilience patterns)
**Plans**: TBD

### Phase 21: FFU.Drivers Reliability
**Goal**: Make OEM driver operations resilient to network issues, vendor quirks, and disk space limits
**Depends on**: Phase 15 (uses FFU.Core)
**Requirements**: REL-DRV-01, REL-DRV-02, REL-DRV-03, REL-DRV-04
**Success Criteria** (what must be TRUE):
  1. Driver downloads retry with exponential backoff on network failures
  2. Dell/HP/Lenovo extraction quirks handled without user intervention
  3. Missing OEM catalog falls back to alternative sources when available
  4. Large driver sets trigger automatic VHDX expansion before extraction
**Research**: Unlikely (existing vendor-specific patterns)
**Plans**: TBD

### Phase 22: FFU.Preflight Reliability
**Goal**: Make pre-flight validation comprehensive with clear remediation and self-healing where possible
**Depends on**: Phase 15 (uses FFU.Core)
**Requirements**: REL-PRE-01, REL-PRE-02, REL-PRE-03, REL-PRE-04
**Success Criteria** (what must be TRUE):
  1. Pre-flight catches all prerequisites before build invests significant time
  2. Failed checks tell user exactly what command/action to take
  3. WIMMount issues auto-repaired where possible (service restart, registry fix)
  4. Critical vs warning vs info checks help user prioritize what to fix
**Research**: Unlikely (existing preflight patterns)
**Plans**: TBD

### Phase 23: BuildFFUVM.ps1 Reliability
**Goal**: Make build orchestrator handle failures gracefully with complete cleanup and useful diagnostics
**Depends on**: Phases 15-22 (uses all modules)
**Requirements**: REL-BUILD-01, REL-BUILD-02, REL-BUILD-03, REL-BUILD-04, REL-BUILD-05
**Success Criteria** (what must be TRUE):
  1. Phase failures allow continuing with degraded capability where sensible
  2. Ctrl+C at any point runs full cleanup (VMs, mounts, temp files)
  3. Build can resume from last checkpoint after unexpected termination
  4. Build summary shows all errors/warnings, not just first failure
  5. Cleanup runs even on unhandled exceptions or process kill
**Research**: Likely (cleanup registration patterns need review)
**Plans**: TBD

### Phase 24: WinPE Scripts Reliability
**Goal**: Make WinPE scripts robust in constrained environment with log preservation and clear errors
**Depends on**: Phase 18 (imaging operations)
**Requirements**: REL-WINPE-01, REL-WINPE-02, REL-WINPE-03, REL-WINPE-04
**Success Criteria** (what must be TRUE):
  1. CaptureFFU validates target disk is correct before overwriting
  2. orchestrator.ps1 detects missing scripts/configs with specific messages
  3. Logs copied to persistent location before VM shutdown for debugging
  4. Scripts handle low memory/disk WinPE environment without crashing
**Research**: Likely (WinPE environment constraints need research)
**Plans**: TBD

### Phase 25: FFUUI.Core Reliability
**Goal**: Make UI display errors clearly and maintain consistent state after failures
**Depends on**: Phase 15 (uses FFU.Core patterns)
**Requirements**: REL-UI-01, REL-UI-02, REL-UI-03, REL-UI-04
**Success Criteria** (what must be TRUE):
  1. Error dialogs show what went wrong and what user can do about it
  2. Background job failures surface with full context, not "Job failed"
  3. Errors don't leave UI in stuck state (progress bars reset, buttons re-enable)
  4. Invalid config detected at load time, not after build starts
**Research**: Unlikely (existing UI error patterns)
**Plans**: TBD

## Progress

**Execution Order:**
Phases 15-25 execute sequentially, with some parallelization possible for independent modules (19-22 could run in parallel after 15).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 15. FFU.Core Reliability | 3/3 | Complete | 2026-01-23 |
| 16. FFU.Hypervisor Reliability | 4/4 | Complete | 2026-01-24 |
| 17. FFU.VM Reliability | 0/4 | Planned | - |
| 18. FFU.Imaging Reliability | 0/TBD | Not started | - |
| 19. FFU.Media Reliability | 0/TBD | Not started | - |
| 20. FFU.Updates Reliability | 0/TBD | Not started | - |
| 21. FFU.Drivers Reliability | 0/TBD | Not started | - |
| 22. FFU.Preflight Reliability | 0/TBD | Not started | - |
| 23. BuildFFUVM.ps1 Reliability | 0/TBD | Not started | - |
| 24. WinPE Scripts Reliability | 0/TBD | Not started | - |
| 25. FFUUI.Core Reliability | 0/TBD | Not started | - |

---
*Created: 2026-01-23 for v1.9.0 Reliability Hardening*
