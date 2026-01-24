# Phase 24: WinPE Scripts Reliability - Research

**Researched:** 2026-01-24
**Domain:** Windows Preinstallation Environment (WinPE), PowerShell scripting, FFU capture/deploy
**Confidence:** HIGH (based on existing codebase analysis and official Microsoft documentation)

## Summary

Phase 24 focuses on making WinPE scripts (CaptureFFU.ps1, Orchestrator.ps1, ApplyFFU.ps1) robust in the constrained WinPE environment with proper log preservation and actionable error messages. The research reveals four key areas requiring attention:

1. **CaptureFFU.ps1** already has extensive network reliability logic but lacks target disk validation before destructive capture operations
2. **Orchestrator.ps1** has integrity verification but minimal dependency detection messaging - it silently skips missing scripts
3. **Log preservation** exists partially (DISM logs copied) but lacks comprehensive logging of script output before VM shutdown
4. **Resource handling** is implicit - WinPE has 512MB minimum RAM and 4GB FAT32 file size limits that scripts don't currently check

**Primary recommendation:** Add defensive validation at script entry points, enhance error messages to be actionable, and ensure all logs are preserved to persistent storage before VM shutdown.

## WinPE Environment Constraints

### Hardware Requirements (HIGH confidence - Microsoft docs)

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| RAM | 512 MB | 1 GB+ | Base WinPE; more needed with drivers/packages |
| Disk | None required | - | Runs entirely from RAM disk |
| FAT32 file size | 4 GB max | - | Critical for FFU files |
| Drive size | 32 GB max | - | FAT32 limitation |

Source: [Microsoft WinPE Documentation](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-intro)

### Critical Behavioral Constraints

| Constraint | Impact | Mitigation |
|------------|--------|------------|
| 72-hour auto-restart | Scripts must complete within 72 hours | Not configurable; N/A for FFU builds (minutes) |
| RAM disk volatility | All changes lost on reboot | Must copy logs to persistent storage before shutdown |
| No .MSI support | Cannot run .MSI installers | Use portable executables only |
| No domain join | Cannot join AD domain | Use local authentication only |
| No Remote Desktop | Cannot RDP to WinPE | Rely on console/logs |
| No .appxbundle | Cannot install via DISM | Pre-provision in image |

### PowerShell Module Availability in WinPE

| Module | Available | Alternative Used |
|--------|-----------|------------------|
| NetAdapter | NO | Get-WmiNetworkAdapter (CIM/WMI) |
| NetTCPIP | NO | Get-WmiIPAddress, Get-WmiDefaultGateway |
| DnsClient | NO | Resolve-HostNameDotNet (.NET) |
| Storage | YES | Native cmdlets work |
| Microsoft.PowerShell.Core | YES | Basic cmdlets available |
| Microsoft.PowerShell.Utility | YES | Basic utilities available |
| WinPE-Scripting | OPTIONAL | Must be added via ADK |

## Current Script Analysis

### CaptureFFU.ps1 (1018 lines)

**Location:** `FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1`

**Current capabilities (STRONG):**
- Network initialization wait with 60-second timeout
- WMI-based network adapter detection (WinPE compatible)
- Retry logic for SMB share connection (3 attempts)
- Comprehensive network diagnostics on failure
- Color-coded status messages
- DISM log copy to network share

**Gaps identified (REL-WINPE-01):**
```powershell
# Current: Always captures PhysicalDrive0 without validation
$dismArgs = "/capture-ffu /imagefile=W:\$FFUFileName /capturedrive=\\.\PhysicalDrive0 ..."
```

| Gap | Risk | Impact |
|-----|------|--------|
| No disk validation before capture | HIGH | Could capture wrong disk if boot order changes |
| Hardcoded PhysicalDrive0 | MEDIUM | Assumes single disk; fails multi-disk scenarios |
| No size check | LOW | DISM will fail gracefully if disk too small |

**AssignDriveLetter.txt uses hardcoded disk 0:**
```
select disk 0
select partition 3
Assign letter="M"
```

### Orchestrator.ps1 (243 lines)

**Location:** `FFUDevelopment/Apps/Orchestration/Orchestrator.ps1`

**Current capabilities:**
- Script integrity verification (SEC-03 compliance)
- Self-verification before proceeding
- Ordered script execution
- Conditional execution based on dependencies

**Gaps identified (REL-WINPE-02):**

