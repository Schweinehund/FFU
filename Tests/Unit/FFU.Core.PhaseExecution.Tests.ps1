#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for FFU.Core phase execution wrapper (Invoke-BuildPhase).

.DESCRIPTION
    Comprehensive tests for the Invoke-BuildPhase function which provides
    consistent phase execution with graceful degradation support.
    Covers: basic execution, critical failures, non-critical failures,
    error aggregation integration, and cancellation support.

.NOTES
    Part of REL-BUILD-01 (Phase Wrapper with Continue-on-Failure)
    Created: 2026-01-24
    FFU.Core v1.0.22

    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.PhaseExecution.Tests.ps1 -Output Detailed
    Filter by tag: Invoke-Pester -Path .\Tests\Unit\FFU.Core.PhaseExecution.Tests.ps1 -Tag 'REL-BUILD-01' -Output Detailed
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
# Invoke-BuildPhase Basic Execution Tests
# =============================================================================

Describe 'Invoke-BuildPhase Basic Execution' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        # Clear error collector between tests to ensure isolation
        Clear-BuildErrors
    }

    It 'Should execute Action scriptblock successfully' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { return 'success' }
        $result.Success | Should -Be $true
        $result.Result | Should -Be 'success'
    }

    It 'Should set Success to true on successful execution' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { 1 + 1 }
        $result.Success | Should -Be $true
    }

    It 'Should return Result from Action' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { @{Key = 'Value'} }
        $result.Result.Key | Should -Be 'Value'
    }

    It 'Should initialize Skipped and Cancelled to false' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { $true }
        $result.Skipped | Should -Be $false
        $result.Cancelled | Should -Be $false
    }

    It 'Should initialize Error to null on success' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { 'ok' }
        $result.Error | Should -BeNullOrEmpty
    }

    It 'Should return complex objects from Action' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action {
            [PSCustomObject]@{
                Name = 'TestVM'
                Status = 'Running'
                Memory = 4GB
            }
        }
        $result.Result.Name | Should -Be 'TestVM'
        $result.Result.Status | Should -Be 'Running'
        $result.Result.Memory | Should -Be 4GB
    }

    It 'Should handle Action returning $null' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { $null }
        $result.Success | Should -Be $true
        $result.Result | Should -BeNullOrEmpty
    }

    It 'Should handle Action returning array' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { @(1, 2, 3) }
        $result.Success | Should -Be $true
        $result.Result | Should -HaveCount 3
    }
}

# =============================================================================
# Critical Phase Failure Tests
# =============================================================================

Describe 'Critical Phase Failures' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should throw on Critical phase failure (default)' {
        { Invoke-BuildPhase -PhaseName 'Critical' -Action { throw 'fail' } } | Should -Throw
    }

    It 'Should throw on Critical phase failure when Critical=$true explicit' {
        { Invoke-BuildPhase -PhaseName 'Critical' -Action { throw 'fail' } -Critical $true } | Should -Throw
    }

    It 'Should add Critical error to collector on failure' {
        try { Invoke-BuildPhase -PhaseName 'VHDX' -Action { throw 'VHDX failed' } } catch {}
        $summary = Get-BuildErrorSummary
        $summary.CriticalCount | Should -Be 1
        $summary.Errors[0].Phase | Should -Be 'VHDX'
    }

    It 'Should include exception in error collector' {
        try { Invoke-BuildPhase -PhaseName 'Test' -Action { throw 'specific error' } } catch {}
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Exception.Message | Should -Be 'specific error'
    }

    It 'Should preserve original exception message in throw' {
        $errorMsg = $null
        try {
            Invoke-BuildPhase -PhaseName 'Test' -Action { throw 'original message' }
        }
        catch {
            $errorMsg = $_.Exception.Message
        }
        $errorMsg | Should -Be 'original message'
    }

    It 'Should set Severity to Critical in error collector' {
        try { Invoke-BuildPhase -PhaseName 'FFU' -Action { throw 'ffu error' } } catch {}
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Severity | Should -Be 'Critical'
    }
}

# =============================================================================
# Non-Critical Phase Failure Tests (Graceful Degradation)
# =============================================================================

