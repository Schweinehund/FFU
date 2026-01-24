# Phase 23: BuildFFUVM.ps1 Reliability - Research

**Researched:** 2026-01-24
**Domain:** Build orchestration, error handling, cleanup, checkpoint/resume
**Confidence:** HIGH (based on existing codebase patterns and official PowerShell documentation)

## Summary

Research for BuildFFUVM.ps1 reliability focuses on five requirements: graceful phase failure handling (REL-BUILD-01), clean cancellation (REL-BUILD-02), checkpoint resume (REL-BUILD-03), error aggregation (REL-BUILD-04), and termination cleanup (REL-BUILD-05).

The existing codebase already has substantial infrastructure to build upon:
- **FFU.Core**: Full cleanup registration system with LIFO execution (`Register-CleanupAction`, `Invoke-FailureCleanup`)
- **FFU.Checkpoint**: Complete checkpoint/resume module with atomic writes, phase tracking, and artifact validation
- **FFU.Messaging**: Thread-safe cancellation via `Test-FFUCancellationRequested` and `Request-FFUCancellation`
- **BuildFFUVM.ps1**: Already has 8 cancellation checkpoints, trap handler, and `PowerShell.Exiting` event

The primary gaps are:
1. No error aggregation - only first error is captured
2. No graceful degradation - failures are all-or-nothing
3. Checkpoint integration incomplete - module exists but not wired to build phases
4. Termination cleanup has known limitations with process kills

**Primary recommendation:** Extend existing infrastructure rather than building new. Focus on wiring FFU.Checkpoint into phase boundaries and implementing an error collector pattern.

## Standard Stack

The established libraries/tools for this domain:

### Core (Already Implemented)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFU.Core | 1.0.18+ | Cleanup registration | LIFO cleanup, resource typing, trap integration |
| FFU.Checkpoint | 1.1.0 | Checkpoint/resume | Atomic writes, phase enum, artifact validation |
| FFU.Messaging | 1.0.0 | Cancellation | Thread-safe flag, UI communication |

### Supporting (PowerShell Native)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Register-EngineEvent | Native | Exit event handler | PowerShell session exits |
| trap {} | Native | Terminating error handler | Unhandled exceptions |
| Console.CancelKeyPress | .NET | Ctrl+C interception | User interrupt handling |

### No New Dependencies Required
The existing modules provide complete coverage. No external packages needed.

**Installation:** N/A - all infrastructure already present

## Architecture Patterns

### Recommended Project Structure (No Changes)
```
Modules/
├── FFU.Core/           # Cleanup registration (existing)
├── FFU.Checkpoint/     # Checkpoint persistence (existing)
├── FFU.Messaging/      # Cancellation signaling (existing)
└── BuildFFUVM.ps1      # Orchestrator (to be enhanced)
```

### Pattern 1: Error Aggregation Collector
**What:** Accumulate errors throughout build instead of failing on first
**When to use:** For phases that can partially succeed (drivers, updates)
**Example:**
```powershell
# Source: Established pattern in FFU.Updates, FFU.Drivers
$script:BuildErrorCollector = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-BuildError {
    param(
        [string]$Phase,
        [string]$Message,
        [ValidateSet('Critical', 'Warning', 'Info')]
        [string]$Severity = 'Warning',
        [System.Exception]$Exception
    )

    $script:BuildErrorCollector.Add([PSCustomObject]@{
        Timestamp = [DateTime]::Now
        Phase     = $Phase
        Message   = $Message
        Severity  = $Severity
        Exception = $Exception
    })

    if ($function:WriteLog) {
        WriteLog "[$Severity] $Phase: $Message"
    }
}

function Get-BuildErrorSummary {
    $errors = @($script:BuildErrorCollector)
    $critical = @($errors | Where-Object Severity -eq 'Critical')
    $warnings = @($errors | Where-Object Severity -eq 'Warning')

    return [PSCustomObject]@{
        TotalCount     = $errors.Count
        CriticalCount  = $critical.Count
        WarningCount   = $warnings.Count
        Errors         = $errors
        HasCritical    = $critical.Count -gt 0
    }
}
```

