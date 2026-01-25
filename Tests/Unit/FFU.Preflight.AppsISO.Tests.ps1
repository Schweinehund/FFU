#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for FFU.Preflight Apps.iso disk estimation functions

.DESCRIPTION
    Tests Get-AppsISODiskEstimate and Test-FFUAppsISODiskSpace functions
    Part of Phase 29: Smart Apps.iso & Disk Estimation

.NOTES
    Version: 1.0.0
    Date: 2026-01-25
    Author: FFU Builder Team
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Preflight'

    # Import module
    Get-Module -Name 'FFU.Preflight' | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module "$ModulePath\FFU.Preflight.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Preflight' | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AppsISODiskEstimate' -Tag 'Unit', 'FFU.Preflight', 'DiskEstimate' {

    BeforeAll {
        # Create test directory structure
        $script:TestAppsPath = Join-Path $TestDrive 'Apps'
        New-Item -Path $TestAppsPath -ItemType Directory -Force | Out-Null
        New-Item -Path "$TestAppsPath\Orchestration" -ItemType Directory -Force | Out-Null
        Set-Content -Path "$TestAppsPath\Orchestration\test.ps1" -Value ('x' * 1024)  # 1KB file
    }

    Context 'Parameter Validation' {
        It 'Should require AppsPath parameter' {
            $cmd = Get-Command -Name 'Get-AppsISODiskEstimate' -Module 'FFU.Preflight'
            $param = $cmd.Parameters['AppsPath']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should require Features parameter' {
            $cmd = Get-Command -Name 'Get-AppsISODiskEstimate' -Module 'FFU.Preflight'
            $param = $cmd.Parameters['Features']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }
    }

    Context 'Basic Functionality' {
        It 'Should return PSCustomObject with expected properties' {
            $features = @{ InstallOffice = $false }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result | Should -BeOfType [PSCustomObject]
            $result.Components | Should -Not -BeNullOrEmpty
            $result.TotalContentBytes | Should -BeGreaterThan 0
            # RequiredFreeGB can be 0 for very small test files, just verify it exists
            $result.RequiredFreeGB | Should -BeGreaterOrEqual 0
        }

        It 'Should include Orchestration component' {
            $features = @{}
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.Components.Keys | Should -Contain 'Orchestration'
        }

        It 'Should use actual size when folder exists' {
            $features = @{}
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.UsedActualSizes | Should -Contain 'Orchestration'
        }

        It 'Should use estimate when folder does not exist' {
            $features = @{ InstallOffice = $true }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.UsedEstimates | Should -Contain 'Office'
        }
    }

    Context 'Feature-Based Calculation' {
        It 'Should include Office when InstallOffice is true' {
            $features = @{ InstallOffice = $true }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.Components.Keys | Should -Contain 'Office'
        }

        It 'Should NOT include Office when InstallOffice is false' {
            $features = @{ InstallOffice = $false }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.Components.Keys | Should -Not -Contain 'Office'
        }

        It 'Should include Defender when UpdateLatestDefender is true' {
            $features = @{ UpdateLatestDefender = $true }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.Components.Keys | Should -Contain 'Defender'
        }

        It 'Should calculate higher total with more features enabled' {
            $fewFeatures = @{ InstallOffice = $false }
            $manyFeatures = @{ InstallOffice = $true; UpdateLatestDefender = $true }

            $fewResult = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $fewFeatures
            $manyResult = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $manyFeatures

            $manyResult.RequiredFreeGB | Should -BeGreaterThan $fewResult.RequiredFreeGB
        }

        It 'Should include MSRT when UpdateLatestMSRT is true' {
            $features = @{ UpdateLatestMSRT = $true }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.Components.Keys | Should -Contain 'MSRT'
        }

        It 'Should include Edge when UpdateEdge is true' {
            $features = @{ UpdateEdge = $true }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.Components.Keys | Should -Contain 'Edge'
        }

        It 'Should include OneDrive when UpdateOneDrive is true' {
            $features = @{ UpdateOneDrive = $true }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.Components.Keys | Should -Contain 'OneDrive'
        }
    }

    Context 'Size Calculations' {
        It 'Should calculate RequiredFreeBytes as content + ISO + temp' {
            $features = @{}
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            # RequiredFree = Content + ISO (same as content) + Temp (0.5 * content)
            # = 2.5 * Content
            $expected = $result.TotalContentBytes + $result.ISOSizeBytes + $result.TempSpaceBytes
            $result.RequiredFreeBytes | Should -Be $expected
        }

        It 'Should have ISOSizeBytes equal to TotalContentBytes' {
            $features = @{}
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $result.ISOSizeBytes | Should -Be $result.TotalContentBytes
        }

        It 'Should have TempSpaceBytes as 50% of TotalContentBytes' {
            $features = @{}
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            $expected = [long]($result.TotalContentBytes * 0.5)
            $result.TempSpaceBytes | Should -Be $expected
        }

        It 'Should convert bytes to GB correctly' {
            $features = @{ InstallOffice = $true }  # Large enough to have meaningful GB
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            # TotalContentGB should be TotalContentBytes / 1GB rounded to 2 decimal places
            $expectedGB = [Math]::Round($result.TotalContentBytes / 1GB, 2)
            $result.TotalContentGB | Should -Be $expectedGB
        }
    }

    Context 'Metadata Tracking' {
        It 'Should track which components used actual sizes' {
            $features = @{}
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            # Can be string (single item) or array (multiple items) due to PowerShell array unwrapping
            $result.UsedActualSizes | Should -Not -BeNullOrEmpty
        }

        It 'Should track which components used estimates' {
            $features = @{ InstallOffice = $true }
            $result = Get-AppsISODiskEstimate -AppsPath $script:TestAppsPath -Features $features

            # Can be string (single item) or array (multiple items) due to PowerShell array unwrapping
            $result.UsedEstimates | Should -Not -BeNullOrEmpty
            $result.UsedEstimates | Should -Contain 'Office'
        }
    }
}

