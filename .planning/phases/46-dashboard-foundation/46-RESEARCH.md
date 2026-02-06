# Phase 46: Dashboard Foundation - Research

**Researched:** 2026-02-06
**Domain:** WPF dashboard UI with background validation and real-time status display
**Confidence:** HIGH

## Summary

Phase 46 transforms the Home tab from a placeholder into a live pre-flight readiness dashboard. This involves:
- WPF UI controls for grouped status display (Expander/TreeView patterns)
- Background execution of FFU.Preflight validation checks
- Real-time UI updates via FFU.Messaging ConcurrentQueue pattern
- Visual status indicators with severity-based coloring
- Build button gating based on check results

The codebase already contains all necessary infrastructure: FFU.Preflight module with 16+ validation functions returning structured results, FFU.Messaging module for thread-safe background-to-UI communication, and established WPF patterns (Expander controls, status text updates, progress bars). This phase is primarily UI wiring and layout work, not new framework development.

**Primary recommendation:** Leverage existing patterns. Use WPF ItemsControl with Expander for category grouping, FFU.Messaging for background check execution, and the established check result structure (Status, Severity, Message, Remediation) from FFU.Preflight.

## Standard Stack

### Core Technologies
| Library/Technology | Version | Purpose | Why Standard |
|-------------------|---------|---------|--------------|
| WPF (Windows Presentation Foundation) | .NET Framework 4.8 / .NET 7+ | Desktop UI framework | Native Windows UI framework, already used throughout BuildFFUVM_UI.ps1 |
| PowerShell | 7.0+ | Scripting engine | Project requirement, UI host language |
| FFU.Preflight | 1.6.0 | Pre-flight validation | Existing module with 16+ checks, structured results |
| FFU.Messaging | 1.0.0 | Thread-safe UI updates | ConcurrentQueue-based messaging, ~20x faster than file polling |

### Supporting Components
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Expander control | WPF built-in | Collapsible category headers | Already styled in BuildFFUVM_UI.xaml (MinimalExpanderNoHighlightStyle) |
| ItemsControl | WPF built-in | Data-bound lists | For check display within categories |
| DispatcherTimer | WPF built-in | UI polling | Already used at 50ms interval for log polling |
| ProgressBar | WPF built-in | Visual progress | Already used in UI (progressBar control) |
| TextBlock | WPF built-in | Status text | Already used throughout UI |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ItemsControl | TreeView | TreeView adds hierarchical complexity we don't need (flat category → checks) |
| Expander | Custom ToggleButton | Expander provides built-in expand/collapse with less code |
| FFU.Messaging | File polling | File polling is 20x slower, FFU.Messaging already integrated |
| ConcurrentQueue | Lock-based queue | ConcurrentQueue is lock-free, better performance |

**Installation:**
No new dependencies required. All components are built-in to .NET/WPF or already installed modules.

## Architecture Patterns

### Recommended Project Structure
```
FFUDevelopment/
├── BuildFFUVM_UI.xaml              # XAML markup (Home tab layout)
├── BuildFFUVM_UI.ps1               # UI host (event handlers, initialization)
├── FFUUI.Core/
│   ├── FFUUI.Core.Initialize.psm1  # NEW: Initialize-HomeTab function
│   └── FFUUI.Core.Events.psm1      # NEW: Register-HomeTabEvents function
├── Modules/
│   ├── FFU.Preflight/              # Existing: validation functions
│   └── FFU.Messaging/              # Existing: background communication
```

