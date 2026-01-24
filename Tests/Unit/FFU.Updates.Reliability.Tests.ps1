#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Updates reliability features (REL-UPD-*)

.DESCRIPTION
    Tests for reliability improvements in FFU.Updates module:
    - REL-UPD-01: Catalog Query Retry (Invoke-CatalogQueryWithRetry)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Updates.Reliability.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Updates'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'

    # Add Modules folder to PSModulePath for proper dependency resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    Get-Module -Name 'FFU.Updates', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (required dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
    }

    if (-not (Test-Path "$ModulePath\FFU.Updates.psd1")) {
        throw "FFU.Updates module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Updates.psd1" -Force -ErrorAction Stop

    # Get the module object for accessing private functions
    $script:UpdatesModule = Get-Module -Name 'FFU.Updates'
}

AfterAll {
    Get-Module -Name 'FFU.Updates', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# REL-UPD-01: Catalog Query Retry Tests
# =============================================================================

Describe 'REL-UPD-01: Catalog Query Retry' -Tag 'Unit', 'FFU.Updates', 'Reliability', 'REL-UPD-01' {

    Context 'Invoke-CatalogQueryWithRetry function' {

        It 'Should be defined in the module (internal function)' {
            # Read the module file directly to check for internal function
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match 'function Invoke-CatalogQueryWithRetry'
        }

        It 'Should have correct parameters defined' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for required parameters (using [\s\S] to match across lines)
            $moduleContent | Should -Match '\[Parameter\(Mandatory\)\][\s\S]*?\[scriptblock\]\$Query'
            $moduleContent | Should -Match '\[string\]\$OperationName'
            $moduleContent | Should -Match '\[int\]\$MaxRetries'
            $moduleContent | Should -Match '\[int\]\$BaseDelaySeconds'
        }

        It 'Should implement exponential backoff with jitter' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for exponential backoff calculation
            $moduleContent | Should -Match '\[math\]::Pow\(2, \$attempt - 1\)'

            # Check for jitter
            $moduleContent | Should -Match 'Get-Random -Minimum 0 -Maximum 3'
        }

        It 'Should use ThreadJob-safe logging pattern' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for $function:WriteLog pattern within Invoke-CatalogQueryWithRetry
            $functionMatch = [regex]::Match($moduleContent, 'function Invoke-CatalogQueryWithRetry[\s\S]*?(?=\r?\nfunction )')
            if ($functionMatch.Success) {
                $functionContent = $functionMatch.Value
                $functionContent | Should -Match '\$function:WriteLog'
            } else {
                # If it's the last function, match to end of module
                $moduleContent | Should -Match 'Invoke-CatalogQueryWithRetry[\s\S]*\$function:WriteLog'
            }
        }

        It 'Should log warning messages with attempt count' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for attempt count in warning message
            $moduleContent | Should -Match 'attempt \$attempt of \$MaxRetries'
        }

        It 'Should throw after MaxRetries exhausted' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for throw at the end
            $moduleContent | Should -Match 'throw \$lastError'
        }

        It 'Should log error when all retries exhausted' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for error message about exhausted retries
            $moduleContent | Should -Match 'failed after \$MaxRetries attempts'
        }

        It 'Should have default MaxRetries of 3' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            $moduleContent | Should -Match '\[int\]\$MaxRetries = 3'
        }

        It 'Should have default BaseDelaySeconds of 10' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            $moduleContent | Should -Match '\[int\]\$BaseDelaySeconds = 10'
        }
    }

    Context 'Get-ProductsCab retry integration' {

        It 'Should use Invoke-CatalogQueryWithRetry for catalog search' {
            # Verify the function uses the retry wrapper for the main search request
            $source = (Get-Command Get-ProductsCab -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match 'Invoke-CatalogQueryWithRetry'
            $source | Should -Match "OperationName.*'Windows Update catalog search'"
        }

        It 'Should use Invoke-CatalogQueryWithRetry for metadata lookup' {
            $source = (Get-Command Get-ProductsCab -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match "OperationName.*'Update metadata lookup'"
        }

        It 'Should use reduced retries for metadata lookup (non-critical)' {
            $source = (Get-Command Get-ProductsCab -Module 'FFU.Updates').ScriptBlock.ToString()
            # Metadata lookup should have MaxRetries 2 (less than default 3)
            $source | Should -Match 'MaxRetries 2.*Update metadata lookup|Update metadata lookup.*MaxRetries 2'
        }

        It 'Should have REL-UPD-01 comment marker' {
            $source = (Get-Command Get-ProductsCab -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match 'REL-UPD-01'
        }
    }

    Context 'Documentation' {

        It 'Should have synopsis in function documentation' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Find the function and check for .SYNOPSIS
            $moduleContent | Should -Match 'function Invoke-CatalogQueryWithRetry[\s\S]*?\.SYNOPSIS'
        }

        It 'Should document REL-UPD-01 in description' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for REL-UPD-01 reference in documentation
            $moduleContent | Should -Match 'REL-UPD-01.*Catalog Query Retry'
        }

        It 'Should have examples in function documentation' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for .EXAMPLE in documentation
            $moduleContent | Should -Match 'function Invoke-CatalogQueryWithRetry[\s\S]*?\.EXAMPLE'
        }
    }

    Context 'Error Handling Behavior' {

        It 'Should return result immediately on first success (no retry needed)' {
            # Verify the function structure returns immediately on success
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check that result is returned after query execution
            $moduleContent | Should -Match 'result = & \$Query[\s\S]*?return \$result'
        }

        It 'Should store last error for re-throw' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check that error is captured
            $moduleContent | Should -Match '\$lastError = \$_'
        }

        It 'Should only sleep when more retries remain' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for conditional sleep
            $moduleContent | Should -Match 'if \(\$attempt -lt \$MaxRetries\)[\s\S]*?Start-Sleep'
        }
    }
}

# =============================================================================
# Module Version Verification
# =============================================================================

Describe 'FFU.Updates Module Version' -Tag 'Unit', 'FFU.Updates', 'Version' {

    It 'Should have version 1.0.6 or higher (includes REL-UPD-01)' {
        $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psd1'
        $manifest = Test-ModuleManifest -Path $ManifestPath
        $version = [Version]$manifest.Version
        $version | Should -BeGreaterOrEqual ([Version]'1.0.6')
    }

    It 'Should have REL-UPD-01 mentioned in release notes' {
        $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psd1'
        $manifestContent = Get-Content $ManifestPath -Raw
        $manifestContent | Should -Match 'REL-UPD-01'
    }
}
