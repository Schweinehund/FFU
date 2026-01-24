#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Reliability tests for FFU.Preflight module.

.DESCRIPTION
    Tests REL-PRE-01 through REL-PRE-04 requirements for FFU.Preflight module.
    Part of v1.9.0 Reliability Hardening milestone, Phase 22.

.NOTES
    REL-PRE-01: Enhanced prerequisite detection (VM resources, scratch space, DISM state)
    - Test-FFUVMResources validates VM creation prerequisites (memory, CPU, virtualization)
    - Test-FFUScratchSpace validates path usability (NTFS, not network, writable)
    - Test-FFUDISMState validates DISM is healthy (no orphaned mounts)

    REL-PRE-02: Standardized remediation format
    - New-FFURemediationBlock provides ISSUE/IMPACT/FIX/VERIFY sections

    REL-PRE-03: WIMMount repair includes retry logic for transient service start failures
    - Invoke-WimMountRepairWithRetry wraps repair steps with exponential backoff
    - Multiple repair strategies attempted before declaring failure

    REL-PRE-04: Tiered check severity classification
    - New-FFUCheckResult includes Severity parameter (Critical/Warning/Info)
    - Invoke-FFUPreflight tracks severity counts and shows grouped summary
    - Only Critical failures block the build
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

Describe 'REL-PRE-01: Prerequisite Detection Completeness' -Tag 'Unit', 'FFU.Preflight', 'Reliability', 'REL-PRE-01' {

    Context 'Test-FFUVMResources function' {

        It 'Should exist as exported function' {
            Get-Command -Name Test-FFUVMResources -Module FFU.Preflight | Should -Not -BeNullOrEmpty
        }

        It 'Should return valid result object' {
            $result = Test-FFUVMResources
            $result.CheckName | Should -Be 'VMResources'
            $result.Status | Should -BeIn @('Passed', 'Warning', 'Failed')
        }

        It 'Should include memory details in result' {
            $result = Test-FFUVMResources
            $result.Details.AvailableMemoryMB | Should -BeGreaterThan 0
        }

        It 'Should include CPU details in result' {
            $result = Test-FFUVMResources
            $result.Details.CPUCores | Should -BeGreaterThan 0
        }

        It 'Should have RequiredMemoryMB parameter' {
            $cmd = Get-Command Test-FFUVMResources
            $cmd.Parameters.Keys | Should -Contain 'RequiredMemoryMB'
        }

        It 'Should have HypervisorType parameter' {
            $cmd = Get-Command Test-FFUVMResources
            $cmd.Parameters.Keys | Should -Contain 'HypervisorType'
        }

        It 'Should fail when required memory exceeds available' {
            # Request impossibly high memory to trigger failure
            $result = Test-FFUVMResources -RequiredMemoryMB 999999999
            $result.Status | Should -Be 'Failed'
            $result.Remediation | Should -Not -BeNullOrEmpty
        }

        It 'Should include virtualization status in details' {
            $result = Test-FFUVMResources
            $result.Details.Keys | Should -Contain 'VirtualizationEnabled'
        }
    }

    Context 'Test-FFUScratchSpace function' {

        It 'Should exist as exported function' {
            Get-Command -Name Test-FFUScratchSpace -Module FFU.Preflight | Should -Not -BeNullOrEmpty
        }

        It 'Should return valid result object' {
            $result = Test-FFUScratchSpace -FFUDevelopmentPath $env:TEMP
            $result.CheckName | Should -Be 'ScratchSpace'
            $result.Status | Should -BeIn @('Passed', 'Warning', 'Failed')
        }

        It 'Should have FFUDevelopmentPath parameter marked mandatory' {
            $cmd = Get-Command Test-FFUScratchSpace
            $param = $cmd.Parameters['FFUDevelopmentPath']
            $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ParameterAttribute' -and $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It 'Should have RequiredScratchGB parameter' {
            $cmd = Get-Command Test-FFUScratchSpace
            $cmd.Parameters.Keys | Should -Contain 'RequiredScratchGB'
        }

        It 'Should detect filesystem type' {
            $result = Test-FFUScratchSpace -FFUDevelopmentPath 'C:\Temp'
            $result.Details.FileSystem | Should -Not -BeNullOrEmpty
        }

        It 'Should detect network path status' {
            $result = Test-FFUScratchSpace -FFUDevelopmentPath 'C:\Temp'
            $result.Details.IsNetworkPath | Should -Be $false
        }

        It 'Should warn for FAT32 filesystem' {
            $source = (Get-Command Test-FFUScratchSpace).ScriptBlock.ToString()
            $source | Should -Match 'FAT32|4GB file limit'
        }

        It 'Should warn for network paths' {
            $source = (Get-Command Test-FFUScratchSpace).ScriptBlock.ToString()
            $source | Should -Match 'network|UNC|performance'
        }
    }

    Context 'Test-FFUDISMState function' {

        It 'Should exist as exported function' {
            Get-Command -Name Test-FFUDISMState -Module FFU.Preflight | Should -Not -BeNullOrEmpty
        }

        It 'Should return valid result object' {
            $result = Test-FFUDISMState
            $result.CheckName | Should -Be 'DISMState'
            $result.Status | Should -BeIn @('Passed', 'Warning', 'Failed')
        }

        It 'Should have AttemptRemediation switch parameter' {
            $cmd = Get-Command Test-FFUDISMState
            $cmd.Parameters.Keys | Should -Contain 'AttemptRemediation'
            $cmd.Parameters['AttemptRemediation'].SwitchParameter | Should -Be $true
        }

        It 'Should check for orphaned mount points' {
            $result = Test-FFUDISMState
            $result.Details.Keys | Should -Contain 'OrphanedMounts'
        }

        It 'Should use dism /Get-MountedImageInfo for detection' {
            $source = (Get-Command Test-FFUDISMState).ScriptBlock.ToString()
            $source | Should -Match 'Get-MountedImageInfo|dism.*Mount'
        }

        It 'Should have cleanup remediation for orphaned mounts' {
            $source = (Get-Command Test-FFUDISMState).ScriptBlock.ToString()
            $source | Should -Match 'Cleanup-Mountpoints|Cleanup-Wim'
        }

        It 'Should track remediation attempts in details' {
            $result = Test-FFUDISMState -AttemptRemediation
            $result.Details.Keys | Should -Contain 'RemediationAttempted'
        }
    }

    Context 'Invoke-FFUPreflight integration' {

        It 'Should include VMResources in Tier 1 results when CreateVM enabled' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            $source | Should -Match 'Test-FFUVMResources'
            $source | Should -Match "Tier1Results\['VMResources'\]|Tier1Results\[.VMResources.\]"
        }

        It 'Should include ScratchSpace in Tier 2 results' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            $source | Should -Match 'Test-FFUScratchSpace'
            $source | Should -Match "Tier2Results\['ScratchSpace'\]|Tier2Results\[.ScratchSpace.\]"
        }

        It 'Should include DISMState in Tier 2 results when ADK needed' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            $source | Should -Match 'Test-FFUDISMState'
            $source | Should -Match "Tier2Results\['DISMState'\]|Tier2Results\[.DISMState.\]"
        }

        It 'Should run VMResources check conditionally based on CreateVM feature' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            # Check that CreateVM conditional and VMResources check are both present
            $source | Should -Match '\$Features\.CreateVM'
            $source | Should -Match 'Test-FFUVMResources'
        }

        It 'Should run DISMState check conditionally based on NeedsADK' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            # Check that ADK conditional and DISMState check are both present
            $source | Should -Match 'requirements\.NeedsADK|NeedsADK'
            $source | Should -Match 'Test-FFUDISMState'
        }
    }

    Context 'Fail-fast ordering' {

        It 'Should check Tier 1 before Tier 2' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            # Tier 1 checks should appear before Tier 2 checks
            $tier1Pos = $source.IndexOf('Tier1Results')
            $tier2Pos = $source.IndexOf('Tier2Results')
            $tier1Pos | Should -BeLessThan $tier2Pos
        }

        It 'Should support early exit on critical failures' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            # Should have logic to check IsValid or early return after critical checks
            $source | Should -Match 'IsValid|early.*exit|return.*false|FailFast'
        }
    }
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

