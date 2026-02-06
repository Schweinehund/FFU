#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Unit tests for FFUUI.Core.Dashboard module functions

.DESCRIPTION
    Pester 5.x tests for the dashboard helper functions in FFUUI.Core.Dashboard.psm1.
    Tests cover:
    - Get-CheckCategory: Mapping FFU.Preflight check names to dashboard categories
    - Module exports: All 6 functions exported correctly
    - Update-BuildButtonState: Build button enable/disable logic with mock state

    WPF-dependent functions (Update-DashboardCheckUI, Update-CategorySummary,
    Update-SummaryStatus, Clear-DashboardResults) are tested via mock state objects
    for their logic, not WPF rendering.

.NOTES
    Phase 46-04: Dashboard Unit Tests
    Tests validate the testable business logic extracted from dashboard functions.
#>

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\FFUDevelopment\FFUUI.Core\FFUUI.Core.Dashboard.psm1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'FFUUI.Core.Dashboard Module Exports' -Tag 'Unit', 'FFUUI.Core', 'Dashboard' {

    Context 'Function export validation' {

        It 'should export Get-CheckCategory' {
            Get-Command -Name 'Get-CheckCategory' -Module 'FFUUI.Core.Dashboard' |
                Should -Not -BeNullOrEmpty
        }

        It 'should export Update-DashboardCheckUI' {
            Get-Command -Name 'Update-DashboardCheckUI' -Module 'FFUUI.Core.Dashboard' |
                Should -Not -BeNullOrEmpty
        }

        It 'should export Update-CategorySummary' {
            Get-Command -Name 'Update-CategorySummary' -Module 'FFUUI.Core.Dashboard' |
                Should -Not -BeNullOrEmpty
        }

        It 'should export Update-SummaryStatus' {
            Get-Command -Name 'Update-SummaryStatus' -Module 'FFUUI.Core.Dashboard' |
                Should -Not -BeNullOrEmpty
        }

        It 'should export Update-BuildButtonState' {
            Get-Command -Name 'Update-BuildButtonState' -Module 'FFUUI.Core.Dashboard' |
                Should -Not -BeNullOrEmpty
        }

        It 'should export Clear-DashboardResults' {
            Get-Command -Name 'Clear-DashboardResults' -Module 'FFUUI.Core.Dashboard' |
                Should -Not -BeNullOrEmpty
        }

        It 'should export exactly 6 functions' {
            $exported = Get-Command -Module 'FFUUI.Core.Dashboard'
            $exported.Count | Should -Be 6
        }
    }
}

