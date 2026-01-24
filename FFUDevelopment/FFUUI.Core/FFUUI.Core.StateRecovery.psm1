#Requires -Version 7.0
<#
.SYNOPSIS
    Centralized UI state recovery functions for FFU Builder.

.DESCRIPTION
    This module provides functions to save, restore, and reset UI state in the FFU Builder
    application. It addresses the need for consistent UI state management after errors,
    ensuring that progress bars, buttons, flags, and status text are properly reset
    regardless of where an error occurs.

    Key functions:
    - Reset-FFUUIToIdle: Main function to reset all UI controls after errors
    - Save-FFUUIState: Capture current state before potentially risky operations
    - Restore-FFUUIState: Restore from a previously saved state snapshot

.NOTES
    Author: Claude Code
    Version: 1.0.0
    Created: 2026-01-24

    This module is part of FFUUI.Core and addresses REL-UI-03: UI state remains consistent after errors.
#>

#region Reset-FFUUIToIdle

<#
.SYNOPSIS
    Resets all UI controls to idle state after an error or build completion.

.DESCRIPTION
    Reset-FFUUIToIdle is the primary function for returning the UI to a ready state.
    It handles resetting:
    - Progress bar (hidden, value = 0)
    - Build button (enabled, text = "Build FFU")
    - Flags (isBuilding = false, isCleanupRunning = false)
    - Status text (customizable message)
    - Poll timer (stopped)
    - Messaging context (closed if exists)

    All operations include null checks for defensive coding.

.PARAMETER State
    The UI state object ($script:uiState from BuildFFUVM_UI.ps1).
    Must contain Controls, Flags, and Data hashtables.

.PARAMETER StatusMessage
    Optional status message to display. Defaults to "Ready".

.EXAMPLE
    Reset-FFUUIToIdle -State $script:uiState -StatusMessage "Build failed. Check log for details."

    Resets all UI controls and displays error message in status bar.

.EXAMPLE
    Reset-FFUUIToIdle -State $script:uiState

    Resets all UI controls with default "Ready" status message.

.OUTPUTS
    None. Modifies UI state object directly.
#>
function Reset-FFUUIToIdle {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State,

        [Parameter(Mandatory = $false)]
        [string]$StatusMessage = "Ready"
    )

    begin {
        # Log state recovery action if WriteLog is available
        $logAvailable = $null -ne (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue)
        if ($logAvailable) {
            WriteLog "Reset-FFUUIToIdle: Resetting UI to idle state. Status: $StatusMessage"
        }
    }

    process {
        # Stop poll timer if running
        if ($null -ne $State.Data -and $null -ne $State.Data.pollTimer) {
            try {
                $State.Data.pollTimer.Stop()
                $State.Data.pollTimer = $null
                if ($logAvailable) {
                    WriteLog "Reset-FFUUIToIdle: Stopped poll timer."
                }
            }
            catch {
                if ($logAvailable) {
                    WriteLog "Reset-FFUUIToIdle: Warning - Failed to stop poll timer: $($_.Exception.Message)"
                }
            }
        }

        # Close messaging context if exists
        if ($null -ne $State.Data -and $null -ne $State.Data.messagingContext) {
            try {
                # Check if Close-FFUMessagingContext is available (module may not be loaded)
                $closeCmd = Get-Command -Name 'Close-FFUMessagingContext' -ErrorAction SilentlyContinue
                if ($null -ne $closeCmd) {
                    Close-FFUMessagingContext -Context $State.Data.messagingContext
                    if ($logAvailable) {
                        WriteLog "Reset-FFUUIToIdle: Closed messaging context."
                    }
                }
                $State.Data.messagingContext = $null
            }
            catch {
                if ($logAvailable) {
                    WriteLog "Reset-FFUUIToIdle: Warning - Failed to close messaging context: $($_.Exception.Message)"
                }
                # Ensure it's nulled even if close fails
                $State.Data.messagingContext = $null
            }
        }

        # Reset progress bar
        if ($null -ne $State.Controls) {
            if ($null -ne $State.Controls.pbOverallProgress) {
                try {
                    $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
                    $State.Controls.pbOverallProgress.Value = 0
                }
                catch {
                    if ($logAvailable) {
                        WriteLog "Reset-FFUUIToIdle: Warning - Failed to reset progress bar: $($_.Exception.Message)"
                    }
                }
            }

            # Reset build button
            if ($null -ne $State.Controls.btnRun) {
                try {
                    $State.Controls.btnRun.IsEnabled = $true
                    $State.Controls.btnRun.Content = "Build FFU"
                }
                catch {
                    if ($logAvailable) {
                        WriteLog "Reset-FFUUIToIdle: Warning - Failed to reset build button: $($_.Exception.Message)"
                    }
                }
            }

            # Reset status text
            if ($null -ne $State.Controls.txtStatus) {
                try {
                    $State.Controls.txtStatus.Text = $StatusMessage
                }
                catch {
                    if ($logAvailable) {
                        WriteLog "Reset-FFUUIToIdle: Warning - Failed to update status text: $($_.Exception.Message)"
                    }
                }
            }
        }

        # Reset flags
        if ($null -ne $State.Flags) {
            try {
                $State.Flags.isBuilding = $false
                $State.Flags.isCleanupRunning = $false
            }
            catch {
                if ($logAvailable) {
                    WriteLog "Reset-FFUUIToIdle: Warning - Failed to reset flags: $($_.Exception.Message)"
                }
            }
        }

        # Clear current build job reference
        if ($null -ne $State.Data) {
            $State.Data.currentBuildJob = $null
        }
    }

    end {
        if ($logAvailable) {
            WriteLog "Reset-FFUUIToIdle: UI reset complete."
        }
    }
}

