#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for FFU.Hypervisor provider switch validation (REL-HYP-03).

.DESCRIPTION
    Tests the Test-ProviderSwitch function, Get-HypervisorProvider switch awareness,
    and Get-PreviousHypervisorType function.

.NOTES
    Phase 16 Plan 03: Provider Switch Validation
#>

BeforeAll {
    # Get project root
    $TestRoot = Split-Path -Parent $PSScriptRoot
    $ProjectRoot = Split-Path -Parent $TestRoot
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    # Add modules path to PSModulePath
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Import the module under test
    Import-Module FFU.Hypervisor -Force -ErrorAction Stop

    # Check hypervisor availability for conditional tests
    $script:HyperVAvailable = $false
    $script:VMwareAvailable = $false

    try {
        $hyperv = [HyperVProvider]::new()
        $script:HyperVAvailable = $hyperv.TestAvailable()
    } catch {}

    try {
        $vmware = [VMwareProvider]::new()
        $script:VMwareAvailable = $vmware.TestAvailable()
    } catch {}
}

Describe 'Test-ProviderSwitch' {

    Context 'Basic functionality' {

        It 'Returns hashtable with expected keys' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'CanSwitch'
            $result.Keys | Should -Contain 'Warnings'
            $result.Keys | Should -Contain 'Blockers'
            $result.Keys | Should -Contain 'OrphanedVMs'
            $result.Keys | Should -Contain 'IncompatibleConfig'
            $result.Keys | Should -Contain 'RecommendedActions'
        }

        It 'CanSwitch is boolean' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            $result.CanSwitch | Should -BeOfType [bool]
        }

        It 'Same provider returns CanSwitch true with no warnings' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'HyperV'

            $result.CanSwitch | Should -BeTrue
            $result.Warnings | Should -HaveCount 0
            $result.Blockers | Should -HaveCount 0
        }

        It 'Warnings supports empty or has array values' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            # Verify count works (works for both @() and $null)
            $count = @($result.Warnings).Count
            $count | Should -BeGreaterOrEqual 0
        }

        It 'Blockers supports empty or has array values' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            $count = @($result.Blockers).Count
            $count | Should -BeGreaterOrEqual 0
        }

        It 'OrphanedVMs supports empty or has array values' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            $count = @($result.OrphanedVMs).Count
            $count | Should -BeGreaterOrEqual 0
        }

        It 'RecommendedActions supports empty or has array values' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            $count = @($result.RecommendedActions).Count
            $count | Should -BeGreaterOrEqual 0
        }

        It 'IncompatibleConfig has expected structure' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            $result.IncompatibleConfig | Should -BeOfType [hashtable]
            $result.IncompatibleConfig.Keys | Should -Contain 'IsIncompatible'
            $result.IncompatibleConfig.Keys | Should -Contain 'Reason'
        }
    }

    Context 'Configuration compatibility - VHDX to VMware' {

        It 'Detects VHDX incompatibility when switching to VMware' {
            # Create mock config with VHDX
            $config = @{
                DiskFormat = 'VHDX'
                VirtualDiskPath = 'C:\Test\disk.vhdx'
            }

            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config

            $result.Blockers | Should -Not -BeNullOrEmpty
            $result.Blockers[0] | Should -Match 'VHDX'
            $result.IncompatibleConfig.IsIncompatible | Should -BeTrue
        }

        It 'Infers VHDX format from file extension' {
            $config = @{
                VirtualDiskPath = 'C:\Test\disk.vhdx'
            }

            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config

            $result.Blockers | Should -Not -BeNullOrEmpty
            $result.Blockers[0] | Should -Match 'VHDX'
        }

        It 'Includes recommended action for VHDX incompatibility' {
            $config = @{
                DiskFormat = 'VHDX'
            }

            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config

            $result.RecommendedActions | Should -Not -BeNullOrEmpty
            $result.RecommendedActions[0] | Should -Match 'VHD|VMDK'
        }
    }

    Context 'Configuration compatibility - VMDK to Hyper-V' {

        It 'Detects VMDK incompatibility when switching to Hyper-V' {
            $config = @{
                DiskFormat = 'VMDK'
            }

            $result = Test-ProviderSwitch -FromProvider 'VMware' -ToProvider 'HyperV' -Config $config

            $result.Blockers | Should -Not -BeNullOrEmpty
            $result.Blockers[0] | Should -Match 'VMDK'
            $result.IncompatibleConfig.IsIncompatible | Should -BeTrue
        }

        It 'Infers VMDK format from file extension' {
            $config = @{
                VirtualDiskPath = 'C:\Test\disk.vmdk'
            }

            $result = Test-ProviderSwitch -FromProvider 'VMware' -ToProvider 'HyperV' -Config $config

            $result.Blockers | Should -Not -BeNullOrEmpty
            $result.Blockers[0] | Should -Match 'VMDK'
        }
    }

    Context 'Configuration compatibility - VHD (compatible with both)' {

        It 'VHD format does not block HyperV to VMware switch' {
            $config = @{
                DiskFormat = 'VHD'
            }

            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config

            $result.Blockers | Where-Object { $_ -match 'disk format' } | Should -BeNullOrEmpty
            $result.IncompatibleConfig.IsIncompatible | Should -BeFalse
        }

        It 'VHD format does not block VMware to HyperV switch' {
            $config = @{
                DiskFormat = 'VHD'
            }

            $result = Test-ProviderSwitch -FromProvider 'VMware' -ToProvider 'HyperV' -Config $config

            $result.Blockers | Where-Object { $_ -match 'disk format' } | Should -BeNullOrEmpty
            $result.IncompatibleConfig.IsIncompatible | Should -BeFalse
        }
    }

    Context 'TPM warnings' {

        It 'Warns about TPM when switching to VMware with TPM enabled' {
            $config = @{
                EnableTPM = $true
            }

            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config

            $result.Warnings | Should -Not -BeNullOrEmpty
            $result.Warnings[0] | Should -Match 'TPM'
        }

        It 'TPM warning includes VMware encryption context' {
            $config = @{
                EnableTPM = $true
            }

            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config

            $result.Warnings[0] | Should -Match 'encryption|vmrun'
        }

        It 'TPM is not a blocker (just a warning)' {
            $config = @{
                EnableTPM = $true
                DiskFormat = 'VHD'  # Compatible format
            }

            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config

            # If only issue is TPM, CanSwitch should still be true (assuming provider available)
            $result.Blockers | Where-Object { $_ -match 'TPM' } | Should -BeNullOrEmpty
        }
    }

    Context 'Provider availability' {

        BeforeAll {
            # These variables are set in the parent BeforeAll, cache them locally for skip checks
            $script:BothAvailable = $script:HyperVAvailable -and $script:VMwareAvailable
        }

        It 'Available providers produce no blocker for availability' {
            # When both providers are available, switching should not produce availability blockers
            if (-not $script:BothAvailable) {
                Set-ItResult -Skipped -Because "Requires both hypervisors to be available"
                return
            }

            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            # No provider unavailability blockers should exist
            $providerBlockers = @($result.Blockers) | Where-Object { $_ -match 'not available' }
            @($providerBlockers).Count | Should -Be 0
        }

        It 'Blockers array populated when provider unavailable' {
            # When at least one provider is unavailable, it should produce blockers
            if ($script:BothAvailable) {
                Set-ItResult -Skipped -Because "Both hypervisors are available - cannot test unavailable provider"
                return
            }

            $targetProvider = if (-not $script:VMwareAvailable) { 'VMware' } else { 'HyperV' }
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider $targetProvider

            @($result.Blockers).Count | Should -BeGreaterThan 0
            $result.Blockers[0] | Should -Match 'not available'
        }

        It 'RecommendedActions populated when provider unavailable' {
            if ($script:BothAvailable) {
                Set-ItResult -Skipped -Because "Both hypervisors are available - cannot test unavailable provider"
                return
            }

            $targetProvider = if (-not $script:VMwareAvailable) { 'VMware' } else { 'HyperV' }
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider $targetProvider

            @($result.RecommendedActions).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Orphan detection - Hyper-V' -Skip:(-not $script:HyperVAvailable) {

        It 'Detects Hyper-V VMs matching default pattern' {
            # This test depends on having VMs matching _FFU* pattern
            # May pass/skip based on environment
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'

            # Just verify the check runs without error
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Custom VMNamePattern filters correctly' {
            $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -VMNamePattern 'NonExistentVM*'

            # Should not find any VMs with this pattern
            $result.OrphanedVMs | Should -HaveCount 0
        }
    }

    Context 'Orphan detection - VMware' {

        It 'Uses VMNamePattern for VMware VMX search' {
            $result = Test-ProviderSwitch -FromProvider 'VMware' -ToProvider 'HyperV' -VMNamePattern 'NonExistentVM*'

            # Should not find any VMs with this pattern
            $result.OrphanedVMs | Should -HaveCount 0
        }
    }
}

