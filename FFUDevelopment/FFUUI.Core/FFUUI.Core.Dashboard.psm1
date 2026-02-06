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
# SECTION: Remediation Mappings and Helpers
# --------------------------------------------------------------------------

# Map of check names to safe repair function names
# These repairs can be executed without reboot or major system changes
$script:SafeRepairMap = @{
    'WimMount'    = 'Repair-FFUWimMount'
    'DISMState'   = 'Repair-FFUDismState'
    'DISMCleanup' = 'Invoke-FFUDISMCleanup'
    'Network'     = 'Repair-FFUNetwork'
}

# Map of check names to unsafe remediation details
# These require reboot or major system changes
$script:UnsafeRemediationMap = @{
    'HyperV' = @{
        Command = 'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart'
        RequiresReboot = $true
        ConfirmTitle = 'Confirm System Change'
        ConfirmMessage = "This will enable Hyper-V on your system.`n`nCommand to run:`n  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart`n`nA system reboot is required to complete the installation.`nThe build cannot proceed until the system is restarted.`n`nContinue?"
        SuccessMessage = 'Hyper-V has been enabled. Please reboot your system to complete the installation.'
    }
}

function Extract-PowerShellCommands {
    # Internal helper function - unapproved verb and plural noun are acceptable for internal use
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    <#
    .SYNOPSIS
        Extracts PowerShell command lines from remediation text.

    .DESCRIPTION
        Parses the FIX section from New-FFURemediationBlock formatted remediation
        text and returns an array of executable PowerShell command lines.

        Looks for the "=== FIX ===" section, extracts indented command lines,
        and filters out comment lines and blank lines.

    .PARAMETER RemediationText
        The formatted remediation text from a check result.

    .OUTPUTS
        [string[]] - Array of PowerShell command strings, or the full remediation
        text if parsing fails.

    .EXAMPLE
        $commands = Extract-PowerShellCommands -RemediationText $check.Remediation
        # Returns: @('Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All')
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RemediationText
    )

    if ([string]::IsNullOrWhiteSpace($RemediationText)) {
        return @()
    }

    # Find text between "=== FIX ===" and the next section marker or end
    # The pattern: after "=== FIX ===", skip any header lines, capture indented commands
    if ($RemediationText -match '(?s)=== FIX ===\s+(.*?)(?:(?:^|\n)Manual steps:|(?:^|\n)=== VERIFY ===|$)') {
        $fixSection = $matches[1]

        # Split by newlines and extract command lines (indented with 4+ spaces)
        $commands = $fixSection -split '\r?\n' |
            Where-Object {
                # Keep lines that start with 4+ spaces and aren't blank/comments after trimming
                $trimmed = $_.Trim()
                $_ -match '^\s{4,}' -and
                -not [string]::IsNullOrWhiteSpace($trimmed) -and
                -not $trimmed.StartsWith('#')
            } |
            ForEach-Object { $_.Trim() }

        if ($commands.Count -gt 0) {
            return $commands
        }
    }

    # Fallback: return the full remediation text as a single item
    return @($RemediationText)
}

