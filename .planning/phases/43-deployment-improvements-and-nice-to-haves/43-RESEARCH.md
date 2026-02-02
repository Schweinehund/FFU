# Phase 43: Deployment Improvements and Nice-to-Haves - Research

**Researched:** 2026-02-02
**Domain:** WinPE deployment script enhancements
**Confidence:** HIGH

## Summary

Phase 43 modifies ApplyFFU.ps1, the WinPE deployment script that runs on bare metal during FFU deployment. All changes are deployment-time enhancements that improve reliability, user experience, and flexibility.

The primary focus areas are:
1. **Multi-disk selection** - Interactive menu when multiple physical disks detected (DEPLOY-01)
2. **Empty driver folder handling** - Skip empty driver folders gracefully (DEPLOY-03)
3. **Audit mode delay** - 30-second delay for Security Platform initialization (DEPLOY-02)
4. **USB UniqueId** - More reliable USB identification (NICE-01)
5. **Skip driver option** - Support driver-free deployments (NICE-02)

Current implementation findings:
- `Get-HardDrive()` (lines 18-47) currently returns SINGLE disk only - no multi-disk handling
- Driver installation (lines 1192-1310) proceeds if `$DriverSourcePath` is not null - no empty folder check
- No audit mode delay exists in ApplyFFU.ps1 (audit mode config is build-time in BuildFFUVM.ps1)
- USB drive identification uses `Get-USBDrive()` (lines 1-16) via Get-Volume, not WMI SerialNumber/UniqueId
- No "skip drivers" option or configuration exists

**Primary recommendation:** All changes are localized to ApplyFFU.ps1 with no upstream dependencies. Audit mode delay requires understanding WHEN Security Platform initialization occurs (likely during oobeSystem pass, not in WinPE).

## Standard Stack

### Core Technology
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| PowerShell | 5.1+ (WinPE) | Deployment scripting | WinPE native PowerShell environment |
| WMI/CIM cmdlets | Windows-native | Hardware detection | Built-in Windows hardware enumeration |
| DISM | Windows ADK | Driver injection | Industry-standard offline image servicing |
| Get-Disk/Get-Partition | Windows Storage | Disk enumeration | Native PowerShell storage management |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Get-CimInstance | Native | WMI queries | Hardware identification (Win32_DiskDrive, Win32_ComputerSystem) |
| Get-Volume | Native | Volume enumeration | USB drive detection |
| Start-Sleep | Native | Delay injection | Audit mode Security Platform wait |

**Installation:** No installation required - all cmdlets are native to Windows/WinPE.

## Architecture Patterns

### Recommended Approach Structure

```
ApplyFFU.ps1 Modifications:
├── Get-HardDrive() Enhancement (DEPLOY-01)
│   ├── Detect all physical disks (not just first match)
│   ├── Return array if multiple disks found
│   └── Present interactive selection menu
├── Driver Installation Block (DEPLOY-03, NICE-02)
│   ├── Check if driver folder is empty (Get-ChildItem -Recurse -File)
│   ├── Add "skip driver installation" parameter/prompt
│   └── Skip with log message if empty or user requests skip
├── Audit Mode Delay (DEPLOY-02)
│   ├── RESEARCH FINDING: Audit mode runs in BuildFFUVM.ps1, NOT ApplyFFU.ps1
│   ├── ApplyFFU.ps1 copies unattend.xml to W:\Windows\Panther (line 1166-1190)
│   └── Delay must be INJECTED INTO UNATTEND.XML during build (oobeSystem/FirstLogonCommands)
└── USB Identification (NICE-01)
    ├── Replace Get-USBDrive() volume-based detection
    └── Use Get-Disk | Get-PhysicalDisk with UniqueId property
```

### Pattern 1: Multi-Disk Interactive Selection

**What:** When multiple physical disks are detected, present numbered menu similar to existing FFU/PPKG selection logic

