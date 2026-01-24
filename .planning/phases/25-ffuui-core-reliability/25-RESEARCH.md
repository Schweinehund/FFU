# Phase 25: FFUUI.Core Reliability - Research

**Researched:** 2026-01-24
**Domain:** WPF UI Error Handling, Background Job Communication, State Management
**Confidence:** HIGH

## Summary

This research investigates the current state of FFUUI.Core error handling, background job failure surfacing, UI state consistency, and configuration validation. The primary focus is on implementing REL-UI-01 through REL-UI-04: meaningful error displays, actionable job failure information, consistent UI state after errors, and load-time configuration validation.

The existing codebase has solid foundations:
- FFU.Messaging module provides structured message types including Error, Warning, and Critical levels
- FFU.Preflight module demonstrates severity-based validation with remediation guidance
- Test-FFUConfiguration in FFU.Core performs comprehensive config schema validation

Key gaps to address:
1. Generic MessageBox error displays lack actionable guidance (what failed, why, how to fix)
2. Background job failures surface with limited context ("Build failed" vs specific failure details)
3. UI state recovery after errors is ad-hoc, not systematic
4. Configuration validation runs at build time, not load time

**Primary recommendation:** Implement a centralized error display service (Show-FFUError) with structured error types (severity, action, remediation), integrate with FFU.Messaging for job errors, create UI state recovery helper, and add load-time config validation.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| System.Windows.MessageBox | WPF Native | Error dialogs | Already in use, WPF standard |
| FFU.Messaging | 1.0.0 | Thread-safe UI/job communication | Existing module with message levels |
| FFU.Preflight | 1.0.0 | Severity-based validation | Has remediation block pattern |
| FFU.Core | 1.0.10+ | Test-FFUConfiguration | JSON schema validation exists |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DispatcherTimer | WPF Native | UI thread updates | Already used for job polling |
| ConcurrentQueue | .NET 4.5+ | Thread-safe messaging | Already in FFU.Messaging |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| MessageBox | Custom WPF Dialog | More flexible but more complex; MessageBox sufficient |
| Manual state tracking | State machine | Overkill for this use case |

**Installation:**
No additional packages required. All capabilities exist in WPF and existing modules.

## Architecture Patterns

### Current Error Handling Architecture

```
BuildFFUVM_UI.ps1 (UI Host)
├── Event Handlers
│   ├── btnRun.Add_Click - Direct MessageBox calls
│   └── Exception catch blocks - Generic error display
├── DispatcherTimer (50ms polling)
│   └── Job state check - Basic error extraction
└── FFU.Messaging (Background Job)
    ├── Write-FFUError - Structured error messages
    └── FFUMessageLevel enum - Info/Warning/Error/Critical
```

### Recommended Project Structure
```
FFUUI.Core/
├── FFUUI.Core.psm1              # Main module (existing)
├── FFUUI.Core.ErrorDisplay.psm1 # NEW: Centralized error handling
│   ├── Show-FFUError            # Main error display function
│   ├── Show-FFUValidationErrors # Validation-specific display
│   └── Get-ErrorFromJobResult   # Job result error extraction
├── FFUUI.Core.StateRecovery.psm1 # NEW: UI state management
│   ├── Save-UIState             # Capture current state
│   ├── Restore-UIState          # Restore after error
│   └── Reset-UIToIdle           # Reset progress/buttons
└── FFUUI.Core.Config.psm1       # ENHANCE: Add load-time validation
    └── Import-FFUConfiguration   # Add validation call
```

### Pattern 1: Structured Error Display
**What:** Display errors with severity, description, remediation, and optional details
**When to use:** Any error that surfaces to the user
**Example:**
```powershell
# Current pattern (scattered, generic)
[System.Windows.MessageBox]::Show($errorMsg, "Build Error", "OK", "Error")

# Recommended pattern (structured, actionable)
Show-FFUError -Severity Critical `
    -Title "Build Failed: DISM Error 0x80070005" `
    -Description "Access denied while mounting WIM file." `
    -Remediation "Run as Administrator or check antivirus exclusions." `
    -LogPath $mainLogPath `
    -Details $errorRecord
