# Stack Research: Readiness Dashboard & Hypervisor-Aware Preflight

**Domain:** PowerShell WPF Application - System Validation Dashboard
**Researched:** 2026-02-05
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **WPF ItemsControl + GroupStyle** | .NET 9.0 (via PowerShell 7+) | Grouped status display | Native WPF grouping - no 3rd party dependencies. Provides category headers, collapsible sections, and data-template flexibility. Official Microsoft pattern for categorized dashboards. |
| **DispatcherTimer** | Built-in WPF | Async check polling | Already proven in FFUBuilder (50ms polling). Non-blocking UI updates. Executes on UI thread = no cross-thread issues. |
| **System.Collections.Concurrent.ConcurrentQueue** | .NET 9.0 | Thread-safe check results | Already used in FFU.Messaging. Lock-free queue for async check results from runspace to UI. 20x faster than file polling. |
| **PowerShell Runspaces** | PowerShell 7.5+ | Async validation execution | Already used in FFUBuilder for background jobs. Better than ThreadJob for this use case - no credential inheritance needed, full cmdlet availability, clean cancellation. |
| **ObservableCollection\<PSObject\>** | .NET 9.0 | Data binding for status items | WPF standard for dynamic UI updates. Auto-notifies ItemsControl when checks complete. Native PowerShell support via `New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]`. |

### Supporting Patterns

| Pattern | Purpose | Implementation Notes |
|---------|---------|---------------------|
| **CollectionViewSource with GroupDescriptions** | Category grouping | Bind ObservableCollection → CollectionViewSource with PropertyGroupDescription on "Category" property. ItemsControl displays via GroupStyle.HeaderTemplate. |
| **DataTemplate per check result** | Visual status indicators | Define DataTemplate in Window.Resources with status icons (✓, ⚠, ✗), color-coded backgrounds, and expand/collapse for remediation guidance. |
| **Runspace Pool (size=4)** | Parallel async checks | Create 4-runspace pool, queue validation functions, poll via BeginInvoke/EndInvoke. Results enqueued to ConcurrentQueue. |
| **Dispatcher.Invoke for UI updates** | Cross-thread safety | DispatcherTimer (UI thread) dequeues results, updates ObservableCollection via Dispatcher.Invoke to avoid cross-thread exceptions. |
| **FFU.Preflight integration** | Reuse existing checks | All 12 existing Test-FFU* functions return standardized FFUCheckResult objects. No rewrites - just call from runspace and enqueue results. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Visual Studio Code** | XAML editing | Existing FFUBuilder toolchain. Use XML validation for XAML syntax. |
| **PowerShell ISE / VS Code** | Async pattern debugging | Test runspace lifecycle (New-RunspacePool, Dispose) and queue operations. |
| **Pester 5.x** | UI state testing | Test dashboard population, refresh behavior, hypervisor-conditional logic. |

## Installation

