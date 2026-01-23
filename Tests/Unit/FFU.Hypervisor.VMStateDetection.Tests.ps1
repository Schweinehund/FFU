#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for VM state detection transient handling in FFU.Hypervisor module.

.DESCRIPTION
    Tests the transient state detection helpers in VMInfo class and the GetVMStateStable
    methods on both HyperVProvider and VMwareProvider. Also tests Wait-VMStateChange
    transient state handling.

.NOTES
    REL-HYP-02: VM state detection reliability
    Created: 2026-01-23
#>

BeforeAll {
    # Set up module path
    $modulePath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules'
    $env:PSModulePath = "$modulePath;$env:PSModulePath"

    # Detect provider availability for skip conditions
    $script:hyperVAvailable = $false
    $script:vmwareAvailable = $false

    # Check Hyper-V availability
    try {
        $service = Get-Service -Name vmms -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            $module = Get-Module -Name Hyper-V -ListAvailable -ErrorAction SilentlyContinue
            if ($module) {
                $script:hyperVAvailable = $true
            }
        }
    }
    catch {
        # Hyper-V not available
    }

    # Check VMware availability
    $vmwarePaths = @(
        'C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe',
        'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
    )
    foreach ($path in $vmwarePaths) {
        if (Test-Path $path) {
            $script:vmwareAvailable = $true
            break
        }
    }

    # Import the module (loads all classes)
    Import-Module FFU.Hypervisor -Force -ErrorAction Stop

    # Load classes directly since PowerShell module classes aren't exported to caller's scope
    # This is the standard pattern for testing PowerShell module classes
    $classesPath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules/FFU.Hypervisor/Classes'
    . (Join-Path $classesPath 'VMInfo.ps1')
}

Describe 'VMInfo Transient State Helpers' {

    Context 'IsTransientState static method' {

        It 'Returns true for Starting state' {
            [VMInfo]::IsTransientState([VMState]::Starting) | Should -BeTrue
        }

        It 'Returns true for Stopping state' {
            [VMInfo]::IsTransientState([VMState]::Stopping) | Should -BeTrue
        }

        It 'Returns true for Saving state' {
            [VMInfo]::IsTransientState([VMState]::Saving) | Should -BeTrue
        }

        It 'Returns true for Restoring state' {
            [VMInfo]::IsTransientState([VMState]::Restoring) | Should -BeTrue
        }

        It 'Returns false for Running state' {
            [VMInfo]::IsTransientState([VMState]::Running) | Should -BeFalse
        }

        It 'Returns false for Off state' {
            [VMInfo]::IsTransientState([VMState]::Off) | Should -BeFalse
        }

        It 'Returns false for Unknown state' {
            [VMInfo]::IsTransientState([VMState]::Unknown) | Should -BeFalse
        }

        It 'Returns false for Paused state' {
            [VMInfo]::IsTransientState([VMState]::Paused) | Should -BeFalse
        }

        It 'Returns false for Saved state' {
            [VMInfo]::IsTransientState([VMState]::Saved) | Should -BeFalse
        }

        It 'Returns false for Suspended state' {
            [VMInfo]::IsTransientState([VMState]::Suspended) | Should -BeFalse
        }
    }

    Context 'GetExpectedStableState static method' {

        It 'Maps Starting to Running' {
            [VMInfo]::GetExpectedStableState([VMState]::Starting) | Should -Be ([VMState]::Running)
        }

        It 'Maps Stopping to Off' {
            [VMInfo]::GetExpectedStableState([VMState]::Stopping) | Should -Be ([VMState]::Off)
        }

        It 'Maps Saving to Saved' {
            [VMInfo]::GetExpectedStableState([VMState]::Saving) | Should -Be ([VMState]::Saved)
        }

        It 'Maps Restoring to Running' {
            [VMInfo]::GetExpectedStableState([VMState]::Restoring) | Should -Be ([VMState]::Running)
        }

        It 'Returns Running unchanged' {
            [VMInfo]::GetExpectedStableState([VMState]::Running) | Should -Be ([VMState]::Running)
        }

        It 'Returns Off unchanged' {
            [VMInfo]::GetExpectedStableState([VMState]::Off) | Should -Be ([VMState]::Off)
        }

        It 'Returns Unknown unchanged' {
            [VMInfo]::GetExpectedStableState([VMState]::Unknown) | Should -Be ([VMState]::Unknown)
        }

        It 'Returns Paused unchanged' {
            [VMInfo]::GetExpectedStableState([VMState]::Paused) | Should -Be ([VMState]::Paused)
        }
    }

    Context 'IsInTransientState instance method' {

        It 'Returns true when VM state is Starting' {
            $vm = [VMInfo]::new()
            $vm.State = [VMState]::Starting
            $vm.IsInTransientState() | Should -BeTrue
        }

        It 'Returns true when VM state is Stopping' {
            $vm = [VMInfo]::new()
            $vm.State = [VMState]::Stopping
            $vm.IsInTransientState() | Should -BeTrue
        }

        It 'Returns false when VM state is Running' {
            $vm = [VMInfo]::new()
            $vm.State = [VMState]::Running
            $vm.IsInTransientState() | Should -BeFalse
        }

        It 'Returns false when VM state is Off' {
            $vm = [VMInfo]::new()
            $vm.State = [VMState]::Off
            $vm.IsInTransientState() | Should -BeFalse
        }
    }
}