### Pattern 1: Background Check Execution with Real-Time Updates
**What:** Run FFU.Preflight checks in background, send results to UI via FFU.Messaging
**When to use:** All dashboard check execution (initial load, manual refresh)
**Example:**
```powershell
# Source: FFU.Messaging module documentation + existing BuildFFUVM_UI.ps1 patterns

# In UI initialization (BuildFFUVM_UI.ps1)
$script:uiState.Data.dashboardMessagingContext = New-FFUMessagingContext

# Launch background checks
$dashboardJob = Start-ThreadJob -ScriptBlock {
    param($messagingContext, $features, $ffuDevPath)

    Import-Module FFU.Preflight -Force
    Import-Module FFU.Messaging -Force

    # Send progress update
    Write-FFUProgress -Context $messagingContext -Activity "Pre-flight Checks" `
        -PercentComplete 0 -CurrentOperation "Starting validation"

    # Run Invoke-FFUPreflight (returns structured result)
    $result = Invoke-FFUPreflight -Features $features `
                                   -FFUDevelopmentPath $ffuDevPath `
                                   -ErrorAction Stop

    # Send individual check results to UI
    foreach ($tier in @('Tier1Results', 'Tier2Results', 'Tier3Results')) {
        foreach ($checkName in $result.$tier.Keys) {
            $checkResult = $result.$tier[$checkName]

            Write-FFUMessage -Context $messagingContext `
                -Message "CHECK_RESULT|$checkName|$($checkResult.Status)|$($checkResult.Severity)|$($checkResult.Message)" `
                -Level Info
        }
    }

    # Send completion
    Write-FFUProgress -Context $messagingContext -Activity "Pre-flight Checks" `
        -PercentComplete 100 -CurrentOperation "Complete"

} -ArgumentList $script:uiState.Data.dashboardMessagingContext, $features, $FFUDevelopmentPath

# Poll for messages in DispatcherTimer (50ms interval)
$pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$pollTimer.Add_Tick({
    $msg = $null
    while ($script:uiState.Data.dashboardMessagingContext.MessageQueue.TryDequeue([ref]$msg)) {
        if ($msg.Message -match '^CHECK_RESULT\|(.+)\|(.+)\|(.+)\|(.+)$') {
            $checkName = $Matches[1]
            $status = $Matches[2]
            $severity = $Matches[3]
            $message = $Matches[4]

            # Update UI control for this check
            Update-DashboardCheckUI -CheckName $checkName -Status $status `
                -Severity $severity -Message $message
        }
    }
})
$pollTimer.Start()
```

### Pattern 2: Category Grouping with Expander Controls
**What:** Use Expander controls for collapsible category groups (System, Hypervisor, Build Tools, Network, Optimization)
**When to use:** Dashboard layout structure
**Example:**
```xml
<!-- Source: Existing BuildFFUVM_UI.xaml Expander pattern (line 289) -->
<!-- Home tab content in BuildFFUVM_UI.xaml -->
<StackPanel x:Name="stackDashboardContainer" Margin="10">
    <!-- Summary Status Bar -->
    <Border x:Name="borderSummaryStatus" BorderBrush="Gray" BorderThickness="1"
            Background="LightGray" Padding="10" Margin="0,0,0,10">
        <TextBlock x:Name="txtSummaryStatus" Text="Checking..." FontSize="16" FontWeight="Bold"/>
    </Border>

    <!-- Progress Indicator -->
    <StackPanel x:Name="pnlProgress" Visibility="Collapsed" Margin="0,0,0,10">
        <ProgressBar x:Name="progressDashboard" IsIndeterminate="True" Height="20"/>
        <TextBlock x:Name="txtProgressStatus" Text="" Margin="0,5,0,0"/>
    </StackPanel>

    <!-- Refresh Button -->
    <Button x:Name="btnRefreshChecks" Content="Refresh" Width="100"
            HorizontalAlignment="Left" Margin="0,0,0,10"/>

    <!-- Category: System -->
    <Expander x:Name="expSystem" Style="{StaticResource MinimalExpanderNoHighlightStyle}"
              IsExpanded="True" Margin="0,5">
        <Expander.Header>
            <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="txtSystemIcon" Text="●" Margin="0,0,5,0" FontSize="16"/>
                <TextBlock Text="System" FontWeight="Bold" Margin="0,0,10,0"/>
                <TextBlock x:Name="txtSystemSummary" Text="(checking...)" Foreground="Gray"/>
            </StackPanel>
        </Expander.Header>
        <ItemsControl x:Name="itemsSystemChecks" Margin="20,5">
            <!-- Individual checks populated dynamically -->
        </ItemsControl>
    </Expander>

    <!-- Repeat for other categories: Hypervisor, Build Tools, Network, Optimization -->