function Format-CheckDuration {
    <#
    .SYNOPSIS
        Formats check duration in milliseconds as a display string.

    .DESCRIPTION
        Converts a duration in milliseconds to a formatted string like " (1.2s)".
        Returns an empty string if duration is 0 or negative.

    .PARAMETER DurationMs
        The duration in milliseconds.

    .OUTPUTS
        [string] - Formatted duration string with 1 decimal precision, or empty string.

    .EXAMPLE
        Format-CheckDuration -DurationMs 1234
        # Returns: " (1.2s)"

    .EXAMPLE
        Format-CheckDuration -DurationMs 0
        # Returns: ""
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [int]$DurationMs = 0
    )

    if ($DurationMs -le 0) {
        return ''
    }

    $seconds = [Math]::Round($DurationMs / 1000.0, 1)
    return " (${seconds}s)"
}

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

    .PARAMETER DurationMs
        Check execution duration in milliseconds. Displayed as "(X.Xs)" suffix
        after the message text.

    .PARAMETER OnFixClick
        Scriptblock to execute when the Fix button is clicked for safe remediations.
        The button's Tag property contains the CheckName.

    .PARAMETER OnUnsafeFixClick
        Scriptblock to execute when the Fix button is clicked for unsafe remediations
        (requires reboot confirmation). The button's Tag property contains the CheckName.

    .PARAMETER OnCopyClick
        Scriptblock to execute when the Copy button is clicked in the Details expander.
        The button's Tag property contains the CheckName.

    .OUTPUTS
        [void]

    .EXAMPLE
        Update-DashboardCheckUI -State $State -CheckName 'Administrator' -Status 'Passed' `
            -Severity 'Critical' -Message 'Running with Administrator privileges' -DurationMs 120

    .EXAMPLE
        Update-DashboardCheckUI -State $State -CheckName 'ADK' -Status 'Failed' `
            -Severity 'Critical' -Message 'Windows ADK not installed' `
            -Remediation 'Download and install Windows ADK from Microsoft' -DurationMs 350
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
        [string]$Remediation = '',

        [Parameter()]
        [int]$DurationMs = 0,

        [Parameter()]
        [scriptblock]$OnFixClick,

        [Parameter()]
        [scriptblock]$OnUnsafeFixClick,

        [Parameter()]
        [scriptblock]$OnCopyClick
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

    # Brief message TextBlock with duration
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $messageBlock = [System.Windows.Controls.TextBlock]::new()
        $durationSuffix = Format-CheckDuration -DurationMs $DurationMs
        $messageBlock.Text = "$Message$durationSuffix"
        $messageBlock.Foreground = [System.Windows.Media.Brushes]::Gray
        $messageBlock.MaxWidth = 500
        $messageBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $messageBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [void]$innerPanel.Children.Add($messageBlock)
    }

    [void]$outerPanel.Children.Add($innerPanel)

    # Add Fix button for failed checks with mapped repair functions
    if ($Status -eq 'Failed') {
        $brushConverter = [System.Windows.Media.BrushConverter]::new()

        # Check if user previously declined an unsafe fix
        $fixDeclined = $false
        if ($null -ne $State.Data -and $State.Data.ContainsKey("fixDeclined_$CheckName")) {
            $fixDeclined = $State.Data["fixDeclined_$CheckName"] -eq $true
        }

        if ($fixDeclined) {
            # Show "Fix available" indicator for declined fixes
            $indicatorBlock = [System.Windows.Controls.TextBlock]::new()
            $indicatorBlock.Text = 'Fix available'
            $indicatorBlock.Foreground = $brushConverter.ConvertFromString('#1565C0')
            $indicatorBlock.FontStyle = [System.Windows.FontStyles]::Italic
            $indicatorBlock.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
            $indicatorBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            [void]$innerPanel.Children.Add($indicatorBlock)
        }
        elseif ($script:SafeRepairMap.ContainsKey($CheckName)) {
            # Safe repair - green Fix button
            $btnFix = [System.Windows.Controls.Button]::new()
            $btnFix.Content = 'Fix'
            $btnFix.Padding = [System.Windows.Thickness]::new(8, 2)
            $btnFix.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
            $btnFix.Background = $brushConverter.ConvertFromString('#C8E6C9')
            $btnFix.Foreground = $brushConverter.ConvertFromString('#1B5E20')
            $btnFix.Tag = $CheckName
            $btnFix.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

            # Wire click handler via scriptblock parameter
            if ($null -ne $OnFixClick) {
                $btnFix.Add_Click($OnFixClick)
            }

            [void]$innerPanel.Children.Add($btnFix)
        }
        elseif ($script:UnsafeRemediationMap.ContainsKey($CheckName)) {
            # Unsafe repair - amber Fix... button (ellipsis indicates confirmation)
            $btnFix = [System.Windows.Controls.Button]::new()
            $btnFix.Content = 'Fix...'
            $btnFix.Padding = [System.Windows.Thickness]::new(8, 2)
            $btnFix.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
            $btnFix.Background = $brushConverter.ConvertFromString('#FFE0B2')
            $btnFix.Foreground = $brushConverter.ConvertFromString('#E65100')
            $btnFix.Tag = $CheckName
            $btnFix.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

            # Wire click handler via scriptblock parameter
            if ($null -ne $OnUnsafeFixClick) {
                $btnFix.Add_Click($OnUnsafeFixClick)
            }

            [void]$innerPanel.Children.Add($btnFix)
        }
    }

    # Add Details expander for failed checks with remediation
    if ($Status -eq 'Failed' -and -not [string]::IsNullOrWhiteSpace($Remediation)) {
        $expander = [System.Windows.Controls.Expander]::new()

        # Header with normal text
        $headerBlock = [System.Windows.Controls.TextBlock]::new()
        $headerBlock.Text = 'Details'
        $headerBlock.FontWeight = [System.Windows.FontWeights]::Normal
        $headerBlock.FontSize = 11
        $expander.Header = $headerBlock

        # Always collapsed by default
        $expander.IsExpanded = $false
        $expander.Margin = [System.Windows.Thickness]::new(22, 2, 0, 4)

        # Content: StackPanel with command TextBox + Copy button + optional full remediation
        $contentPanel = [System.Windows.Controls.StackPanel]::new()
        $contentPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical

        # Extract PowerShell commands from remediation text
        $commands = Extract-PowerShellCommands -RemediationText $Remediation
        $commandText = $commands -join "`n"

        # Monospace TextBox for commands
        $txtCommands = [System.Windows.Controls.TextBox]::new()
        $txtCommands.Text = $commandText
        $txtCommands.IsReadOnly = $true
        $txtCommands.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
        $txtCommands.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $txtCommands.AcceptsReturn = $true
        $txtCommands.Background = [System.Windows.Media.Brushes]::WhiteSmoke
        $txtCommands.MaxHeight = 200
        $txtCommands.Name = "txtRemediation_$CheckName"
        [void]$contentPanel.Children.Add($txtCommands)

        # Copy button
        $btnCopy = [System.Windows.Controls.Button]::new()
        $btnCopy.Content = 'Copy'
        $btnCopy.Width = 60
        $btnCopy.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
        $btnCopy.Tag = $CheckName

        # Wire click handler via scriptblock parameter
        if ($null -ne $OnCopyClick) {
            $btnCopy.Add_Click($OnCopyClick)
        }

        [void]$contentPanel.Children.Add($btnCopy)

        # For Critical severity, also show full remediation text
        if ($Severity -eq 'Critical') {
            $fullRemediationBlock = [System.Windows.Controls.TextBlock]::new()
            $fullRemediationBlock.Text = $Remediation
            $fullRemediationBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $fullRemediationBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
            $fullRemediationBlock.Padding = [System.Windows.Thickness]::new(8)
            $fullRemediationBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
            $fullRemediationBlock.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFF3F3')
            [void]$contentPanel.Children.Add($fullRemediationBlock)
        }

        $expander.Content = $contentPanel
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