Describe 'Test-FFUAppsISODiskSpace' -Tag 'Unit', 'FFU.Preflight', 'DiskValidation' {

    BeforeAll {
        $script:TestAppsPath = Join-Path $TestDrive 'Apps'
        New-Item -Path $TestAppsPath -ItemType Directory -Force | Out-Null
        New-Item -Path "$TestAppsPath\Orchestration" -ItemType Directory -Force | Out-Null
        Set-Content -Path "$TestAppsPath\Orchestration\test.ps1" -Value ('x' * 1024)
    }

    Context 'Parameter Validation' {
        It 'Should require AppsPath parameter' {
            $cmd = Get-Command -Name 'Test-FFUAppsISODiskSpace' -Module 'FFU.Preflight'
            $param = $cmd.Parameters['AppsPath']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should require Features parameter' {
            $cmd = Get-Command -Name 'Test-FFUAppsISODiskSpace' -Module 'FFU.Preflight'
            $param = $cmd.Parameters['Features']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }
    }

    Context 'Result Structure' {
        It 'Should return FFUCheckResult-like object' {
            $features = @{}
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            $result.Status | Should -BeIn @('Passed', 'Failed', 'Warning')
            $result.Message | Should -Not -BeNullOrEmpty
            $result.Details | Should -Not -BeNullOrEmpty
        }

        It 'Should include CheckName as AppsISODiskSpace' {
            $features = @{}
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            $result.CheckName | Should -Be 'AppsISODiskSpace'
        }

        It 'Should include required details fields' {
            $features = @{}
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            $result.Details.RequiredFreeGB | Should -Not -BeNullOrEmpty
            $result.Details.AvailableFreeGB | Should -Not -BeNullOrEmpty
            $result.Details.DriveLetter | Should -Not -BeNullOrEmpty
        }

        It 'Should include component breakdown in details' {
            $features = @{}
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            $result.Details.Components | Should -Not -BeNullOrEmpty
        }

        It 'Should include estimation tracking in details' {
            $features = @{}
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            $result.Details.Keys | Should -Contain 'UsedActualSizes'
            $result.Details.Keys | Should -Contain 'UsedEstimates'
        }

        It 'Should include DurationMs' {
            $features = @{}
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            $result.DurationMs | Should -BeOfType [int]
        }
    }

    Context 'Pass/Fail Logic' {
        It 'Should pass when sufficient space available' {
            # With minimal features, should pass on most systems
            $features = @{ InstallOffice = $false }
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            # Test drive typically has plenty of space
            $result.Status | Should -Be 'Passed'
        }

        It 'Should include margin info when passed' {
            $features = @{}
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            if ($result.Status -eq 'Passed') {
                $result.Message | Should -Match 'Margin'
            }
        }

        It 'Should include Required and Available in passed message' {
            $features = @{}
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            if ($result.Status -eq 'Passed') {
                $result.Message | Should -Match 'Required'
                $result.Message | Should -Match 'Available'
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle non-existent AppsPath gracefully' {
            $features = @{}
            # Parent of TestDrive should exist
            $nonExistentPath = Join-Path $TestDrive 'NonExistent\Apps'

            { Test-FFUAppsISODiskSpace -AppsPath $nonExistentPath -Features $features } | Should -Not -Throw
        }

        It 'Should return a result even for non-existent path' {
            $features = @{}
            $nonExistentPath = Join-Path $TestDrive 'NonExistent\Apps'
            $result = Test-FFUAppsISODiskSpace -AppsPath $nonExistentPath -Features $features

            $result.Status | Should -BeIn @('Passed', 'Failed')
            $result.Details | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Integration with Get-AppsISODiskEstimate' {
        It 'Should call Get-AppsISODiskEstimate internally' {
            $features = @{ InstallOffice = $true }
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            # Verify by checking components are present (which comes from Get-AppsISODiskEstimate)
            $result.Details.Components | Should -Not -BeNullOrEmpty
            $result.Details.Components.Keys | Should -Contain 'Orchestration'
        }

        It 'Should include estimate for enabled features' {
            $features = @{ InstallOffice = $true }
            $result = Test-FFUAppsISODiskSpace -AppsPath $script:TestAppsPath -Features $features

            $result.Details.Components.Keys | Should -Contain 'Office'
        }
    }
}

Describe 'Module Export Verification' -Tag 'Unit', 'FFU.Preflight', 'Module' {

    It 'Should export Get-AppsISODiskEstimate' {
        Get-Command -Name 'Get-AppsISODiskEstimate' -Module 'FFU.Preflight' | Should -Not -BeNullOrEmpty
    }

    It 'Should export Test-FFUAppsISODiskSpace' {
        Get-Command -Name 'Test-FFUAppsISODiskSpace' -Module 'FFU.Preflight' | Should -Not -BeNullOrEmpty
    }

    It 'Should have both functions in manifest FunctionsToExport' {
        $manifest = Test-ModuleManifest -Path (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psd1')
        $manifest.ExportedFunctions.Keys | Should -Contain 'Get-AppsISODiskEstimate'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Test-FFUAppsISODiskSpace'
    }
}

Describe 'Invoke-FFUPreflight Integration' -Tag 'Integration', 'FFU.Preflight' {

    It 'Should include AppsISODiskSpace in Tier2Results when InstallApps enabled' -Skip:(-not (Test-Path 'C:\FFUDevelopment')) {
        # This test requires C:\FFUDevelopment to exist
        $features = @{ InstallApps = $true }
        $result = Invoke-FFUPreflight -Features $features -FFUDevelopmentPath 'C:\FFUDevelopment'

        $result.Tier2Results.Keys | Should -Contain 'AppsISODiskSpace'
    }

    It 'Should skip AppsISODiskSpace when InstallApps is false' -Skip:(-not (Test-Path 'C:\FFUDevelopment')) {
        $features = @{ InstallApps = $false }
        $result = Invoke-FFUPreflight -Features $features -FFUDevelopmentPath 'C:\FFUDevelopment'

        $result.Tier2Results['AppsISODiskSpace'].Status | Should -Be 'Skipped'
    }
}
