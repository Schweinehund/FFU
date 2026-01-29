# Requirements: v1.10.0 Upstream Cherry-Pick

**Defined:** 2026-01-28
**Core Value:** Enable rapid, reliable Windows deployment through pre-configured FFU images with minimal manual intervention.

## v1 Requirements

Requirements for v1.10.0 release. Each maps to roadmap phases.

### Critical Bug Fixes (BUGFIX)

- [x] **BUGFIX-01**: Parallel Winget app updates complete without JSON corruption (file locking/mutex on WinGetWin32Apps.json)
- [x] **BUGFIX-02**: PPKG files with spaces in filenames copy successfully during deployment and USB creation (xcopy quoting)
- [x] **BUGFIX-03**: MSI installers with spaces in paths execute without "file not found" errors (path quoting)
- [x] **BUGFIX-04**: Build skips CU download when ESD image version already matches or exceeds available CU version

### Winget Improvements (WINGET)

- [x] **WINGET-01**: Apps install in exact order specified in AppList.json (not hash/alphabetical order)
- [x] **WINGET-02**: Win32 app dependencies automatically resolved and deduplicated before installation

### Download Improvements (DL)

- [x] **DL-01**: ESD downloads use BITS transfer for reliability (Start-BitsTransferWithRetry)

### Path Reliability (PATH)

- [x] **PATH-01**: SUBST virtual drive mapped during driver operations to prevent long path (>260 char) failures

### Deployment Improvements (DEPLOY)

- [ ] **DEPLOY-01**: Multiple physical disks present an interactive selection menu instead of defaulting to disk 0
- [ ] **DEPLOY-02**: 30-second delay in audit mode allows Windows Security Platform to initialize before app installations
- [ ] **DEPLOY-03**: Empty driver folders automatically skipped during deployment with log message

### Driver Improvements (DRV)

- [ ] **DRV-01**: Dell driver download uses CatalogIndexPC for efficient driver package selection
- [x] **DRV-02**: Model names normalized to remove duplicate brand prefixes (e.g., "Dell Dell Latitude" → "Dell Latitude")
- [x] **DRV-03**: SystemID extraction from BIOS/WMI works correctly across HP, Dell, and Lenovo
- [ ] **DRV-04**: 8 new OEM manufacturers supported (Panasonic, Fujitsu, Getac, Dynabook, Samsung, Acer, ASUS, MSI)
- [ ] **DRV-05**: Generic/family-level driver fallback attempted when no exact model match found
- [ ] **DRV-06**: PE driver copy operations retry on transient failures with logging
- [ ] **DRV-07**: Driver source selection UI clearly indicates which source is used and why

### Nice-to-Have (NICE)

- [ ] **NICE-01**: USB drive identification uses UniqueId instead of SerialNumber for reliability
- [ ] **NICE-02**: Deployment supports "skip driver installation" option for driver-free scenarios

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
| Threads parameter (upstream) | We deprecated this; skip |
| Refactored cleanup into shared module | We already have FFU.Common.Cleanup.psm1 |
| Refactored app download for UI/CLI reuse | We already share via FFU.Common.Winget.psm1 |
| Major architectural rewrites | Focus on selective cherry-pick per upstream evaluation |

## Traceability

Which phases cover which requirements. Updated by create-roadmap.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUGFIX-01 | Phase 34 | Complete |
| BUGFIX-02 | Phase 35 | Complete |
| BUGFIX-03 | Phase 34 | Complete |
| BUGFIX-04 | Phase 36 | Complete |
| WINGET-01 | Phase 37 | Complete |
| WINGET-02 | Phase 37 | Complete |
| DL-01 | Phase 36 | Complete |
| PATH-01 | Phase 38 | Complete |
| DEPLOY-01 | Phase 43 | Pending |
| DEPLOY-02 | Phase 43 | Pending |
| DEPLOY-03 | Phase 43 | Pending |
| DRV-01 | Phase 40 | Pending |
| DRV-02 | Phase 39 | Complete |
| DRV-03 | Phase 39 | Complete |
| DRV-04 | Phase 42 | Pending |
| DRV-05 | Phase 41 | Pending |
| DRV-06 | Phase 41 | Pending |
| DRV-07 | Phase 41 | Pending |
| NICE-01 | Phase 43 | Pending |
| NICE-02 | Phase 43 | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0 ✓

---
*Requirements defined: 2026-01-28*