function Update-HypervisorCategoryVisibility {
    <#
    .SYNOPSIS
        Updates hypervisor info banner text based on selected hypervisor type.

    .DESCRIPTION
        Updates the inline hypervisor info banner to indicate which hypervisor
        is currently being validated. All hypervisor types have relevant checks,
        so the Hypervisor category expander is always visible. The backend
        (Invoke-FFUPreflight) handles which checks run vs skip.

    .PARAMETER State
        The UI state object containing Controls hashtable.

    .PARAMETER HypervisorType
        The hypervisor type selected: HyperV, VMware, or Auto.

    .OUTPUTS
        [void]

    .EXAMPLE
        Update-HypervisorCategoryVisibility -State $State -HypervisorType 'VMware'
        # Sets info banner to: "Validating for: VMware Workstation -- Hyper-V checks skipped"

    .EXAMPLE
        Update-HypervisorCategoryVisibility -State $State -HypervisorType 'HyperV'
        # Sets info banner to: "Validating for: Hyper-V -- VMware checks skipped"
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State,

        [Parameter(Mandatory)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType
    )

    # All hypervisor types have relevant checks, so always show the Hypervisor expander
    # The backend (Invoke-FFUPreflight) handles which checks run vs skip
    # This function's primary role is updating the info banner text

    # Update hypervisor info banner
    $infoBorder = $State.Controls.borderHypervisorInfo
    $infoText = $State.Controls.txtHypervisorInfo

    if ($null -ne $infoBorder -and $null -ne $infoText) {
        $infoBorder.Visibility = [System.Windows.Visibility]::Visible
        $infoText.Text = switch ($HypervisorType) {
            'HyperV' { 'Validating for: Hyper-V -- VMware checks skipped' }
            'VMware' { 'Validating for: VMware Workstation -- Hyper-V checks skipped' }
            'Auto'   { 'Validating for: Auto-detected hypervisor' }
        }
    }
}