**When to use:** In `Get-HardDrive()` after detecting multiple disks with `Get-CimInstance -Class Win32_DiskDrive`

**Example from existing code:**
```powershell
# Existing FFU selection pattern (lines 498-524)
If ($FFUCount -gt 1) {
    WriteLog "Found $FFUCount FFU Files"
    Write-Host "Found $FFUCount FFU Files"
    $array = @()
    for ($i = 0; $i -le $FFUCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; FFUFile = $FFUFiles[$i].FullName }
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, FFUFile
    do {
        try {
            $var = $true
            [int]$FFUSelected = Read-Host 'Enter the FFU number to install'
            $FFUSelected = $FFUSelected - 1
        }
        catch {
            Write-Host 'Input was not in correct format. Please enter a valid FFU number'
            $var = $false
        }
    } until (($FFUSelected -le $FFUCount - 1) -and $var)
}
```

**Adaptation for disks:**
```powershell
# In Get-HardDrive(), after getting all disks
$diskDrives = Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object {
    $_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk'
}
if ($diskDrives.Count -gt 1) {
    # Present menu, return selected disk
}
# Return PSCustomObject with DeviceID, BytesPerSector, DiskSize
```

### Pattern 2: Empty Folder Detection

**What:** Check if driver folder contains any .inf files recursively before attempting injection

**When to use:** Before `if ($null -ne $DriverSourcePath)` block at line 1193

**Example:**
```powershell
# Check if folder is empty of driver files (.inf, .sys, .cat)
if ($DriverSourceType -eq 'Folder') {
    $driverFiles = Get-ChildItem -Path $DriverSourcePath -Recurse -File -Include *.inf,*.sys,*.cat -ErrorAction SilentlyContinue
    if ($driverFiles.Count -eq 0) {
        WriteLog "Driver folder '$DriverSourcePath' is empty. Skipping driver installation."
        Write-Host "Driver folder '$DriverSourcePath' is empty. Skipping driver installation."
        $DriverSourcePath = $null  # Skip driver block
    }
}
```

### Pattern 3: USB UniqueId Identification

**What:** Use Get-Disk/Get-PhysicalDisk with UniqueId instead of volume-based detection

**When to use:** Replace `Get-USBDrive()` function (lines 1-16)

**Current implementation (volume-based):**
```powershell
function Get-USBDrive() {
    $USBDriveLetter = (Get-Volume | Where-Object {
        $_.DriveType -eq 'Removable' -and $_.FileSystemType -eq 'NTFS'
    }).DriveLetter
    # Fallback to "Deploy" labeled fixed volume
}
```

**Recommended approach (UniqueId-based):**
```powershell
# Get removable disks via Get-Disk (more reliable than volume detection)
$usbDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' }
if ($usbDisks) {
    # Get partition with "Deploy" label or NTFS filesystem
    $deployPartition = $usbDisks | Get-Partition | Get-Volume | Where-Object {
        $_.FileSystemLabel -eq 'Deploy' -or ($_.FileSystemType -eq 'NTFS' -and $_.DriveType -eq 'Removable')
    } | Select-Object -First 1
}
```

**Note:** UniqueId property exists on Get-PhysicalDisk, not Get-Disk. However, Get-Disk with BusType filter is MORE reliable than volume-based detection for USB identification.

### Anti-Patterns to Avoid

- **Don't default to disk 0 blindly** - Current `Get-HardDrive()` returns first match; multi-disk scenarios require user selection
- **Don't assume driver folders are populated** - Empty folders should skip gracefully, not fail DISM /Add-Driver
- **Don't inject audit mode delay in ApplyFFU.ps1** - Audit mode is a BUILD-TIME config, not deployment-time. Delay belongs in unattend.xml FirstLogonCommands, not WinPE script.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Disk enumeration | Custom WMI queries with hardcoded filters | Get-Disk + Get-CimInstance Win32_DiskDrive | Native cmdlets handle GPT/MBR, offline/online states, provide structured objects |
| Interactive menus | Custom prompt loops | Adapt existing FFU selection pattern (lines 498-524) | Codebase consistency, proven validation logic |
| Empty folder detection | Manual file counting | Get-ChildItem -Recurse -File -Include *.inf | Handles nested drivers, filters by extension |
| USB identification | Volume enumeration alone | Get-Disk with BusType filter | More reliable than DriveType property, immune to volume label changes |

