# Phase 19: FFU.Media Reliability - Research

**Researched:** 2026-01-23
**Domain:** WinPE media creation, Windows ADK integration, DISM operations
**Confidence:** HIGH

## Summary

This research analyzes the FFU.Media module's current state and identifies gaps between existing implementation and the REL-MED reliability requirements. The module already has substantial infrastructure for DISM pre-flight cleanup and retry logic, but lacks formal dependency validation before operations start and structured remediation guidance for ADK/DISM failures.

The existing FFU.ADK module provides comprehensive ADK validation (`Test-ADKPrerequisites`) with detailed error templates, but FFU.Media doesn't fully leverage this before WinPE creation. The FFU.Preflight module demonstrates the project's standard pattern for validation with remediation (e.g., `Test-FFUWimMount`), which should be applied to media creation.

**Primary recommendation:** Extend FFU.Media with pre-operation validation functions following the established `New-FFUCheckResult` pattern from FFU.Preflight, add error pattern matching with remediation templates similar to FFU.ADK's `$ADKErrorMessageTemplates`, and implement early disk space estimation for ISO creation.

## Standard Stack

The modules use native PowerShell and Windows components:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFU.Core | 1.0.9+ | WriteLog, error handling, cleanup registration | Foundation module |
| FFU.ADK | 1.0.0 | ADK validation, installation | Existing ADK management |
| FFU.Preflight | 1.0.0 | Validation patterns, check result objects | Reference implementation |
| FFU.Constants | 1.1.0 | Configuration values, timeouts | Centralized constants |

### Supporting (Windows Components)
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| DISM.exe | Image servicing, WIM operations | Mounting, package injection |
| Mount-WindowsImage | Native PowerShell WIM mount | New-WinPEMediaNative (default) |
| oscdimg.exe | ISO creation | Final media generation |
| fltmc.exe | Filter driver management | WimMount validation |

### Not Used
| Alternative | Why Not Used |
|-------------|--------------|
| copype.cmd | Legacy method, prone to WIMMount errors |
| External ISO tools | oscdimg.exe is sufficient and available via ADK |

## Architecture Patterns

### Recommended Function Structure

Based on FFU.Preflight and FFU.Imaging patterns, new reliability functions should follow this structure:

```
FFU.Media/
  FFU.Media.psm1         # Extended with new functions
    # Existing functions (keep):
    - Invoke-DISMPreFlightCleanup
    - Invoke-CopyPEWithRetry
    - New-WinPEMediaNative
    - New-PEMedia
    - Get-PEArchitecture

    # New reliability functions (REL-MED-*):
    - Test-WinPEMediaReadiness      # REL-MED-01: Pre-validation
    - Get-ADKToolFailureRemediation # REL-MED-02: Error classification
    - Test-ISOCreationReadiness     # REL-MED-03: Disk space estimation
    - Test-ArchitectureCapability   # REL-MED-04: Hardware validation
```

### Pattern 1: Structured Readiness Result

**What:** Return standardized result objects with Ready/FailureReason/Remediation fields
**When to use:** All pre-operation validation functions
**Source:** FFU.Imaging `Test-FFUCaptureReadiness` pattern

```powershell
function Test-WinPEMediaReadiness {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(...)

    # Validate each dependency in sequence
    # Return structured result with actionable remediation

    [PSCustomObject]@{
        Ready         = $true/$false
        FailureReason = 'ADKNotInstalled'|'WinPEMissing'|'InsufficientSpace'|...
        Message       = "Human-readable description"
        Remediation   = "Try this to fix..."
        Details       = @{ ADKPath = ...; DiskSpaceGB = ... }
    }
}
```

### Pattern 2: Error Pattern Matching with Remediation

**What:** Match error messages/codes to known issues and provide specific remediation
**When to use:** ADK/DISM failure handling in REL-MED-02
**Source:** FFU.ADK `$ADKErrorMessageTemplates` pattern