function Invoke-DashboardRemediation {
    <#
    .SYNOPSIS
        Executes a safe repair function for a failed check.

    .DESCRIPTION
        Looks up the repair function name from SafeRepairMap and executes it.
        Tracks execution duration and returns a result object with Succeeded,
        Message, and DurationMs properties.

        Special case: Invoke-FFUDISMCleanup requires -FFUDevelopmentPath parameter.

    .PARAMETER CheckName
        The name of the check to repair (e.g., 'WimMount', 'DISMState').

    .PARAMETER FFUDevelopmentPath
        The FFU development path. Required for DISMCleanup repair.

    .OUTPUTS
        [PSCustomObject] - Result object with Succeeded, Message, DurationMs properties.

    .EXAMPLE
        $result = Invoke-DashboardRemediation -CheckName 'WimMount'
        # Executes Repair-FFUWimMount and returns result

    .EXAMPLE
        $result = Invoke-DashboardRemediation -CheckName 'DISMCleanup' -FFUDevelopmentPath 'C:\FFUDevelopment'
        # Executes Invoke-FFUDISMCleanup with path parameter
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$CheckName,

        [Parameter()]
        [string]$FFUDevelopmentPath = ''
    )

    # Verify check has a mapped repair function
    if (-not $script:SafeRepairMap.ContainsKey($CheckName)) {
        return [PSCustomObject]@{
            Succeeded = $false
            Message = "No repair available for $CheckName"
            DurationMs = 0
        }
    }

    $funcName = $script:SafeRepairMap[$CheckName]
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Special case: DISMCleanup needs FFUDevelopmentPath parameter
        if ($CheckName -eq 'DISMCleanup') {
            if ([string]::IsNullOrWhiteSpace($FFUDevelopmentPath)) {
                throw 'DISMCleanup repair requires FFUDevelopmentPath parameter'
            }
            $result = & $funcName -FFUDevelopmentPath $FFUDevelopmentPath
        }
        else {
            $result = & $funcName
        }

        $stopwatch.Stop()

        # Return the result from the repair function
        if ($null -ne $result) {
            return $result
        }

        # Fallback if repair function doesn't return a result
        return [PSCustomObject]@{
            Succeeded = $true
            Message = "Repair executed successfully"
            DurationMs = $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        return [PSCustomObject]@{
            Succeeded = $false
            Message = "Repair failed: $($_.Exception.Message)"
            DurationMs = $stopwatch.ElapsedMilliseconds
        }
    }
}

