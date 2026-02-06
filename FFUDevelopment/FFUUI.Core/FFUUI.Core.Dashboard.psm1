<#
.SYNOPSIS
    Dashboard helper functions for the FFU Builder readiness dashboard.

.DESCRIPTION
    Provides functions to manage the pre-flight readiness dashboard on the Home tab.
    Handles check result display, category grouping, summary banner updates, and
    build button gating based on check severity.

    Functions:
    - Get-CheckCategory: Maps FFU.Preflight check names to dashboard categories
    - Update-DashboardCheckUI: Creates WPF elements for individual check results
    - Update-CategorySummary: Updates category header icons and summary text
    - Update-SummaryStatus: Updates the top-level readiness banner
    - Update-BuildButtonState: Enables/disables Build button based on check results
    - Clear-DashboardResults: Resets all dashboard UI to initial state
#>

# --------------------------------------------------------------------------
# SECTION: Category Mapping
# --------------------------------------------------------------------------

# Map of FFU.Preflight check names to dashboard categories
# Must cover every check name used in FFU.Preflight module
$script:CategoryMap = @{
    # System category - core system requirements
    'Administrator'        = 'System'
    'PowerShellVersion'    = 'System'
    'VMResources'          = 'System'
    'ScratchSpace'         = 'System'

    # Hypervisor category - virtualization platform checks
    'HyperV'               = 'Hypervisor'
    'VmxToolkit'           = 'Hypervisor'
    'VMwareDrivers'        = 'Hypervisor'
    'VMwareBridgeConfig'   = 'Hypervisor'
    'HyperVSwitchConflict' = 'Hypervisor'

    # BuildTools category - build infrastructure checks
    'ADK'                  = 'BuildTools'
    'WimMount'             = 'BuildTools'
    'DiskSpace'            = 'BuildTools'
    'DISMState'            = 'BuildTools'
    'DISMCleanup'          = 'BuildTools'
    'AppsISODiskSpace'     = 'BuildTools'
    'CaptureDiskSpace'     = 'BuildTools'

    # Network category - connectivity checks
    'Network'              = 'Network'
    'HostIPAddress'        = 'Network'

    # Optimization category - optional improvements
    'AntivirusExclusions'  = 'Optimization'
    'Configuration'        = 'Optimization'
}

# Map of check names to human-readable display names
$script:FriendlyNames = @{
    'Administrator'        = 'Administrator Privileges'
    'PowerShellVersion'    = 'PowerShell Version'
    'VMResources'          = 'VM Resources'
    'ScratchSpace'         = 'Scratch Space'
    'HyperV'               = 'Hyper-V'
    'VmxToolkit'           = 'VMX Toolkit'
    'VMwareDrivers'        = 'VMware Drivers'
    'VMwareBridgeConfig'   = 'VMware Bridge Configuration'
    'HyperVSwitchConflict' = 'Hyper-V Switch Conflict'
    'ADK'                  = 'Windows ADK'
    'WimMount'             = 'WIM Mount Service'
    'DiskSpace'            = 'Disk Space'
    'DISMState'            = 'DISM Service State'
    'DISMCleanup'          = 'DISM Cleanup'
    'AppsISODiskSpace'     = 'Apps ISO Disk Space'
    'CaptureDiskSpace'     = 'Capture Disk Space'
    'Network'              = 'Network Connectivity'
    'HostIPAddress'        = 'Host IP Address'
    'AntivirusExclusions'  = 'Antivirus Exclusions'
    'Configuration'        = 'Configuration File'
}

# List of all dashboard category names for iteration
$script:AllCategories = @('System', 'Hypervisor', 'BuildTools', 'Network', 'Optimization')

# --------------------------------------------------------------------------
# SECTION: Public Functions
# --------------------------------------------------------------------------

function Get-CheckCategory {
    <#
    .SYNOPSIS
        Maps an FFU.Preflight check name to a dashboard category.

    .DESCRIPTION
        Looks up the given check name in the category map and returns the
        corresponding dashboard category. Returns 'System' as default if
        the check name is not found in the map.

        Valid categories: System, Hypervisor, BuildTools, Network, Optimization.

    .PARAMETER CheckName
        The FFU.Preflight check name (e.g., 'Administrator', 'ADK', 'Network').

    .OUTPUTS
        [string] - The dashboard category name.

    .EXAMPLE
        Get-CheckCategory -CheckName 'Administrator'
        # Returns: 'System'

    .EXAMPLE
        Get-CheckCategory -CheckName 'ADK'
        # Returns: 'BuildTools'

    .EXAMPLE
        Get-CheckCategory -CheckName 'UnknownCheck'
        # Returns: 'System' (default)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$CheckName
    )

    if ($script:CategoryMap.ContainsKey($CheckName)) {
        return $script:CategoryMap[$CheckName]
    }

    return 'System'
}