</StackPanel>
```

### Pattern 3: Dynamic Check Item Creation
**What:** Programmatically create check items in PowerShell based on validation results
**When to use:** Populating category ItemsControls with check results
**Example:**
```powershell
# Source: Existing FFUUI.Core.Initialize.psm1 pattern for dynamic UI elements

function Update-DashboardCheckUI {
    param(
        [string]$CheckName,
        [string]$Status,      # Passed, Failed, Warning, Skipped
        [string]$Severity,    # Critical, Warning, Info
        [string]$Message,
        [string]$Remediation = ''
    )

    # Determine category (System, Hypervisor, BuildTools, Network, Optimization)
    $category = Get-CheckCategory -CheckName $CheckName
    $itemsControl = $script:uiState.Controls."items${category}Checks"

    # Create StackPanel for check item
    $checkPanel = New-Object System.Windows.Controls.StackPanel
    $checkPanel.Orientation = 'Horizontal'
    $checkPanel.Margin = '0,2'

    # Status icon (colored circle)
    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.FontSize = 16
    $icon.Margin = '0,0,5,0'
    switch ($Status) {
        'Passed' {
            $icon.Text = '●'  # Unicode filled circle
            $icon.Foreground = 'Green'
        }
        'Failed' {
            $icon.Text = '●'
            $icon.Foreground = if ($Severity -eq 'Critical') { 'Red' } else { 'Orange' }
        }
        'Warning' {
            $icon.Text = '▲'  # Unicode triangle
            $icon.Foreground = 'Gold'
        }
        'Skipped' {
            $icon.Text = '○'  # Unicode empty circle
            $icon.Foreground = 'Gray'
        }
    }
    $checkPanel.Children.Add($icon)

    # Check name
    $nameText = New-Object System.Windows.Controls.TextBlock
    $nameText.Text = $CheckName
    $nameText.Margin = '0,0,5,0'
    $checkPanel.Children.Add($nameText)

    # Status message (collapsed by default, expand on click if failed)
    if ($Status -eq 'Failed' -and $Severity -eq 'Critical') {
        # Auto-expand critical failures
        $detailExpander = New-Object System.Windows.Controls.Expander
        $detailExpander.Header = $Message
        $detailExpander.IsExpanded = $true
        $detailExpander.Margin = '20,5,0,5'

        if ($Remediation) {
            $remedText = New-Object System.Windows.Controls.TextBlock
            $remedText.Text = $Remediation
            $remedText.TextWrapping = 'Wrap'
            $remedText.FontFamily = 'Consolas'
            $remedText.Background = '#FFF9F9'
            $remedText.Padding = '5'
            $detailExpander.Content = $remedText
        }

        $checkPanel.Children.Add($detailExpander)
    }

    # Add to ItemsControl
    $itemsControl.Items.Add($checkPanel)
}
```

### Pattern 4: Build Button Gating
**What:** Disable Build button when critical failures exist, show warning dialog for non-critical warnings
**When to use:** After dashboard check completion
**Example:**
```powershell
# Source: Existing BuildFFUVM_UI.ps1 validation patterns