```

### Pattern 2: Job Error Extraction
**What:** Extract meaningful error context from background job results
**When to use:** When job enters Failed/Stopped state
**Example:**
```powershell
# Current pattern (limited context)
$reason = $currentJob.JobStateInfo.Reason.Message
if ([string]::IsNullOrWhiteSpace($reason)) {
    $reason = "An unknown error occurred."
}

# Recommended pattern (rich context)
$errorInfo = Get-FFUJobError -Job $currentJob -MessagingContext $msgContext
# Returns: @{
#   ErrorType = 'DISMError'
#   Message = 'Failed to apply updates'
#   Source = 'FFU.Updates'
#   Details = @{ ExitCode = 1234; Command = 'DISM /Add-Package' }
#   Remediation = 'Check available disk space'
# }
```

### Pattern 3: UI State Recovery
**What:** Systematic reset of UI controls after errors
**When to use:** After any error that interrupted normal flow
**Example:**
```powershell
# Current pattern (ad-hoc, repeated in multiple places)
$btnRun.IsEnabled = $true
$btnRun.Content = "Build FFU"
$script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
$script:uiState.Controls.pbOverallProgress.Value = 0
$script:uiState.Flags.isBuilding = $false

# Recommended pattern (centralized)
Reset-FFUUIToIdle -State $script:uiState -StatusMessage "Build failed. Ready to retry."
# Handles all control resets in one call
```

### Pattern 4: Load-Time Config Validation
**What:** Validate configuration when loaded, not when build starts
**When to use:** When loading config from file or restoring previous state
**Example:**
```powershell
# Current pattern (validation at build time)
# User loads config -> Clicks Build -> Validation fails -> Wasted time