```powershell
$script:DISMErrorPatterns = @{
    '0x800704DB' = @{
        Name = 'ServiceNotExist'
        Message = 'WIMMount service not registered'
        Remediation = @'
The WIMMount filter driver is not registered. Try:
1. Run: fltmc load WimMount
2. If that fails, repair ADK: adksetup.exe /repair
3. If still failing, reinstall ADK WinPE add-on
'@
    }
    '0x80070005' = @{
        Name = 'AccessDenied'
        Message = 'Access denied during DISM operation'
        Remediation = @'
Access denied. Ensure:
1. PowerShell is running as Administrator
2. No antivirus is blocking DISM operations
3. Target path is not read-only
'@
    }
    # Additional patterns...
}
```

### Pattern 3: Early Disk Space Estimation

**What:** Calculate required space before starting operations
**When to use:** Before ISO creation (REL-MED-03)
**Source:** FFU.Imaging `Test-DiskSpaceForOperation`

```powershell
# ISO creation space estimation formula:
# WinPE media folder size + boot.wim + packages + 10% margin

$estimatedISOSize = Get-WinPEMediaEstimatedSize -WinPEPath $path
$check = Test-DiskSpaceForOperation -Path $OutputISO `
    -RequiredBytes $estimatedISOSize -SafetyMarginPercent 10 `
    -OperationName 'ISO creation'
```

### Anti-Patterns to Avoid

- **Late validation:** Don't validate dependencies mid-operation; validate all before starting
- **Vague errors:** Don't return generic "operation failed" - include specific remediation
- **Assumption of success:** Don't proceed without checking return values from `Test-*` functions

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ADK validation | Custom registry checks | `Test-ADKPrerequisites` (FFU.ADK) | Already handles 6 check types with templates |
| Disk space checks | Simple `Get-PSDrive` | `Test-DiskSpaceForOperation` (FFU.Imaging) | Handles safety margins, error cases |
| WIMMount validation | Service status check | `Test-FFUWimMount` (FFU.Preflight) | Includes auto-repair, fltmc check |
| Check result objects | Inline hashtables | `New-FFUCheckResult` (FFU.Preflight) | Standardized format, duration tracking |
| Structured logging | Custom Write-Host | `WriteLog` (FFU.Core) | ThreadJob compatible, file logging |

**Key insight:** The project has established patterns for validation with remediation. New reliability functions should use these patterns, not invent new ones.

## Common Pitfalls

### Pitfall 1: Missing WIMMount Pre-Check

**What goes wrong:** `Mount-WindowsImage` or `Add-WindowsPackage` fails with 0x800704DB
**Why it happens:** WIMMount filter driver not loaded, even though module functions exist
**How to avoid:** Call `Test-FFUWimMount` before any WIM mount operation
**Warning signs:** Errors mentioning "service does not exist" or "filter driver"

**Current gap:** `New-WinPEMediaNative` calls `Test-FFUWimMount` at line 549-563, but:
1. Only if FFU.Preflight module is loaded
2. `New-PEMedia` at line 895 does NOT call it before mounting boot.wim

### Pitfall 2: ADK Validation Bypass

**What goes wrong:** WinPE creation fails because ADK components missing
**Why it happens:** Code assumes ADK is installed without verification
**How to avoid:** Call `Test-ADKPrerequisites` before any media creation
**Warning signs:** "copype.cmd not found", "oscdimg.exe not found"

**Current gap:** `New-PEMedia` doesn't call `Test-ADKPrerequisites` before operations. It trusts that the caller already validated ADK.

### Pitfall 3: Disk Space Exhaustion During ISO Creation

**What goes wrong:** oscdimg.exe fails mid-write when disk fills up
**Why it happens:** No pre-estimation of final ISO size
**How to avoid:** Calculate estimated ISO size, verify space before starting
**Warning signs:** "There is not enough space on the disk", partial ISO files

**Current gap:** `New-PEMedia` checks space for WinPE creation (line 831) but not for final ISO output.

### Pitfall 4: Architecture Mismatch

**What goes wrong:** Build fails because ARM64 ADK tools used on x64 system (or vice versa)
**Why it happens:** No validation that requested architecture is actually buildable
**How to avoid:** Verify system can build for requested architecture before starting
**Warning signs:** "The image platform does not match the target processor"

**Current gap:** No validation that the system supports building for the requested architecture.

## Code Examples

### REL-MED-01: WinPE Dependency Validation

Verified pattern from existing code (FFU.Imaging Test-FFUCaptureReadiness):

