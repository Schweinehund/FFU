#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for FFU.VM reliability features

.DESCRIPTION
    Pester tests for VM creation diagnostics and cleanup in FFU.VM module.
    Tests cover:
    - Get-VMCreationDiagnostics error classification
    - Get-VMCreationDiagnostics remediation guidance
    - Module exports verification

.NOTES
    REL-VM-01: VM creation diagnostics and cleanup registration
    These tests validate that users receive helpful error classification
    and remediation guidance when VM creation fails.
#>

BeforeAll {
    # Get paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulesPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\Modules'
    $script:FFUCommonPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\FFU.Common'

    # Add modules folder to PSModulePath if not present
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Import FFU.Common first (provides WriteLog function)
    Import-Module (Join-Path $FFUCommonPath 'FFU.Common.psd1') -Force -ErrorAction Stop

    # Import FFU.Core (dependency)
    Import-Module (Join-Path $ModulesPath 'FFU.Core\FFU.Core.psd1') -Force -ErrorAction Stop

    # Import the FFU.VM module
    Import-Module (Join-Path $ModulesPath 'FFU.VM\FFU.VM.psd1') -Force -ErrorAction Stop

    # Mock WriteLog in FFU.Common to suppress log file operations during tests
    Mock WriteLog { } -ModuleName 'FFU.Common'
}

