# Architecture Research: Readiness Dashboard Integration

**Domain:** WPF Application - Pre-Flight Validation Dashboard
**Researched:** 2026-02-05
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    WPF UI Layer (STA Thread)                 │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Home Tab   │  │  Config Tab  │  │  Build Tab   │      │
│  │  (Dashboard) │  │              │  │              │      │
│  └──────┬───────┘  └──────────────┘  └──────────────┘      │
│         │                                                     │
│    ┌────▼────────────────────────────────────┐               │
│    │  Dashboard Controls (New Component)     │               │
│    │  - Status Badges                        │               │
│    │  - Check Results List                   │               │
│    │  - Auto-Fix Buttons                     │               │
│    │  - Refresh Button                       │               │
│    │  - Build Gate (Enable/Disable Build)    │               │
│    └────┬────────────────────────────────────┘               │
│         │                                                     │
├─────────┴─────────────────────────────────────────────────────┤
│              UI State Management Layer                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │  $script:uiState.Data.preflightResults (new field) │    │
│  │  - Check results from FFU.Preflight                 │    │
│  │  - Last run timestamp                                │    │
│  │  - Critical failures flag                            │    │
│  │  - Hypervisor selection awareness                    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  DispatcherTimer (50ms interval) - EXISTING         │    │
│  │  - Polls ConcurrentQueue for async check updates    │    │
│  │  - Updates dashboard controls                        │    │
│  │  - Triggers UI refresh on state change               │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│             Background Execution Layer                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Start-ThreadJob (Background Check Runner)          │    │
│  │  - Runs Invoke-FFUPreflight                          │    │
│  │  - Passes hypervisor selection                       │    │
│  │  - Sends results via ConcurrentQueue                 │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│              Validation & Remediation Layer                  │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐   │
│  │  FFU.Preflight Module (EXISTING)                     │   │
│  │  - Invoke-FFUPreflight (orchestrator)                │   │
│  │  - 16 individual Test-FFU* functions                 │   │
│  │  - Tiered validation (Critical/Warning/Info)         │   │
│  │  - Hypervisor-aware checks                           │   │
│  │  - Returns structured results                        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  FFU.Hypervisor Module (EXISTING)                    │   │
│  │  - Test-HypervisorService (service health)           │   │
│  │  - Provider pattern (HyperV/VMware)                  │   │
│  │  - Supplies hypervisor type to preflight             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Auto-Remediation Functions (NEW)                    │   │
│  │  - Repair-FFUWimMount                                │   │
│  │  - Enable-FFUHyperV                                  │   │
│  │  - Install-FFUADK                                    │   │
│  │  - Clear-FFUDismState                                │   │
│  └──────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│              Messaging & Communication Layer                 │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐   │
│  │  FFU.Messaging Module (EXISTING)                     │   │
│  │  - ConcurrentQueue for thread-safe updates           │   │
│  │  - FFUMessage class with severity levels             │   │
│  │  - FFUProgressMessage for check progress             │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **Dashboard UI Controls** | Display check results, provide user actions (auto-fix, refresh) | WPF XAML controls bound to $uiState data |
| **UI State Manager** | Store check results, track dashboard state, coordinate updates | PowerShell hashtable in $script:uiState.Data |
| **DispatcherTimer** | Poll ConcurrentQueue for updates, trigger UI refresh | System.Windows.Threading.DispatcherTimer (50ms) |
| **ThreadJob Runner** | Execute preflight checks async without blocking UI | Start-ThreadJob with Invoke-FFUPreflight |
| **FFU.Preflight** | Orchestrate validation checks, return structured results | Module with 16+ Test-FFU* functions |
| **Auto-Remediation** | Fix common issues programmatically | New functions wrapping existing repair logic |
| **FFU.Messaging** | Thread-safe communication between UI and background job | ConcurrentQueue-based message passing |
| **Build Gate** | Enable/disable Build button based on critical checks | Event handler checking $uiState.Data.preflightResults |

## Integration with Existing Architecture

### How Dashboard Connects to FFU.Preflight

**Current state:**
- `FFU.Preflight` module exists with `Invoke-FFUPreflight` orchestrator
- 16 individual `Test-FFU*` functions (Administrator, PowerShellVersion, HyperV, ADK, DiskSpace, Network, WimMount, etc.)
- Returns structured results: `CheckName`, `Status` (Passed/Failed/Warning/Skipped), `Severity`, `Message`, `Details`, `Remediation`, `DurationMs`
- Already supports tiered validation (Critical, Warning, Info)
- Already has hypervisor awareness (checks `Test-FFUHyperV` for Hyper-V, `Test-FFUVmxToolkit` for VMware)

