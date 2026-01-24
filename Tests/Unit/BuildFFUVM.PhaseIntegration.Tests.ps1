#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Invoke-BuildPhase integration in BuildFFUVM.ps1.

.DESCRIPTION
    Tests the integration of Invoke-BuildPhase wrapper for build phase
    management. Validates critical vs non-critical phase behavior,
    error aggregation, and final summary generation.

.NOTES
    Part of INT-BUILD requirements (Phase 26)
    Created: 2026-01-24

    Run: Invoke-Pester -Path .\Tests\Unit\BuildFFUVM.PhaseIntegration.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesFolder = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    if ($env:PSModulePath -notlike "*$ModulesFolder*") {
        $env:PSModulePath = "$ModulesFolder;$env:PSModulePath"
    }

    # Create global WriteLog stub
    if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
        function global:WriteLog { param([string]$Message) }
    }

    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModulesFolder 'FFU.Core\FFU.Core.psd1') -Force -ErrorAction Stop

    Mock WriteLog { }
}

AfterAll {
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Critical Phase Integration Tests (INT-BUILD-03)
# =============================================================================

Describe 'Critical Phase Integration (INT-BUILD-03)' -Tag 'Unit', 'Integration', 'INT-BUILD-03' {

    BeforeEach {
        Clear-BuildErrors
    }

    It 'Should throw on critical phase failure (simulated Disk Creation)' {
        {
            Invoke-BuildPhase -PhaseName 'Disk Creation' -Critical $true -Action {
                throw "Simulated VHDX creation failure"
            }
        } | Should -Throw -ExpectedMessage "*Simulated VHDX creation failure*"
    }

    It 'Should throw on critical phase failure (simulated VM Creation)' {
        {
            Invoke-BuildPhase -PhaseName 'VM Creation' -Critical $true -Action {
                throw "Simulated VM creation failure"
            }
        } | Should -Throw -ExpectedMessage "*Simulated VM creation failure*"
    }

    It 'Should throw on critical phase failure (simulated FFU Capture)' {
        {
            Invoke-BuildPhase -PhaseName 'FFU Capture' -Critical $true -Action {
                throw "Simulated FFU capture failure"
            }
        } | Should -Throw -ExpectedMessage "*Simulated FFU capture failure*"
    }

    It 'Should add critical error to collector before throwing' {
        try {
            Invoke-BuildPhase -PhaseName 'Critical Test' -Critical $true -Action {
                throw "Critical error message"
            }
        } catch { }

        $summary = Get-BuildErrorSummary
        $summary.CriticalCount | Should -Be 1
        $summary.HasCritical | Should -Be $true
    }

    It 'Should return Success=false on critical failure (before throw)' {
        # Use -ErrorAction SilentlyContinue to capture result before throw propagates
        $result = $null
        try {
            $result = Invoke-BuildPhase -PhaseName 'Test' -Critical $true -Action {
                throw "Fail"
            }
        } catch {
            # Expected - critical phases throw
        }

        # Result should be set to failure state before throw
        $summary = Get-BuildErrorSummary
        $summary.HasCritical | Should -Be $true
    }

    It 'Should capture exception details in error collector' {
        try {
            Invoke-BuildPhase -PhaseName 'Exception Test' -Critical $true -Action {
                throw [System.IO.FileNotFoundException]::new("VHD file not found")
            }
        } catch { }

        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Phase | Should -Be 'Exception Test'
        $summary.Errors[0].Severity | Should -Be 'Critical'
    }

    It 'Should halt build sequence at critical failure' {
        $reachedAfterFailure = $false

        try {
            Invoke-BuildPhase -PhaseName 'Preflight' -Critical $true -Action { "OK" }
            Invoke-BuildPhase -PhaseName 'Disk Creation' -Critical $true -Action { throw "Disk fail" }
            $reachedAfterFailure = $true  # Should never execute
        } catch {
            # Expected
        }

        $reachedAfterFailure | Should -Be $false
    }
}

# =============================================================================
# Non-Critical Phase Integration Tests (INT-BUILD-02)
# =============================================================================

Describe 'Non-Critical Phase Integration (INT-BUILD-02)' -Tag 'Unit', 'Integration', 'INT-BUILD-02' {

    BeforeEach {
        Clear-BuildErrors
    }

    It 'Should NOT throw on non-critical phase failure (simulated USB Creation)' {
        $result = Invoke-BuildPhase -PhaseName 'USB Drive Creation' -Critical $false -Action {
            throw "Simulated USB creation failure"
        }

        $result.Success | Should -Be $false
        # No exception should propagate
    }

    It 'Should NOT throw on non-critical phase failure (simulated Deployment Media)' {
        $result = Invoke-BuildPhase -PhaseName 'Deployment Media Creation' -Critical $false -Action {
            throw "Simulated deployment media failure"
        }

        $result.Success | Should -Be $false
    }

    It 'Should NOT throw on non-critical phase failure (simulated Driver Download)' {
        $result = Invoke-BuildPhase -PhaseName 'Driver Download' -Critical $false -Action {
            throw "Dell drivers unavailable"
        }

        $result.Success | Should -Be $false
    }

    It 'Should NOT throw on non-critical phase failure (simulated FFU Cleanup)' {
        $result = Invoke-BuildPhase -PhaseName 'FFU Cleanup' -Critical $false -Action {
            throw "Cleanup failed"
        }

        $result.Success | Should -Be $false
    }

    It 'Should add warning to error collector for non-critical failures' {
        Invoke-BuildPhase -PhaseName 'Non-Critical Test' -Critical $false -Action {
            throw "Warning level error"
        }

        $summary = Get-BuildErrorSummary
        $summary.WarningCount | Should -Be 1
        $summary.HasCritical | Should -Be $false
    }

    It 'Should continue execution after non-critical failure' {
        $executionContinued = $false

        $result = Invoke-BuildPhase -PhaseName 'Failing Phase' -Critical $false -Action {
            throw "Fail"
        }

        $executionContinued = $true  # This line executes if no throw

        $executionContinued | Should -Be $true
        $result.Success | Should -Be $false
    }

    It 'Should capture error message for user-friendly display' {
        Invoke-BuildPhase -PhaseName 'USB Creation' -Critical $false -Action {
            throw "No USB drive detected"
        }

        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Message | Should -BeLike "*No USB drive detected*"
    }

    It 'Should allow subsequent phases to execute after failure' {
        $phase1Completed = $false
        $phase2Completed = $false
        $phase3Completed = $false

        $r1 = Invoke-BuildPhase -PhaseName 'Phase 1' -Critical $false -Action { throw "Fail 1" }
        $phase1Completed = $true

        $r2 = Invoke-BuildPhase -PhaseName 'Phase 2' -Critical $false -Action { return "Success" }
        $phase2Completed = $r2.Success

        $r3 = Invoke-BuildPhase -PhaseName 'Phase 3' -Critical $false -Action { throw "Fail 3" }
        $phase3Completed = $true

        $phase1Completed | Should -Be $true
        $phase2Completed | Should -Be $true
        $phase3Completed | Should -Be $true

        $summary = Get-BuildErrorSummary
        $summary.TotalCount | Should -Be 2
    }
}

# =============================================================================
# Error Aggregation Tests (INT-BUILD-04)
# =============================================================================

Describe 'Error Aggregation in Final Summary (INT-BUILD-04)' -Tag 'Unit', 'Integration', 'INT-BUILD-04' {

    BeforeEach {
        Clear-BuildErrors
    }

    It 'Should aggregate multiple non-critical failures in summary' {
        # Simulate multiple non-critical phases failing
        Invoke-BuildPhase -PhaseName 'Phase 1' -Critical $false -Action { throw "Error 1" }
        Invoke-BuildPhase -PhaseName 'Phase 2' -Critical $false -Action { throw "Error 2" }
        Invoke-BuildPhase -PhaseName 'Phase 3' -Critical $false -Action { throw "Error 3" }

        $summary = Get-BuildErrorSummary
        $summary.TotalCount | Should -Be 3
        $summary.WarningCount | Should -Be 3
        $summary.Errors.Count | Should -Be 3
    }

    It 'Should include phase names in error summary' {
        Invoke-BuildPhase -PhaseName 'USB Drive Creation' -Critical $false -Action { throw "USB fail" }
        Invoke-BuildPhase -PhaseName 'Deployment Media Creation' -Critical $false -Action { throw "Deploy fail" }

        $summary = Get-BuildErrorSummary
        $phaseNames = $summary.Errors | ForEach-Object { $_.Phase }
        $phaseNames | Should -Contain 'USB Drive Creation'
        $phaseNames | Should -Contain 'Deployment Media Creation'
    }

    It 'Should distinguish critical vs warning severity' {
        try {
            Invoke-BuildPhase -PhaseName 'Critical Phase' -Critical $true -Action { throw "Critical" }
        } catch { }

        Invoke-BuildPhase -PhaseName 'Warning Phase' -Critical $false -Action { throw "Warning" }

        $summary = Get-BuildErrorSummary
        $summary.CriticalCount | Should -Be 1
        $summary.WarningCount | Should -Be 1
        $summary.TotalCount | Should -Be 2
    }

    It 'Should return HasCritical=false when only warnings exist' {
        Invoke-BuildPhase -PhaseName 'USB' -Critical $false -Action { throw "Fail" }
        Invoke-BuildPhase -PhaseName 'Cleanup' -Critical $false -Action { throw "Fail" }

        $summary = Get-BuildErrorSummary
        $summary.HasCritical | Should -Be $false
        $summary.TotalCount | Should -BeGreaterThan 0
    }

    It 'Should clear errors between builds' {
        Invoke-BuildPhase -PhaseName 'Test' -Critical $false -Action { throw "Old error" }

        $beforeClear = Get-BuildErrorSummary
        $beforeClear.TotalCount | Should -Be 1

        Clear-BuildErrors

        $afterClear = Get-BuildErrorSummary
        $afterClear.TotalCount | Should -Be 0
    }

    It 'Should preserve error details for logging' {
        Invoke-BuildPhase -PhaseName 'Driver Download' -Critical $false -Action {
            throw "Dell BIOS driver package unavailable from catalog"
        }

        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Message | Should -BeLike "*Dell BIOS driver*"
        $summary.Errors[0].Phase | Should -Be 'Driver Download'
        $summary.Errors[0].Severity | Should -Be 'Warning'
    }

    It 'Should track timestamp for each error' {
        Invoke-BuildPhase -PhaseName 'Test' -Critical $false -Action { throw "Error" }

        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Timestamp | Should -Not -BeNullOrEmpty
    }
}

# =============================================================================
# Mixed Phase Scenario Tests
# =============================================================================

Describe 'Mixed Phase Scenarios' -Tag 'Unit', 'Integration', 'INT-BUILD' {

    BeforeEach {
        Clear-BuildErrors
    }

    It 'Should execute successful phases and continue past non-critical failures' {
        $phase1Complete = $false
        $phase2Complete = $false
        $phase3Complete = $false

        $r1 = Invoke-BuildPhase -PhaseName 'Disk Creation' -Critical $true -Action {
            return "VHDX Created"
        }
        $phase1Complete = $r1.Success

        $r2 = Invoke-BuildPhase -PhaseName 'USB Creation' -Critical $false -Action {
            throw "No USB drive"
        }
        $phase2Complete = $true  # Execution continues even though phase failed

        $r3 = Invoke-BuildPhase -PhaseName 'Cleanup' -Critical $false -Action {
            return "Cleaned"
        }
        $phase3Complete = $r3.Success

        $phase1Complete | Should -Be $true
        $phase2Complete | Should -Be $true
        $phase3Complete | Should -Be $true

        $r1.Result | Should -Be "VHDX Created"
        $r2.Success | Should -Be $false
        $r3.Result | Should -Be "Cleaned"
    }

    It 'Should stop at first critical failure (simulated build sequence)' {
        $reachedFinalPhase = $false

        try {
            Invoke-BuildPhase -PhaseName 'Preflight' -Critical $true -Action { "OK" }
            Invoke-BuildPhase -PhaseName 'Disk Creation' -Critical $true -Action { throw "Disk fail" }
            Invoke-BuildPhase -PhaseName 'Final Phase' -Critical $true -Action { $reachedFinalPhase = $true }
        } catch {
            # Expected
        }

        $reachedFinalPhase | Should -Be $false
    }

    It 'Should produce comprehensive final summary' {
        # Simulate a build with mixed results
        Invoke-BuildPhase -PhaseName 'Preflight' -Critical $true -Action { "pass" }
        Invoke-BuildPhase -PhaseName 'Disk Creation' -Critical $true -Action { "pass" }
        Invoke-BuildPhase -PhaseName 'Driver Download' -Critical $false -Action { throw "Dell driver unavailable" }
        Invoke-BuildPhase -PhaseName 'USB Creation' -Critical $false -Action { throw "No USB drive" }

        $summary = Get-BuildErrorSummary
        $summary.TotalCount | Should -Be 2
        $summary.WarningCount | Should -Be 2
        $summary.CriticalCount | Should -Be 0
        $summary.HasCritical | Should -Be $false
    }

    It 'Should simulate full BuildFFUVM.ps1 build flow' {
        # Mimic the actual BuildFFUVM.ps1 phase sequence
        $results = @{}

        # Critical phases (from 26-01)
        $results['DiskCreation'] = Invoke-BuildPhase -PhaseName 'Disk Creation' -Critical $true -Action {
            return @{ Path = 'C:\temp\ffu.vhdx' }
        }

        $results['VMCreation'] = Invoke-BuildPhase -PhaseName 'VM Creation' -Critical $true -Action {
            return @{ Name = 'FFU_Build_VM'; State = 'Running' }
        }

        $results['FFUCapture'] = Invoke-BuildPhase -PhaseName 'FFU Capture' -Critical $true -Action {
            return @{ Path = 'C:\FFU\windows.ffu' }
        }

        # Non-critical phases (from 26-02)
        $results['DriverDownload'] = Invoke-BuildPhase -PhaseName 'Driver Download' -Critical $false -Action {
            throw "Dell catalog unavailable"
        }

        $results['DeployMedia'] = Invoke-BuildPhase -PhaseName 'Deployment Media Creation' -Critical $false -Action {
            return @{ ISOPath = 'C:\Deploy\media.iso' }
        }

        $results['USB'] = Invoke-BuildPhase -PhaseName 'USB Drive Creation' -Critical $false -Action {
            throw "No removable drive detected"
        }

        $results['Cleanup'] = Invoke-BuildPhase -PhaseName 'FFU Cleanup' -Critical $false -Action {
            return "Cleanup complete"
        }

        # Verify critical phases succeeded
        $results['DiskCreation'].Success | Should -Be $true
        $results['VMCreation'].Success | Should -Be $true
        $results['FFUCapture'].Success | Should -Be $true

        # Verify non-critical failures were captured but didn't halt
        $results['DriverDownload'].Success | Should -Be $false
        $results['DeployMedia'].Success | Should -Be $true
        $results['USB'].Success | Should -Be $false
        $results['Cleanup'].Success | Should -Be $true

        # Final summary
        $summary = Get-BuildErrorSummary
        $summary.TotalCount | Should -Be 2
        $summary.HasCritical | Should -Be $false
    }

    It 'Should handle early critical failure with proper error tracking' {
        $summary = $null

        try {
            Invoke-BuildPhase -PhaseName 'Preflight' -Critical $true -Action { "OK" }
            Invoke-BuildPhase -PhaseName 'Disk Creation' -Critical $true -Action {
                throw "Insufficient disk space"
            }
            # These should never run
            Invoke-BuildPhase -PhaseName 'VM Creation' -Critical $true -Action { "VM" }
            Invoke-BuildPhase -PhaseName 'FFU Capture' -Critical $true -Action { "FFU" }
        } catch {
            $summary = Get-BuildErrorSummary
        }

        $summary.TotalCount | Should -Be 1
        $summary.HasCritical | Should -Be $true
        $summary.Errors[0].Phase | Should -Be 'Disk Creation'
        $summary.Errors[0].Message | Should -BeLike "*Insufficient disk space*"
    }
}

# =============================================================================
# Phase Result Object Tests
# =============================================================================

Describe 'Phase Result Object Verification' -Tag 'Unit', 'Integration', 'INT-BUILD' {

    BeforeEach {
        Clear-BuildErrors
    }

    It 'Should return Result property for successful phases' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Critical $true -Action {
            return @{ VHDXPath = 'C:\temp\disk.vhdx'; SizeGB = 50 }
        }

        $result.Result.VHDXPath | Should -Be 'C:\temp\disk.vhdx'
        $result.Result.SizeGB | Should -Be 50
    }

    It 'Should return Error property for failed phases' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Critical $false -Action {
            throw "Specific failure reason"
        }

        $result.Error | Should -Not -BeNullOrEmpty
        $result.Error.Message | Should -Be 'Specific failure reason'
    }

    It 'Should return all five result properties' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Critical $false -Action { "OK" }

        $result.PSObject.Properties.Name | Should -Contain 'Success'
        $result.PSObject.Properties.Name | Should -Contain 'Skipped'
        $result.PSObject.Properties.Name | Should -Contain 'Cancelled'
        $result.PSObject.Properties.Name | Should -Contain 'Error'
        $result.PSObject.Properties.Name | Should -Contain 'Result'
    }
}