Describe 'Non-Critical Phase Failures' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should not throw on non-critical phase failure' {
        { Invoke-BuildPhase -PhaseName 'USB' -Action { throw 'fail' } -Critical $false } | Should -Not -Throw
    }

    It 'Should set Success to false on non-critical failure' {
        $result = Invoke-BuildPhase -PhaseName 'USB' -Action { throw 'fail' } -Critical $false
        $result.Success | Should -Be $false
    }

    It 'Should add Warning error to collector for non-critical failure' {
        Invoke-BuildPhase -PhaseName 'Deploy' -Action { throw 'deploy fail' } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.WarningCount | Should -Be 1
        $summary.CriticalCount | Should -Be 0
    }

    It 'Should include Error property on non-critical failure' {
        $result = Invoke-BuildPhase -PhaseName 'USB' -Action { throw 'usb error' } -Critical $false
        $result.Error | Should -Not -BeNullOrEmpty
        $result.Error.Message | Should -Be 'usb error'
    }

    It 'Should set Severity to Warning in error collector for non-critical' {
        Invoke-BuildPhase -PhaseName 'USB' -Action { throw 'usb fail' } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Severity | Should -Be 'Warning'
    }

    It 'Should not set Cancelled on non-critical failure' {
        $result = Invoke-BuildPhase -PhaseName 'USB' -Action { throw 'fail' } -Critical $false
        $result.Cancelled | Should -Be $false
    }

    It 'Should not set Skipped on non-critical failure' {
        $result = Invoke-BuildPhase -PhaseName 'USB' -Action { throw 'fail' } -Critical $false
        $result.Skipped | Should -Be $false
    }
}

# =============================================================================
# Mixed Critical and Non-Critical Phase Tests
# =============================================================================

Describe 'Mixed Critical and Non-Critical Phases' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should accumulate errors from multiple phases' {
        # Non-critical failures
        Invoke-BuildPhase -PhaseName 'USB1' -Action { throw 'usb1' } -Critical $false
        Invoke-BuildPhase -PhaseName 'USB2' -Action { throw 'usb2' } -Critical $false

        $summary = Get-BuildErrorSummary
        $summary.TotalCount | Should -Be 2
        $summary.WarningCount | Should -Be 2
        $summary.HasCritical | Should -Be $false
    }

    It 'Should correctly classify mixed severity errors' {
        Invoke-BuildPhase -PhaseName 'USB' -Action { throw 'usb' } -Critical $false
        try { Invoke-BuildPhase -PhaseName 'FFU' -Action { throw 'ffu' } -Critical $true } catch {}

        $summary = Get-BuildErrorSummary
        $summary.TotalCount | Should -Be 2
        $summary.CriticalCount | Should -Be 1
        $summary.WarningCount | Should -Be 1
        $summary.HasCritical | Should -Be $true
    }

    It 'Should maintain error order across phases' {
        Invoke-BuildPhase -PhaseName 'Phase1' -Action { throw 'error1' } -Critical $false
        Invoke-BuildPhase -PhaseName 'Phase2' -Action { throw 'error2' } -Critical $false
        Invoke-BuildPhase -PhaseName 'Phase3' -Action { throw 'error3' } -Critical $false

        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Phase | Should -Be 'Phase1'
        $summary.Errors[1].Phase | Should -Be 'Phase2'
        $summary.Errors[2].Phase | Should -Be 'Phase3'
    }
}

# =============================================================================
# Phase Naming and Error Message Tests
# =============================================================================

Describe 'Phase Naming and Error Messages' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should use PhaseName in error message' {
        Invoke-BuildPhase -PhaseName 'DriverExtraction' -Action { throw 'driver error' } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Phase | Should -Be 'DriverExtraction'
    }

    It 'Should handle PhaseName with spaces' {
        Invoke-BuildPhase -PhaseName 'Driver Extraction Phase' -Action { throw 'err' } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Phase | Should -Be 'Driver Extraction Phase'
    }

    It 'Should handle PhaseName with special characters' {
        Invoke-BuildPhase -PhaseName 'Phase_1.2 (Test)' -Action { throw 'err' } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Phase | Should -Be 'Phase_1.2 (Test)'
    }

    It 'Should capture full exception message in error' {
        $longMsg = "This is a detailed error message explaining what went wrong during the operation"
        Invoke-BuildPhase -PhaseName 'Test' -Action { throw $longMsg } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Message | Should -Be $longMsg
    }
}

# =============================================================================
# Result Object Structure Tests
# =============================================================================

Describe 'Result Object Structure' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should return object with all required properties' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { 'ok' }

        $result.PSObject.Properties.Name | Should -Contain 'Success'
        $result.PSObject.Properties.Name | Should -Contain 'Skipped'
        $result.PSObject.Properties.Name | Should -Contain 'Cancelled'
        $result.PSObject.Properties.Name | Should -Contain 'Error'
        $result.PSObject.Properties.Name | Should -Contain 'Result'
    }

    It 'Should return correct property count (5)' {
        $result = Invoke-BuildPhase -PhaseName 'Test' -Action { 'ok' }
        $result.PSObject.Properties | Should -HaveCount 5
    }
}

# =============================================================================
# Integration with Build Error Aggregation Tests
# =============================================================================

