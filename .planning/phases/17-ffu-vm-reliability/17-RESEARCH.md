# Phase 17: FFU.VM Reliability - Research

**Researched:** 2026-01-24
**Domain:** VM lifecycle management, cleanup, retry logic for Hyper-V and VMware
**Confidence:** HIGH

## Summary

This phase hardens the FFU.VM module to handle failures at any point in the VM lifecycle with proper cleanup and retry logic. The research focuses on:

1. **Failure diagnostics** - Capturing and reporting exactly why VM creation failed
2. **Cleanup of partial resources** - Handling Ctrl+C and orphaned VMs, VHDXs, and switches
3. **Transient error retry** - Disk busy, file locked, network timeout patterns
4. **Disk space exhaustion** - Checkpoint/snapshot operations under low disk conditions

The module already has good structure from FFU.VM v1.0.8, and Phase 16 established retry patterns (`Invoke-WithHypervisorRetry`, `Test-HypervisorService`) that can be extended. FFU.Core provides the cleanup registration system (`Register-CleanupAction`, `Invoke-FailureCleanup`) that should be leveraged.

**Primary recommendation:** Extend existing patterns from Phase 15-16 rather than creating new ones. Add pre-validation for disk space before checkpoint operations.

## Standard Stack

The established patterns for this domain are already in the codebase:

### Core Patterns to Extend

| Pattern | Location | Purpose | Why Standard |
|---------|----------|---------|--------------|
| Cleanup Registration | FFU.Core | Register resources for automatic cleanup | LIFO cleanup on failure |
| Invoke-WithHypervisorRetry | FFU.Hypervisor | Retry with exponential backoff | Handles service interruptions |
| Test-IsServiceError | FFU.Hypervisor | Classify transient vs permanent errors | Avoid retrying permanent failures |
| Invoke-WithErrorHandling | FFU.Core | Generic retry wrapper | For non-hypervisor operations |
| Invoke-WithCleanup | FFU.Core | try/finally pattern | Guaranteed cleanup |

### Supporting Functions

| Function | Module | Purpose | When to Use |
|----------|--------|---------|-------------|
| Register-VMCleanup | FFU.Core | Register Hyper-V VM cleanup | After New-VM succeeds |
| Register-VHDXCleanup | FFU.Core | Register mounted VHDX cleanup | After Mount-VHD |
| Register-TempFileCleanup | FFU.Core | Register temp file cleanup | For VM config files |
| Invoke-FailureCleanup | FFU.Core | Execute all registered cleanups | In catch blocks |
| WriteLog | FFU.Core | Thread-safe logging | All error messages |

### No New Dependencies Required

The existing module structure provides everything needed:
- FFU.VM depends on FFU.Core and FFU.Hypervisor
- FFU.Core provides error handling and cleanup registration
- FFU.Hypervisor provides retry logic and service checks

## Architecture Patterns

### Pattern 1: Progressive Resource Cleanup

**What:** Register cleanup actions immediately after each resource creation, unregister after successful completion.

**When to use:** Any function that creates multiple related resources (VM, VHDX, switch, user account).

**Example (from existing codebase):**
```powershell
# Source: FFU.Core Register-CleanupAction pattern
$vmCreated = $false
$vhdxMounted = $false

try {
    # Create VM
    $VM = New-VM -Name $VMName -Path $VMPath -ErrorAction Stop
    $vmCreated = $true
    $cleanupId = Register-VMCleanup -VMName $VMName

    # Mount VHDX
    Mount-VHD -Path $VHDXPath -ErrorAction Stop
    $vhdxMounted = $true
    $vhdxCleanupId = Register-VHDXCleanup -VHDXPath $VHDXPath

    # ... more operations ...

    # Success - unregister cleanups
    Unregister-CleanupAction -CleanupId $cleanupId
    Unregister-CleanupAction -CleanupId $vhdxCleanupId
}
catch {
    # Cleanup runs automatically via Invoke-FailureCleanup in outer handler
    throw
}
```

### Pattern 2: Transient Error Classification

**What:** Classify errors as transient (retryable) or permanent (fail fast) based on error message patterns.

**When to use:** Before deciding whether to retry an operation.

