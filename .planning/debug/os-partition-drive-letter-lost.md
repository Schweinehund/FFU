---
status: verifying
trigger: "OS partition drive letter becomes empty during unattend file copy verification"
created: 2026-01-22T12:00:00Z
updated: 2026-01-24T10:15:00Z
---

## Current Focus

hypothesis: After fsutil volume flush, the CIM disk instance ($disk) becomes stale and can no longer be used to query partitions. All subsequent operations that use $disk fail because it references an invalidated CIM object.
test: Replace stale $disk with fresh Get-Disk call using stored disk number
expecting: Fresh disk object can enumerate partitions and drive letter recovery succeeds
next_action: User verification needed - run FFU build with VMware hypervisor to confirm fix works

## Symptoms

expected: OS partition drive letter should remain assigned (W:) throughout unattend file copy and verification
actual:
  1. Drive letter W: assigned initially
  2. After fsutil flush, drive letter is lost (Post-flush drive letter: '')
  3. Set-OSPartitionDriveLetter fails with "Cannot bind argument to parameter 'Disk' because it is null"
  4. Emergency recovery assigns Z: but path 'Z:\Windows\Panther\Unattend\Unattend.xml' cannot be found
  5. Final error: "Cannot bind argument to parameter 'DiskPath' because it is an empty string"
errors:
  - "DEBUG: Post-flush drive letter from partition: ''"
  - "WARNING: Drive letter was released by fsutil flush (VHD destabilization)"
  - "ERROR: Failed to re-acquire drive letter: Cannot bind argument to parameter 'Disk' because it is null."
  - "ERROR: Write-through copy failed: Exception calling '.ctor' with '6' argument(s): 'Could not find a part of the path 'Z:\Windows\Panther\Unattend\Unattend.xml'.'"
  - "[Critical] Unhandled: Cannot bind argument to parameter 'DiskPath' because it is an empty string."
reproduction: Build FFU with VMware hypervisor, reaches "Finalizing VHDX" phase at ~40%, copies unattend file, then verification fails
started: Regression after initial fix - the fix didn't account for CIM instance staleness

## Eliminated

- hypothesis: Drive letter simply disappears and needs reassignment
  evidence: The previous fix attempted to call Set-OSPartitionDriveLetter but failed because $disk was null/stale, not because the drive letter was missing
  timestamp: 2026-01-24T09:30:00Z

## Evidence

- timestamp: 2026-01-22T12:00:00Z
  checked: Log output from user
  found: |
    - Line 307: "OS partition already has drive letter: W"
    - Lines 320-322: Unattend file written successfully (1395 bytes)
    - Line 323: Volume flush started at 7:27:21
    - Line 325: Drive letter empty at 7:27:22 (~1 second later)
  implication: Something between volume flush and verification removes the drive letter

- timestamp: 2026-01-22T12:10:00Z
  checked: Code analysis of BuildFFUVM.ps1 lines 3980-4220
  found: |
    - Line 4174: `$null = & fsutil volume flush "$osPartitionDriveLetter`:" 2>&1`
    - After this, the $disk CIM instance becomes stale
    - Line 4181: `$disk | Get-Partition` returns nothing because $disk is stale
    - Line 4194: Set-OSPartitionDriveLetter receives stale $disk, fails
  implication: The fsutil volume flush command causes the CIM disk instance to become invalid

- timestamp: 2026-01-24T09:45:00Z
  checked: Set-OSPartitionDriveLetter function (lines 1718-1850 in FFU.Imaging.psm1)
  found: |
    - Line 1778: Gets disk number via `$Disk.DiskNumber` or `$Disk.Number`
    - Line 1782: `$osPartition = $Disk | Get-Partition | Where-Object {...}`
    - If $Disk is stale CIM instance, Get-Partition returns nothing
    - This causes the "No OS partition found" error or null partition
    - The Mandatory parameter validation catches null $Disk before function body
  implication: The "Disk is null" error occurs because the stale CIM object evaluates to null when passed to mandatory parameter

- timestamp: 2026-01-24T09:50:00Z
  checked: Emergency recovery code (lines 4206-4221)
  found: |
    - Line 4212: `$osPartitionRefresh | Set-Partition` - but $osPartitionRefresh is null
    - Line 4181 set $osPartitionRefresh from `$disk | Get-Partition` which returned null
    - The emergency recovery tries to assign a drive letter to a null partition
    - This silently fails, so Z: is never actually assigned
    - When verification tries Z:\Windows\..., the path doesn't exist
  implication: The entire recovery chain fails because it relies on the stale $disk object

- timestamp: 2026-01-24T10:15:00Z
  checked: Fix implementation in BuildFFUVM.ps1
  found: |
    - Added $diskNumber = $disk.Number before fsutil flush (line 4173)
    - Added $freshDisk = Get-Disk -Number $diskNumber after flush (line 4189)
    - Added fallback disk discovery by path/BusType if number lookup fails (lines 4194-4198)
    - Updated $disk variable to use fresh object (line 4207)
    - All post-flush operations now use $freshDisk instead of stale $disk
    - Emergency recovery now gets fresh partition from fresh disk (line 4238)
  implication: Fix addresses root cause by refreshing the CIM disk instance after fsutil flush

## Resolution

root_cause: |
  The CIM disk instance ($disk) becomes stale after fsutil volume flush on VHD/VHDX files.
  When the volume is flushed, Windows may momentarily detach and reattach the virtual disk,
  invalidating the CIM object reference. All subsequent operations that pipe through $disk
  (e.g., `$disk | Get-Partition`) return nothing because the CIM object is no longer valid.

  The previous fix attempted to use Set-OSPartitionDriveLetter with the stale $disk, but:
  1. The stale $disk causes `$disk | Get-Partition` to return nothing
  2. Set-OSPartitionDriveLetter's mandatory -Disk parameter receives a stale object
  3. PowerShell's mandatory parameter validation treats stale CIM objects as null
  4. The emergency recovery uses $osPartitionRefresh which is also null (from same stale pipe)
  5. All paths fail, leaving no valid drive letter

fix: |
  1. Store the disk number ($disk.Number) BEFORE the fsutil flush (line 4173)
  2. After the flush, use Get-Disk -Number $diskNumber to get a FRESH CIM instance (line 4189)
  3. If Get-Disk by number fails, fall back to finding disk by path/BusType (lines 4194-4198)
  4. Update $disk variable to use fresh object for subsequent operations (line 4207)
  5. Use fresh disk object for all partition operations (lines 4211, 4225, 4238)
  6. Update emergency recovery to get fresh partition from fresh disk (line 4238)

verification:
  - PSScriptAnalyzer: No new errors (pre-existing warnings only)
  - Syntax check: File parses successfully
  - PENDING: User must run a build with VMware hypervisor to verify the fix

files_changed:
  - FFUDevelopment/BuildFFUVM.ps1 (lines 4163-4269: disk object refresh after fsutil flush)
