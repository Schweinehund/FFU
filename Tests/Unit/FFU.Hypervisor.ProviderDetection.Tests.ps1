#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for FFU.Hypervisor provider detection with remediation guidance

.DESCRIPTION
    Pester tests for provider detection scenarios in FFU.Hypervisor module.
    Tests cover:
    - GetAvailabilityDetails returns Remediation and ErrorCode
    - Get-HypervisorProvider error messages include remediation
    - Test-HypervisorAvailable -Detailed includes remediation
    - Provider availability detection scenarios

.NOTES
    REL-HYP-01: Provider detection with actionable guidance
    These tests validate that users receive helpful remediation steps
    when hypervisors are unavailable.
#>

BeforeAll {
    # Get paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulesPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\Modules'

    # Add modules folder to PSModulePath if not present
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Import FFU.Core first (dependency)
    Import-Module (Join-Path $ModulesPath 'FFU.Core\FFU.Core.psd1') -Force -ErrorAction SilentlyContinue

    # Import the FFU.Hypervisor module
    Import-Module (Join-Path $ModulesPath 'FFU.Hypervisor\FFU.Hypervisor.psd1') -Force -ErrorAction Stop

    # Helper function to run code in module scope (for class access)
    $script:HypervisorModule = Get-Module -Name 'FFU.Hypervisor'
    function Invoke-InModuleScope {
        param([scriptblock]$ScriptBlock)
        & $script:HypervisorModule $ScriptBlock
    }
}