```powershell
# No additional dependencies required
# All technologies are built into PowerShell 7.5+ and .NET 9.0

# Verify prerequisites (already present in FFUBuilder environment)
$PSVersionTable.PSVersion.Major  # Should be 7+
Add-Type -AssemblyName PresentationFramework  # Should succeed
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **ItemsControl + GroupStyle** | 3rd-party WPF toolkit (MaterialDesign, ModernWPF) | NEVER. FFUBuilder is pure PowerShell with no NuGet packages. Adding dependencies increases maintenance burden and breaks "just run the script" model. |
| **Runspace Pool** | ThreadJob module | Only if credential inheritance is needed. For dashboard checks (no network auth), runspaces are cleaner - no module import in job, full cmdlet availability, explicit lifecycle control. |
| **DispatcherTimer (50ms)** | Reactive Extensions (Rx.NET) | NEVER. Rx.NET is C#-focused, poor PowerShell interop, massive overkill for simple polling. DispatcherTimer is proven in FFUBuilder UI. |
| **ConcurrentQueue** | Synchronized Hashtable | When you need keyed access. For ordered status results, ConcurrentQueue is correct - FIFO ordering, zero contention, simpler dequeue loop. |
| **ObservableCollection** | Manual INotifyPropertyChanged | When you need custom change notifications. For dashboard, ObservableCollection auto-wires to ItemsControl updates - less code, fewer bugs. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **XAML x:Bind** | PowerShell WPF uses XamlReader, not compiled XAML. x:Bind requires C# compilation. | Standard `{Binding}` syntax with DataContext. |
| **WPF DataGrid for status display** | Overkill for read-only status. DataGrid has sorting/editing features you don't need. Heavy rendering. | ItemsControl with custom DataTemplate. Lighter, cleaner, easier to style. |
| **Start-Job for async checks** | Creates new PowerShell process per job. Slow startup (~500ms), heavy memory. Module imports required. | Runspace Pool with 4 reusable threads. 10x faster. |
| **file-based polling for check results** | Already proven slow in FFUBuilder (1000ms refresh). Race conditions on file writes. | ConcurrentQueue (existing FFU.Messaging pattern). 20x faster, no file I/O. |
| **C# interop for UI logic** | FFUBuilder is pure PowerShell. Adding C# means compilation step, breaks script portability. | Pure PowerShell with .NET types (Add-Type -AssemblyName). |
| **BackgroundWorker** | Legacy .NET Framework pattern. Poor cancellation support. Hard to pass data back. | Runspace Pool with ConcurrentQueue. Modern, clean, testable. |

## Stack Patterns by Variant

### If Hyper-V selected (default):
- Enable all checks including `Test-FFUHyperV` (blocking)
- Category: "Hypervisor" with status "Required (Hyper-V selected)"
- Auto-remediation: Offer `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All` button
- Blocking: Critical failure prevents build start

### If VMware selected:
- Skip `Test-FFUHyperV` check entirely
- Category: "Hypervisor" with status "Not Required (VMware selected)"
- Run VMware-specific checks: VMrun.exe availability, VIX API installed
- Non-blocking: VMware issues warn but don't block (build script validates again at runtime)

### If Auto-detect selected:
- Run both Hyper-V and VMware detection in parallel
- First available hypervisor becomes active
- Display detection result: "Hyper-V detected and enabled" or "VMware Workstation Pro detected"
- Category shows which hypervisor was chosen

## Architecture Integration Points

### 1. Dashboard Data Flow

```
[Home Tab Load] → [Initialize-ReadinessDashboard]
    ↓
[Create ObservableCollection<CheckResult>]
    ↓
[Create RunspacePool (size=4)] → [Queue all Test-FFU* checks]
    ↓
[BeginInvoke each check] → [Runspaces execute in parallel]
    ↓
[Check completes] → [Enqueue result to ConcurrentQueue]
    ↓
[DispatcherTimer (50ms)] → [Dequeue result] → [Dispatcher.Invoke] → [Add to ObservableCollection]
    ↓
[ItemsControl auto-updates via data binding]
```

### 2. Hypervisor-Conditional Logic

```powershell
# In Initialize-ReadinessDashboard
$hypervisorType = $script:uiState.Controls.cmbHypervisorType.SelectedItem.Content

$checksToRun = @(
    @{ Name = 'Administrator'; Function = 'Test-FFUAdministrator'; Category = 'System'; Always = $true }
    @{ Name = 'PowerShell7'; Function = 'Test-FFUPowerShell7'; Category = 'System'; Always = $true }
    @{ Name = 'DiskSpace'; Function = 'Test-FFUDiskSpace'; Category = 'Storage'; Always = $true }
    @{ Name = 'ADK'; Function = 'Test-FFUADKInstalled'; Category = 'Prerequisites'; Always = $true }
    @{ Name = 'HyperV'; Function = 'Test-FFUHyperV'; Category = 'Hypervisor'; Condition = ($hypervisorType -eq 'Hyper-V') }
    @{ Name = 'VMware'; Function = 'Test-FFUVMware'; Category = 'Hypervisor'; Condition = ($hypervisorType -eq 'VMware Workstation Pro') }
    # ... more checks
)