**Key insight:** ApplyFFU.ps1 already has robust interactive selection patterns (FFU, PPKG, Autopilot, prefixes). Reuse these patterns for disk selection to maintain codebase consistency.

## Common Pitfalls

### Pitfall 1: Audit Mode Delay Placement

**What goes wrong:** Attempting to inject a 30-second delay in ApplyFFU.ps1 before/after driver installation

**Why it happens:** Misunderstanding of Windows deployment phases:
- **WinPE (ApplyFFU.ps1):** Bare-metal environment, applies FFU, injects drivers offline
- **Audit Mode (BuildFFUVM.ps1):** First boot of Windows OS, runs app installations via unattend.xml auditSystem/FirstLogonCommands
- **OOBE (End user):** Final boot after Sysprep /generalize

**How to avoid:** The "Security Platform delay" is needed DURING AUDIT MODE (when apps install), not during WinPE deployment. The delay must be injected into the unattend.xml used by BuildFFUVM.ps1, specifically in:
```xml
<settings pass="auditUser">
  <component name="Microsoft-Windows-Shell-Setup">
    <FirstLogonCommands>
      <SynchronousCommand>
        <CommandLine>cmd /c timeout /t 30 /nobreak</CommandLine>
        <Order>1</Order>
        <Description>Delay for Security Platform initialization</Description>
      </SynchronousCommand>
    </FirstLogonCommands>
  </component>
</settings>
```

**Warning signs:**
- DEPLOY-02 requirement states "30-second delay in audit mode" - this is NOT a deployment script change
- ApplyFFU.ps1 runs in WinPE BEFORE Windows first boot
- Research Finding: BuildFFUVM.ps1 line 4242 "Copying unattend file to boot to audit mode"

**CORRECTED SCOPE FOR DEPLOY-02:** This requirement does NOT belong in Phase 43 (ApplyFFU.ps1 changes). It belongs in a separate phase that modifies the audit-mode unattend.xml template used by BuildFFUVM.ps1.

### Pitfall 2: Multi-Disk Enumeration Edge Cases

**What goes wrong:** Returning wrong disk when multiple fixed disks are present (e.g., dual-boot systems, NVMe + SATA)

**Why it happens:** Current `Get-HardDrive()` filters for "Fixed hard disk media" and returns first match. On multi-disk systems, this could be the wrong disk.

**How to avoid:**
1. Always enumerate ALL fixed hard disks (exclude USB, removable, optical)
2. If count > 1, present interactive menu with disk size, model, and bus type
3. Log selected disk for audit trail
4. Consider VM detection separately (Hyper-V selects specific Index/SCSILogicalUnit)

**Warning signs:**
- System has NVMe (Index 0) and SATA (Index 1) disks
- Get-HardDrive returns Index 0 by default, user wanted Index 1

### Pitfall 3: Empty Driver Folder False Positives

**What goes wrong:** Detecting folder as "empty" when drivers exist in subdirectories

**Why it happens:** Using `(Get-ChildItem $folder).Count` without `-Recurse` flag

**How to avoid:**
```powershell
# WRONG: Only checks top-level folder
$isEmpty = (Get-ChildItem -Path $DriverSourcePath).Count -eq 0

# CORRECT: Checks recursively for .inf files (driver signature)
$driverFiles = Get-ChildItem -Path $DriverSourcePath -Recurse -File -Include *.inf -ErrorAction SilentlyContinue
$isEmpty = ($null -eq $driverFiles -or $driverFiles.Count -eq 0)
```

