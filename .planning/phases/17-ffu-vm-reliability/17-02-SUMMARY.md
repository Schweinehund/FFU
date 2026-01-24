---
phase: 17-ffu-vm-reliability
plan: 02
title: "Orphan Detection and Cleanup"
subsystem: ffu.vm
tags: [orphan-detection, cleanup, vmware, checkpoint, hyper-v]

dependency-graph:
  requires: [17-01]
  provides: [Get-OrphanedVMResources, Enhanced Remove-FFUVM]
  affects: [builds-with-failures, ctrl-c-interruption]

tech-stack:
  added: []
  patterns: [orphan-scanning, safe-lock-removal, checkpoint-cleanup]

file-tracking:
  key-files:
    created: []
    modified:
      - FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1
      - FFUDevelopment/Modules/FFU.VM/FFU.VM.psd1
      - Tests/Unit/FFU.VM.Reliability.Tests.ps1

decisions:
  - "Scan for orphans by _FFU- prefix for VMs, guardians, certificates"
  - "Check for vmware-vmx process before removing lock directories"
  - "Cross-reference AVHDX files with Get-VMSnapshot to find true orphans"
  - "Return structured PSCustomObject with all orphan types and cleanup actions"
  - "ScanOnly switch to report without generating cleanup commands"

metrics:
  duration: "~20 minutes"
  completed: "2026-01-24"
---

# Phase 17 Plan 02: Orphan Detection and Cleanup Summary

**REL-VM-02: Comprehensive orphan resource detection and cleanup**

## One-liner

Added Get-OrphanedVMResources to detect 6 orphan types (VMs, VHDXs, guardians, certs, locks, checkpoints) and enhanced Remove-FFUVM with VMware lock and AVHDX cleanup.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Add Get-OrphanedVMResources function | bc48e6c |
| 2 | Enhance Remove-FFUVM with lock and checkpoint cleanup | 4b89573 |
| 3 | Add Pester tests for REL-VM-02 | 371ef9a |

## Implementation Details

### Get-OrphanedVMResources Function

Scans for 6 types of orphaned resources:

1. **Orphaned Hyper-V VMs** - VMs with names starting with `_FFU-`
2. **Orphaned VHDX files** - VHDXs in VM folder not attached to any VM
3. **Orphaned HGS Guardians** - Guardians with names starting with `_FFU-`
4. **Orphaned certificates** - Certs in Shielded VM store matching `*_FFU-*`
5. **VMware lock directories** - `*.lck` directories (when `-IncludeVMware`)
6. **Orphaned checkpoint files** - `*.avhdx` files not part of active snapshots

Returns structured PSCustomObject:
```powershell
@{
    OrphanedVMs             = @()    # VM names
    OrphanedVHDX            = @()    # File paths
    OrphanedGuardians       = @()    # Guardian names
    OrphanedCertificates    = @()    # Cert PSPaths
    OrphanedLockFiles       = @()    # Lock directory paths
    OrphanedCheckpointFiles = @()    # AVHDX file paths
    TotalOrphans            = 0      # Total count
    CleanupActions          = @()    # Cleanup commands (if not -ScanOnly)
}
```

### Remove-FFUVM Enhancements

Added two new cleanup sections after HGS Guardian cleanup:

1. **VMware lock file cleanup**
   - Scans for `*.lck` directories in VMPath
   - Checks for running `vmware-vmx` process before removal
   - Skips locks that are in use by active processes

2. **Orphaned checkpoint file cleanup**
   - Scans for `*.avhdx` files in VMPath
   - Cross-references with `Get-VMSnapshot` to identify true orphans
   - Only removes AVHDX files not part of active checkpoints

Both sections have comprehensive error handling with try/catch and WriteLog.

## Tests

8 new tests added to `FFU.VM.Reliability.Tests.ps1` for REL-VM-02:

- Get-OrphanedVMResources function existence and export
- Parameter validation (FFUDevelopmentPath, IncludeVMware, ScanOnly)
- TotalOrphans property in return object
- Lock file cleanup logic presence (.lck directories)
- vmware-vmx process check before lock removal
- AVHDX cleanup logic presence

All 42 tests in the test file pass.

## Version Updates

| Component | Version |
|-----------|---------|
| FFU.VM | 1.0.9 |

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

- [x] `Get-OrphanedVMResources` function exists and is exported
- [x] `Get-OrphanedVMResources` detects VMs, VHDXs, guardians, certs, locks, and AVHDX
- [x] `Remove-FFUVM` includes VMware lock file cleanup
- [x] `Remove-FFUVM` includes orphaned AVHDX cleanup
- [x] Pester tests pass for all REL-VM-02 scenarios
- [x] Module imports without errors

## Next Phase Readiness

Ready for Phase 17 Plan 03 (if any remaining plans in phase).

---
*Summary created: 2026-01-24*
