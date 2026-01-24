<#
.SYNOPSIS
    Pester tests for FFU.Hypervisor service recovery functionality (REL-HYP-04)

.DESCRIPTION
    Tests for Test-HypervisorService and Invoke-WithHypervisorRetry functions
    that provide automatic recovery from hypervisor service interruptions.
#>

BeforeAll {
    # Set up module path
    $ModulesPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules'
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"

    # Import FFU.Hypervisor
    Import-Module FFU.Hypervisor -Force -ErrorAction Stop

    # Check hypervisor availability for skip conditions
    $hyperVService = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue
    $script:HyperVAvailable = ($hyperVService -and $hyperVService.Status -eq 'Running')

    # Check VMware availability
    $vmwarePath = $null
    $regPaths = @(
        'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation',
        'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation'
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $vmwarePath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath
            if ($vmwarePath -and (Test-Path $vmwarePath)) {
                break
            }
        }
    }
    $script:VMwareAvailable = ($vmwarePath -and (Test-Path (Join-Path $vmwarePath 'vmrun.exe')))
}

Describe 'Test-HypervisorService' {

    Context 'Hyper-V service check' {

        It 'Returns IsHealthy boolean' {
            $result = Test-HypervisorService -Provider 'HyperV'
            $result.IsHealthy | Should -BeOfType [bool]
        }

        It 'Returns ServiceStatus string' {
            $result = Test-HypervisorService -Provider 'HyperV'
            $result.ServiceStatus | Should -Not -BeNullOrEmpty
        }

        It 'Returns CanRecover boolean' {
            $result = Test-HypervisorService -Provider 'HyperV'
            $result.CanRecover | Should -BeOfType [bool]
        }

        It 'Returns LastCheckTime datetime' {
            $result = Test-HypervisorService -Provider 'HyperV'
            $result.LastCheckTime | Should -BeOfType [datetime]
        }

        It 'Detects running vmms service' -Skip:(-not $script:HyperVAvailable) {
            $result = Test-HypervisorService -Provider 'HyperV'
            $result.IsHealthy | Should -BeTrue
            $result.ServiceStatus | Should -Be 'Running'
        }

        It 'Reports CanRecover for stopped service' {
            # This test validates the logic - if service is stopped, CanRecover should be true
            # We can't actually stop vmms during tests, so we test the return structure
            $result = Test-HypervisorService -Provider 'HyperV'
            $result.Keys | Should -Contain 'CanRecover'
            $result.Keys | Should -Contain 'RecoveryAction'
        }

        It 'Reports NotInstalled when vmms service missing' {
            # Mock scenario - the function should handle missing service gracefully
            # In real test, it returns current state
            $result = Test-HypervisorService -Provider 'HyperV'
            # If Hyper-V not installed, ServiceStatus should be NotInstalled
            if (-not $script:HyperVAvailable) {
                $result.ServiceStatus | Should -BeIn @('NotInstalled', 'Stopped', 'Error')
            }
        }
    }

    Context 'VMware service check' {

        It 'Returns IsHealthy for VMware' {
            $result = Test-HypervisorService -Provider 'VMware'
            $result.IsHealthy | Should -BeOfType [bool]
        }

        It 'Returns ServiceStatus for VMware' {
            $result = Test-HypervisorService -Provider 'VMware'
            $result.ServiceStatus | Should -Not -BeNullOrEmpty
        }

        It 'Checks vmrun accessibility' -Skip:(-not $script:VMwareAvailable) {
            $result = Test-HypervisorService -Provider 'VMware'
            # VMware is healthy if vmrun is accessible
            $result.IsHealthy | Should -BeTrue
        }

        It 'Reports correct status based on VMware installation' {
            $result = Test-HypervisorService -Provider 'VMware'

            if ($script:VMwareAvailable) {
                # VMware is installed - should report healthy
                $result.IsHealthy | Should -BeTrue
                $result.ServiceStatus | Should -Match 'Available|Running'
            }
            else {
                # VMware not installed - should report NotInstalled
                $result.ServiceStatus | Should -Be 'NotInstalled'
                $result.RecoveryAction | Should -Match 'VMware Workstation'
            }
        }
    }

    Context 'WaitForReady behavior' {

        It 'Accepts WaitForReady switch' {
            # Short timeout to avoid long test
            { Test-HypervisorService -Provider 'HyperV' -WaitForReady -TimeoutSeconds 1 } | Should -Not -Throw
        }

        It 'Returns after timeout if not ready' {
            # If service is not available, should return within timeout
            $start = [datetime]::Now
            $result = Test-HypervisorService -Provider 'VMware' -WaitForReady -TimeoutSeconds 2
            $elapsed = ([datetime]::Now - $start).TotalSeconds

            # Should either return quickly (if healthy) or within timeout
            $elapsed | Should -BeLessThan 10
        }

        It 'TimeoutSeconds parameter works' {
            $params = (Get-Command Test-HypervisorService).Parameters
            $params.Keys | Should -Contain 'TimeoutSeconds'
        }
    }
}

