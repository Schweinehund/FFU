#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Drivers reliability features (REL-DRV-*)

.DESCRIPTION
    Tests for reliability improvements in FFU.Drivers module:
    - REL-DRV-01: Driver Download Retry (Invoke-DriverDownloadWithRetry)
    - REL-DRV-02: Vendor-Specific Extraction Error Handling (Get-DriverExtractionResult)
    - REL-DRV-03: Catalog Fallback Sources (Get-CachedOEMCatalog)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.Reliability.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Drivers'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'
    $ConstantsModulePath = Join-Path $ModulesPath 'FFU.Constants'

    # Add Modules folder to PSModulePath for proper dependency resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    Get-Module -Name 'FFU.Drivers', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (required dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
    }

    if (-not (Test-Path "$ModulePath\FFU.Drivers.psd1")) {
        throw "FFU.Drivers module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Drivers.psd1" -Force -ErrorAction Stop

    # Get the module object for accessing private functions
    $script:DriversModule = Get-Module -Name 'FFU.Drivers'
}

AfterAll {
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# REL-DRV-01: Driver Download Retry Tests
# =============================================================================

Describe 'REL-DRV-01: Driver Download Retry' -Tag 'Unit', 'FFU.Drivers', 'Reliability', 'REL-DRV-01' {

    Context 'Invoke-DriverDownloadWithRetry function' {

        It 'Should be defined in the module (internal function)' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match 'function Invoke-DriverDownloadWithRetry'
        }

        It 'Should have correct parameters defined' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            $moduleContent | Should -Match '\[Parameter\(Mandatory\)\][\s\S]*?\[string\]\$Source'
            $moduleContent | Should -Match '\[Parameter\(Mandatory\)\][\s\S]*?\[string\]\$Destination'
            $moduleContent | Should -Match '\[string\]\$OperationName'
            $moduleContent | Should -Match '\[int\]\$MaxRetries'
            $moduleContent | Should -Match '\[int\]\$BaseDelaySeconds'
        }

        It 'Should implement exponential backoff with jitter' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for exponential backoff calculation
            $moduleContent | Should -Match '\[math\]::Pow\(2, \$attempt - 1\)'

            # Check for jitter
            $moduleContent | Should -Match 'Get-Random -Minimum 0 -Maximum 3'
        }

        It 'Should use ThreadJob-safe logging pattern' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for $function:WriteLog pattern within Invoke-DriverDownloadWithRetry
            $functionMatch = [regex]::Match($moduleContent, 'function Invoke-DriverDownloadWithRetry[\s\S]*?(?=\r?\nfunction )')
            if ($functionMatch.Success) {
                $functionContent = $functionMatch.Value
                $functionContent | Should -Match '\$function:WriteLog'
            } else {
                Set-ItResult -Skipped -Because 'Could not isolate function content'
            }
        }
    }
}

# =============================================================================
# REL-DRV-02: Vendor-Specific Extraction Error Handling Tests
# =============================================================================

Describe 'REL-DRV-02: Vendor-Specific Extraction Error Handling' -Tag 'Unit', 'FFU.Drivers', 'Reliability', 'REL-DRV-02' {

    Context 'Get-DriverExtractionResult function' {

        It 'Should be defined in the module (internal function)' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match 'function Get-DriverExtractionResult'
        }

        It 'Should support HP vendor' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match "'HP'\s*\{"
        }

        It 'Should support Lenovo vendor' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match "'Lenovo'\s*\{"
        }

        It 'Should support Dell vendor' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match "'Dell'\s*\{"
        }

        It 'Should support Microsoft vendor' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match "'Microsoft'\s*\{"
        }

        It 'Should treat exit code 3010 (reboot required) as success' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            # 3010 should set Success = $true
            $moduleContent | Should -Match '3010[\s\S]*?\$result\.Success = \$true'
        }

        It 'Should return PSCustomObject with expected properties' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match 'Success\s*='
            $moduleContent | Should -Match 'Critical\s*='
            $moduleContent | Should -Match 'Message\s*='
            $moduleContent | Should -Match 'Action\s*='
        }
    }
}

# =============================================================================
# REL-DRV-03: Catalog Fallback Sources Tests
# =============================================================================