function Update-BuildButtonState {
    param(
        [int]$CriticalCount,
        [int]$WarningCount
    )

    $btnRun = $script:uiState.Controls.btnRun

    if ($CriticalCount -gt 0) {
        # Disable Build button on critical failures
        $btnRun.IsEnabled = $false
        $btnRun.ToolTip = "$CriticalCount critical issue(s) must be resolved before building"
    }
    elseif ($WarningCount -gt 0) {
        # Enable with warning tooltip
        $btnRun.IsEnabled = $true
        $btnRun.ToolTip = "$WarningCount warning(s) detected. Build will show confirmation dialog."

        # Add event handler for warning confirmation
        # (Pattern: existing btnRun.Add_Click handler in BuildFFUVM_UI.ps1)
    }
    else {
        # Enable normally
        $btnRun.IsEnabled = $true
        $btnRun.ToolTip = "Start FFU build"
    }
}
```

### Anti-Patterns to Avoid
- **Blocking UI thread for checks:** Never run Invoke-FFUPreflight on UI thread (30+ seconds blocks window). Always use Start-ThreadJob.
- **File polling for status:** Don't poll log files for check updates. Use FFU.Messaging ConcurrentQueue (20x faster, real-time).
- **Hardcoded check categories:** Don't hardcode category mappings. Derive from FFU.Preflight tier structure (Tier1 = System/Hypervisor, Tier2 = BuildTools/Network, Tier3 = Optimization).
- **Creating custom WPF controls:** Don't create custom UserControls for status display. Use built-in Expander, ItemsControl, TextBlock with dynamic creation.
- **Ignoring FFU.Preflight structure:** Don't parse check results manually. Use the structured result object (Tier1Results, Tier2Results, etc.) from Invoke-FFUPreflight.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thread-safe UI updates | Custom locking or event system | FFU.Messaging module | Already implemented with ConcurrentQueue, integrated into UI, proven in production |
| Validation check logic | New validation functions | FFU.Preflight module | 16+ functions covering all requirements, structured results, remediation guidance |
| Progress indication | Custom progress tracking | Existing ProgressBar + FFU.Messaging progress messages | Already styled in XAML, FFU.Messaging has built-in progress support |
| Collapsible sections | Custom toggle controls | WPF Expander with MinimalExpanderNoHighlightStyle | Already styled in BuildFFUVM_UI.xaml, consistent with existing UI |
| Background job execution | Custom threading | Start-ThreadJob with FFU.Messaging | Credential inheritance, error handling, already used for builds |

**Key insight:** This phase is 90% wiring and layout, not new framework code. Every major component (validation logic, messaging infrastructure, WPF controls, background execution pattern) already exists and is battle-tested. The work is assembling these pieces into the Home tab, not building new infrastructure.

## Common Pitfalls

### Pitfall 1: Running Checks on UI Thread
**What goes wrong:** Invoke-FFUPreflight takes 30+ seconds (WIMMount validation, ADK checks, network tests). Running on UI thread freezes the window.
**Why it happens:** Temptation to call Invoke-FFUPreflight directly in Initialize-HomeTab without Start-ThreadJob.
**How to avoid:** Always use Start-ThreadJob for check execution. Use FFU.Messaging to send results back to UI.
**Warning signs:** Window becomes unresponsive during "Checking..." phase, click events don't register.

### Pitfall 2: Check Category Mapping Inconsistency
**What goes wrong:** Checks appear in wrong categories or are duplicated because category assignment logic doesn't match FFU.Preflight tier structure.
**Why it happens:** FFU.Preflight has 4 tiers (Tier1=Critical, Tier2=FeatureDependent, Tier3=Recommended, Tier4=Cleanup). Dashboard has 5 categories (System, Hypervisor, BuildTools, Network, Optimization). Mapping is not 1:1.
**How to avoid:** Create explicit mapping function:
```powershell
function Get-CheckCategory {
    param([string]$CheckName)

    # Map FFU.Preflight check names to dashboard categories
    $categoryMap = @{
        'Administrator' = 'System'
        'PowerShellVersion' = 'System'
        'HyperV' = 'Hypervisor'
        'VmxToolkit' = 'Hypervisor'
        'VMwareDrivers' = 'Hypervisor'
        'ADK' = 'BuildTools'
        'WimMount' = 'BuildTools'
        'DiskSpace' = 'BuildTools'
        'Network' = 'Network'
        'AntivirusExclusions' = 'Optimization'
        # ... etc
    }

    return $categoryMap[$CheckName]
}
```
**Warning signs:** Checks missing from dashboard, checks appearing under multiple categories, "Skipped" checks appearing in wrong sections.

### Pitfall 3: Auto-Refresh on Tab Switch
**What goes wrong:** Dashboard re-runs all checks every time user switches away and back to Home tab, causing unnecessary 30+ second delays.
**Why it happens:** Putting check execution in TabItem.GotFocus event without checking if checks already ran.
**How to avoid:** Run checks once on application launch (in Initialize-HomeTab) and cache results. Manual refresh via button only.
```powershell
# In Initialize-HomeTab
if ($null -eq $script:uiState.Data.dashboardLastCheckTime) {
    # First load, run checks
    Start-DashboardChecks
    $script:uiState.Data.dashboardLastCheckTime = [DateTime]::Now
}

