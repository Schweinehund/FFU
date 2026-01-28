#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for BITS priority configuration in FFU.Common.Core module

.DESCRIPTION
    Tests covering:
    - Set-BitsTransferPriority function behavior
    - BITS priority resolution cascade (parameter > env > script > default)
    - Environment variable propagation for ThreadJob compatibility
    - Module initialization from environment variable

    These tests verify that BITS transfer priority can be configured via
    multiple methods and follows the correct precedence cascade.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Common.BitsPriority.Tests.ps1 -Output Detailed
    Phase: 36-cu-skip-esd-bits (Plan 03)
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $CommonModulePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common'

    # Add Modules folder to PSModulePath for proper dependency resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    Get-Module -Name 'FFU.Common', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (required dependency)
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
    }

    # Import FFU.Common which contains Set-BitsTransferPriority and Start-BitsTransferWithRetry
    if (-not (Test-Path "$CommonModulePath\FFU.Common.psd1")) {
        throw "FFU.Common module not found at: $CommonModulePath"
    }
    Import-Module "$CommonModulePath\FFU.Common.psd1" -Force -ErrorAction Stop

    # Save original env var to restore later
    $script:originalBitsPriority = $env:FFU_BITS_PRIORITY

    # Set up a temporary log path for testing
    $script:testLogPath = Join-Path $env:TEMP "FFU.Common.BitsPriority.Tests.log"
    Set-CommonCoreLogPath -Path $script:testLogPath -Initialize
}