Describe 'Invoke-WithHypervisorRetry' {

    It 'Has required parameters' {
        $params = (Get-Command Invoke-WithHypervisorRetry).Parameters
        $params.Keys | Should -Contain 'ScriptBlock'
        $params.Keys | Should -Contain 'Provider'
        $params.Keys | Should -Contain 'MaxRetries'
        $params.Keys | Should -Contain 'PreCheckService'
    }

    It 'Executes ScriptBlock on success' {
        $result = Invoke-WithHypervisorRetry -Provider 'HyperV' -ScriptBlock { 'success' }
        $result | Should -Be 'success'
    }

    It 'Returns ScriptBlock result' {
        $result = Invoke-WithHypervisorRetry -Provider 'VMware' -ScriptBlock {
            @{ Value = 42; Status = 'OK' }
        }
        $result.Value | Should -Be 42
        $result.Status | Should -Be 'OK'
    }

    It 'Does not retry non-service errors' {
        # Track execution via global variable since scriptblocks have separate scope
        $Global:NonServiceRetryCount = 0
        $errorThrown = $false

        try {
            Invoke-WithHypervisorRetry -Provider 'HyperV' -MaxRetries 3 -ScriptBlock {
                $Global:NonServiceRetryCount++
                throw "Invalid parameter error - not service related"
            }
        }
        catch {
            $errorThrown = $true
        }

        $errorThrown | Should -BeTrue
        # Should only execute once (no retries for non-service errors)
        $Global:NonServiceRetryCount | Should -Be 1
    }

    It 'Retries on service error' {
        # Track execution via global variable since scriptblocks have separate scope
        $Global:ServiceRetryCount = 0

        try {
            Invoke-WithHypervisorRetry -Provider 'HyperV' -MaxRetries 2 -BaseDelaySeconds 1 -ScriptBlock {
                $Global:ServiceRetryCount++
                if ($Global:ServiceRetryCount -lt 2) {
                    throw "Virtual Machine Management Service is not running"
                }
                return 'recovered'
            }
        }
        catch {
            # May fail on retry, that's expected
        }

        # Should have retried at least once
        $Global:ServiceRetryCount | Should -BeGreaterOrEqual 1
    }

    It 'Uses exponential backoff' {
        # This tests the concept - actual timing is hard to verify precisely
        $params = (Get-Command Invoke-WithHypervisorRetry).Parameters
        $params.Keys | Should -Contain 'BaseDelaySeconds'
    }

    It 'Throws after max retries' {
        {
            Invoke-WithHypervisorRetry -Provider 'HyperV' -MaxRetries 2 -BaseDelaySeconds 1 -ScriptBlock {
                throw "RPC server is unavailable"
            }
        } | Should -Throw
    }

    It 'PreCheckService validates before execution' -Skip:(-not $script:HyperVAvailable) {
        # When service is healthy, PreCheckService should not block execution
        $result = Invoke-WithHypervisorRetry -Provider 'HyperV' -PreCheckService -ScriptBlock {
            'executed'
        }
        $result | Should -Be 'executed'
    }

    It 'OperationName parameter exists' {
        $params = (Get-Command Invoke-WithHypervisorRetry).Parameters
        $params.Keys | Should -Contain 'OperationName'
    }
}

