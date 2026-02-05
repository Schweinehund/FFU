---
status: diagnosed
trigger: "After copying unattend.xml with write-through and flushing the volume, the disk number becomes null and the disk path becomes empty string, causing the build to fail."
created: 2026-01-27T00:00:00Z
updated: 2026-01-27T00:30:00Z
---

## Current Focus

hypothesis: CONFIRMED - The fsutil volume flush at line 4214 is unnecessary because WriteThrough + Flush(true) at lines 4184/4188 already guarantee data persistence. The fsutil flush destabilizes the VHD CIM state, and the recovery code at line 4222 fails because Get-Disk parameter validation errors are terminating (bypass -ErrorAction). The entire flush-and-recovery section (lines 4196-4302) is over-engineered defense for a problem that doesn't exist when WriteThrough is used correctly.
test: Code analysis of data persistence guarantees vs fsutil side effects
expecting: WriteThrough + Flush(true) provides full cache bypass + disk flush, making fsutil redundant
next_action: Present options to user

## Symptoms

expected: After writing unattend.xml with WriteThrough and flushing the volume, the OS partition should still be accessible at drive letter W: with disk number 2, and the build should continue normally.
actual: The flush operation causes the disk number to become null and the disk path to become an empty string. Error chain shows disk number is 2 before flush but null after.
errors:
  - "Cannot validate argument on parameter 'Number'. The argument is null."
  - "Cannot bind argument to parameter 'DiskPath' because it is an empty string."
reproduction: Run a full FFU build through the UI with VMware hypervisor. Fails during the unattend.xml write-through-and-flush step.
started: After flush was added to resolve a previous unattend.xml copy reliability issue.

## Eliminated

- hypothesis: The $diskNumber variable is not being stored correctly before flush
  evidence: Log shows "Storing disk number for post-flush recovery: 2" - variable is correctly set at line 4206
  timestamp: 2026-01-27T00:15:00Z

- hypothesis: The recovery code at line 4222 (Get-Disk -Number) correctly handles the null case
  evidence: Get-Disk -Number with -ErrorAction SilentlyContinue does NOT suppress parameter validation errors. When $diskNumber is null (possibly due to CIM/pipeline scope issues after fsutil), the [ValidateNotNull()] on Get-Disk's -Number parameter throws a terminating error that bypasses -ErrorAction.
  timestamp: 2026-01-27T00:20:00Z

## Evidence

- timestamp: 2026-01-27T00:05:00Z
  checked: BuildFFUVM.ps1 lines 4161-4355 (unattend copy with write-through and flush)
  found: |
    The code uses TWO layers of flush:
    1. .NET FileStream with FileOptions.WriteThrough + Flush(true) at lines 4184/4188
    2. fsutil volume flush at line 4214
    The first layer already guarantees data is written to disk. The second is redundant and destructive.
  implication: The fsutil flush is unnecessary for data integrity and is the sole cause of the drive letter/disk instability

- timestamp: 2026-01-27T00:08:00Z
  checked: .NET documentation on FileOptions.WriteThrough and Flush(true)
  found: |
    - FileOptions.WriteThrough = FILE_FLAG_WRITE_THROUGH, bypasses OS cache for each write
    - Flush(true) flushes both FileStream internal buffer AND OS file system cache
    - Combined: WriteThrough + Flush(true) guarantees data is on physical disk
    - The fsutil volume flush after this is redundant
  implication: No data integrity benefit from the fsutil flush

- timestamp: 2026-01-27T00:10:00Z
  checked: fsutil calls at lines 4213-4214
  found: |
    Line 4213: fsutil file seteof $unattendDest $sourceContent.Length - sets end-of-file marker
    Line 4214: fsutil volume flush "$osPartitionDriveLetter`:" - flushes entire volume
    The volume-level flush on a file-backed virtual disk (VHD) causes Windows to destabilize
    the CIM disk instance, potentially causing disk number and drive letter associations to
    become stale/null.
  implication: fsutil volume flush on VHD volumes causes CIM object staleness and drive letter loss

- timestamp: 2026-01-27T00:12:00Z
  checked: Previous debug session (os-partition-drive-letter-lost.md)
  found: |
    Previous fix (commit b492a16) attempted to solve this by:
    1. Storing disk number before flush
    2. Getting fresh CIM instance after flush
    3. Recovery logic for drive letter reassignment
    But the current error shows this recovery still fails because Get-Disk -Number $diskNumber
    with a null value throws a terminating error even with -ErrorAction SilentlyContinue.
    The previous fix treated the symptom (stale CIM object) not the cause (unnecessary fsutil flush).
  implication: The recovery-after-flush approach is inherently fragile

- timestamp: 2026-01-27T00:15:00Z
  checked: Invoke-VerifiedVolumeFlush in FFU.Imaging.psm1 (lines 1173-1266)
  found: |
    This function is used ONLY during Dismount-ScratchVhd (line 1452), NOT during unattend copy.
    The unattend copy code at BuildFFUVM.ps1 line 4214 uses a SEPARATE inline fsutil call.
    Two different flush mechanisms exist: one in FFU.Imaging for dismount, one inline for unattend.
  implication: The inline fsutil flush in BuildFFUVM.ps1 was hand-written specifically for the unattend copy path

- timestamp: 2026-01-27T00:18:00Z
  checked: Dismount-ScratchVhd in FFU.Imaging.psm1 (lines 1416-1500)
  found: |
    The dismount function (called at line 4387) ALSO flushes via Invoke-VerifiedVolumeFlush.
    So if we remove the inline fsutil flush from the unattend copy, the data will still be
    flushed when Dismount-ScratchVhd is called immediately after (line 4387).
    This provides a TRIPLE guarantee: WriteThrough, Flush(true), and dismount-time flush.
  implication: Even removing the inline fsutil flush leaves data integrity fully protected

- timestamp: 2026-01-27T00:20:00Z
  checked: The fsutil file seteof call at line 4213
  found: |
    fsutil file seteof $unattendDest $sourceContent.Length
    This is unnecessary when the file was just written with exact content via FileStream.
    The file size is already correct. seteof is typically used for pre-allocation or truncation,
    neither of which applies here. This call may also contribute to destabilization.
  implication: The seteof call is also redundant and potentially harmful

- timestamp: 2026-01-27T00:25:00Z
  checked: Lines 4196-4302 (recovery code after flush)
  found: |
    ~107 lines of recovery code exist solely to handle the drive letter loss caused by fsutil flush.
    This includes: CIM refresh, drive letter re-acquisition, emergency fallback, error handling.
    All of this code is only needed because of the fsutil flush. If the flush is removed,
    all 107 lines of recovery code become dead code.
  implication: Removing the flush dramatically simplifies the code

## Resolution

root_cause: |
  TWO redundant fsutil calls at BuildFFUVM.ps1 lines 4213-4214 destabilize the VHD mount state:
  1. `fsutil file seteof` (line 4213) - unnecessary, file size is already correct
  2. `fsutil volume flush` (line 4214) - unnecessary, WriteThrough + Flush(true) already persisted data

  These were added to solve a previous unattend.xml copy reliability problem, but the actual fix
  (WriteThrough at line 4184 + Flush(true) at line 4188) already solved that problem. The fsutil
  calls are belt-and-suspenders that turned out to be a noose.

  The recovery code (lines 4219-4302, ~84 lines) attempts to handle the drive letter loss but
  fails because PowerShell parameter validation errors on Get-Disk -Number are terminating and
  bypass -ErrorAction SilentlyContinue.

fix: See options below
verification:
files_changed: []