#endregion

#region Save-FFUUIState

<#
.SYNOPSIS
    Captures current UI state for potential recovery.

.DESCRIPTION
    Save-FFUUIState creates a snapshot of the current UI state that can be used
    to restore the UI if an operation fails. This is useful before starting
    operations that might need to be rolled back.

    Captured state includes:
    - isBuilding flag
    - Build button content and enabled state
    - Progress bar value and visibility
    - Status text

.PARAMETER State
    The UI state object ($script:uiState from BuildFFUVM_UI.ps1).

.EXAMPLE
    $savedState = Save-FFUUIState -State $script:uiState
    try {
        # Risky operation
    }
    catch {
        Restore-FFUUIState -State $script:uiState -SavedState $savedState
    }

.OUTPUTS
    [hashtable] A snapshot of the UI state that can be passed to Restore-FFUUIState.
#>
function Save-FFUUIState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State
    )

    $savedState = @{
        isBuilding       = $false
        isCleanupRunning = $false
        btnRunContent    = "Build FFU"
        btnRunEnabled    = $true
        progressValue    = 0
        progressVisible  = 'Collapsed'
        statusText       = "Ready"
    }

    # Capture flags
    if ($null -ne $State.Flags) {
        if ($null -ne $State.Flags.isBuilding) {
            $savedState.isBuilding = $State.Flags.isBuilding
        }
        if ($null -ne $State.Flags.isCleanupRunning) {
            $savedState.isCleanupRunning = $State.Flags.isCleanupRunning
        }
    }

    # Capture controls
    if ($null -ne $State.Controls) {
        if ($null -ne $State.Controls.btnRun) {
            try {
                $savedState.btnRunContent = $State.Controls.btnRun.Content
                $savedState.btnRunEnabled = $State.Controls.btnRun.IsEnabled
            }
            catch {
                # Use defaults if access fails
            }
        }

        if ($null -ne $State.Controls.pbOverallProgress) {
            try {
                $savedState.progressValue = $State.Controls.pbOverallProgress.Value
                $savedState.progressVisible = $State.Controls.pbOverallProgress.Visibility
            }
            catch {
                # Use defaults if access fails
            }
        }

        if ($null -ne $State.Controls.txtStatus) {
            try {
                $savedState.statusText = $State.Controls.txtStatus.Text
            }
            catch {
                # Use defaults if access fails
            }
        }
    }

    return $savedState
}

#endregion

#region Restore-FFUUIState

<#
.SYNOPSIS
    Restores UI to a previously saved state.

.DESCRIPTION
    Restore-FFUUIState applies a previously captured state snapshot back to the UI.
    This is useful for rolling back UI changes when an operation fails.

    The function handles missing keys gracefully, using sensible defaults for
    any values not present in the saved state.

.PARAMETER State
    The UI state object ($script:uiState from BuildFFUVM_UI.ps1).

.PARAMETER SavedState
    The state snapshot returned by Save-FFUUIState.

.EXAMPLE
    $savedState = Save-FFUUIState -State $script:uiState
    try {
        # Risky operation that modifies UI
    }
    catch {
        Restore-FFUUIState -State $script:uiState -SavedState $savedState
    }

.OUTPUTS
    None. Modifies UI state object directly.
#>
function Restore-FFUUIState {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$SavedState
    )

    begin {
        $logAvailable = $null -ne (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue)
        if ($logAvailable) {
            WriteLog "Restore-FFUUIState: Restoring UI to saved state."
        }
    }

    process {
        # Restore flags
        if ($null -ne $State.Flags) {
            if ($SavedState.ContainsKey('isBuilding')) {
                $State.Flags.isBuilding = $SavedState.isBuilding
            }
            if ($SavedState.ContainsKey('isCleanupRunning')) {
                $State.Flags.isCleanupRunning = $SavedState.isCleanupRunning
            }
        }

        # Restore controls
        if ($null -ne $State.Controls) {
            if ($null -ne $State.Controls.btnRun) {
                try {
                    if ($SavedState.ContainsKey('btnRunContent')) {
                        $State.Controls.btnRun.Content = $SavedState.btnRunContent
                    }
                    if ($SavedState.ContainsKey('btnRunEnabled')) {
                        $State.Controls.btnRun.IsEnabled = $SavedState.btnRunEnabled
                    }
                }
                catch {
                    if ($logAvailable) {
                        WriteLog "Restore-FFUUIState: Warning - Failed to restore button: $($_.Exception.Message)"
                    }
                }
            }

            if ($null -ne $State.Controls.pbOverallProgress) {
                try {
                    if ($SavedState.ContainsKey('progressValue')) {
                        $State.Controls.pbOverallProgress.Value = $SavedState.progressValue
                    }
                    if ($SavedState.ContainsKey('progressVisible')) {
                        $State.Controls.pbOverallProgress.Visibility = $SavedState.progressVisible
                    }
                }
                catch {
                    if ($logAvailable) {
                        WriteLog "Restore-FFUUIState: Warning - Failed to restore progress bar: $($_.Exception.Message)"
                    }
                }
            }

            if ($null -ne $State.Controls.txtStatus) {
                try {
                    if ($SavedState.ContainsKey('statusText')) {
                        $State.Controls.txtStatus.Text = $SavedState.statusText
                    }
                }
                catch {
                    if ($logAvailable) {
                        WriteLog "Restore-FFUUIState: Warning - Failed to restore status text: $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    end {
        if ($logAvailable) {
            WriteLog "Restore-FFUUIState: UI state restored."
        }
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Reset-FFUUIToIdle'
    'Save-FFUUIState'
    'Restore-FFUUIState'
)