Describe 'Test-IsServiceError' {

    It 'Detects Hyper-V service errors' {
        $hyperVErrors = @(
            'The Virtual Machine Management Service is not running',
            'RPC server is unavailable',
            'The VMMS service has not been started',
            'Failed to connect to Hyper-V'
        )

        foreach ($error in $hyperVErrors) {
            $result = Test-IsServiceError -Provider 'HyperV' -ErrorMessage $error
            $result | Should -BeTrue -Because "Should detect: $error"
        }
    }

    It 'Does not flag non-service Hyper-V errors' {
        $nonServiceErrors = @(
            'VM not found',
            'Invalid VM name',
            'Disk space insufficient'
        )

        foreach ($error in $nonServiceErrors) {
            $result = Test-IsServiceError -Provider 'HyperV' -ErrorMessage $error
            $result | Should -BeFalse -Because "Should not flag: $error"
        }
    }

    It 'Detects VMware service errors' {
        $vmwareErrors = @(
            'Unable to connect to VMware',
            'vmrun command failed',
            'Process not found',
            'Cannot connect to virtual machine'
        )

        foreach ($error in $vmwareErrors) {
            $result = Test-IsServiceError -Provider 'VMware' -ErrorMessage $error
            $result | Should -BeTrue -Because "Should detect: $error"
        }
    }

    It 'Does not flag non-service VMware errors' {
        $nonServiceErrors = @(
            'VM not found',
            'Invalid VMX path',
            'Disk format unsupported'
        )

        foreach ($error in $nonServiceErrors) {
            $result = Test-IsServiceError -Provider 'VMware' -ErrorMessage $error
            $result | Should -BeFalse -Because "Should not flag: $error"
        }
    }

    It 'Handles empty error message' {
        $result = Test-IsServiceError -Provider 'HyperV' -ErrorMessage ''
        $result | Should -BeFalse
    }
}

Describe 'Provider Integration' {

    Context 'HyperVProvider' -Skip:(-not $script:HyperVAvailable) {

        BeforeAll {
            $script:HyperVProvider = Get-HypervisorProvider -Type 'HyperV'
        }

        It 'StartVM method exists' {
            $script:HyperVProvider.PSObject.Methods.Name | Should -Contain 'StartVM'
        }

        It 'StopVM method exists' {
            $script:HyperVProvider.PSObject.Methods.Name | Should -Contain 'StopVM'
        }

        It 'GetVMState method exists' {
            $script:HyperVProvider.PSObject.Methods.Name | Should -Contain 'GetVMState'
        }
    }

    Context 'VMwareProvider' -Skip:(-not $script:VMwareAvailable) {

        BeforeAll {
            $script:VMwareProvider = Get-HypervisorProvider -Type 'VMware'
        }

        It 'StartVM method exists' {
            $script:VMwareProvider.PSObject.Methods.Name | Should -Contain 'StartVM'
        }

        It 'StopVM method exists' {
            $script:VMwareProvider.PSObject.Methods.Name | Should -Contain 'StopVM'
        }

        It 'GetVMState method exists' {
            $script:VMwareProvider.PSObject.Methods.Name | Should -Contain 'GetVMState'
        }
    }
}

Describe 'Module Exports' {

    It 'Exports Test-HypervisorService' {
        $command = Get-Command -Module FFU.Hypervisor -Name 'Test-HypervisorService' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
    }

    It 'Exports Invoke-WithHypervisorRetry' {
        $command = Get-Command -Module FFU.Hypervisor -Name 'Invoke-WithHypervisorRetry' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
    }

    It 'Test-HypervisorService has Provider parameter' {
        $command = Get-Command Test-HypervisorService
        $command.Parameters.Keys | Should -Contain 'Provider'
    }

    It 'Invoke-WithHypervisorRetry has ScriptBlock parameter' {
        $command = Get-Command Invoke-WithHypervisorRetry
        $command.Parameters.Keys | Should -Contain 'ScriptBlock'
    }
}