**Example (from FFU.Hypervisor):**
```powershell
# Source: FFU.Hypervisor Test-IsServiceError pattern
function Test-IsTransientVMError {
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$ErrorMessage)

    $transientPatterns = @(
        'disk.*busy',
        'file.*locked',
        'access.*denied',  # During resource contention
        'network.*timeout',
        'rpc.*unavailable',
        'cannot access',
        'in use'
    )

    foreach ($pattern in $transientPatterns) {
        if ($ErrorMessage -imatch $pattern) {
            return $true
        }
    }
    return $false
}
```

### Pattern 3: Pre-Validation Before Expensive Operations

**What:** Check prerequisites (disk space, permissions, resource availability) before starting operations that are expensive to roll back.

**When to use:** Before checkpoint creation, large VHDX operations, VM creation.

**Example:**
```powershell
function Test-DiskSpaceForCheckpoint {
    param([string]$Path, [int64]$RequiredBytes)

    $drive = [System.IO.Path]::GetPathRoot($Path)
    $driveInfo = [System.IO.DriveInfo]::new($drive)

    if ($driveInfo.AvailableFreeSpace -lt $RequiredBytes) {
        return @{
            HasSpace = $false
            Available = $driveInfo.AvailableFreeSpace
            Required = $RequiredBytes
            Drive = $drive
            Message = "Insufficient disk space on $drive. Required: $([math]::Round($RequiredBytes/1GB, 2)) GB, Available: $([math]::Round($driveInfo.AvailableFreeSpace/1GB, 2)) GB"
        }
    }
    return @{ HasSpace = $true }
}
```

### Recommended Project Structure

The FFU.VM module functions should be organized as:
```
FFU.VM.psm1
  |-- VM Lifecycle (New-FFUVM, Remove-FFUVM)
  |-- Cleanup (Get-FFUEnvironment, Remove-FFUBuildArtifacts)
  |-- User/Share (Set-CaptureFFU, Remove-FFUUserShare)
  |-- Scripts (Update-CaptureFFUScript, Remove-SensitiveCaptureMedia)

New functions to add:
  |-- Invoke-VMOperationWithRetry (wraps Invoke-WithHypervisorRetry for VM ops)
  |-- Test-IsTransientVMError (error classification)
  |-- Test-VMResourceRequirements (pre-validation)
  |-- Get-VMCreationDiagnostics (detailed failure info)
```

### Anti-Patterns to Avoid

- **Retry everything:** Only retry transient errors. "VM already exists" should fail immediately.
- **Silent cleanup:** Always log what was cleaned up and why.
- **Cleanup in catch without logging error first:** Log the original error, THEN cleanup.
- **Hardcoded retry counts:** Use parameters with sensible defaults.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Retry with backoff | Custom retry loop | Invoke-WithHypervisorRetry | Already has jitter, logging, error classification |
| Cleanup on failure | try/catch/manual cleanup | Register-CleanupAction + Invoke-FailureCleanup | LIFO ordering, handles partial failure |
| Service health check | Get-Service polling | Test-HypervisorService | Handles both Hyper-V and VMware |
| Error logging | Custom Write-* | WriteLog | Thread-safe, consistent format |
| Secure string handling | Manual BSTR | ConvertFrom-SecureStringToPlainText | Proper cleanup patterns |

**Key insight:** Phase 15-16 already built the infrastructure. This phase extends existing patterns rather than creating new ones.

## Common Pitfalls

### Pitfall 1: Orphaned HGS Guardian Certificates

**What goes wrong:** TPM configuration creates HGS Guardian and certificates that persist after VM deletion.

**Why it happens:** HGS Guardian is created separately from VM and can fail to clean up if VM removal fails partway.

**How to avoid:** Register HGS cleanup immediately after creation, before TPM configuration:
```powershell
$guardian = New-HgsGuardian -Name $VMName -GenerateCertificates -ErrorAction Stop
$guardianCleanupId = Register-CleanupAction -Name "Remove HGS Guardian: $VMName" -ResourceType 'HGS' -Action {
    Remove-HgsGuardian -Name $using:VMName -ErrorAction SilentlyContinue
    # Also clean up certificates
    Get-ChildItem 'Cert:\LocalMachine\Shielded VM Local Certificates\' -Recurse |
        Where-Object { $_.Subject -like "*$using:VMName*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}.GetNewClosure()
```