# Refresh button click handler
$btnRefreshChecks.Add_Click({
    Start-DashboardChecks
    $script:uiState.Data.dashboardLastCheckTime = [DateTime]::Now
})
```
**Warning signs:** Users report "Home tab is slow", checks run multiple times in single session, DispatcherTimer keeps running after tab switch.

### Pitfall 4: Remediation Text Rendering Issues
**What goes wrong:** Remediation guidance (from FFU.Preflight) contains formatted text with sections (=== ISSUE ===, === FIX ===) that don't render well in TextBlock, appearing as wall of text.
**Why it happens:** FFU.Preflight remediation strings use plain text formatting with line breaks, but TextBlock doesn't preserve formatting without TextWrapping and FontFamily settings.
**How to avoid:** Use TextBlock with proper formatting:
```powershell
$remedText = New-Object System.Windows.Controls.TextBlock
$remedText.Text = $checkResult.Remediation
$remedText.TextWrapping = 'Wrap'
$remedText.FontFamily = 'Consolas'  # Monospace preserves ASCII art
$remedText.Background = '#FFF9F9'   # Light background for contrast
$remedText.Padding = '5'
```
**Warning signs:** Remediation text runs off screen horizontally, section headers (===) not aligned, commands hard to read.

### Pitfall 5: Build Button State Inconsistency
**What goes wrong:** Build button state (enabled/disabled) doesn't match dashboard status, or gets out of sync after refresh.
**Why it happens:** Not updating button state after every check run, or forgetting to update when user resolves issues externally (e.g., installs ADK) and refreshes.
**How to avoid:** Always call Update-BuildButtonState at the end of every check run (initial load, manual refresh).
```powershell
# At end of dashboard job
$criticalCount = ($result.Tier1Results.Values + $result.Tier2Results.Values |
                  Where-Object { $_.Status -eq 'Failed' -and $_.Severity -eq 'Critical' }).Count

$warningCount = ($result.Tier1Results.Values + $result.Tier2Results.Values + $result.Tier3Results.Values |
                 Where-Object { $_.Status -in @('Failed', 'Warning') -and $_.Severity -eq 'Warning' }).Count

Write-FFUMessage -Context $messagingContext -Message "UPDATE_BUILD_BUTTON|$criticalCount|$warningCount" -Level Info
```
**Warning signs:** Build button grayed out after user fixes issue and refreshes, Build button enabled despite critical failures shown in dashboard.

## Code Examples

Verified patterns from official sources:

### Running FFU.Preflight in Background
```powershell
# Source: FFU.Preflight module + FFU.Messaging pattern from BuildFFUVM_UI.ps1

