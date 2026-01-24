# Phase 18: FFU.Imaging Reliability - Research

**Researched:** 2026-01-23
**Domain:** DISM operations, disk space validation, partition verification, FFU capture resilience
**Confidence:** HIGH

## Summary

This phase hardens the FFU.Imaging module to handle failures gracefully with space checks, partition validation, and recovery from transient mount/dismount errors. The research focuses on:

1. **Disk space validation** - Pre-flight checks before disk operations that could fail with ERROR_DISK_FULL
2. **Partition state verification** - Before/after comparison to catch silent partition operation failures
3. **Safe FFU capture patterns** - Preserving source VHDX integrity when capture fails
4. **Mount/dismount retry logic** - Handling transient "drive in use" and sharing violation errors
5. **Resume capability assessment** - DISM /capture-ffu does NOT support resume (design accordingly)

FFU.Imaging already has significant error handling (retry logic in `Invoke-ExpandWindowsImageWithRetry`, file lock retry in `Invoke-FFUOptimizeWithScratchDir`). This phase extends these patterns to cover the remaining reliability gaps. Phase 17 established patterns (exponential backoff, error classification, cleanup registration) that apply directly.

**Primary recommendation:** Extend existing patterns from Phase 17 (Invoke-WithHypervisorRetry, Register-CleanupAction) to imaging domain. Add pre-validation functions for disk space and partition state. DISM lacks checkpoint/resume - design around this limitation.

## Standard Stack

The established patterns for this domain are already in the codebase:

### Core Patterns to Extend

| Pattern | Location | Purpose | Why Standard |
|---------|----------|---------|--------------|
| Invoke-WithErrorHandling | FFU.Core | Generic retry wrapper | Already has logging, cleanup, retry delay |
| Register-CleanupAction | FFU.Core | Track resources for cleanup | LIFO cleanup on failure |
| Invoke-WithHypervisorRetry | FFU.Hypervisor | Retry with exponential backoff | Service error detection, jitter |
| Test-IsServiceError | FFU.Hypervisor | Classify transient vs permanent | Template for Test-IsImagingError |
| Test-WimSourceAccessibility | FFU.Imaging | Pre-validation before long ops | Already validates WIM/ISO state |

### Supporting Functions

| Function | Module | Purpose | When to Use |
|----------|--------|---------|-------------|
| WriteLog | FFU.Core | Thread-safe logging | All error messages |
| Get-Volume | Storage | Disk space info | Pre-validation |
| Get-Partition | Storage | Partition state | Before/after validation |
| Get-VHD | Hyper-V | VHDX state info | Integrity checks |

### No New External Dependencies Required

The existing module structure provides everything needed:
- FFU.Imaging depends on FFU.Core
- FFU.Core provides error handling and cleanup registration
- Storage cmdlets (Get-Volume, Get-Partition) are built-in
- .NET System.IO.DriveInfo for cross-platform disk space

## Architecture Patterns

### Pattern 1: Disk Space Pre-Validation

**What:** Check available disk space before operations that could fail with ERROR_DISK_FULL (0x80070070).

**When to use:** Before FFU capture, VHDX expansion, partition operations.

**Example:**
```powershell
# Source: Pattern based on Phase 17 Test-CheckpointDiskSpace
function Test-DiskSpaceForOperation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [int64]$RequiredBytes,

        [Parameter()]
        [int]$SafetyMarginPercent = 10
    )

    $drive = [System.IO.Path]::GetPathRoot($Path)
    $driveInfo = [System.IO.DriveInfo]::new($drive)

    $requiredWithMargin = [int64]($RequiredBytes * (1 + $SafetyMarginPercent / 100))

    [PSCustomObject]@{
        HasSufficientSpace = $driveInfo.AvailableFreeSpace -ge $requiredWithMargin
        Drive = $drive
        AvailableBytes = $driveInfo.AvailableFreeSpace
        AvailableGB = [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)
        RequiredBytes = $requiredWithMargin
        RequiredGB = [math]::Round($requiredWithMargin / 1GB, 2)
        ShortfallBytes = [math]::Max(0, $requiredWithMargin - $driveInfo.AvailableFreeSpace)
    }
}
```

### Pattern 2: Partition State Verification

**What:** Capture partition state before operation, compare after to detect silent failures.

**When to use:** Before/after Initialize-Disk, New-Partition, Set-Partition operations.