# Filter checks based on conditions
$activeChecks = $checksToRun | Where-Object { $_.Always -or $_.Condition }
```

### 3. Auto-Remediation Pattern

```powershell
# Each FFUCheckResult includes Remediation property (already standardized in FFU.Preflight)
# Dashboard DataTemplate includes conditional remediation UI

# Example auto-remediable checks:
# - Hyper-V not installed → Enable-WindowsOptionalFeature (SAFE, user-initiated)
# - ADK not installed → Download + silent install (SAFE, long-running)
# - Disk space low → Open "Storage Settings" (SAFE, user action)
# - WimMount service stopped → Start-Service (SAFE, requires admin - already running as admin)

# Non-remediable checks (manual guidance only):
# - Not running as Administrator → Relaunch script
# - PowerShell version too old → Install PS7 from aka.ms/powershell
# - Network unreachable → Check firewall/proxy
```

### 4. Refresh Button Behavior

```powershell
# Clear existing results
$script:uiState.Data.checkResults.Clear()

# Re-queue all checks to runspace pool
foreach ($check in $activeChecks) {
    $ps = [PowerShell]::Create().AddScript({ ... })
    $ps.RunspacePool = $runspacePool
    $handle = $ps.BeginInvoke()
    # Store handle for polling
}

# DispatcherTimer continues polling for completion
```

## Version Compatibility

| Component | Minimum Version | Tested Version | Notes |
|-----------|-----------------|----------------|-------|
| PowerShell | 7.0 | 7.5 | FFUBuilder already requires 7.0+ (BuildFFUVM_UI.ps1 line 18) |
| .NET | .NET 6 | .NET 9 | Ships with PowerShell 7.5 |
| Windows | 10 1809+ | 11 24H2 | WPF requires Windows 10+. ItemsControl.GroupStyle stable since .NET 3.0. |
| FFU.Preflight | 1.0.0 | 1.0.0 | All 12 Test-FFU* functions return FFUCheckResult (standardized schema) |
| FFU.Messaging | 1.0.0 | 1.0.0 | ConcurrentQueue pattern proven at 50ms latency |

## Critical Implementation Notes

### 1. Runspace Module Import Pattern

**Problem:** Runspaces don't auto-import modules from parent session.

**Solution:**
```powershell
$initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initialSessionState.ImportPSModule(@(
    "$PSScriptRoot\Modules\FFU.Preflight\FFU.Preflight.psm1",
    "$PSScriptRoot\Modules\FFU.Core\FFU.Core.psm1",
    "$PSScriptRoot\Modules\FFU.ADK\FFU.ADK.psm1"
))
$runspacePool = [runspacefactory]::CreateRunspacePool(1, 4, $initialSessionState, $Host)
$runspacePool.Open()
```

### 2. UI Thread Marshaling

**Problem:** ObservableCollection updates from DispatcherTimer (UI thread) are safe. Direct updates from runspace throw `InvalidOperationException`.

**Solution:** DispatcherTimer already runs on UI thread. Just dequeue and add:
```powershell
# In DispatcherTimer.Tick handler
while ($script:uiState.Data.messagingContext.MessageQueue.TryDequeue([ref]$result)) {
    $script:uiState.Data.checkResults.Add($result)  # Safe - we're on UI thread
}
```

### 3. Cancellation Pattern

**Problem:** Runspaces don't have built-in cancellation.

**Solution:** Pass synchronized cancellation flag:
```powershell
# In runspace script
param($syncContext)

