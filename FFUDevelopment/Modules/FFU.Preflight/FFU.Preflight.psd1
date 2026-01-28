#
# Module manifest for module 'FFU.Preflight'
#

@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'FFU.Preflight.psm1'

    # Version number of this module.
    ModuleVersion = '1.6.0'

    # ID used to uniquely identify this module
    GUID = 'a7e8b3f2-c4d5-4e6a-9b8c-1d2e3f4a5b6c'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'Community'

    # Copyright statement for this module
    Copyright = '(c) 2025 FFU Builder Team. MIT License.'

    # Description of the functionality provided by this module
    Description = 'Comprehensive pre-flight validation system for FFU Builder. Provides tiered environment checks (Administrator, PowerShell 7+, Hyper-V, ADK, disk space, network, antivirus) with actionable remediation guidance. Fail-fast design detects all issues before build operations begin.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    # Note: FFU.Core is OPTIONAL - only loaded dynamically when ConfigFile validation is used
    # All other validation is self-contained to avoid WriteLog dependency issues
    RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        # Main entry point
        'Invoke-FFUPreflight',
        # Tier 1: Critical (Always Run, Blocking)
        'Test-FFUAdministrator',
        'Test-FFUPowerShellVersion',
        'Test-FFUHyperV',
        # Tier 2: Feature-Dependent (Conditional, Blocking)
        'Test-FFUADK',
        'Test-FFUDiskSpace',
        'Test-FFUNetwork',
        'Test-FFUConfigurationFile',
        'Test-FFUWimMount',
        'Test-FFUVmxToolkit',
        'Test-FFUHyperVSwitchConflict',
        'Test-FFUVMwareDrivers',
        'Test-FFUVMwareBridgeConfiguration',
        'Test-FFUHostIPAddress',
        # REL-PRE-01: Enhanced prerequisite detection
        'Test-FFUVMResources',
        'Test-FFUScratchSpace',
        'Test-FFUDISMState',
        # Tier 3: Recommended (Warnings Only)
        'Test-FFUAntivirusExclusions',
        # Tier 4: Cleanup (Pre-Remediation)
        'Invoke-FFUDISMCleanup',
        # Helper functions
        'New-FFUCheckResult',
        'Get-FFURequirements',
        # Phase 29: Apps.iso Disk Estimation
        'Get-AppsISODiskEstimate',
        'Test-FFUAppsISODiskSpace',
        # Capture location disk space
        'Test-FFUCaptureDiskSpace'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('FFU', 'Windows', 'Preflight', 'Validation', 'Hyper-V', 'ADK', 'Prerequisites')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/Schweinehund/FFU/blob/feature/improvements-and-fixes/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/Schweinehund/FFU'

            # ReleaseNotes of this module
            ReleaseNotes = @'
# Release Notes - FFU.Preflight v1.6.0

## v1.6.0 (2026-01-27)
### Capture Location Disk Space Pre-flight Check
- **NEW**: Test-FFUCaptureDiskSpace - Validates FFU capture location has sufficient free space
  - Checks capture output drive for minimum 20GB free (configurable MinimumFreeGB)
  - Returns Passed (>30GB), Warning (20-30GB), or Failed (<20GB)
  - Prevents 30+ minute build from failing at the very end due to insufficient space
  - Provides actionable remediation with cleanup commands
- **ENHANCED**: Invoke-FFUPreflight now accepts FFUCaptureLocation parameter
  - Defaults to $FFUDevelopmentPath\FFU when not specified
  - Integrated into Tier 2 validation (blocking on failure)
- Part of capture error reporting improvements

---

## v1.5.0 (2026-01-25)
### Phase 30: VM Host IP Pre-flight Integration
- **ENHANCED**: Invoke-FFUPreflight now accepts VMHostIPAddress parameter
- **INTEGRATED**: Test-FFUHostIPAddress called in Tier 2 validation when:
  - HypervisorType is 'VMware'
  - VMHostIPAddress is configured (non-empty)
- **WARNING-LEVEL**: IP not found on host produces warning (non-blocking)
  - Allows build to proceed for manual intervention scenarios
  - Follows NET-02 requirement for non-blocking validation
- **SEVERITY TRACKING**: WarningCount incremented for warning results (REL-PRE-04)
- **SKIP LOGIC**: Check skipped with descriptive reason when:
  - Using Hyper-V hypervisor (Hyper-V has different network model)
  - No IP configured (InstallApps may be disabled)
- Part of Phase 30: VM Host IP Pre-flight Integration (NET-02 gap closure)

