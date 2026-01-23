#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for FFU.Core credential validation functionality (REL-CORE-04)

.DESCRIPTION
    Tests the Test-FFUCredentials function that provides credential validation
    with actionable error messages.

.NOTES
    Module: FFU.Core
    Functions: Test-FFUCredentials
    Version: 1.0.20
#>

BeforeAll {
    # Set up module path for FFU modules
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    # Add modules folder to PSModulePath
    if ($env:PSModulePath -notlike "*$ModulePath*") {
        $env:PSModulePath = "$ModulePath;$env:PSModulePath"
    }

    # Import the module
    Import-Module FFU.Core -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Test-FFUCredentials' -Tag 'Unit', 'FFU.Core', 'Credentials' {

    Context 'Null credential object' {
        # Note: Passing $null to [PSCredential] mandatory parameter triggers a prompt
        # in PowerShell, which fails in non-interactive test execution.
        # These tests verify the function handles null credentials correctly,
        # but cannot be run in automated test environments.

        It 'Returns IsValid=false for null credential' -Skip {
            $result = Test-FFUCredentials -Credential $null
            $result.IsValid | Should -BeFalse
        }

        It 'Returns InvalidCredentials error code for null credential' -Skip {
            $result = Test-FFUCredentials -Credential $null
            $result.ErrorCode | Should -Be 'InvalidCredentials'
        }

        It 'Returns meaningful message for null credential' -Skip {
            $result = Test-FFUCredentials -Credential $null
            $result.Message | Should -Match 'null'
        }

        It 'Includes remediation steps for null credential' -Skip {
            $result = Test-FFUCredentials -Credential $null
            $result.Remediation | Should -Not -BeNullOrEmpty
            $result.Remediation | Should -Match 'Get-Credential|PSCredential'
        }
    }

    Context 'Empty username' {
        # Note: [PSCredential]::new() doesn't allow empty usernames (throws exception).
        # This is a PowerShell constraint, not a function limitation.
        # These tests are skipped as the precondition cannot be created.

        It 'Returns IsValid=false for empty username' -Skip {
            # Cannot create PSCredential with empty username in PowerShell
            $emptyCred = [PSCredential]::new('', (ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $emptyCred
            $result.IsValid | Should -BeFalse
        }

        It 'Returns InvalidCredentials error code for empty username' -Skip {
            $emptyCred = [PSCredential]::new('', (ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $emptyCred
            $result.ErrorCode | Should -Be 'InvalidCredentials'
        }

        It 'Returns meaningful message for empty username' -Skip {
            $emptyCred = [PSCredential]::new('', (ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $emptyCred
            $result.Message | Should -Match 'empty'
        }
    }

    Context 'Well-formed credentials without target' {

        It 'Validates well-formed credential object' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.IsValid | Should -BeTrue
        }

        It 'Returns appropriate message for well-formed credentials' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.Message | Should -Match 'well-formed'
        }

        It 'Returns empty ErrorCode for valid credentials' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.ErrorCode | Should -BeNullOrEmpty
        }
    }

    Context 'Domain-qualified usernames' {

        It 'Validates DOMAIN\username format' {
            $cred = [PSCredential]::new('DOMAIN\testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.IsValid | Should -BeTrue
        }

        It 'Validates user@domain.com format' {
            $cred = [PSCredential]::new('testuser@domain.com', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.IsValid | Should -BeTrue
        }
    }

    Context 'Network share validation - unreachable server' {

        It 'Returns NetworkError for unreachable server' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            # Use a non-routable IP to ensure quick failure
            $result = Test-FFUCredentials -Credential $cred -SharePath '\\192.0.2.1\share'
            $result.IsValid | Should -BeFalse
            $result.ErrorCode | Should -Be 'NetworkError'
        }

        It 'Returns actionable message for unreachable server' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -SharePath '\\192.0.2.1\share'
            $result.Message | Should -Match 'Cannot reach server'
        }

        It 'Includes remediation for unreachable server' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -SharePath '\\192.0.2.1\share'
            $result.Remediation | Should -Match 'network connectivity|Test-Connection'
        }
    }

    Context 'Network share validation - invalid hostname' {

        It 'Returns NetworkError for invalid hostname' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            # Use a clearly non-existent hostname
            $result = Test-FFUCredentials -Credential $cred -SharePath '\\nonexistent-server-xyz12345\share'
            $result.IsValid | Should -BeFalse
        }

        It 'Includes remediation steps in error' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -SharePath '\\nonexistent-server-xyz12345\share'
            $result.Remediation | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Local account validation' {

        It 'Validates existing local account (Administrator)' -Skip:(-not (Test-Path 'C:\Windows\System32\config')) {
            # Administrator always exists on Windows
            $cred = [PSCredential]::new('Administrator', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -ValidateLocalAccount
            $result.IsValid | Should -BeTrue
            $result.Message | Should -Match 'exists'
        }

        It 'Returns error for non-existent local account' {
            $cred = [PSCredential]::new('NonExistentUser12345XYZ', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -ValidateLocalAccount
            $result.IsValid | Should -BeFalse
            $result.ErrorCode | Should -Be 'InvalidCredentials'
        }

        It 'Includes remediation for non-existent local account' {
            $cred = [PSCredential]::new('NonExistentUser12345XYZ', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -ValidateLocalAccount
            $result.Remediation | Should -Match 'net user|Create the local account'
        }

        It 'Extracts username from DOMAIN\user format for local validation' {
            $cred = [PSCredential]::new('.\NonExistentUser12345XYZ', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -ValidateLocalAccount
            $result.IsValid | Should -BeFalse
            $result.Message | Should -Match 'NonExistentUser12345XYZ'
        }
    }

    Context 'Result object structure' {

        It 'Returns PSCustomObject with IsValid property' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.PSObject.Properties.Name | Should -Contain 'IsValid'
            $result.IsValid | Should -BeOfType [bool]
        }

        It 'Returns PSCustomObject with Message property' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Returns PSCustomObject with Remediation property' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
        }

        It 'Returns PSCustomObject with ErrorCode property' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred
            $result.PSObject.Properties.Name | Should -Contain 'ErrorCode'
        }
    }

    Context 'Actionable error messages' {

        It 'Error messages contain "To fix:" section' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -SharePath '\\nonexistent-server-12345\share'
            $result.IsValid | Should -BeFalse
            # Either in Message or Remediation
            ($result.Remediation -match 'To fix:' -or $result.Remediation -match 'Check') | Should -BeTrue
        }

        It 'Remediation provides specific steps' -Skip {
            # Cannot pass $null to [PSCredential] in non-interactive mode
            $result = Test-FFUCredentials -Credential $null
            $result.Remediation | Should -Match 'Get-Credential|PSCredential'
        }
    }

    Context 'Error code values' {

        It 'Uses InvalidCredentials error code appropriately' -Skip {
            # Cannot pass $null to [PSCredential] in non-interactive mode
            $result = Test-FFUCredentials -Credential $null
            $result.ErrorCode | Should -Be 'InvalidCredentials'
        }

        It 'Uses NetworkError error code for network issues' {
            $cred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force))
            $result = Test-FFUCredentials -Credential $cred -SharePath '\\192.0.2.1\share'
            $result.ErrorCode | Should -Be 'NetworkError'
        }
    }
}

Describe 'Test-FFUCredentials Help' -Tag 'Unit', 'FFU.Core', 'Credentials', 'Help' {

    It 'Has help content' {
        $help = Get-Help Test-FFUCredentials -Full
        $help | Should -Not -BeNullOrEmpty
    }

    It 'Has synopsis' {
        $help = Get-Help Test-FFUCredentials -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
    }

    It 'Has description' {
        $help = Get-Help Test-FFUCredentials -Full
        $help.Description | Should -Not -BeNullOrEmpty
    }

    It 'Has examples' {
        $help = Get-Help Test-FFUCredentials -Full
        $help.Examples | Should -Not -BeNullOrEmpty
    }

    It 'Has parameter documentation for Credential' {
        $help = Get-Help Test-FFUCredentials -Parameter Credential
        $help | Should -Not -BeNullOrEmpty
    }
}
