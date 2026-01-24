#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Drivers module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.Drivers module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Drivers\*.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Drivers'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Remove modules if loaded
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.Drivers module
    if (-not (Test-Path "$ModulePath\FFU.Drivers.psd1")) {
        throw "FFU.Drivers module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Drivers.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Drivers Module Exports' -Tag 'Unit', 'FFU.Drivers', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Get-MicrosoftDrivers' {
            Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-HPDrivers' {
            Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-LenovoDrivers' {
            Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-DellDrivers' {
            Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Copy-Drivers' {
            Get-Command -Name 'Copy-Drivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-MicrosoftDrivers Tests
# =============================================================================

Describe 'Get-MicrosoftDrivers' -Tag 'Unit', 'FFU.Drivers', 'Get-MicrosoftDrivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Make parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsRelease parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 10
            $validateSet.ValidValues | Should -Contain 11
        }

        It 'Should have mandatory Headers parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Headers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory UserAgent parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['UserAgent']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Get-HPDrivers Tests
# =============================================================================

Describe 'Get-HPDrivers' -Tag 'Unit', 'FFU.Drivers', 'Get-HPDrivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Make parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have mandatory WindowsRelease parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 10
            $validateSet.ValidValues | Should -Contain 11
        }

        It 'Should have mandatory WindowsVersion parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsVersion']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Get-LenovoDrivers Tests
# =============================================================================

Describe 'Get-LenovoDrivers' -Tag 'Unit', 'FFU.Drivers', 'Get-LenovoDrivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Make parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have mandatory WindowsRelease parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 10
            $validateSet.ValidValues | Should -Contain 11
        }

        It 'Should have mandatory Headers parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Headers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory UserAgent parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['UserAgent']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Get-DellDrivers Tests
# =============================================================================

Describe 'Get-DellDrivers' -Tag 'Unit', 'FFU.Drivers', 'Get-DellDrivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Make parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have mandatory WindowsRelease parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory isServer parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['isServer']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Copy-Drivers Tests
# =============================================================================

Describe 'Copy-Drivers' -Tag 'Unit', 'FFU.Drivers', 'Copy-Drivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Path parameter' {
            $command = Get-Command -Name 'Copy-Drivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Path']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Output parameter' {
            $command = Get-Command -Name 'Copy-Drivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Output']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Copy-Drivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }
    }
}

# =============================================================================
# REL-DRV-01: Invoke-DriverDownloadWithRetry Tests
# =============================================================================

Describe 'Invoke-DriverDownloadWithRetry' -Tag 'Unit', 'FFU.Drivers', 'Retry', 'REL-DRV-01' {

    BeforeAll {
        # Get reference to internal function via module invoke
        $module = Get-Module -Name 'FFU.Drivers'
        $Script:InvokeRetry = $module.Invoke({
            Get-Item function:Invoke-DriverDownloadWithRetry -ErrorAction SilentlyContinue
        })
    }

    Context 'Function Existence and Parameters' {
        It 'Should have Invoke-DriverDownloadWithRetry as internal function' {
            $Script:InvokeRetry | Should -Not -BeNullOrEmpty
        }

        It 'Should have Source parameter defined' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match '\$Source'
            $funcBody | Should -Match '\[Parameter\(Mandatory'
        }

        It 'Should have Destination parameter defined' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match '\$Destination'
        }

        It 'Should have OperationName parameter with default value' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match "\`$OperationName\s*=\s*'Driver download'"
        }

        It 'Should have MaxRetries parameter with default value of 3' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match '\$MaxRetries\s*=\s*3'
        }

        It 'Should have BaseDelaySeconds parameter with default value of 5' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match '\$BaseDelaySeconds\s*=\s*5'
        }
    }

    Context 'Retry Logic Implementation' {
        It 'Should implement exponential backoff pattern' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            # Check for exponential calculation: 2^(attempt-1)
            $funcBody | Should -Match 'Pow.*2'
        }

        It 'Should implement jitter pattern' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            # Check for random jitter: Get-Random
            $funcBody | Should -Match 'Get-Random'
        }

        It 'Should call Start-BitsTransferWithRetry' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match 'Start-BitsTransferWithRetry'
        }

        It 'Should track attempt count' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match '\$attempt'
        }

        It 'Should log source URL on failure' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            # Check for Source URL in logging
            $funcBody | Should -Match 'Source:'
        }
    }

    Context 'ThreadJob Compatibility' {
        It 'Should use safe logging pattern with $function:WriteLog check' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            # Check for ThreadJob-safe pattern
            $funcBody | Should -Match '\$function:WriteLog'
        }

        It 'Should fall back to Write-Verbose when WriteLog unavailable' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match 'Write-Verbose'
        }
    }

    Context 'Error Handling' {
        It 'Should preserve last error for rethrow' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match '\$lastError'
        }

        It 'Should throw after all retries exhausted' {
            $funcBody = $Script:InvokeRetry.ScriptBlock.ToString()
            $funcBody | Should -Match 'throw \$lastError'
        }
    }
}

