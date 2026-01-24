#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Core build error aggregation system

.DESCRIPTION
    Comprehensive unit tests covering the build error aggregation functions in FFU.Core:
    - Add-BuildError: Add errors with Phase, Message, Severity, Exception, Timestamp
    - Get-BuildErrorSummary: Returns summary with counts by severity
    - Clear-BuildErrors: Clears all accumulated errors
    - Write-BuildErrorSummary: Formats and logs error summary

    Tests implement REL-BUILD-04 requirement for build error aggregation.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.BuildErrors.Tests.ps1 -Output Detailed
    Filter by tag: Invoke-Pester -Path .\Tests\Unit\FFU.Core.BuildErrors.Tests.ps1 -Tag 'REL-BUILD-04' -Output Detailed

.EXAMPLE
    # Run all build error tests
    Invoke-Pester -Path .\Tests\Unit\FFU.Core.BuildErrors.Tests.ps1

.EXAMPLE
    # Run with detailed output
    Invoke-Pester -Path .\Tests\Unit\FFU.Core.BuildErrors.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Add modules folder to PSModulePath
    $ModulesFolder = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    if ($env:PSModulePath -notlike "*$ModulesFolder*") {
        $env:PSModulePath = "$ModulesFolder;$env:PSModulePath"
    }

    # Create global WriteLog stub BEFORE module import
    # FFU.Core functions check for WriteLog and call it if available
    if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
        function global:WriteLog {
            param([string]$Message)
        }
    }

    # Remove module if loaded (ensures clean state)
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Verify module exists
    if (-not (Test-Path "$ModulePath\FFU.Core.psd1")) {
        throw "FFU.Core module not found at: $ModulePath"
    }

    # Import the module
    Import-Module "$ModulePath\FFU.Core.psd1" -Force -ErrorAction Stop

    # Mock WriteLog to suppress logging noise during tests
    Mock WriteLog { }
}

