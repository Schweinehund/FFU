# Phase 33: OEM Driver Logging - Research

**Researched:** 2026-01-27
**Domain:** PowerShell logging patterns, driver operations auditing, test-driven logging migration
**Confidence:** HIGH

## Summary

This research investigated how to migrate OEM driver operations from console-only output (Write-Host, Write-Warning, Write-Verbose) to proper file logging using the existing WriteLog function in FFU.Common.Core. The audit scope covers the FFU.Drivers module (2,293 lines), BuildFFUVM.ps1 driver sections, and any driver-related code paths.

**Key findings:**
- FFU.Drivers.psm1 contains 12 console output calls requiring migration (8 Write-Host, 4 Write-Verbose)
- WriteLog is already heavily used (228 calls) but console output bypasses file logging
- Phase 31 (HP exit code 1168) and Phase 32 (Dell CatalogPC.xml) remediation messages need structured prefix retrofitting
- Dual output pattern (WriteLog + Write-Host) preserves console visibility for users running builds interactively
- Mock-based Pester testing is the established pattern in this codebase

**Primary recommendation:** Systematic audit and migration using structured message prefixes `[OEM][Model][Operation]`, dual WriteLog+Write-Host calls, and mock-based test coverage for every migrated logging call.

## Standard Stack

The established tools for this logging migration:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| WriteLog | FFU.Common.Core v0.0.12 | File + queue logging | Project-standard logging function, thread-safe, dual output (file + UI queue) |
| Pester | 5.x | Testing framework | Project requirement (see Tests/Unit/*.Tests.ps1), mock-based testing established |
| [DateTime]::Now | .NET BCL | Timestamp generation | ThreadJob-compatible (v0.0.9 fix), avoids Get-Date cmdlet availability issues |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Write-Host | Built-in | Console visibility | Dual output pattern - keep alongside WriteLog for interactive builds |
| Write-Verbose | Built-in | Verbose diagnostics | Keep for -Verbose switch users, add WriteLog for file logging |
| [Console]::WriteLine() | .NET BCL | ThreadJob-safe console | Already used in v0.0.10 fix - DO NOT migrate (excluded from audit) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| WriteLog (custom) | Write-Information | Would lose dual output (file + queue), no UI integration, breaking change |
| Mock WriteLog | Integration tests | Mocking is faster, isolated, matches existing test patterns (see FFU.Drivers.Tests.ps1) |
| Measure-Command | [Diagnostics.Stopwatch] | Both work, Measure-Command is more PowerShell-idiomatic for simple timing |

**Installation:**
N/A - All components are already in the codebase.

## Architecture Patterns

### Recommended Audit Structure
```
Audit Inventory:
├── FFU.Drivers.psm1           # 12 console calls (8 Write-Host, 4 Write-Verbose)
│   ├── Lines 710-711          # HP model not found (Write-Host)
│   ├── Lines 718, 732         # HP model selection menu (Write-Host)
│   ├── Lines 1028, 1047, 1055 # Lenovo failures (Write-Host)
│   ├── Line 1103              # HP cab URL failure (Write-Host)
│   └── Lines 101, 114, 127, 141 # Invoke-DriverDownloadWithRetry (Write-Verbose)
├── BuildFFUVM.ps1             # Driver orchestration (lines 2564-2596)
│   └── Already uses WriteLog  # No migration needed, may need structured prefix retrofit
└── Phase 31/32 code           # Recently added remediation messages
    ├── HP exit code 1168      # Line 234-238 (needs structured prefix)
    └── Dell catalog failures  # Lines 1716-1745 (needs structured prefix)
```

### Pattern 1: Dual Output Migration
**What:** Replace console-only calls with WriteLog + Write-Host
**When to use:** Every Write-Host call that provides user-visible feedback
**Example:**
```powershell
# BEFORE (console-only, no file logging)
Write-Host "The model '$Model' was not found in the list of available models."

# AFTER (dual output - file + console)
$message = "[HP][$Model][Selection] Model not found in available models"
WriteLog $message
Write-Host "The model '$Model' was not found in the list of available models."
```
**Why dual output:** Users running builds interactively still see console feedback, but logs are now captured for troubleshooting.

### Pattern 2: Structured Prefix Format
**What:** All OEM driver log messages use `[OEM][Model][Operation]` prefix
**When to use:** Every driver-related log message (new and retrofitted)
**Example:**
```powershell
# Download operation
WriteLog "[Dell][Latitude 7490][Download] Downloading CatalogPC.cab from $url"
WriteLog "[Dell][Latitude 7490][Download] Download complete (2.3 MB in 4.5s)"

# Extraction operation
WriteLog "[HP][EliteBook 840 G8][Extract] Extracting softpaq sp123456.exe"
WriteLog "[HP][EliteBook 840 G8][Extract] Extraction complete (142 files)"

# Injection operation (if applicable)
WriteLog "[Lenovo][ThinkPad X1 Carbon][Inject] Adding drivers to WinPE image"
WriteLog "[Lenovo][ThinkPad X1 Carbon][Inject] Injection complete"
```
**Why structured:** Enables grep/filtering (`grep "\[Dell\]" FFUDevelopment.log`), consistent troubleshooting, easy pattern recognition.

### Pattern 3: WriteLog + Write-Verbose Preservation
**What:** Add WriteLog but keep Write-Verbose for users running with -Verbose
**When to use:** Existing Write-Verbose calls in verbose diagnostic code
**Example:**
```powershell
# BEFORE (verbose-only, no file logging)
Write-Verbose $successMsg

# AFTER (file logging + verbose switch support)
WriteLog $successMsg
Write-Verbose $successMsg
```
**Why preserve:** Users running builds with `-Verbose` expect verbose output, file logging doesn't replace console diagnostics.

### Pattern 4: Timing Implementation
**What:** Log elapsed duration for download, extraction, and injection operations
**When to use:** Any long-running driver operation (download, extraction)
**Example:**
```powershell
# Using Measure-Command (PowerShell-idiomatic for simple timing)
$downloadResult = Measure-Command {
    Start-BitsTransferWithRetry -Source $url -Destination $dest
}
WriteLog "[Dell][Latitude 7490][Download] Download complete in $($downloadResult.TotalSeconds.ToString('F1'))s"

# Alternative: [Diagnostics.Stopwatch] for more control
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
# ... operation ...
$stopwatch.Stop()
WriteLog "[HP][$Model][Extract] Extraction complete in $($stopwatch.Elapsed.TotalSeconds.ToString('F1'))s"
```
**Why timing:** Helps diagnose slow networks, large driver sets, performance regressions.

### Pattern 5: Remediation Message Format
**What:** Non-critical failures log actionable remediation steps
**When to use:** Error paths that allow build continuation (graceful degradation)
**Example:**
```powershell
# Source: Phase 32 Dell catalog failure (lines 1716-1718)
catch {
    WriteLog "WARNING: [Dell][$Model][Download] Catalog download failed: $($_.Exception.Message)"
    WriteLog "WARNING: [Dell][$Model][Download] Remediation: Check network connectivity to downloads.dell.com. Verify proxy settings if behind a corporate firewall. See FFUDevelopment.log for full error details. The build will continue without Dell drivers."
    Write-Host "WARNING: Dell catalog download failed. Build will continue without Dell drivers."
    return
}
```
**Key elements:**
- Structured prefix `[OEM][Model][Operation]`
- Full exception message logged
- Specific numbered/bulleted steps (here: "Check X. Verify Y.")
- Copy-paste ready commands (if applicable)
- Build impact stated: "The build will continue without Dell drivers."
- Points to log file: "See FFUDevelopment.log for full error details."

### Pattern 6: Mock-Based Pester Testing
**What:** Mock WriteLog and assert it was called with expected parameters
**When to use:** Every logging migration (fast, isolated, matches existing patterns)
**Example:**
```powershell
# Source: Established pattern from Tests/Unit/FFU.Drivers.Tests.ps1 structure
Describe 'Get-HPDrivers Logging' -Tag 'Unit', 'FFU.Drivers', 'Logging' {
    BeforeAll {
        Mock WriteLog {}
        Mock Write-Host {}
        Mock Start-BitsTransferWithRetry { return $true }
        # ... other mocks ...
    }

    Context 'Model Not Found Scenario' {
        It 'Should log model not found message' {
            # ... setup ...
            Get-HPDrivers -Make 'HP' -Model 'InvalidModel' -WindowsArch 'x64' -WindowsRelease 10 -WindowsVersion '22H2' -DriversFolder $testPath -FFUDevelopmentPath $testPath

            # Assert WriteLog was called with structured prefix
            Should -Invoke WriteLog -ParameterFilter { $LogText -match '\[HP\]\[InvalidModel\]\[Selection\]' }
        }

        It 'Should preserve Write-Host for console visibility' {
            # ... same test ...
            Should -Invoke Write-Host -ParameterFilter { $_ -match 'not found in the list' }
        }
    }
}
```
**Why mocking:** Fast execution, no file I/O, isolated from environment, matches existing test patterns.

### Anti-Patterns to Avoid
- **Migrating [Console]::WriteLine() calls:** These are ThreadJob-safe (v0.0.10 fix), NOT in scope for this phase
- **Removing Write-Host entirely:** Users expect console feedback during interactive builds (dual output required)
- **Generic catch blocks without exception logging:** Always log `$($_.Exception.Message)` in remediation messages
- **Forgetting to retrofit Phase 31/32 messages:** Recent code also needs structured prefix format
- **Missing "Build will continue" statements:** Every non-critical failure must state build impact

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Logging to file + UI queue | Custom logging | `WriteLog` (FFU.Common.Core) | Already thread-safe, mutex-protected, dual output, UI integration |
| Timing operations | Custom timer | `Measure-Command` or `[Diagnostics.Stopwatch]` | Built-in, accurate, no dependencies |
| Test-time logging verification | Integration tests | Mock WriteLog (Pester) | Faster, isolated, matches existing patterns (FFU.Drivers.Tests.ps1) |
| Console output in ThreadJob | Write-Host | `[Console]::WriteLine()` | ThreadJob-safe (v0.0.10 fix), but NOT applicable here (dual output keeps Write-Host) |

**Key insight:** WriteLog is the project-standard logging function with UI integration, mutex protection, and queue support. Don't create a new logging abstraction.

## Common Pitfalls

### Pitfall 1: Missing Dual Output on User-Facing Messages
**What goes wrong:** Migrating Write-Host to WriteLog only, users lose console feedback during interactive builds
**Why it happens:** Assumption that WriteLog replaces console output (it doesn't - it's dual output)
**How to avoid:** Every Write-Host migration must keep Write-Host AND add WriteLog
**Warning signs:** User complaints about "silent builds", no console output during driver downloads

### Pitfall 2: Forgetting to Retrofit Recent Code
**What goes wrong:** Phase 31/32 remediation messages lack structured prefix format, inconsistent grep/filtering
**Why it happens:** Phases 31/32 were implemented before structured logging standards were defined
**How to avoid:** Audit ALL driver code, including recently added error paths (lines 234-238, 1716-1745)
**Warning signs:** Log messages like "WARNING: Dell catalog download failed" instead of "WARNING: [Dell][$Model][Download] Catalog download failed"

### Pitfall 3: Not Logging Exception Details
**What goes wrong:** Remediation messages say "failed" without logging `$_.Exception.Message`, no root cause
**Why it happens:** Forgetting to include exception in log statement
**How to avoid:** Every catch block logs `$($_.Exception.Message)` before remediation steps
**Warning signs:** Log shows "Dell catalog download failed" but not "Dell catalog download failed: The remote server returned an error: (404) Not Found."

### Pitfall 4: Testing Without Mocks
**What goes wrong:** Slow integration tests, file I/O in unit tests, brittle tests
**Why it happens:** Not following existing Pester patterns (FFU.Drivers.Tests.ps1)
**How to avoid:** Always mock WriteLog and Write-Host, use `-ParameterFilter` to assert message content
**Warning signs:** Tests take >10 seconds, tests fail when log file is locked, tests create actual log files

### Pitfall 5: Missing Build Impact Statements
**What goes wrong:** Non-critical failures don't state if build continues, users assume build aborted
**Why it happens:** Forgetting to add "The build will continue without [X] drivers." to remediation messages
**How to avoid:** Every non-critical failure (graceful degradation) explicitly states build impact
**Warning signs:** User questions like "Did the build fail?" after seeing WARNING messages in logs

## Code Examples

Verified patterns from existing codebase:

### Example 1: WriteLog Function Signature
```powershell
# Source: FFUDevelopment\FFU.Common\FFU.Common.Core.psm1 lines 141-148
function WriteLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogText
    )
    # ... implementation writes to file + queue, adds timestamp, mutex-protected ...
}

# Usage - simple string parameter
WriteLog "Message text here"
WriteLog "[Dell][Latitude 7490][Download] Downloading drivers"
```

### Example 2: Existing Dual Output Pattern (Needs Retrofit)
```powershell
# Source: FFU.Drivers.psm1 lines 710-711 (CURRENT - console-only)
Write-Host "The model '$Model' was not found in the list of available models."
Write-Host "Please run the script with the -Verbose switch to see the list of available models."

# PROPOSED MIGRATION (dual output + structured prefix)
WriteLog "[HP][$Model][Selection] Model not found in available models"
Write-Host "The model '$Model' was not found in the list of available models."
Write-Host "Please run the script with the -Verbose switch to see the list of available models."
```

### Example 3: Existing Remediation Pattern (Needs Structured Prefix)
```powershell
# Source: FFU.Drivers.psm1 lines 1716-1718 (Phase 32 - Dell catalog failure)
# CURRENT (lacks structured prefix)
catch {
    WriteLog "WARNING: Dell catalog download failed: $($_.Exception.Message)"
    WriteLog "WARNING: Remediation: Check network connectivity to downloads.dell.com. Verify proxy settings if behind a corporate firewall. The build will continue without Dell drivers."
    return
}

# PROPOSED RETROFIT (add structured prefix)
catch {
    WriteLog "WARNING: [Dell][$Model][Download] Catalog download failed: $($_.Exception.Message)"
    WriteLog "WARNING: [Dell][$Model][Download] Remediation: Check network connectivity to downloads.dell.com. Verify proxy settings if behind a corporate firewall. See FFUDevelopment.log for full error details. The build will continue without Dell drivers."
    Write-Host "WARNING: Dell catalog download failed. Build will continue without Dell drivers."
    return
}
```

### Example 4: Write-Verbose Migration Pattern
```powershell
# Source: FFU.Drivers.psm1 lines 101, 114 (Invoke-DriverDownloadWithRetry)
# CURRENT (verbose-only, no file logging)
$successMsg = "$OperationName completed successfully"
if ($function:WriteLog) {
    WriteLog $successMsg
}
else {
    Write-Verbose $successMsg
}

# PROPOSED SIMPLIFICATION (WriteLog always available in production)
$successMsg = "[OEM][$Model][Download] $OperationName completed successfully"
WriteLog $successMsg
Write-Verbose $successMsg  # Keep for -Verbose users
```

### Example 5: Timing Pattern
```powershell
# PROPOSED PATTERN (download timing)
$startTime = [DateTime]::Now
try {
    Invoke-DriverDownloadWithRetry -Source $url -Destination $dest -OperationName "Dell driver catalog"
    $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
    WriteLog "[Dell][$Model][Download] Download complete in $($elapsed.ToString('F1'))s"
}
catch {
    $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
    WriteLog "WARNING: [Dell][$Model][Download] Download failed after $($elapsed.ToString('F1'))s: $($_.Exception.Message)"
    # ... remediation ...
}
```

### Example 6: Mock-Based Test Pattern
```powershell
# PROPOSED PATTERN (based on existing FFU.Drivers.Tests.ps1 structure)
Describe 'OEM Driver Logging - Dell Catalog Download' -Tag 'Unit', 'FFU.Drivers', 'Logging' {
    BeforeAll {
        Mock WriteLog {}
        Mock Write-Host {}
        Mock Get-CachedOEMCatalog { throw "Network error" }
    }

    Context 'Catalog Download Failure' {
        It 'Should log failure with structured prefix' {
            Get-DellDrivers -Make 'Dell' -Model 'Latitude 7490' -WindowsArch 'x64' -WindowsRelease 11 -DriversFolder $testPath -FFUDevelopmentPath $testPath -isServer $false

            Should -Invoke WriteLog -ParameterFilter {
                $LogText -match '\[Dell\]\[Latitude 7490\]\[Download\]' -and
                $LogText -match 'Catalog download failed'
            }
        }

        It 'Should log remediation steps' {
            Get-DellDrivers -Make 'Dell' -Model 'Latitude 7490' -WindowsArch 'x64' -WindowsRelease 11 -DriversFolder $testPath -FFUDevelopmentPath $testPath -isServer $false

            Should -Invoke WriteLog -ParameterFilter {
                $LogText -match 'Remediation:' -and
                $LogText -match 'downloads.dell.com' -and
                $LogText -match 'build will continue'
            }
        }

        It 'Should preserve Write-Host for console visibility' {
            Get-DellDrivers -Make 'Dell' -Model 'Latitude 7490' -WindowsArch 'x64' -WindowsRelease 11 -DriversFolder $testPath -FFUDevelopmentPath $testPath -isServer $false

            Should -Invoke Write-Host -ParameterFilter {
                $_ -match 'Build will continue without Dell drivers'
            }
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Console-only output (Write-Host) | File logging via WriteLog | v0.0.1 (WriteLog added) | Console output not captured in logs, troubleshooting hard |
| Get-Date for timestamps | [DateTime]::Now | v0.0.9 (ThreadJob fix) | ThreadJob compatibility, no cmdlet availability issues |
| Write-Host for all output | [Console]::WriteLine() | v0.0.10 (ThreadJob fix) | ThreadJob-safe, but NOT applicable to driver logging (dual output needed) |
| Single output destination | Dual output (file + queue) | v0.0.12 (UI integration) | Real-time UI updates via queue + file logging |
| Unstructured log messages | Structured prefix format | Phase 33 (this phase) | Grep/filtering, consistent troubleshooting |

**Deprecated/outdated:**
- **Write-Host only:** Deprecated for driver operations, must add WriteLog for file logging (but keep Write-Host for console)
- **Write-Warning for driver errors:** No longer used (WriteLog + Write-Host pattern), inconsistent with file logging
- **Get-Date in driver code:** Deprecated (use [DateTime]::Now for ThreadJob compatibility)

## Open Questions

Things that couldn't be fully resolved:

1. **ThreadJob-safe $function:WriteLog guard pattern**
   - What we know: Invoke-DriverDownloadWithRetry (lines 97-102) checks `if ($function:WriteLog)` before calling WriteLog
   - What's unclear: Is this guard still needed? BuildFFUVM.ps1 runs in ThreadJob, but FFU.Core is always imported
   - Recommendation: Simplify to direct WriteLog calls (guard was defensive for older code), but verify no edge cases

2. **BuildFFUVM.ps1 driver section logging**
   - What we know: BuildFFUVM.ps1 lines 2564-2596 already use WriteLog for driver operations
   - What's unclear: Do these messages need structured prefix retrofit? (e.g., "Getting HP drivers" → "[HP][$Model][Download] Starting driver download")
   - Recommendation: Include in audit inventory, retrofit if needed for consistency

3. **Timing precision requirements**
   - What we know: Timing should show seconds with one decimal place (4.5s)
   - What's unclear: Is sub-second precision needed for very fast operations? (0.1s vs "< 1s")
   - Recommendation: Use `ToString('F1')` for consistency, no special handling for fast operations

## Sources

### Primary (HIGH confidence)
- **FFU.Common.Core.psm1** (lines 141-231) - WriteLog function implementation and signature
- **FFU.Drivers.psm1** (2,293 lines) - Existing driver code with 12 console output calls
- **BuildFFUVM.ps1** (lines 2564-2596) - Driver download orchestration
- **Tests/Unit/FFU.Drivers.Tests.ps1** - Existing Pester test patterns (mock-based)
- **CLAUDE.md** - ThreadJob compatibility notes (v0.0.9, v0.0.10, v0.0.12 fixes)
- **33-CONTEXT.md** - User decisions from `/gsd:discuss-phase`

### Secondary (MEDIUM confidence)
- **Phase 31 implementation** - HP exit code 1168 handling (lines 232-239) as reference pattern
- **Phase 32 implementation** - Dell catalog failure handling (lines 1710-1745) as reference pattern
- **IMPLEMENTATION_PATTERNS.md** - Error handling patterns, logging guidance

### Tertiary (LOW confidence)
- None - all findings verified against codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components exist in codebase, no external dependencies
- Architecture: HIGH - Patterns verified in existing code (WriteLog, Pester mocking, dual output)
- Pitfalls: HIGH - Based on common logging mistakes and ThreadJob compatibility issues (v0.0.9, v0.0.10, v0.0.12)

**Research date:** 2026-01-27
**Valid until:** 2026-02-27 (30 days - stable patterns, no fast-moving dependencies)