### Pattern 2: Phase Wrapper with Degradation
**What:** Wrap phases to enable continue-on-failure for non-critical phases
**When to use:** For optional phases (USB creation, deployment media)
**Example:**
```powershell
# Source: Pattern derived from existing Test-BuildCancellation
function Invoke-BuildPhase {
    param(
        [string]$PhaseName,
        [FFUBuildPhase]$Phase,
        [scriptblock]$Action,
        [bool]$Critical = $true,
        [hashtable]$MessagingContext
    )

    # Check cancellation first
    if (Test-BuildCancellation -MessagingContext $MessagingContext -PhaseName $PhaseName) {
        return [PSCustomObject]@{ Success = $false; Skipped = $true; Cancelled = $true }
    }

    try {
        WriteLog "=== Starting Phase: $PhaseName ==="
        $result = & $Action

        # Save checkpoint on success
        Save-FFUBuildCheckpoint -CompletedPhase $Phase -Configuration $config `
            -Artifacts $artifacts -Paths $paths -FFUDevelopmentPath $FFUDevPath

        WriteLog "=== Completed Phase: $PhaseName ==="
        return [PSCustomObject]@{ Success = $true; Result = $result }
    }
    catch {
        Add-BuildError -Phase $PhaseName -Message $_.Exception.Message `
            -Severity $(if ($Critical) { 'Critical' } else { 'Warning' }) `
            -Exception $_.Exception

        if ($Critical) {
            throw  # Re-throw for trap handler
        }

        WriteLog "WARNING: Phase $PhaseName failed but continuing (non-critical)"
        return [PSCustomObject]@{ Success = $false; Error = $_.Exception }
    }
}
```

### Pattern 3: Checkpoint Integration at Phase Boundaries
**What:** Wire existing FFU.Checkpoint to build phases
**When to use:** After each successful phase
**Example:**
```powershell
# Source: FFU.Checkpoint module (existing)
# At phase completion:
if (-not (Test-PhaseAlreadyComplete -PhaseName 'DriverDownload' -Checkpoint $checkpoint)) {
    # Execute driver download phase
    $driversResult = Download-Drivers ...

    # Update artifacts tracking
    $artifacts.driversDownloaded = $true
    $paths.DriversFolder = $driversResult.Path

    # Save checkpoint
    Save-FFUBuildCheckpoint -CompletedPhase ([FFUBuildPhase]::DriverDownload) `
        -Configuration $buildConfig -Artifacts $artifacts -Paths $paths `
        -FFUDevelopmentPath $FFUDevPath
}
```

### Pattern 4: Termination Handler Registration
**What:** Register Console.CancelKeyPress for Ctrl+C cleanup
**When to use:** At script start for guaranteed cleanup
**Example:**
```powershell
# Source: PowerShell GitHub issue #24902, Dan Sheehan's blog
# Note: This is Windows-specific, Unix behavior differs

Add-Type @'
using System;
public class CtrlCHandler {
    public static bool CtrlCPressed = false;
    public static void Handler(object sender, ConsoleCancelEventArgs args) {
        CtrlCPressed = true;
        args.Cancel = true;  // Don't terminate immediately
        // Set environment variable for script detection
        Environment.SetEnvironmentVariable("FFU_CTRL_C_PRESSED", "1");
    }
}
'@

# Register the handler
[Console]::add_CancelKeyPress([CtrlCHandler]::Handler)