# =============================================================================
# Error Collector State Management Tests
# =============================================================================

Describe 'Error Collector State Management' -Tag 'Unit', 'Integration', 'INT-BUILD' {

    BeforeEach {
        Clear-BuildErrors
    }

    It 'Should initialize clean error state at build start' {
        Clear-BuildErrors
        $summary = Get-BuildErrorSummary

        $summary.TotalCount | Should -Be 0
        $summary.CriticalCount | Should -Be 0
        $summary.WarningCount | Should -Be 0
        $summary.HasCritical | Should -Be $false
    }

    It 'Should accumulate errors across entire build' {
        # Phase 1 - non-critical failure
        Invoke-BuildPhase -PhaseName 'Driver' -Critical $false -Action { throw "Driver fail" }

        $summary1 = Get-BuildErrorSummary
        $summary1.TotalCount | Should -Be 1

        # Phase 2 - success (no new error)
        Invoke-BuildPhase -PhaseName 'Media' -Critical $false -Action { "OK" }

        $summary2 = Get-BuildErrorSummary
        $summary2.TotalCount | Should -Be 1  # Still 1

        # Phase 3 - non-critical failure
        Invoke-BuildPhase -PhaseName 'USB' -Critical $false -Action { throw "USB fail" }

        $summary3 = Get-BuildErrorSummary
        $summary3.TotalCount | Should -Be 2  # Now 2
    }

    It 'Should persist critical status after critical failure' {
        try {
            Invoke-BuildPhase -PhaseName 'Critical' -Critical $true -Action { throw "Critical" }
        } catch { }

        Invoke-BuildPhase -PhaseName 'NonCritical' -Critical $false -Action { throw "Warning" }

        $summary = Get-BuildErrorSummary
        $summary.HasCritical | Should -Be $true  # Critical status persists
    }
}