# Recommended pattern (load-time validation)
function Import-FFUConfiguration {
    param([string]$ConfigPath, [PSCustomObject]$State)

    # Parse JSON
    $config = Get-Content $ConfigPath | ConvertFrom-Json

    # Validate immediately
    $validation = Test-FFUConfiguration -ConfigObject $config
    if (-not $validation.IsValid) {
        Show-FFUValidationErrors -Errors $validation.Errors `
            -Title "Configuration has errors" `
            -ConfigPath $ConfigPath
        return $null  # Prevent applying invalid config
    }

    # Apply to UI
    Set-UIFromConfig -Config $config -State $State
    return $config
}
```

### Anti-Patterns to Avoid
- **Swallowing errors silently:** Always surface errors to user, even if just logging to Monitor tab
- **Generic "Error occurred" messages:** Always include what failed, why, and what to do
- **Leaving UI in inconsistent state:** Always reset progress bars, re-enable buttons after errors
- **Validation after user commits:** Validate as early as possible (on load, not on build)

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Message severity levels | Custom enum | FFU.Messaging.FFUMessageLevel | Already defined: Debug/Info/Progress/Success/Warning/Error/Critical |
| Remediation block formatting | String concatenation | New-FFURemediationBlock | FFU.Preflight has structured format with ISSUE/IMPACT/FIX/VERIFY |
| Config validation | Manual property checks | Test-FFUConfiguration | FFU.Core has full JSON schema validation |
| Thread-safe error queuing | Lock/Monitor | ConcurrentQueue in FFU.Messaging | Already thread-safe, lock-free |
| UI thread dispatch | Dispatcher.Invoke | DispatcherTimer pattern | Already used, avoids cross-thread issues |

**Key insight:** The infrastructure for reliable error handling already exists in FFU.Messaging and FFU.Preflight. The gap is integrating these patterns into the UI layer systematically.

## Common Pitfalls

### Pitfall 1: MessageBox Blocking During Cleanup
**What goes wrong:** Showing MessageBox while cleanup is running blocks UI thread
**Why it happens:** Cleanup runs via timer, MessageBox is modal
**How to avoid:** Queue error display, show after cleanup completes
**Warning signs:** UI becomes unresponsive during error display

### Pitfall 2: Job Error Stream Contains Non-Errors
**What goes wrong:** Receive-Job -ErrorVariable captures warnings, verbose, not just errors
**Why it happens:** PowerShell streams all non-terminating records to error variable
**How to avoid:** Check for success marker FIRST (FFUBuildSuccess=$true pattern already exists)
**Warning signs:** Successful builds incorrectly marked as failed

### Pitfall 3: Progress Bar Stays Visible After Error
**What goes wrong:** Progress bar shows indefinitely after job failure
**Why it happens:** Error handling path doesn't reset all UI elements
**How to avoid:** Use centralized Reset-FFUUIToIdle function
**Warning signs:** Progress bar visible when no build is running

### Pitfall 4: Lost Error Context from ThreadJob
**What goes wrong:** Error details lost when job runs in separate thread
**Why it happens:** Exception serialization between threads loses InnerException
**How to avoid:** Use FFU.Messaging to send structured errors before throwing
**Warning signs:** "An error occurred" with no details

### Pitfall 5: Config Validation Too Late
**What goes wrong:** User configures 20 options, clicks Build, first option is invalid
**Why it happens:** Validation only runs in BuildFFUVM.ps1 parameter validation
**How to avoid:** Validate on config load, show inline errors in UI
**Warning signs:** User wastes time configuring before discovering invalid settings

## Code Examples

Verified patterns from existing codebase:

### FFU.Messaging Error Writing (existing)
```powershell
# Source: FFU.Messaging.psm1 lines 514-531
function Write-FFUError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Source = '',

        [Parameter()]
        [hashtable]$Data = @{}
    )

    Write-FFUMessage -Context $Context -Message $Message -Level Error -Source $Source -Data $Data
}
```

### FFU.Preflight Remediation Block (existing)
```powershell
# Source: FFU.Preflight.psm1 lines 103-200
function New-FFURemediationBlock {
    param(
        [Parameter(Mandatory)]
        [string]$Issue,
        [string]$Impact = 'Build cannot proceed',
        [string[]]$PowerShellCommands = @(),
        [string[]]$ManualSteps = @(),
        [string]$VerifyCommand = ''
    )
    # Creates structured block with:
    # === ISSUE ===
    # === IMPACT ===
    # === FIX ===
    # === VERIFY ===
}
```

### Current Job Error Handling (existing - to be enhanced)
```powershell
# Source: BuildFFUVM_UI.ps1 lines 767-809
if ($hasErrors) {
    $reason = $null

    # Try to get error message from various sources
    if ($null -ne $jobErrors -and $jobErrors.Count -gt 0) {
        $reason = ($jobErrors | Select-Object -Last 1).ToString()
    }

    if ([string]::IsNullOrWhiteSpace($reason) -and $currentJob.JobStateInfo.Reason) {
        $reason = $currentJob.JobStateInfo.Reason.Message
    }

    # ... more fallback attempts ...

    $errorMsg = "The build process failed.`n`n"
    if (Test-Path -LiteralPath $mainLogPath) {
        $errorMsg += "Please check the log file for details:`n$mainLogPath`n`n"
    }
    $errorMsg += "Error: $reason"

    [System.Windows.MessageBox]::Show($errorMsg, "Build Error", "OK", "Error") | Out-Null
}
```

### Current Config Validation (existing - to be integrated earlier)
```powershell
# Source: FFU.Core.psm1 lines 2698-2750 (abbreviated)
function Test-FFUConfiguration {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [hashtable]$ConfigObject,

        [switch]$ThrowOnError
    )

    $result = [PSCustomObject]@{
        IsValid  = $false
        Errors   = [System.Collections.Generic.List[string]]::new()
        Warnings = [System.Collections.Generic.List[string]]::new()
        Config   = $null
    }
    # ... validation logic ...
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| File-based log polling | Queue-based messaging | v1.3.0+ | 20x faster UI updates |
| Generic MessageBox | Still generic | Current | Needs improvement |
| No config validation | Test-FFUConfiguration | v1.0.10 | Exists but not at load time |

