#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Unit tests for Phase 48 config-aware revalidation and diagnostics export features

.DESCRIPTION
    Pester 5.x tests for the Phase 48 dashboard enhancements in FFUUI.Core.Dashboard.psm1.
    Tests cover:
    - Get-HypervisorDependentChecks: Hypervisor-dependent check categorization (HyperV/VMware/Independent)
    - Export-DashboardDiagnostics: Timestamped diagnostics report generation
    - Set-CategoryDimmed: Visual dimming for categories during revalidation
    - Module export completeness validation

.NOTES
    Phase 48-04: Config-Aware Revalidation Tests
    Tests validate the config revalidation, diagnostics export, and dimming features.
#>

BeforeAll {
    # Import the dashboard module directly (not via FFUUI.Core.psd1 which needs WPF assemblies)
    $dashboardPath = Join-Path $PSScriptRoot '../../FFUDevelopment/FFUUI.Core/FFUUI.Core.Dashboard.psm1'
    Import-Module $dashboardPath -Force -ErrorAction Stop
}

Describe 'Get-HypervisorDependentChecks' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'ConfigRevalidation' {

    Context 'Hypervisor dependency mapping' {

        It 'returns a hashtable' {
            $result = Get-HypervisorDependentChecks
            $result | Should -BeOfType [hashtable]
        }

        It 'contains HyperV key with array' {
            $result = Get-HypervisorDependentChecks
            $result.HyperV | Should -Not -BeNullOrEmpty
            @($result.HyperV).Count | Should -BeGreaterThan 0
        }

        It 'HyperV array contains HyperV check' {
            $result = Get-HypervisorDependentChecks
            $result.HyperV | Should -Contain 'HyperV'
        }

        It 'HyperV array has exactly 1 entry' {
            $result = Get-HypervisorDependentChecks
            $result.HyperV.Count | Should -Be 1
        }

        It 'contains VMware key with array' {
            $result = Get-HypervisorDependentChecks
            $result.VMware | Should -Not -BeNullOrEmpty
            @($result.VMware).Count | Should -BeGreaterThan 0
        }

        It 'VMware array has 5 entries' {
            $result = Get-HypervisorDependentChecks
            $result.VMware.Count | Should -Be 5
        }

        It 'VMware array contains VmxToolkit' {
            $result = Get-HypervisorDependentChecks
            $result.VMware | Should -Contain 'VmxToolkit'
        }

        It 'VMware array contains VMwareBridgeConfig' {
            $result = Get-HypervisorDependentChecks
            $result.VMware | Should -Contain 'VMwareBridgeConfig'
        }

        It 'VMware array contains HostIPAddress' {
            $result = Get-HypervisorDependentChecks
            $result.VMware | Should -Contain 'HostIPAddress'
        }

        It 'VMware array contains VMwareDrivers' {
            $result = Get-HypervisorDependentChecks
            $result.VMware | Should -Contain 'VMwareDrivers'
        }

        It 'VMware array contains HyperVSwitchConflict' {
            $result = Get-HypervisorDependentChecks
            $result.VMware | Should -Contain 'HyperVSwitchConflict'
        }

        It 'contains Independent key with array' {
            $result = Get-HypervisorDependentChecks
            $result.Independent | Should -Not -BeNullOrEmpty
            @($result.Independent).Count | Should -BeGreaterThan 0
        }

        It 'Independent array has 14 entries' {
            $result = Get-HypervisorDependentChecks
            $result.Independent.Count | Should -Be 14
        }

        It 'Independent array contains Administrator' {
            $result = Get-HypervisorDependentChecks
            $result.Independent | Should -Contain 'Administrator'
        }

        It 'Independent array contains ADK' {
            $result = Get-HypervisorDependentChecks
            $result.Independent | Should -Contain 'ADK'
        }

        It 'Independent array contains WimMount' {
            $result = Get-HypervisorDependentChecks
            $result.Independent | Should -Contain 'WimMount'
        }

        It 'Independent array contains PowerShellVersion' {
            $result = Get-HypervisorDependentChecks
            $result.Independent | Should -Contain 'PowerShellVersion'
        }

        It 'Independent array does NOT contain HyperV' {
            $result = Get-HypervisorDependentChecks
            $result.Independent | Should -Not -Contain 'HyperV'
        }

        It 'Independent array does NOT contain VmxToolkit' {
            $result = Get-HypervisorDependentChecks
            $result.Independent | Should -Not -Contain 'VmxToolkit'
        }

        It 'total check count is 20 (1 + 5 + 14)' {
            $result = Get-HypervisorDependentChecks
            $totalCount = $result.HyperV.Count + $result.VMware.Count + $result.Independent.Count
            $totalCount | Should -Be 20
        }
    }
}

