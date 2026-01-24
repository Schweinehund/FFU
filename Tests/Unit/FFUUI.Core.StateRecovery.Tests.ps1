#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for FFUUI.Core.StateRecovery module.

.DESCRIPTION
    Comprehensive tests covering Reset-FFUUIToIdle, Save-FFUUIState, and Restore-FFUUIState
    functions. Tests verify normal operation and edge cases including null controls,
    missing keys, and defensive error handling.

.NOTES
    Author: Claude Code
    Version: 1.0.0
    Created: 2026-01-24
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\FFUUI.Core\FFUUI.Core.StateRecovery.psm1"
    Import-Module $modulePath -Force

    # Helper function to create a mock UI state object matching BuildFFUVM_UI.ps1 structure
    function New-MockUIState {
        param(
            [bool]$IsBuilding = $true,
            [bool]$IsCleanupRunning = $true,
            [string]$ButtonContent = "Cancel",
            [bool]$ButtonEnabled = $false,
            [int]$ProgressValue = 50,
            [string]$ProgressVisibility = 'Visible',
            [string]$StatusText = "Building...",
            [bool]$IncludePollTimer = $true,
            [bool]$IncludeMessagingContext = $true
        )

        $state = [PSCustomObject]@{
            Controls = @{
                btnRun = [PSCustomObject]@{
                    IsEnabled = $ButtonEnabled
                    Content   = $ButtonContent
                }
                pbOverallProgress = [PSCustomObject]@{
                    Visibility = $ProgressVisibility
                    Value      = $ProgressValue
                }
                txtStatus = [PSCustomObject]@{
                    Text = $StatusText
                }
            }
            Flags = @{
                isBuilding       = $IsBuilding
                isCleanupRunning = $IsCleanupRunning
            }
            Data = @{
                pollTimer        = $null
                messagingContext = $null
                currentBuildJob  = "MockJob"
            }
        }

        if ($IncludePollTimer) {
            $state.Data.pollTimer = [PSCustomObject]@{
                IsEnabled = $true
            }
            # Add Stop method mock
            $state.Data.pollTimer | Add-Member -MemberType ScriptMethod -Name Stop -Value { } -Force
        }

        if ($IncludeMessagingContext) {
            $state.Data.messagingContext = @{ SomeKey = "value" }
        }

        return $state
    }

    # Helper function to create minimal state for edge case testing
    function New-MinimalUIState {
        return [PSCustomObject]@{
            Controls = @{}
            Flags    = @{}
            Data     = @{}
        }
    }
}