**Example:**
```powershell
# Capture disk state before operation
function Get-DiskPartitionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$DiskNumber
    )

    $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        DiskNumber = $DiskNumber
        PartitionCount = ($partitions | Measure-Object).Count
        TotalSizeBytes = ($partitions | Measure-Object -Property Size -Sum).Sum
        PartitionStyles = @($partitions | Select-Object -ExpandProperty GptType -Unique)
        DriveLetters = @($partitions | Where-Object DriveLetter | Select-Object -ExpandProperty DriveLetter)
        CapturedAt = [DateTime]::Now
    }
}

# Compare states
function Compare-DiskPartitionState {
    param(
        [PSCustomObject]$Before,
        [PSCustomObject]$After,
        [string]$ExpectedChange  # 'PartitionAdded', 'PartitionRemoved', 'DriveLetterAssigned'
    )

    $changes = @{
        PartitionCountChanged = $After.PartitionCount -ne $Before.PartitionCount
        SizeChanged = $After.TotalSizeBytes -ne $Before.TotalSizeBytes
        DriveLettersChanged = (Compare-Object $Before.DriveLetters $After.DriveLetters) -ne $null
    }

    # Validate expected change occurred
    switch ($ExpectedChange) {
        'PartitionAdded' {
            if ($After.PartitionCount -le $Before.PartitionCount) {
                return @{ Valid = $false; Error = "Expected partition count to increase" }
            }
        }
        'DriveLetterAssigned' {
            if (-not $changes.DriveLettersChanged) {
                return @{ Valid = $false; Error = "Drive letter assignment not detected" }
            }
        }
    }

    @{ Valid = $true; Changes = $changes }
}
```

### Pattern 3: Transient Error Classification for Imaging

**What:** Classify DISM/disk errors as transient (retryable) or permanent (fail fast).

**When to use:** Before deciding whether to retry an imaging operation.

**Example:**
```powershell
# Source: Based on FFU.Hypervisor Test-IsServiceError pattern
function Test-IsTransientImagingError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ErrorMessage,

        [int]$HResult = 0
    )

    # Transient error patterns (retryable)
    $transientPatterns = @(
        'sharing violation',           # 0x80070020 - file in use
        'device is not connected',     # 0x8007048f - mount lost
        'drive.*in use',
        'file.*locked',
        'cannot access',
        'rpc.*unavailable',
        'network.*timeout',
        'operation cannot be performed while.*in use'
    )

    # Transient HResult codes
    $transientHResults = @(
        -2147024864,  # 0x80070020 ERROR_SHARING_VIOLATION
        -2147023729,  # 0x8007048F ERROR_INVALID_ADDRESS (device disconnected)
        -2147024784   # 0x80070070 ERROR_DISK_FULL (retryable after cleanup)
    )

    # Permanent error patterns (do NOT retry)
    $permanentPatterns = @(
        'not found',
        'does not exist',
        'access denied',              # Usually permission, not transient
        'invalid parameter',
        'registry.*corrupt',          # Error 1009
        'request.*not supported'      # Error 50
    )

    # Check permanent patterns first
    foreach ($pattern in $permanentPatterns) {
        if ($ErrorMessage -imatch $pattern) {
            return $false
        }
    }

    # Check transient HResults
    if ($HResult -ne 0 -and $transientHResults -contains $HResult) {
        return $true
    }

    # Check transient patterns
    foreach ($pattern in $transientPatterns) {
        if ($ErrorMessage -imatch $pattern) {
            return $true
        }
    }

    # Default: unknown errors are NOT transient (fail fast)
    return $false
}
```

### Pattern 4: Safe VHDX Preservation During FFU Capture

**What:** Ensure source VHDX remains intact and usable if FFU capture fails.

**When to use:** During `New-FFU` capture operations.

**Design principles:**
1. Never modify source VHDX during capture (DISM /Capture-FFU reads only)
2. Register cleanup for output FFU file (delete partial on failure)
3. Validate VHDX integrity before and after capture
4. If capture fails, VHDX should be mountable for retry