AfterAll {
    # Cleanup
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Add-BuildError Tests
# =============================================================================

Describe 'Add-BuildError' -Tag 'Unit', 'FFU.Core', 'BuildErrors', 'REL-BUILD-04' {

    AfterEach {
        # Clean up errors between tests
        Clear-BuildErrors
    }

    Context 'Error Entry Properties' {
        It 'Should add error with all required properties' {
            Add-BuildError -Phase 'DriverDownload' -Message 'Test error message' -Severity Warning

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 1

            $error = $summary.Errors[0]
            $error.Phase | Should -Be 'DriverDownload'
            $error.Message | Should -Be 'Test error message'
            $error.Severity | Should -Be 'Warning'
        }

        It 'Should default Severity to Warning when not specified' {
            Add-BuildError -Phase 'TestPhase' -Message 'Test message'

            $summary = Get-BuildErrorSummary
            $summary.Errors[0].Severity | Should -Be 'Warning'
            $summary.WarningCount | Should -Be 1
        }

        It 'Should accept Critical severity' {
            Add-BuildError -Phase 'TestPhase' -Message 'Critical error' -Severity Critical

            $summary = Get-BuildErrorSummary
            $summary.Errors[0].Severity | Should -Be 'Critical'
            $summary.CriticalCount | Should -Be 1
        }

        It 'Should accept Info severity' {
            Add-BuildError -Phase 'TestPhase' -Message 'Info message' -Severity Info

            $summary = Get-BuildErrorSummary
            $summary.Errors[0].Severity | Should -Be 'Info'
            $summary.InfoCount | Should -Be 1
        }

        It 'Should include Exception when provided' {
            $testException = [System.InvalidOperationException]::new('Test exception')
            Add-BuildError -Phase 'TestPhase' -Message 'Error with exception' -Exception $testException

            $summary = Get-BuildErrorSummary
            $summary.Errors[0].Exception | Should -Not -BeNull
            $summary.Errors[0].Exception.Message | Should -Be 'Test exception'
        }

        It 'Should set Timestamp to current time' {
            $before = [DateTime]::Now
            Add-BuildError -Phase 'TestPhase' -Message 'Timestamp test'
            $after = [DateTime]::Now

            $summary = Get-BuildErrorSummary
            $timestamp = $summary.Errors[0].Timestamp

            $timestamp | Should -BeGreaterOrEqual $before
            $timestamp | Should -BeLessOrEqual $after
        }

        It 'Should have null Exception when not provided' {
            Add-BuildError -Phase 'TestPhase' -Message 'No exception'

            $summary = Get-BuildErrorSummary
            $summary.Errors[0].Exception | Should -BeNull
        }
    }

    Context 'Error Accumulation' {
        It 'Should accumulate multiple errors' {
            Add-BuildError -Phase 'Phase1' -Message 'Error 1' -Severity Warning
            Add-BuildError -Phase 'Phase2' -Message 'Error 2' -Severity Critical
            Add-BuildError -Phase 'Phase3' -Message 'Error 3' -Severity Info

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 3
        }

        It 'Should preserve error order (FIFO)' {
            Add-BuildError -Phase 'First' -Message 'First error'
            Add-BuildError -Phase 'Second' -Message 'Second error'
            Add-BuildError -Phase 'Third' -Message 'Third error'

            $summary = Get-BuildErrorSummary
            $summary.Errors[0].Phase | Should -Be 'First'
            $summary.Errors[1].Phase | Should -Be 'Second'
            $summary.Errors[2].Phase | Should -Be 'Third'
        }

        It 'Should handle many errors without issue' {
            for ($i = 1; $i -le 100; $i++) {
                Add-BuildError -Phase "Phase$i" -Message "Error $i"
            }

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 100
        }
    }

    Context 'Parameter Validation' {
        It 'Should reject empty Phase' {
            { Add-BuildError -Phase '' -Message 'Test' } | Should -Throw
        }

        It 'Should reject empty Message' {
            { Add-BuildError -Phase 'Test' -Message '' } | Should -Throw
        }

        It 'Should reject invalid Severity' {
            { Add-BuildError -Phase 'Test' -Message 'Test' -Severity 'Invalid' } | Should -Throw
        }
    }
}

# =============================================================================
# Get-BuildErrorSummary Tests
# =============================================================================

Describe 'Get-BuildErrorSummary' -Tag 'Unit', 'FFU.Core', 'BuildErrors', 'REL-BUILD-04' {

    AfterEach {
        Clear-BuildErrors
    }

    Context 'Empty State' {
        It 'Should return empty summary when no errors' {
            $summary = Get-BuildErrorSummary

            $summary.TotalCount | Should -Be 0
            $summary.CriticalCount | Should -Be 0
            $summary.WarningCount | Should -Be 0
            $summary.InfoCount | Should -Be 0
            $summary.HasCritical | Should -Be $false
            $summary.Errors.Count | Should -Be 0
        }
    }

    Context 'Severity Counting' {
        It 'Should count Critical errors correctly' {
            Add-BuildError -Phase 'Test1' -Message 'Critical 1' -Severity Critical
            Add-BuildError -Phase 'Test2' -Message 'Critical 2' -Severity Critical
            Add-BuildError -Phase 'Test3' -Message 'Warning' -Severity Warning

            $summary = Get-BuildErrorSummary
            $summary.CriticalCount | Should -Be 2
        }

        It 'Should count Warning errors correctly' {
            Add-BuildError -Phase 'Test1' -Message 'Warning 1' -Severity Warning
            Add-BuildError -Phase 'Test2' -Message 'Warning 2' -Severity Warning
            Add-BuildError -Phase 'Test3' -Message 'Warning 3' -Severity Warning

            $summary = Get-BuildErrorSummary
            $summary.WarningCount | Should -Be 3
        }

        It 'Should count Info errors correctly' {
            Add-BuildError -Phase 'Test1' -Message 'Info 1' -Severity Info
            Add-BuildError -Phase 'Test2' -Message 'Info 2' -Severity Info

            $summary = Get-BuildErrorSummary
            $summary.InfoCount | Should -Be 2
        }

        It 'Should calculate TotalCount as sum of all severities' {
            Add-BuildError -Phase 'Test1' -Message 'Critical' -Severity Critical
            Add-BuildError -Phase 'Test2' -Message 'Warning' -Severity Warning
            Add-BuildError -Phase 'Test3' -Message 'Info' -Severity Info

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 3
            $summary.TotalCount | Should -Be ($summary.CriticalCount + $summary.WarningCount + $summary.InfoCount)
        }
    }

    Context 'HasCritical Flag' {
        It 'Should set HasCritical to true when Critical errors exist' {
            Add-BuildError -Phase 'Test' -Message 'Critical error' -Severity Critical

            $summary = Get-BuildErrorSummary
            $summary.HasCritical | Should -Be $true
        }

        It 'Should set HasCritical to false when no Critical errors' {
            Add-BuildError -Phase 'Test1' -Message 'Warning' -Severity Warning
            Add-BuildError -Phase 'Test2' -Message 'Info' -Severity Info

            $summary = Get-BuildErrorSummary
            $summary.HasCritical | Should -Be $false
        }

        It 'Should set HasCritical correctly with mixed severities' {
            Add-BuildError -Phase 'Test1' -Message 'Warning' -Severity Warning
            Add-BuildError -Phase 'Test2' -Message 'Critical' -Severity Critical
            Add-BuildError -Phase 'Test3' -Message 'Info' -Severity Info

            $summary = Get-BuildErrorSummary
            $summary.HasCritical | Should -Be $true
        }
    }

    Context 'Errors Array' {
        It 'Should return all errors in Errors property' {
            Add-BuildError -Phase 'Phase1' -Message 'Error 1'
            Add-BuildError -Phase 'Phase2' -Message 'Error 2'
            Add-BuildError -Phase 'Phase3' -Message 'Error 3'

            $summary = Get-BuildErrorSummary
            $summary.Errors | Should -HaveCount 3
            $summary.Errors[0].Phase | Should -Be 'Phase1'
            $summary.Errors[1].Phase | Should -Be 'Phase2'
            $summary.Errors[2].Phase | Should -Be 'Phase3'
        }

        It 'Should return errors with all properties intact' {
            $testException = [System.ArgumentException]::new('Test arg exception')
            Add-BuildError -Phase 'TestPhase' -Message 'Test message' -Severity Critical -Exception $testException

            $summary = Get-BuildErrorSummary
            $error = $summary.Errors[0]

            $error.Phase | Should -Be 'TestPhase'
            $error.Message | Should -Be 'Test message'
            $error.Severity | Should -Be 'Critical'
            $error.Exception.Message | Should -Be 'Test arg exception'
            $error.Timestamp | Should -Not -BeNull
        }
    }
}

# =============================================================================
# Clear-BuildErrors Tests
# =============================================================================

Describe 'Clear-BuildErrors' -Tag 'Unit', 'FFU.Core', 'BuildErrors', 'REL-BUILD-04' {

    Context 'Clearing Errors' {
        It 'Should clear all accumulated errors' {
            Add-BuildError -Phase 'Test1' -Message 'Error 1' -Severity Critical
            Add-BuildError -Phase 'Test2' -Message 'Error 2' -Severity Warning
            Add-BuildError -Phase 'Test3' -Message 'Error 3' -Severity Info

            $beforeClear = Get-BuildErrorSummary
            $beforeClear.TotalCount | Should -Be 3

            Clear-BuildErrors

            $afterClear = Get-BuildErrorSummary
            $afterClear.TotalCount | Should -Be 0
            $afterClear.CriticalCount | Should -Be 0
            $afterClear.WarningCount | Should -Be 0
            $afterClear.InfoCount | Should -Be 0
        }

        It 'Should be safe to call when already empty' {
            Clear-BuildErrors  # First clear
            { Clear-BuildErrors } | Should -Not -Throw  # Second clear should not throw

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 0
        }

        It 'Should reset HasCritical to false' {
            Add-BuildError -Phase 'Test' -Message 'Critical' -Severity Critical

            $before = Get-BuildErrorSummary
            $before.HasCritical | Should -Be $true

            Clear-BuildErrors

            $after = Get-BuildErrorSummary
            $after.HasCritical | Should -Be $false
        }

        It 'Should allow new errors after clearing' {
            Add-BuildError -Phase 'Old' -Message 'Old error'
            Clear-BuildErrors
            Add-BuildError -Phase 'New' -Message 'New error'

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 1
            $summary.Errors[0].Phase | Should -Be 'New'
        }
    }
}

# =============================================================================
# Write-BuildErrorSummary Tests
# =============================================================================

Describe 'Write-BuildErrorSummary' -Tag 'Unit', 'FFU.Core', 'BuildErrors', 'REL-BUILD-04' {

    AfterEach {
        Clear-BuildErrors
    }

    Context 'Basic Functionality' {
        It 'Should not throw on valid summary' {
            Add-BuildError -Phase 'Test' -Message 'Test error' -Severity Warning
            $summary = Get-BuildErrorSummary

            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw
        }

        It 'Should not throw on empty summary' {
            $summary = Get-BuildErrorSummary

            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw
        }

        It 'Should require Summary parameter' {
            { Write-BuildErrorSummary } | Should -Throw
        }
    }

    Context 'Output Formatting' {
        # Note: Write-BuildErrorSummary uses a scriptblock helper that calls WriteLog if available,
        # otherwise falls back to Write-Verbose. The exact output depends on the presence of WriteLog.
        # We test behavior rather than exact output format.

        It 'Should process summary with Critical errors without error' {
            Add-BuildError -Phase 'TestPhase' -Message 'Critical issue' -Severity Critical
            $summary = Get-BuildErrorSummary

            # Should complete without throwing
            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw

            # Verify summary has expected data
            $summary.CriticalCount | Should -Be 1
            $summary.Errors[0].Severity | Should -Be 'Critical'
        }

        It 'Should process summary with Warning errors without error' {
            Add-BuildError -Phase 'TestPhase' -Message 'Warning issue' -Severity Warning
            $summary = Get-BuildErrorSummary

            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw
            $summary.WarningCount | Should -Be 1
        }

        It 'Should process summary with Info errors without error' {
            Add-BuildError -Phase 'TestPhase' -Message 'Info message' -Severity Info
            $summary = Get-BuildErrorSummary

            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw
            $summary.InfoCount | Should -Be 1
        }

        It 'Should process summary with mixed severity errors' {
            Add-BuildError -Phase 'Test1' -Message 'Critical' -Severity Critical
            Add-BuildError -Phase 'Test2' -Message 'Warning' -Severity Warning
            Add-BuildError -Phase 'Test3' -Message 'Info' -Severity Info
            $summary = Get-BuildErrorSummary

            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw
            $summary.TotalCount | Should -Be 3
        }

        It 'Should process summary with timestamps' {
            Add-BuildError -Phase 'Test' -Message 'Error with timestamp' -Severity Warning
            $summary = Get-BuildErrorSummary

            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw

            # Verify timestamp was recorded
            $summary.Errors[0].Timestamp | Should -Not -BeNull
            $summary.Errors[0].Timestamp | Should -BeOfType [DateTime]
        }

        It 'Should process large summary without error' {
            for ($i = 1; $i -le 50; $i++) {
                $severity = @('Critical', 'Warning', 'Info')[$i % 3]
                Add-BuildError -Phase "Phase$i" -Message "Error $i" -Severity $severity
            }
            $summary = Get-BuildErrorSummary

            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw
            $summary.TotalCount | Should -Be 50
        }
    }
}

# =============================================================================
# Integration Scenarios
# =============================================================================

Describe 'Build Error Aggregation Integration' -Tag 'Unit', 'FFU.Core', 'BuildErrors', 'REL-BUILD-04', 'Integration' {

    AfterEach {
        Clear-BuildErrors
    }

    Context 'Real-World Scenarios' {
        It 'Should handle mixed severity errors from multiple phases' {
            Add-BuildError -Phase 'DriverDownload' -Message 'Dell driver unavailable' -Severity Warning
            Add-BuildError -Phase 'UpdatesDownload' -Message 'KB5001234 failed' -Severity Critical
            Add-BuildError -Phase 'DriverDownload' -Message 'HP driver timeout' -Severity Warning
            Add-BuildError -Phase 'VMSetup' -Message 'TPM not available' -Severity Info

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 4
            $summary.CriticalCount | Should -Be 1
            $summary.WarningCount | Should -Be 2
            $summary.InfoCount | Should -Be 1
            $summary.HasCritical | Should -Be $true
        }

        It 'Should preserve phase information for filtering' {
            Add-BuildError -Phase 'DriverDownload' -Message 'Error 1' -Severity Warning
            Add-BuildError -Phase 'DriverDownload' -Message 'Error 2' -Severity Warning
            Add-BuildError -Phase 'UpdatesDownload' -Message 'Error 3' -Severity Critical

            $summary = Get-BuildErrorSummary
            $driverErrors = $summary.Errors | Where-Object { $_.Phase -eq 'DriverDownload' }
            $driverErrors | Should -HaveCount 2
        }

        It 'Should support decision making based on HasCritical' {
            # Simulate a build that should continue (no critical errors)
            Add-BuildError -Phase 'DriverDownload' -Message 'Non-critical issue' -Severity Warning
            Add-BuildError -Phase 'VMSetup' -Message 'Optional feature unavailable' -Severity Info

            $summary = Get-BuildErrorSummary

            # Business logic: Continue if no critical errors
            $shouldContinue = -not $summary.HasCritical
            $shouldContinue | Should -Be $true
        }

        It 'Should support decision making to stop on critical' {
            # Simulate a build that should stop (critical error)
            Add-BuildError -Phase 'ISODownload' -Message 'Windows ISO corrupt' -Severity Critical

            $summary = Get-BuildErrorSummary

            # Business logic: Stop if critical errors
            $shouldStop = $summary.HasCritical
            $shouldStop | Should -Be $true
        }

        It 'Should enable full error report at build end' {
            # Simulate errors from entire build
            Add-BuildError -Phase 'Initialization' -Message 'Config validation warning' -Severity Warning
            Add-BuildError -Phase 'ISOMount' -Message 'ISO mounted successfully' -Severity Info
            Add-BuildError -Phase 'DriverDownload' -Message 'Dell BIOS driver 404' -Severity Warning
            Add-BuildError -Phase 'UpdatesDownload' -Message 'KB5001234 checksum mismatch' -Severity Critical
            Add-BuildError -Phase 'VMCreation' -Message 'TPM warning' -Severity Info
            Add-BuildError -Phase 'FFUCapture' -Message 'Capture slow due to fragmentation' -Severity Warning

            $summary = Get-BuildErrorSummary

            # Generate report
            { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw

            # Verify all phases captured
            $phases = $summary.Errors | ForEach-Object { $_.Phase } | Sort-Object -Unique
            $phases | Should -Contain 'Initialization'
            $phases | Should -Contain 'DriverDownload'
            $phases | Should -Contain 'UpdatesDownload'
            $phases | Should -Contain 'FFUCapture'
        }

        It 'Should work correctly after multiple clear cycles' {
            # First batch
            Add-BuildError -Phase 'Build1' -Message 'Error 1' -Severity Critical
            Add-BuildError -Phase 'Build1' -Message 'Error 2' -Severity Warning
            $summary1 = Get-BuildErrorSummary
            $summary1.TotalCount | Should -Be 2

            Clear-BuildErrors

            # Second batch
            Add-BuildError -Phase 'Build2' -Message 'Error 3' -Severity Info
            $summary2 = Get-BuildErrorSummary
            $summary2.TotalCount | Should -Be 1
            $summary2.Errors[0].Phase | Should -Be 'Build2'

            Clear-BuildErrors

            # Third batch
            Add-BuildError -Phase 'Build3' -Message 'Error 4' -Severity Critical
            Add-BuildError -Phase 'Build3' -Message 'Error 5' -Severity Critical
            Add-BuildError -Phase 'Build3' -Message 'Error 6' -Severity Critical
            $summary3 = Get-BuildErrorSummary
            $summary3.TotalCount | Should -Be 3
            $summary3.CriticalCount | Should -Be 3
        }
    }
}