function Update-DashboardCheckUI {
    <#
    .SYNOPSIS
        Creates WPF elements for a check result and adds them to the appropriate category panel.

    .DESCRIPTION
        Determines the check's category via Get-CheckCategory, then creates a StackPanel
        containing a status icon, check name, and brief message. For failed checks with
        Critical severity, an auto-expanded remediation Expander is added. For failed
        checks with Warning severity, a collapsed remediation Expander is added.

        The created elements are added to the corresponding category panel
        ($State.Controls."pnl${Category}Checks").

    .PARAMETER State
        The UI state object containing Controls and Data hashtables.

    .PARAMETER CheckName
        The FFU.Preflight check name.

    .PARAMETER Status
        The check result status: Passed, Failed, Warning, Skipped, or Running.

    .PARAMETER Severity
        The check severity: Critical, Warning, or Info.

    .PARAMETER Message
        A brief message describing the check result.

    .PARAMETER Remediation
        Optional remediation steps text for failed checks.

    .OUTPUTS
        [void]

    .EXAMPLE
        Update-DashboardCheckUI -State $State -CheckName 'Administrator' -Status 'Passed' `
            -Severity 'Critical' -Message 'Running with Administrator privileges'

    .EXAMPLE
        Update-DashboardCheckUI -State $State -CheckName 'ADK' -Status 'Failed' `
            -Severity 'Critical' -Message 'Windows ADK not installed' `
            -Remediation 'Download and install Windows ADK from Microsoft'
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State,

        [Parameter(Mandatory)]
        [string]$CheckName,

        [Parameter(Mandatory)]
        [ValidateSet('Passed', 'Failed', 'Warning', 'Skipped', 'Running')]
        [string]$Status,

        [Parameter()]
        [ValidateSet('Critical', 'Warning', 'Info')]
        [string]$Severity = 'Warning',

        [Parameter()]
        [string]$Message = '',

        [Parameter()]
        [string]$Remediation = ''
    )

    $category = Get-CheckCategory -CheckName $CheckName
    $panelName = "pnl${category}Checks"
    $panel = $State.Controls.$panelName

    if ($null -eq $panel) {
        return
    }

    # Determine status icon and color
    $iconText = switch ($Status) {
        'Passed'  { [char]0x2713 }  # checkmark
        'Failed'  {
            if ($Severity -eq 'Critical') { [char]0x2717 }  # X mark
            else { [char]0x26A0 }  # warning triangle
        }
        'Warning' { [char]0x26A0 }  # warning triangle
        'Skipped' { [char]0x25CB }  # empty circle
        'Running' { [char]0x25CC }  # dotted circle
    }

    $iconColor = switch ($Status) {
        'Passed'  { '#2E7D32' }
        'Failed'  {
            if ($Severity -eq 'Critical') { '#C62828' }
            else { '#F57F17' }
        }
        'Warning' { '#F57F17' }
        'Skipped' { 'Gray' }
        'Running' { '#1565C0' }
    }

    # Get friendly display name
    $displayName = if ($script:FriendlyNames.ContainsKey($CheckName)) {
        $script:FriendlyNames[$CheckName]
    }
    else {
        $CheckName
    }

    # Create outer StackPanel (vertical) for check line + optional remediation
    $outerPanel = [System.Windows.Controls.StackPanel]::new()
    $outerPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical

    # Create inner StackPanel (horizontal) for status icon + check name + message
    $innerPanel = [System.Windows.Controls.StackPanel]::new()
    $innerPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $innerPanel.Margin = [System.Windows.Thickness]::new(0, 3, 0, 0)

    # Status icon TextBlock
    $iconBlock = [System.Windows.Controls.TextBlock]::new()
    $iconBlock.Text = [string]$iconText
    $iconBlock.FontSize = 14
    $iconBlock.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $iconBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($iconColor)
    [void]$innerPanel.Children.Add($iconBlock)

    # Check name TextBlock
    $nameBlock = [System.Windows.Controls.TextBlock]::new()
    $nameBlock.Text = $displayName
    $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $nameBlock.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
    $nameBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$innerPanel.Children.Add($nameBlock)

    # Brief message TextBlock
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $messageBlock = [System.Windows.Controls.TextBlock]::new()
        $messageBlock.Text = $Message
        $messageBlock.Foreground = [System.Windows.Media.Brushes]::Gray
        $messageBlock.MaxWidth = 500
        $messageBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $messageBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [void]$innerPanel.Children.Add($messageBlock)
    }

    [void]$outerPanel.Children.Add($innerPanel)

    # Add remediation Expander for failed checks
    if ($Status -eq 'Failed' -and -not [string]::IsNullOrWhiteSpace($Remediation)) {
        $expander = [System.Windows.Controls.Expander]::new()

        # Header with bold text
        $headerBlock = [System.Windows.Controls.TextBlock]::new()
        $headerBlock.Text = 'Remediation Steps'
        $headerBlock.FontWeight = [System.Windows.FontWeights]::Bold
        $headerBlock.FontSize = 12
        $expander.Header = $headerBlock

        # Content with remediation text
        $remediationBlock = [System.Windows.Controls.TextBlock]::new()
        $remediationBlock.Text = $Remediation
        $remediationBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $remediationBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
        $remediationBlock.Padding = [System.Windows.Thickness]::new(8)

        # Background color based on severity
        $bgColor = if ($Severity -eq 'Critical') { '#FFF3F3' } else { '#FFFBF0' }
        $remediationBlock.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($bgColor)

        $expander.Content = $remediationBlock
        $expander.Margin = [System.Windows.Thickness]::new(22, 2, 0, 4)

        # Auto-expand for critical failures, collapsed for warnings
        $expander.IsExpanded = ($Severity -eq 'Critical')

        [void]$outerPanel.Children.Add($expander)
    }

    # Add to category panel
    [void]$panel.Children.Add($outerPanel)
}

function Update-CategorySummary {
    <#
    .SYNOPSIS
        Updates a category header's icon and summary text based on check counts.

    .DESCRIPTION
        Updates the category icon TextBlock and summary TextBlock to reflect the
        current state of checks in that category. Shows green checkmark when all
        pass, red X when any fail, amber warning when only warnings exist, and
        gray circle when no checks have run yet.

    .PARAMETER State
        The UI state object containing Controls hashtable.

    .PARAMETER Category
        The dashboard category name (System, Hypervisor, BuildTools, Network, Optimization).

    .PARAMETER TotalChecks
        Total number of checks in this category.

    .PARAMETER PassedChecks
        Number of checks that passed.

    .PARAMETER FailedChecks
        Number of checks that failed (critical severity).

    .PARAMETER WarningChecks
        Number of checks with warnings.

    .OUTPUTS
        [void]

    .EXAMPLE
        Update-CategorySummary -State $State -Category 'System' `
            -TotalChecks 4 -PassedChecks 4 -FailedChecks 0 -WarningChecks 0

    .EXAMPLE
        Update-CategorySummary -State $State -Category 'BuildTools' `
            -TotalChecks 5 -PassedChecks 3 -FailedChecks 2 -WarningChecks 0
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State,

        [Parameter(Mandatory)]
        [ValidateSet('System', 'Hypervisor', 'BuildTools', 'Network', 'Optimization')]
        [string]$Category,

        [Parameter(Mandatory)]
        [int]$TotalChecks,

        [Parameter(Mandatory)]
        [int]$PassedChecks,

        [Parameter()]
        [int]$FailedChecks = 0,

        [Parameter()]
        [int]$WarningChecks = 0
    )

    $iconControl = $State.Controls."txt${Category}Icon"
    $summaryControl = $State.Controls."txt${Category}Summary"

    if ($null -eq $iconControl -or $null -eq $summaryControl) {
        return
    }

    $brushConverter = [System.Windows.Media.BrushConverter]::new()

    if ($TotalChecks -eq 0) {
        # No checks run yet
        $iconControl.Text = [string][char]0x25CB  # empty circle
        $iconControl.Foreground = [System.Windows.Media.Brushes]::Gray
        $summaryControl.Text = '(checking...)'
        $summaryControl.Foreground = [System.Windows.Media.Brushes]::Gray
        $summaryControl.FontStyle = [System.Windows.FontStyles]::Italic
        return
    }

    # Reset font style from italic
    $summaryControl.FontStyle = [System.Windows.FontStyles]::Normal

    if ($FailedChecks -gt 0) {
        # Any failed checks - red
        $iconControl.Text = [string][char]0x2717  # X mark
        $iconControl.Foreground = $brushConverter.ConvertFromString('#C62828')
        $summaryControl.Text = "($PassedChecks/$TotalChecks -- $FailedChecks failed)"
        $summaryControl.Foreground = $brushConverter.ConvertFromString('#C62828')
    }
    elseif ($WarningChecks -gt 0) {
        # Warnings only - amber
        $iconControl.Text = [string][char]0x26A0  # warning triangle
        $iconControl.Foreground = $brushConverter.ConvertFromString('#F57F17')
        $summaryControl.Text = "($PassedChecks/$TotalChecks -- $WarningChecks warnings)"
        $summaryControl.Foreground = $brushConverter.ConvertFromString('#E65100')
    }
    else {
        # All passed - green
        $iconControl.Text = [string][char]0x2713  # checkmark
        $iconControl.Foreground = $brushConverter.ConvertFromString('#2E7D32')
        $summaryControl.Text = "($PassedChecks/$TotalChecks)"
        $summaryControl.Foreground = $brushConverter.ConvertFromString('#2E7D32')
    }
}

function Update-SummaryStatus {
    # PassedChecks is accepted for caller convenience and future summary detail expansion
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PassedChecks')]
    <#
    .SYNOPSIS
        Updates the summary status banner at the top of the dashboard.

    .DESCRIPTION
        Sets the background color and text of the summary status banner based
        on the overall check results. Shows green "Ready to Build" when all
        checks pass, red error summary for critical failures, and amber
        "Ready to Build" with warning count for warnings only.

    .PARAMETER State
        The UI state object containing Controls hashtable.

    .PARAMETER CriticalCount
        Number of critical failures.

    .PARAMETER WarningCount
        Number of warnings.

    .PARAMETER TotalChecks
        Total number of checks run.

    .PARAMETER PassedChecks
        Number of checks that passed. Reserved for future summary detail expansion.

    .OUTPUTS
        [void]

    .EXAMPLE
        Update-SummaryStatus -State $State -CriticalCount 0 -WarningCount 0 `
            -TotalChecks 12 -PassedChecks 12

    .EXAMPLE
        Update-SummaryStatus -State $State -CriticalCount 2 -WarningCount 1 `
            -TotalChecks 12 -PassedChecks 9
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State,

        [Parameter(Mandatory)]
        [int]$CriticalCount,

        [Parameter(Mandatory)]
        [int]$WarningCount,

        [Parameter(Mandatory)]
        [int]$TotalChecks,

        [Parameter(Mandatory)]
        [int]$PassedChecks
    )

    $border = $State.Controls.borderSummaryStatus
    $textBlock = $State.Controls.txtSummaryStatus

    if ($null -eq $border -or $null -eq $textBlock) {
        return
    }

    $brushConverter = [System.Windows.Media.BrushConverter]::new()

    if ($CriticalCount -gt 0) {
        # Critical failures - red banner
        $border.Background = $brushConverter.ConvertFromString('#FFEBEE')
        $textBlock.Text = "$CriticalCount Critical Issue(s), $WarningCount Warning(s)"
        $textBlock.Foreground = $brushConverter.ConvertFromString('#C62828')
    }
    elseif ($WarningCount -gt 0) {
        # Warnings only - amber banner
        $border.Background = $brushConverter.ConvertFromString('#FFF8E1')
        $textBlock.Text = "Ready to Build -- $WarningCount Warning(s)"
        $textBlock.Foreground = $brushConverter.ConvertFromString('#F57F17')
    }
    else {
        # All passed - green banner
        $border.Background = $brushConverter.ConvertFromString('#E8F5E9')
        $textBlock.Text = "Ready to Build -- All $TotalChecks checks passed"
        $textBlock.Foreground = $brushConverter.ConvertFromString('#2E7D32')
    }
}

function Update-BuildButtonState {
    <#
    .SYNOPSIS
        Enables or disables the Build button based on check results.

    .DESCRIPTION
        Manages the Build button (btnRun) enabled state and tooltip based on
        the number of critical failures and warnings from pre-flight checks.

        - Critical failures: Button disabled with error tooltip
        - Warnings only: Button enabled with warning tooltip, warning count
          stored in State.Data for the build click handler to check
        - All passed: Button enabled with standard tooltip

        Does NOT modify the btnRun click handler. Handler wiring is done in Plan 03.

    .PARAMETER State
        The UI state object containing Controls and Data hashtables.

    .PARAMETER CriticalCount
        Number of critical failures from pre-flight checks.

    .PARAMETER WarningCount
        Number of warnings from pre-flight checks.

    .OUTPUTS
        [void]

    .EXAMPLE
        Update-BuildButtonState -State $State -CriticalCount 0 -WarningCount 0

    .EXAMPLE
        Update-BuildButtonState -State $State -CriticalCount 2 -WarningCount 1
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State,

        [Parameter(Mandatory)]
        [int]$CriticalCount,

        [Parameter(Mandatory)]
        [int]$WarningCount
    )

    $btnRun = $State.Controls.btnRun

    if ($null -eq $btnRun) {
        return
    }

    if ($CriticalCount -gt 0) {
        # Critical failures - disable Build button
        $btnRun.IsEnabled = $false
        $btnRun.ToolTip = "$CriticalCount critical issue(s) must be resolved before building"
        if ($null -ne $State.Data) {
            $State.Data.dashboardWarningCount = 0
        }
    }
    elseif ($WarningCount -gt 0) {
        # Warnings only - enable with warning tooltip
        $btnRun.IsEnabled = $true
        $btnRun.ToolTip = "$WarningCount warning(s) detected. Build will prompt for confirmation."
        if ($null -ne $State.Data) {
            $State.Data.dashboardWarningCount = $WarningCount
        }
    }
    else {
        # All passed - enable with standard tooltip
        $btnRun.IsEnabled = $true
        $btnRun.ToolTip = 'Start FFU build'
        if ($null -ne $State.Data) {
            $State.Data.dashboardWarningCount = 0
        }
    }
}

function Clear-DashboardResults {
    # Plural noun is intentional - this function clears multiple dashboard result panels
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    <#
    .SYNOPSIS
        Resets all dashboard UI elements to their initial state.

    .DESCRIPTION
        Clears all check items from all 5 category panels, resets category
        icons to gray empty circles, resets summaries to "(checking...)" in
        italic gray, and resets the summary banner to "Checking system
        readiness..." with a LightGray background.

        Does NOT touch build button state (that is reset separately).

    .PARAMETER State
        The UI state object containing Controls hashtable.

    .OUTPUTS
        [void]

    .EXAMPLE
        Clear-DashboardResults -State $State
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State
    )

    # Clear check items from all category panels
    foreach ($category in $script:AllCategories) {
        $panelName = "pnl${category}Checks"
        $panel = $State.Controls.$panelName
        if ($null -ne $panel) {
            $panel.Children.Clear()
        }

        # Reset category icon to gray empty circle
        $iconControl = $State.Controls."txt${category}Icon"
        if ($null -ne $iconControl) {
            $iconControl.Text = [string][char]0x25CB  # empty circle
            $iconControl.Foreground = [System.Windows.Media.Brushes]::Gray
        }

        # Reset category summary to "(checking...)" italic gray
        $summaryControl = $State.Controls."txt${category}Summary"
        if ($null -ne $summaryControl) {
            $summaryControl.Text = '(checking...)'
            $summaryControl.Foreground = [System.Windows.Media.Brushes]::Gray
            $summaryControl.FontStyle = [System.Windows.FontStyles]::Italic
        }
    }

    # Reset summary banner
    $border = $State.Controls.borderSummaryStatus
    if ($null -ne $border) {
        $border.Background = [System.Windows.Media.Brushes]::LightGray
    }

    $textBlock = $State.Controls.txtSummaryStatus
    if ($null -ne $textBlock) {
        $textBlock.Text = 'Checking system readiness...'
        $textBlock.Foreground = [System.Windows.Media.Brushes]::Black
    }
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function Get-CheckCategory, Update-DashboardCheckUI, Update-CategorySummary, Update-SummaryStatus, Update-BuildButtonState, Clear-DashboardResults