if ($syncContext.CancellationRequested) {
    return [PSCustomObject]@{ CheckName = 'Cancelled'; Status = 'Skipped' }
}
# ... perform check
```

### 4. Check Result Schema

**Already standardized in FFU.Preflight** (lines 26-101):
```powershell
[PSCustomObject]@{
    CheckName   = 'HyperV'
    Status      = 'Passed' | 'Failed' | 'Warning' | 'Skipped'
    Severity    = 'Critical' | 'Warning' | 'Info'
    Message     = 'Human-readable result'
    Details     = @{ ... }  # Structured data
    Remediation = 'Multi-line guidance'
    DurationMs  = 1500
}
```

**Dashboard binding:** Bind ItemsControl.ItemsSource to ObservableCollection. GroupStyle.HeaderTemplate binds to `Category` property (add to check queue metadata).

## XAML Structure for Dashboard

```xml
<!-- Home Tab - replace existing TextBlock -->
<TabItem Header="Home" Padding="20">
    <ScrollViewer VerticalScrollBarVisibility="Auto">
        <Grid Margin="10">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>  <!-- Header + Refresh button -->
                <RowDefinition Height="*"/>     <!-- Status dashboard -->
            </Grid.RowDefinitions>

            <!-- Header -->
            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                <TextBlock Text="System Readiness Dashboard" FontSize="20" VerticalAlignment="Center"/>
                <Button x:Name="btnRefreshChecks" Content="Refresh" Margin="20,0,0,0" Padding="10,5" ToolTip="Re-run all validation checks"/>
            </StackPanel>

            <!-- Grouped Status Display -->
            <ItemsControl x:Name="lstReadinessChecks" Grid.Row="1">
                <ItemsControl.ItemsSource>
                    <Binding Path="CheckResults"/>  <!-- Bound to ObservableCollection in $script:uiState.Data -->
                </ItemsControl.ItemsSource>

                <!-- Group by Category -->
                <ItemsControl.GroupStyle>
                    <GroupStyle>
                        <GroupStyle.HeaderTemplate>
                            <DataTemplate>
                                <Border Background="#E0E0E0" Padding="5" Margin="0,10,0,5" CornerRadius="3">
                                    <TextBlock Text="{Binding Name}" FontWeight="Bold" FontSize="14"/>
                                </Border>
                            </DataTemplate>
                        </GroupStyle.HeaderTemplate>
                    </GroupStyle>
                </ItemsControl.GroupStyle>

                <!-- Item Template (each check result) -->
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <Border BorderBrush="#CCCCCC" BorderThickness="1" Padding="10" Margin="5" CornerRadius="3">
                            <Border.Style>
                                <Style TargetType="Border">
                                    <Style.Triggers>
                                        <DataTrigger Binding="{Binding Status}" Value="Passed">
                                            <Setter Property="Background" Value="#E8F5E9"/>
                                        </DataTrigger>
                                        <DataTrigger Binding="{Binding Status}" Value="Failed">
                                            <Setter Property="Background" Value="#FFEBEE"/>
                                        </DataTrigger>
                                        <DataTrigger Binding="{Binding Status}" Value="Warning">
                                            <Setter Property="Background" Value="#FFF9C4"/>
                                        </DataTrigger>
                                    </Style.Triggers>
                                </Style>
                            </Border.Style>

                            <StackPanel>
                                <StackPanel Orientation="Horizontal">
                                    <!-- Status icon -->
                                    <TextBlock FontSize="16" Margin="0,0,10,0" VerticalAlignment="Center">
                                        <TextBlock.Style>
                                            <Style TargetType="TextBlock">
                                                <Style.Triggers>
                                                    <DataTrigger Binding="{Binding Status}" Value="Passed">
                                                        <Setter Property="Text" Value="✓"/>
                                                        <Setter Property="Foreground" Value="Green"/>
                                                    </DataTrigger>
                                                    <DataTrigger Binding="{Binding Status}" Value="Failed">
                                                        <Setter Property="Text" Value="✗"/>
                                                        <Setter Property="Foreground" Value="Red"/>
                                                    </DataTrigger>
                                                    <DataTrigger Binding="{Binding Status}" Value="Warning">
                                                        <Setter Property="Text" Value="⚠"/>
                                                        <Setter Property="Foreground" Value="Orange"/>
                                                    </DataTrigger>
                                                </Style.Triggers>
                                            </Style>
                                        </TextBlock.Style>
                                    </TextBlock>

                                    <!-- Check name and message -->
                                    <StackPanel>
                                        <TextBlock Text="{Binding CheckName}" FontWeight="Bold"/>
                                        <TextBlock Text="{Binding Message}" TextWrapping="Wrap"/>
                                    </StackPanel>
                                </StackPanel>

                                <!-- Expandable remediation (shown only for Failed/Warning) -->
                                <Expander Header="Remediation Steps" Margin="0,5,0,0">
                                    <Expander.Style>
                                        <Style TargetType="Expander">
                                            <Style.Triggers>
                                                <DataTrigger Binding="{Binding Status}" Value="Passed">
                                                    <Setter Property="Visibility" Value="Collapsed"/>
                                                </DataTrigger>
                                            </Style.Triggers>
                                        </Style>
                                    </Expander.Style>
                                    <TextBlock Text="{Binding Remediation}" TextWrapping="Wrap" FontFamily="Consolas" FontSize="11" Margin="10"/>
                                </Expander>
                            </StackPanel>
                        </Border>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </Grid>
    </ScrollViewer>