---

## v1.4.0 (2026-01-25)
### Phase 29: Apps.iso Disk Estimation
- **NEW**: Get-AppsISODiskEstimate - Calculates required disk space for Apps.iso creation
  - Measures actual component sizes when folders exist
  - Falls back to empirical estimates for planned downloads
  - Includes content, ISO, temp, and total required space
  - Tracks which values are actual vs estimated
- **NEW**: Test-FFUAppsISODiskSpace - Pre-flight validation for Apps.iso disk space
  - Calls Get-AppsISODiskEstimate for requirements
  - Compares against available drive space
  - Returns Passed/Failed with detailed breakdown
  - Provides actionable remediation steps on failure
  - Integrated into Invoke-FFUPreflight Tier 2 (when InstallApps enabled)
- Part of Phase 29: Smart Apps.iso & Disk Estimation (DISK-01, DISK-02)

---

## v1.3.0 (2026-01-24)
### REL-PRE-01: Enhanced Prerequisite Detection
- **NEW**: Test-FFUVMResources - Validates VM creation prerequisites
  - Checks available RAM vs required (VM + host overhead)
  - Validates CPU cores and virtualization extensions
  - Returns detailed resource availability metrics
- **NEW**: Test-FFUScratchSpace - Validates working directory usability
  - Detects filesystem type (warns for FAT32 4GB limit)
  - Identifies network paths (warns for performance)
  - Validates path exists or parent is writable
- **NEW**: Test-FFUDISMState - Validates DISM health
  - Checks for orphaned mount points via dism /Get-MountedImageInfo
  - Auto-remediation via Cleanup-Wim/Cleanup-Mountpoints
  - Tracks remediation attempts in details
- **ENHANCED**: Invoke-FFUPreflight integration
  - VMResources check in Tier 1 when CreateVM enabled
  - ScratchSpace and DISMState checks in Tier 2
  - Fail-fast ordering maintained
- **TESTS**: Added 30 Pester tests for REL-PRE-01 requirements

### Part of Phase 22 FFU.Preflight Reliability (v1.9.0 Milestone)

---

## v1.2.0 (2026-01-24)
### REL-PRE-02: Remediation Steps Quality
- **NEW**: New-FFURemediationBlock - Standardized remediation string builder
  - Produces ISSUE, IMPACT, FIX, and VERIFY sections
  - Accepts PowerShellCommands array for copy-paste ready commands
  - Accepts ManualSteps array for step-by-step guidance
  - Includes VerifyCommand for confirming fix success
- **ENHANCED**: Tier 1 checks use standardized remediation format:
  - Test-FFUAdministrator: Includes Start-Process and gsudo commands
  - Test-FFUPowerShellVersion: Includes winget install command
  - Test-FFUHyperV: Separate Server/Client commands with DISM alternative
- **ENHANCED**: Tier 2 checks use standardized remediation format:
  - Test-FFUADK: Includes ADK download URL and FFU Builder auto-install
  - Test-FFUDiskSpace: Structured error messaging
- **TESTS**: Added 21 Pester tests for REL-PRE-02 requirements

### Part of Phase 22 FFU.Preflight Reliability (v1.9.0 Milestone)

---

## v1.1.0 (2026-01-24)
### REL-PRE-03: WIMMount Repair Resilience
- **NEW**: Invoke-WimMountRepairWithRetry - Retry helper with exponential backoff
- **ENHANCED**: Test-FFUWimMount now uses 5 repair strategies with retry logic:
  - Strategy 1: Registry repair (idempotent, no retry needed)
  - Strategy 2: Service start via sc.exe with retry (MaxRetries: 3, BaseDelay: 2s)
  - Strategy 3: Filter load via fltmc with retry (MaxRetries: 3, BaseDelay: 2s)
  - Strategy 4: Driver re-registration via rundll32 (MaxRetries: 2, BaseDelay: 3s)
  - Strategy 5: Filter Manager restart as last resort
- **ENHANCED**: Exponential backoff with jitter prevents thundering herd
- **ENHANCED**: Clear "All repair strategies exhausted" message on failure

### Internal Helper Functions
- Invoke-WimMountRepairWithRetry: Wraps repair operations with retry logic
  - Parameters: RepairAction, ActionName, MaxRetries, BaseDelaySeconds, Details
  - Returns: Boolean success indicator
  - Implements: Exponential backoff (BaseDelay * 2^(attempt-1) + jitter)

