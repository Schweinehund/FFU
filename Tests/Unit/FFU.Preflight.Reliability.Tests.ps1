#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Reliability tests for FFU.Preflight module.

.DESCRIPTION
    Tests REL-PRE-03 (WIMMount Repair Resilience) requirements for FFU.Preflight module.
    Part of v1.9.0 Reliability Hardening milestone, Phase 22.

.NOTES
    REL-PRE-03: WIMMount repair includes retry logic for transient service start failures
    - Invoke-WimMountRepairWithRetry wraps repair steps with exponential backoff
    - Multiple repair strategies attempted before declaring failure
#>

BeforeAll {
    # Get paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulesPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\Modules'

    # Add modules folder to PSModulePath if not present
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Import the FFU.Preflight module
    Import-Module (Join-Path $ModulesPath 'FFU.Preflight\FFU.Preflight.psd1') -Force -ErrorAction Stop
}

Describe 'REL-PRE-03: WIMMount Repair Resilience' -Tag 'Unit', 'FFU.Preflight', 'Reliability', 'REL-PRE-03' {

    Context 'Invoke-WimMountRepairWithRetry function' {

        It 'Should exist as internal helper' {
            $module = Get-Module FFU.Preflight
            $helper = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry} })
            $helper | Should -Not -BeNullOrEmpty
        }

        It 'Should have MaxRetries parameter' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match '\$MaxRetries'
        }

        It 'Should have BaseDelaySeconds parameter for exponential backoff' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match '\$BaseDelaySeconds'
        }

        It 'Should have ActionName parameter for logging' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match '\$ActionName'
        }

        It 'Should have RepairAction parameter for scriptblock' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match '\$RepairAction'
        }

        It 'Should have Details parameter for tracking' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match '\$Details'
        }

        It 'Should implement exponential backoff calculation' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match 'Pow.*2'
            $source | Should -Match 'Get-Random'
        }

        It 'Should return boolean success indicator' {
            $module = Get-Module FFU.Preflight
            $helper = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry} })
            # Check OutputType attribute
            $outputTypeAttr = $helper.Ast.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'OutputType' }
            $outputTypeAttr | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Test-FFUWimMount repair strategies' {

        It 'Should use Invoke-WimMountRepairWithRetry for service start' {
            $source = (Get-Command Test-FFUWimMount).ScriptBlock.ToString()
            # Check separately due to multi-line matching
            $source | Should -Match 'Invoke-WimMountRepairWithRetry'
            $source | Should -Match 'sc start wimmount'
        }

        It 'Should use Invoke-WimMountRepairWithRetry for filter load' {
            $source = (Get-Command Test-FFUWimMount).ScriptBlock.ToString()
            $source | Should -Match 'Invoke-WimMountRepairWithRetry'
            $source | Should -Match 'fltmc load WimMount'
        }

        It 'Should have Strategy 4: rundll32 driver re-registration' {
            $source = (Get-Command Test-FFUWimMount).ScriptBlock.ToString()
            $source | Should -Match 'rundll32\.exe wimmount\.dll'
        }

        It 'Should have Strategy 5: Filter Manager restart as last resort' {
            $source = (Get-Command Test-FFUWimMount).ScriptBlock.ToString()
            $source | Should -Match 'Restart-Service'
            $source | Should -Match 'FltMgr'
        }

        It 'Should track repair actions in Details hashtable' {
            $source = (Get-Command Test-FFUWimMount).ScriptBlock.ToString()
            $source | Should -Match 'RemediationActions\.Add'
        }

        It 'Should have "All repair strategies exhausted" message' {
            $source = (Get-Command Test-FFUWimMount).ScriptBlock.ToString()
            $source | Should -Match 'All repair strategies exhausted'
        }
    }

    Context 'Test-FFUWimMount result object' {

        It 'Should return valid result object' {
            $result = Test-FFUWimMount
            $result.CheckName | Should -Be 'WimMount'
            $result.Status | Should -BeIn @('Passed', 'Failed')
        }

        It 'Should include repair attempt tracking in details' {
            $result = Test-FFUWimMount -AttemptRemediation
            $result.Details.Keys | Should -Contain 'RemediationAttempted'
            $result.Details.Keys | Should -Contain 'RemediationActions'
        }

        It 'Should include filter loaded status' {
            $result = Test-FFUWimMount
            $result.Details.Keys | Should -Contain 'WimMountFilterLoaded'
        }

        It 'Should include remediation success status when remediation attempted' {
            $result = Test-FFUWimMount -AttemptRemediation
            $result.Details.Keys | Should -Contain 'RemediationSuccess'
        }
    }

    Context 'Retry helper exponential backoff behavior' {

        It 'Should have default MaxRetries of 3' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match '\$MaxRetries\s*=\s*3'
        }

        It 'Should have default BaseDelaySeconds of 2' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match '\$BaseDelaySeconds\s*=\s*2'
        }

        It 'Should use jitter to prevent thundering herd' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match 'jitter'
            $source | Should -Match 'Get-Random'
        }

        It 'Should log retry attempts with attempt number' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Invoke-WimMountRepairWithRetry}.ToString() })
            $source | Should -Match 'attempt \$attempt'
        }
    }
}