Describe 'REL-PRE-04: Tiered Check Severity Classification' -Tag 'Unit', 'FFU.Preflight', 'Reliability', 'REL-PRE-04' {

    Context 'New-FFUCheckResult Severity parameter' {

        It 'Should accept Critical severity' {
            $result = New-FFUCheckResult -CheckName 'Test' -Status 'Failed' -Message 'Test' -Severity 'Critical'
            $result.Severity | Should -Be 'Critical'
        }

        It 'Should accept Warning severity' {
            $result = New-FFUCheckResult -CheckName 'Test' -Status 'Failed' -Message 'Test' -Severity 'Warning'
            $result.Severity | Should -Be 'Warning'
        }

        It 'Should accept Info severity' {
            $result = New-FFUCheckResult -CheckName 'Test' -Status 'Warning' -Message 'Test' -Severity 'Info'
            $result.Severity | Should -Be 'Info'
        }

        It 'Should default to Warning severity' {
            $result = New-FFUCheckResult -CheckName 'Test' -Status 'Failed' -Message 'Test'
            $result.Severity | Should -Be 'Warning'
        }

        It 'Should include Severity in output object' {
            $result = New-FFUCheckResult -CheckName 'Test' -Status 'Passed' -Message 'Test'
            $result.PSObject.Properties.Name | Should -Contain 'Severity'
        }
    }

    Context 'Tier 1 checks use Critical severity' {

        It 'Test-FFUAdministrator should use Critical severity for failures' {
            $source = (Get-Command Test-FFUAdministrator).ScriptBlock.ToString()
            $source | Should -Match "Severity.*'Critical'"
        }

        It 'Test-FFUPowerShellVersion should use Critical severity for failures' {
            $source = (Get-Command Test-FFUPowerShellVersion).ScriptBlock.ToString()
            $source | Should -Match "Severity.*'Critical'"
        }

        It 'Test-FFUHyperV should use Critical severity for failures' {
            $source = (Get-Command Test-FFUHyperV).ScriptBlock.ToString()
            $source | Should -Match "Severity.*'Critical'"
        }
    }

    Context 'Tier 2 checks use appropriate severity' {

        It 'Test-FFUADK should use Critical severity' {
            $source = (Get-Command Test-FFUADK).ScriptBlock.ToString()
            $source | Should -Match "Severity.*'Critical'"
        }

        It 'Test-FFUVmxToolkit should use Info severity (optional)' {
            $source = (Get-Command Test-FFUVmxToolkit).ScriptBlock.ToString()
            $source | Should -Match "Severity.*'Info'"
        }

        It 'Test-FFUDiskSpace should use Critical severity' {
            $source = (Get-Command Test-FFUDiskSpace).ScriptBlock.ToString()
            $source | Should -Match "Severity.*'Critical'"
        }

        It 'Test-FFUWimMount should use Critical severity' {
            $source = (Get-Command Test-FFUWimMount).ScriptBlock.ToString()
            $source | Should -Match "Severity.*'Critical'"
        }
    }

    Context 'Invoke-FFUPreflight severity tracking' {

        It 'Should include CriticalCount in result' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            $source | Should -Match 'CriticalCount'
        }

        It 'Should include WarningCount in result' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            $source | Should -Match 'WarningCount'
        }

        It 'Should include InfoCount in result' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            $source | Should -Match 'InfoCount'
        }

        It 'Should include InfoMessages list in result' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            $source | Should -Match 'InfoMessages'
        }

        It 'Add-CheckToResult helper should exist' {
            $module = Get-Module FFU.Preflight
            $helper = $module.Invoke({ ${function:Add-CheckToResult} })
            $helper | Should -Not -BeNullOrEmpty
        }

        It 'Add-CheckToResult should track severity counts' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Add-CheckToResult}.ToString() })
            $source | Should -Match 'CriticalCount\+\+'
            $source | Should -Match 'WarningCount\+\+'
            $source | Should -Match 'InfoCount\+\+'
        }

        It 'Should only block on Critical failures' {
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Add-CheckToResult}.ToString() })
            $source | Should -Match "Severity.*-eq.*'Critical'"
            $source | Should -Match 'IsValid.*=.*\$false'
        }
    }

    Context 'Severity display in summary' {

        It 'Should format errors with [CRITICAL] prefix' {
            # [CRITICAL] prefix is in Add-CheckToResult helper which tracks failed checks
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Add-CheckToResult}.ToString() })
            $source | Should -Match '\[CRITICAL\]'
        }

        It 'Should format warnings with [WARNING] prefix' {
            # [WARNING] prefix is in Add-CheckToResult helper which tracks failed checks
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Add-CheckToResult}.ToString() })
            $source | Should -Match '\[WARNING\]'
        }

        It 'Should format info with [INFO] prefix' {
            # [INFO] prefix is in Add-CheckToResult helper which tracks failed checks
            $module = Get-Module FFU.Preflight
            $source = $module.Invoke({ ${function:Add-CheckToResult}.ToString() })
            $source | Should -Match '\[INFO\]'
        }

        It 'Summary should show severity breakdown' {
            $source = (Get-Command Invoke-FFUPreflight).ScriptBlock.ToString()
            $source | Should -Match 'CRITICAL ISSUES:'
            $source | Should -Match 'WARNINGS:'
            $source | Should -Match 'INFO:'
        }
    }
}