Describe 'Export-DashboardDiagnostics' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'ConfigRevalidation' {

    Context 'Diagnostics report generation' {

        BeforeAll {
            # Create temp directory for test
            $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "FFUTest_$(Get-Random)"
            New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

            # Create mock state object
            $script:mockState = [PSCustomObject]@{
                FFUDevelopmentPath = $script:tempDir
                Version = [PSCustomObject]@{
                    Number = '1.11.3'
                    BuildDate = '2026-02-06'
                    Modules = [PSCustomObject]@{
                        'FFU.Core' = [PSCustomObject]@{ version = '1.0.27' }
                        'FFUUI.Core' = [PSCustomObject]@{ version = '0.3.0' }
                    }
                }
                Controls = @{
                    cmbHypervisorType = [PSCustomObject]@{ SelectedIndex = 0 }
                }
                Data = @{
                    dashboardCategoryStats = @{
                        System = @{ Total = 4; Passed = 3; Failed = 1; Warning = 0 }
                        Hypervisor = @{ Total = 1; Passed = 1; Failed = 0; Warning = 0 }
                        BuildTools = @{ Total = 3; Passed = 3; Failed = 0; Warning = 0 }
                        Network = @{ Total = 2; Passed = 2; Failed = 0; Warning = 0 }
                        Optimization = @{ Total = 0; Passed = 0; Failed = 0; Warning = 0 }
                    }
                    dashboardCheckResults = @{
                        'Administrator' = @{
                            Status = 'Passed'
                            Message = 'Running as administrator'
                            Severity = 'Critical'
                            DurationMs = 50
                            Category = 'System'
                            Remediation = ''
                        }
                        'HyperV' = @{
                            Status = 'Passed'
                            Message = 'Hyper-V enabled'
                            Severity = 'Critical'
                            DurationMs = 200
                            Category = 'Hypervisor'
                            Remediation = ''
                        }
                        'ADK' = @{
                            Status = 'Failed'
                            Message = 'Windows ADK not installed'
                            Severity = 'Critical'
                            DurationMs = 150
                            Category = 'BuildTools'
                            Remediation = "=== FIX ===`n    Install-WindowsADK"
                        }
                    }
                }
            }
        }

        AfterAll {
            # Clean up temp directory
            if (Test-Path $script:tempDir) {
                Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'returns a file path string' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $result | Should -BeOfType [string]
        }

        It 'creates file in Logs subdirectory' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            Test-Path $result | Should -Be $true
            $result | Should -Match '\\Logs\\'
        }

        It 'file contains FFU BUILDER header' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match 'FFU BUILDER PRE-FLIGHT DIAGNOSTICS REPORT'
        }

        It 'file contains OS version' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match 'OS Version'
        }

        It 'file contains PowerShell version' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match 'PowerShell'
        }

        It 'file contains FFU Builder version' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match 'v1\.11\.3'
        }

        It 'file contains Hyper-V as hypervisor' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match 'Hyper-V'
        }

        It 'file contains System category results' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match '\[System\]'
        }

        It 'file contains check counts' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match 'Total:\s*4'
        }

        It 'file contains passed check results' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match '\[PASS\]'
        }

        It 'file contains failed check results' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match '\[FAIL\]'
        }

        It 'file ends with END OF REPORT' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match 'END OF REPORT'
        }

        It 'creates Logs directory if missing' {
            # Remove Logs folder if it exists
            $logsPath = Join-Path $script:tempDir 'Logs'
            if (Test-Path $logsPath) {
                Remove-Item -Path $logsPath -Recurse -Force
            }

            # Export should create it
            $result = Export-DashboardDiagnostics -State $script:mockState
            Test-Path $logsPath | Should -Be $true
        }

        It 'filename includes timestamp' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $filename = Split-Path -Leaf $result
            $filename | Should -Match 'FFU-Diagnostics-\d{4}-\d{2}-\d{2}-\d{6}\.txt'
        }

        It 'includes module versions section' {
            $result = Export-DashboardDiagnostics -State $script:mockState
            $content = Get-Content -Path $result -Raw
            $content | Should -Match 'MODULE VERSIONS'
        }
    }
}