function Get-SafeRepairMap {
    <#
    .SYNOPSIS
        Returns the safe repair function mapping hashtable.

    .DESCRIPTION
        Exposes the script-scoped SafeRepairMap for external callers
        (e.g., BuildFFUVM_UI.ps1 click handler wiring).

    .OUTPUTS
        [hashtable] - Map of check names to repair function names.

    .EXAMPLE
        $repairMap = Get-SafeRepairMap
        # Returns: @{ 'WimMount' = 'Repair-FFUWimMount'; ... }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return $script:SafeRepairMap
}

function Get-UnsafeRemediationMap {
    <#
    .SYNOPSIS
        Returns the unsafe remediation details mapping hashtable.

    .DESCRIPTION
        Exposes the script-scoped UnsafeRemediationMap for external callers
        (e.g., BuildFFUVM_UI.ps1 confirmation dialog logic).

    .OUTPUTS
        [hashtable] - Map of check names to unsafe remediation details.

    .EXAMPLE
        $unsafeMap = Get-UnsafeRemediationMap
        # Returns: @{ 'HyperV' = @{ Command = '...'; RequiresReboot = $true; ... } }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return $script:UnsafeRemediationMap
}

function Export-DashboardDiagnostics {
    <#
    .SYNOPSIS
        Exports dashboard check results and system information to a timestamped text file.

    .DESCRIPTION
        Generates a comprehensive diagnostics report containing system information,
        module versions, and all check results. The report is saved to the Logs
        folder with a timestamped filename. Returns the full path to the generated file.

    .PARAMETER State
        The UI state object containing check results, version info, and control references.

    .OUTPUTS
        [string] - Full path to the generated diagnostics file.

    .EXAMPLE
        $path = Export-DashboardDiagnostics -State $script:uiState
        # Returns: "C:\FFUDevelopment\Logs\FFU-Diagnostics-2026-02-06-183015.txt"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State
    )

    # Generate timestamped filename
    $timestamp = [DateTime]::Now.ToString('yyyy-MM-dd-HHmmss')
    $logsPath = Join-Path $State.FFUDevelopmentPath 'Logs'

    # Ensure Logs folder exists
    if (-not (Test-Path $logsPath)) {
        New-Item -Path $logsPath -ItemType Directory -Force | Out-Null
    }

    $outputPath = Join-Path $logsPath "FFU-Diagnostics-$timestamp.txt"

    $sb = [System.Text.StringBuilder]::new()

    # ========== HEADER ==========
    [void]$sb.AppendLine("=" * 80)
    [void]$sb.AppendLine("FFU BUILDER PRE-FLIGHT DIAGNOSTICS REPORT")
    [void]$sb.AppendLine("=" * 80)
    [void]$sb.AppendLine("Generated: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))")
    [void]$sb.AppendLine()

    # ========== SYSTEM INFORMATION ==========
    [void]$sb.AppendLine("SYSTEM INFORMATION")
    [void]$sb.AppendLine("-" * 80)
    [void]$sb.AppendLine("OS Version       : $([Environment]::OSVersion.VersionString)")
    [void]$sb.AppendLine("PowerShell       : PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))")
    [void]$sb.AppendLine("FFU Builder      : v$($State.Version.Number) (Build: $($State.Version.BuildDate))")

    # Selected hypervisor
    $hvType = 'Unknown'
    try {
        if ($null -ne $State.Controls -and $null -ne $State.Controls.cmbHypervisorType) {
            $hvType = switch ($State.Controls.cmbHypervisorType.SelectedIndex) {
                0 { 'Hyper-V' }
                1 { 'VMware Workstation Pro' }
                2 { 'Auto-detect' }
                default { 'Unknown' }
            }
        }
    }
    catch {
        $hvType = 'Unable to determine'
    }
    [void]$sb.AppendLine("Hypervisor       : $hvType")

    # Available disk space
    try {
        $drive = [System.IO.Path]::GetPathRoot($State.FFUDevelopmentPath)
        $driveInfo = [System.IO.DriveInfo]::new($drive)
        $freeSpaceGB = [Math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)
        [void]$sb.AppendLine("Available Space  : $freeSpaceGB GB ($drive)")
    }
    catch {
        [void]$sb.AppendLine("Available Space  : Unable to determine")
    }

    [void]$sb.AppendLine()

    # ========== MODULE VERSIONS ==========
    if ($null -ne $State.Version.Modules) {
        [void]$sb.AppendLine("MODULE VERSIONS")
        [void]$sb.AppendLine("-" * 80)
        foreach ($module in $State.Version.Modules.PSObject.Properties) {
            $name = $module.Name
            $version = $module.Value.version
            [void]$sb.AppendLine("  $($name.PadRight(30)): v$version")
        }
        [void]$sb.AppendLine()
    }

    # ========== CHECK RESULTS ==========
    [void]$sb.AppendLine("CHECK RESULTS")
    [void]$sb.AppendLine("-" * 80)

    $allCategories = @('System', 'Hypervisor', 'BuildTools', 'Network', 'Optimization')
    foreach ($category in $allCategories) {
        $stats = $null
        if ($null -ne $State.Data -and $null -ne $State.Data.dashboardCategoryStats) {
            $stats = $State.Data.dashboardCategoryStats[$category]
        }

        if ($null -eq $stats -or $stats.Total -eq 0) {
            continue
        }

        [void]$sb.AppendLine()
        [void]$sb.AppendLine("[$category]")
        [void]$sb.AppendLine("  Total: $($stats.Total) | Passed: $($stats.Passed) | Failed: $($stats.Failed) | Warning: $($stats.Warning)")

        # Individual check details if available
        if ($null -ne $State.Data -and $null -ne $State.Data.dashboardCheckResults) {
            foreach ($checkEntry in $State.Data.dashboardCheckResults.GetEnumerator()) {
                $checkName = $checkEntry.Key
                $checkData = $checkEntry.Value

                # Filter by category
                $checkCategory = Get-CheckCategory -CheckName $checkName
                if ($checkCategory -ne $category) {
                    continue
                }

                $statusPrefix = switch ($checkData.Status) {
                    'Passed'  { '[PASS]' }
                    'Failed'  { '[FAIL]' }
                    'Warning' { '[WARN]' }
                    'Skipped' { '[SKIP]' }
                    default   { '[????]' }
                }

                $durationText = ''
                if ($checkData.DurationMs -gt 0) {
                    $seconds = [Math]::Round($checkData.DurationMs / 1000.0, 1)
                    $durationText = " ($($seconds)s)"
                }

                # Get friendly name
                $displayName = if ($script:FriendlyNames.ContainsKey($checkName)) {
                    $script:FriendlyNames[$checkName]
                }
                else {
                    $checkName
                }

                [void]$sb.AppendLine("  $statusPrefix $displayName - $($checkData.Message)$durationText")

                # For failed checks, add severity and remediation info
                if ($checkData.Status -eq 'Failed' -and $null -ne $checkData.Severity) {
                    [void]$sb.AppendLine("         Severity: $($checkData.Severity)")
                    if (-not [string]::IsNullOrWhiteSpace($checkData.Remediation)) {
                        # Extract just the commands for concise output
                        $commands = Extract-PowerShellCommands -RemediationText $checkData.Remediation
                        if ($commands.Count -gt 0) {
                            [void]$sb.AppendLine("         Remediation: $($commands[0])")
                            if ($commands.Count -gt 1) {
                                [void]$sb.AppendLine("                      (+ $($commands.Count - 1) more command(s))")
                            }
                        }
                    }
                }
            }
        }
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine("=" * 80)
    [void]$sb.AppendLine("END OF REPORT")
    [void]$sb.AppendLine("=" * 80)

    # Write to file
    $sb.ToString() | Out-File -FilePath $outputPath -Encoding UTF8

    return $outputPath
}

