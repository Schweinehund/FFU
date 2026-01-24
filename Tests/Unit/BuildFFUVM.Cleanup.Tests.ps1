#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for BuildFFUVM.ps1 cleanup and error summary integration.

.DESCRIPTION
    Validates REL-BUILD-02 (cleanup on termination), REL-BUILD-04 (error summary),
    and REL-BUILD-05 (cleanup on exceptions) requirements.

.NOTES
    Phase: 23-04
    Requirements: REL-BUILD-02, REL-BUILD-04, REL-BUILD-05
#>

Describe 'BuildFFUVM.ps1 Cleanup and Error Summary' -Tag 'Unit', 'BuildFFUVM', 'REL-BUILD-02', 'REL-BUILD-04', 'REL-BUILD-05' {
    BeforeAll {
        # Import required modules
        $modulesPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules'
        $env:PSModulePath = "$modulesPath;$env:PSModulePath"
        Import-Module (Join-Path $modulesPath 'FFU.Core') -Force

        # Script path for content analysis
        $script:ScriptPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\BuildFFUVM.ps1'
    }

    AfterEach {
        # Clean up module state between tests
        if (Get-Command 'Clear-BuildErrors' -ErrorAction SilentlyContinue) {
            Clear-BuildErrors
        }
        if (Get-Command 'Clear-CleanupRegistry' -ErrorAction SilentlyContinue) {
            Clear-CleanupRegistry
        }
    }

    Context 'Error Aggregation Integration' {
        It 'Should accumulate errors from multiple phases' {
            Add-BuildError -Phase 'DriverDownload' -Message 'Driver not found' -Severity Warning
            Add-BuildError -Phase 'UpdateDownload' -Message 'KB failed' -Severity Warning
            Add-BuildError -Phase 'VMCreation' -Message 'VM failed' -Severity Critical

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 3
            $summary.CriticalCount | Should -Be 1
            $summary.WarningCount | Should -Be 2
            $summary.HasCritical | Should -Be $true
        }

        It 'Should clear errors between builds' {
            Add-BuildError -Phase 'Test' -Message 'Error' -Severity Warning
            Clear-BuildErrors
            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 0
        }

        It 'Should preserve error details (Phase, Message, Severity, Timestamp)' {
            Add-BuildError -Phase 'TestPhase' -Message 'Test message' -Severity Info
            $summary = Get-BuildErrorSummary
            $summary.Errors[0].Phase | Should -Be 'TestPhase'
            $summary.Errors[0].Message | Should -Be 'Test message'
            $summary.Errors[0].Severity | Should -Be 'Info'
            $summary.Errors[0].Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should return empty summary when no errors' {
            Clear-BuildErrors
            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 0
            $summary.CriticalCount | Should -Be 0
            $summary.WarningCount | Should -Be 0
            $summary.InfoCount | Should -Be 0
            $summary.HasCritical | Should -Be $false
        }

        It 'Should count severity levels correctly' {
            Add-BuildError -Phase 'Test1' -Message 'Critical 1' -Severity Critical
            Add-BuildError -Phase 'Test2' -Message 'Critical 2' -Severity Critical
            Add-BuildError -Phase 'Test3' -Message 'Warning 1' -Severity Warning
            Add-BuildError -Phase 'Test4' -Message 'Info 1' -Severity Info
            Add-BuildError -Phase 'Test5' -Message 'Info 2' -Severity Info
            Add-BuildError -Phase 'Test6' -Message 'Info 3' -Severity Info

            $summary = Get-BuildErrorSummary
            $summary.TotalCount | Should -Be 6
            $summary.CriticalCount | Should -Be 2
            $summary.WarningCount | Should -Be 1
            $summary.InfoCount | Should -Be 3
        }
    }

    Context 'Cleanup Registry Integration' {
        It 'Should register cleanup actions' {
            Register-CleanupAction -Name 'Test cleanup' -Action { }
            $registry = Get-CleanupRegistry
            $registry.Count | Should -Be 1
        }

        It 'Should clear cleanup registry' {
            Register-CleanupAction -Name 'Test' -Action { }
            Clear-CleanupRegistry
            $registry = Get-CleanupRegistry
            $registry.Count | Should -Be 0
        }

        It 'Should invoke cleanup in LIFO order' {
            $script:cleanupOrder = @()
            Register-CleanupAction -Name 'First' -Action { $script:cleanupOrder += 'First' }
            Register-CleanupAction -Name 'Second' -Action { $script:cleanupOrder += 'Second' }

            Invoke-FailureCleanup -Reason 'Test'

            $script:cleanupOrder[0] | Should -Be 'Second'
            $script:cleanupOrder[1] | Should -Be 'First'
        }

        It 'Should continue cleanup even if one action fails' {
            $script:cleanupRan = @()
            Register-CleanupAction -Name 'First' -Action { $script:cleanupRan += 'First' }
            Register-CleanupAction -Name 'Failing' -Action { throw 'Cleanup error' }
            Register-CleanupAction -Name 'Third' -Action { $script:cleanupRan += 'Third' }

            { Invoke-FailureCleanup -Reason 'Test' } | Should -Not -Throw

            $script:cleanupRan | Should -Contain 'First'
            $script:cleanupRan | Should -Contain 'Third'
        }
    }

    Context 'Trap Handler Behavior' {
        It 'Should have trap handler in BuildFFUVM.ps1' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'trap\s*\{'
        }

        It 'Should call Invoke-FailureCleanup in trap' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Invoke-FailureCleanup'
        }

        It 'Should call Add-BuildError in trap with Unhandled phase' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match "Add-BuildError.*-Phase\s*'Unhandled'"
        }

        It 'Should display error summary in trap' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'BUILD FAILED - Error Summary'
        }

        It 'Should use break statement in trap' {
            $content = Get-Content $script:ScriptPath -Raw
            # Match break inside the trap block
            $content | Should -Match 'trap\s*\{[\s\S]*?break[\s\S]*?\}'
        }
    }

    Context 'PowerShell Exit Event Handler' {
        It 'Should have PowerShell.Exiting event handler' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Register-EngineEvent.*PowerShell\.Exiting'
        }

        It 'Should call Invoke-FailureCleanup in exit handler' {
            $content = Get-Content $script:ScriptPath -Raw
            # Match within the exit event action block
            $content | Should -Match 'PowerShell\.Exiting[\s\S]*?Invoke-FailureCleanup'
        }
    }

    Context 'Build Completion Summary' {
        It 'Should have error summary section at build end' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'BUILD COMPLETED WITH ISSUES'
        }

        It 'Should call Get-BuildErrorSummary at build end' {
            $content = Get-Content $script:ScriptPath -Raw
            # Match the completion section (after security cleanup)
            $content | Should -Match 'BUILD ERROR SUMMARY.*REL-BUILD-04'
        }

        It 'Should clear errors at build end' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Clear-BuildErrors'
        }

        It 'Should call Write-BuildErrorSummary for logging' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Write-BuildErrorSummary'
        }

        It 'Should show green message when no issues' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Build completed with no issues'
        }
    }

    Context 'ThreadJob Safety' {
        It 'Should use InvokeCommand.GetCommand for Add-BuildError check' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match "InvokeCommand\.GetCommand\('Add-BuildError'"
        }

        It 'Should use InvokeCommand.GetCommand for Get-BuildErrorSummary check' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match "InvokeCommand\.GetCommand\('Get-BuildErrorSummary'"
        }

        It 'Should use InvokeCommand.GetCommand for Clear-BuildErrors check' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match "InvokeCommand\.GetCommand\('Clear-BuildErrors'"
        }

        It 'Should use InvokeCommand.GetCommand for Get-CleanupRegistry check' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match "InvokeCommand\.GetCommand\('Get-CleanupRegistry'"
        }
    }

    Context 'Error Summary Formatting' {
        It 'Should format errors with severity colors' {
            $content = Get-Content $script:ScriptPath -Raw
            # Check for color switch pattern - match across newlines
            $content | Should -Match '\$color\s*=\s*switch\s*\(\$err\.Severity\)'
            $content | Should -Match "'Critical'\s*\{\s*'Red'\s*\}"
            $content | Should -Match "'Warning'\s*\{\s*'Yellow'\s*\}"
        }

        It 'Should include phase name in error output' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match '\$err\.Phase'
        }

        It 'Should include error message in output' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match '\$err\.Message'
        }
    }

    Context 'Integration Scenarios' {
        It 'Should allow multiple errors then clear for new build' {
            # Simulate first build with errors
            Add-BuildError -Phase 'Phase1' -Message 'Error 1' -Severity Warning
            Add-BuildError -Phase 'Phase2' -Message 'Error 2' -Severity Critical

            $summary1 = Get-BuildErrorSummary
            $summary1.TotalCount | Should -Be 2

            # Clear for new build
            Clear-BuildErrors

            # Simulate second build
            Add-BuildError -Phase 'Phase3' -Message 'Error 3' -Severity Info

            $summary2 = Get-BuildErrorSummary
            $summary2.TotalCount | Should -Be 1
            $summary2.Errors[0].Phase | Should -Be 'Phase3'
        }

        It 'Should handle exception capture in error collector' {
            $testException = [System.Exception]::new('Test exception message')
            Add-BuildError -Phase 'TestPhase' -Message 'Test error' -Severity Critical -Exception $testException

            $summary = Get-BuildErrorSummary
            $summary.Errors[0].Exception | Should -Not -BeNullOrEmpty
            $summary.Errors[0].Exception.Message | Should -Be 'Test exception message'
        }
    }
}