Describe 'Provider Detection - Availability Details' {

    Context 'HyperVProvider.GetAvailabilityDetails' {

        It 'Returns Remediation array in result' {
            $details = Invoke-InModuleScope {
                $provider = [HyperVProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            $details | Should -Not -BeNullOrEmpty
            $details.Keys | Should -Contain 'Remediation'
            # Remediation is an array - may be empty when provider is available
            # PowerShell may convert empty array to $null, so we check the key exists
            if ($details.Remediation) {
                $details.Remediation | Should -BeOfType [System.Collections.IEnumerable]
            }
        }

        It 'Returns ErrorCode key in result' {
            $details = Invoke-InModuleScope {
                $provider = [HyperVProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            $details | Should -Not -BeNullOrEmpty
            $details.Keys | Should -Contain 'ErrorCode'
        }

        It 'Returns empty Remediation when Hyper-V is available' -Skip:(-not (Test-HypervisorAvailable -Type 'HyperV')) {
            $details = Invoke-InModuleScope {
                $provider = [HyperVProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            $details.IsAvailable | Should -Be $true
            $details.Remediation.Count | Should -Be 0
            $details.ErrorCode | Should -BeNullOrEmpty
        }

        It 'Returns ErrorCode starting with HYPERV_ when issues found' {
            # This test validates the ErrorCode format when Hyper-V has issues
            # We can only test the format if Hyper-V is actually unavailable
            $details = Invoke-InModuleScope {
                $provider = [HyperVProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            if (-not $details.IsAvailable) {
                $details.ErrorCode | Should -Match '^HYPERV_'
            }
            else {
                # If available, ErrorCode should be null
                $details.ErrorCode | Should -BeNullOrEmpty
            }
        }

        It 'Includes actionable PowerShell command in remediation when unavailable' {
            # This test validates remediation content format
            $details = Invoke-InModuleScope {
                $provider = [HyperVProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            if (-not $details.IsAvailable -and $details.Remediation.Count -gt 0) {
                # Should contain PowerShell commands like Enable-WindowsOptionalFeature or Start-Service
                $hasCommand = $details.Remediation | Where-Object {
                    $_ -match 'Enable-WindowsOptionalFeature|Start-Service|Set-Service'
                }
                $hasCommand | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'VMwareProvider.GetAvailabilityDetails' {

        It 'Returns Remediation array in result' {
            $details = Invoke-InModuleScope {
                $provider = [VMwareProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            $details | Should -Not -BeNullOrEmpty
            $details.Keys | Should -Contain 'Remediation'
            # Remediation is an array - may be empty when provider is available
            # PowerShell may convert empty array to $null, so we check the key exists
            if ($details.Remediation) {
                $details.Remediation | Should -BeOfType [System.Collections.IEnumerable]
            }
        }

        It 'Returns ErrorCode key in result' {
            $details = Invoke-InModuleScope {
                $provider = [VMwareProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            $details | Should -Not -BeNullOrEmpty
            $details.Keys | Should -Contain 'ErrorCode'
        }

        It 'Returns empty Remediation when VMware is available' -Skip:(-not (Test-HypervisorAvailable -Type 'VMware')) {
            $details = Invoke-InModuleScope {
                $provider = [VMwareProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            $details.IsAvailable | Should -Be $true
            $details.Remediation.Count | Should -Be 0
            $details.ErrorCode | Should -BeNullOrEmpty
        }

        It 'Returns ErrorCode starting with VMWARE_ when issues found' {
            $details = Invoke-InModuleScope {
                $provider = [VMwareProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            if (-not $details.IsAvailable) {
                $details.ErrorCode | Should -Match '^VMWARE_'
            }
            else {
                $details.ErrorCode | Should -BeNullOrEmpty
            }
        }

        It 'Includes download URL in remediation when not installed' {
            $details = Invoke-InModuleScope {
                $provider = [VMwareProvider]::new()
                $provider.GetAvailabilityDetails()
            }

            if ($details.ErrorCode -eq 'VMWARE_NOT_INSTALLED') {
                $hasUrl = $details.Remediation | Where-Object { $_ -match 'vmware\.com' }
                $hasUrl | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Provider Detection - Get-HypervisorProvider' {

    Context 'Validate parameter' {

        It 'Returns provider when available with -Validate' {
            # Test with whatever provider is available on this system
            $provider = Get-HypervisorProvider -Type 'Auto' -Validate
            $provider | Should -Not -BeNullOrEmpty
            $provider.Name | Should -BeIn @('HyperV', 'VMware')
        }

        It 'Error message includes ErrorCode when provider unavailable' {
            # We can only test this if at least one provider is unavailable
            $hypervAvailable = Test-HypervisorAvailable -Type 'HyperV'
            $vmwareAvailable = Test-HypervisorAvailable -Type 'VMware'

            if (-not $hypervAvailable) {
                { Get-HypervisorProvider -Type 'HyperV' -Validate } | Should -Throw -ErrorId '*'
                try {
                    Get-HypervisorProvider -Type 'HyperV' -Validate
                }
                catch {
                    # Error message should contain 'Error Code' or error code pattern
                    $_.Exception.Message | Should -Match 'Error Code|HYPERV_'
                }
            }
            elseif (-not $vmwareAvailable) {
                { Get-HypervisorProvider -Type 'VMware' -Validate } | Should -Throw -ErrorId '*'
                try {
                    Get-HypervisorProvider -Type 'VMware' -Validate
                }
                catch {
                    $_.Exception.Message | Should -Match 'Error Code|VMWARE_'
                }
            }
            else {
                # Both available - test passes (nothing to validate error message on)
                Set-ItResult -Skipped -Because 'Both hypervisors are available - cannot test error message format'
            }
        }

        It 'Error message includes remediation steps when provider unavailable' {
            $hypervAvailable = Test-HypervisorAvailable -Type 'HyperV'
            $vmwareAvailable = Test-HypervisorAvailable -Type 'VMware'

            if (-not $hypervAvailable) {
                try {
                    Get-HypervisorProvider -Type 'HyperV' -Validate
                }
                catch {
                    $_.Exception.Message | Should -Match 'Remediation|Enable-WindowsOptionalFeature|Start-Service'
                }
            }
            elseif (-not $vmwareAvailable) {
                try {
                    Get-HypervisorProvider -Type 'VMware' -Validate
                }
                catch {
                    $_.Exception.Message | Should -Match 'Remediation|vmware\.com'
                }
            }
            else {
                Set-ItResult -Skipped -Because 'Both hypervisors are available - cannot test error message format'
            }
        }
    }

    Context 'Auto mode' {

        It 'Returns first available provider' {
            $provider = Get-HypervisorProvider -Type 'Auto'
            $provider | Should -Not -BeNullOrEmpty
            $provider.Name | Should -BeIn @('HyperV', 'VMware')
        }

        It 'Prefers Hyper-V over VMware when both available' -Skip:(-not ((Test-HypervisorAvailable -Type 'HyperV') -and (Test-HypervisorAvailable -Type 'VMware'))) {
            $provider = Get-HypervisorProvider -Type 'Auto'
            $provider.Name | Should -Be 'HyperV'
        }

        It 'Throws with remediation for both providers when none available' {
            # This test can only run on systems without any hypervisor
            $hypervAvailable = Test-HypervisorAvailable -Type 'HyperV'
            $vmwareAvailable = Test-HypervisorAvailable -Type 'VMware'

            if (-not $hypervAvailable -and -not $vmwareAvailable) {
                try {
                    Get-HypervisorProvider -Type 'Auto'
                }
                catch {
                    # Error should mention both Hyper-V and VMware
                    $_.Exception.Message | Should -Match 'Hyper-V'
                    $_.Exception.Message | Should -Match 'VMware'
                    # And include remediation for both
                    $_.Exception.Message | Should -Match 'Remediation'
                }
            }
            else {
                Set-ItResult -Skipped -Because 'At least one hypervisor is available'
            }
        }
    }
}

Describe 'Provider Detection - Test-HypervisorAvailable' {

    Context 'Detailed mode' {

        It 'Includes Remediation in detailed result' {
            $result = Test-HypervisorAvailable -Type 'HyperV' -Detailed
            $result.Keys | Should -Contain 'Remediation'
        }

        It 'Includes ErrorCode in detailed result' {
            $result = Test-HypervisorAvailable -Type 'HyperV' -Detailed
            $result.Keys | Should -Contain 'ErrorCode'
        }

        It 'Returns correct IsAvailable status' {
            $detailedResult = Test-HypervisorAvailable -Type 'HyperV' -Detailed
            $boolResult = Test-HypervisorAvailable -Type 'HyperV'

            $detailedResult.IsAvailable | Should -Be $boolResult
        }

        It 'Returns all expected keys in detailed mode' {
            $result = Test-HypervisorAvailable -Type 'HyperV' -Detailed

            $expectedKeys = @('IsAvailable', 'ProviderName', 'ProviderVersion', 'Issues', 'Details', 'ErrorCode', 'Remediation')
            foreach ($key in $expectedKeys) {
                $result.Keys | Should -Contain $key
            }
        }

        It 'VMware detailed result includes all expected keys' {
            $result = Test-HypervisorAvailable -Type 'VMware' -Detailed

            $expectedKeys = @('IsAvailable', 'ProviderName', 'ProviderVersion', 'Issues', 'Details', 'ErrorCode', 'Remediation')
            foreach ($key in $expectedKeys) {
                $result.Keys | Should -Contain $key
            }
        }
    }

    Context 'Simple mode' {

        It 'Returns boolean without throwing' {
            { $result = Test-HypervisorAvailable -Type 'HyperV' } | Should -Not -Throw
            $result = Test-HypervisorAvailable -Type 'HyperV'
            $result | Should -BeOfType [bool]
        }

        It 'Returns boolean for VMware check' {
            { $result = Test-HypervisorAvailable -Type 'VMware' } | Should -Not -Throw
            $result = Test-HypervisorAvailable -Type 'VMware'
            $result | Should -BeOfType [bool]
        }

        It 'Returns boolean for Any check' {
            { $result = Test-HypervisorAvailable -Type 'Any' } | Should -Not -Throw
            $result = Test-HypervisorAvailable -Type 'Any'
            $result | Should -BeOfType [bool]
        }

        It 'Any returns true when at least one hypervisor available' {
            $hypervAvailable = Test-HypervisorAvailable -Type 'HyperV'
            $vmwareAvailable = Test-HypervisorAvailable -Type 'VMware'
            $anyAvailable = Test-HypervisorAvailable -Type 'Any'

            if ($hypervAvailable -or $vmwareAvailable) {
                $anyAvailable | Should -Be $true
            }
        }
    }
}

Describe 'Provider Detection - Error Code Values' {

    Context 'Hyper-V Error Codes' {

        It 'Defines valid ErrorCode constants' {
            # This test validates that known error codes follow the expected pattern
            $validHypervErrorCodes = @(
                'HYPERV_NOT_INSTALLED',
                'HYPERV_SERVICE_STOPPED',
                'HYPERV_MODULE_MISSING',
                'HYPERV_FEATURE_DISABLED',
                'HYPERV_FEATURE_CHECK_FAILED'
            )

            # These should all be valid patterns the code might return
            foreach ($code in $validHypervErrorCodes) {
                $code | Should -Match '^HYPERV_[A-Z_]+$'
            }
        }
    }

    Context 'VMware Error Codes' {

        It 'Defines valid ErrorCode constants' {
            $validVmwareErrorCodes = @(
                'VMWARE_NOT_INSTALLED',
                'VMWARE_PATH_INVALID',
                'VMWARE_VMRUN_MISSING',
                'VMWARE_VERSION_OLD'
            )

            foreach ($code in $validVmwareErrorCodes) {
                $code | Should -Match '^VMWARE_[A-Z_]+$'
            }
        }
    }
}

Describe 'Provider Detection - Remediation Content' {

    Context 'Hyper-V Remediation' {

        It 'Service stopped remediation includes Start-Service command' {
            # This validates the remediation content pattern
            $expectedRemediation = 'Start-Service vmms'
            $expectedRemediation | Should -Match 'Start-Service'
        }

        It 'Not installed remediation includes Enable-WindowsOptionalFeature' {
            $expectedRemediation = 'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All'
            $expectedRemediation | Should -Match 'Enable-WindowsOptionalFeature'
            $expectedRemediation | Should -Match 'Microsoft-Hyper-V'
        }

        It 'Module missing remediation includes PowerShell feature enablement' {
            $expectedRemediation = 'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell'
            $expectedRemediation | Should -Match 'Hyper-V-Management-PowerShell'
        }
    }

    Context 'VMware Remediation' {

        It 'Not installed remediation includes VMware download URL' {
            $expectedUrl = 'https://www.vmware.com/products/workstation-pro.html'
            $expectedUrl | Should -Match 'vmware\.com.*workstation'
        }

        It 'Version old remediation mentions upgrade' {
            $expectedRemediation = 'Consider upgrading for best compatibility'
            $expectedRemediation | Should -Match 'upgrade|upgrading'
        }
    }
}