**Warning signs:**
- Driver folder has nested OEM structure (Dell/HP/Lenovo subfolders)
- Top-level folder only contains subdirectories, no files

### Pitfall 4: USB Drive Detection Fragility

**What goes wrong:** Get-USBDrive() fails when USB drive is "Fixed" (not "Removable") or has no drive letter yet

**Why it happens:** Current implementation relies on `Get-Volume | Where-Object DriveType -eq 'Removable'`, which fails for USB drives reported as "Fixed" by some controllers

**How to avoid:**
```powershell
# Get USB disks via BusType (more reliable than volume DriveType)
$usbDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' }
if ($usbDisks) {
    # Then find the Deploy partition
    foreach ($disk in $usbDisks) {
        $volume = $disk | Get-Partition | Get-Volume | Where-Object {
            $_.FileSystemLabel -eq 'Deploy' -and $_.FileSystemType -eq 'NTFS'
        } | Select-Object -First 1
        if ($volume) {
            return "$($volume.DriveLetter):\"
        }
    }
}
```

**Warning signs:**
- USB drive created with USBImagingToolCreator.ps1 has "Deploy" label but DriveType shows "Fixed"
- Get-USBDrive() falls back to fixed drive search (lines 4-11)

## Code Examples

Verified patterns from existing ApplyFFU.ps1:

### Multi-Disk Selection Menu

```powershell
# Adapt existing FFU selection pattern (lines 498-524)
function Get-HardDrive() {
    $systemInfo = Get-CimInstance -Class 'Win32_ComputerSystem'
    $manufacturer = $systemInfo.Manufacturer
    $model = $systemInfo.Model
    WriteLog 'Getting Hard Drive info'

    if ($manufacturer -eq 'Microsoft Corporation' -and $model -eq 'Virtual Machine') {
        # VM logic unchanged
        WriteLog 'Running in a Hyper-V VM. Getting virtual disk on Index 0 and SCSILogicalUnit 0'
        $diskDrive = Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object {
            $_.MediaType -eq 'Fixed hard disk media' -and
            $_.Model -eq 'Microsoft Virtual Disk' -and
            $_.Index -eq 0 -and
            $_.SCSILogicalUnit -eq 0
        }
    }
    else {
        WriteLog 'Not running in a VM. Getting physical disk drive(s)'
        $diskDrives = @(Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object {
            $_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk'
        })

        if ($diskDrives.Count -gt 1) {
            # DEPLOY-01: Interactive selection
            WriteLog "Found $($diskDrives.Count) physical disks"
            Write-Host "Found $($diskDrives.Count) physical disks"
            $array = @()
            for ($i = 0; $i -lt $diskDrives.Count; $i++) {
                $sizeGB = [math]::Round($diskDrives[$i].Size / 1GB, 2)
                $Properties = [ordered]@{
                    Number = $i + 1
                    Model = $diskDrives[$i].Model
                    SizeGB = $sizeGB
                    Index = $diskDrives[$i].Index
                }
                $array += New-Object PSObject -Property $Properties
            }
            $array | Format-Table -AutoSize -Property Number, Model, SizeGB, Index

            do {
                try {
                    $var = $true
                    [int]$diskSelected = Read-Host 'Enter the disk number to install to'
                    $diskSelected = $diskSelected - 1
                }
                catch {
                    Write-Host 'Input was not in correct format. Please enter a valid disk number'
                    $var = $false
                }
            } until (($diskSelected -ge 0) -and ($diskSelected -lt $diskDrives.Count) -and $var)

            $diskDrive = $diskDrives[$diskSelected]
            WriteLog "User selected disk: Index $($diskDrive.Index), Model $($diskDrive.Model)"
        }
        else {
            $diskDrive = $diskDrives[0]
        }
    }

    # Return PSCustomObject as before
    return [PSCustomObject]@{
        DeviceID       = $diskDrive.DeviceID
        BytesPerSector = $diskDrive.BytesPerSector
        DiskSize       = $diskDrive.Size
    }
}
```