# In Initialize-HomeTab function (FFUUI.Core.Initialize.psm1)
function Start-DashboardChecks {
    param([hashtable]$State)

    # Create messaging context
    if ($null -eq $State.Data.dashboardMessagingContext) {
        $State.Data.dashboardMessagingContext = New-FFUMessagingContext
    }

    # Get features from UI controls
    $features = @{
        CreateVM = $State.Controls.chkCreateVM.IsChecked
        CreateCaptureMedia = $State.Controls.chkCreateCaptureMedia.IsChecked
        CreateDeploymentMedia = $State.Controls.chkCreateDeploymentMedia.IsChecked
        InstallApps = $State.Controls.chkInstallApps.IsChecked
        UpdateLatestCU = $State.Controls.chkUpdateLatestCU.IsChecked
        DownloadDrivers = $State.Controls.chkDownloadDrivers.IsChecked
    }

    # Launch background job
    $dashboardJob = Start-ThreadJob -ScriptBlock {
        param($context, $features, $ffuPath, $configPath)

        Import-Module FFU.Preflight -Force
        Import-Module FFU.Messaging -Force

        try {
            # Run validation
            $result = Invoke-FFUPreflight -Features $features `
                                          -FFUDevelopmentPath $ffuPath `
                                          -ConfigFile $configPath `
                                          -ErrorAction Stop

            # Send results to UI
            Write-FFUMessage -Context $context -Message "CHECKS_STARTED" -Level Info

            $checkNum = 0
            $totalChecks = ($result.Tier1Results.Count + $result.Tier2Results.Count +
                           $result.Tier3Results.Count)

            foreach ($tier in @('Tier1Results', 'Tier2Results', 'Tier3Results')) {
                foreach ($checkName in $result.$tier.Keys) {
                    $checkNum++
                    $check = $result.$tier[$checkName]

                    # Progress update
                    Write-FFUProgress -Context $context -Activity "Pre-flight Checks" `
                        -PercentComplete ([int](($checkNum / $totalChecks) * 100)) `
                        -CurrentOperation "Check $checkNum of ${totalChecks}: $checkName"

                    # Check result
                    $resultMsg = "CHECK|$checkName|$($check.Status)|$($check.Severity)|" +
                                "$($check.Message)|$($check.Remediation)"
                    Write-FFUMessage -Context $context -Message $resultMsg -Level Info
                }
            }

            # Summary
            Write-FFUMessage -Context $context -Message "CHECKS_COMPLETE|$($result.CriticalCount)|$($result.WarningCount)" -Level Info
        }
        catch {
            Write-FFUError -Context $context -Message "Dashboard checks failed: $_"
        }

    } -ArgumentList $State.Data.dashboardMessagingContext, $features,
                      $State.FFUDevelopmentPath, $State.Data.lastConfigFilePath

    $State.Data.currentDashboardJob = $dashboardJob

    # Show progress UI
    $State.Controls.pnlProgress.Visibility = 'Visible'
    $State.Controls.btnRefreshChecks.IsEnabled = $false
}
```

### Polling for Dashboard Messages
```powershell
# Source: Existing BuildFFUVM_UI.ps1 polling pattern (lines 181-204)

# In Initialize-HomeTab
$pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$pollTimer.Add_Tick({
    if ($null -eq $script:uiState.Data.dashboardMessagingContext) { return }

    $msg = $null
    while ($script:uiState.Data.dashboardMessagingContext.MessageQueue.TryDequeue([ref]$msg)) {
        # Handle different message types
        if ($msg.Message -eq 'CHECKS_STARTED') {
            # Clear previous results
            foreach ($category in @('System', 'Hypervisor', 'BuildTools', 'Network', 'Optimization')) {
                $itemsControl = $script:uiState.Controls."items${category}Checks"
                $itemsControl.Items.Clear()
            }
        }
        elseif ($msg.Message -match '^CHECK\|(.+)\|(.+)\|(.+)\|(.+)\|(.*)$') {
            $checkName = $Matches[1]
            $status = $Matches[2]
            $severity = $Matches[3]
            $message = $Matches[4]
            $remediation = $Matches[5]

            # Update UI
            Update-DashboardCheckUI -CheckName $checkName -Status $status `
                -Severity $severity -Message $message -Remediation $remediation
        }
        elseif ($msg.Message -match '^CHECKS_COMPLETE\|(\d+)\|(\d+)$') {
            $criticalCount = [int]$Matches[1]
            $warningCount = [int]$Matches[2]

            # Update summary
            Update-SummaryStatus -CriticalCount $criticalCount -WarningCount $warningCount

            # Update build button
            Update-BuildButtonState -CriticalCount $criticalCount -WarningCount $warningCount

            # Hide progress
            $script:uiState.Controls.pnlProgress.Visibility = 'Collapsed'
            $script:uiState.Controls.btnRefreshChecks.IsEnabled = $true
        }
        elseif ($msg.Level -eq [FFUMessageLevel]::Progress) {
            # Update progress bar
            $script:uiState.Controls.progressDashboard.Value = $msg.Data.PercentComplete
            $script:uiState.Controls.txtProgressStatus.Text = $msg.Data.CurrentOperation
        }
    }
})
$pollTimer.Start()

$script:uiState.Data.dashboardPollTimer = $pollTimer
```

### Category Summary Updates
```powershell
# Source: Pattern derived from FFU.Preflight result structure