### Part of Phase 22 FFU.Preflight Reliability (v1.9.0 Milestone)

---

## v1.0.14 (2026-01-20)
### Enhanced WimMount Failure Scenario Detection
- **NEW**: Test-WimMountDriverIntegrity - SHA256 hash verification for wimmount.sys
- **NEW**: Test-WimMountAltitudeConflict - Filter altitude conflict detection at 180700
- **NEW**: Test-WimMountSecuritySoftwareBlocking - EDR/security software detection
- **ENHANCED**: Test-FFUWimMount now includes enhanced diagnostic details:
  - Driver hash and file size in details
  - Altitude conflict information with conflicting filter names
  - Security software detection (CrowdStrike, SentinelOne, Carbon Black, etc.)
- **ENHANCED**: Remediation guidance includes scenario-specific steps

### Helper Functions (Internal)
- Test-WimMountDriverIntegrity: Verifies driver file integrity via hash comparison
- Test-WimMountAltitudeConflict: Detects filters at WimMount's altitude (180700)
- Test-WimMountSecuritySoftwareBlocking: Identifies running EDR/security products

### New Details Fields
- WimMountDriverHash: SHA256 hash of wimmount.sys
- WimMountDriverSize: File size in bytes
- DriverIntegrityIssue: Description if driver corrupted/missing
- AltitudeConflict: Boolean indicating altitude conflict
- ConflictingFilters: Array of conflicting filter details
- SecuritySoftwareDetected: Array of detected security products
- SecurityBlockingLikely: Boolean indicating if security software may block

### Part of Phase 10 Dependency Resilience (DEP-03)

---

## v1.0.12 (2026-01-20)
### vmxtoolkit Now Optional for VMware Builds
- **CHANGED**: Test-FFUVmxToolkit returns 'Warning' instead of 'Failed' when module missing
- **CHANGED**: Invoke-FFUPreflight treats vmxtoolkit warnings as non-blocking
- **REASON**: vmrun.exe and filesystem search fallback provide full VM management capability
- **IMPACT**: VMware builds no longer require vmxtoolkit installation

### Details
- vmxtoolkit is optional - vmrun.exe handles all VM operations directly
- VMwareProvider now includes SearchVMXFilesystem method for VM discovery
- GetVM and GetAllVMs use filesystem fallback when vmxtoolkit unavailable
- Warning message clearly indicates vmrun.exe fallback is available
- Part of Phase 10 Dependency Resilience (DEP-01)

---

## v1.0.11 (2026-01-18)
### Tech Debt: Replace Write-Host with Write-Information
- **CHANGED**: Replaced 2 Write-Host calls in documentation examples with Write-Information
- **SCOPE**: Example code in Test-FFUHyperVSwitchConflict and Test-FFUVMwareBridgeConfiguration
- **REASON**: Consistency with module's proper output stream usage
- **NOTE**: Module already uses Write-Information/Write-Warning/Write-Error throughout

### Details
- Research initially estimated 91 Write-Host occurrences, actual count was 2
- Both occurrences were in comment-based help .EXAMPLE sections
- Module production code was already correctly using proper output streams
- Part of DEBT-03 tech debt cleanup initiative

---

## v1.0.10 (2026-01-16)
### New Feature: VMware Bridge Configuration Guidance
- **NEW**: Test-FFUVMwareBridgeConfiguration detects network adapter configuration
- **WARNING-level** check (non-blocking) when using VMware hypervisor
- Identifies recommended adapter for bridging (has internet, not VPN)
- Detects problematic VPN adapters (GlobalProtect PANGP, Cisco AnyConnect, etc.)
- Provides step-by-step Virtual Network Editor configuration guidance

### Problem Addressed
VMware auto-bridging may select wrong adapter (VPN or disconnected) causing
Error 53 (network path not found) during FFU capture. No programmatic way
to configure VMware bridging on Windows - requires manual Virtual Network Editor.

### Details
- Check only runs when HypervisorType is 'VMware'
- Returns 'Passed' if suitable adapter found with no VPN adapters present
- Returns 'Warning' if VPN adapters detected or netmap.conf missing
- Returns 'Failed' if no adapter with internet connectivity found
- Detailed remediation includes vmnetcfg.exe steps and adapter selection guidance

---

## v1.0.9 (2026-01-16)
### New Feature: Hyper-V External Switch Conflict Detection for VMware
- **NEW**: Test-FFUHyperVSwitchConflict detects External Hyper-V virtual switches
- **BLOCKING** check when using VMware hypervisor
- Prevents Error 53 (network path not found) during FFU capture