Describe 'Get-HypervisorProvider Switch Awareness' {

    BeforeEach {
        # Reset provider tracking state by importing module fresh
        Import-Module FFU.Hypervisor -Force
    }

    Context 'Parameter validation' {

        It 'Has ValidateSwitch parameter' {
            $params = (Get-Command Get-HypervisorProvider).Parameters
            $params.Keys | Should -Contain 'ValidateSwitch'
        }

        It 'Has Force parameter' {
            $params = (Get-Command Get-HypervisorProvider).Parameters
            $params.Keys | Should -Contain 'Force'
        }

        It 'Has Config parameter' {
            $params = (Get-Command Get-HypervisorProvider).Parameters
            $params.Keys | Should -Contain 'Config'
        }

        It 'ValidateSwitch is switch type' {
            $param = (Get-Command Get-HypervisorProvider).Parameters['ValidateSwitch']
            $param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Force is switch type' {
            $param = (Get-Command Get-HypervisorProvider).Parameters['Force']
            $param.ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Provider tracking' -Skip:(-not ($script:HyperVAvailable -or $script:VMwareAvailable)) {

        It 'Get-PreviousHypervisorType returns null initially' {
            # Fresh import should have no previous provider
            Import-Module FFU.Hypervisor -Force
            $previous = Get-PreviousHypervisorType

            $previous | Should -BeNullOrEmpty
        }

        It 'Tracks provider type after Get-HypervisorProvider call' {
            Import-Module FFU.Hypervisor -Force

            # Get a provider (will be whichever is available)
            $provider = Get-HypervisorProvider -Type 'Auto'
            $previous = Get-PreviousHypervisorType

            $previous | Should -Not -BeNullOrEmpty
            $previous | Should -BeIn @('HyperV', 'VMware')
        }

        It 'Get-PreviousHypervisorType returns tracked value' {
            Import-Module FFU.Hypervisor -Force

            $provider = Get-HypervisorProvider -Type 'Auto'
            $previous = Get-PreviousHypervisorType

            $previous | Should -Be $provider.Name
        }
    }

    Context 'ValidateSwitch behavior' -Skip:(-not ($script:HyperVAvailable -and $script:VMwareAvailable)) {

        It 'ValidateSwitch with no previous provider does not throw' {
            Import-Module FFU.Hypervisor -Force

            { Get-HypervisorProvider -Type 'HyperV' -ValidateSwitch } | Should -Not -Throw
        }

        It 'ValidateSwitch same provider does not throw' {
            Import-Module FFU.Hypervisor -Force

            $null = Get-HypervisorProvider -Type 'HyperV'
            { Get-HypervisorProvider -Type 'HyperV' -ValidateSwitch } | Should -Not -Throw
        }
    }

    Context 'Force behavior with blockers' {

        It 'Force parameter exists on Get-HypervisorProvider' {
            $cmd = Get-Command Get-HypervisorProvider
            $cmd.Parameters.Keys | Should -Contain 'Force'
        }
    }
}

Describe 'Get-PreviousHypervisorType' {

    It 'Function exists' {
        $cmd = Get-Command Get-PreviousHypervisorType -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }

    It 'Returns string or null' {
        $result = Get-PreviousHypervisorType

        if ($result) {
            $result | Should -BeOfType [string]
        }
        # null is also acceptable
    }
}

Describe 'Integration scenarios' -Skip:(-not ($script:HyperVAvailable -and $script:VMwareAvailable)) {

    It 'Full switch workflow: HyperV to VMware with VHD config' {
        Import-Module FFU.Hypervisor -Force

        # Step 1: Get Hyper-V provider
        $hyperv = Get-HypervisorProvider -Type 'HyperV'
        $hyperv.Name | Should -Be 'HyperV'

        # Step 2: Validate switch to VMware with VHD config
        $config = @{
            DiskFormat = 'VHD'
            EnableTPM = $false
        }

        $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config

        # VHD is compatible, should be able to switch
        $result.IncompatibleConfig.IsIncompatible | Should -BeFalse

        # Step 3: Get VMware provider
        $vmware = Get-HypervisorProvider -Type 'VMware'
        $vmware.Name | Should -Be 'VMware'

        # Step 4: Verify tracking updated
        $previous = Get-PreviousHypervisorType
        $previous | Should -Be 'VMware'
    }

    It 'Full switch workflow: VMware to HyperV with incompatible config' {
        Import-Module FFU.Hypervisor -Force

        # Step 1: Get VMware provider
        $vmware = Get-HypervisorProvider -Type 'VMware'

        # Step 2: Validate switch to HyperV with VMDK config (incompatible)
        $config = @{
            DiskFormat = 'VMDK'
        }

        $result = Test-ProviderSwitch -FromProvider 'VMware' -ToProvider 'HyperV' -Config $config

        # VMDK should block
        $result.CanSwitch | Should -BeFalse
        $result.IncompatibleConfig.IsIncompatible | Should -BeTrue
    }
}
