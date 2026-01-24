#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for Orchestrator.ps1 dependency detection (REL-WINPE-02)

.DESCRIPTION
    Tests verify that Orchestrator.ps1 properly:
    - Logs warnings when optional scripts are missing
    - Throws critical error when Run-Sysprep.ps1 is missing
    - Shows execution summary at end
    - Includes full paths in error messages

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\Orchestrator.DependencyDetection.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $script:ProjectRoot = Split-Path $TestRoot -Parent
    $script:OrchestratorPath = Join-Path $script:ProjectRoot 'FFUDevelopment\Apps\Orchestration\Orchestrator.ps1'

    # Verify Orchestrator.ps1 exists
    if (-not (Test-Path $script:OrchestratorPath)) {
        throw "Orchestrator.ps1 not found at: $script:OrchestratorPath"
    }
}

# =============================================================================
# Orchestrator.ps1 Dependency Detection Tests
# =============================================================================

Describe 'Orchestrator.ps1 Dependency Detection' -Tag 'Unit', 'Orchestrator', 'REL-WINPE-02' {

    Context 'Script Structure' {
        It 'Should have executionSummary tracking variable' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match '\$script:executionSummary\s*=\s*@\{'
        }

        It 'Should track Executed scripts' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Executed\s*=\s*.*System\.Collections\.ArrayList'
        }

        It 'Should track Skipped scripts' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Skipped\s*=\s*.*System\.Collections\.ArrayList'
        }

        It 'Should track Failed scripts' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Failed\s*=\s*.*System\.Collections\.ArrayList'
        }
    }

    Context 'Missing Optional Scripts Warning' {
        It 'Should log SKIP warning when script not found' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'SKIP.*Script not found'
        }

        It 'Should include expected path in skip warning' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Expected at:.*\$scriptFile'
        }

        It 'Should add skipped scripts to summary with reason' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match '\$script:executionSummary\.Skipped\.Add\('
        }

        It 'Should include File not found as reason' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Reason\s*=\s*.*File not found'
        }
    }

    Context 'Dependency-Based Skip Tracking' {
        It 'Should track skips for Install-Win32Apps.ps1 without JSON files' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'WinGetWin32Apps\.json or UserAppList\.json'
        }

        It 'Should track skips for Install-StoreApps.ps1 without MSStore folder' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'MSStore folder empty or not found'
        }

        It 'Should track skips for Invoke-AppsScript.ps1 without config' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'AppsScriptVariables\.json not found'
        }
    }

    Context 'Critical Script Handling (Run-Sysprep.ps1)' {
        It 'Should have CRITICAL ERROR message for missing Run-Sysprep.ps1' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'CRITICAL ERROR: Run-Sysprep\.ps1 not found'
        }

        It 'Should throw when Run-Sysprep.ps1 is missing' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'throw.*CRITICAL.*Run-Sysprep\.ps1 not found'
        }

        It 'Should include expected location in error' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Expected location:.*\$sysprepScript'
        }

        It 'Should list possible causes' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Possible causes:'
            $content | Should -Match 'Apps ISO was not created correctly'
            $content | Should -Match 'Orchestration folder is missing files'
            $content | Should -Match 'File was accidentally deleted'
        }

        It 'Should explain why sysprep is required' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'FFU will not be properly generalized'
        }
    }

    Context 'Execution Summary' {
        It 'Should have Execution Summary section' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Orchestrator Execution Summary'
        }

        It 'Should display Scripts Executed count' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Scripts Executed:.*executionSummary\.Executed\.Count'
        }

        It 'Should display Scripts Skipped count' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Scripts Skipped:.*executionSummary\.Skipped\.Count'
        }

        It 'Should display Scripts Failed count' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Scripts Failed:.*executionSummary\.Failed\.Count'
        }

        It 'Should use OK marker for executed scripts' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'OK.*\$executed'
        }

        It 'Should use -- marker for skipped scripts' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match '--.*skipped\.Script'
        }

        It 'Should use !! marker for failed scripts' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match '!!.*failed\.Script'
        }
    }

    Context 'Error Handling' {
        It 'Should wrap script execution in try/catch' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            # Should have try block followed by script invocation
            $content | Should -Match 'try\s*\{'
            $content | Should -Match '&\s*\$scriptFile'
            $content | Should -Match '\}\s*catch'
        }

        It 'Should log ERROR when script fails' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'ERROR.*Script failed'
        }

        It 'Should track failed scripts in summary' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'executionSummary\.Failed\.Add\('
        }

        It 'Should include exception message in failure tracking' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Error\s*=\s*\$_\.Exception\.Message'
        }
    }

    Context 'Security Integration' {
        It 'Should track integrity check failures as Failed' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            # Security errors should also populate Failed summary
            $content | Should -Match 'Error\s*=\s*.Integrity check failed'
        }
    }

    Context 'Color Coding' {
        It 'Should use Yellow for skip warnings' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'SKIP.*-ForegroundColor Yellow'
        }

        It 'Should use Red for critical errors' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'CRITICAL ERROR.*-ForegroundColor Red'
        }

        It 'Should use Gray for paths in messages' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Expected at:.*-ForegroundColor Gray'
        }

        It 'Should use Cyan for summary header' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'Execution Summary.*-ForegroundColor Cyan'
        }

        It 'Should use Green for executed scripts in summary' {
            $content = Get-Content -Path $script:OrchestratorPath -Raw
            $content | Should -Match 'OK.*-ForegroundColor Green'
        }
    }
}

# =============================================================================
# Line Count Verification
# =============================================================================

Describe 'Orchestrator.ps1 Code Coverage' -Tag 'Unit', 'Orchestrator', 'Coverage' {

    It 'Should have minimum required lines for full implementation' {
        $content = Get-Content -Path $script:OrchestratorPath
        $content.Count | Should -BeGreaterThan 400 -Because 'Full dependency detection adds ~100 lines to base script'
    }

    It 'Should have REL-WINPE-02 comments documenting the feature' {
        $content = Get-Content -Path $script:OrchestratorPath -Raw
        ($content | Select-String -Pattern 'REL-WINPE-02' -AllMatches).Matches.Count | Should -BeGreaterOrEqual 5
    }
}
