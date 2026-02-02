#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for Orchestrator.ps1 Security Platform initialization delay (DEPLOY-02)

.DESCRIPTION
    Tests verify that Orchestrator.ps1 properly implements a 30-second delay after
    integrity verification to allow Windows Security Platform services to initialize
    before app installation scripts execute.

    Tests use content-based validation (same pattern as Orchestrator.DependencyDetection.Tests.ps1).

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\Orchestrator.SecurityPlatformDelay.Tests.ps1 -Output Detailed
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

    # Load content for pattern matching
    $script:OrchestratorContent = Get-Content -Path $script:OrchestratorPath -Raw
}

Describe 'DEPLOY-02: Security Platform Delay' -Tag 'Unit', 'Orchestrator', 'DEPLOY-02' {

    Context 'Delay Block Structure' {
        It 'Should define securityPlatformDelay variable set to 30' {
            $script:OrchestratorContent | Should -Match '\$securityPlatformDelay\s*=\s*30'
        }

        It 'Should use Start-Sleep for delay' {
            $script:OrchestratorContent | Should -Match 'Start-Sleep\s+-Seconds\s+1'
        }

        It 'Should have countdown loop' {
            $script:OrchestratorContent | Should -Match 'for\s*\(\s*\$i\s*=\s*\$securityPlatformDelay'
        }

        It 'Should decrement counter in loop' {
            $script:OrchestratorContent | Should -Match '\$i\s*-gt\s*0'
            $script:OrchestratorContent | Should -Match '\$i--'
        }

        It 'Should display countdown with Write-Host -NoNewline' {
            $script:OrchestratorContent | Should -Match 'Write-Host.*Time remaining.*\$i.*-NoNewline'
        }

        It 'Should indicate completion after delay' {
            $script:OrchestratorContent | Should -Match 'delay complete'
        }

        It 'Should use carriage return for in-place countdown update' {
            $script:OrchestratorContent | Should -Match '`r'
        }
    }

    Context 'Logging' {
        It 'Should log delay start with Write-OrchestratorLog' {
            $script:OrchestratorContent | Should -Match 'Write-OrchestratorLog.*Waiting.*securityPlatformDelay.*seconds'
        }

        It 'Should mention Windows Security Platform in log' {
            $script:OrchestratorContent | Should -Match 'Write-OrchestratorLog.*Windows Security Platform'
        }

        It 'Should log delay completion' {
            $script:OrchestratorContent | Should -Match 'Write-OrchestratorLog.*Security Platform.*delay complete'
        }

        It 'Should log message about proceeding with script execution' {
            $script:OrchestratorContent | Should -Match 'Write-OrchestratorLog.*Proceeding with script execution'
        }

        It 'Should use Info level for logging' {
            $script:OrchestratorContent | Should -Match 'Write-OrchestratorLog.*-Level\s+Info'
        }
    }

    Context 'User Display' {
        It 'Should display waiting message to user' {
            $script:OrchestratorContent | Should -Match 'Write-Host.*Waiting.*Windows Security Platform.*initialize'
        }

        It 'Should use Cyan color for waiting message' {
            $script:OrchestratorContent | Should -Match 'Write-Host.*Waiting.*Windows Security Platform.*-ForegroundColor\s+Cyan'
        }

        It 'Should use Gray color for countdown display' {
            $script:OrchestratorContent | Should -Match 'Write-Host.*Time remaining.*-ForegroundColor\s+Gray'
        }

        It 'Should use Green color for completion message' {
            $script:OrchestratorContent | Should -Match 'Write-Host.*delay complete.*-ForegroundColor\s+Green'
        }

        It 'Should have blank lines for visual spacing' {
            $script:OrchestratorContent | Should -Match 'Write-Host\s+""'
        }
    }

    Context 'Placement' {
        It 'Should appear after integrity verification section' {
            # Verify delay comes after "verified" message from security integrity checks
            $integrityIndex = $script:OrchestratorContent.IndexOf('SECURITY:')
            $delayIndex = $script:OrchestratorContent.IndexOf('$securityPlatformDelay')
            $delayIndex | Should -BeGreaterThan $integrityIndex -Because 'Delay should be after integrity verification'
        }

        It 'Should appear before script list definition' {
            # Verify delay comes before scriptList array definition
            $delayIndex = $script:OrchestratorContent.IndexOf('$securityPlatformDelay')
            $scriptListIndex = $script:OrchestratorContent.IndexOf('$scriptList = @(')
            $scriptListIndex | Should -BeGreaterThan $delayIndex -Because 'Delay should be before script execution'
        }

        It 'Should not modify script execution loop' {
            # Verify the foreach script execution loop still exists
            $script:OrchestratorContent | Should -Match 'foreach\s*\(\s*\$script\s+in\s+\$scriptList\s*\)'
        }
    }

    Context 'Comment Documentation' {
        It 'Should have DEPLOY-02 reference in comments' {
            $script:OrchestratorContent | Should -Match '#.*DEPLOY-02'
        }

        It 'Should explain Security Platform in comments' {
            $script:OrchestratorContent | Should -Match '#.*Security Platform.*services.*initialize'
        }

        It 'Should mention audit mode in comments' {
            $script:OrchestratorContent | Should -Match '#.*audit mode'
        }

        It 'Should explain why delay is needed' {
            $script:OrchestratorContent | Should -Match '#.*app installations.*depend.*security'
        }

        It 'Should have comment block separator' {
            $script:OrchestratorContent | Should -Match '#\s*=+'
        }
    }

    Context 'Configuration' {
        It 'Should use 30 seconds as delay duration' {
            # Verify the hardcoded value is 30 seconds (Phase 43 requirement)
            $script:OrchestratorContent | Should -Match '\$securityPlatformDelay\s*=\s*30'
        }

        It 'Should have inline comment explaining seconds unit' {
            $script:OrchestratorContent | Should -Match '\$securityPlatformDelay\s*=\s*30\s*#.*seconds'
        }
    }
}