**New integration points:**

1. **Dashboard Invocation Point** (Home Tab Load)
```powershell
# In FFUUI.Core\Initialize-HomeTab.ps1 (NEW FUNCTION)
function Initialize-HomeTab {
    param([PSCustomObject]$State)

    # Initialize dashboard UI elements
    $refreshButton = $State.Window.FindName('RefreshPreflightButton')
    $checksList = $State.Window.FindName('PreflightChecksList')

    # Trigger initial preflight check
    Invoke-PreflightCheckAsync -State $State
}
```

2. **Background Check Execution**
```powershell
# In FFUUI.Core\Invoke-PreflightCheckAsync.ps1 (NEW FUNCTION)
function Invoke-PreflightCheckAsync {
    param([PSCustomObject]$State)

    # Read hypervisor selection from UI
    $hypervisorType = Get-SelectedHypervisor -State $State  # 'HyperV', 'VMware', or 'Auto'

    # Get enabled features from UI
    $enabledFeatures = Get-EnabledFeatures -State $State

    # Launch ThreadJob for async execution
    $job = Start-ThreadJob -ScriptBlock {
        param($FFUDevPath, $HypervisorType, $Features, $SyncContext)

        # Import modules in background context
        Import-Module "$FFUDevPath\Modules\FFU.Preflight" -Force

        # Run preflight with hypervisor awareness
        $results = Invoke-FFUPreflight -HypervisorType $HypervisorType -Features $Features

        # Send results via messaging queue
        $msg = [FFUMessage]::new([FFUMessageLevel]::Info, "Preflight checks complete")
        $msg.Data['PreflightResults'] = $results
        $SyncContext.MessageQueue.Enqueue($msg)

    } -ArgumentList $State.FFUDevelopmentPath, $hypervisorType, $enabledFeatures, $State.Data.messagingContext

    # Store job reference for polling
    $State.Data.preflightJob = $job
}
```

3. **DispatcherTimer Update Handler** (EXISTING - ENHANCED)
```powershell
# In BuildFFUVM_UI.ps1 DispatcherTimer.Add_Tick (MODIFY EXISTING)
$script:uiState.Data.pollTimer.Add_Tick({
    # EXISTING: Process messages from build job
    if ($script:uiState.Data.messagingContext) {
        $msg = $null
        while ($script:uiState.Data.messagingContext.MessageQueue.TryDequeue([ref]$msg)) {
            # NEW: Handle preflight result messages
            if ($msg.Data.ContainsKey('PreflightResults')) {
                Update-PreflightDashboard -State $script:uiState -Results $msg.Data['PreflightResults']
            }
            # EXISTING: Handle build progress messages...
        }
    }
})
```

### Hypervisor Selection Flow

**How hypervisor selection feeds into preflight:**

1. **UI Capture** (Config Tab)
```
User selects Hypervisor: [Dropdown: Auto | Hyper-V | VMware Workstation Pro]
   ↓
Stored in: $uiState.Controls.HypervisorComboBox.SelectedItem
   ↓
Read by: Get-SelectedHypervisor function
```

2. **Preflight Filtering** (FFU.Preflight)
```powershell
# In Invoke-FFUPreflight (EXISTING - MODIFY)
function Invoke-FFUPreflight {
    param(
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'Auto',  # NEW PARAMETER

        [hashtable]$Features = @{}
    )

    # Resolve 'Auto' to actual hypervisor
    if ($HypervisorType -eq 'Auto') {
        $HypervisorType = Resolve-AutoHypervisor  # Checks what's available
    }

    # TIER 1: Critical checks (always run)
    $results += Test-FFUAdministrator
    $results += Test-FFUPowerShellVersion

    # CONDITIONAL: Only check selected hypervisor
    if ($HypervisorType -eq 'HyperV') {
        $results += Test-FFUHyperV
        $results += Test-FFUHyperVSwitchConflict
    }
    elseif ($HypervisorType -eq 'VMware') {
        $results += Test-FFUVmxToolkit
        $results += Test-FFUVMwareBridgeConfiguration
        $results += Test-FFUVMwareDrivers
    }

    # TIER 2: Feature-dependent checks
    if ($Features.CreateCaptureMedia -or $Features.CreateDeploymentMedia) {
        $results += Test-FFUADK
        $results += Test-FFUWimMount
    }
    # ... etc
}
```

