#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for -Priority parameter in download functions

.DESCRIPTION
    Tests covering:
    - Start-ResilientDownload accepts -Priority parameter
    - Invoke-BITSDownload accepts -Priority parameter
    - Priority value is passed through the download chain

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Common.Download.Priority.Tests.ps1 -Output Detailed
    Bug Fix: bits-priority-parameter-download-failure
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

    # Import FFU.Common which contains download functions
    if (-not (Test-Path "$CommonModulePath\FFU.Common.psd1")) {
        throw "FFU.Common module not found at: $CommonModulePath"
    }
    Import-Module "$CommonModulePath\FFU.Common.psd1" -Force -ErrorAction Stop

    # Set up a temporary log path for testing
    $script:testLogPath = Join-Path $env:TEMP "FFU.Common.Download.Priority.Tests.log"
    Set-CommonCoreLogPath -Path $script:testLogPath -Initialize
}

AfterAll {
    # Cleanup test log
    if (Test-Path $script:testLogPath) {
        Remove-Item -Path $script:testLogPath -Force -ErrorAction SilentlyContinue
    }

    Get-Module -Name 'FFU.Common', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Start-ResilientDownload Priority Parameter Tests
# =============================================================================

Describe 'Start-ResilientDownload' -Tag 'Unit', 'FFU.Common', 'Download', 'Priority' {

    Context 'Priority Parameter' {
        It 'Should have Priority parameter' {
            $cmd = Get-Command -Name 'Start-ResilientDownload' -Module 'FFU.Common.Download'
            $cmd.Parameters.ContainsKey('Priority') | Should -Be $true
        }

        It 'Should have ValidateSet for Priority (Foreground, High, Normal, Low)' {
            $cmd = Get-Command -Name 'Start-ResilientDownload' -Module 'FFU.Common.Download'
            $priorityParam = $cmd.Parameters['Priority']

            $validateSet = $priorityParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Foreground'
            $validateSet.ValidValues | Should -Contain 'High'
            $validateSet.ValidValues | Should -Contain 'Normal'
            $validateSet.ValidValues | Should -Contain 'Low'
        }

        It 'Should have Priority parameter default to Normal' {
            $cmd = Get-Command -Name 'Start-ResilientDownload' -Module 'FFU.Common.Download'
            $priorityParam = $cmd.Parameters['Priority']

            # Check if there's a default value in the parameter definition
            # We need to check the AST for the default value
            $modulePath = Join-Path $CommonModulePath 'FFU.Common.Download.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw

            # Should find: [string]$Priority = 'Normal'
            $moduleContent | Should -Match "\[string\]\`$Priority\s*=\s*'Normal'"
        }

        It 'Should be optional (not mandatory)' {
            $cmd = Get-Command -Name 'Start-ResilientDownload' -Module 'FFU.Common.Download'
            $priorityParam = $cmd.Parameters['Priority']

            $priorityParam.Attributes.Mandatory | Should -Not -Contain $true
        }
    }
}

# =============================================================================
# Invoke-BITSDownload Priority Parameter Tests
# =============================================================================

Describe 'Invoke-BITSDownload' -Tag 'Unit', 'FFU.Common', 'Download', 'Priority' {

    Context 'Priority Parameter' {
        It 'Should have Priority parameter' {
            $cmd = Get-Command -Name 'Invoke-BITSDownload' -Module 'FFU.Common.Download'
            $cmd.Parameters.ContainsKey('Priority') | Should -Be $true
        }

        It 'Should have ValidateSet for Priority (Foreground, High, Normal, Low)' {
            $cmd = Get-Command -Name 'Invoke-BITSDownload' -Module 'FFU.Common.Download'
            $priorityParam = $cmd.Parameters['Priority']

            $validateSet = $priorityParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Foreground'
            $validateSet.ValidValues | Should -Contain 'High'
            $validateSet.ValidValues | Should -Contain 'Normal'
            $validateSet.ValidValues | Should -Contain 'Low'
        }

        It 'Should have Priority parameter default to Normal' {
            $cmd = Get-Command -Name 'Invoke-BITSDownload' -Module 'FFU.Common.Download'
            $priorityParam = $cmd.Parameters['Priority']

            # Check the AST for the default value
            $modulePath = Join-Path $CommonModulePath 'FFU.Common.Download.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw

            # Should find: [string]$Priority = 'Normal' in Invoke-BITSDownload function
            $moduleContent | Should -Match "function Invoke-BITSDownload[\s\S]{1,500}\[string\]\`$Priority\s*=\s*'Normal'"
        }
    }

    Context 'Priority Usage in BITS Transfer' {
        It 'Should use Priority parameter instead of hardcoded Normal' {
            $modulePath = Join-Path $CommonModulePath 'FFU.Common.Download.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw

            # Should find: Priority = $Priority (not Priority = 'Normal')
            $moduleContent | Should -Match "Priority\s*=\s*\`$Priority"

            # Should NOT have hardcoded Priority = 'Normal' in $bitsParams
            # This regex looks for the $bitsParams hashtable and ensures Priority is not hardcoded
            $moduleContent | Should -Not -Match "\`$bitsParams\s*=\s*@\{[\s\S]{1,200}Priority\s*=\s*'Normal'"
        }
    }
}

# =============================================================================
# Priority Pass-Through Chain Tests
# =============================================================================

Describe 'Download Priority Pass-Through' -Tag 'Unit', 'FFU.Common', 'Download', 'Priority', 'Integration' {

    Context 'Start-ResilientDownload to Invoke-BITSDownload' {
        It 'Should pass Priority parameter to Invoke-BITSDownload' {
            $modulePath = Join-Path $CommonModulePath 'FFU.Common.Download.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw

            # Find the call to Invoke-BITSDownload within Start-ResilientDownload
            # Should include -Priority $Priority
            $moduleContent | Should -Match "Invoke-BITSDownload[\s\S]{1,300}-Priority\s+\`$Priority"
        }
    }

    Context 'Start-BitsTransferWithRetry to Start-ResilientDownload' {
        It 'Should pass Priority parameter from Start-BitsTransferWithRetry to Start-ResilientDownload' {
            $modulePath = Join-Path $CommonModulePath 'FFU.Common.Core.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw

            # Find the call to Start-ResilientDownload within Start-BitsTransferWithRetry
            # Should include 'Priority' key in the splatting hashtable
            $moduleContent | Should -Match "Start-ResilientDownload\s+@downloadParams"
            $moduleContent | Should -Match "downloadParams\['Priority'\]\s*=\s*\`$Priority"
        }
    }
}