function Get-HypervisorDependentChecks {
    <#
    .SYNOPSIS
        Returns lists of checks that are dependent on hypervisor selection.

    .DESCRIPTION
        Identifies which pre-flight checks are conditionally executed based on
        the HypervisorType parameter. Used to determine revalidation scope when
        the hypervisor selection changes.

        Based on Invoke-FFUPreflight conditional logic in FFU.Preflight.psm1.

    .OUTPUTS
        [hashtable] - Contains three keys:
        - HyperV: Array of check names that only run for Hyper-V
        - VMware: Array of check names that only run for VMware
        - Independent: Array of check names that run for all hypervisors

    .EXAMPLE
        $deps = Get-HypervisorDependentChecks
        # $deps.HyperV contains @('HyperV')
        # $deps.VMware contains @('VmxToolkit', 'VMwareDrivers', ...)
        # $deps.Independent contains @('Administrator', 'PowerShellVersion', ...)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        # Checks that ONLY run when HypervisorType = 'HyperV'
        HyperV = @(
            'HyperV'
        )

        # Checks that ONLY run when HypervisorType = 'VMware'
        VMware = @(
            'VmxToolkit'
            'VMwareDrivers'
            'HyperVSwitchConflict'
            'VMwareBridgeConfig'
            'HostIPAddress'
        )

        # Checks that run regardless of hypervisor selection
        Independent = @(
            'Administrator'
            'PowerShellVersion'
            'VMResources'
            'ScratchSpace'
            'ADK'
            'WimMount'
            'DiskSpace'
            'DISMState'
            'DISMCleanup'
            'Network'
            'Configuration'
            'AntivirusExclusions'
            'AppsISODiskSpace'
            'CaptureDiskSpace'
        )
    }
}