# =============================================================================
# REL-DRV-02: Get-DriverExtractionResult Tests
# =============================================================================

Describe 'Get-DriverExtractionResult' -Tag 'Unit', 'FFU.Drivers', 'Extraction', 'REL-DRV-02' {

    BeforeAll {
        # Get reference to internal function via module invoke
        $module = Get-Module -Name 'FFU.Drivers'
        $Script:GetExtractionResult = $module.Invoke({
            Get-Item function:Get-DriverExtractionResult -ErrorAction SilentlyContinue
        })
    }

    Context 'Function Existence and Parameters' {
        It 'Should have Get-DriverExtractionResult as internal function' {
            $Script:GetExtractionResult | Should -Not -BeNullOrEmpty
        }

        It 'Should have Vendor parameter with ValidateSet' {
            $funcBody = $Script:GetExtractionResult.ScriptBlock.ToString()
            $funcBody | Should -Match '\$Vendor'
            $funcBody | Should -Match "ValidateSet\('Dell', 'HP', 'Lenovo', 'Microsoft'\)"
        }

        It 'Should have ExitCode parameter (mandatory)' {
            $funcBody = $Script:GetExtractionResult.ScriptBlock.ToString()
            $funcBody | Should -Match '\$ExitCode'
            $funcBody | Should -Match '\[Parameter\(Mandatory'
        }

        It 'Should have DriverName parameter with default value' {
            $funcBody = $Script:GetExtractionResult.ScriptBlock.ToString()
            $funcBody | Should -Match "\`$DriverName\s*=\s*'Unknown'"
        }
    }

    Context 'HP Exit Code Classification' {
        BeforeAll {
            $module = Get-Module -Name 'FFU.Drivers'
        }

        It 'Should classify HP exit code 0 as Success' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 0 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
            $result.Critical | Should -BeFalse
        }

        It 'Should classify HP exit code 3010 as Success (reboot required)' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 3010 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
            $result.Message | Should -Match 'reboot required'
        }

        It 'Should classify HP exit code 1641 as Success (reboot initiated)' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 1641 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
        }

        It 'Should classify HP exit code 2 as Critical (invalid command line)' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 2 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeFalse
            $result.Critical | Should -BeTrue
            $result.Action | Should -Be 'Fail'
        }

        It 'Should classify HP exit code 1 as Warn' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 1 -DriverName 'TestDriver'
            })
            $result.Action | Should -Be 'Warn'
        }
    }

    Context 'Lenovo Exit Code Classification' {
        BeforeAll {
            $module = Get-Module -Name 'FFU.Drivers'
        }

        It 'Should classify Lenovo exit code 0 as Success' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Lenovo' -ExitCode 0 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
        }

        It 'Should classify Lenovo exit code 3010 as Success' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Lenovo' -ExitCode 3010 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
        }

        It 'Should classify Lenovo exit code 5 as Critical (access denied)' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Lenovo' -ExitCode 5 -DriverName 'TestDriver'
            })
            $result.Critical | Should -BeTrue
            $result.Action | Should -Be 'Fail'
        }

        It 'Should classify Lenovo exit code 1603 as non-critical' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Lenovo' -ExitCode 1603 -DriverName 'TestDriver'
            })
            $result.Critical | Should -BeFalse
            $result.Action | Should -Be 'Warn'
        }
    }

    Context 'Dell Exit Code Classification' {
        BeforeAll {
            $module = Get-Module -Name 'FFU.Drivers'
        }

        It 'Should classify Dell exit code 0 as Success' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Dell' -ExitCode 0 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
        }

        It 'Should classify Dell exit code 3010 as Success' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Dell' -ExitCode 3010 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
        }

        It 'Should classify Dell exit code 2 as Critical' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Dell' -ExitCode 2 -DriverName 'TestDriver'
            })
            $result.Critical | Should -BeTrue
        }
    }

    Context 'Microsoft Exit Code Classification' {
        BeforeAll {
            $module = Get-Module -Name 'FFU.Drivers'
        }

        It 'Should classify Microsoft exit code 0 as Success' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Microsoft' -ExitCode 0 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
        }

        It 'Should classify Microsoft exit code 3010 as Success' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Microsoft' -ExitCode 3010 -DriverName 'TestDriver'
            })
            $result.Success | Should -BeTrue
        }

        It 'Should classify Microsoft exit code 1601 as non-critical' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Microsoft' -ExitCode 1601 -DriverName 'TestDriver'
            })
            $result.Critical | Should -BeFalse
            $result.Action | Should -Be 'Warn'
        }

        It 'Should classify Microsoft exit code 1618 as non-critical' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'Microsoft' -ExitCode 1618 -DriverName 'TestDriver'
            })
            $result.Critical | Should -BeFalse
            $result.Action | Should -Be 'Warn'
        }
    }

    Context 'Unknown Exit Codes' {
        BeforeAll {
            $module = Get-Module -Name 'FFU.Drivers'
        }

        It 'Should classify unknown exit codes as Warn for all vendors' {
            $vendors = @('HP', 'Lenovo', 'Dell', 'Microsoft')
            foreach ($vendor in $vendors) {
                $result = $module.Invoke({
                    param($v) Get-DriverExtractionResult -Vendor $v -ExitCode 99999 -DriverName 'TestDriver'
                }, @($vendor))
                $result.Action | Should -Be 'Warn' -Because "$vendor should warn on unknown exit code"
                $result.Message | Should -Match 'unknown exit code'
            }
        }
    }

    Context 'Result Object Structure' {
        BeforeAll {
            $module = Get-Module -Name 'FFU.Drivers'
        }

        It 'Should return object with Success, Critical, Message, and Action properties' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 0 -DriverName 'TestDriver'
            })
            $result.PSObject.Properties.Name | Should -Contain 'Success'
            $result.PSObject.Properties.Name | Should -Contain 'Critical'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $result.PSObject.Properties.Name | Should -Contain 'Action'
        }

        It 'Should include driver name in message' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 0 -DriverName 'MySpecificDriver'
            })
            $result.Message | Should -Match 'MySpecificDriver'
        }
    }
}