**Warning signs:** Certificates accumulating in `Cert:\LocalMachine\Shielded VM Local Certificates\` with old VM names.

### Pitfall 2: VHDX/VHD Still Mounted After Failed VM Creation

**What goes wrong:** VHDX attached to VM during creation remains attached even after VM is deleted on failure.

**Why it happens:** Hyper-V may attach VHDX to VM before other configuration steps fail. Remove-VM doesn't always detach.

**How to avoid:** Explicitly dismount before cleanup:
```powershell
# In cleanup action for VM
$vhd = Get-VHD -Path $VHDXPath -ErrorAction SilentlyContinue
if ($vhd -and $vhd.Attached) {
    Dismount-VHD -Path $VHDXPath -ErrorAction SilentlyContinue
}
```

**Warning signs:** "Cannot delete file because it is in use" errors during cleanup.

### Pitfall 3: Checkpoint Disk Space Exhaustion Mid-Operation

**What goes wrong:** Checkpoint creation starts but fails partway through due to disk space, leaving orphaned AVHDX files.

**Why it happens:** Disk space check only done at start; other processes may use space during checkpoint.

**How to avoid:**
1. Pre-check with 2x margin (checkpoints can grow)
2. Monitor during operation
3. Handle "The system cannot find the file specified" gracefully
4. Clear orphaned AVHDX files in cleanup

**Warning signs:** AVHDX files in VM folder that don't appear in Get-VMSnapshot.

### Pitfall 4: Ctrl+C During VM Creation Leaves Partial State

**What goes wrong:** User presses Ctrl+C during long VM creation, leaving orphaned resources.

**Why it happens:** PowerShell break/cancel doesn't run catch blocks, only finally blocks.

**How to avoid:**
1. Use Register-CleanupAction which persists in module scope
2. Handle Console.CancelKeyPress event in long operations
3. Get-FFUEnvironment runs on startup to clean previous failures

**Warning signs:** `dirty.txt` file present; `_FFU-*` VMs in Hyper-V Manager from previous runs.

### Pitfall 5: VMware Lock Files Blocking Retry

**What goes wrong:** VMware VM operation fails, leaving `.lck` files that prevent retry.

**Why it happens:** VMware creates lock directories for running VMs. Crashes may leave orphaned locks.

**How to avoid:** Check for and remove orphaned lock directories before retry:
```powershell
$lockDirs = Get-ChildItem -Path (Split-Path $vmxPath -Parent) -Filter '*.lck' -Directory
foreach ($lock in $lockDirs) {
    # Only remove if no vmware-vmx process is running for this VM
    Remove-Item $lock.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
```

**Warning signs:** "Failed to lock the file" or "One or more disks are busy" errors.

## Code Examples

Verified patterns from existing codebase:

### Cleanup Registration (from FFU.Core)
```powershell
# Source: FFU.Core Register-CleanupAction
$cleanupId = Register-CleanupAction -Name "Stop and remove VM: $VMName" `
    -ResourceType 'VM' `
    -ResourceId $VMName `
    -Action {
        $vm = Get-VM -Name $using:VMName -ErrorAction SilentlyContinue
        if ($vm) {
            if ($vm.State -ne 'Off') {
                Stop-VM -Name $using:VMName -Force -TurnOff -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            Remove-VM -Name $using:VMName -Force -ErrorAction SilentlyContinue
        }
    }.GetNewClosure()
```

### Retry Wrapper (from FFU.Hypervisor)
```powershell
# Source: FFU.Hypervisor Invoke-WithHypervisorRetry
Invoke-WithHypervisorRetry -Provider 'HyperV' -OperationName 'StartVM' -MaxRetries 3 -ScriptBlock {
    Start-VM -Name $VMName -ErrorAction Stop
}
```

### Error Classification (from FFU.Hypervisor)
```powershell
# Source: FFU.Hypervisor Test-IsServiceError
$isServiceError = Test-IsServiceError -Provider 'HyperV' -ErrorMessage $_.Exception.Message
if (-not $isServiceError) {
    # Not retryable - fail immediately
    throw
}
```

### Disk Space Pre-Check (new pattern)
```powershell
# Pattern for checkpoint disk space validation
function Test-CheckpointDiskSpace {
    param(
        [Parameter(Mandatory)]
        [string]$VMName,
        [int]$MarginPercent = 100  # 100% margin = 2x space
    )

    $vm = Get-VM -Name $VMName -ErrorAction Stop
    $vhdxPath = ($vm | Get-VMHardDiskDrive | Select-Object -First 1).Path
    $vhdxSize = (Get-VHD -Path $vhdxPath).FileSize

    $requiredSpace = $vhdxSize * (1 + $MarginPercent / 100)
    $drive = [System.IO.Path]::GetPathRoot($vhdxPath)
    $driveInfo = [System.IO.DriveInfo]::new($drive)

    if ($driveInfo.AvailableFreeSpace -lt $requiredSpace) {
        throw "Insufficient disk space for checkpoint on $drive. " +
              "Required: $([math]::Round($requiredSpace/1GB, 2)) GB, " +
              "Available: $([math]::Round($driveInfo.AvailableFreeSpace/1GB, 2)) GB. " +
              "Free up space or change VM storage location."
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual cleanup in catch | Register-CleanupAction | Phase 15 (v1.0.6) | Consistent cleanup ordering |
| Simple retry loops | Invoke-WithHypervisorRetry | Phase 16 (v1.3.6) | Exponential backoff with jitter |
| Assume service always running | Test-HypervisorService | Phase 16 (v1.3.6) | Recovery from service restart |
| Silent failures | Invoke-WithErrorHandling | Phase 15 (v1.0.5) | Actionable error messages |

**Deprecated/outdated:**
- Direct `Start-VM`/`Stop-VM` without retry wrapper: Use `Invoke-WithHypervisorRetry` for critical paths
- Manual try/catch with inline cleanup: Use `Register-CleanupAction` for resource cleanup

## Open Questions

Things that were verified in research:

1. **Hyper-V checkpoint disk space errors**
   - What we know: Error code 0x80070070 (ERROR_DISK_FULL), can leave orphaned AVHDX
   - Resolved: Pre-validate with Test-CheckpointDiskSpace, clean orphaned files in Get-FFUEnvironment

2. **VMware lock file cleanup**
   - What we know: `.lck` directories can orphan after crash
   - Resolved: Add lock file cleanup to VMware provider cleanup path

3. **Ctrl+C handling**
   - What we know: Finally blocks run, but not catch blocks
   - Resolved: Register-CleanupAction persists in module scope, survives cancellation

## Sources

### Primary (HIGH confidence)
- FFU.Core module source (FFU.Core.psm1) - Cleanup registration patterns
- FFU.Hypervisor module source (Invoke-WithHypervisorRetry.ps1) - Retry patterns
- FFU.VM module source (FFU.VM.psm1) - Current implementation to extend

### Secondary (MEDIUM confidence)
- [Microsoft Learn: Troubleshoot Hyper-V VM Backup, Checkpoint, and Storage Failures](https://learn.microsoft.com/en-us/troubleshoot/windows-server/virtualization/hyper-v-virtual-machine-backup-checkpoint-storage) - Checkpoint error patterns
- [Microsoft Learn: Troubleshoot Hyper-V Snapshots, Checkpoints, and Differencing Disks](https://learn.microsoft.com/en-us/troubleshoot/windows-server/virtualization/hyper-v-snapshots-checkpoints-differencing-disks) - AVHDX orphan handling
- [Microsoft Learn: Troubleshoot Hyper-V VM Creation](https://learn.microsoft.com/en-us/troubleshoot/windows-server/virtualization/troubleshoot-hyper-v-virtual-machine-creation) - VM creation failures

### Tertiary (MEDIUM confidence)
- [VMware KB: Failed to lock the file](https://kb.vmware.com/s/article/2017072) - VMware lock file issues
- [Broadcom: Troubleshooting issues resulting from locked virtual disks](https://knowledge.broadcom.com/external/article/316576/troubleshooting-issues-resulting-from-lo.html) - VMware disk lock patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All patterns already exist in codebase
- Architecture: HIGH - Extending proven patterns from Phase 15-16
- Pitfalls: HIGH - Based on actual codebase issues and Microsoft documentation

**Research date:** 2026-01-24
**Valid until:** 2026-02-24 (stable patterns, unlikely to change)