### Empty Driver Folder Check

```powershell
# Insert before line 1193 (if ($null -ne $DriverSourcePath))
if ($null -ne $DriverSourcePath -and $DriverSourceType -eq 'Folder') {
    # DEPLOY-03: Check if folder is empty of driver files
    $driverFiles = Get-ChildItem -Path $DriverSourcePath -Recurse -File -Include *.inf -ErrorAction SilentlyContinue
    if ($null -eq $driverFiles -or $driverFiles.Count -eq 0) {
        WriteLog "Driver folder '$DriverSourcePath' contains no .inf files. Skipping driver installation."
        Write-Host "Driver folder '$DriverSourcePath' contains no .inf files. Skipping driver installation."
        $DriverSourcePath = $null  # Skip driver installation block
    }
    else {
        WriteLog "Found $($driverFiles.Count) driver .inf file(s) in '$DriverSourcePath'"
    }
}
```

### USB Drive Detection with BusType

```powershell
# Replace Get-USBDrive() function (lines 1-16)
function Get-USBDrive() {
    # NICE-01: Use BusType for more reliable USB detection
    WriteLog 'Detecting USB deployment drive'

    # Get all USB disks (more reliable than volume DriveType)
    $usbDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' }

    if ($usbDisks) {
        foreach ($disk in $usbDisks) {
            # Find Deploy partition on USB disk
            $volume = $disk | Get-Partition | Get-Volume | Where-Object {
                $_.FileSystemLabel -eq 'Deploy' -and $_.FileSystemType -eq 'NTFS'
            } | Select-Object -First 1

            if ($volume -and $volume.DriveLetter) {
                $driveLetter = "$($volume.DriveLetter):\"
                WriteLog "Found USB Deploy volume: $driveLetter (Disk $($disk.Number), UniqueId: $($disk.UniqueId))"
                return $driveLetter
            }
        }
    }

    # Fallback: Look for "Deploy" labeled fixed volume (existing logic)
    WriteLog 'No USB Deploy partition found. Searching for fixed "Deploy" volume...'
    $USBDriveLetter = (Get-Volume | Where-Object {
        $_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' -and $_.FileSystemLabel -eq 'Deploy'
    }).DriveLetter

    if ($null -eq $USBDriveLetter) {
        $errorMessage = 'Cannot find USB drive letter. If using a fixed USB drive, name the deployment partition "Deploy".'
        WriteLog ($errorMessage + ' Exiting.')
        Stop-Script -Message $errorMessage
    }

    $USBDriveLetter = $USBDriveLetter + ":\"
    return $USBDriveLetter
}
```

### Skip Driver Installation Option