3. **Result Filtering in UI**
```
FFU.Preflight returns only relevant checks
   ↓
Dashboard displays only checked items
   ↓
Build gate evaluates only relevant critical failures
```

### Data Flow: Check Execution → Result → UI Update → Remediation

```
┌──────────────────────────────────────────────────────────────┐
│ PHASE 1: User Action                                          │
└──────────────────────────────────────────────────────────────┘
    User clicks "Refresh Checks" button OR selects hypervisor
    User clicks "Start Build" button (triggers auto-check)
                     ↓
┌──────────────────────────────────────────────────────────────┐
│ PHASE 2: Preflight Execution (Background ThreadJob)           │
└──────────────────────────────────────────────────────────────┘
    Invoke-PreflightCheckAsync launches Start-ThreadJob
                     ↓
    ThreadJob executes Invoke-FFUPreflight with:
      - HypervisorType: from UI selection
      - Features: from enabled checkboxes
                     ↓
    Invoke-FFUPreflight runs tiered checks:
      Tier 1 (Critical): Administrator, PowerShell, Hypervisor
      Tier 2 (Feature-Dependent): ADK, WimMount, DiskSpace, Network
      Tier 3 (Recommended): Antivirus Exclusions
      Tier 4 (Cleanup): DISM State
                     ↓
    Each Test-FFU* function returns:
      [PSCustomObject]@{
          CheckName   = 'HyperV'
          Status      = 'Failed'
          Severity    = 'Critical'
          Message     = 'Hyper-V feature not installed'
          Details     = @{ FeatureName = 'Microsoft-Hyper-V-All' }
          Remediation = '=== ISSUE ===\nHyper-V not installed...'
          DurationMs  = 1500
      }
                     ↓
    Results collection sent via FFU.Messaging:
      $msg = [FFUMessage]::new([FFUMessageLevel]::Info, "Checks complete")
      $msg.Data['PreflightResults'] = $results
      $messagingContext.MessageQueue.Enqueue($msg)
                     ↓
┌──────────────────────────────────────────────────────────────┐
│ PHASE 3: UI Update (DispatcherTimer Tick - 50ms interval)     │
└──────────────────────────────────────────────────────────────┘
    DispatcherTimer.Tick fires
                     ↓
    Dequeue message from ConcurrentQueue
                     ↓
    Detect 'PreflightResults' in message data
                     ↓
    Call Update-PreflightDashboard:
      - Parse results array
      - Update $uiState.Data.preflightResults
      - Set $uiState.Data.hasCriticalFailures = $true if any Severity='Critical' and Status='Failed'
      - Update UI controls:
          * Status badge (✓ Ready / ⚠ Issues / ✗ Critical)
          * Checks list (populate DataGrid/ListView)
          * Auto-fix buttons (visible if Remediation available)
          * Build button (Enabled = !hasCriticalFailures)
                     ↓
    WPF data binding refreshes UI visually
                     ↓
┌──────────────────────────────────────────────────────────────┐
│ PHASE 4: Auto-Remediation (Optional User Action)              │
└──────────────────────────────────────────────────────────────┘
    User clicks "Auto-Fix" button next to failed check
                     ↓
    Invoke-AutoRemediation function:
      - Read CheckName from button context
      - Switch on CheckName:
          'WimMount'   → Repair-FFUWimMount
          'HyperV'     → Enable-FFUHyperV
          'ADK'        → Install-FFUADK
          'DISMState'  → Clear-FFUDismState
                     ↓
    Remediation function executes:
      - Shows progress dialog
      - Runs fix commands (Enable-WindowsOptionalFeature, etc.)
      - Returns success/failure
                     ↓
    If success:
      - Re-run specific check: Test-FFU* function
      - Update result in $uiState.Data.preflightResults
      - Refresh dashboard display
                     ↓
    If failure:
      - Show detailed error dialog
      - Display manual remediation steps from Remediation field
```

### New vs Modified Components

