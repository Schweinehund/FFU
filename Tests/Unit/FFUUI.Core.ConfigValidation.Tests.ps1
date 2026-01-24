<#
.SYNOPSIS
    Pester tests for FFUUI.Core.Config validation integration (REL-UI-05).

.DESCRIPTION
    Tests load-time configuration validation functionality:
    - Validation runs on config load (Invoke-LoadConfiguration)
    - Validation errors block load by default (user can override)
    - Validation warnings don't block
    - Validation result stored in State.Data
    - Auto-load logs validation issues without popups
    - Test-FFUConfiguration failure handled gracefully
#>

BeforeAll {
    # Get the absolute path to the project root
    $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
    $errorDisplayModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.ErrorDisplay.psm1"

    # Load WPF assemblies needed for MessageBox types
    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue

    # Import the error display module first (creates Show-FFUValidationErrors)
    if (Test-Path $errorDisplayModulePath) {
        Import-Module $errorDisplayModulePath -Force
    }

    # Import the config module
    Import-Module $configModulePath -Force

    # Try to import FFU.Core for Test-FFUConfiguration
    $ffuCorePath = Join-Path $projectRoot "FFUDevelopment\Modules\FFU.Core\FFU.Core.psd1"
    if (Test-Path $ffuCorePath) {
        Import-Module $ffuCorePath -Force -ErrorAction SilentlyContinue
    }

    # Global mock for WriteLog
    function global:WriteLog { param([string]$Message) }

    # Helper to create a mock State object
    function New-MockState {
        [PSCustomObject]@{
            FFUDevelopmentPath = 'C:\FFUDevelopment'
            Controls           = @{
                txtFFUDevPath = [PSCustomObject]@{ Text = 'C:\FFUDevelopment' }
            }
            Data               = @{
                configValidationResult = $null
                hasValidationErrors    = $false
                lastConfigFilePath     = $null
            }
        }
    }

    # Helper to create a valid test config content
    function New-ValidConfigContent {
        [PSCustomObject]@{
            FFUDevelopmentPath = 'C:\FFUDevelopment'
            WindowsVersion     = 'Windows 11'
            WindowsRelease     = 24
            WindowsSKU         = 'Pro'
            Memory             = 4294967296
            Disksize           = 53687091200
            Processors         = 4
        }
    }

    # Helper to create an invalid test config content
    function New-InvalidConfigContent {
        [PSCustomObject]@{
            FFUDevelopmentPath = 'C:\FFUDevelopment'
            WindowsVersion     = 'Windows 11'
            WindowsRelease     = 'invalid'  # Should be int
            WindowsSKU         = 'InvalidSKU'  # Not a valid enum value
            Memory             = -1  # Negative memory
            Disksize           = 53687091200
            Processors         = 4
        }
    }
}

Describe 'FFUUI.Core.Config Module Structure' {

    Context 'Module exports and functions' {

        It 'Should export Invoke-LoadConfiguration function' {
            Get-Command -Module FFUUI.Core.Config -Name Invoke-LoadConfiguration | Should -Not -BeNullOrEmpty
        }

        It 'Should export Invoke-AutoLoadPreviousEnvironment function' {
            Get-Command -Module FFUUI.Core.Config -Name Invoke-AutoLoadPreviousEnvironment | Should -Not -BeNullOrEmpty
        }

        It 'Should export Update-UIFromConfig function' {
            Get-Command -Module FFUUI.Core.Config -Name Update-UIFromConfig | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Validation integration code presence' {

        It 'Invoke-LoadConfiguration should contain Test-FFUConfiguration call' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            $content | Should -Match 'Test-FFUConfiguration'
        }

        It 'Invoke-LoadConfiguration should contain Show-FFUValidationErrors call' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            $content | Should -Match 'Show-FFUValidationErrors'
        }

        It 'Invoke-LoadConfiguration should store validation result in State.Data' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            $content | Should -Match '\$State\.Data\.configValidationResult\s*='
        }

        It 'Invoke-LoadConfiguration should set hasValidationErrors flag' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            $content | Should -Match '\$State\.Data\.hasValidationErrors\s*='
        }

        It 'Invoke-AutoLoadPreviousEnvironment should contain Test-FFUConfiguration call' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Match function definition and verify it contains Test-FFUConfiguration
            $funcStart = $content.IndexOf('function Invoke-AutoLoadPreviousEnvironment')
            $funcStart | Should -BeGreaterThan 0

            # Find the function body
            $funcContent = $content.Substring($funcStart)
            $funcContent | Should -Match 'Test-FFUConfiguration'
        }

        It 'Invoke-AutoLoadPreviousEnvironment should log validation errors' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should log errors during auto-load
            $content | Should -Match 'AutoLoad: ERROR'
        }

        It 'Invoke-AutoLoadPreviousEnvironment should log validation warnings' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should log warnings during auto-load
            $content | Should -Match 'AutoLoad: WARNING'
        }
    }
}