Describe 'Integration with Build Error Aggregation' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should work with Get-BuildErrorSummary after multiple phases' {
        # Simulate a real build scenario
        $r1 = Invoke-BuildPhase -PhaseName 'VHDX Creation' -Action { 'vhdx created' }
        $r2 = Invoke-BuildPhase -PhaseName 'USB Media' -Action { throw 'no usb' } -Critical $false
        $r3 = Invoke-BuildPhase -PhaseName 'Deploy Media' -Action { throw 'deploy fail' } -Critical $false

        $r1.Success | Should -Be $true
        $r2.Success | Should -Be $false
        $r3.Success | Should -Be $false

        $summary = Get-BuildErrorSummary
        $summary.TotalCount | Should -Be 2
        $summary.WarningCount | Should -Be 2
    }

    It 'Should enable decision making based on HasCritical' {
        Invoke-BuildPhase -PhaseName 'USB' -Action { throw 'usb' } -Critical $false
        Invoke-BuildPhase -PhaseName 'ISO' -Action { throw 'iso' } -Critical $false

        $summary = Get-BuildErrorSummary
        # No critical errors means build can continue
        $summary.HasCritical | Should -Be $false

        # Now add a critical error
        try { Invoke-BuildPhase -PhaseName 'FFU' -Action { throw 'ffu fail' } -Critical $true } catch {}

        $summary = Get-BuildErrorSummary
        $summary.HasCritical | Should -Be $true
    }

    It 'Should work with Write-BuildErrorSummary' {
        Invoke-BuildPhase -PhaseName 'Test1' -Action { throw 'e1' } -Critical $false
        Invoke-BuildPhase -PhaseName 'Test2' -Action { throw 'e2' } -Critical $false

        $summary = Get-BuildErrorSummary

        # Should not throw when writing summary
        { Write-BuildErrorSummary -Summary $summary } | Should -Not -Throw
    }
}

# =============================================================================
# Parameter Validation Tests
# =============================================================================

Describe 'Parameter Validation' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should require PhaseName parameter' {
        { Invoke-BuildPhase -Action { 'ok' } } | Should -Throw
    }

    It 'Should require Action parameter' {
        { Invoke-BuildPhase -PhaseName 'Test' } | Should -Throw
    }

    It 'Should reject empty PhaseName' {
        { Invoke-BuildPhase -PhaseName '' -Action { 'ok' } } | Should -Throw
    }

    It 'Should reject null Action' {
        { Invoke-BuildPhase -PhaseName 'Test' -Action $null } | Should -Throw
    }

    It 'Should accept MessagingContext as null (default)' {
        { Invoke-BuildPhase -PhaseName 'Test' -Action { 'ok' } -MessagingContext $null } | Should -Not -Throw
    }

    It 'Should accept MessagingContext hashtable' {
        $context = @{ CancellationToken = $null }
        { Invoke-BuildPhase -PhaseName 'Test' -Action { 'ok' } -MessagingContext $context } | Should -Not -Throw
    }
}

# =============================================================================
# Exception Type Handling Tests
# =============================================================================

Describe 'Exception Type Handling' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should capture System.Exception' {
        Invoke-BuildPhase -PhaseName 'Test' -Action {
            throw [System.Exception]::new('base exception')
        } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Exception | Should -BeOfType [System.Exception]
    }

    It 'Should capture InvalidOperationException' {
        Invoke-BuildPhase -PhaseName 'Test' -Action {
            throw [System.InvalidOperationException]::new('invalid op')
        } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Exception | Should -BeOfType [System.InvalidOperationException]
    }

    It 'Should capture ArgumentException' {
        Invoke-BuildPhase -PhaseName 'Test' -Action {
            throw [System.ArgumentException]::new('bad arg')
        } -Critical $false
        $summary = Get-BuildErrorSummary
        $summary.Errors[0].Exception | Should -BeOfType [System.ArgumentException]
    }
}

# =============================================================================
# Real-World Simulation Tests
# =============================================================================

Describe 'Real-World Simulation' -Tag 'Unit', 'FFU.Core', 'PhaseExecution', 'REL-BUILD-01' {

    AfterEach {
        Clear-BuildErrors
    }

    It 'Should simulate typical build with mixed results' {
        # Simulate: some phases succeed, some fail non-critically
        $results = @()

        # Critical phases (must succeed or stop)
        $results += Invoke-BuildPhase -PhaseName 'Initialize Environment' -Action { @{Ready = $true} }
        $results += Invoke-BuildPhase -PhaseName 'Create VHDX' -Action { @{Path = 'C:\temp\test.vhdx'} }

        # Non-critical phases (may fail)
        $results += Invoke-BuildPhase -PhaseName 'Create USB Media' -Action { throw 'No USB drive' } -Critical $false
        $results += Invoke-BuildPhase -PhaseName 'Create ISO' -Action { @{Path = 'C:\temp\deploy.iso'} } -Critical $false
        $results += Invoke-BuildPhase -PhaseName 'Deploy to Network' -Action { throw 'Network unavailable' } -Critical $false

        # Verify results
        ($results | Where-Object { $_.Success }).Count | Should -Be 3
        ($results | Where-Object { -not $_.Success }).Count | Should -Be 2

        # Verify error summary
        $summary = Get-BuildErrorSummary
        $summary.TotalCount | Should -Be 2
        $summary.HasCritical | Should -Be $false
        $summary.WarningCount | Should -Be 2
    }
}