Describe 'Reset-FFUUIToIdle' {
    Context 'Progress Bar Reset' {
        It 'Should hide progress bar (set Visibility to Collapsed)' {
            $state = New-MockUIState -ProgressVisibility 'Visible'

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Controls.pbOverallProgress.Visibility | Should -Be 'Collapsed'
        }

        It 'Should reset progress bar value to 0' {
            $state = New-MockUIState -ProgressValue 75

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Controls.pbOverallProgress.Value | Should -Be 0
        }
    }

    Context 'Build Button Reset' {
        It 'Should re-enable build button' {
            $state = New-MockUIState -ButtonEnabled $false

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Controls.btnRun.IsEnabled | Should -BeTrue
        }

        It 'Should set build button content to "Build FFU"' {
            $state = New-MockUIState -ButtonContent "Cancel"

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Controls.btnRun.Content | Should -Be "Build FFU"
        }
    }

    Context 'Flag Reset' {
        It 'Should reset isBuilding flag to false' {
            $state = New-MockUIState -IsBuilding $true

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Flags.isBuilding | Should -BeFalse
        }

        It 'Should reset isCleanupRunning flag to false' {
            $state = New-MockUIState -IsCleanupRunning $true

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Flags.isCleanupRunning | Should -BeFalse
        }
    }

    Context 'Status Text' {
        It 'Should set status text to provided message' {
            $state = New-MockUIState -StatusText "Building..."
            $expectedMessage = "Build failed. Check log for details."

            Reset-FFUUIToIdle -State $state -StatusMessage $expectedMessage

            $state.Controls.txtStatus.Text | Should -Be $expectedMessage
        }

        It 'Should use default "Ready" message when not specified' {
            $state = New-MockUIState -StatusText "Building..."

            Reset-FFUUIToIdle -State $state

            $state.Controls.txtStatus.Text | Should -Be "Ready"
        }
    }

    Context 'Poll Timer Handling' {
        It 'Should stop poll timer if running' {
            $state = New-MockUIState -IncludePollTimer $true
            $timerStopped = $false
            $state.Data.pollTimer | Add-Member -MemberType ScriptMethod -Name Stop -Value { $script:timerStopped = $true } -Force

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Data.pollTimer | Should -BeNullOrEmpty
        }

        It 'Should null the poll timer reference' {
            $state = New-MockUIState -IncludePollTimer $true

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Data.pollTimer | Should -BeNullOrEmpty
        }
    }

    Context 'Messaging Context Handling' {
        It 'Should null the messaging context reference' {
            $state = New-MockUIState -IncludeMessagingContext $true

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Data.messagingContext | Should -BeNullOrEmpty
        }
    }

    Context 'Current Build Job' {
        It 'Should null the currentBuildJob reference' {
            $state = New-MockUIState
            $state.Data.currentBuildJob = "SomeJob"

            Reset-FFUUIToIdle -State $state -StatusMessage "Test"

            $state.Data.currentBuildJob | Should -BeNullOrEmpty
        }
    }

    Context 'Null Control Handling (Defensive Coding)' {
        It 'Should handle null Controls gracefully' {
            $state = [PSCustomObject]@{
                Controls = $null
                Flags    = @{ isBuilding = $true; isCleanupRunning = $true }
                Data     = @{ pollTimer = $null; messagingContext = $null }
            }

            { Reset-FFUUIToIdle -State $state -StatusMessage "Test" } | Should -Not -Throw
        }

        It 'Should handle null pbOverallProgress gracefully' {
            $state = [PSCustomObject]@{
                Controls = @{
                    btnRun            = [PSCustomObject]@{ IsEnabled = $false; Content = "Cancel" }
                    pbOverallProgress = $null
                    txtStatus         = [PSCustomObject]@{ Text = "Building..." }
                }
                Flags = @{ isBuilding = $true; isCleanupRunning = $true }
                Data  = @{ pollTimer = $null; messagingContext = $null }
            }

            { Reset-FFUUIToIdle -State $state -StatusMessage "Test" } | Should -Not -Throw
            $state.Controls.btnRun.IsEnabled | Should -BeTrue
        }

        It 'Should handle null btnRun gracefully' {
            $state = [PSCustomObject]@{
                Controls = @{
                    btnRun            = $null
                    pbOverallProgress = [PSCustomObject]@{ Visibility = 'Visible'; Value = 50 }
                    txtStatus         = [PSCustomObject]@{ Text = "Building..." }
                }
                Flags = @{ isBuilding = $true; isCleanupRunning = $true }
                Data  = @{ pollTimer = $null; messagingContext = $null }
            }

            { Reset-FFUUIToIdle -State $state -StatusMessage "Test" } | Should -Not -Throw
            $state.Controls.pbOverallProgress.Visibility | Should -Be 'Collapsed'
        }

        It 'Should handle null txtStatus gracefully' {
            $state = [PSCustomObject]@{
                Controls = @{
                    btnRun            = [PSCustomObject]@{ IsEnabled = $false; Content = "Cancel" }
                    pbOverallProgress = [PSCustomObject]@{ Visibility = 'Visible'; Value = 50 }
                    txtStatus         = $null
                }
                Flags = @{ isBuilding = $true; isCleanupRunning = $true }
                Data  = @{ pollTimer = $null; messagingContext = $null }
            }

            { Reset-FFUUIToIdle -State $state -StatusMessage "Test" } | Should -Not -Throw
            $state.Controls.btnRun.IsEnabled | Should -BeTrue
        }

        It 'Should handle null Flags gracefully' {
            $state = [PSCustomObject]@{
                Controls = @{
                    btnRun            = [PSCustomObject]@{ IsEnabled = $false; Content = "Cancel" }
                    pbOverallProgress = [PSCustomObject]@{ Visibility = 'Visible'; Value = 50 }
                    txtStatus         = [PSCustomObject]@{ Text = "Building..." }
                }
                Flags = $null
                Data  = @{ pollTimer = $null; messagingContext = $null }
            }

            { Reset-FFUUIToIdle -State $state -StatusMessage "Test" } | Should -Not -Throw
        }

        It 'Should handle null Data gracefully' {
            $state = [PSCustomObject]@{
                Controls = @{
                    btnRun            = [PSCustomObject]@{ IsEnabled = $false; Content = "Cancel" }
                    pbOverallProgress = [PSCustomObject]@{ Visibility = 'Visible'; Value = 50 }
                    txtStatus         = [PSCustomObject]@{ Text = "Building..." }
                }
                Flags = @{ isBuilding = $true; isCleanupRunning = $true }
                Data  = $null
            }

            { Reset-FFUUIToIdle -State $state -StatusMessage "Test" } | Should -Not -Throw
        }
    }
}