```powershell
# Add parameter prompt before driver detection (after line 763)
Write-SectionHeader -Title 'Driver Installation Options'
$skipDrivers = $false
if (Test-Path -Path $DriversPath) {
    WriteLog 'Drivers folder detected. Prompting for driver installation preference.'
    Write-Host 'Drivers folder detected.'
    do {
        try {
            $var = $true
            $response = Read-Host 'Install drivers? (Y/N)'
            if ($response -match '^[Yy]') {
                $skipDrivers = $false
            }
            elseif ($response -match '^[Nn]') {
                $skipDrivers = $true
                WriteLog 'User elected to skip driver installation'
                Write-Host 'Driver installation will be skipped.'
            }
            else {
                Write-Host 'Please enter Y or N'
                $var = $false
            }
        }
        catch {
            Write-Host 'Invalid input. Please enter Y or N'
            $var = $false
        }
    } until ($var)
}

# Later, before driver installation block (line 1193)
if ($skipDrivers) {
    WriteLog 'Skipping driver installation per user request (NICE-02)'
    Write-Host 'Skipping driver installation per user request.'
    $DriverSourcePath = $null  # Skip driver block
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single disk assumption | Multi-disk interactive selection | Phase 43 | Prevents accidental wrong-disk wipes on multi-disk systems |
| Blind driver injection | Empty folder check + skip option | Phase 43 | Avoids DISM errors, supports driver-free scenarios |
| Volume-based USB detection | BusType-filtered disk detection | Phase 43 | More reliable for "fixed" USB drives |
| N/A | Audit mode Security Platform delay | NOT Phase 43 | Moved to separate unattend.xml modification |

**Deprecated/outdated:**
- **Audit mode delay in ApplyFFU.ps1**: RESEARCH FINDING - This is NOT a deployment script change. Audit mode runs during BuildFFUVM.ps1 app installation, not in WinPE. Delay belongs in unattend.xml FirstLogonCommands.

## Open Questions

1. **Audit Mode Delay Placement (DEPLOY-02)**
   - What we know: ApplyFFU.ps1 runs in WinPE, audit mode is a build-time Windows boot phase
   - What's unclear: Should DEPLOY-02 be moved to a different phase (unattend.xml modification)?
   - Recommendation: **Exclude DEPLOY-02 from Phase 43**. Create separate phase for audit-mode unattend.xml enhancements in BuildFFUVM.ps1.

2. **USB UniqueId vs BusType**
   - What we know: Get-PhysicalDisk has UniqueId property, Get-Disk has BusType property
   - What's unclear: NICE-01 says "USB uses UniqueId" but BusType filtering is more practical for drive letter lookup
   - Recommendation: Use BusType for identification, log UniqueId for audit trail (best of both worlds)

3. **Skip Driver UI vs Config Parameter**
   - What we know: NICE-02 requires "skip driver installation" option
   - What's unclear: Should this be interactive prompt (like FFU/PPKG selection) or config parameter?
   - Recommendation: Interactive prompt for consistency with existing ApplyFFU.ps1 UX patterns

4. **Empty Folder Detection Scope**
   - What we know: Should skip empty driver folders with log message
   - What's unclear: Should this check WIM files too, or only folders?
   - Recommendation: Check folders only (WIM files can't be "empty" without being corrupt)

## Sources

### Primary (HIGH confidence)
- ApplyFFU.ps1 (C:\claude\FFUBuilder\FFUDevelopment\WinPEDeployFFUFiles\ApplyFFU.ps1) - Full source review lines 1-1326
- BuildFFUVM.ps1 (C:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM.ps1) - Audit mode unattend injection (lines 4169-4401)
- Run-Sysprep.ps1 - Audit mode unattend handling during Sysprep
- USBImagingToolCreator.ps1 - USB creation script (no PPKG/driver logic found)

### Secondary (MEDIUM confidence)
- Phase 35 PLAN (35-01-PLAN.md) - PPKG quoting patterns, xcopy usage precedent
- FFU.Drivers.psm1 - SUBST helper functions for long path handling (lines 949-1105)
- config schema - No SkipDrivers or audit delay config found

### Tertiary (LOW confidence)
- None - all findings from direct source code inspection

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All native Windows/WinPE cmdlets
- Architecture: HIGH - Existing ApplyFFU.ps1 patterns clearly established
- Pitfalls: HIGH - Audit mode delay placement confirmed via BuildFFUVM.ps1 source review

**Research date:** 2026-02-02
**Valid until:** 2026-03-02 (30 days - stable domain, unlikely to change)

**CRITICAL FINDING:** DEPLOY-02 (audit mode delay) does NOT belong in Phase 43. This requirement targets BuildFFUVM.ps1 unattend.xml injection, not ApplyFFU.ps1 deployment script. Recommend splitting Phase 43 into:
- Phase 43A: ApplyFFU.ps1 enhancements (DEPLOY-01, DEPLOY-03, NICE-01, NICE-02) - 4 requirements
- Phase 43B: Audit mode unattend.xml delay (DEPLOY-02) - 1 requirement, different file scope