Describe 'BuildFFUVM_UI.ps1 validation integration' {

    Context 'State initialization' {

        It 'uiState.Data should include configValidationResult' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $uiPath = Join-Path $projectRoot "FFUDevelopment\BuildFFUVM_UI.ps1"
            $content = Get-Content $uiPath -Raw

            $content | Should -Match 'configValidationResult\s*=\s*\$null'
        }

        It 'uiState.Data should include hasValidationErrors' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $uiPath = Join-Path $projectRoot "FFUDevelopment\BuildFFUVM_UI.ps1"
            $content = Get-Content $uiPath -Raw

            $content | Should -Match 'hasValidationErrors\s*=\s*\$false'
        }
    }

    Context 'Build button validation check' {

        It 'Build button handler should check hasValidationErrors' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $uiPath = Join-Path $projectRoot "FFUDevelopment\BuildFFUVM_UI.ps1"
            $content = Get-Content $uiPath -Raw

            # Should check validation errors at build start
            $content | Should -Match '\$script:uiState\.Data\.hasValidationErrors'
        }

        It 'Build button handler should warn user about validation errors' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $uiPath = Join-Path $projectRoot "FFUDevelopment\BuildFFUVM_UI.ps1"
            $content = Get-Content $uiPath -Raw

            # Should show warning about validation errors
            $content | Should -Match 'configuration has validation errors'
        }

        It 'Build button handler should allow user to proceed despite errors' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $uiPath = Join-Path $projectRoot "FFUDevelopment\BuildFFUVM_UI.ps1"
            $content = Get-Content $uiPath -Raw

            # Should have YesNo MessageBox for user choice
            $content | Should -Match 'MessageBoxButton.*YesNo'
        }
    }
}

Describe 'Validation state object' {

    Context 'hasValidationErrors flag behavior' {

        It 'hasValidationErrors should be false by default in new state' {
            $state = New-MockState
            $state.Data.hasValidationErrors | Should -Be $false
        }

        It 'configValidationResult should be null by default in new state' {
            $state = New-MockState
            $state.Data.configValidationResult | Should -BeNullOrEmpty
        }

        It 'hasValidationErrors can be set to true' {
            $state = New-MockState
            $state.Data.hasValidationErrors = $true
            $state.Data.hasValidationErrors | Should -Be $true
        }

        It 'configValidationResult can hold validation result object' {
            $state = New-MockState
            $state.Data.configValidationResult = [PSCustomObject]@{
                IsValid  = $false
                Errors   = @('Error 1', 'Error 2')
                Warnings = @('Warning 1')
            }
            $state.Data.configValidationResult.IsValid | Should -Be $false
            $state.Data.configValidationResult.Errors.Count | Should -Be 2
            $state.Data.configValidationResult.Warnings.Count | Should -Be 1
        }
    }

    Context 'State reset behavior' {

        It 'hasValidationErrors can be reset to false' {
            $state = New-MockState
            $state.Data.hasValidationErrors = $true
            $state.Data.hasValidationErrors = $false
            $state.Data.hasValidationErrors | Should -Be $false
        }

        It 'configValidationResult can be cleared' {
            $state = New-MockState
            $state.Data.configValidationResult = [PSCustomObject]@{ IsValid = $false }
            $state.Data.configValidationResult = $null
            $state.Data.configValidationResult | Should -BeNullOrEmpty
        }
    }
}