Describe 'Save-FFUUIState' {
    Context 'State Capture' {
        It 'Should capture all relevant state properties' {
            $state = New-MockUIState -IsBuilding $true -IsCleanupRunning $false `
                -ButtonContent "Cancel" -ButtonEnabled $false `
                -ProgressValue 75 -ProgressVisibility 'Visible' `
                -StatusText "Building..."

            $savedState = Save-FFUUIState -State $state

            $savedState.isBuilding | Should -BeTrue
            $savedState.isCleanupRunning | Should -BeFalse
            $savedState.btnRunContent | Should -Be "Cancel"
            $savedState.btnRunEnabled | Should -BeFalse
            $savedState.progressValue | Should -Be 75
            $savedState.progressVisible | Should -Be 'Visible'
            $savedState.statusText | Should -Be "Building..."
        }

        It 'Should return hashtable with expected keys' {
            $state = New-MockUIState

            $savedState = Save-FFUUIState -State $state

            $savedState | Should -BeOfType [hashtable]
            $savedState.ContainsKey('isBuilding') | Should -BeTrue
            $savedState.ContainsKey('isCleanupRunning') | Should -BeTrue
            $savedState.ContainsKey('btnRunContent') | Should -BeTrue
            $savedState.ContainsKey('btnRunEnabled') | Should -BeTrue
            $savedState.ContainsKey('progressValue') | Should -BeTrue
            $savedState.ContainsKey('progressVisible') | Should -BeTrue
            $savedState.ContainsKey('statusText') | Should -BeTrue
        }
    }

    Context 'Null Control Handling' {
        It 'Should return defaults when Controls is null' {
            $state = [PSCustomObject]@{
                Controls = $null
                Flags    = @{ isBuilding = $true; isCleanupRunning = $false }
                Data     = @{}
            }

            $savedState = Save-FFUUIState -State $state

            $savedState.isBuilding | Should -BeTrue
            $savedState.isCleanupRunning | Should -BeFalse
            # Control values should have defaults
            $savedState.btnRunContent | Should -Be "Build FFU"
            $savedState.btnRunEnabled | Should -BeTrue
            $savedState.progressValue | Should -Be 0
            $savedState.progressVisible | Should -Be 'Collapsed'
            $savedState.statusText | Should -Be "Ready"
        }

        It 'Should return defaults when Flags is null' {
            $state = [PSCustomObject]@{
                Controls = @{
                    btnRun            = [PSCustomObject]@{ IsEnabled = $false; Content = "Cancel" }
                    pbOverallProgress = [PSCustomObject]@{ Visibility = 'Visible'; Value = 50 }
                    txtStatus         = [PSCustomObject]@{ Text = "Building..." }
                }
                Flags = $null
                Data  = @{}
            }

            $savedState = Save-FFUUIState -State $state

            $savedState.isBuilding | Should -BeFalse
            $savedState.isCleanupRunning | Should -BeFalse
            # Control values should be captured
            $savedState.btnRunContent | Should -Be "Cancel"
            $savedState.progressValue | Should -Be 50
        }

        It 'Should handle null individual controls' {
            $state = [PSCustomObject]@{
                Controls = @{
                    btnRun            = $null
                    pbOverallProgress = $null
                    txtStatus         = $null
                }
                Flags = @{ isBuilding = $true; isCleanupRunning = $true }
                Data  = @{}
            }

            $savedState = Save-FFUUIState -State $state

            # Should not throw and return defaults for controls
            $savedState.btnRunContent | Should -Be "Build FFU"
            $savedState.progressValue | Should -Be 0
            $savedState.statusText | Should -Be "Ready"
        }
    }
}

Describe 'Restore-FFUUIState' {
    Context 'State Restoration' {
        It 'Should restore saved state correctly' {
            # Start with "building" state
            $state = New-MockUIState -IsBuilding $true -ButtonContent "Cancel"

            # Save an "idle" state
            $savedState = @{
                isBuilding       = $false
                isCleanupRunning = $false
                btnRunContent    = "Build FFU"
                btnRunEnabled    = $true
                progressValue    = 0
                progressVisible  = 'Collapsed'
                statusText       = "Ready"
            }

            Restore-FFUUIState -State $state -SavedState $savedState

            $state.Flags.isBuilding | Should -BeFalse
            $state.Flags.isCleanupRunning | Should -BeFalse
            $state.Controls.btnRun.Content | Should -Be "Build FFU"
            $state.Controls.btnRun.IsEnabled | Should -BeTrue
            $state.Controls.pbOverallProgress.Value | Should -Be 0
            $state.Controls.pbOverallProgress.Visibility | Should -Be 'Collapsed'
            $state.Controls.txtStatus.Text | Should -Be "Ready"
        }
    }

    Context 'Missing Keys Handling' {
        It 'Should handle missing keys gracefully' {
            $state = New-MockUIState -IsBuilding $true -ButtonContent "Cancel"
            $originalContent = $state.Controls.btnRun.Content

            # SavedState with only some keys
            $savedState = @{
                isBuilding = $false
            }

            { Restore-FFUUIState -State $state -SavedState $savedState } | Should -Not -Throw

            $state.Flags.isBuilding | Should -BeFalse
            # Other values should remain unchanged
            $state.Controls.btnRun.Content | Should -Be $originalContent
        }

        It 'Should handle empty SavedState hashtable' {
            $state = New-MockUIState -IsBuilding $true
            $originalIsBuilding = $state.Flags.isBuilding

            $savedState = @{}

            { Restore-FFUUIState -State $state -SavedState $savedState } | Should -Not -Throw

            # State should remain unchanged
            $state.Flags.isBuilding | Should -Be $originalIsBuilding
        }
    }

    Context 'Null Control Handling' {
        It 'Should handle null Controls gracefully' {
            $state = [PSCustomObject]@{
                Controls = $null
                Flags    = @{ isBuilding = $true; isCleanupRunning = $true }
                Data     = @{}
            }

            $savedState = @{
                isBuilding       = $false
                isCleanupRunning = $false
                btnRunContent    = "Build FFU"
            }

            { Restore-FFUUIState -State $state -SavedState $savedState } | Should -Not -Throw
            $state.Flags.isBuilding | Should -BeFalse
        }

        It 'Should handle null individual controls' {
            $state = [PSCustomObject]@{
                Controls = @{
                    btnRun            = $null
                    pbOverallProgress = [PSCustomObject]@{ Visibility = 'Visible'; Value = 50 }
                    txtStatus         = $null
                }
                Flags = @{ isBuilding = $true; isCleanupRunning = $true }
                Data  = @{}
            }

            $savedState = @{
                isBuilding      = $false
                progressValue   = 0
                progressVisible = 'Collapsed'
            }

            { Restore-FFUUIState -State $state -SavedState $savedState } | Should -Not -Throw
            $state.Controls.pbOverallProgress.Value | Should -Be 0
            $state.Controls.pbOverallProgress.Visibility | Should -Be 'Collapsed'
        }
    }
}

Describe 'Integration Scenarios' {
    Context 'Save and Restore Cycle' {
        It 'Should successfully save and restore state' {
            $state = New-MockUIState -IsBuilding $false -ButtonContent "Build FFU" -ButtonEnabled $true -ProgressValue 0 -ProgressVisibility 'Collapsed' -StatusText "Ready"

            # Save initial idle state
            $savedState = Save-FFUUIState -State $state

            # Simulate starting a build
            $state.Flags.isBuilding = $true
            $state.Controls.btnRun.Content = "Cancel"
            $state.Controls.btnRun.IsEnabled = $false
            $state.Controls.pbOverallProgress.Value = 50
            $state.Controls.pbOverallProgress.Visibility = 'Visible'
            $state.Controls.txtStatus.Text = "Building..."

            # Restore to saved state
            Restore-FFUUIState -State $state -SavedState $savedState

            # Verify restoration
            $state.Flags.isBuilding | Should -BeFalse
            $state.Controls.btnRun.Content | Should -Be "Build FFU"
            $state.Controls.btnRun.IsEnabled | Should -BeTrue
            $state.Controls.pbOverallProgress.Value | Should -Be 0
            $state.Controls.pbOverallProgress.Visibility | Should -Be 'Collapsed'
            $state.Controls.txtStatus.Text | Should -Be "Ready"
        }
    }

    Context 'Reset After Error Scenario' {
        It 'Should properly reset UI after simulated error' {
            # Start with building state
            $state = New-MockUIState -IsBuilding $true -ButtonContent "Cancel" -ButtonEnabled $false -ProgressValue 75 -ProgressVisibility 'Visible' -StatusText "Building Windows image..."

            # Simulate error and reset
            Reset-FFUUIToIdle -State $state -StatusMessage "Build failed. Check log for details."

            # Verify all controls are reset
            $state.Flags.isBuilding | Should -BeFalse
            $state.Flags.isCleanupRunning | Should -BeFalse
            $state.Controls.btnRun.Content | Should -Be "Build FFU"
            $state.Controls.btnRun.IsEnabled | Should -BeTrue
            $state.Controls.pbOverallProgress.Value | Should -Be 0
            $state.Controls.pbOverallProgress.Visibility | Should -Be 'Collapsed'
            $state.Controls.txtStatus.Text | Should -Be "Build failed. Check log for details."
            $state.Data.pollTimer | Should -BeNullOrEmpty
            $state.Data.messagingContext | Should -BeNullOrEmpty
            $state.Data.currentBuildJob | Should -BeNullOrEmpty
        }
    }
}