| Component | Status | Location | Purpose |
|-----------|--------|----------|---------|
| **Dashboard XAML** | NEW | BuildFFUVM_UI.xaml (Home Tab section) | Visual controls for check display |
| **Initialize-HomeTab** | NEW | FFUUI.Core\Functions\Initialize-HomeTab.ps1 | Sets up dashboard on tab load |
| **Invoke-PreflightCheckAsync** | NEW | FFUUI.Core\Functions\Invoke-PreflightCheckAsync.ps1 | Launches background checks |
| **Update-PreflightDashboard** | NEW | FFUUI.Core\Functions\Update-PreflightDashboard.ps1 | Updates UI with check results |
| **Invoke-AutoRemediation** | NEW | FFUUI.Core\Functions\Invoke-AutoRemediation.ps1 | Dispatches fix functions |
| **Repair-FFUWimMount** | NEW | FFU.Preflight\Public\Repair-FFUWimMount.ps1 | Fixes WimMount service |
| **Enable-FFUHyperV** | NEW | FFU.Preflight\Public\Enable-FFUHyperV.ps1 | Installs Hyper-V feature |
| **Install-FFUADK** | NEW | FFU.Preflight\Public\Install-FFUADK.ps1 | Downloads/installs ADK |
| **Clear-FFUDismState** | NEW | FFU.Preflight\Public\Clear-FFUDismState.ps1 | Clears DISM corruption |
| **Invoke-FFUPreflight** | MODIFY | FFU.Preflight\FFU.Preflight.psm1 | Add -HypervisorType parameter |
| **BuildFFUVM_UI.ps1** | MODIFY | BuildFFUVM_UI.ps1 | Add preflightResults to $uiState.Data |
| **DispatcherTimer.Tick** | MODIFY | BuildFFUVM_UI.ps1 (line ~673) | Handle PreflightResults messages |
| **Build Button Click** | MODIFY | FFUUI.Core\Register-EventHandlers.ps1 | Gate on hasCriticalFailures |
| **FFU.Messaging** | EXISTING | Modules\FFU.Messaging\FFU.Messaging.psm1 | No changes (already supports structured data) |
| **FFU.Preflight** | EXISTING | Modules\FFU.Preflight\FFU.Preflight.psm1 | No changes to check functions (only orchestrator) |
| **FFU.Hypervisor** | EXISTING | Modules\FFU.Hypervisor\FFU.Hypervisor.psm1 | No changes (already provides service tests) |

## Architectural Patterns

### Pattern 1: Async-First UI Updates

**What:** All long-running operations execute in background jobs with results streamed via ConcurrentQueue

**When to use:** Any operation that takes >100ms (network checks, disk scans, service queries)

**Trade-offs:**
- **Pro:** UI stays responsive, no freezing
- **Pro:** User can continue working while checks run
- **Con:** Requires message passing infrastructure
- **Con:** Error handling more complex (no direct try/catch)

**Example:**
```powershell
# ANTI-PATTERN: Blocking UI
$checkResults = Invoke-FFUPreflight  # UI freezes for 5-10 seconds

# PATTERN: Async with messaging
$job = Start-ThreadJob -ScriptBlock {
    $results = Invoke-FFUPreflight
    $syncContext.MessageQueue.Enqueue(@{ Results = $results })
}
# UI continues responding, DispatcherTimer handles results when ready
```

### Pattern 2: Build Gating

**What:** Disable critical user actions until prerequisites are met

**When to use:** When proceeding with incomplete setup causes errors or data loss

**Trade-offs:**
- **Pro:** Prevents user mistakes (clicking Build before ready)
- **Pro:** Clear visual feedback (disabled button = not ready)
- **Con:** Must be accurate (false negatives frustrate users)
- **Con:** Requires real-time validation

**Example:**
```powershell
# Build button state management
function Update-BuildButtonState {
    param([PSCustomObject]$State)

    $buildButton = $State.Window.FindName('BuildButton')
    $criticalFailures = $State.Data.preflightResults |
        Where-Object { $_.Severity -eq 'Critical' -and $_.Status -eq 'Failed' }

    if ($criticalFailures.Count -gt 0) {
        $buildButton.IsEnabled = $false
        $buildButton.ToolTip = "Cannot start build: $($criticalFailures.Count) critical issues. Check Home tab for details."
    }
    else {
        $buildButton.IsEnabled = $true
        $buildButton.ToolTip = "Start FFU build process"
    }
}
```

### Pattern 3: Hypervisor-Aware Validation

**What:** Only validate prerequisites for the selected hypervisor backend

**When to use:** When different backends have different requirements (Hyper-V vs VMware)