Describe 'Get-CheckCategory' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'CategoryMapping' {

    Context 'System category mappings' {

        $systemCases = @(
            @{ CheckName = 'Administrator'; Expected = 'System' }
            @{ CheckName = 'PowerShellVersion'; Expected = 'System' }
            @{ CheckName = 'VMResources'; Expected = 'System' }
            @{ CheckName = 'ScratchSpace'; Expected = 'System' }
        )

        It 'should map <CheckName> to <Expected>' -TestCases $systemCases {
            param($CheckName, $Expected)
            Get-CheckCategory -CheckName $CheckName | Should -Be $Expected
        }
    }

    Context 'Hypervisor category mappings' {

        $hypervisorCases = @(
            @{ CheckName = 'HyperV'; Expected = 'Hypervisor' }
            @{ CheckName = 'VmxToolkit'; Expected = 'Hypervisor' }
            @{ CheckName = 'VMwareDrivers'; Expected = 'Hypervisor' }
            @{ CheckName = 'VMwareBridgeConfig'; Expected = 'Hypervisor' }
            @{ CheckName = 'HyperVSwitchConflict'; Expected = 'Hypervisor' }
        )

        It 'should map <CheckName> to <Expected>' -TestCases $hypervisorCases {
            param($CheckName, $Expected)
            Get-CheckCategory -CheckName $CheckName | Should -Be $Expected
        }
    }

    Context 'BuildTools category mappings' {

        $buildToolsCases = @(
            @{ CheckName = 'ADK'; Expected = 'BuildTools' }
            @{ CheckName = 'WimMount'; Expected = 'BuildTools' }
            @{ CheckName = 'DiskSpace'; Expected = 'BuildTools' }
            @{ CheckName = 'DISMState'; Expected = 'BuildTools' }
            @{ CheckName = 'DISMCleanup'; Expected = 'BuildTools' }
            @{ CheckName = 'AppsISODiskSpace'; Expected = 'BuildTools' }
            @{ CheckName = 'CaptureDiskSpace'; Expected = 'BuildTools' }
        )

        It 'should map <CheckName> to <Expected>' -TestCases $buildToolsCases {
            param($CheckName, $Expected)
            Get-CheckCategory -CheckName $CheckName | Should -Be $Expected
        }
    }

    Context 'Network category mappings' {

        $networkCases = @(
            @{ CheckName = 'Network'; Expected = 'Network' }
            @{ CheckName = 'HostIPAddress'; Expected = 'Network' }
        )

        It 'should map <CheckName> to <Expected>' -TestCases $networkCases {
            param($CheckName, $Expected)
            Get-CheckCategory -CheckName $CheckName | Should -Be $Expected
        }
    }

    Context 'Optimization category mappings' {

        $optimizationCases = @(
            @{ CheckName = 'AntivirusExclusions'; Expected = 'Optimization' }
            @{ CheckName = 'Configuration'; Expected = 'Optimization' }
        )

        It 'should map <CheckName> to <Expected>' -TestCases $optimizationCases {
            param($CheckName, $Expected)
            Get-CheckCategory -CheckName $CheckName | Should -Be $Expected
        }
    }

    Context 'Default fallback behavior' {

        It 'should return System as default for unknown check names' {
            Get-CheckCategory -CheckName 'UnknownCheck' | Should -Be 'System'
        }

        It 'should return System for an arbitrary unrecognized name' {
            Get-CheckCategory -CheckName 'SomeFutureCheck' | Should -Be 'System'
        }

        It 'should return System for a name with mixed casing not in the map' {
            Get-CheckCategory -CheckName 'nonExistentCheck' | Should -Be 'System'
        }
    }

    Context 'Return type validation' {

        It 'should return a string type' {
            $result = Get-CheckCategory -CheckName 'Administrator'
            $result | Should -BeOfType [string]
        }

        It 'should return a non-empty string for known checks' {
            $result = Get-CheckCategory -CheckName 'ADK'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should return a non-empty string for unknown checks' {
            $result = Get-CheckCategory -CheckName 'Unknown'
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Update-BuildButtonState' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'BuildButton' {

    BeforeEach {
        # Create a fresh mock state object for each test
        # Mimics the $State structure used by the actual UI without WPF dependencies
        $script:mockState = [PSCustomObject]@{
            Controls = @{
                btnRun = [PSCustomObject]@{
                    IsEnabled = $true
                    ToolTip   = $null
                }
            }
            Data = @{
                dashboardWarningCount = 0
            }
        }
    }

    Context 'Critical failures disable build button' {

        It 'should disable button when critical count is greater than zero' {
            Update-BuildButtonState -State $script:mockState -CriticalCount 2 -WarningCount 0

            $script:mockState.Controls.btnRun.IsEnabled | Should -BeFalse
        }

        It 'should set error tooltip for critical failures' {
            Update-BuildButtonState -State $script:mockState -CriticalCount 3 -WarningCount 0

            $script:mockState.Controls.btnRun.ToolTip | Should -BeLike '*3 critical*'
        }

        It 'should disable button with both critical and warning counts' {
            Update-BuildButtonState -State $script:mockState -CriticalCount 1 -WarningCount 5

            $script:mockState.Controls.btnRun.IsEnabled | Should -BeFalse
        }

        It 'should set dashboardWarningCount to 0 for critical failures' {
            Update-BuildButtonState -State $script:mockState -CriticalCount 2 -WarningCount 3

            $script:mockState.Data.dashboardWarningCount | Should -Be 0
        }
    }

    Context 'Warnings enable button with warning tooltip' {

        It 'should enable button when only warnings exist' {
            # Start disabled to confirm state change
            $script:mockState.Controls.btnRun.IsEnabled = $false

            Update-BuildButtonState -State $script:mockState -CriticalCount 0 -WarningCount 3

            $script:mockState.Controls.btnRun.IsEnabled | Should -BeTrue
        }

        It 'should set warning tooltip with count' {
            Update-BuildButtonState -State $script:mockState -CriticalCount 0 -WarningCount 2

            $script:mockState.Controls.btnRun.ToolTip | Should -BeLike '*2 warning*'
        }

        It 'should store warning count in state data' {
            Update-BuildButtonState -State $script:mockState -CriticalCount 0 -WarningCount 4

            $script:mockState.Data.dashboardWarningCount | Should -Be 4
        }
    }

    Context 'All checks pass enables button with standard tooltip' {

        It 'should enable button when all checks pass' {
            $script:mockState.Controls.btnRun.IsEnabled = $false

            Update-BuildButtonState -State $script:mockState -CriticalCount 0 -WarningCount 0

            $script:mockState.Controls.btnRun.IsEnabled | Should -BeTrue
        }

        It 'should set standard build tooltip when all pass' {
            Update-BuildButtonState -State $script:mockState -CriticalCount 0 -WarningCount 0

            $script:mockState.Controls.btnRun.ToolTip | Should -Be 'Start FFU build'
        }

        It 'should reset dashboardWarningCount to 0 when all pass' {
            $script:mockState.Data.dashboardWarningCount = 5

            Update-BuildButtonState -State $script:mockState -CriticalCount 0 -WarningCount 0

            $script:mockState.Data.dashboardWarningCount | Should -Be 0
        }
    }

    Context 'Null button handling' {

        It 'should not throw when btnRun control is null' {
            $nullBtnState = [PSCustomObject]@{
                Controls = @{
                    btnRun = $null
                }
                Data = @{}
            }

            { Update-BuildButtonState -State $nullBtnState -CriticalCount 1 -WarningCount 0 } |
                Should -Not -Throw
        }
    }

    Context 'Null data handling' {

        It 'should not throw when State.Data is null' {
            $nullDataState = [PSCustomObject]@{
                Controls = @{
                    btnRun = [PSCustomObject]@{
                        IsEnabled = $true
                        ToolTip   = $null
                    }
                }
                Data = $null
            }

            { Update-BuildButtonState -State $nullDataState -CriticalCount 0 -WarningCount 0 } |
                Should -Not -Throw
        }
    }
}

AfterAll {
    Remove-Module -Name 'FFUUI.Core.Dashboard' -Force -ErrorAction SilentlyContinue
}