</TabItem>
```

## PowerShell Initialization Code

```powershell
# In Initialize-UIControls (FFUUI.Core)
function Initialize-ReadinessDashboard {
    param($State)

    # Create ObservableCollection for check results
    $State.Data.checkResults = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]

    # Set up CollectionViewSource with grouping
    $cvs = New-Object System.Windows.Data.CollectionViewSource
    $cvs.Source = $State.Data.checkResults
    $cvs.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription -ArgumentList 'Category'))

    # Bind to ItemsControl
    $State.Controls.lstReadinessChecks.DataContext = $cvs

    # Initialize runspace pool for async checks
    $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $initialState.ImportPSModule(@(
        "$($State.FFUDevelopmentPath)\Modules\FFU.Preflight\FFU.Preflight.psm1",
        "$($State.FFUDevelopmentPath)\Modules\FFU.Core\FFU.Core.psm1",
        "$($State.FFUDevelopmentPath)\Modules\FFU.ADK\FFU.ADK.psm1"
    ))
    $State.Data.checkRunspacePool = [runspacefactory]::CreateRunspacePool(1, 4, $initialState, $Host)
    $State.Data.checkRunspacePool.Open()

    # Start DispatcherTimer for result polling (reuse existing pattern from line 106)
    $State.Data.checkPollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $State.Data.checkPollTimer.Interval = [TimeSpan]::FromMilliseconds(50)
    $State.Data.checkPollTimer.Add_Tick({
        # Dequeue results from messaging context
        while ($script:uiState.Data.messagingContext.MessageQueue.TryDequeue([ref]$result)) {
            $script:uiState.Data.checkResults.Add($result)
        }

        # Check if all runspaces completed
        $allCompleted = $true
        foreach ($handle in $script:uiState.Data.checkHandles) {
            if (-not $handle.AsyncResult.IsCompleted) {
                $allCompleted = $false
                break
            }
        }

        if ($allCompleted) {
            $script:uiState.Data.checkPollTimer.Stop()
            # Clean up runspace pool
            foreach ($handle in $script:uiState.Data.checkHandles) {
                $handle.PowerShell.EndInvoke($handle.AsyncResult)
                $handle.PowerShell.Dispose()
            }
        }
    })

    # Auto-run checks on load
    Start-ReadinessChecks -State $State
}

