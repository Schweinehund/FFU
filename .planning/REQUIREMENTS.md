# Requirements: v1.9.3 OEM Driver Bug Fixes

**Defined:** 2026-01-25
**Core Value:** Enable rapid, reliable Windows deployment through pre-configured FFU images with minimal manual intervention.

## v1 Requirements

Requirements for v1.9.3 release. Each maps to roadmap phases.

### HP Driver Fix (HP)

- [x] **HP-01**: HP driver extraction handles exit code 1168 without failing the build
- [x] **HP-02**: HP driver extraction logs the specific exit code and remediation steps when extraction fails
- [x] **HP-03**: Pester tests verify HP driver extraction exit code 1168 handling
- [x] **HP-04**: Pester tests verify HP extraction produces actionable error messages

### Dell Driver Fix (DELL)

- [x] **DELL-01**: Dell driver download handles missing CatalogPC.xml without failing the build
- [x] **DELL-02**: Dell catalog lookup logs the failure reason and fallback action taken
- [x] **DELL-03**: Pester tests verify Dell CatalogPC.xml missing scenario handling
- [x] **DELL-04**: Pester tests verify Dell catalog fallback behavior

### OEM Driver Logging (LOG)

- [x] **LOG-01**: OEM driver selection decisions logged to FFUDevelopment.log (not just console)
- [x] **LOG-02**: OEM driver download progress and outcomes logged to FFUDevelopment.log
- [x] **LOG-03**: OEM driver extraction/decompression steps logged to FFUDevelopment.log
- [x] **LOG-04**: OEM driver injection results logged to FFUDevelopment.log
- [x] **LOG-05**: All OEM driver error paths log actionable remediation messages
- [x] **LOG-06**: Pester tests verify driver logging goes to WriteLog (not Write-Host/Console)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Driver Resilience

- **DRVR-01**: expand.exe large MSU fallback improved (currently works but not optimal)
- **DRVR-02**: Retry logic for transient OEM catalog download failures

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| expand.exe large MSU fix | Fallback works — explicitly deferred per PROJECT.md |
| New OEM vendor support | Current vendors sufficient per PROJECT.md |
| Driver caching/reuse across builds | Optimization — not a bug fix milestone |
| Major architectural rewrites | Focus on incremental improvements per PROJECT.md |

## Traceability

Which phases cover which requirements. Updated by create-roadmap.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HP-01 | Phase 31 | Complete |
| HP-02 | Phase 31 | Complete |
| HP-03 | Phase 31 | Complete |
| HP-04 | Phase 31 | Complete |
| DELL-01 | Phase 32 | Complete |
| DELL-02 | Phase 32 | Complete |
| DELL-03 | Phase 32 | Complete |
| DELL-04 | Phase 32 | Complete |
| LOG-01 | Phase 33 | Complete |
| LOG-02 | Phase 33 | Complete |
| LOG-03 | Phase 33 | Complete |
| LOG-04 | Phase 33 | Complete |
| LOG-05 | Phase 33 | Complete |
| LOG-06 | Phase 33 | Complete |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-01-25*
*Last updated: 2026-01-27 — LOG-01..06 complete (Phase 33), all v1 requirements complete*