Describe 'Orchestrator.ps1 DEPLOY-02 Integration' -Tag 'Unit', 'Orchestrator', 'Integration' {

    Context 'Code Coverage' {
        It 'Should have minimum required lines for Security Platform delay' {
            $content = Get-Content -Path $script:OrchestratorPath
            $content.Count | Should -BeGreaterThan 180 -Because 'Security Platform delay adds ~20 lines'
        }

        It 'Should have DEPLOY-02 comments documenting the feature' {
            ($script:OrchestratorContent | Select-String -Pattern 'DEPLOY-02' -AllMatches).Matches.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Existing Functionality Preserved' {
        It 'Should still have executionSummary tracking' {
            $script:OrchestratorContent | Should -Match '\$script:executionSummary'
        }

        It 'Should still have dependency detection' {
            $script:OrchestratorContent | Should -Match 'Script not found'
        }

        It 'Should still have error handling' {
            $script:OrchestratorContent | Should -Match 'ERROR.*Script failed'
        }

        It 'Should still have security integrity checks' {
            $script:OrchestratorContent | Should -Match 'SECURITY:'
        }
    }

    Context 'Execution Flow' {
        It 'Should follow correct order: integrity then delay then scripts' {
            $integrityIndex = $script:OrchestratorContent.IndexOf('SECURITY:')
            $delayIndex = $script:OrchestratorContent.IndexOf('$securityPlatformDelay')
            $scriptListIndex = $script:OrchestratorContent.IndexOf('$scriptList = @(')

            $integrityIndex | Should -BeLessThan $delayIndex
            $delayIndex | Should -BeLessThan $scriptListIndex
        }

        It 'Should have delay between log initialization and script execution' {
            $logFunctionIndex = $script:OrchestratorContent.IndexOf('function Write-OrchestratorLog')
            $delayIndex = $script:OrchestratorContent.IndexOf('$securityPlatformDelay')
            $scriptListIndex = $script:OrchestratorContent.IndexOf('$scriptList = @(')

            $logFunctionIndex | Should -BeLessThan $delayIndex
            $delayIndex | Should -BeLessThan $scriptListIndex
        }
    }
}
