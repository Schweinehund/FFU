# Requirements: v1.9.2 Smart Configuration & Bug Fixes

## Overview

This milestone improves UI intelligence for network configuration and optimizes build efficiency with smart Apps.iso handling.

## Requirements

### Bug Fixes (BUG)

- **BUG-01**: VHD drive letter stability after fsutil flush
  - Priority: v1
  - Committed: b492a16
  - Status: COMPLETE

- **BUG-02**: CopyOfficeConfigXML checkbox persistence in config
  - Priority: v1
  - Committed: ceb77eb
  - Status: COMPLETE

- **BUG-03**: Config migration triggering unnecessarily
  - Priority: v1
  - Committed: 6d9afde
  - Status: COMPLETE

- **BUG-04**: Winget CLI not available in elevated admin context
  - Priority: v1
  - Committed: bfd6943, f1ad60f
  - Status: COMPLETE

- **BUG-05**: Winget Source package not registered for admin users
  - Priority: v1
  - Committed: 38c897c
  - Status: COMPLETE

### Network Configuration (NET)

- **NET-01**: Enumerate host network adapters with valid IPv4 addresses
  - Priority: v1
  - Show format: `192.168.1.100 (Ethernet - Intel I219-V)`
  - Include adapter name and description for context

- **NET-02**: Replace VM Host IP text field with dropdown
  - Priority: v1
  - Include "Custom" option for manual entry
  - Auto-select best IP if none configured
  - Pre-flight warning if configured IP doesn't exist

### Apps.iso Validation (ISO)

- **ISO-01**: Create content manifest/hash for Apps folder verification
  - Priority: v1
  - Hash ALL files: Office installer, custom apps, downloads
  - Detect changes to any component

- **ISO-02**: Skip ISO rebuild when content hash matches existing
  - Priority: v1
  - Log why rebuild was skipped or what changed
  - Extend existing staleness detection

- **ISO-03**: Enhanced logging for Apps.iso decisions
  - Priority: v1
  - Show what changed and why rebuild needed
  - Clear diagnostic messages for troubleshooting

### Disk Space Estimation (DISK)

- **DISK-01**: Calculate required disk space based on enabled options
  - Priority: v1
  - Component sizes: Base ISO (~50MB), Edge (~150MB), OneDrive (~50MB), Defender (~1GB), MSRT (~150MB), Office (~4GB), Custom apps (sum)
  - Account for temp space (EstimatedSize * 1.5)

- **DISK-02**: Pre-flight disk space validation with actionable message
  - Priority: v1
  - Format: "Estimated Apps.iso: 5.2GB, Required free space: 7.8GB, Available: 15GB"
  - Fail pre-flight if insufficient space

### Logging (LOG)

- **LOG-01**: Ensure all new features follow WriteLog patterns
  - Priority: v1
  - Network adapter enumeration diagnostics
  - Disk space calculation logging
  - Content hash comparison logging

## Summary

| Category | v1 Count | Status |
|----------|----------|--------|
| Bug Fixes | 5 | COMPLETE |
| Network | 2 | Pending |
| Apps.iso | 3 | Pending |
| Disk Space | 2 | Pending |
| Logging | 1 | Pending |
| **Total** | **13** | 5 complete, 8 pending |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUG-01 | Phase 27 | Complete |
| BUG-02 | Phase 27 | Complete |
| BUG-03 | Phase 27 | Complete |
| BUG-04 | Phase 27 | Complete |
| BUG-05 | Phase 27 | Complete |
| NET-01 | Phase 28 | Pending |
| NET-02 | Phase 28 | Pending |
| ISO-01 | Phase 29 | Pending |
| ISO-02 | Phase 29 | Pending |
| ISO-03 | Phase 29 | Pending |
| DISK-01 | Phase 29 | Pending |
| DISK-02 | Phase 29 | Pending |
| LOG-01 | Phase 28, 29 | Pending |

**Coverage:**
- v1 requirements: 13 total
- Mapped to phases: 13
- Unmapped: 0 ✓

---
*Created: 2026-01-25 for milestone v1.9.2*