**Deprecated/outdated:**
- File polling for log updates: Replaced by FFU.Messaging queue, though file logging kept for persistence

## Requirements Mapping

### REL-UI-01: UI displays meaningful error states, not generic failures
**Current state:** Generic MessageBox with "Build Error" title, raw error message
**Gap:** No structured error format, no remediation guidance
**Recommendation:**
- Create `Show-FFUError` function with severity, title, description, remediation, details
- Use existing `New-FFURemediationBlock` pattern from FFU.Preflight
- Include "Open Log File" button for detailed investigation

### REL-UI-02: Background job failures surface with actionable information
**Current state:** Attempts to extract error from multiple sources, often gets "unknown error"
**Gap:** Error context lost in thread boundary, no structured error from job
**Recommendation:**
- Use FFU.Messaging to send structured errors BEFORE throwing
- Create `Get-FFUJobError` to extract rich error from job + messaging context
- Include error source, type, and specific remediation

### REL-UI-03: UI state remains consistent after errors
**Current state:** Ad-hoc reset of controls in multiple catch blocks
**Gap:** Easy to miss controls, inconsistent reset behavior
**Recommendation:**
- Create `Reset-FFUUIToIdle` function that resets ALL relevant controls
- Call from single location at job completion (success or failure)
- Track all controls that need reset in state object

### REL-UI-04: Configuration validation prevents invalid builds from starting
**Current state:** Validation runs in BuildFFUVM.ps1, after user clicks Build
**Gap:** User wastes time configuring before learning config is invalid
**Recommendation:**
- Call Test-FFUConfiguration when loading config file
- Call Test-FFUConfiguration when switching tabs (validate visible tab)
- Show validation errors inline where possible (e.g., text box border color)
- Block build button if critical validation errors exist

## Open Questions

Things that couldn't be fully resolved:

1. **Inline validation feedback**
   - What we know: WPF supports validation error styles via IDataErrorInfo
   - What's unclear: How much inline validation vs dialog is appropriate for this UI
   - Recommendation: Start with dialog-based validation errors, add inline for obvious fields (paths, numbers)

2. **Error history/persistence**
   - What we know: Log file captures all errors
   - What's unclear: Should UI show error history beyond current session?
   - Recommendation: Defer to log file for history, focus on current-session error display

3. **Localization**
   - What we know: All error messages are currently English strings
   - What's unclear: Is localization a future requirement?
   - Recommendation: Use string resources pattern but defer actual localization

## Sources

### Primary (HIGH confidence)
- FFU.Messaging.psm1 - Message types, Write-FFUError, FFUMessageLevel enum
- FFU.Preflight.psm1 - New-FFURemediationBlock, severity-based validation
- FFU.Core.psm1 - Test-FFUConfiguration, validation result structure
- BuildFFUVM_UI.ps1 - Current job error handling, UI state management

### Secondary (MEDIUM confidence)
- WPF MessageBox documentation - Standard dialog patterns
- PowerShell job error handling - Error stream behavior

### Tertiary (LOW confidence)
- N/A - All patterns verified against existing codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components exist in codebase
- Architecture: HIGH - Patterns derived from existing code analysis
- Pitfalls: HIGH - Observed in current implementation

**Research date:** 2026-01-24
**Valid until:** Indefinite - architecture-level research, not version-specific

## Implementation Priority

Based on user impact and implementation complexity:

1. **REL-UI-03: UI State Consistency** (Quick Win)
   - Create Reset-FFUUIToIdle function
   - Single point of control reset
   - Low risk, immediate improvement

2. **REL-UI-01: Meaningful Error Display** (High Impact)
   - Create Show-FFUError function
   - Integrate with existing remediation block pattern
   - User-facing improvement

3. **REL-UI-02: Job Failure Context** (Medium Complexity)
   - Enhance error extraction from job results
   - Integrate with FFU.Messaging error messages
   - Requires coordination with job code

4. **REL-UI-04: Load-Time Validation** (Preventive)
   - Add validation call to config loading
   - Show validation errors before build starts
   - Prevents wasted user time