Describe 'FFU.VM Reliability - REL-VM-01' -Tag 'Unit', 'FFU.VM', 'Reliability' {

    Context 'Get-VMCreationDiagnostics Error Classification' {

        It 'Should classify already exists error correctly' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "A virtual machine with the same name already exists" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'AlreadyExists'
            $result.IsCritical | Should -Be $true
        }

        It 'Should classify "name is already in use" error correctly' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "The name is already in use by another VM" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'AlreadyExists'
            $result.IsCritical | Should -Be $true
        }

        It 'Should classify insufficient memory error correctly' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Insufficient memory to start the VM" `
                                                -FailedStep 'StartVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'InsufficientResources'
            $result.IsCritical | Should -Be $true
        }

        It 'Should classify "not enough memory" error correctly' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Not enough memory available on the system" `
                                                -FailedStep 'StartVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'InsufficientResources'
            $result.IsCritical | Should -Be $true
        }

        It 'Should classify TPM/HGS error as non-critical' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Failed to create HGS Guardian" `
                                                -FailedStep 'ConfigureTPM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'TPMConfiguration'
            $result.IsCritical | Should -Be $false
        }

        It 'Should classify guardian error as non-critical' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Cannot find the guardian certificate" `
                                                -FailedStep 'ConfigureTPM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'TPMConfiguration'
            $result.IsCritical | Should -Be $false
        }

        It 'Should classify path not found error correctly' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Cannot find path 'C:\VMs\NonExistent'" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM' -VMPath 'C:\VMs\NonExistent'

            $result.ErrorType | Should -Be 'PathNotFound'
            $result.IsCritical | Should -Be $true
        }

        It 'Should classify access denied error correctly' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Access is denied to the specified path" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'AccessDenied'
            $result.IsCritical | Should -Be $true
        }

        It 'Should classify Hyper-V not enabled error correctly' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Hyper-V is not enabled on this machine" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'HypervisorNotAvailable'
            $result.IsCritical | Should -Be $true
        }

        It 'Should classify VHDX in use error correctly' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "The virtual hard disk is currently in use" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'DiskError'
            $result.IsCritical | Should -Be $true
        }

        It 'Should classify unknown errors with Unknown type' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Some completely unrecognized error" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'Unknown'
            $result.IsCritical | Should -Be $true
            $result.Remediation | Should -Match 'Some completely unrecognized error'
        }
    }

    Context 'Get-VMCreationDiagnostics Remediation' {

        It 'Should include VM removal command for already exists' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "VM already exists" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.Remediation | Should -Match 'Remove-VM'
            $result.Remediation | Should -Match 'TestVM'
        }

        It 'Should include memory guidance for insufficient resources' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Insufficient memory" `
                                                -FailedStep 'StartVM' -VMName 'TestVM'

            $result.Remediation | Should -Match 'memory'
        }

        It 'Should include path in PathNotFound remediation when provided' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Cannot find path" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM' `
                                                -VMPath 'C:\CustomPath'

            $result.Remediation | Should -Match 'C:\\CustomPath'
        }

        It 'Should note TPM is non-critical' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "HGS Guardian failed" `
                                                -FailedStep 'ConfigureTPM' -VMName 'TestVM'

            $result.Remediation | Should -Match 'non-critical'
        }

        It 'Should include Enable-WindowsOptionalFeature for Hyper-V errors' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Hyper-V is not available" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.Remediation | Should -Match 'Enable-WindowsOptionalFeature'
            $result.Remediation | Should -Match 'Microsoft-Hyper-V'
        }

        It 'Should include Administrator guidance for access denied' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Access denied" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.Remediation | Should -Match 'Administrator'
        }
    }

    Context 'Get-VMCreationDiagnostics ResourcesCreated' {

        It 'Should indicate no resources created for CreateVM failure' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Some error" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ResourcesCreated.Count | Should -Be 0
        }

        It 'Should indicate VM resource for ConfigureProcessor failure' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Some error" `
                                                -FailedStep 'ConfigureProcessor' -VMName 'TestVM'

            $result.ResourcesCreated | Should -Contain 'VM'
        }

        It 'Should indicate VM resource for MountISO failure' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Some error" `
                                                -FailedStep 'MountISO' -VMName 'TestVM'

            $result.ResourcesCreated | Should -Contain 'VM'
        }

        It 'Should indicate VM and HGSGuardian resources for StartVM failure' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Some error" `
                                                -FailedStep 'StartVM' -VMName 'TestVM'

            $result.ResourcesCreated | Should -Contain 'VM'
            $result.ResourcesCreated | Should -Contain 'HGSGuardian'
        }
    }

    Context 'Get-VMCreationDiagnostics Output Properties' {

        It 'Should return all expected properties' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Test error" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.PSObject.Properties.Name | Should -Contain 'ErrorType'
            $result.PSObject.Properties.Name | Should -Contain 'FailedStep'
            $result.PSObject.Properties.Name | Should -Contain 'OriginalError'
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
            $result.PSObject.Properties.Name | Should -Contain 'IsCritical'
            $result.PSObject.Properties.Name | Should -Contain 'ResourcesCreated'
        }

        It 'Should preserve original error message' {
            $originalMessage = "This is the exact original error message"
            $result = Get-VMCreationDiagnostics -ErrorMessage $originalMessage `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.OriginalError | Should -Be $originalMessage
        }

        It 'Should preserve failed step' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Some error" `
                                                -FailedStep 'ConfigureTPM' -VMName 'TestVM'

            $result.FailedStep | Should -Be 'ConfigureTPM'
        }
    }

    Context 'Module Exports Verification' {

        It 'Get-VMCreationDiagnostics is exported' {
            $cmd = Get-Command Get-VMCreationDiagnostics -Module FFU.VM -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Get-VMCreationDiagnostics has correct parameters' {
            $cmd = Get-Command Get-VMCreationDiagnostics -Module FFU.VM
            $cmd.Parameters.Keys | Should -Contain 'ErrorMessage'
            $cmd.Parameters.Keys | Should -Contain 'FailedStep'
            $cmd.Parameters.Keys | Should -Contain 'VMName'
            $cmd.Parameters.Keys | Should -Contain 'VMPath'
        }

        It 'FailedStep parameter has ValidateSet' {
            $cmd = Get-Command Get-VMCreationDiagnostics -Module FFU.VM
            $validateSet = $cmd.Parameters['FailedStep'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'CreateVM'
            $validateSet.ValidValues | Should -Contain 'ConfigureTPM'
            $validateSet.ValidValues | Should -Contain 'StartVM'
        }
    }

    Context 'Error Classification Edge Cases' {

        It 'Should handle case-insensitive error matching' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "ALREADY EXISTS IN UPPERCASE" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'AlreadyExists'
        }

        It 'Should handle mixed case error matching' {
            $result = Get-VMCreationDiagnostics -ErrorMessage "Hyper-V Is Not Available" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            $result.ErrorType | Should -Be 'HypervisorNotAvailable'
        }

        It 'Should handle errors with multiple keywords' {
            # Error contains both "path" and "access" - should prioritize properly
            $result = Get-VMCreationDiagnostics -ErrorMessage "Cannot find path due to access denied" `
                                                -FailedStep 'CreateVM' -VMName 'TestVM'

            # Should match first pattern (path not found)
            $result.ErrorType | Should -BeIn @('PathNotFound', 'AccessDenied')
        }
    }
}

Describe 'FFU.VM Module Integration - REL-VM-01' -Tag 'Unit', 'FFU.VM', 'Reliability' {

    Context 'New-FFUVM Prerequisites' {

        It 'New-FFUVM function exists' {
            $cmd = Get-Command New-FFUVM -Module FFU.VM -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Register-VMCleanup is available from FFU.Core' {
            $cmd = Get-Command Register-VMCleanup -Module FFU.Core -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Register-CleanupAction is available from FFU.Core' {
            $cmd = Get-Command Register-CleanupAction -Module FFU.Core -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Unregister-CleanupAction is available from FFU.Core' {
            $cmd = Get-Command Unregister-CleanupAction -Module FFU.Core -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# REL-VM-02: Orphan Detection and Cleanup Tests
# =============================================================================
Describe 'FFU.VM Reliability - REL-VM-02' -Tag 'Unit', 'FFU.VM', 'Reliability' {

    Context 'Get-OrphanedVMResources Function' {
        It 'Should be exported from FFU.VM module' {
            Get-Command -Name 'Get-OrphanedVMResources' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUDevelopmentPath parameter' {
            $cmd = Get-Command -Name 'Get-OrphanedVMResources' -Module 'FFU.VM'
            $cmd.Parameters['FFUDevelopmentPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have IncludeVMware switch parameter' {
            $cmd = Get-Command -Name 'Get-OrphanedVMResources' -Module 'FFU.VM'
            $cmd.Parameters['IncludeVMware'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ScanOnly switch parameter' {
            $cmd = Get-Command -Name 'Get-OrphanedVMResources' -Module 'FFU.VM'
            $cmd.Parameters['ScanOnly'] | Should -Not -BeNullOrEmpty
        }

        It 'Should return object with TotalOrphans property' {
            # Mock the module functions for isolated testing
            Mock Get-VM { @() } -ModuleName FFU.VM
            Mock Get-HgsGuardian { @() } -ModuleName FFU.VM
            Mock Get-ChildItem { @() } -ModuleName FFU.VM
            Mock Test-Path { $false } -ModuleName FFU.VM
            Mock WriteLog { } -ModuleName FFU.VM

            $result = Get-OrphanedVMResources -FFUDevelopmentPath 'C:\TestPath' -ScanOnly
            $result.TotalOrphans | Should -Be 0
        }
    }

    Context 'Remove-FFUVM Lock File Cleanup' {
        BeforeAll {
            $script:FFUVMModule = Join-Path $script:ModulesPath 'FFU.VM\FFU.VM.psm1'
        }

        It 'Should have cleanup logic for .lck directories' {
            $modulePath = $script:FFUVMModule
            $content = Get-Content $modulePath -Raw
            $content | Should -Match '\.lck.*-Directory'
        }

        It 'Should check for running vmware-vmx before removing locks' {
            $modulePath = $script:FFUVMModule
            $content = Get-Content $modulePath -Raw
            $content | Should -Match 'vmware-vmx'
        }
    }

    Context 'Remove-FFUVM Checkpoint Cleanup' {
        BeforeAll {
            $script:FFUVMModule = Join-Path $script:ModulesPath 'FFU.VM\FFU.VM.psm1'
        }

        It 'Should have cleanup logic for .avhdx files' {
            $modulePath = $script:FFUVMModule
            $content = Get-Content $modulePath -Raw
            $content | Should -Match '\.avhdx'
        }
    }
}

# =============================================================================
# REL-VM-03: Transient Error Retry Tests
# =============================================================================
Describe 'FFU.VM Reliability - REL-VM-03' -Tag 'Unit', 'FFU.VM', 'Reliability' {

    Context 'Test-IsTransientVMError Classification' {
        It 'Should classify disk busy as transient' {
            Test-IsTransientVMError -ErrorMessage "The disk is busy" | Should -BeTrue
        }

        It 'Should classify file locked as transient' {
            Test-IsTransientVMError -ErrorMessage "The file is locked by another process" | Should -BeTrue
        }

        It 'Should classify file in use as transient' {
            Test-IsTransientVMError -ErrorMessage "The process cannot access the file because it is being used by another process" | Should -BeTrue
        }

        It 'Should classify network timeout as transient' {
            Test-IsTransientVMError -ErrorMessage "Network operation timed out" | Should -BeTrue
        }

        It 'Should classify RPC unavailable as transient' {
            Test-IsTransientVMError -ErrorMessage "The RPC server is unavailable" | Should -BeTrue
        }

        It 'Should classify sharing violation as transient' {
            Test-IsTransientVMError -ErrorMessage "The file has a sharing violation" | Should -BeTrue
        }

        It 'Should classify device not ready as transient' {
            Test-IsTransientVMError -ErrorMessage "The device is not ready" | Should -BeTrue
        }

        It 'Should classify operation timed out as transient' {
            Test-IsTransientVMError -ErrorMessage "The operation timed out" | Should -BeTrue
        }

        It 'Should classify already exists as permanent (not transient)' {
            Test-IsTransientVMError -ErrorMessage "A VM with this name already exists" | Should -BeFalse
        }

        It 'Should classify not found as permanent' {
            Test-IsTransientVMError -ErrorMessage "The specified VM was not found" | Should -BeFalse
        }

        It 'Should classify insufficient memory as permanent' {
            Test-IsTransientVMError -ErrorMessage "Insufficient memory to complete operation" | Should -BeFalse
        }

        It 'Should classify disk full as permanent' {
            Test-IsTransientVMError -ErrorMessage "There is not enough disk space" | Should -BeFalse
        }

        It 'Should classify invalid parameter as permanent' {
            Test-IsTransientVMError -ErrorMessage "Invalid parameter specified" | Should -BeFalse
        }

        It 'Should classify out of memory as permanent' {
            Test-IsTransientVMError -ErrorMessage "System is out of memory" | Should -BeFalse
        }

        It 'Should classify Hyper-V not enabled as permanent' {
            Test-IsTransientVMError -ErrorMessage "Hyper-V is not enabled on this system" | Should -BeFalse
        }

        It 'Should classify unknown errors as not transient (fail fast)' {
            Test-IsTransientVMError -ErrorMessage "Some random error message" | Should -BeFalse
        }

        It 'Should handle empty error message' {
            Test-IsTransientVMError -ErrorMessage "" | Should -BeFalse
        }

        It 'Should be case insensitive for transient patterns' {
            Test-IsTransientVMError -ErrorMessage "THE DISK IS BUSY" | Should -BeTrue
        }

        It 'Should be case insensitive for permanent patterns' {
            Test-IsTransientVMError -ErrorMessage "VM ALREADY EXISTS" | Should -BeFalse
        }
    }

    Context 'Invoke-VMOperationWithRetry Function' {
        It 'Should be exported from FFU.VM module' {
            Get-Command -Name 'Invoke-VMOperationWithRetry' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should have ScriptBlock parameter' {
            $cmd = Get-Command -Name 'Invoke-VMOperationWithRetry' -Module 'FFU.VM'
            $cmd.Parameters['ScriptBlock'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have OperationName parameter' {
            $cmd = Get-Command -Name 'Invoke-VMOperationWithRetry' -Module 'FFU.VM'
            $cmd.Parameters['OperationName'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have MaxRetries parameter' {
            $cmd = Get-Command -Name 'Invoke-VMOperationWithRetry' -Module 'FFU.VM'
            $cmd.Parameters['MaxRetries'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have BaseDelaySeconds parameter' {
            $cmd = Get-Command -Name 'Invoke-VMOperationWithRetry' -Module 'FFU.VM'
            $cmd.Parameters['BaseDelaySeconds'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have UseHypervisorRetry switch parameter' {
            $cmd = Get-Command -Name 'Invoke-VMOperationWithRetry' -Module 'FFU.VM'
            $cmd.Parameters['UseHypervisorRetry'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Provider parameter with ValidateSet' {
            $cmd = Get-Command -Name 'Invoke-VMOperationWithRetry' -Module 'FFU.VM'
            $param = $cmd.Parameters['Provider']
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'HyperV'
            $validateSet.ValidValues | Should -Contain 'VMware'
        }

        It 'Should execute script block successfully on first try' {
            $result = Invoke-VMOperationWithRetry -OperationName 'Test' -ScriptBlock {
                return "success"
            }
            $result | Should -Be "success"
        }

        It 'Should return script block result without retry on success' {
            $result = Invoke-VMOperationWithRetry -OperationName 'Test' -ScriptBlock {
                return 42
            }
            $result | Should -Be 42
        }

        It 'Should fail immediately for permanent errors' {
            {
                Invoke-VMOperationWithRetry -OperationName 'Test' -MaxRetries 3 -ScriptBlock {
                    throw "VM already exists"
                }
            } | Should -Throw
        }

        It 'Should throw original error for permanent errors (already exists)' {
            # Verify that permanent errors are thrown without retry
            $errorThrown = $null
            try {
                Invoke-VMOperationWithRetry -OperationName 'Test' -MaxRetries 3 -ScriptBlock {
                    throw "A VM with this name already exists"
                }
            } catch {
                $errorThrown = $_
            }
            $errorThrown | Should -Not -BeNullOrEmpty
            $errorThrown.Exception.Message | Should -Match 'already exists'
        }

        It 'Should throw original error for permanent errors (not found)' {
            $errorThrown = $null
            try {
                Invoke-VMOperationWithRetry -OperationName 'Test' -MaxRetries 3 -ScriptBlock {
                    throw "The specified resource was not found"
                }
            } catch {
                $errorThrown = $_
            }
            $errorThrown | Should -Not -BeNullOrEmpty
            $errorThrown.Exception.Message | Should -Match 'not found'
        }

        It 'Should throw original error for permanent errors (insufficient memory)' {
            $errorThrown = $null
            try {
                Invoke-VMOperationWithRetry -OperationName 'Test' -MaxRetries 3 -ScriptBlock {
                    throw "Insufficient memory available"
                }
            } catch {
                $errorThrown = $_
            }
            $errorThrown | Should -Not -BeNullOrEmpty
            $errorThrown.Exception.Message | Should -Match 'Insufficient memory'
        }
    }

    Context 'Test-IsTransientVMError Module Export' {
        It 'Should be exported from FFU.VM module' {
            Get-Command -Name 'Test-IsTransientVMError' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should have ErrorMessage parameter' {
            $cmd = Get-Command -Name 'Test-IsTransientVMError' -Module 'FFU.VM'
            $cmd.Parameters['ErrorMessage'] | Should -Not -BeNullOrEmpty
        }

        It 'Should return boolean type' {
            $cmd = Get-Command -Name 'Test-IsTransientVMError' -Module 'FFU.VM'
            $outputType = $cmd.OutputType
            $outputType.Type | Should -Be ([bool])
        }
    }
}
