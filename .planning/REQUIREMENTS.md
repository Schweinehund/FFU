# Requirements: FFU Builder

**Defined:** 2026-03-12
**Core Value:** Enable rapid, reliable Windows deployment through pre-configured FFU images with minimal manual intervention

## v1.11.0 Requirements

Requirements for USB from Existing Components milestone. Each maps to roadmap phases.

### UI Mode

- [x] **UIMODE-01**: User can toggle between "Full Build" and "USB Mode" via a mode switch in the UI
- [x] **UIMODE-02**: Build-specific controls (VM settings, Windows version, etc.) hide or disable when USB Mode is active
- [x] **UIMODE-03**: USB Mode panel displays artifact-focused controls when active

### Artifact Discovery

- [ ] **DISC-01**: USB Mode auto-detects all deployable artifacts from FFUDevelopmentPath on activation (FFU, boot ISO, drivers, PPKG, unattend, Autopilot, Apps.iso)
- [x] **DISC-02**: User can browse to arbitrary file/folder paths for each artifact type
- [ ] **DISC-03**: User-specified artifact paths persist across sessions via config

### Artifact Validation

- [ ] **VALID-01**: USB Mode displays found/missing status for each artifact with path and file size
- [ ] **VALID-02**: USB Mode extracts and displays FFU metadata (Windows version, SKU, architecture) via DISM
- [ ] **VALID-03**: USB Mode cross-validates artifact compatibility (architecture mismatch warning between FFU and boot ISO)
- [ ] **VALID-04**: USB Mode displays staleness indicator per artifact (age relative to current date)

### USB Assembly

- [x] **USB-01**: USB Mode blocks USB creation if WinPE deployment ISO is missing with actionable message
- [ ] **USB-02**: USB Mode reuses existing USB drive detection and selection
- [ ] **USB-03**: User can select which artifacts to include on the USB (per-artifact checkboxes)
- [x] **USB-04**: USB Mode assembles selected artifacts into deployable USB via existing New-DeploymentUSB

### Selective Rebuild

- [ ] **REBUILD-01**: User can mark each artifact as reuse, rebuild, or skip
- [ ] **REBUILD-02**: Pipeline executes only the build phases needed for artifacts marked "rebuild"
- [ ] **REBUILD-03**: Rebuilt artifacts are combined with reused artifacts for final USB assembly

### Configuration

- [x] **CONFIG-01**: Config schema extended with USB Mode fields (artifact paths, dispositions)
- [x] **CONFIG-02**: Config migration adds USB Mode defaults for existing configs

## Future Requirements

### Selective Rebuild Enhancements

- **REBUILD-04**: Saved USB Mode profiles (named configurations per deployment scenario)
- **REBUILD-05**: Artifact version history with rollback selection

## Out of Scope

| Feature | Reason |
|---------|--------|
| Cloud/network artifact sources | Scope explosion — authentication, network errors, partial downloads; users should copy locally first |
| Auto-rebuild stale artifacts | Silently triggers 40+ minute pipeline without user intent; staleness indicator + explicit choice is safer |
| USB Mode without WinPE ISO | Produces non-bootable drive; ApplyFFU.ps1 directly is the right tool for pre-formatted drives |
| Merge/combine multiple FFUs | Already handled by existing CopyAdditionalFFUFiles mechanism |
| Standalone script enhancement | USBImagingToolCreator.ps1 improvements deferred — UI-first approach |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| UIMODE-01 | Phase 48 | Complete |
| UIMODE-02 | Phase 48 | Complete |
| UIMODE-03 | Phase 48 | Complete |
| DISC-01 | Phase 46 | Pending |
| DISC-02 | Phase 49 | Complete |
| DISC-03 | Phase 49 | Pending |
| VALID-01 | Phase 46 | Pending |
| VALID-02 | Phase 46 | Pending |
| VALID-03 | Phase 46 | Pending |
| VALID-04 | Phase 46 | Pending |
| USB-01 | Phase 47 | Complete |
| USB-02 | Phase 49 | Pending |
| USB-03 | Phase 49 | Pending |
| USB-04 | Phase 47 | Complete |
| REBUILD-01 | Phase 50 | Pending |
| REBUILD-02 | Phase 50 | Pending |
| REBUILD-03 | Phase 50 | Pending |
| CONFIG-01 | Phase 45 | Complete |
| CONFIG-02 | Phase 45 | Complete |

**Coverage:**
- v1.11.0 requirements: 19 total
- Mapped to phases: 19
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-12*
*Last updated: 2026-03-12 after roadmap creation — all 19 requirements mapped*