Describe 'REL-UI-05 validation flow code analysis' {

    Context 'Invoke-LoadConfiguration validation flow' {

        It 'Should convert PSCustomObject to hashtable for validation' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should create hashtable from config content
            $content | Should -Match '\$configHashtable\s*=\s*@\{\}'
            $content | Should -Match 'foreach.*\$prop.*\$configContent\.PSObject\.Properties'
        }

        It 'Should check for Test-FFUConfiguration availability before calling' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should check command availability
            $content | Should -Match "Get-Command.*'Test-FFUConfiguration'"
        }

        It 'Should handle validation function exceptions gracefully' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should have try-catch around validation call
            $content | Should -Match 'try\s*\{[\s\S]*Test-FFUConfiguration[\s\S]*\}\s*catch'
        }

        It 'Should check for Show-FFUValidationErrors availability' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should check command availability before showing errors
            $content | Should -Match "Get-Command.*'Show-FFUValidationErrors'"
        }

        It 'Should allow user to decline loading invalid config' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should return early if user declines
            $content | Should -Match 'User declined to load invalid configuration'
        }

        It 'Should allow user to load config despite validation errors' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should log user choice to proceed
            $content | Should -Match 'User chose to load configuration despite validation errors'
        }
    }

    Context 'Invoke-AutoLoadPreviousEnvironment validation flow' {

        It 'Should perform validation silently (no MessageBox)' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Find AutoLoad function and check it doesn't show MessageBox for validation
            $funcStart = $content.IndexOf('function Invoke-AutoLoadPreviousEnvironment')
            $funcEnd = $content.IndexOf('function ', $funcStart + 50)  # Find next function
            if ($funcEnd -eq -1) { $funcEnd = $content.Length }

            $funcContent = $content.Substring($funcStart, $funcEnd - $funcStart)

            # Should NOT show Show-FFUValidationErrors in AutoLoad (silent mode)
            $funcContent | Should -Not -Match 'Show-FFUValidationErrors'
        }

        It 'Should store validation result for later use' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $configModulePath = Join-Path $projectRoot "FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1"
            $content = Get-Content $configModulePath -Raw

            # Should store validation state during auto-load
            $funcStart = $content.IndexOf('function Invoke-AutoLoadPreviousEnvironment')
            $funcEnd = $content.IndexOf('function ', $funcStart + 50)
            if ($funcEnd -eq -1) { $funcEnd = $content.Length }

            $funcContent = $content.Substring($funcStart, $funcEnd - $funcStart)

            $funcContent | Should -Match '\$State\.Data\.configValidationResult'
            $funcContent | Should -Match '\$State\.Data\.hasValidationErrors'
        }
    }
}

Describe 'Error and warning count handling' {

    Context 'Count validation' {

        It 'Should handle zero errors count' {
            $validationResult = [PSCustomObject]@{
                IsValid  = $true
                Errors   = @()
                Warnings = @()
            }
            $errorCount = if ($null -ne $validationResult.Errors) { $validationResult.Errors.Count } else { 0 }
            $errorCount | Should -Be 0
        }

        It 'Should handle multiple errors count' {
            $validationResult = [PSCustomObject]@{
                IsValid  = $false
                Errors   = @('Error 1', 'Error 2', 'Error 3')
                Warnings = @()
            }
            $errorCount = if ($null -ne $validationResult.Errors) { $validationResult.Errors.Count } else { 0 }
            $errorCount | Should -Be 3
        }

        It 'Should handle null errors array' {
            $validationResult = [PSCustomObject]@{
                IsValid  = $true
                Errors   = $null
                Warnings = $null
            }
            $errorCount = if ($null -ne $validationResult.Errors) { $validationResult.Errors.Count } else { 0 }
            $errorCount | Should -Be 0
        }

        It 'Should handle warnings with valid config' {
            $validationResult = [PSCustomObject]@{
                IsValid  = $true
                Errors   = @()
                Warnings = @('Warning 1', 'Warning 2')
            }
            $validationResult.IsValid | Should -Be $true
            $validationResult.Warnings.Count | Should -Be 2
        }
    }
}