Describe 'Set-CategoryDimmed' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'ConfigRevalidation' {

    Context 'Category dimming transitions' {

        BeforeEach {
            # Create mock state object with PSCustomObject properties
            $script:mockState = [PSCustomObject]@{
                Controls = @{
                    expHypervisor = [PSCustomObject]@{ Opacity = 1.0 }
                    txtHypervisorSummary = [PSCustomObject]@{
                        FontStyle = 'Normal'
                        Text = '(3/3)'
                    }
                }
            }

            # Mock System.Windows.FontStyles enum if not available
            if (-not ([System.Management.Automation.PSTypeName]'System.Windows.FontStyles').Type) {
                Add-Type -TypeDefinition @"
namespace System.Windows {
    public class FontStyles {
        public static string Normal = "Normal";
        public static string Italic = "Italic";
    }
}
"@
            }
        }

        It 'sets opacity to 0.5 when dimmed' {
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $true
            $script:mockState.Controls.expHypervisor.Opacity | Should -Be 0.5
        }

        It 'sets summary text to rechecking when dimmed' {
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $true
            $script:mockState.Controls.txtHypervisorSummary.Text | Should -Be '(rechecking...)'
        }

        It 'sets summary to italic when dimmed' {
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $true
            $script:mockState.Controls.txtHypervisorSummary.FontStyle | Should -Be 'Italic'
        }

        It 'restores opacity to 1.0 when undimmed' {
            # First dim
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $true
            # Then undim
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $false
            $script:mockState.Controls.expHypervisor.Opacity | Should -Be 1.0
        }

        It 'sets summary to normal font when undimmed' {
            # First dim
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $true
            # Then undim
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $false
            $script:mockState.Controls.txtHypervisorSummary.FontStyle | Should -Be 'Normal'
        }

        It 'does not change summary text when undimmed' {
            # First dim
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $true
            # Then undim (text should stay as-is, not reset to original)
            Set-CategoryDimmed -State $script:mockState -Category 'Hypervisor' -IsDimmed $false
            # Text should remain '(rechecking...)' until Update-CategorySummary sets final value
            $script:mockState.Controls.txtHypervisorSummary.Text | Should -Be '(rechecking...)'
        }

        It 'handles null expander gracefully' {
            # Create state without expander control
            $invalidState = [PSCustomObject]@{
                Controls = @{
                    expInvalidCategory = $null
                }
            }
            # Should not throw
            { Set-CategoryDimmed -State $invalidState -Category 'System' -IsDimmed $true } | Should -Not -Throw
        }
    }
}

Describe 'Module Export Completeness' -Tag 'Unit', 'FFUUI.Core', 'Dashboard', 'ConfigRevalidation' {

    Context 'Phase 48 function exports' {

        It 'exports Export-DashboardDiagnostics' {
            Get-Command Export-DashboardDiagnostics -Module FFUUI.Core.Dashboard -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'exports Get-HypervisorDependentChecks' {
            Get-Command Get-HypervisorDependentChecks -Module FFUUI.Core.Dashboard -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'exports Set-CategoryDimmed' {
            Get-Command Set-CategoryDimmed -Module FFUUI.Core.Dashboard -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'has 13 total exported functions' {
            $functions = Get-Command -Module FFUUI.Core.Dashboard -CommandType Function
            $functions.Count | Should -Be 13
        }

        It 'exported functions include Phase 46 baseline' {
            $functions = (Get-Command -Module FFUUI.Core.Dashboard -CommandType Function).Name
            $functions | Should -Contain 'Get-CheckCategory'
            $functions | Should -Contain 'Update-DashboardCheckUI'
            $functions | Should -Contain 'Update-CategorySummary'
            $functions | Should -Contain 'Update-SummaryStatus'
            $functions | Should -Contain 'Update-BuildButtonState'
            $functions | Should -Contain 'Clear-DashboardResults'
        }

        It 'exported functions include Phase 47 additions' {
            $functions = (Get-Command -Module FFUUI.Core.Dashboard -CommandType Function).Name
            $functions | Should -Contain 'Update-HypervisorCategoryVisibility'
            $functions | Should -Contain 'Invoke-DashboardRemediation'
            $functions | Should -Contain 'Get-SafeRepairMap'
            $functions | Should -Contain 'Get-UnsafeRemediationMap'
        }
    }
}

AfterAll {
    # Clean up module
    Remove-Module 'FFUUI.Core.Dashboard' -Force -ErrorAction SilentlyContinue
}
