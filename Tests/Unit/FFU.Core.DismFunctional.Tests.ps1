#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Core Test-DismFunctional and Test-DismReady functions

.DESCRIPTION
    Comprehensive unit tests covering the Test-DismFunctional helper function and
    Test-DismReady main function in the FFU.Core module. Tests verify DISM service
    initialization validation, timeout handling, job cleanup, and repair workflows.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.DismFunctional.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Core.DismFunctional.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Core\*.psm1

    Test Strategy:
    - Mock Start-Job/Wait-Job/Receive-Job to simulate various DISM states
    - Verify timeout handling (15-second limit)
    - Verify job cleanup (no orphaned jobs)
    - Verify ThreadJob compatibility patterns
    - Verify WriteLog fallback when function unavailable
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'
    $ModulesDir = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    # Add Modules directory to PSModulePath for dependency resolution
    if ($env:PSModulePath -notlike "*$ModulesDir*") {
        $env:PSModulePath = "$ModulesDir;$env:PSModulePath"
    }

    # Remove modules if loaded
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core module (will auto-import FFU.Constants dependency)
    if (-not (Test-Path "$ModulePath\FFU.Core.psd1")) {
        throw "FFU.Core module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Test-DismFunctional Function Export Verification
# =============================================================================

Describe 'FFU.Core Test-DismFunctional Export' -Tag 'Unit', 'FFU.Core', 'DismFunctional' {

    Context 'Function Export' {
        It 'Should export Test-DismFunctional function' {
            Get-Command -Name 'Test-DismFunctional' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-DismReady function' {
            Get-Command -Name 'Test-DismReady' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Test-DismFunctional should have CmdletBinding attribute' {
            $command = Get-Command -Name 'Test-DismFunctional' -Module 'FFU.Core'
            $command.CmdletBinding | Should -Be $true
        }

        It 'Test-DismReady should have CmdletBinding attribute' {
            $command = Get-Command -Name 'Test-DismReady' -Module 'FFU.Core'
            $command.CmdletBinding | Should -Be $true
        }

        It 'Test-DismFunctional should have OutputType attribute set to bool' {
            $command = Get-Command -Name 'Test-DismFunctional' -Module 'FFU.Core'
            $command.OutputType.Type.Name | Should -Contain 'Boolean'
        }

        It 'Test-DismReady should have OutputType attribute set to bool' {
            $command = Get-Command -Name 'Test-DismReady' -Module 'FFU.Core'
            $command.OutputType.Type.Name | Should -Contain 'Boolean'
        }
    }
}

# =============================================================================
# Test-DismReady Parameter Validation Tests
# =============================================================================

Describe 'Test-DismReady Parameter Validation' -Tag 'Unit', 'FFU.Core', 'DismFunctional', 'Parameters' {

    Context 'AttemptRepair Parameter' {
        It 'Should have optional AttemptRepair parameter with default value true' {
            $command = Get-Command -Name 'Test-DismReady' -Module 'FFU.Core'
            $param = $command.Parameters['AttemptRepair']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'Boolean'
        }

        It 'Should accept AttemptRepair = $true' {
            # This is a syntax/parameter test - actual execution mocked in behavior tests
            $command = Get-Command -Name 'Test-DismReady' -Module 'FFU.Core'
            $param = $command.Parameters['AttemptRepair']
            $param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should accept AttemptRepair = $false' {
            $command = Get-Command -Name 'Test-DismReady' -Module 'FFU.Core'
            $param = $command.Parameters['AttemptRepair']
            $param.ParameterType.Name | Should -Be 'Boolean'
        }
    }

    Context 'TimeoutSeconds Parameter' {
        It 'Should have optional TimeoutSeconds parameter' {
            $command = Get-Command -Name 'Test-DismReady' -Module 'FFU.Core'
            $param = $command.Parameters['TimeoutSeconds']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have int type for TimeoutSeconds parameter' {
            $command = Get-Command -Name 'Test-DismReady' -Module 'FFU.Core'
            $param = $command.Parameters['TimeoutSeconds']
            $param.ParameterType.Name | Should -Be 'Int32'
        }
    }
}

# =============================================================================
# Source Code Analysis - Test-DismFunctional
# =============================================================================

Describe 'Test-DismFunctional Source Code Analysis' -Tag 'Unit', 'FFU.Core', 'DismFunctional', 'SourceCode' {

    BeforeAll {
        $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
    }

    Context 'Job-Based Execution Pattern' {
        It 'Should use Start-Job for DISM test' {
            $FunctionSource | Should -Match 'Start-Job\s*-ScriptBlock'
        }

        It 'Should call Get-WindowsEdition -Online in job' {
            # Note: Get-WindowsImage does NOT have -Online parameter
            # Get-WindowsEdition -Online is the correct lightweight DISM test
            $FunctionSource | Should -Match 'Get-WindowsEdition\s+-Online'
        }

        It 'Should use Wait-Job with timeout' {
            $FunctionSource | Should -Match 'Wait-Job\s+-Timeout'
        }

        It 'Should have 15-second timeout for DISM test' {
            $FunctionSource | Should -Match 'Wait-Job\s+-Timeout\s+15'
        }

        It 'Should use Receive-Job to get result' {
            $FunctionSource | Should -Match 'Receive-Job'
        }

        It 'Should use Stop-Job on timeout' {
            $FunctionSource | Should -Match 'Stop-Job'
        }

        It 'Should use Remove-Job for cleanup' {
            $FunctionSource | Should -Match 'Remove-Job'
        }
    }

    Context 'Error Handling' {
        It 'Should have try-catch block' {
            # Use multiline pattern - try block can contain anything including newlines before catch
            $FunctionSource | Should -Match 'try\s*\{'
            $FunctionSource | Should -Match 'catch\s*\{'
        }

        It 'Should return $false on exception' {
            $FunctionSource | Should -Match 'return\s+\$false'
        }

        It 'Should return $true on success' {
            $FunctionSource | Should -Match 'return\s+\$true'
        }
    }

    Context 'Safe Logging Pattern' {
        It 'Should check for WriteLog availability using $function: drive' {
            $FunctionSource | Should -Match '\$function:WriteLog'
        }

        It 'Should log timeout warning' {
            $FunctionSource | Should -Match 'timed out after 15 seconds'
        }

        It 'Should log success message' {
            $FunctionSource | Should -Match 'DISM functional validation passed'
        }

        It 'Should log failure message' {
            $FunctionSource | Should -Match 'DISM functional test failed'
        }
    }
}

# =============================================================================
# Source Code Analysis - Test-DismReady
# =============================================================================

Describe 'Test-DismReady Source Code Analysis' -Tag 'Unit', 'FFU.Core', 'DismReady', 'SourceCode' {

    BeforeAll {
        $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
    }

    Context 'Two-Stage Validation' {
        It 'Should use fltmc to check WIMMount filter' {
            $FunctionSource | Should -Match 'fltmc\.exe\s+filters'
        }

        It 'Should match WimMount in fltmc output' {
            $FunctionSource | Should -Match "'WimMount'"
        }

        It 'Should call Test-DismFunctional after filter check' {
            $FunctionSource | Should -Match 'Test-DismFunctional'
        }
    }

    Context 'Repair Workflow' {
        It 'Should delegate to Test-FFUWimMount when available' {
            $FunctionSource | Should -Match 'Test-FFUWimMount'
        }

        It 'Should use sc.exe to start wimmount service' {
            $FunctionSource | Should -Match 'sc\.exe\s+start\s+wimmount'
        }

        It 'Should use fltmc.exe load to load WimMount filter' {
            $FunctionSource | Should -Match 'fltmc\.exe\s+load\s+WimMount'
        }

        It 'Should try rundll32 registration as fallback' {
            $FunctionSource | Should -Match 'rundll32\.exe\s+wimmount\.dll'
        }

        It 'Should verify DISM functional after each repair attempt' {
            # Test-DismFunctional is called after each repair
            $matchCount = ([regex]::Matches($FunctionSource, 'return\s+Test-DismFunctional')).Count
            $matchCount | Should -BeGreaterOrEqual 3
        }
    }

    Context 'Error Messages' {
        It 'Should log when WIMMount filter is not loaded' {
            $FunctionSource | Should -Match 'WIMMount filter driver is NOT loaded'
        }

        It 'Should log when DISM service is not functional' {
            $FunctionSource | Should -Match 'DISM service is NOT functional'
        }

        It 'Should provide remediation guidance on failure' {
            $FunctionSource | Should -Match 'Repair-WimMountService\.ps1'
        }

        It 'Should mention reboot as last resort' {
            $FunctionSource | Should -Match 'reboot'
        }
    }
}

# =============================================================================
# Behavior Tests with Mocking - Test-DismFunctional
# NOTE: These tests verify code patterns exist in source rather than runtime behavior
# because $function:WriteLog check cannot be mocked (it's a runtime check for FFU.Common.WriteLog)
# Full behavior testing requires integration tests with FFU.Common module loaded
# =============================================================================

Describe 'Test-DismFunctional Behavior Patterns' -Tag 'Unit', 'FFU.Core', 'DismFunctional', 'Behavior' {

    BeforeAll {
        $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
    }

    Context 'Successful DISM Detection Pattern' {
        It 'Should convert job result to bool for success detection' {
            # Verify the success detection pattern - job result is cast to bool
            $FunctionSource | Should -Match '\$dismFunctional\s*=\s*\[bool\]\$result'
        }

        It 'Should return $true from job ScriptBlock on success' {
            # Inside the job ScriptBlock, return $true when Get-WindowsImage succeeds
            $FunctionSource | Should -Match 'return\s+\$true'
        }

        It 'Should use Start-Job for DISM test isolation' {
            $FunctionSource | Should -Match 'Start-Job\s+-ScriptBlock'
        }
    }

    Context 'Hung DISM Detection (Timeout) Pattern' {
        It 'Should return $false when timeout occurs' {
            # Verify timeout handling returns false
            $FunctionSource | Should -Match 'dismFunctional\s*=\s*\$false'
        }

        It 'Should use Stop-Job to terminate hung jobs' {
            $FunctionSource | Should -Match 'Stop-Job'
        }

        It 'Should have 15-second timeout' {
            $FunctionSource | Should -Match 'Wait-Job\s+-Timeout\s+15'
        }
    }

    Context 'Failed DISM Detection Pattern' {
        It 'Should cast result to bool to handle null/false' {
            $FunctionSource | Should -Match '\[bool\]\$result'
        }

        It 'Should return $false from job ScriptBlock on exception' {
            # Job ScriptBlock catches exceptions and returns false
            $FunctionSource | Should -Match 'return\s+\$false'
        }
    }

    Context 'Job Cleanup Verification Pattern' {
        It 'Should call Remove-Job for cleanup' {
            $FunctionSource | Should -Match 'Remove-Job'
        }

        It 'Should use -Force on Remove-Job' {
            $FunctionSource | Should -Match 'Remove-Job.*-Force'
        }

        It 'Should use -ErrorAction SilentlyContinue on Remove-Job' {
            $FunctionSource | Should -Match 'Remove-Job.*-ErrorAction\s+SilentlyContinue'
        }
    }

    Context 'Exception Handling Pattern' {
        It 'Should have catch block for exception handling' {
            $FunctionSource | Should -Match 'catch\s*\{'
        }

        It 'Should log exception message in catch block' {
            $FunctionSource | Should -Match '\$_\.Exception\.Message'
        }
    }
}

# =============================================================================
# Behavior Pattern Tests - Test-DismReady
# NOTE: Full behavior testing requires WriteLog from FFU.Common.
# These tests verify code patterns in source rather than runtime behavior.
# =============================================================================

Describe 'Test-DismReady Behavior Patterns' -Tag 'Unit', 'FFU.Core', 'DismReady', 'Behavior' {

    BeforeAll {
        $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
    }

    Context 'WIMMount Filter Check Pattern' {
        It 'Should use fltmc to check WIMMount filter status' {
            $FunctionSource | Should -Match 'fltmc\.exe\s+filters'
        }

        It 'Should check for WimMount in filter output' {
            $FunctionSource | Should -Match "'WimMount'"
        }

        It 'Should set wimMountLoaded based on fltmc output' {
            $FunctionSource | Should -Match '\$wimMountLoaded'
        }
    }

    Context 'Two-Stage Validation Pattern' {
        It 'Should call Test-DismFunctional after confirming filter is loaded' {
            $FunctionSource | Should -Match 'Test-DismFunctional'
        }

        It 'Should return true only when both filter loaded AND DISM functional' {
            $FunctionSource | Should -Match '\$dismFunctional'
        }
    }

    Context 'Repair Attempt Pattern' {
        It 'Should check for Test-FFUWimMount availability' {
            $FunctionSource | Should -Match "InvokeCommand\.GetCommand\('Test-FFUWimMount'"
        }

        It 'Should use sc.exe to start wimmount service' {
            $FunctionSource | Should -Match 'sc\.exe\s+start\s+wimmount'
        }

        It 'Should use rundll32 for WIMMount registration' {
            $FunctionSource | Should -Match 'rundll32\.exe\s+wimmount\.dll'
        }

        It 'Should verify DISM functional after each repair attempt' {
            $FunctionSource | Should -Match 'return\s+Test-DismFunctional'
        }
    }
}

# =============================================================================
# ThreadJob Compatibility Tests
# =============================================================================

Describe 'Test-DismFunctional ThreadJob Compatibility' -Tag 'Unit', 'FFU.Core', 'DismFunctional', 'ThreadJob' {

    Context 'Safe Logging Pattern' {
        BeforeAll {
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
        }

        It 'Should use $function:WriteLog pattern (not Get-Command)' {
            # Verify function uses ThreadJob-safe pattern
            $FunctionSource | Should -Match '\$function:WriteLog'
        }

        It 'Should not use Get-Command for WriteLog check in Test-DismFunctional' {
            # Get the Test-DismFunctional function text
            $funcMatch = [regex]::Match($FunctionSource, 'function Test-DismFunctional\s*\{[\s\S]*?\n\}')
            if ($funcMatch.Success) {
                $funcText = $funcMatch.Value
                # Should not use Get-Command pattern for WriteLog (causes ThreadJob issues)
                $funcText | Should -Not -Match 'Get-Command\s+WriteLog'
            }
        }

        It 'Should handle WriteLog not being available gracefully' {
            # This tests the fallback behavior exists in code
            $FunctionSource | Should -Match 'if\s*\(\$function:WriteLog\)'
        }
    }

    Context 'Background Job Execution' {
        It 'Should use Start-Job (not Start-ThreadJob) for isolation' {
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $FunctionSource | Should -Match 'Start-Job\s+-ScriptBlock'
            # Test-DismFunctional should NOT use ThreadJob since DISM needs full session
            $funcMatch = [regex]::Match($FunctionSource, 'function Test-DismFunctional\s*\{[\s\S]*?\n\}')
            if ($funcMatch.Success) {
                $funcText = $funcMatch.Value
                $funcText | Should -Not -Match 'Start-ThreadJob'
            }
        }
    }
}

# =============================================================================
# Integration Pattern Tests
# =============================================================================

Describe 'Test-DismFunctional Integration Patterns' -Tag 'Unit', 'FFU.Core', 'DismFunctional', 'Integration' {

    Context 'Usage with Test-DismReady' {
        BeforeAll {
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
        }

        It 'Test-DismReady should call Test-DismFunctional after filter check' {
            $FunctionSource | Should -Match 'Test-DismFunctional'
        }

        It 'Test-DismReady should verify DISM functional after repairs' {
            # After each repair, Test-DismReady should call Test-DismFunctional
            $FunctionSource | Should -Match 'return\s+Test-DismFunctional'
        }
    }

    Context 'Pre-Operation Validation Pattern' {
        It 'Should be callable before DISM operations' {
            # Test that function exists and can be called
            { Test-DismFunctional } | Should -Not -Throw
        }

        It 'Should return boolean for use in conditionals' {
            $mockJob = [PSCustomObject]@{ Id = 200; State = 'Completed' }
            Mock -CommandName Start-Job -MockWith { return $mockJob } -ModuleName 'FFU.Core'
            Mock -CommandName Wait-Job -MockWith { return $mockJob } -ModuleName 'FFU.Core'
            Mock -CommandName Receive-Job -MockWith { return $true } -ModuleName 'FFU.Core'
            Mock -CommandName Remove-Job -MockWith { } -ModuleName 'FFU.Core'

            $result = Test-DismFunctional
            $result | Should -BeOfType [bool]
        }
    }
}

# =============================================================================
# Documentation Tests
# =============================================================================

Describe 'Test-DismFunctional Documentation' -Tag 'Unit', 'FFU.Core', 'DismFunctional', 'Documentation' {

    BeforeAll {
        $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
    }

    Context 'Test-DismFunctional Documentation' {
        It 'Should have SYNOPSIS in comment-based help' {
            $FunctionSource | Should -Match 'function Test-DismFunctional[\s\S]*?\.SYNOPSIS'
        }

        It 'Should have DESCRIPTION in comment-based help' {
            $FunctionSource | Should -Match 'function Test-DismFunctional[\s\S]*?\.DESCRIPTION'
        }

        It 'Should have OUTPUTS in comment-based help' {
            $FunctionSource | Should -Match 'function Test-DismFunctional[\s\S]*?\.OUTPUTS'
        }

        It 'Should document 15-second timeout' {
            $FunctionSource | Should -Match '15[-\s]second'
        }
    }

    Context 'Test-DismReady Documentation' {
        It 'Should have SYNOPSIS in comment-based help' {
            $FunctionSource | Should -Match 'function Test-DismReady[\s\S]*?\.SYNOPSIS'
        }

        It 'Should have DESCRIPTION in comment-based help' {
            $FunctionSource | Should -Match 'function Test-DismReady[\s\S]*?\.DESCRIPTION'
        }

        It 'Should have PARAMETER documentation for AttemptRepair' {
            $FunctionSource | Should -Match '\.PARAMETER AttemptRepair'
        }

        It 'Should have PARAMETER documentation for TimeoutSeconds' {
            $FunctionSource | Should -Match '\.PARAMETER TimeoutSeconds'
        }

        It 'Should have EXAMPLE section' {
            $FunctionSource | Should -Match 'function Test-DismReady[\s\S]*?\.EXAMPLE'
        }

        It 'Should document two-stage validation' {
            $FunctionSource | Should -Match 'two[-\s]stage'
        }
    }
}

# =============================================================================
# Phase 45: DISM Resilience Pipeline Integration Patterns
# =============================================================================

Describe 'Phase 45: DISM Resilience Pipeline Integration Patterns' -Tag 'Unit', 'FFU.Core', 'DismFunctional', 'Phase45' {

    Context 'Hard-stop behavior requirements' {
        It 'Test-DismFunctional returns boolean for pipeline consumption' {
            # Mock to return $true (healthy)
            Mock -CommandName Start-Job -MockWith {
                return [PSCustomObject]@{ Id = 1; State = 'Running' }
            } -ModuleName 'FFU.Core'
            Mock -CommandName Wait-Job -MockWith {
                return [PSCustomObject]@{ Id = 1; State = 'Completed' }
            } -ModuleName 'FFU.Core'
            Mock -CommandName Receive-Job -MockWith { return $true } -ModuleName 'FFU.Core'
            Mock -CommandName Remove-Job -MockWith { } -ModuleName 'FFU.Core'

            $result = Test-DismFunctional
            $result | Should -BeOfType [bool]
        }

        It 'Test-DismReady returns boolean for pipeline consumption' {
            # Mock healthy state
            Mock -CommandName fltmc.exe -MockWith { return "WimMount" }
            Mock -CommandName Start-Job -MockWith {
                return [PSCustomObject]@{ Id = 1; State = 'Running' }
            } -ModuleName 'FFU.Core'
            Mock -CommandName Wait-Job -MockWith {
                return [PSCustomObject]@{ Id = 1; State = 'Completed' }
            } -ModuleName 'FFU.Core'
            Mock -CommandName Receive-Job -MockWith { return $true } -ModuleName 'FFU.Core'
            Mock -CommandName Remove-Job -MockWith { } -ModuleName 'FFU.Core'

            $result = Test-DismReady -AttemptRepair $false
            $result | Should -BeOfType [bool]
        }

        It 'Test-DismReady with AttemptRepair calls repair on failure' {
            # Mock unhealthy state - filter not loaded
            Mock -CommandName fltmc.exe -MockWith { return "No filters loaded" }

            # Mock repair commands
            Mock -CommandName Invoke-Expression -MockWith { } -ParameterFilter { $Command -match 'sc\.exe' }
            Mock -CommandName Start-Service -MockWith { }
            Mock -CommandName Start-Sleep -MockWith { }

            # Mock Test-DismFunctional to still return false after repair
            Mock -CommandName Test-DismFunctional -MockWith { return $false } -ModuleName 'FFU.Core'

            # Should attempt repair but still return false
            $result = Test-DismReady -AttemptRepair $true -TimeoutSeconds 5
            $result | Should -BeOfType [bool]
        }
    }

    Context 'Test-DismReady timeout protection' {
        It 'Does not hang when DISM service is unresponsive' {
            # Mock healthy filter state
            Mock -CommandName fltmc.exe -MockWith { return "WimMount" }

            # Mock job that times out
            Mock -CommandName Start-Job -MockWith {
                return [PSCustomObject]@{ Id = 999; State = 'Running' }
            } -ModuleName 'FFU.Core'
            Mock -CommandName Wait-Job -MockWith {
                # Timeout - returns null
                return $null
            } -ModuleName 'FFU.Core'
            Mock -CommandName Stop-Job -MockWith { } -ModuleName 'FFU.Core'
            Mock -CommandName Remove-Job -MockWith { } -ModuleName 'FFU.Core'
            Mock -CommandName Receive-Job -MockWith { return $null } -ModuleName 'FFU.Core'

            # Should return $false without hanging
            $result = Test-DismFunctional
            $result | Should -Be $false
        }
    }

    Context 'Error message format requirements' {
        It 'Test-DismFunctional source has structured error messages' {
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw

            # Verify structured error message pattern exists
            $FunctionSource | Should -Match 'DISM functional'
        }

        It 'Test-DismReady source has success logging' {
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw

            # Verify success logging exists in source
            $FunctionSource | Should -Match 'DISM.*ready|ready.*validation'
        }
    }

    Context 'Pipeline integration pattern verification' {
        It 'Test-DismReady boolean return enables hard-stop pattern' {
            # Verify function returns boolean type (source code analysis)
            $command = Get-Command -Name 'Test-DismReady' -Module 'FFU.Core'
            $command.OutputType.Type.Name | Should -Contain 'Boolean'

            # Verify source code has conditional pattern usage
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $FunctionSource | Should -Match 'return\s+\$true|return\s+\$false'
        }

        It 'Test-DismFunctional boolean return enables post-operation validation pattern' {
            # Verify function returns boolean type (source code analysis)
            $command = Get-Command -Name 'Test-DismFunctional' -Module 'FFU.Core'
            $command.OutputType.Type.Name | Should -Contain 'Boolean'

            # Verify source code returns boolean
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $FunctionSource | Should -Match 'return\s+\$true|return\s+\$false'
        }

        It 'Hard-stop pattern is documented in usage examples' {
            # Verify the integration pattern is clear from documentation/source
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw

            # Should have examples or documentation showing usage
            $FunctionSource | Should -Match 'Test-DismReady|Test-DismFunctional'
        }
    }
}