**Example:**
```powershell
function Invoke-SafeFFUCapture {
    param(
        [string]$VHDXPath,
        [string]$OutputFFUPath,
        [string]$DandIEnv
    )

    # Pre-capture validation
    $vhdxState = Get-VHD -Path $VHDXPath -ErrorAction Stop
    if ($vhdxState.Attached) {
        throw "VHDX must be dismounted before capture. Currently attached."
    }

    # Register cleanup for partial FFU on failure
    $ffuCleanupId = Register-CleanupAction -Name "Remove partial FFU: $OutputFFUPath" `
        -ResourceType 'TempFile' -ResourceId $OutputFFUPath -Action {
            if (Test-Path $using:OutputFFUPath) {
                Remove-Item $using:OutputFFUPath -Force -ErrorAction SilentlyContinue
            }
        }.GetNewClosure()

    try {
        # Capture FFU (DISM reads VHDX, doesn't modify)
        $dismArgs = "/c call `"$DandIEnv`" && dism /Capture-FFU /ImageFile:`"$OutputFFUPath`" ..."
        Invoke-Process cmd $dismArgs

        # Success - unregister cleanup
        Unregister-CleanupAction -CleanupId $ffuCleanupId
    }
    catch {
        # Validate VHDX is still intact
        try {
            $postState = Get-VHD -Path $VHDXPath -ErrorAction Stop
            WriteLog "VHDX integrity verified after capture failure"
        }
        catch {
            WriteLog "WARNING: VHDX may be corrupted: $($_.Exception.Message)"
        }
        throw  # Re-throw original error, cleanup runs via Invoke-FailureCleanup
    }
}
```

### Recommended Project Structure

The FFU.Imaging reliability functions should be organized as:
```
FFU.Imaging.psm1
  |-- Existing functions (unchanged)
  |-- New reliability functions:
      |-- Test-DiskSpaceForOperation (pre-validation)
      |-- Get-DiskPartitionState (state capture)
      |-- Compare-DiskPartitionState (state verification)
      |-- Test-IsTransientImagingError (error classification)
      |-- Invoke-ImagingOperationWithRetry (retry wrapper)
      |-- Invoke-SafeFFUCapture (capture with VHDX preservation)
      |-- Invoke-MountWithRetry (mount retry for transient errors)
```

### Anti-Patterns to Avoid

- **Modifying VHDX during capture:** DISM /Capture-FFU only reads - don't mount/unmount during capture
- **Retrying ERROR_DISK_FULL without cleanup:** Free space first, then retry
- **Silently ignoring partition validation failures:** Log and fail explicitly
- **Hardcoded space requirements:** Calculate dynamically based on operation

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Retry with backoff | Custom retry loop | Invoke-WithErrorHandling | Already has logging, cleanup hooks |
| Disk space check | Manual Get-Volume parsing | System.IO.DriveInfo | Works without Storage module |
| Transient error detection | Simple string match | Test-IsTransientImagingError | Needs HResult + pattern matching |
| Cleanup on failure | try/catch manual | Register-CleanupAction | LIFO ordering, survives Ctrl+C |
| File lock retry | Custom loop | Existing pattern in Invoke-FFUOptimizeWithScratchDir | Already handles this |

**Key insight:** FFU.Imaging already has significant retry logic. This phase standardizes and extends it, doesn't replace it.

## Common Pitfalls

### Pitfall 1: DISM Does Not Support Resume for FFU Capture

**What goes wrong:** Expecting checkpoint/resume capability for interrupted captures.

**Why it happens:** DISM /Capture-FFU is atomic - no partial output is usable.

**How to avoid:**
1. Design for idempotent retry (full re-capture on failure)
2. Pre-validate disk space with margin for full capture
3. If interrupted, delete partial FFU and restart
4. Log estimated capture time so users know to wait

**Warning signs:** Partial .ffu files after interruption are corrupt and must be deleted.

### Pitfall 2: Mount-WindowsImage Fails with Stale Mount Points

**What goes wrong:** Mount fails with "path is already mounted" even though it shouldn't be.

**Why it happens:** Previous failed dismount left stale mount point in DISM registry.

**How to avoid:**
```powershell
# Always cleanup before mount
& dism.exe /Cleanup-Mountpoints 2>&1 | Out-Null
Start-Sleep -Seconds 3
Mount-WindowsImage -ImagePath $path -Path $mountPath ...
```

**Warning signs:** Error 1168 "Element not found" or "directory is not empty".

### Pitfall 3: Sharing Violation During VHD Operations (0x80070020)

**What goes wrong:** Mount/dismount fails because another process has the file open.

**Why it happens:** Windows Defender scanning, Search indexer, or previous operation handle not released.

**How to avoid:**
1. Add FFU folder to Defender exclusions
2. Exclude from Windows Search indexing
3. Wait for file lock release with retry (existing pattern in module)
4. Use dedicated scratch directory (already implemented)

**Warning signs:** "The process cannot access the file because it is being used by another process."

### Pitfall 4: Partition Operations Succeed But Lose Drive Letter

**What goes wrong:** Partition created successfully but DriveLetter property is null.

**Why it happens:** Windows doesn't auto-assign letters to all partition types. Mount operations don't assign letters.

**How to avoid:**
- Always call `Set-OSPartitionDriveLetter` after mount operations (already implemented)
- Verify DriveLetter is not null before file operations
- Use state comparison to detect drive letter changes

**Warning signs:** "Cannot validate argument on parameter 'DriveLetter'. The argument is null."

### Pitfall 5: Disk Space Check Passes But Operation Fails

**What goes wrong:** Pre-check shows sufficient space but DISM fails with ERROR_DISK_FULL.

**Why it happens:**
1. Safety margin too small
2. Other processes using space during operation
3. Compressed/sparse file size differs from disk allocation

**How to avoid:**
1. Use 2x margin for FFU capture (FFU can be as large as source disk)
2. Re-check space before each phase of long operations
3. Use `Get-VHD` FileSize property, not logical size

**Warning signs:** DISM error 112 partway through operation.

## Code Examples

Verified patterns from existing codebase:

### Mount Retry Pattern (from FFU.Imaging New-FFU)
```powershell
# Source: FFU.Imaging.psm1 lines 2600-2631
try {
    Mount-WindowsImage -ImagePath $FFUFile -Index 1 -Path $mountPath -ErrorAction Stop | Out-Null
    $imageMounted = $true
}
catch {
    WriteLog "ERROR: Failed to mount image: $($_.Exception.Message)"
    WriteLog "Attempting DISM cleanup and retry..."
    & dism.exe /Cleanup-Mountpoints 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    try {
        Mount-WindowsImage -ImagePath $FFUFile -Index 1 -Path $mountPath -ErrorAction Stop | Out-Null
        $imageMounted = $true
    }
    catch {
        throw "Failed to mount image after retry: $($_.Exception.Message)"
    }
}
```

### File Lock Retry Pattern (from FFU.Imaging)
```powershell
# Source: FFU.Imaging.psm1 Invoke-FFUOptimizeWithScratchDir lines 2997-3021
$lockRetryAttempt = 0
$fileAccessible = $false
$lastLockError = $null