function Update-CategorySummary {
    param(
        [string]$Category,  # System, Hypervisor, BuildTools, Network, Optimization
        [int]$TotalChecks,
        [int]$PassedChecks,
        [int]$FailedChecks,
        [int]$WarningChecks
    )

    $iconText = $script:uiState.Controls."txt${Category}Icon"
    $summaryText = $script:uiState.Controls."txt${Category}Summary"

    if ($FailedChecks -gt 0) {
        # Red circle for failures
        $iconText.Text = '●'
        $iconText.Foreground = 'Red'
        $summaryText.Text = "($PassedChecks/$TotalChecks — $FailedChecks failed)"
        $summaryText.Foreground = 'Red'
    }
    elseif ($WarningChecks -gt 0) {
        # Yellow triangle for warnings
        $iconText.Text = '▲'
        $iconText.Foreground = 'Gold'
        $summaryText.Text = "($PassedChecks/$TotalChecks — $WarningChecks warnings)"
        $summaryText.Foreground = 'DarkOrange'
    }
    else {
        # Green checkmark for all passed
        $iconText.Text = '✓'
        $iconText.Foreground = 'Green'
        $summaryText.Text = "($PassedChecks/$TotalChecks)"
        $summaryText.Foreground = 'Green'
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| File polling for log updates | ConcurrentQueue via FFU.Messaging | v1.0.0 (FFU.Messaging) | 20x faster UI updates (50ms vs 1000ms), lock-free thread safety |
| Manual service validation | Structured pre-flight with FFU.Preflight | v1.0.0 (FFU.Preflight) | Comprehensive checks with remediation guidance, tiered validation |
| Ad-hoc error display | Standardized check results (Status, Severity, Message, Remediation) | v1.0.0 (FFU.Preflight) | Consistent error presentation, actionable guidance |
| Placeholder Home tab | Live dashboard (this phase) | v1.7.0 (Phase 46) | Real-time validation visibility, build gating |

**Deprecated/outdated:**
- File-based log polling: Replaced by FFU.Messaging ConcurrentQueue (20x faster)
- Individual validation functions: Replaced by Invoke-FFUPreflight orchestrator (centralized, tiered)

## Open Questions

1. **Category Sorting Behavior**
   - What we know: User wants "severity-first ordering: categories with failures sort to top, warnings next, then passing. Dynamically reorders after each run"
   - What's unclear: Should reordering animate/slide, or instant update? Should user-expanded categories stay expanded when reordered?
   - Recommendation: Instant reorder (no animation), preserve expanded state. Animation adds complexity without UX benefit for infrequent operation (refresh button only).

2. **Refresh Button During Active Build**
   - What we know: User specified "Refresh button disabled during active builds"
   - What's unclear: Should dashboard continue showing stale results from pre-build check, or show "Build in progress" message?
   - Recommendation: Leave results visible with banner "Results from pre-build check. Refresh disabled during build." Avoids confusion about system state.

3. **Initial Check Run Timing**
   - What we know: "Dashboard automatically runs all checks on application launch in background without blocking UI"
   - What's unclear: Should checks run when Home tab is not visible (user starts on different tab), or defer until first Home tab view?
   - Recommendation: Always run on app launch regardless of active tab. Pre-populates results before user views Home, avoids delay on first tab switch.

## Sources

### Primary (HIGH confidence)
- FFU.Preflight module v1.6.0 - Reviewed all 16+ validation functions, Invoke-FFUPreflight orchestrator, result structure
- FFU.Messaging module v1.0.0 - Reviewed ConcurrentQueue pattern, New-FFUMessagingContext, Write-FFU* functions
- BuildFFUVM_UI.ps1 - Reviewed existing DispatcherTimer polling pattern (lines 181-204), Start-ThreadJob usage, UI state management
- BuildFFUVM_UI.xaml - Reviewed Expander control styling (MinimalExpanderNoHighlightStyle), existing ProgressBar, ItemsControl patterns
- FFUUI.Core.Initialize.psm1 - Reviewed Initialize-* function patterns, dynamic UI element creation

### Secondary (MEDIUM confidence)
- WPF documentation (Microsoft Learn) - Expander, ItemsControl, DispatcherTimer usage patterns verified against existing code

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components already in codebase and battle-tested
- Architecture: HIGH - Patterns match existing BuildFFUVM_UI.ps1 implementation exactly
- Pitfalls: HIGH - Derived from actual FFU.Preflight/FFU.Messaging structure and common WPF issues

**Research date:** 2026-02-06
**Valid until:** 2026-03-06 (30 days - stable codebase, no fast-moving external dependencies)