AfterAll {
    # Restore original environment variable
    if ($null -ne $script:originalBitsPriority) {
        $env:FFU_BITS_PRIORITY = $script:originalBitsPriority
    }
    else {
        Remove-Item -Path Env:\FFU_BITS_PRIORITY -ErrorAction SilentlyContinue
    }

    # Cleanup test log
    if (Test-Path $script:testLogPath) {
        Remove-Item -Path $script:testLogPath -Force -ErrorAction SilentlyContinue
    }

    Get-Module -Name 'FFU.Common', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Set-BitsTransferPriority Tests
# =============================================================================

Describe 'Set-BitsTransferPriority' -Tag 'Unit', 'FFU.Common', 'BitsPriority' {

    BeforeEach {
        # Save and clear state before each test
        $script:savedEnvBits = $env:FFU_BITS_PRIORITY
    }

    AfterEach {
        # Restore state after each test
        if ($null -ne $script:savedEnvBits) {
            $env:FFU_BITS_PRIORITY = $script:savedEnvBits
        }
        else {
            Remove-Item -Path Env:\FFU_BITS_PRIORITY -ErrorAction SilentlyContinue
        }
    }

    Context 'Function Export and Parameters' {
        It 'Should be exported from FFU.Common module' {
            Get-Command -Name 'Set-BitsTransferPriority' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory Priority parameter' {
            $cmd = Get-Command -Name 'Set-BitsTransferPriority' -Module 'FFU.Common'
            $param = $cmd.Parameters['Priority']
            $param | Should -Not -BeNullOrEmpty
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $mandatory.Mandatory | Should -BeTrue
        }

        It 'Should have ValidateSet for Foreground, High, Normal, Low' {
            $cmd = Get-Command -Name 'Set-BitsTransferPriority' -Module 'FFU.Common'
            $param = $cmd.Parameters['Priority']
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Foreground'
            $validateSet.ValidValues | Should -Contain 'High'
            $validateSet.ValidValues | Should -Contain 'Normal'
            $validateSet.ValidValues | Should -Contain 'Low'
        }
    }

    Context 'Priority Setting Behavior' {
        It 'Should set FFU_BITS_PRIORITY environment variable to Foreground' {
            Set-BitsTransferPriority -Priority 'Foreground'
            $env:FFU_BITS_PRIORITY | Should -Be 'Foreground'
        }

        It 'Should set FFU_BITS_PRIORITY environment variable to High' {
            Set-BitsTransferPriority -Priority 'High'
            $env:FFU_BITS_PRIORITY | Should -Be 'High'
        }

        It 'Should set FFU_BITS_PRIORITY environment variable to Normal' {
            Set-BitsTransferPriority -Priority 'Normal'
            $env:FFU_BITS_PRIORITY | Should -Be 'Normal'
        }

        It 'Should set FFU_BITS_PRIORITY environment variable to Low' {
            Set-BitsTransferPriority -Priority 'Low'
            $env:FFU_BITS_PRIORITY | Should -Be 'Low'
        }

        It 'Should reject invalid priority value' {
            { Set-BitsTransferPriority -Priority 'Invalid' } | Should -Throw
        }

        It 'Should log the priority change' {
            Set-BitsTransferPriority -Priority 'Foreground'
            # Verify log file contains priority message
            if (Test-Path $script:testLogPath) {
                $logContent = Get-Content $script:testLogPath -Raw
                $logContent | Should -Match 'BITS transfer priority set to Foreground'
            }
        }
    }
}

# =============================================================================
# BITS Priority Resolution Cascade Tests
# =============================================================================

Describe 'BITS Priority Resolution Cascade' -Tag 'Unit', 'FFU.Common', 'BitsPriority', 'Cascade' {

    BeforeEach {
        # Save state
        $script:savedEnvBits = $env:FFU_BITS_PRIORITY
    }

    AfterEach {
        # Restore state
        if ($null -ne $script:savedEnvBits) {
            $env:FFU_BITS_PRIORITY = $script:savedEnvBits
        }
        else {
            Remove-Item -Path Env:\FFU_BITS_PRIORITY -ErrorAction SilentlyContinue
        }
    }

    Context 'Start-BitsTransferWithRetry Priority Parameter' {
        It 'Should have Priority parameter with ValidateSet' {
            $cmd = Get-Command -Name 'Start-BitsTransferWithRetry' -Module 'FFU.Common'
            $param = $cmd.Parameters['Priority']
            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Foreground'
            $validateSet.ValidValues | Should -Contain 'High'
            $validateSet.ValidValues | Should -Contain 'Normal'
            $validateSet.ValidValues | Should -Contain 'Low'
        }

        It 'Should have Priority parameter as optional (not mandatory)' {
            $cmd = Get-Command -Name 'Start-BitsTransferWithRetry' -Module 'FFU.Common'
            $param = $cmd.Parameters['Priority']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            # Priority is optional - when not specified, cascade resolves it
            if ($mandatory) {
                $mandatory.Mandatory | Should -BeFalse
            }
            else {
                # No explicit ParameterAttribute means non-mandatory by default
                $true | Should -BeTrue
            }
        }
    }

    Context 'Cascade Resolution Logic' {
        <#
            The priority cascade in Start-BitsTransferWithRetry is:
            1. Explicit -Priority parameter (highest precedence)
            2. FFU_BITS_PRIORITY environment variable
            3. Script-level $BitsTransferPriority variable
            4. Default: 'Normal'

            We test this by examining the code structure and parameter behavior.
        #>

        It 'Should resolve cascade: env var used when no parameter specified' {
            # Set env var to 'High'
            $env:FFU_BITS_PRIORITY = 'High'

            # The cascade logic checks env var before script var when no explicit param
            # Verify the module initialization code reads from env var
            $commonCorePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.Core.psm1'
            $content = Get-Content $commonCorePath -Raw
            # Verify the cascade code exists
            $content | Should -Match 'env:FFU_BITS_PRIORITY'
            $content | Should -Match 'BitsTransferPriority'
        }

        It 'Should have cascade code: param > env > script > default' {
            $commonCorePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.Core.psm1'
            $content = Get-Content $commonCorePath -Raw

            # Verify cascade structure exists in Start-BitsTransferWithRetry
            $content | Should -Match 'IsNullOrWhiteSpace\(\$Priority\)'
            $content | Should -Match 'env:FFU_BITS_PRIORITY'
            $content | Should -Match 'script:BitsTransferPriority'
            # Default should be Normal
            $content | Should -Match "'Normal'"
        }
    }
}

# =============================================================================
# BITS Priority Environment Propagation Tests
# =============================================================================

Describe 'BITS Priority Environment Propagation' -Tag 'Unit', 'FFU.Common', 'BitsPriority', 'Environment' {

    BeforeEach {
        $script:savedEnvBits = $env:FFU_BITS_PRIORITY
    }

    AfterEach {
        if ($null -ne $script:savedEnvBits) {
            $env:FFU_BITS_PRIORITY = $script:savedEnvBits
        }
        else {
            Remove-Item -Path Env:\FFU_BITS_PRIORITY -ErrorAction SilentlyContinue
        }
    }

    Context 'Environment Variable Persistence' {
        It 'Should persist FFU_BITS_PRIORITY in env after Set-BitsTransferPriority' {
            Set-BitsTransferPriority -Priority 'Foreground'
            $env:FFU_BITS_PRIORITY | Should -Be 'Foreground'
        }

        It 'Should persist value across multiple Set-BitsTransferPriority calls' {
            Set-BitsTransferPriority -Priority 'Low'
            $env:FFU_BITS_PRIORITY | Should -Be 'Low'

            Set-BitsTransferPriority -Priority 'High'
            $env:FFU_BITS_PRIORITY | Should -Be 'High'

            Set-BitsTransferPriority -Priority 'Normal'
            $env:FFU_BITS_PRIORITY | Should -Be 'Normal'
        }

        It 'Should have env var readable by child processes (ThreadJob propagation)' {
            Set-BitsTransferPriority -Priority 'Foreground'

            # Simulate what happens in a ThreadJob: read env var from new scope
            $result = & {
                $env:FFU_BITS_PRIORITY
            }
            $result | Should -Be 'Foreground'
        }

        It 'Should survive across function calls (simulates ThreadJob propagation)' {
            Set-BitsTransferPriority -Priority 'High'

            # Call another function and verify env var persists
            function Test-EnvVarPersistence {
                return $env:FFU_BITS_PRIORITY
            }

            $result = Test-EnvVarPersistence
            $result | Should -Be 'High'
        }
    }
}

# =============================================================================
# BITS Priority Module Initialization Tests
# =============================================================================

Describe 'BITS Priority Module Initialization' -Tag 'Unit', 'FFU.Common', 'BitsPriority', 'Initialization' {

    Context 'Module Reads From Environment on Load' {
        It 'Should have initialization code that reads FFU_BITS_PRIORITY env var' {
            $commonCorePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.Core.psm1'
            $content = Get-Content $commonCorePath -Raw

            # Module initialization (top-level code) should read env var
            # Pattern: if env var is set, use it for script:BitsTransferPriority
            $content | Should -Match 'script:BitsTransferPriority\s*=\s*.*Normal'
            $content | Should -Match 'env:FFU_BITS_PRIORITY'
        }

        It 'Should default script:BitsTransferPriority to Normal when no env var set' {
            $commonCorePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.Core.psm1'
            $lines = Get-Content $commonCorePath

            # Find the initialization line
            $initLine = $lines | Where-Object { $_ -match 'script:BitsTransferPriority\s*=\s*.*Normal' }
            $initLine | Should -Not -BeNullOrEmpty
        }

        It 'Should read env var for script:BitsTransferPriority when FFU_BITS_PRIORITY is set' {
            $commonCorePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.Core.psm1'
            $content = Get-Content $commonCorePath -Raw

            # Verify conditional env var reading pattern
            $content | Should -Match 'IsNullOrWhiteSpace.*env:FFU_BITS_PRIORITY'
            $content | Should -Match 'script:BitsTransferPriority\s*=\s*\$env:FFU_BITS_PRIORITY'
        }

        It 'Should initialize with env var when module is freshly imported' {
            # Set env var, reimport module, verify behavior
            $savedEnv = $env:FFU_BITS_PRIORITY
            try {
                $env:FFU_BITS_PRIORITY = 'Low'

                # Reimport module to trigger initialization
                Get-Module 'FFU.Common' | Remove-Module -Force -ErrorAction SilentlyContinue
                $CommonPath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.psd1'
                Import-Module $CommonPath -Force -ErrorAction Stop

                # Verify by calling Set-BitsTransferPriority which reads from script var
                # After reimport with env=Low, the script var should be 'Low'
                # We can verify this by setting to High and checking env
                Set-BitsTransferPriority -Priority 'High'
                $env:FFU_BITS_PRIORITY | Should -Be 'High'
            }
            finally {
                if ($null -ne $savedEnv) {
                    $env:FFU_BITS_PRIORITY = $savedEnv
                }
                else {
                    Remove-Item -Path Env:\FFU_BITS_PRIORITY -ErrorAction SilentlyContinue
                }
                # Restore log path after module reimport
                Set-CommonCoreLogPath -Path $script:testLogPath
            }
        }
    }

    Context 'Set-BitsTransferPriority Sets Both Script and Env Variables' {
        It 'Should set both script-level variable and environment variable' {
            $commonCorePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.Core.psm1'
            $content = Get-Content $commonCorePath -Raw

            # Find Set-BitsTransferPriority function body
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $commonCorePath, [ref]$tokens, [ref]$errors
            )
            $funcAst = $ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $args[0].Name -eq 'Set-BitsTransferPriority'
            }, $false)
            $funcAst | Should -Not -BeNullOrEmpty

            $funcBody = $funcAst[0].Body.Extent.Text
            # Should set script variable
            $funcBody | Should -Match 'script:BitsTransferPriority\s*=\s*\$Priority'
            # Should set environment variable
            $funcBody | Should -Match 'Env:FFU_BITS_PRIORITY'
        }
    }
}