**Trade-offs:**
- **Pro:** Fewer false positives (don't check VMware if using Hyper-V)
- **Pro:** Faster checks (skip irrelevant validations)
- **Con:** Selection must be known before checks run
- **Con:** Changing hypervisor requires re-check

**Example:**
```powershell
# Conditional check execution based on hypervisor
if ($HypervisorType -eq 'HyperV') {
    $results += Test-FFUHyperV                    # Hyper-V feature
    $results += Test-FFUHyperVSwitchConflict      # External vSwitch check
}
elseif ($HypervisorType -eq 'VMware') {
    $results += Test-FFUVmxToolkit                # vmxtoolkit module
    $results += Test-FFUVMwareBridgeConfiguration # Network adapter
    $results += Test-FFUVMwareDrivers             # Intel e1000e drivers
}
# Common checks run regardless of hypervisor
$results += Test-FFUDiskSpace
$results += Test-FFUNetwork
```

### Pattern 4: Tiered Validation

**What:** Group checks by severity and run critical checks first

**When to use:** When some failures block everything else (e.g., no admin = can't proceed)

**Trade-offs:**
- **Pro:** Fast failure (don't waste time if admin rights missing)
- **Pro:** Clear severity visualization in UI
- **Con:** Requires careful severity classification

**Example:**
```powershell
# Tier 1: CRITICAL (Always Run, Blocking)
$tier1 = @(
    Test-FFUAdministrator,
    Test-FFUPowerShellVersion,
    Test-FFUHypervisor  # Conditional on selection
)

# Tier 2: FEATURE-DEPENDENT (Conditional, Blocking)
if ($Features.CreateCaptureMedia) {
    $tier2 = @(
        Test-FFUADK,
        Test-FFUWimMount
    )
}

# Early exit if critical failures
if ($tier1 | Where-Object Status -eq 'Failed') {
    return $tier1  # Don't run Tier 2
}
```

### Pattern 5: Self-Describing Remediation

**What:** Check results include structured remediation steps (PowerShell commands + manual steps)

**When to use:** When fixes are complex or multi-step

**Trade-offs:**
- **Pro:** User has clear path to fix (no guesswork)
- **Pro:** Can be automated (parse commands and run)
- **Con:** Remediation must be tested (wrong commands break system)
- **Con:** Version-specific (Windows 10 vs 11, Server vs Client)

**Example:**
```powershell
# From New-FFURemediationBlock
$remediation = @"
=== ISSUE ===
Hyper-V feature not installed

=== IMPACT ===
Cannot create build VM

=== FIX ===
Run these PowerShell commands (as Administrator):

    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart

Manual steps:
    1. Restart computer after enabling Hyper-V
    2. Verify BIOS virtualization is enabled

=== VERIFY ===
Run this to confirm the fix worked:

    Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
"@
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Blocking Checks on UI Thread

**What people do:** Run `Invoke-FFUPreflight` directly in button click handler

**Why it's wrong:**
- UI freezes for 5-10 seconds during checks
- User cannot cancel or interact
- Progress cannot be shown incrementally
- Violates STA thread responsiveness

**Do this instead:** Always use `Start-ThreadJob` with `ConcurrentQueue` messaging

### Anti-Pattern 2: Checking All Hypervisors Regardless of Selection

**What people do:** Run all hypervisor checks (Hyper-V, VMware, etc.) every time

**Why it's wrong:**
- False negatives (VMware checks fail when user selected Hyper-V)
- Confuses users ("Why is it checking VMware when I'm using Hyper-V?")
- Wastes time (3-5 extra seconds per check)
- Dashboard cluttered with irrelevant failures

**Do this instead:** Pass `-HypervisorType` to `Invoke-FFUPreflight` and conditionally run checks

### Anti-Pattern 3: Generic Error Messages Without Remediation

**What people do:** Return "Check failed" without actionable guidance

**Why it's wrong:**
- User has no path to fix
- Requires knowledge of system internals
- Support burden (users ask "What do I do now?")
- Poor UX (frustration without resolution)

**Do this instead:** Use `New-FFURemediationBlock` with structured Issue/Impact/Fix/Verify sections

### Anti-Pattern 4: No Build Gating (Allow Build Despite Critical Failures)

**What people do:** Show warnings but allow Build button click anyway

**Why it's wrong:**
- Build fails 5-10 minutes later with cryptic error
- Wastes time (user could have fixed issue upfront)
- Bad UX (why warn if you don't enforce?)
- Data loss risk (partial FFU creation that corrupts state)

**Do this instead:** Disable Build button when `hasCriticalFailures = $true`

### Anti-Pattern 5: File-Based Status Polling

**What people do:** Write check status to file, poll with `Get-Content` every 500ms

**Why it's wrong:**
- File I/O is slow (50-100ms per poll)
- Race conditions (read while writing)
- Disk wear (SSD lifespan concern)
- Stale data (up to 500ms latency)
- Existing pattern uses 50ms DispatcherTimer (10x faster)

**Do this instead:** Use `ConcurrentQueue` from `FFU.Messaging` module (already implemented, 20x faster)

## Scalability Considerations

| Scale | Dashboard Response | Architecture Adjustments |
|-------|-------------------|--------------------------|
| **1-5 checks** | Instant (<100ms) | Direct execution acceptable, but still use async for consistency |
| **5-15 checks** | Fast (<500ms) | Async required, sequential check execution acceptable |
| **15-30 checks** | Moderate (1-2s) | Parallel check execution needed (ForEach-Object -Parallel) |
| **30+ checks** | Slow (3-5s+) | Tiered execution (critical first), batching, progress indicators |

### Current State: 16 Checks

**Recommendation:** Sequential async execution with progress updates

**Why:**
- 16 checks at ~100-300ms each = 1.6-4.8 seconds total
- Acceptable latency for preflight (users expect validation to take a moment)
- Sequential is simpler (no race conditions, clear ordering)
- Parallel would only save 1-2 seconds (not worth complexity)

**Future-proofing:** If checks grow to 30+, refactor to parallel:
```powershell
$checkFunctions = @(
    { Test-FFUAdministrator },
    { Test-FFUPowerShellVersion },
    { Test-FFUHyperV },
    # ... 27 more
)

$results = $checkFunctions | ForEach-Object -Parallel {
    & $_.Invoke()
} -ThrottleLimit 8
```

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| **Hyper-V Management** | Get-WindowsOptionalFeature, Get-VMSwitch | Requires elevation, existing FFU.Hypervisor provider wraps this |
| **VMware REST API** | Invoke-RestMethod to http://localhost:8697/api | Requires vmrest service, existing VMwareProvider implements |
| **Windows ADK** | Registry checks, Test-Path on installation folders | FFU.ADK module already has validation functions |
| **DISM** | Get-WindowsImage, Repair-WindowsImage | FFU.Preflight already uses, need service state checks |
| **WIMMount Service** | Get-Service, fltmc.exe queries | FFU.Preflight Test-FFUWimMount already implements |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **UI ↔ Background Job** | ConcurrentQueue (FFU.Messaging) | Lock-free, high-performance, already battle-tested |
| **FFU.Preflight ↔ FFU.Hypervisor** | Direct function calls | Same process, module dependency declared in manifest |
| **Dashboard ↔ Build Pipeline** | $uiState.Data.preflightResults | Shared state, Build button reads this for gating |
| **Auto-Remediation ↔ FFU.Preflight** | Function calls with Try/Catch | Remediation functions wrap check logic for idempotency |

## Build Order (Dependency-Aware)

### Phase 1: Core Infrastructure (No Dependencies)

1. **Dashboard XAML Controls** (BuildFFUVM_UI.xaml)
   - Status badge (TextBlock)
   - Checks list (DataGrid or ListView)
   - Refresh button
   - Auto-fix buttons (templated, hidden by default)

2. **UI State Extension** (BuildFFUVM_UI.ps1)
   - Add `preflightResults` field to `$uiState.Data`
   - Add `hasCriticalFailures` flag
   - Add `lastPreflightRun` timestamp

3. **Messaging Context** (Already exists in FFU.Messaging)
   - No changes needed
   - Verify `FFUMessage.Data` hashtable supports nested objects

### Phase 2: Preflight Enhancements (Depends on Phase 1)

4. **Invoke-FFUPreflight Modification** (FFU.Preflight.psm1)
   - Add `-HypervisorType` parameter
   - Add conditional check execution based on hypervisor
   - Test existing check functions return correct structure

5. **Auto-Remediation Functions** (FFU.Preflight\Public\*)
   - `Repair-FFUWimMount` (wraps existing repair logic)
   - `Enable-FFUHyperV` (calls Enable-WindowsOptionalFeature)
   - `Install-FFUADK` (uses existing FFU.ADK installer)
   - `Clear-FFUDismState` (runs DISM cleanup commands)

### Phase 3: UI Integration Functions (Depends on Phases 1-2)

6. **Initialize-HomeTab** (FFUUI.Core\Functions\)
   - Binds dashboard controls to $uiState
   - Triggers initial preflight check
   - Sets up event handlers for Refresh button

7. **Invoke-PreflightCheckAsync** (FFUUI.Core\Functions\)
   - Launches Start-ThreadJob
   - Passes hypervisor selection and features
   - Sends results via ConcurrentQueue

8. **Update-PreflightDashboard** (FFUUI.Core\Functions\)
   - Parses preflight results
   - Updates DataGrid/ListView items
   - Sets status badge (✓/⚠/✗)
   - Evaluates hasCriticalFailures flag

9. **Invoke-AutoRemediation** (FFUUI.Core\Functions\)
   - Switch statement on CheckName
   - Calls appropriate remediation function
   - Shows progress dialog
   - Re-runs check on success

### Phase 4: Event Handler Modifications (Depends on Phases 1-3)

10. **DispatcherTimer Enhancement** (BuildFFUVM_UI.ps1)
    - Add message handler for 'PreflightResults'
    - Call Update-PreflightDashboard when received

11. **Build Button Gating** (FFUUI.Core\Register-EventHandlers.ps1)
    - Check $uiState.Data.hasCriticalFailures before build
    - Show dialog if critical failures exist
    - Offer to open Home tab to view/fix issues

12. **Hypervisor Selection Change** (FFUUI.Core\Register-EventHandlers.ps1)
    - Re-run preflight when hypervisor dropdown changes
    - Clear old results that no longer apply

### Phase 5: Polish & Edge Cases (Depends on Phases 1-4)

13. **Error Handling**
    - Handle preflight check timeouts (kill ThreadJob after 30s)
    - Handle missing check functions gracefully
    - Handle remediation failures with fallback to manual steps

14. **Visual Polish**
    - Add icons for check status (✓ green, ⚠ yellow, ✗ red)
    - Add tooltip on disabled Build button explaining why
    - Add loading spinner during checks
    - Add last-run timestamp display

15. **Testing & Validation**
    - Pester tests for each remediation function
    - UI automation tests for dashboard updates
    - Manual testing of all hypervisor combinations

## Suggested Build Order Rationale

**Why this order:**

1. **Foundation first:** Dashboard UI and state management don't depend on anything
2. **Enhance preflight:** Make FFU.Preflight hypervisor-aware before UI consumes it
3. **Wire up integration:** UI functions that call preflight and display results
4. **Connect event handlers:** Hook up existing UI events to new functionality
5. **Polish last:** Error handling and visual improvements after core works

**Critical path:** Phases 1-2-3 are sequential (each depends on previous). Phase 4 can partially overlap with Phase 3. Phase 5 can overlap with Phase 4.

**Parallel work:** If multiple developers:
- Dev 1: Phase 1-2 (XAML + Preflight changes)
- Dev 2: Phase 5 (Remediation functions)
- Dev 3: Phase 3-4 (UI integration + event handlers)

## Sources

**HIGH CONFIDENCE (Codebase Analysis):**
- BuildFFUVM_UI.ps1: Existing DispatcherTimer pattern (lines 666-834)
- FFU.Preflight module: Check function structure and return format (lines 26-101)
- FFU.Messaging module: ConcurrentQueue usage (lines 132-200)
- FFU.Hypervisor module: Provider pattern and service tests (lines 89-200)
- FFUUI.Core module: UI state management ($uiState structure, lines 54-89)

**MEDIUM CONFIDENCE (Domain Knowledge):**
- WPF STA threading requirements (standard .NET/WPF architecture)
- PowerShell ThreadJob vs Start-Job credential inheritance (documented behavior)
- DispatcherTimer 50ms interval pattern (existing implementation in codebase)

**Recommendations are based on:**
- Existing architectural patterns in FFUBuilder codebase
- Minimal disruption principle (reuse existing FFU.Messaging, FFU.Preflight)
- WPF best practices (async-first, data binding, separation of concerns)
- Build gating patterns from similar validation-heavy applications

---
*Architecture research for: FFUBuilder Readiness Dashboard*
*Researched: 2026-02-05*