while (-not $fileAccessible -and $lockRetryAttempt -lt $FileLockRetryCount) {
    $lockRetryAttempt++
    try {
        $fileStream = [System.IO.File]::Open($FFUFile, 'Open', 'Read', 'Read')
        $fileStream.Close()
        $fileStream.Dispose()
        $fileAccessible = $true
    }
    catch {
        $lastLockError = $_.Exception.Message
        if ($lockRetryAttempt -lt $FileLockRetryCount) {
            WriteLog "WARNING: FFU file is locked (attempt $lockRetryAttempt/$FileLockRetryCount)..."
            Start-Sleep -Seconds $FileLockRetryDelaySeconds
        }
    }
}
```

### Disk Space Check (from FFU.Imaging)
```powershell
# Source: FFU.Imaging.psm1 Invoke-FFUOptimizeWithScratchDir lines 3066-3077
$scratchDrive = Split-Path -Qualifier $scratchDir
$scratchVolume = Get-Volume -DriveLetter $scratchDrive.TrimEnd(':') -ErrorAction SilentlyContinue
if ($scratchVolume) {
    $freeSpaceGB = [math]::Round($scratchVolume.SizeRemaining / 1GB, 2)
    WriteLog "Available space on $scratchDrive : $freeSpaceGB GB"
    if ($freeSpaceGB -lt 10) {
        WriteLog "WARNING: Low disk space. FFU optimization may fail."
    }
}
```

### Cleanup Registration (from FFU.Core)
```powershell
# Source: FFU.Core.psm1 Register-CleanupAction pattern
$cleanupId = Register-CleanupAction -Name "Dismount FFU: $mountPath" `
    -ResourceType 'DISM' -ResourceId $mountPath -Action {
        Dismount-WindowsImage -Path $using:mountPath -Discard -ErrorAction SilentlyContinue
    }.GetNewClosure()

# After successful dismount, unregister
Unregister-CleanupAction -CleanupId $cleanupId
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No pre-validation | Test-WimSourceAccessibility | v1.0.0 | Prevents mid-operation failures |
| Direct Mount-WindowsImage | Retry with DISM cleanup | v1.1.5 | Handles stale mount points |
| Single FFU optimization attempt | Invoke-FFUOptimizeWithScratchDir | v1.1.0 | Scratch dir prevents locks |
| Fixed wait times | File lock retry loop | v1.1.5 | Adaptive to actual lock release |
| Manual space check | Inline in optimize function | v1.1.0 | Warns before failure |

**Deprecated/outdated:**
- Assuming VHD operations always succeed: Always validate state changes
- Trusting $LASTEXITCODE alone for DISM: Check output for specific error patterns

## Open Questions

Things that were resolved during research:

1. **Resume capability for FFU capture**
   - What we know: DISM /Capture-FFU has NO resume capability
   - Resolution: Design for idempotent full retry; delete partial FFU on failure
   - Source: [Microsoft Q&A: DISM capture-ffu error 112](https://learn.microsoft.com/en-us/answers/questions/4307585/dism-capture-ffu-getting-error-112)

2. **Checkpointing for large file operations**
   - What we know: FFU format doesn't support incremental capture
   - Resolution: Pre-validation is the only defense; ensure sufficient space before starting
   - Recommendation: REL-IMG-05 should focus on pre-validation, not resume

3. **Transient vs permanent DISM errors**
   - What we know: 0x80070020 (sharing violation) is transient; 0x800f081f (source missing) is permanent
   - Resolution: Use pattern-based classification with HResult fallback
   - Source: [UNIQ: Error code 0x80070020](https://uniq.software/en/help-centre/troubleshooting/windows-10/how-to-solve-the-error-code-0x80070020-file-in-use-in-windows-10)

## Sources

### Primary (HIGH confidence)
- FFU.Imaging.psm1 source (v1.1.5) - Existing error handling patterns
- FFU.Core.psm1 source (v1.0.9) - Cleanup registration, error handling helpers
- FFU.Hypervisor source - Test-IsServiceError pattern, retry with backoff
- Phase 17 RESEARCH.md - Retry patterns, cleanup registration, disk space validation

### Secondary (MEDIUM confidence)
- [Microsoft Learn: Mount-WindowsImage](https://learn.microsoft.com/en-us/powershell/module/dism/mount-windowsimage?view=windowsserver2025-ps) - Mount parameters, CheckIntegrity, Remount
- [Microsoft Q&A: DISM optimize-ffu](https://learn.microsoft.com/en-us/answers/questions/3847277/dism-optimize-ffu-has-anyone-got-it-to-work) - Optimization issues
- [GitHub FFU Issue #154](https://github.com/rbalsleyMSFT/FFU/issues/154) - DISM capture failure patterns
- [Microsoft Q&A: DISM capture-ffu error 112](https://learn.microsoft.com/en-us/answers/questions/4307585/dism-capture-ffu-getting-error-112) - Disk space requirements

### Tertiary (LOW confidence)
- [UNIQ: Error 0x80070020](https://uniq.software/en/help-centre/troubleshooting/windows-10/how-to-solve-the-error-code-0x80070020-file-in-use-in-windows-10) - Sharing violation remediation
- [UNIQ: Error 0x80070070](https://uniq.software/en-help-centre/troubleshooting/windows-10/how-to-solve-the-error-code-0x80070070-not-enough-space-in-windows-10) - Disk full remediation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Patterns exist in codebase and Phase 17
- Architecture: HIGH - Direct extension of existing error handling
- Pitfalls: HIGH - Based on existing module release notes and issues

**Research date:** 2026-01-23
**Valid until:** 2026-02-23 (stable patterns, DISM API unchanged)

## Requirement-Specific Findings

### REL-IMG-01: Disk Space Detection
- **Pattern:** Test-DiskSpaceForOperation with System.IO.DriveInfo
- **Integration:** Call before New-ScratchVhd, New-FFU, Expand-FFUPartitionForDrivers
- **Confidence:** HIGH - straightforward implementation

### REL-IMG-02: Partition Validation
- **Pattern:** Get-DiskPartitionState before/after with Compare-DiskPartitionState
- **Integration:** Wrap New-SystemPartition, New-OSPartition, New-RecoveryPartition
- **Confidence:** HIGH - uses existing Storage cmdlets

### REL-IMG-03: FFU Capture Recovery
- **Pattern:** Register-CleanupAction for partial FFU, Get-VHD for integrity check
- **Integration:** Wrap capture block in New-FFU
- **Confidence:** HIGH - VHDX is read-only during capture

### REL-IMG-04: Mount/Dismount Retry
- **Pattern:** Existing mount retry + Test-IsTransientImagingError for classification
- **Integration:** Enhance existing retry in New-FFU, create Invoke-MountWithRetry wrapper
- **Confidence:** HIGH - pattern already exists, needs standardization

### REL-IMG-05: Resume Capability
- **Finding:** DISM /Capture-FFU does NOT support resume
- **Recommendation:** Focus on pre-validation (space, accessibility) rather than resume
- **Alternative:** Log estimated time, advise user not to interrupt
- **Confidence:** HIGH - verified DISM limitation
