---
phase: 24
plan: 01
subsystem: WinPE-CaptureFFU
tags: [disk-validation, winpe, safety, capture, reliability]

dependency-graph:
  requires:
    - Phase 24 research (disk validation patterns)
  provides:
    - Test-CaptureTargetDisk function for validating target disk before FFU capture
    - Protection against accidental capture of wrong disk (USB, physical hardware)
  affects:
    - CaptureFFU.ps1 execution flow
    - WinPE capture media behavior

tech-stack:
  added: []
  patterns:
    - WMI/CIM Win32_DiskDrive query for WinPE compatibility
    - PSCustomObject return with Valid/DiskInfo/Error properties
    - Fail-fast validation before destructive operations

file-tracking:
  created:
    - Tests/Unit/CaptureFFU.DiskValidation.Tests.ps1 (508 lines, 21 tests)
  modified:
    - FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1 (added Test-CaptureTargetDisk function + integration)

decisions:
  - id: wmi-disk-query
    context: "How to query disk information in WinPE"
    choice: "Get-CimInstance Win32_DiskDrive"
    rationale: "WMI/CIM is available in WinPE; Get-Disk from Storage module is not"

  - id: virtual-disk-pattern-match
    context: "How to identify Hyper-V/VMware virtual disks"
    choice: "Model -notmatch 'Virtual|VMware'"
    rationale: "Both Hyper-V (Microsoft Virtual Disk) and VMware (VMware Virtual disk) contain these keywords"

  - id: fail-fast-before-diskpart
    context: "When to validate disk before capture"
    choice: "Before diskpart drive letter assignment"
    rationale: "Earliest point where disk manipulation begins; fail before any partition changes"

metrics:
  duration: "10 minutes"
  completed: 2026-01-24
---

# Phase 24 Plan 01: CaptureFFU Disk Validation Summary

**One-liner:** Test-CaptureTargetDisk function validates PhysicalDrive0 is a Hyper-V/VMware virtual disk before DISM capture, preventing accidental capture of wrong disks.

## What Was Built

Implemented REL-WINPE-01 requirement for target disk validation before FFU capture. Previously, CaptureFFU.ps1 would always capture PhysicalDrive0 without verification, risking accidental capture of USB drives or physical hardware if boot order changed.

### Function Added

**Test-CaptureTargetDisk**

| Property | Description |
|----------|-------------|
| Purpose | Validates target disk exists and is virtual before FFU capture |
| WinPE Compatible | Uses Get-CimInstance Win32_DiskDrive (not Get-Disk) |
| Returns | PSCustomObject with Valid, DiskInfo, Error properties |

### Validation Checks

1. **Disk Existence**: Verifies requested disk number exists
2. **Virtual Disk Model**: Confirms disk model contains "Virtual" or "VMware"
3. **Error Messages**: Provides actionable errors with available disk list

### Integration Point

Disk validation is called BEFORE diskpart drive letter assignment:

```
Network connection -> Disk validation -> diskpart -> Registry load -> DISM capture
```

If validation fails, script aborts with clear safety message before any disk manipulation.

### Error Message Examples

**Physical disk detected:**
```
Disk 0 is NOT a virtual disk (Model: Samsung SSD 970 EVO).
FFU capture requires a Hyper-V or VMware virtual disk to prevent accidental data loss on physical hardware.
```

**Missing disk:**
```
Disk 5 not found. Available disks: \\.\PHYSICALDRIVE0 (Microsoft Virtual Disk), \\.\PHYSICALDRIVE1 (USB Storage)
```

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 1617e4e | feat | Add disk validation before FFU capture (Tasks 1-2) |
| f266bd3 | test | Add Pester tests for disk validation (Task 3) |

## Test Coverage

21 comprehensive Pester tests in `Tests/Unit/CaptureFFU.DiskValidation.Tests.ps1`:

- **Virtual Disk Validation**: Hyper-V, VMware, variant names, case-insensitive matching (5 tests)
- **Physical Disk Rejection**: SSD, HDD, USB drives, safety warnings (5 tests)
- **Missing Disk Handling**: Non-existent disk, available disk list (3 tests)
- **Error Handling**: WMI failures, original error preservation (2 tests)
- **Default Parameters**: Disk 0 default behavior (1 test)
- **DiskInfo Property**: Valid disk details, physical disk details (2 tests)
- **Integration**: Function existence, call order, WinPE compatibility (3 tests)

## Deviations from Plan

None - plan executed exactly as written.

## Security Rationale

FFU capture writes the entire disk to a file. Without validation:
- USB drives could be captured if boot order changes
- Physical host disks could be exposed if WinPE boots on wrong hardware
- Captured FFU images could contain unexpected/sensitive data

By requiring virtual disk model validation, we ensure only intended Hyper-V/VMware VMs are captured.

## Next Phase Readiness

Plan 24-02 (Orchestrator Dependency Detection) is independent and can proceed.

### Blockers

None.

### Dependencies Met

- CaptureFFU.ps1 modifications complete
- Test coverage validates functionality
- WinPE compatibility confirmed (uses WMI/CIM, not Storage module)