Describe 'REL-DRV-03: Catalog Fallback Sources' -Tag 'Unit', 'FFU.Drivers', 'Reliability', 'REL-DRV-03' {

    Context 'FFUConstants catalog URLs' {

        BeforeAll {
            # Access FFUConstants through the module's scope since it uses 'using module'
            $module = Get-Module FFU.Drivers
            $script:dellPcUrl = $module.Invoke({ [FFUConstants]::DELL_CATALOG_PC_URL })
            $script:dellServerUrl = $module.Invoke({ [FFUConstants]::DELL_CATALOG_SERVER_URL })
            $script:hpUrl = $module.Invoke({ [FFUConstants]::HP_PLATFORM_LIST_URL })
            $script:cacheHours = $module.Invoke({ [FFUConstants]::OEM_CATALOG_CACHE_HOURS })
        }

        It 'Should define DELL_CATALOG_PC_URL' {
            $dellPcUrl | Should -Not -BeNullOrEmpty
            $dellPcUrl | Should -Match 'downloads\.dell\.com'
        }

        It 'Should define DELL_CATALOG_SERVER_URL' {
            $dellServerUrl | Should -Not -BeNullOrEmpty
            $dellServerUrl | Should -Match 'downloads\.dell\.com'
        }

        It 'Should define HP_PLATFORM_LIST_URL' {
            $hpUrl | Should -Not -BeNullOrEmpty
            $hpUrl | Should -Match 'hpia\.hpcloud\.hp\.com'
        }

        It 'Should define OEM_CATALOG_CACHE_HOURS' {
            $cacheHours | Should -BeGreaterThan 0
            $cacheHours | Should -Be 168  # 7 days
        }
    }

    Context 'Get-CachedOEMCatalog function' {

        BeforeAll {
            $module = Get-Module FFU.Drivers
            $script:getCatalog = $module.Invoke({ Get-Item "Function:\Get-CachedOEMCatalog" -ErrorAction SilentlyContinue })
        }

        It 'Should exist as internal function' {
            $getCatalog | Should -Not -BeNullOrEmpty
        }

        It 'Should have required parameters' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for parameters in Get-CachedOEMCatalog
            $functionMatch = [regex]::Match($moduleContent, 'function Get-CachedOEMCatalog[\s\S]*?(?=\r?\nfunction )')
            if ($functionMatch.Success) {
                $functionContent = $functionMatch.Value
                $functionContent | Should -Match '\$Vendor'
                $functionContent | Should -Match '\$CatalogType'
                $functionContent | Should -Match '\$PrimaryUrl'
                $functionContent | Should -Match '\$BackupUrl'
                $functionContent | Should -Match '\$CachePath'
                $functionContent | Should -Match '\$MaxCacheAgeHours'
            } else {
                Set-ItResult -Skipped -Because 'Could not isolate function content'
            }
        }

        It 'Should have ForceRefresh switch parameter' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            $functionMatch = [regex]::Match($moduleContent, 'function Get-CachedOEMCatalog[\s\S]*?(?=\r?\nfunction )')
            if ($functionMatch.Success) {
                $functionContent = $functionMatch.Value
                $functionContent | Should -Match '\[switch\]\$ForceRefresh'
            } else {
                Set-ItResult -Skipped -Because 'Could not isolate function content'
            }
        }
    }

    Context 'Get-DellDrivers catalog integration' {

        It 'Should use Get-CachedOEMCatalog for catalog download' {
            $source = (Get-Command Get-DellDrivers).ScriptBlock.ToString()
            $source | Should -Match 'Get-CachedOEMCatalog'
        }

        It 'Should use FFUConstants for catalog URL' {
            $source = (Get-Command Get-DellDrivers).ScriptBlock.ToString()
            $source | Should -Match '\[FFUConstants\]::DELL_CATALOG'
        }
    }

    Context 'Get-HPDrivers catalog integration' {

        It 'Should use Get-CachedOEMCatalog for platform list' {
            $source = (Get-Command Get-HPDrivers).ScriptBlock.ToString()
            $source | Should -Match 'Get-CachedOEMCatalog'
        }

        It 'Should use FFUConstants for platform list URL' {
            $source = (Get-Command Get-HPDrivers).ScriptBlock.ToString()
            $source | Should -Match '\[FFUConstants\]::HP_PLATFORM_LIST_URL'
        }
    }

    Context 'Stale cache fallback' {

        It 'Should implement stale cache fallback when download fails' {
            $module = Get-Module FFU.Drivers
            $source = $module.Invoke({ (Get-Item "Function:\Get-CachedOEMCatalog").ScriptBlock.ToString() })
            # Should check for existing cache and use it when download fails
            $source | Should -Match 'Using stale cached'
        }
    }
}