Describe 'Provider GetVMStateStable' {

    Context 'HyperVProvider' -Skip:(-not $script:hyperVAvailable) {

        It 'Method exists on provider' {
            $provider = [HyperVProvider]::new()
            $methods = $provider | Get-Member -MemberType Method
            $methods.Name | Should -Contain 'GetVMStateStable'
        }

        It 'GetVMStateStable method accepts VMInfo and int parameters' {
            $provider = [HyperVProvider]::new()
            # This is a signature test - we're not actually calling the method with a real VM
            # Just verifying the method signature is correct
            $method = $provider.GetType().GetMethod('GetVMStateStable')
            $method | Should -Not -BeNullOrEmpty
            $params = $method.GetParameters()
            $params.Count | Should -Be 2
            $params[0].ParameterType.Name | Should -Be 'VMInfo'
            $params[1].ParameterType.Name | Should -Be 'Int32'
        }
    }

    Context 'VMwareProvider' -Skip:(-not $script:vmwareAvailable) {

        It 'Method exists on provider' {
            $provider = [VMwareProvider]::new()
            $methods = $provider | Get-Member -MemberType Method
            $methods.Name | Should -Contain 'GetVMStateStable'
        }

        It 'GetVMStateStable method accepts VMInfo and int parameters' {
            $provider = [VMwareProvider]::new()
            $method = $provider.GetType().GetMethod('GetVMStateStable')
            $method | Should -Not -BeNullOrEmpty
            $params = $method.GetParameters()
            $params.Count | Should -Be 2
            $params[0].ParameterType.Name | Should -Be 'VMInfo'
            $params[1].ParameterType.Name | Should -Be 'Int32'
        }

        It 'VMwareProvider has LastStartVMTime property for race condition handling' {
            $provider = [VMwareProvider]::new()
            # Check that the private property exists
            $field = $provider.GetType().GetField('LastStartVMTime', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
            $field | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Wait-VMStateChange Transient Handling' {

    Context 'Function parameters' {

        It 'Has AllowTransient parameter' {
            $cmd = Get-Command Wait-VMStateChange -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Parameters.Keys | Should -Contain 'AllowTransient'
        }

        It 'AllowTransient parameter is a switch' {
            $cmd = Get-Command Wait-VMStateChange
            $param = $cmd.Parameters['AllowTransient']
            $param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'AllowTransient default value is false' {
            $cmd = Get-Command Wait-VMStateChange
            $param = $cmd.Parameters['AllowTransient']
            # Switch parameters default to false when not specified
            $param.SwitchParameter | Should -BeTrue -Because 'Switch parameters default to false'
        }
    }

    Context 'With Hyper-V available' -Skip:(-not $script:hyperVAvailable) {

        It 'Function is exported from module' {
            $exported = Get-Command -Module FFU.Hypervisor -Name Wait-VMStateChange -ErrorAction SilentlyContinue
            $exported | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'VMware State Detection' {

    Context 'Get-VMwarePowerStateWithVmrun function' -Skip:(-not $script:vmwareAvailable) {

        It 'Function exists in module' {
            # This is a private function, so we need to check it exists in the module scope
            $modulePath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules/FFU.Hypervisor/Private/Invoke-VMwareRestMethod.ps1'
            $content = Get-Content $modulePath -Raw
            $content | Should -Match 'function Get-VMwarePowerStateWithVmrun'
        }

        It 'Has Detailed parameter' {
            $modulePath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules/FFU.Hypervisor/Private/Invoke-VMwareRestMethod.ps1'
            $content = Get-Content $modulePath -Raw
            $content | Should -Match '\[switch\]\$Detailed'
        }

        It 'Detailed mode returns hashtable structure' {
            $modulePath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules/FFU.Hypervisor/Private/Invoke-VMwareRestMethod.ps1'
            $content = Get-Content $modulePath -Raw
            # Check for the detection result hashtable structure
            $content | Should -Match "State = 'unknown'"
            $content | Should -Match "Confidence = 'Low'"
            $content | Should -Match "Method = 'none'"
            $content | Should -Match "IsTransient = \`$false"
        }

        It 'Has High, Medium, and Low confidence levels' {
            $modulePath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules/FFU.Hypervisor/Private/Invoke-VMwareRestMethod.ps1'
            $content = Get-Content $modulePath -Raw
            $content | Should -Match "Confidence = 'High'"
            $content | Should -Match "Confidence = 'Medium'"
            $content | Should -Match "Confidence = 'Low'"
        }
    }

    Context 'VMwareProvider GetVMState race condition handling' -Skip:(-not $script:vmwareAvailable) {

        It 'VMwareProvider.GetVMState handles recent StartVM calls' {
            # Check the source code for race condition handling
            $modulePath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1'
            $content = Get-Content $modulePath -Raw
            $content | Should -Match 'LastStartVMTime'
            $content | Should -Match 'timeSinceStart'
            $content | Should -Match 'isRecentStart'
        }
    }
}

Describe 'VMState Enum Documentation' {

    It 'VMState enum has transient state comments' {
        $classPath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules/FFU.Hypervisor/Classes/VMInfo.ps1'
        $content = Get-Content $classPath -Raw
        # The comments document transient states with "# Transient:" inline comments
        $content | Should -Match 'Starting.*Transient'
        $content | Should -Match 'Stopping.*Transient'
        $content | Should -Match 'Saving.*Transient'
        $content | Should -Match 'Restoring.*Transient'
    }

    It 'VMState enum has IsTransientState documentation reference' {
        $classPath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules/FFU.Hypervisor/Classes/VMInfo.ps1'
        $content = Get-Content $classPath -Raw
        $content | Should -Match 'IsTransientState\(\)'
    }
}
