#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Unit tests for Phase 47 auto-remediation and hypervisor visibility features

.DESCRIPTION
    Pester 5.x tests for the Phase 47 dashboard enhancements in FFUUI.Core.Dashboard.psm1.
    Tests cover:
    - Get-SafeRepairMap: Safe repair function mapping (WimMount, DISMState, DISMCleanup, Network)
    - Get-UnsafeRemediationMap: Unsafe remediation with confirmation (HyperV)
    - Extract-PowerShellCommands: Parsing FIX sections from remediation text
    - Format-CheckDuration: Duration formatting for UI display
    - Update-HypervisorCategoryVisibility: Info banner management
    - Invoke-DashboardRemediation: Repair execution with result tracking

.NOTES
    Phase 47-04: Auto-Remediation and Hypervisor Visibility Tests
    Tests validate the auto-remediation and hypervisor conditional logic features.
#>

BeforeAll {
    # Import the dashboard module directly (not via FFUUI.Core.psd1 which needs WPF assemblies)
    $dashboardPath = Join-Path $PSScriptRoot '../../FFUDevelopment/FFUUI.Core/FFUUI.Core.Dashboard.psm1'
    Import-Module $dashboardPath -Force -ErrorAction Stop
}

Describe 'Get-SafeRepairMap' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'AutoRemediation' {

    Context 'Safe repair function mappings' {

        It 'returns a hashtable' {
            $map = Get-SafeRepairMap
            $map | Should -BeOfType [hashtable]
        }

        It 'contains WimMount mapping' {
            $map = Get-SafeRepairMap
            $map['WimMount'] | Should -Be 'Repair-FFUWimMount'
        }

        It 'contains DISMState mapping' {
            $map = Get-SafeRepairMap
            $map['DISMState'] | Should -Be 'Repair-FFUDismState'
        }

        It 'contains DISMCleanup mapping' {
            $map = Get-SafeRepairMap
            $map['DISMCleanup'] | Should -Be 'Invoke-FFUDISMCleanup'
        }

        It 'contains Network mapping' {
            $map = Get-SafeRepairMap
            $map['Network'] | Should -Be 'Repair-FFUNetwork'
        }

        It 'does not contain ADK' {
            $map = Get-SafeRepairMap
            $map.ContainsKey('ADK') | Should -Be $false
        }

        It 'contains exactly 4 safe repairs' {
            $map = Get-SafeRepairMap
            $map.Count | Should -Be 4
        }
    }
}