Describe 'REL-PRE-02: Remediation Steps Quality' -Tag 'Unit', 'FFU.Preflight', 'Reliability', 'REL-PRE-02' {

    Context 'New-FFURemediationBlock helper function' {

        It 'Should exist as internal helper' {
            $module = Get-Module FFU.Preflight
            $helper = $module.Invoke({ Get-Command New-FFURemediationBlock -ErrorAction SilentlyContinue })
            $helper | Should -Not -BeNullOrEmpty
        }

        It 'Should produce ISSUE section' {
            $module = Get-Module FFU.Preflight
            $output = $module.Invoke({ New-FFURemediationBlock -Issue "Test issue" })
            $output | Should -Match '=== ISSUE ==='
            $output | Should -Match 'Test issue'
        }

        It 'Should produce IMPACT section' {
            $module = Get-Module FFU.Preflight
            $output = $module.Invoke({ New-FFURemediationBlock -Issue "Test" -Impact "Build will fail" })
            $output | Should -Match '=== IMPACT ==='
            $output | Should -Match 'Build will fail'
        }

        It 'Should produce FIX section with PowerShell commands' {
            $module = Get-Module FFU.Preflight
            $output = $module.Invoke({ New-FFURemediationBlock -Issue "Test" -PowerShellCommands @('winget install X') })
            $output | Should -Match '=== FIX ==='
            $output | Should -Match 'winget install X'
            $output | Should -Match 'Run these PowerShell commands'
        }

        It 'Should produce FIX section with manual steps' {
            $module = Get-Module FFU.Preflight
            $output = $module.Invoke({ New-FFURemediationBlock -Issue "Test" -ManualSteps @('Step one', 'Step two') })
            $output | Should -Match '=== FIX ==='
            $output | Should -Match 'Manual steps:'
            $output | Should -Match '1\. Step one'
            $output | Should -Match '2\. Step two'
        }

        It 'Should produce VERIFY section' {
            $module = Get-Module FFU.Preflight
            $output = $module.Invoke({ New-FFURemediationBlock -Issue "Test" -VerifyCommand 'Get-Service' })
            $output | Should -Match '=== VERIFY ==='
            $output | Should -Match 'Get-Service'
        }

        It 'Should use default Impact when not provided' {
            $module = Get-Module FFU.Preflight
            $output = $module.Invoke({ New-FFURemediationBlock -Issue "Test" })
            $output | Should -Match 'Build cannot proceed'
        }
    }

    Context 'Tier 1 checks use standardized remediation' {

        It 'Test-FFUAdministrator should use New-FFURemediationBlock' {
            $source = (Get-Command Test-FFUAdministrator).ScriptBlock.ToString()
            $source | Should -Match 'New-FFURemediationBlock'
        }

        It 'Test-FFUAdministrator remediation includes Start-Process command' {
            $source = (Get-Command Test-FFUAdministrator).ScriptBlock.ToString()
            $source | Should -Match 'Start-Process.*pwsh.*-Verb.*RunAs'
        }

        It 'Test-FFUPowerShellVersion should use New-FFURemediationBlock' {
            $source = (Get-Command Test-FFUPowerShellVersion).ScriptBlock.ToString()
            $source | Should -Match 'New-FFURemediationBlock'
        }

        It 'Test-FFUPowerShellVersion remediation includes winget command' {
            $source = (Get-Command Test-FFUPowerShellVersion).ScriptBlock.ToString()
            $source | Should -Match 'winget install Microsoft\.PowerShell'
        }

        It 'Test-FFUHyperV should use New-FFURemediationBlock' {
            $source = (Get-Command Test-FFUHyperV).ScriptBlock.ToString()
            $source | Should -Match 'New-FFURemediationBlock'
        }

        It 'Test-FFUHyperV client remediation includes Enable-WindowsOptionalFeature' {
            $source = (Get-Command Test-FFUHyperV).ScriptBlock.ToString()
            $source | Should -Match 'Enable-WindowsOptionalFeature.*Microsoft-Hyper-V-All'
        }

        It 'Test-FFUHyperV server remediation includes Install-WindowsFeature' {
            $source = (Get-Command Test-FFUHyperV).ScriptBlock.ToString()
            $source | Should -Match 'Install-WindowsFeature.*Hyper-V'
        }
    }

    Context 'Tier 2 checks use standardized remediation' {

        It 'Test-FFUADK should use New-FFURemediationBlock' {
            $source = (Get-Command Test-FFUADK).ScriptBlock.ToString()
            $source | Should -Match 'New-FFURemediationBlock'
        }

        It 'Test-FFUADK remediation includes ADK download command' {
            $source = (Get-Command Test-FFUADK).ScriptBlock.ToString()
            $source | Should -Match 'go\.microsoft\.com.*adk|aka\.ms.*adk'
        }

        It 'Test-FFUDiskSpace catch block uses New-FFURemediationBlock' {
            $source = (Get-Command Test-FFUDiskSpace).ScriptBlock.ToString()
            $source | Should -Match 'New-FFURemediationBlock'
        }
    }

    Context 'Remediation blocks include required sections' {

        It 'Administrator remediation includes VERIFY command' {
            $source = (Get-Command Test-FFUAdministrator).ScriptBlock.ToString()
            $source | Should -Match '-VerifyCommand'
            $source | Should -Match 'WindowsPrincipal|IsInRole'
        }

        It 'PowerShell version remediation includes VERIFY command' {
            $source = (Get-Command Test-FFUPowerShellVersion).ScriptBlock.ToString()
            $source | Should -Match '-VerifyCommand'
            $source | Should -Match 'PSVersionTable'
        }

        It 'Hyper-V remediation includes VERIFY command' {
            $source = (Get-Command Test-FFUHyperV).ScriptBlock.ToString()
            $source | Should -Match '-VerifyCommand'
            $source | Should -Match 'Get-WindowsOptionalFeature|Get-WindowsFeature'
        }

        It 'ADK remediation includes VERIFY command' {
            $source = (Get-Command Test-FFUADK).ScriptBlock.ToString()
            $source | Should -Match '-VerifyCommand'
            $source | Should -Match 'Test-Path.*DandISetEnv'
        }
    }
}