function Start-ReadinessChecks {
    param($State)

    # Clear previous results
    $State.Data.checkResults.Clear()

    # Get hypervisor selection
    $hypervisorType = $State.Controls.cmbHypervisorType.SelectedItem.Content

    # Define checks with conditional execution
    $checksToRun = @(
        @{ Name = 'Administrator'; Function = 'Test-FFUAdministrator'; Category = 'System'; Always = $true }
        @{ Name = 'PowerShell7'; Function = 'Test-FFUPowerShell7'; Category = 'System'; Always = $true }
        @{ Name = 'DiskSpace'; Function = 'Test-FFUDiskSpace'; Category = 'Storage'; Always = $true; Params = @{ Path = $State.FFUDevelopmentPath; RequiredGB = 80 } }
        @{ Name = 'ADK'; Function = 'Test-FFUADKInstalled'; Category = 'Prerequisites'; Always = $true }
        @{ Name = 'WimMount'; Function = 'Test-FFUWimMount'; Category = 'Prerequisites'; Always = $true }
        @{ Name = 'HyperV'; Function = 'Test-FFUHyperV'; Category = 'Hypervisor'; Condition = ($hypervisorType -eq 'Hyper-V') }
        @{ Name = 'Network'; Function = 'Test-FFUNetwork'; Category = 'Network'; Always = $true }
        @{ Name = 'HostIP'; Function = 'Test-FFUHostIPAddress'; Category = 'Network'; Always = $true }
    )

    # Filter active checks
    $activeChecks = $checksToRun | Where-Object { $_.Always -or $_.Condition }

    # Queue checks to runspace pool
    $State.Data.checkHandles = @()

    foreach ($check in $activeChecks) {
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $State.Data.checkRunspacePool

        # Build script block
        $scriptBlock = {
            param($FunctionName, $Category, $Params, $SyncContext)

            if ($SyncContext.CancellationRequested) {
                return [PSCustomObject]@{ CheckName = $FunctionName; Status = 'Skipped'; Category = $Category }
            }

            # Call the validation function
            $result = & $FunctionName @Params

            # Add category for grouping
            $result | Add-Member -NotePropertyName 'Category' -NotePropertyValue $Category -Force

            # Enqueue result
            $SyncContext.MessageQueue.Enqueue($result)
        }

        [void]$ps.AddScript($scriptBlock)
        [void]$ps.AddArgument($check.Function)
        [void]$ps.AddArgument($check.Category)
        [void]$ps.AddArgument(($check.Params ?? @{}))
        [void]$ps.AddArgument($State.Data.messagingContext)

        $handle = $ps.BeginInvoke()

        $State.Data.checkHandles += [PSCustomObject]@{
            PowerShell  = $ps
            AsyncResult = $handle
        }
    }

    # Start polling timer
    $State.Data.checkPollTimer.Start()
}

# Register button handler
$State.Controls.btnRefreshChecks.Add_Click({
    Start-ReadinessChecks -State $script:uiState
})
```

## Sources

- [WPF ItemsControl GroupStyle - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.itemscontrol.groupstyle?view=windowsdesktop-9.0) — Official .NET documentation for category grouping
- [WPF Multithreading UI Dispatcher in MVVM: Complete Guide for 2026](https://copyprogramming.com/howto/wpf-multithreading-ui-dispatcher-in-mvvm) — Cross-thread UI update patterns
- [The DispatcherTimer - The complete WPF tutorial](https://wpf-tutorial.com/misc/dispatchertimer/) — Timer-based async polling patterns
- [Beginning Use of PowerShell Runspaces: Part 1 - Scripting Blog](https://devblogs.microsoft.com/scripting/beginning-use-of-powershell-runspaces-part-1/) — Official Microsoft runspace guide
- [Part V - Building Responsive PowerShell Apps with Progress bars](https://www.foxdeploy.com/blog/part-v-powershell-guis-responsive-apps-with-progress-bars.html) — Runspace pool + WPF integration
- [Creating a GUI App with PowerShell and WPF - Part 1 Runspaces](https://write-verbose.com/2023/03/21/PowerShellWPFPt1/) — Practical PowerShell + runspace patterns
- [Windows Autopatch: Auto-remediation with PowerShell scripts](https://techcommunity.microsoft.com/blog/windows-itpro-blog/windows-autopatch-auto-remediation-with-powershell-scripts/4228854) — Detection + remediation script patterns
- [Use Remediations to Detect and Fix Support Issues - Microsoft Intune](https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations) — Enterprise auto-remediation guidance
- [ListView grouping - The complete WPF tutorial](https://wpf-tutorial.com/listview-control/listview-grouping/) — CollectionViewSource grouping examples

---
*Stack research for: FFU Builder Readiness Dashboard*
*Researched: 2026-02-05*