### Root Cause Addressed
When a Hyper-V External Virtual Switch exists, it bridges to a physical adapter
(e.g., WiFi). VMware's auto-bridging then selects a different adapter (e.g.,
disconnected Ethernet), resulting in network connectivity failure during capture.

### Remediation
- User must delete the External Hyper-V switch before using VMware
- Clear guidance provided: Hyper-V Manager → Virtual Switch Manager → Remove
- PowerShell command included: Remove-VMSwitch -Name '<name>' -Force

### Details
- Check only runs when HypervisorType is 'VMware'
- Returns 'Skipped' for Hyper-V or Auto
- Returns 'Passed' if Hyper-V not accessible (conflict impossible)
- Returns 'Failed' with detailed remediation if External switch exists

---

## v1.0.8 (2026-01-13)
### New Feature: VMware Network Driver Validation
- **NEW**: Test-FFUVMwareDrivers validates Intel e1000e drivers for WinPE capture
- Only runs when HypervisorType is 'VMware'
- Checks VMwareDrivers folder for network driver INF files
- Informational check - drivers auto-download during build if missing
- Provides remediation guidance if folder exists but is empty

### Details
- Returns 'Passed' if folder missing (auto-download will occur)
- Returns 'Warning' if folder exists but empty (user action needed)
- Returns 'Passed' with details if drivers present
- Integrated into Tier 2 feature-dependent checks

---

## v1.0.7 (2026-01-12)
### New Feature: vmxtoolkit Pre-flight Check for VMware
- **NEW**: Test-FFUVmxToolkit validates vmxtoolkit PowerShell module availability
- Auto-remediation: Attempts to install from PSGallery when not found
- Integrated into Invoke-FFUPreflight (runs when HypervisorType is VMware)
- vmxtoolkit provides PowerShell cmdlets wrapping vmrun.exe for VMware Workstation
- Supports vmxtoolkit/vmrun architecture replacing vmrest REST API

### Details
- Check only runs when HypervisorType is set to 'VMware' or 'Auto-detect' resolves to VMware
- Falls back gracefully to direct vmrun.exe if module installation fails
- Module is optional but recommended for enhanced VMware operations

---

## v1.0.6 (2026-01-11)
### CRITICAL FIX: Test-FFUWimMount Returns Multiple Results
- **BUG**: Function was outputting multiple result objects to pipeline instead of one
- **SYMPTOM**: Concatenated error messages like:
  "WimMount filter is loaded and functional WimMount filter loaded after automatic repair WimMount filter not loaded (BLOCKING)"
- **CAUSE**: Missing `return` statements after successful New-FFUCheckResult calls
- **FIX**: Added `return` at:
  1. Initial success path (WimMount filter already loaded)
  2. Remediation success path (WimMount loaded after repair)
- **IMPACT**: Function now returns exactly one result object as expected

---

## v1.0.4 (2025-12-17)
### Enhanced WimMount Detection and Auto-Repair
- **PRIMARY CHECK**: Now uses `fltmc filters` as THE definitive indicator
  - If WimMount appears in filter list -> PASSED (no further checks needed)
  - If WimMount not found -> attempt auto-repair
- **AUTO-REPAIR**: Silently repairs WimMount when filter not loaded:
  1. Verify wimmount.sys driver file exists
  2. Create/recreate service registry entries
  3. Create filter instance with Altitude 180700
  4. Start service via `sc start wimmount`
  5. Load filter via `fltmc load WimMount`
  6. Re-verify filter is now loaded
- **FAIL WITH DIAGNOSTICS**: If repair fails, provides detailed diagnostic info:
  - Filter loaded status, driver file status, registry status
  - All repair actions attempted and their results
  - Manual remediation steps including security software guidance
- **New Details Fields**:
  - WimMountFilterLoaded (primary indicator)
  - WimMountDriverVersion
  - RegistryExists
  - FilterInstanceExists
  - RemediationSuccess

### Behavior
- Default: Auto-repair is enabled (`-AttemptRemediation:$true`)
- Detection only: Use `-AttemptRemediation:$false`
- Returns PASSED if WimMount in fltmc filters (before or after repair)
- Returns FAILED with full diagnostics if repair unsuccessful

---

## v1.0.3 (2025-12-15)
### CRITICAL FIX: WimMount Failures Now Blocking
- **REVERTED v1.0.2 CHANGE**: WIMMount service issues are now BLOCKING failures again
- Test-FFUWimMount returns FAILED (not WARNING) when WIMMount issues detected
- Removed incorrect UsingNativeDISM fallback logic