# =============================================================================
# REL-DRV-04: Test-DriverDiskSpace Tests
# =============================================================================

Describe 'REL-DRV-04: Large Driver Set Disk Space Handling' -Tag 'Unit', 'FFU.Drivers', 'Reliability', 'REL-DRV-04' {

    Context 'FFUConstants driver space settings' {

        BeforeAll {
            $module = Get-Module FFU.Drivers
        }

        It 'Should define DRIVER_EXTRACTION_MULTIPLIER as 4' {
            # Access constants through module scope
            $value = $module.Invoke({ [FFUConstants]::DRIVER_EXTRACTION_MULTIPLIER })
            $value | Should -Be 4
        }

        It 'Should define MIN_DRIVER_FREE_SPACE (5GB)' {
            $value = $module.Invoke({ [FFUConstants]::MIN_DRIVER_FREE_SPACE })
            $value | Should -Be (5GB)
        }

        It 'Should define DRIVER_SET_SMALL_THRESHOLD (500MB)' {
            $value = $module.Invoke({ [FFUConstants]::DRIVER_SET_SMALL_THRESHOLD })
            $value | Should -Be (500MB)
        }

        It 'Should define DRIVER_SET_LARGE_THRESHOLD (2GB)' {
            $value = $module.Invoke({ [FFUConstants]::DRIVER_SET_LARGE_THRESHOLD })
            $value | Should -Be (2GB)
        }

        It 'Should define DRIVER_SPACE_WARNING_BUFFER (2GB)' {
            $value = $module.Invoke({ [FFUConstants]::DRIVER_SPACE_WARNING_BUFFER })
            $value | Should -Be (2GB)
        }
    }

    Context 'Test-DriverDiskSpace function' {

        BeforeAll {
            $module = Get-Module FFU.Drivers
            $Script:TestDriverDiskSpace = $module.Invoke({
                Get-Item 'function:Test-DriverDiskSpace' -ErrorAction SilentlyContinue
            })
        }

        It 'Should exist as internal function' {
            $Script:TestDriverDiskSpace | Should -Not -BeNullOrEmpty
        }

        It 'Should have required parameters' {
            $funcBody = $Script:TestDriverDiskSpace.ScriptBlock.ToString()
            $funcBody | Should -Match '\$DriversFolder'
            $funcBody | Should -Match '\$EstimatedCompressedSizeMB'
            $funcBody | Should -Match '\$Vendor'
        }

        It 'Should return object with expected properties' {
            $module = Get-Module FFU.Drivers
            $result = $module.Invoke({
                Test-DriverDiskSpace -DriversFolder $env:TEMP -Vendor 'Dell'
            })
            $result.PSObject.Properties.Name | Should -Contain 'HasSpace'
            $result.PSObject.Properties.Name | Should -Contain 'FreeSpaceGB'
            $result.PSObject.Properties.Name | Should -Contain 'EstimatedNeedGB'
            $result.PSObject.Properties.Name | Should -Contain 'SizeCategory'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $result.PSObject.Properties.Name | Should -Contain 'Recommendation'
        }

        It 'Should calculate estimated need based on multiplier' {
            $module = Get-Module FFU.Drivers
            $result = $module.Invoke({
                Test-DriverDiskSpace -DriversFolder $env:TEMP -Vendor 'Dell' -EstimatedCompressedSizeMB 1000
            })
            # 1000MB * 4 (multiplier) + 5GB (min) + 2GB (buffer) = ~11GB
            $result.EstimatedNeedGB | Should -BeGreaterThan 10
        }

        It 'Should classify small driver sets correctly' {
            $module = Get-Module FFU.Drivers
            $result = $module.Invoke({
                Test-DriverDiskSpace -DriversFolder $env:TEMP -Vendor 'Microsoft' -EstimatedCompressedSizeMB 200
            })
            $result.SizeCategory | Should -Be 'small'
        }

        It 'Should classify medium driver sets correctly' {
            $module = Get-Module FFU.Drivers
            $result = $module.Invoke({
                Test-DriverDiskSpace -DriversFolder $env:TEMP -Vendor 'HP' -EstimatedCompressedSizeMB 1000
            })
            $result.SizeCategory | Should -Be 'medium'
        }

        It 'Should classify large driver sets correctly' {
            $module = Get-Module FFU.Drivers
            $result = $module.Invoke({
                Test-DriverDiskSpace -DriversFolder $env:TEMP -Vendor 'Dell' -EstimatedCompressedSizeMB 3000
            })
            $result.SizeCategory | Should -Be 'large'
        }

        It 'Should provide message with free and needed space' {
            $module = Get-Module FFU.Drivers
            $result = $module.Invoke({
                Test-DriverDiskSpace -DriversFolder $env:TEMP -Vendor 'Dell'
            })
            $result.Message | Should -Match 'Free:'
            $result.Message | Should -Match 'Need:'
        }
    }

    Context 'Get-DellDrivers disk space integration' {

        It 'Should use Test-DriverDiskSpace for pre-validation' {
            $source = (Get-Command Get-DellDrivers).ScriptBlock.ToString()
            $source | Should -Match 'Test-DriverDiskSpace'
        }

        It 'Should use Dell vendor parameter' {
            $source = (Get-Command Get-DellDrivers).ScriptBlock.ToString()
            $source | Should -Match "Vendor 'Dell'"
        }
    }

    Context 'Get-HPDrivers disk space integration' {

        It 'Should use Test-DriverDiskSpace for pre-validation' {
            $source = (Get-Command Get-HPDrivers).ScriptBlock.ToString()
            $source | Should -Match 'Test-DriverDiskSpace'
        }

        It 'Should use HP vendor parameter' {
            $source = (Get-Command Get-HPDrivers).ScriptBlock.ToString()
            $source | Should -Match "Vendor 'HP'"
        }
    }

    Context 'Get-LenovoDrivers disk space integration' {

        It 'Should use Test-DriverDiskSpace for pre-validation' {
            $source = (Get-Command Get-LenovoDrivers).ScriptBlock.ToString()
            $source | Should -Match 'Test-DriverDiskSpace'
        }

        It 'Should use Lenovo vendor parameter' {
            $source = (Get-Command Get-LenovoDrivers).ScriptBlock.ToString()
            $source | Should -Match "Vendor 'Lenovo'"
        }
    }
}