# Check in long-running operations
function Test-CtrlCPressed {
    return [CtrlCHandler]::CtrlCPressed -or $env:FFU_CTRL_C_PRESSED -eq "1"
}
```

### Anti-Patterns to Avoid
- **Anti-pattern: Relying solely on PowerShell.Exiting** - Does not fire on process kill or Ctrl+C in many scenarios. Use as backup, not primary mechanism.
- **Anti-pattern: Using $Error automatic variable for aggregation** - Gets cleared and contains unrelated errors. Use dedicated collector.
- **Anti-pattern: Stopping on first driver/update failure** - Wastes work already done. Accumulate errors and continue.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cleanup registry | Custom list management | FFU.Core Register-CleanupAction | Already handles LIFO, resource types, logging |
| Checkpoint persistence | Custom file writes | FFU.Checkpoint Save-FFUBuildCheckpoint | Atomic writes, validation, PS5.1/7 compat |
| Cancellation detection | Custom flag checking | FFU.Messaging Test-FFUCancellationRequested | Thread-safe, UI-integrated |
| Phase tracking enum | Custom string comparisons | FFUBuildPhase enum in FFU.Checkpoint | Type-safe, ordered |
| Exit event handling | Custom event system | Register-EngineEvent PowerShell.Exiting | Native PowerShell support |

**Key insight:** The project already has 90% of the infrastructure. The work is integration, not creation.

## Common Pitfalls

### Pitfall 1: PowerShell.Exiting Event Unreliability
**What goes wrong:** Cleanup code doesn't run on window close, process kill, or Ctrl+C
**Why it happens:** PowerShell.Exiting only fires on explicit `exit` command or normal runspace termination
**How to avoid:** Use trap handler + PowerShell.Exiting + Console.CancelKeyPress as defense-in-depth
**Warning signs:** Orphaned VMs or mounted images after interrupted builds

### Pitfall 2: Ctrl+C Handler Thread Context
**What goes wrong:** Cleanup code fails because it runs on wrong thread
**Why it happens:** Console.CancelKeyPress fires on thread-pool thread without PowerShell runspace
**How to avoid:** Set flag only in C# handler, check flag from PowerShell code with retry loop
**Warning signs:** "Runspace not available" errors during cleanup

### Pitfall 3: Error Aggregation Memory Growth
**What goes wrong:** Error collector grows unbounded in long-running builds
**Why it happens:** No cleanup of old errors
**How to avoid:** Limit error collector to reasonable size (e.g., 100 entries), trim oldest when full
**Warning signs:** Memory usage increases over repeated builds

### Pitfall 4: Checkpoint File Corruption
**What goes wrong:** Checkpoint file is half-written on crash
**Why it happens:** Direct file write interrupted mid-operation
**How to avoid:** FFU.Checkpoint already uses atomic write pattern (temp file + rename)
**Warning signs:** JSON parse errors on resume attempt

### Pitfall 5: Graceful Degradation Masking Critical Failures
**What goes wrong:** Build "succeeds" but is missing critical components
**Why it happens:** All failures treated as non-critical
**How to avoid:** Maintain Critical vs Warning severity distinction, fail build on any Critical error
**Warning signs:** FFU boots but has no drivers or apps

## Code Examples

Verified patterns from official sources and existing codebase:

### Error Aggregation with Summary (REL-BUILD-04)
```powershell
# Source: FFU.Preflight validation result pattern
# Build error collection and summary display

function Write-BuildSummary {
    [CmdletBinding()]
    param([PSCustomObject]$Summary)

    $log = {
        param([string]$Message)
        if ($function:WriteLog) { WriteLog $Message }
        else { Write-Verbose $Message }
    }

    & $log "=========================================="
    & $log "BUILD SUMMARY"
    & $log "=========================================="
    & $log "Total Issues: $($Summary.TotalCount)"
    & $log "  Critical: $($Summary.CriticalCount)"
    & $log "  Warnings: $($Summary.WarningCount)"
    & $log "=========================================="

    if ($Summary.Errors.Count -gt 0) {
        & $log "ISSUES ENCOUNTERED:"
        foreach ($err in $Summary.Errors) {
            $prefix = switch ($err.Severity) {
                'Critical' { '[CRITICAL]' }
                'Warning'  { '[WARNING]' }
                default    { '[INFO]' }
            }
            & $log "  $prefix $($err.Phase): $($err.Message)"
        }
        & $log "=========================================="
    }
}
```

### Checkpoint Resume Integration (REL-BUILD-03)
```powershell
# Source: FFU.Checkpoint module + BuildFFUVM.ps1 existing checkpoint loading
# Wire checkpoint to phase execution

# At build start:
$checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $FFUDevPath

if ($checkpoint -and (Test-FFUBuildCheckpoint -Checkpoint $checkpoint)) {
    if (Test-CheckpointArtifacts -Checkpoint $checkpoint) {
        WriteLog "Valid checkpoint found. Resuming from: $($checkpoint.lastCompletedPhase)"
        $artifacts = $checkpoint.artifacts
        $paths = $checkpoint.paths
        # Build will skip completed phases via Test-PhaseAlreadyComplete
    }
    else {
        WriteLog "Checkpoint invalid (artifacts missing). Starting fresh build."
        Remove-FFUBuildCheckpoint -FFUDevelopmentPath $FFUDevPath
    }
}

# At phase execution:
if (-not (Test-PhaseAlreadyComplete -PhaseName 'VHDXCreation' -Checkpoint $checkpoint)) {
    # Execute phase...
    # On success, save checkpoint
}
```

### Cleanup On Any Termination (REL-BUILD-05)
```powershell
# Source: BuildFFUVM.ps1 existing trap + Register-EngineEvent
# Enhanced with Ctrl+C handling