### Root Cause
The v1.0.2 change was based on an INCORRECT assumption that PowerShell DISM cmdlets
(Mount-WindowsImage/Dismount-WindowsImage) do not require the WIMMount filter driver.

**FACT: Both ADK dism.exe AND native PowerShell DISM cmdlets require the WIMMount
filter driver service.** The cmdlets are just PowerShell wrappers around the same
underlying DISM infrastructure.

### Impact of v1.0.2 Bug
Users with corrupted WIMMount saw a WARNING during pre-flight, the build proceeded,
then failed 5 minutes later at Mount-WindowsImage with error 0x800704db
("The specified service does not exist").

### Behavior After This Fix
- Test-FFUWimMount returns Status 'Passed' when WIMMount is healthy
- Test-FFUWimMount returns Status 'Failed' when WIMMount has issues (BLOCKING)
- Build will NOT proceed if WIMMount validation fails
- Users get clear remediation steps upfront, not a cryptic failure mid-build

---

## v1.0.2 (2025-12-12) - SUPERSEDED
### Fix: WimMount Validation False Positives
- **BREAKING CHANGE MITIGATION**: WIMMount service issues no longer block builds
- Changed Test-FFUWimMount to return WARNING instead of FAILED when WIMMount issues detected
- Added sc.exe fallback when Get-Service fails in ThreadJob context
- Added UsingNativeDISM detail field to indicate native DISM cmdlet usage
- Updated Invoke-FFUPreflight to treat WimMount warnings as non-blocking

### NOTE: This version contained an incorrect assumption and was superseded by v1.0.3

---

## v1.0.1 (2025-12-11)
### New Feature: WIM Mount Capability Validation
- Added Test-FFUWimMount function for validating WIM mount infrastructure
- Addresses DISM error 0x800704DB "The specified service does not exist"
- Validates WIMMount service, WOF service, FltMgr service, and driver files
- Automatic remediation via service restart and driver re-registration
- Integrated into Invoke-FFUPreflight when ADK/WinPE operations are needed
- Comprehensive Pester test suite (28+ tests)

### Checks Performed:
- WIMMount service existence and status
- WOF (Windows Overlay Filter) service existence
- Filter Manager (FltMgr) service status
- wimmount.sys driver file (System32\drivers)
- wof.sys driver file (System32\drivers)

### Remediation Actions (when -AttemptRemediation used):
1. Restart FltMgr service if stopped
2. Restart WIMMount service if stopped
3. Re-register WIM mount driver via rundll32.exe wimmount.dll,WimMountDriver

---

## v1.0.0 (Initial Release)
- Comprehensive pre-flight validation system for FFU Builder
- Tiered validation architecture with fail-fast design
- Feature-aware validation (only checks requirements for enabled features)
- Actionable remediation guidance for every failure

### Validation Tiers

#### Tier 1: CRITICAL (Always Run, Blocking)
- Test-FFUAdministrator: Verify Administrator privileges
- Test-FFUPowerShellVersion: Require PowerShell 7.0+
- Test-FFUHyperV: Check Hyper-V feature installation

#### Tier 2: FEATURE-DEPENDENT (Conditional, Blocking)
- Test-FFUADK: ADK installation (Deployment Tools, WinPE add-on)
- Test-FFUDiskSpace: Calculate required space based on enabled features
- Test-FFUNetwork: Basic connectivity check (DNS + HTTPS)
- Test-FFUConfigurationFile: Config file validation (calls FFU.Core)
- Test-FFUWimMount: WIM mount infrastructure validation (v1.0.1)

#### Tier 3: RECOMMENDED (Warnings Only)
- Test-FFUAntivirusExclusions: Check Windows Defender exclusions

#### Tier 4: CLEANUP (Pre-Remediation)
- Invoke-FFUDISMCleanup: Clean stale mounts, temp dirs, orphaned VHDs

### Key Design Decisions
- NO TrustedInstaller running state check (it is a demand-start service)
- Feature-aware validation reduces unnecessary checks
- Delegates to existing functions (Test-ADKPrerequisites, Test-FFUConfiguration)
- Returns structured result object with aggregated errors, warnings, remediation steps

### Dependencies
- FFU.Core module for WriteLog, Test-FFUConfiguration
- FFU.ADK module for Test-ADKPrerequisites
- Administrator privileges for Hyper-V and DISM operations
'@
        }
    }
}