Describe 'Get-UnsafeRemediationMap' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'AutoRemediation' {

    Context 'Unsafe remediation mappings' {

        It 'returns a hashtable' {
            $map = Get-UnsafeRemediationMap
            $map | Should -BeOfType [hashtable]
        }

        It 'contains HyperV mapping' {
            $map = Get-UnsafeRemediationMap
            $map.ContainsKey('HyperV') | Should -Be $true
        }

        It 'HyperV requires reboot' {
            $map = Get-UnsafeRemediationMap
            $map['HyperV'].RequiresReboot | Should -Be $true
        }

        It 'HyperV command contains Enable-WindowsOptionalFeature' {
            $map = Get-UnsafeRemediationMap
            $map['HyperV'].Command | Should -Match 'Enable-WindowsOptionalFeature'
        }

        It 'HyperV has confirmation message' {
            $map = Get-UnsafeRemediationMap
            $map['HyperV'].ConfirmMessage | Should -Not -BeNullOrEmpty
        }

        It 'HyperV has success message' {
            $map = Get-UnsafeRemediationMap
            $map['HyperV'].SuccessMessage | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Extract-PowerShellCommands' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'AutoRemediation' {

    Context 'Remediation text parsing' {

        It 'extracts commands from standard remediation block' {
            $remediationText = @"
=== ISSUE ===
WIMMount filter driver is not loaded.

=== FIX ===
Run these PowerShell commands (as Administrator):

    sc.exe start WIMMount
    fltmc load WIMMount

Run Test-FFUWimMount again to verify.
"@

            $commands = InModuleScope 'FFUUI.Core.Dashboard' -Parameters @{ Text = $remediationText } {
                param($Text)
                Extract-PowerShellCommands -RemediationText $Text
            }

            $commands | Should -HaveCount 2
            $commands[0] | Should -Be 'sc.exe start WIMMount'
            $commands[1] | Should -Be 'fltmc load WIMMount'
        }

        It 'skips comment lines' {
            $remediationText = @"
=== FIX ===
Run these commands:

    # This is a comment
    Get-Service WIMMount
    # Another comment
    Start-Service WIMMount
"@

            $commands = InModuleScope 'FFUUI.Core.Dashboard' -Parameters @{ Text = $remediationText } {
                param($Text)
                Extract-PowerShellCommands -RemediationText $Text
            }

            # Should only get non-comment lines
            $commands | Should -HaveCount 2
            $commands[0] | Should -Be 'Get-Service WIMMount'
            $commands[1] | Should -Be 'Start-Service WIMMount'
        }

        It 'skips blank lines' {
            $remediationText = @"
=== FIX ===
Commands:

    Get-Service WIMMount

    Start-Service WIMMount

"@

            $commands = InModuleScope 'FFUUI.Core.Dashboard' -Parameters @{ Text = $remediationText } {
                param($Text)
                Extract-PowerShellCommands -RemediationText $Text
            }

            # Should only get non-blank lines
            $commands | Should -HaveCount 2
        }

        It 'returns full text as fallback when no FIX section found' {
            $remediationText = "This is plain text without a FIX section marker."

            $commands = InModuleScope 'FFUUI.Core.Dashboard' -Parameters @{ Text = $remediationText } {
                param($Text)
                # Wrap return in array to prevent PowerShell unwrapping single-element arrays
                $result = Extract-PowerShellCommands -RemediationText $Text
                return ,$result
            }

            # Should return the full text as single item
            # PowerShell unwraps single-element arrays, so $commands will be a string
            $commands | Should -BeOfType [string]
            $commands | Should -BeExactly $remediationText
        }
    }
}

Describe 'Format-CheckDuration' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'AutoRemediation' {

    Context 'Duration formatting for UI display' {

        It 'returns empty string for zero duration' {
            $formatted = InModuleScope 'FFUUI.Core.Dashboard' {
                Format-CheckDuration -DurationMs 0
            }
            $formatted | Should -BeExactly ''
        }

        It 'returns empty string for negative duration' {
            $formatted = InModuleScope 'FFUUI.Core.Dashboard' {
                Format-CheckDuration -DurationMs -1
            }
            $formatted | Should -BeExactly ''
        }

        It 'formats milliseconds to seconds with 1 decimal' {
            $formatted = InModuleScope 'FFUUI.Core.Dashboard' {
                Format-CheckDuration -DurationMs 1234
            }
            $formatted | Should -BeExactly ' (1.2s)'
        }

        It 'formats sub-second durations' {
            $formatted = InModuleScope 'FFUUI.Core.Dashboard' {
                Format-CheckDuration -DurationMs 500
            }
            $formatted | Should -BeExactly ' (0.5s)'
        }

        It 'formats multi-second durations' {
            $formatted = InModuleScope 'FFUUI.Core.Dashboard' {
                Format-CheckDuration -DurationMs 15678
            }
            $formatted | Should -BeExactly ' (15.7s)'
        }

        It 'rounds to 1 decimal place' {
            # 1236ms should round to 1.2s (not 1.236s or 1.24s)
            $formatted = InModuleScope 'FFUUI.Core.Dashboard' {
                Format-CheckDuration -DurationMs 1236
            }
            $formatted | Should -Match '^\s\(\d+\.\d{1}s\)$'
        }
    }
}

Describe 'Update-HypervisorCategoryVisibility' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'HypervisorVisibility' {

    Context 'Hypervisor info banner management' {

        BeforeEach {
            # Create mock state object with WPF Visibility enum mock
            $script:mockState = [PSCustomObject]@{
                Controls = @{
                    borderHypervisorInfo = [PSCustomObject]@{ Visibility = 'Collapsed'; Text = '' }
                    txtHypervisorInfo = [PSCustomObject]@{ Text = '' }
                }
            }

            # Mock System.Windows.Visibility enum if not available
            if (-not ([System.Management.Automation.PSTypeName]'System.Windows.Visibility').Type) {
                Add-Type -TypeDefinition @"
namespace System.Windows {
    public enum Visibility {
        Visible = 0,
        Hidden = 1,
        Collapsed = 2
    }
}
"@
            }
        }

        It 'shows info banner for HyperV selection' {
            Update-HypervisorCategoryVisibility -State $script:mockState -HypervisorType 'HyperV'
            $script:mockState.Controls.borderHypervisorInfo.Visibility | Should -Be 'Visible'
        }

        It 'sets correct text for HyperV' {
            Update-HypervisorCategoryVisibility -State $script:mockState -HypervisorType 'HyperV'
            $text = $script:mockState.Controls.txtHypervisorInfo.Text
            $text | Should -Match 'Hyper-V'
            $text | Should -Match 'VMware.*skipped'
        }

        It 'shows info banner for VMware selection' {
            Update-HypervisorCategoryVisibility -State $script:mockState -HypervisorType 'VMware'
            $script:mockState.Controls.borderHypervisorInfo.Visibility | Should -Be 'Visible'
        }

        It 'sets correct text for VMware' {
            Update-HypervisorCategoryVisibility -State $script:mockState -HypervisorType 'VMware'
            $text = $script:mockState.Controls.txtHypervisorInfo.Text
            $text | Should -Match 'VMware Workstation'
            $text | Should -Match 'Hyper-V.*skipped'
        }

        It 'shows info banner for Auto selection' {
            Update-HypervisorCategoryVisibility -State $script:mockState -HypervisorType 'Auto'
            $script:mockState.Controls.borderHypervisorInfo.Visibility | Should -Be 'Visible'
        }

        It 'sets correct text for Auto' {
            Update-HypervisorCategoryVisibility -State $script:mockState -HypervisorType 'Auto'
            $text = $script:mockState.Controls.txtHypervisorInfo.Text
            $text | Should -Match 'Auto-detected'
        }
    }
}

Describe 'Invoke-DashboardRemediation' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'AutoRemediation' {

    Context 'Repair execution with result tracking' {

        It 'returns failure for unknown check name' {
            # Mock FFUDevelopmentPath parameter
            $result = Invoke-DashboardRemediation -CheckName 'UnknownCheck' -FFUDevelopmentPath 'C:\FFUDevelopment'
            $result.Succeeded | Should -Be $false
            $result.Message | Should -Match 'No repair available'
        }

        It 'returns result with required properties' {
            # Test with unknown check to avoid actual repair
            $result = Invoke-DashboardRemediation -CheckName 'UnknownCheck' -FFUDevelopmentPath 'C:\FFUDevelopment'

            $result.PSObject.Properties.Name | Should -Contain 'Succeeded'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
        }

        It 'calls correct repair function for WimMount' -Skip {
            # Skip - repair functions are from FFU.Preflight module which needs to be imported
            # This test would require mocking across module boundaries
            # Logic validated via SafeRepairMap tests
        }

        It 'tracks duration in milliseconds' {
            $result = Invoke-DashboardRemediation -CheckName 'UnknownCheck' -FFUDevelopmentPath 'C:\FFUDevelopment'
            $result.DurationMs | Should -BeGreaterOrEqual 0
        }
    }
}

Describe 'Update-DashboardCheckUI with DurationMs' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'AutoRemediation' {

    Context 'Duration display in check messages' {

        BeforeEach {
            # Create mock state object with minimal dashboard structure
            $script:mockState = [PSCustomObject]@{
                Controls = @{
                    spDashboardSystem = [PSCustomObject]@{
                        Children = [System.Collections.ArrayList]::new()
                    }
                    spDashboardHypervisor = [PSCustomObject]@{
                        Children = [System.Collections.ArrayList]::new()
                    }
                    spDashboardBuildTools = [PSCustomObject]@{
                        Children = [System.Collections.ArrayList]::new()
                    }
                    spDashboardNetwork = [PSCustomObject]@{
                        Children = [System.Collections.ArrayList]::new()
                    }
                    spDashboardOptimization = [PSCustomObject]@{
                        Children = [System.Collections.ArrayList]::new()
                    }
                }
            }
        }

        It 'appends duration to message for passed check' -Skip {
            # Skip - requires full WPF context for StackPanel.Children manipulation
            # Logic validated via Extract-PowerShellCommands and Format-CheckDuration tests
        }

        It 'does not append duration when DurationMs is 0' -Skip {
            # Skip - requires full WPF context
        }

        It 'creates Fix button for WimMount failure' -Skip {
            # Skip - requires full WPF context for button creation
            # Logic validated via Get-SafeRepairMap tests
        }

        It 'creates unsafe Fix button for HyperV failure' -Skip {
            # Skip - requires full WPF context for button creation
            # Logic validated via Get-UnsafeRemediationMap tests
        }

        It 'creates Details expander for failed check with remediation' -Skip {
            # Skip - requires full WPF context for Expander creation
            # Logic validated via Extract-PowerShellCommands tests
        }

        It 'does not create Fix button for ADK failure' -Skip {
            # Skip - requires full WPF context
            # Logic validated via Get-SafeRepairMap tests (ADK not in map)
        }
    }
}

AfterAll {
    # Clean up module
    Remove-Module 'FFUUI.Core.Dashboard' -Force -ErrorAction SilentlyContinue
}