# 1. Trap handler (catches terminating errors)
trap {
    if ($ExecutionContext.InvokeCommand.GetCommand('Get-CleanupRegistry', 'Function')) {
        $registry = Get-CleanupRegistry
        if ($registry -and $registry.Count -gt 0) {
            WriteLog "TRAP: Invoking cleanup for $($registry.Count) resources"
            Invoke-FailureCleanup -Reason "Terminating error: $($_.Exception.Message)"
        }
    }
    break
}

# 2. Exit event (catches normal exits)
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    if ($ExecutionContext.InvokeCommand.GetCommand('Get-CleanupRegistry', 'Function')) {
        $registry = Get-CleanupRegistry
        if ($registry -and $registry.Count -gt 0) {
            Write-Host "PowerShell exiting - cleanup $($registry.Count) resources"
            Invoke-FailureCleanup -Reason "PowerShell session exiting"
        }
    }
}

# 3. At build end (normal completion)
Clear-CleanupRegistry
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Stop on first error | Error aggregation with continue | Current best practice | See all failures in one run |
| No checkpoint | JSON checkpoint at phase boundaries | FFU.Checkpoint v1.0.0 | Resume interrupted builds |
| Single cleanup call | Registered cleanup actions | FFU.Core v1.0.0 | Automatic LIFO cleanup |
| Manual cancellation checks | Test-BuildCancellation helper | FFU.Core v1.0.16 | Consistent cancellation pattern |

**Deprecated/outdated:**
- PowerShell Workflows with Checkpoint-Workflow: Not available in PS7+, FFU.Checkpoint provides equivalent functionality
- $Error automatic variable for aggregation: Unreliable, use dedicated collector

## Open Questions

Things that couldn't be fully resolved:

1. **Ctrl+C reliability on Unix-like platforms**
   - What we know: Console.CancelKeyPress works on Windows but has issues on Unix (PowerShell #24902)
   - What's unclear: Whether BuildFFUVM.ps1 needs to support non-Windows hosts
   - Recommendation: Implement Windows-specific Ctrl+C handler, rely on trap/exit events for cross-platform

2. **Process kill cleanup guarantee**
   - What we know: No mechanism can guarantee cleanup when process is killed externally (taskkill /f)
   - What's unclear: Whether we need to handle this scenario or document it as a known limitation
   - Recommendation: Document limitation, provide manual cleanup script for orphaned resources

3. **Checkpoint granularity within phases**
   - What we know: Current FFU.Checkpoint saves at phase boundaries
   - What's unclear: Whether we need mid-phase checkpoints (e.g., during 20-file update download)
   - Recommendation: Start with phase-level, add sub-phase if testing reveals need

## Sources

### Primary (HIGH confidence)
- FFU.Core v1.0.18 - Cleanup registration system (Register-CleanupAction, Invoke-FailureCleanup)
- FFU.Checkpoint v1.1.0 - Checkpoint/resume functionality (Save-FFUBuildCheckpoint, Test-PhaseAlreadyComplete)
- FFU.Messaging v1.0.0 - Cancellation support (Test-FFUCancellationRequested)
- BuildFFUVM.ps1 - Existing trap handler and Register-EngineEvent patterns

### Secondary (MEDIUM confidence)
- [Register-EngineEvent Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/register-engineevent) - PowerShell.Exiting behavior
- [PowerShell Error Handling Guide NinjaOne](https://www.ninjaone.com/blog/powershell-error-handling-guide/) - Error handling patterns
- [Get-Error Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-error) - Error retrieval

### Tertiary (LOW confidence - needs validation)
- [PowerShell GitHub #8000](https://github.com/PowerShell/PowerShell/issues/8000) - PowerShell.Exiting limitations
- [PowerShell GitHub #24902](https://github.com/PowerShell/PowerShell/issues/24902) - Console.CancelKeyPress Unix issues
- [Dan Sheehan Blog](https://blog.sheehans.org/2018/10/27/powershell-taking-control-over-ctrl-c/) - Ctrl+C interception patterns
- [PowerShell Forums](https://forums.powershell.org/t/clean-up-before-exiting-script/20605) - Cleanup best practices

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Using existing modules from this project
- Architecture: HIGH - Patterns derived from existing codebase
- Pitfalls: MEDIUM - Based on official GitHub issues and community experience

**Research date:** 2026-01-24
**Valid until:** 60 days (stable patterns, no rapid changes expected)