| Pattern | Current Behavior | Issue |
|---------|------------------|-------|
| Missing script | `continue` (silent skip) | User has no idea script was skipped |
| Failed integrity | Logs error, `continue` | User may not see if many scripts run |
| Missing Run-DiskCleanup.ps1 | `Write-Host "not found!"` | No context on impact |
| Missing Run-Sysprep.ps1 | `Write-Host "not found!"` | Critical - should abort |

**Example of silent skip:**
```powershell
foreach ($script in $scriptList) {
    $scriptFile = Join-Path -Path $scriptPath -ChildPath $script
    if (-not (Test-Path -Path $scriptFile)) {
        continue  # Silent skip - no warning logged
    }
```

### ApplyFFU.ps1 (966 lines)

**Location:** `FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1`

**Current capabilities (STRONG):**
- USB drive detection with fallback logic
- Disk validation with model/type filtering
- Log file creation on USB drive
- Comprehensive error handling with Stop-Script function
- DISM log preservation on failure
- Press-Enter-to-exit on errors

**Noteworthy pattern for reuse:**
```powershell
function Stop-Script {
    param([string]$Message)
    Write-Host "`n"
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-Error -Message $Message
    }
    WriteLog "Copying dism log to $USBDrive"
    Invoke-Process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y"
    Read-Host "Press Enter to exit"
    Exit
}
```

## Log Preservation Analysis

### Current State (REL-WINPE-03)

| Script | Log Destination | When Preserved | Gap |
|--------|-----------------|----------------|-----|
| CaptureFFU.ps1 | Network share (W:) | After DISM capture | No console log preserved |
| ApplyFFU.ps1 | USB drive | Always via WriteLog | DISM log copied on success/failure |
| Orchestrator.ps1 | Console only | Never | All output lost on VM shutdown |

### Log Preservation Options

**Option A: Network Share (CaptureFFU.ps1)**
- Pros: Already connected, accessible from host
- Cons: Network dependency; fails if share disconnected
- Current: Only DISM log copied

**Option B: USB Drive (ApplyFFU.ps1 pattern)**
- Pros: Persistent, no network needed
- Cons: Not available in VM capture scenario
- Current: Used by ApplyFFU.ps1

**Option C: VM Virtual Disk (Recommended for VM capture)**
- Pros: Survives VM shutdown, accessible from host
- Cons: Requires disk mounting logic
- Approach: Write to Windows partition before shutdown, host reads after

**Recommendation:** For CaptureFFU.ps1, add script log preservation to network share alongside DISM log. For Orchestrator.ps1, write log to D:\orchestration\orchestrator.log (Apps ISO or virtual disk).

## Disk Validation Requirements

### REL-WINPE-01: Target Disk Validation

**Current risk:** CaptureFFU.ps1 always captures PhysicalDrive0 without verifying it's the intended target.

**Validation checks needed:**

| Check | Purpose | Implementation |
|-------|---------|----------------|
| Disk exists | Basic sanity | `Get-CimInstance Win32_DiskDrive` |
| Is virtual disk | Confirm Hyper-V/VMware disk | Check model contains "Virtual" or "VMware" |
| Has Windows partition | Confirm OS installed | Check for partition with Windows folder |
| Correct size range | Sanity check | Compare to expected VHDX size |

**Proposed validation function:**
```powershell
function Test-CaptureTargetDisk {
    param([int]$DiskNumber = 0)

    $disk = Get-CimInstance Win32_DiskDrive | Where-Object { $_.DeviceID -eq "\\.\PHYSICALDRIVE$DiskNumber" }

    if (-not $disk) {
        return @{ Valid = $false; Error = "Disk $DiskNumber not found" }
    }

    # Verify it's a virtual disk (Hyper-V or VMware)
    if ($disk.Model -notmatch 'Virtual|VMware') {
        return @{ Valid = $false; Error = "Disk $DiskNumber is not a virtual disk (Model: $($disk.Model))" }
    }

    return @{ Valid = $true; DiskInfo = $disk }
}
```

## Resource Exhaustion Handling

### REL-WINPE-04: Low Resource Detection

**WinPE Memory Constraints:**
- WinPE itself uses ~400-512 MB RAM
- RAM disk holds entire boot.wim (varies by WinPE customization)
- Remaining RAM available for scripts and DISM operations

**Detection approach:**
```powershell
function Test-WinPEResources {
    $os = Get-CimInstance Win32_OperatingSystem
    $freeMemoryMB = [math]::Round($os.FreePhysicalMemory / 1024, 0)
    $totalMemoryMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)

    # Warn if less than 256 MB free
    if ($freeMemoryMB -lt 256) {
        Write-Warning "Low memory: ${freeMemoryMB}MB free of ${totalMemoryMB}MB total"
        return $false
    }
    return $true
}
```

**Disk Space Constraints:**
- RAM disk has limited write space
- X: drive is read-only (WinPE root)
- Network share space depends on host configuration

**Graceful degradation strategies:**
1. Check memory before large operations
2. Stream output instead of buffering
3. Fail fast with clear message if resources insufficient

## Gaps Mapped to Requirements

### REL-WINPE-01: Disk Validation Before Capture

| Gap | Current | Required |
|-----|---------|----------|
| No disk existence check | Assumes disk 0 exists | Verify disk present |
| No disk type validation | Could capture USB | Verify virtual disk |
| Hardcoded disk number | Always 0 | Validate expected disk |
| No partition validation | Assumes partition 3 | Verify Windows partition |

**Files affected:** `CaptureFFU.ps1`, `AssignDriveLetter.txt`

### REL-WINPE-02: Dependency Detection

| Gap | Current | Required |
|-----|---------|----------|
| Silent script skip | `continue` with no output | Log warning for each skip |
| Missing dependency ignored | Script proceeds | Fail-fast for critical dependencies |
| No summary of skips | Individual messages only | Summary at end showing what was skipped |
| Vague error messages | "not found!" | Include full path and expected location |

**Files affected:** `Orchestrator.ps1`

### REL-WINPE-03: Log Preservation

| Gap | Current | Required |
|-----|---------|----------|
| CaptureFFU console log | Lost on shutdown | Tee to network share |
| Orchestrator log | Lost on shutdown | Write to D: drive or network |
| DISM log (CaptureFFU) | Copied to W: | Already handled |
| Script execution log | None | Add timestamped execution log |

**Files affected:** `CaptureFFU.ps1`, `Orchestrator.ps1`

### REL-WINPE-04: Resource Handling

| Gap | Current | Required |
|-----|---------|----------|
| No memory check | Implicit assumption | Warn if <256MB free |
| No disk space check | DISM fails silently | Pre-check share free space |
| No graceful degradation | Crash on exhaustion | Fail with clear message |

**Files affected:** `CaptureFFU.ps1`

## Recommended Plan Structure

### Plan 24-01: CaptureFFU Disk Validation (REL-WINPE-01)

**Scope:** Add disk validation before capture begins
**Tasks:**
1. Create `Test-CaptureTargetDisk` function
2. Add validation call before DISM capture
3. Update `AssignDriveLetter.txt` generation to be dynamic
4. Add tests for disk validation logic

### Plan 24-02: Orchestrator Dependency Detection (REL-WINPE-02)

**Scope:** Improve error messages and dependency detection
**Tasks:**
1. Replace silent `continue` with `Write-Warning`
2. Add summary of skipped scripts at end
3. Fail-fast for critical scripts (Run-Sysprep.ps1)
4. Add full path in all error messages

### Plan 24-03: Log Preservation Enhancement (REL-WINPE-03)

**Scope:** Ensure all logs preserved before VM shutdown
**Tasks:**
1. Add transcript logging to CaptureFFU.ps1 (network share)
2. Add log file to Orchestrator.ps1 (D: drive)
3. Copy Orchestrator log to network share before shutdown
4. Add script execution timing log

### Plan 24-04: Resource Handling (REL-WINPE-04)

**Scope:** Graceful handling of resource constraints
**Tasks:**
1. Add `Test-WinPEResources` function to CaptureFFU.ps1
2. Check available memory before DISM capture
3. Check network share free space before capture
4. Add warning messages for low-resource conditions

## Code Examples

### Disk Validation Pattern (from ApplyFFU.ps1)

```powershell
# Source: FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1 lines 18-47
function Get-HardDrive() {
    $systemInfo = Get-CimInstance -Class 'Win32_ComputerSystem'
    $manufacturer = $systemInfo.Manufacturer
    $model = $systemInfo.Model
    WriteLog 'Getting Hard Drive info'
    if ($manufacturer -eq 'Microsoft Corporation' -and $model -eq 'Virtual Machine') {
        WriteLog 'Running in a Hyper-V VM. Getting virtual disk on Index 0 and SCSILogicalUnit 0'
        $diskDrive = Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object {
            $_.MediaType -eq 'Fixed hard disk media' `
            -and $_.Model -eq 'Microsoft Virtual Disk' `
            -and $_.Index -eq 0 `
            -and $_.SCSILogicalUnit -eq 0
        }
    }
    else {
        WriteLog 'Not running in a VM. Getting physical disk drive'
        $diskDrive = Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object {
            $_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk'
        }
    }
    return [PSCustomObject]@{
        DeviceID       = $diskDrive.DeviceID
        BytesPerSector = $diskDrive.BytesPerSector
        DiskSize       = $diskDrive.Size
    }
}
```

### Log Preservation Pattern (from ApplyFFU.ps1)

```powershell
# Source: FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1 lines 195-208
function Stop-Script {
    param([string]$Message)
    Write-Host "`n"
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-Error -Message $Message
    }
    WriteLog "Copying dism log to $USBDrive"
    Invoke-Process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y"
    WriteLog "Copying dism log to $USBDrive succeeded"
    Read-Host "Press Enter to exit"
    Exit
}
```

### WinPE-Compatible Network Functions (from CaptureFFU.ps1)

```powershell
# Source: FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1 lines 47-112
function Get-WmiNetworkAdapter {
    param([switch]$ConnectedOnly)

    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop | Where-Object {
            $_.AdapterType -notlike "*software*" -and
            $_.Name -notlike "*Virtual*" -and
            $_.Name -notlike "*Loopback*" -and
            $_.Name -notlike "*Bluetooth*" -and
            $_.NetConnectionID -ne $null
        }

        if ($ConnectedOnly) {
            $adapters = $adapters | Where-Object { $_.NetConnectionStatus -eq 2 }
        }

        # Return with normalized property names
        $adapters | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.NetConnectionID
                InterfaceDescription = $_.Name
                Status = switch ($_.NetConnectionStatus) { 0 {'Disconnected'} 2 {'Up'} 7 {'Disconnected'} default {'Unknown'} }
                MacAddress = $_.MACAddress
            }
        }
    }
    catch {
        Write-Host "Error querying network adapters: $_" -ForegroundColor Red
        return $null
    }
}
```

## Common Pitfalls

### Pitfall 1: Assuming NetAdapter Module Exists

**What goes wrong:** Scripts use Get-NetAdapter, Get-NetIPAddress which don't exist in WinPE
**Why it happens:** Developer tests on full Windows, deploys to WinPE
**How to avoid:** Always use WMI/CIM alternatives (already done in CaptureFFU.ps1)
**Warning signs:** "Command not found" errors on WinPE boot

### Pitfall 2: Silent Script Failures

**What goes wrong:** Script skips operations without user notification
**Why it happens:** Defensive `continue` statements without logging
**How to avoid:** Always log warnings for skipped operations; use `Write-Warning`
**Warning signs:** Build completes but output is incomplete

### Pitfall 3: Lost Logs on Shutdown

**What goes wrong:** Console output lost when WinPE restarts/shuts down
**Why it happens:** RAM disk is volatile; no persistent logging configured
**How to avoid:** Write logs to network share or mounted VHDX partition
**Warning signs:** User reports "it failed" but no log available

### Pitfall 4: Hardcoded Disk Numbers

**What goes wrong:** Wrong disk captured or formatted
**Why it happens:** Boot order can change; USB drives detected before virtual disk
**How to avoid:** Validate disk by model/type, not just index
**Warning signs:** Captured FFU contains wrong content or is empty

## Sources

### Primary (HIGH confidence)
- Microsoft WinPE Documentation - https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-intro
- FFUBuilder codebase analysis - CaptureFFU.ps1, Orchestrator.ps1, ApplyFFU.ps1

### Secondary (MEDIUM confidence)
- Existing fix documentation - docs/fixes/CAPTUREFFU_NETWORK_FIX_SUMMARY.md
- Test file - Tests/Fixes/Test-CaptureFFUWinPECompat.ps1

### Codebase Files Analyzed
- `FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1` (1018 lines)
- `FFUDevelopment/WinPECaptureFFUFiles/AssignDriveLetter.txt`
- `FFUDevelopment/WinPECaptureFFUFiles/Windows/System32/startnet.cmd`
- `FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1` (966 lines)
- `FFUDevelopment/Apps/Orchestration/Orchestrator.ps1` (243 lines)
- `FFUDevelopment/Apps/Orchestration/Run-Sysprep.ps1`
- `FFUDevelopment/Apps/Orchestration/Run-DiskCleanup.ps1`

## Metadata

**Confidence breakdown:**
- WinPE constraints: HIGH - Official Microsoft documentation
- Current script gaps: HIGH - Direct codebase analysis
- Log preservation options: MEDIUM - Based on existing patterns
- Resource handling: MEDIUM - WinPE behavior documented, implementation inferred

**Research date:** 2026-01-24
**Valid until:** 2026-02-24 (30 days - stable domain)