```powershell
function Test-WinPEMediaReadiness {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture,

        [Parameter(Mandatory)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory)]
        [string]$ADKPath,

        [Parameter()]
        [switch]$CreateCapture,

        [Parameter()]
        [switch]$CreateDeploy,

        [Parameter()]
        [string]$OutputISO
    )

    # 1. ADK Prerequisites
    $adkResult = Test-ADKPrerequisites -WindowsArch $Architecture -ThrowOnFailure $false
    if (-not $adkResult.IsValid) {
        return [PSCustomObject]@{
            Ready         = $false
            FailureReason = 'ADKValidation'
            Message       = "ADK validation failed: $($adkResult.Errors -join '; ')"
            Remediation   = $adkResult.Errors | ForEach-Object {
                Get-ADKToolFailureRemediation -ErrorMessage $_
            } -join "`n"
            Details       = @{ ADKResult = $adkResult }
        }
    }

    # 2. WIMMount Service
    $wimMountResult = Test-FFUWimMount -AttemptRemediation
    if ($wimMountResult.Status -eq 'Failed') {
        return [PSCustomObject]@{
            Ready         = $false
            FailureReason = 'WIMMount'
            Message       = $wimMountResult.Message
            Remediation   = $wimMountResult.Remediation
            Details       = @{ WimMountResult = $wimMountResult }
        }
    }

    # 3. Disk Space for WinPE working directory
    $winPEPath = Join-Path $FFUDevelopmentPath 'WinPE'
    $spaceCheck = Test-DiskSpaceForOperation -Path $winPEPath `
        -RequiredBytes 15GB -SafetyMarginPercent 10 `
        -OperationName 'WinPE media creation'

    if (-not $spaceCheck.HasSufficientSpace) {
        return [PSCustomObject]@{
            Ready         = $false
            FailureReason = 'InsufficientSpace'
            Message       = $spaceCheck.Message
            Remediation   = $spaceCheck.Remediation
            Details       = @{ SpaceCheck = $spaceCheck }
        }
    }

    # 4. ISO output space (if creating ISO)
    if ($OutputISO) {
        $isoSpaceCheck = Test-ISOCreationReadiness -WinPEPath $winPEPath `
            -OutputISOPath $OutputISO
        if (-not $isoSpaceCheck.HasSufficientSpace) {
            return [PSCustomObject]@{
                Ready         = $false
                FailureReason = 'ISOSpaceInsufficient'
                Message       = $isoSpaceCheck.Message
                Remediation   = $isoSpaceCheck.Remediation
                Details       = @{ ISOSpaceCheck = $isoSpaceCheck }
            }
        }
    }

    # All checks passed
    [PSCustomObject]@{
        Ready         = $true
        Message       = "Ready for WinPE media creation"
        Details       = @{
            ADKPath     = $ADKPath
            Architecture = $Architecture
            ADKVersion  = $adkResult.ADKVersion
        }
    }
}
```

### REL-MED-02: Error Pattern Remediation

Pattern from FFU.ADK `$script:ADKErrorMessageTemplates`:

```powershell
$script:DISMErrorRemediation = @{
    '0x800704DB' = @{
        Code = 'ServiceNotExist'
        ShortMessage = 'WIMMount service not available'
        Remediation = @'
The WIMMount filter driver is not registered. Try these steps:

1. Load the filter driver manually:
   fltmc load WimMount

2. If step 1 fails, register the service:
   sc create wimmount type= filesys binPath= system32\drivers\wimmount.sys
   fltmc load WimMount

3. If still failing, repair ADK installation:
   - Run: adksetup.exe /repair
   - Or reinstall Windows PE add-on

4. Check Event Viewer > System for related errors
'@
    }

    '0x80070005' = @{
        Code = 'AccessDenied'
        ShortMessage = 'Access denied during DISM operation'
        Remediation = @'
Access was denied. Check the following:

1. Run PowerShell as Administrator
2. Temporarily disable antivirus (Windows Defender, third-party)
3. Add exclusions for:
   - C:\Windows\System32\dism.exe
   - C:\Windows\System32\DismHost.exe
   - Your FFUDevelopment folder
4. Verify the target path is not read-only
5. Check if another process has files locked (use Process Monitor)
'@
    }

    '0x800F081F' = @{
        Code = 'SourceNotFound'
        ShortMessage = 'Source files not found'
        Remediation = @'
Required source files were not found. Check:

1. ADK installation is complete (both ADK and WinPE add-on)
2. Verify winpe.wim exists at:
   <ADK Path>\Windows Preinstallation Environment\<arch>\en-us\winpe.wim
3. Reinstall WinPE add-on if missing
'@
    }
}

function Get-ADKToolFailureRemediation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ErrorMessage,

        [Parameter()]
        [string]$ToolName = 'DISM'
    )

    # Match against known error patterns
    foreach ($pattern in $script:DISMErrorRemediation.Keys) {
        if ($ErrorMessage -match $pattern) {
            $info = $script:DISMErrorRemediation[$pattern]
            return [PSCustomObject]@{
                ErrorCode    = $pattern
                ErrorName    = $info.Code
                Message      = $info.ShortMessage
                Remediation  = $info.Remediation
                ToolName     = $ToolName
            }
        }
    }

    # Generic remediation if no pattern matches
    [PSCustomObject]@{
        ErrorCode    = 'Unknown'
        ErrorName    = 'UnclassifiedError'
        Message      = "Unrecognized $ToolName error"
        Remediation  = @"
An unrecognized error occurred during $ToolName operation.

Try these general troubleshooting steps:
1. Run: Dism.exe /Cleanup-Mountpoints
2. Restart TrustedInstaller service
3. Check DISM logs: $env:SystemRoot\Logs\DISM\dism.log
4. Review Event Viewer > Application for DISM events
5. Try running with -UpdateADK `$true to reinstall ADK

Original error: $ErrorMessage
"@
        ToolName     = $ToolName
    }
}
```

### REL-MED-03: ISO Space Estimation

```powershell
function Test-ISOCreationReadiness {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$WinPEPath,

        [Parameter(Mandatory)]
        [string]$OutputISOPath,

        [Parameter()]
        [int]$SafetyMarginPercent = 10
    )

    # Estimate ISO size from WinPE media folder
    $mediaPath = Join-Path $WinPEPath 'media'

    if (-not (Test-Path $mediaPath)) {
        return [PSCustomObject]@{
            HasSufficientSpace = $false
            EstimatedSizeGB    = 0
            AvailableGB        = 0
            Message            = "WinPE media folder not found: $mediaPath"
            Remediation        = "Ensure WinPE media was created before calling ISO creation."
        }
    }

    # Calculate folder size
    $folderSize = (Get-ChildItem -Path $mediaPath -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum

    # ISO overhead is typically minimal (metadata only)
    # Add safety margin
    $estimatedSize = [int64]($folderSize * (1 + $SafetyMarginPercent / 100))

    # Use existing disk space check function
    $spaceCheck = Test-DiskSpaceForOperation -Path $OutputISOPath `
        -RequiredBytes $estimatedSize -SafetyMarginPercent 0 `
        -OperationName 'ISO creation'

    [PSCustomObject]@{
        HasSufficientSpace = $spaceCheck.HasSufficientSpace
        EstimatedSizeGB    = [math]::Round($estimatedSize / 1GB, 2)
        AvailableGB        = $spaceCheck.AvailableGB
        MediaFolderSizeGB  = [math]::Round($folderSize / 1GB, 2)
        Message            = $spaceCheck.Message
        Remediation        = $spaceCheck.Remediation
    }
}
```

### REL-MED-04: Architecture Capability Check

```powershell
function Test-ArchitectureCapability {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x64', 'arm64', 'x86')]
        [string]$TargetArchitecture,

        [Parameter(Mandatory)]
        [string]$ADKPath
    )

    # Get host architecture
    $hostArch = switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture) {
        'X64'   { 'x64' }
        'Arm64' { 'arm64' }
        'X86'   { 'x86' }
        default { 'unknown' }
    }

    # Check ADK has tools for target architecture
    $archFolder = if ($TargetArchitecture -eq 'x64') { 'amd64' } else { $TargetArchitecture }
    $oscdimgPath = Join-Path $ADKPath "Assessment and Deployment Kit\Deployment Tools\$archFolder\Oscdimg"
    $winPEPath = Join-Path $ADKPath "Assessment and Deployment Kit\Windows Preinstallation Environment\$archFolder"

    $hasOscdimg = Test-Path (Join-Path $oscdimgPath 'oscdimg.exe')
    $hasWinPE = Test-Path (Join-Path $winPEPath 'en-us\winpe.wim')

    # Determine if build is supported
    $canBuild = $hasOscdimg -and $hasWinPE

    if (-not $canBuild) {
        $missing = @()
        if (-not $hasOscdimg) { $missing += "oscdimg.exe ($archFolder)" }
        if (-not $hasWinPE) { $missing += "winpe.wim ($archFolder)" }

        return [PSCustomObject]@{
            CanBuild          = $false
            TargetArchitecture = $TargetArchitecture
            HostArchitecture   = $hostArch
            Message           = "Missing ADK components for $TargetArchitecture architecture"
            Remediation       = @"
The following ADK components are missing for $TargetArchitecture builds:
$($missing | ForEach-Object { "  - $_" } | Out-String)

To fix:
1. Re-run ADK setup and ensure $TargetArchitecture components are selected
2. Or reinstall ADK with: adksetup.exe /features OptionId.DeploymentTools
3. Also install WinPE add-on with $TargetArchitecture support
"@
            Details           = @{
                MissingComponents = $missing
                OscdimgPath      = $oscdimgPath
                WinPEPath        = $winPEPath
            }
        }
    }

    # Cross-architecture notes
    $crossArchNote = if ($hostArch -ne $TargetArchitecture) {
        "Note: Building $TargetArchitecture media from $hostArch host. " +
        "This is supported but requires target architecture ADK components."
    } else { $null }

    [PSCustomObject]@{
        CanBuild           = $true
        TargetArchitecture = $TargetArchitecture
        HostArchitecture   = $hostArch
        Message            = "Architecture $TargetArchitecture is supported. $crossArchNote"
        Details            = @{
            OscdimgPath = Join-Path $oscdimgPath 'oscdimg.exe'
            WinPEWim    = Join-Path $winPEPath 'en-us\winpe.wim'
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| copype.cmd | New-WinPEMediaNative | v1.3.7 | Avoids WIMMount filter issues |
| No pre-validation | Invoke-DISMPreFlightCleanup | Existing | 93% failure reduction |
| Generic errors | ADKErrorMessageTemplates | FFU.ADK | Actionable remediation |
| Inline validation | New-FFUCheckResult | FFU.Preflight | Standardized results |

**Current state:**
- FFU.Media has good DISM cleanup and retry infrastructure
- FFU.ADK has comprehensive validation with templates
- FFU.Preflight has standardized check result patterns
- Gap: FFU.Media doesn't orchestrate these into pre-operation validation

## Open Questions

1. **Architecture cross-compilation scope**
   - What we know: ADK supports building ARM64 on x64 and vice versa
   - What's unclear: Should we validate CPU capabilities for target arch?
   - Recommendation: Validate ADK component presence, not CPU capabilities

2. **ISO size estimation accuracy**
   - What we know: Folder size + overhead is reasonable estimate
   - What's unclear: How much overhead does oscdimg add exactly?
   - Recommendation: Use 10% margin, measure in testing

## Sources

### Primary (HIGH confidence)
- FFU.Media.psm1 - Direct code analysis of existing functions
- FFU.ADK.psm1 - Direct code analysis of validation patterns
- FFU.Preflight.psm1 - Direct code analysis of check result patterns
- FFU.Imaging.psm1 - Direct code analysis of reliability patterns (Phase 18)
- FFU.Constants.psm1 - Centralized configuration values

### Secondary (MEDIUM confidence)
- Existing Pester tests (FFU.Media.Tests.ps1, FFU.ADK.Tests.ps1, FFU.Imaging.Reliability.Tests.ps1)
- CLAUDE.md project documentation

### Tertiary (LOW confidence)
- Microsoft DISM documentation (training data, not verified current)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Based on direct code analysis of existing modules
- Architecture patterns: HIGH - Patterns extracted from working Phase 18 code
- Pitfalls: HIGH - Identified from gaps between requirements and current implementation
- Code examples: HIGH - Adapted from verified working patterns in codebase

**Research date:** 2026-01-23
**Valid until:** 60 days (stable internal patterns, no external dependencies)