function Set-CategoryDimmed {
    <#
    .SYNOPSIS
        Applies or removes visual dimming on a dashboard category expander.

    .DESCRIPTION
        Manages the visual transition state for a category during revalidation.
        When dimmed, sets opacity to 0.5 and shows italic "(rechecking...)" text.
        When undimmed, restores opacity to 1.0 and normal font style.

    .PARAMETER State
        The UI state object containing control references.

    .PARAMETER Category
        The dashboard category name (System, Hypervisor, BuildTools, Network, Optimization).

    .PARAMETER IsDimmed
        True to apply dimming, false to remove dimming.

    .OUTPUTS
        [void]

    .EXAMPLE
        Set-CategoryDimmed -State $State -Category 'Hypervisor' -IsDimmed $true
        # Dims the Hypervisor category and shows "(rechecking...)"

    .EXAMPLE
        Set-CategoryDimmed -State $State -Category 'Hypervisor' -IsDimmed $false
        # Restores normal appearance (Update-CategorySummary will update text)
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
        [bool]$IsDimmed
    )

    $expander = $State.Controls."exp$Category"
    if ($null -eq $expander) {
        return
    }

    if ($IsDimmed) {
        # Apply dimming
        $expander.Opacity = 0.5
        $summaryControl = $State.Controls."txt${Category}Summary"
        if ($null -ne $summaryControl) {
            $summaryControl.FontStyle = [System.Windows.FontStyles]::Italic
            $summaryControl.Text = '(rechecking...)'
        }
    }
    else {
        # Remove dimming
        $expander.Opacity = 1.0
        $summaryControl = $State.Controls."txt${Category}Summary"
        if ($null -ne $summaryControl) {
            $summaryControl.FontStyle = [System.Windows.FontStyles]::Normal
            # Do NOT change text - Update-CategorySummary will set final text
        }
    }
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function Get-CheckCategory, Update-DashboardCheckUI, Update-CategorySummary, Update-SummaryStatus, Update-BuildButtonState, Clear-DashboardResults, Update-HypervisorCategoryVisibility, Invoke-DashboardRemediation, Get-SafeRepairMap, Get-UnsafeRemediationMap, Export-DashboardDiagnostics, Get-HypervisorDependentChecks, Set-CategoryDimmed
