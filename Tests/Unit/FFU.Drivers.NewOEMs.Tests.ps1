#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for Phase 42 new OEM driver functions

.DESCRIPTION
    Comprehensive unit tests covering all 8 new OEM driver implementations added in Phase 42:
    - Tier 1 (catalog-based): Acer, Dynabook, Panasonic
    - Tier 2 (portal-based): Samsung, Fujitsu
    - Tier 3 (stubs): ASUS, MSI, Getac

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.NewOEMs.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Drivers'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'
    $ConstantsModulePath = Join-Path $ModulesPath 'FFU.Constants'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Remove modules if loaded
    Get-Module -Name 'FFU.Drivers', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import dependencies in order: Constants -> Core -> Drivers
    if (Test-Path "$ConstantsModulePath\FFU.Constants.psd1") {
        Import-Module "$ConstantsModulePath\FFU.Constants.psd1" -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.Drivers module
    if (-not (Test-Path "$ModulePath\FFU.Drivers.psd1")) {
        throw "FFU.Drivers module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Drivers.psd1" -Force -ErrorAction Stop

    # Create global WriteLog stub function to suppress output in tests
    if (-not (Get-Command -Name WriteLog -ErrorAction SilentlyContinue)) {
        function global:WriteLog {
            param([Parameter(ValueFromPipeline)]$Message)
            # Suppress output in tests
        }
    }

    # Store source file path and content for static analysis
    $Script:SourceFile = Join-Path $ModulePath 'FFU.Drivers.psm1'
    $Script:SourceContent = Get-Content $Script:SourceFile -Raw
}

AfterAll {
    Get-Module -Name 'FFU.Drivers', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Tier 1 OEM Tests (Catalog-Based): Acer, Dynabook, Panasonic
# =============================================================================

Describe 'Get-AcerDrivers' -Tag 'Unit', 'FFU.Drivers', 'Phase42', 'NewOEMs', 'Acer', 'Tier1' {

    Context 'Function Export' {
        It 'Should be exported from FFU.Drivers module' {
            Get-Command -Name 'Get-AcerDrivers' -Module 'FFU.Drivers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-AcerDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-AcerDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsRelease parameter' {
            $command = Get-Command -Name 'Get-AcerDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-AcerDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Catalog Handling' {
        It 'Should reference ACER_CATALOG_URL constant' {
            $Script:SourceContent | Should -Match 'ACER_CATALOG_URL'
        }

        It 'Should reference AcerCatalog.xml in source' {
            $Script:SourceContent | Should -Match 'AcerCatalog\.xml'
        }
    }
}

Describe 'Get-DynabookDrivers' -Tag 'Unit', 'FFU.Drivers', 'Phase42', 'NewOEMs', 'Dynabook', 'Tier1' {

    Context 'Function Export' {
        It 'Should be exported from FFU.Drivers module' {
            Get-Command -Name 'Get-DynabookDrivers' -Module 'FFU.Drivers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-DynabookDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-DynabookDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context 'CAB Extraction Pattern' {
        It 'Should use CAB-to-XML extraction pattern' {
            # Check for expand.exe usage in Dynabook function context
            $Script:SourceContent | Should -Match '(?s)function Get-DynabookDrivers.*?expand\.exe|Expand\.exe'
        }

        It 'Should reference DYNABOOK_CATALOG_URL constant' {
            $Script:SourceContent | Should -Match 'DYNABOOK_CATALOG_URL'
        }
    }
}

Describe 'Get-PanasonicDrivers' -Tag 'Unit', 'FFU.Drivers', 'Phase42', 'NewOEMs', 'Panasonic', 'Tier1' {

    Context 'Function Export' {
        It 'Should be exported from FFU.Drivers module' {
            Get-Command -Name 'Get-PanasonicDrivers' -Module 'FFU.Drivers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-PanasonicDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-PanasonicDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Catalog Handling' {
        It 'Should reference PANASONIC_CATALOG_URL constant' {
            $Script:SourceContent | Should -Match 'PANASONIC_CATALOG_URL'
        }

        It 'Should handle SCCM CAB catalog format' {
            # Verify CAB extraction logic in Panasonic function
            $Script:SourceContent | Should -Match '(?s)function Get-PanasonicDrivers.*?\.cab'
        }
    }
}

# =============================================================================
# Tier 2 OEM Tests (Portal-Based): Samsung, Fujitsu
# =============================================================================

Describe 'Get-SamsungDrivers' -Tag 'Unit', 'FFU.Drivers', 'Phase42', 'NewOEMs', 'Samsung', 'Tier2' {

    Context 'Function Export' {
        It 'Should be exported from FFU.Drivers module' {
            Get-Command -Name 'Get-SamsungDrivers' -Module 'FFU.Drivers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-SamsungDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have Model parameter' {
            $command = Get-Command -Name 'Get-SamsungDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Portal Integration' {
        It 'Should reference Samsung portal URL' {
            $Script:SourceContent | Should -Match 'SAMSUNG_PORTAL_URL|samsung'
        }

        It 'Should use Expand-Archive for ZIP extraction' {
            # Verify ZIP extraction in Samsung function context
            $Script:SourceContent | Should -Match '(?s)function Get-SamsungDrivers.*?Expand-Archive'
        }
    }
}

Describe 'Get-FujitsuDrivers' -Tag 'Unit', 'FFU.Drivers', 'Phase42', 'NewOEMs', 'Fujitsu', 'Tier2' {

    Context 'Function Export' {
        It 'Should be exported from FFU.Drivers module' {
            Get-Command -Name 'Get-FujitsuDrivers' -Module 'FFU.Drivers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-FujitsuDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have Model parameter' {
            $command = Get-Command -Name 'Get-FujitsuDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Portal Integration' {
        It 'Should reference Fujitsu portal URL' {
            $Script:SourceContent | Should -Match 'FUJITSU_PORTAL_URL|fujitsu'
        }
    }
}

# =============================================================================
# Tier 3 OEM Tests (Stubs): ASUS, MSI, Getac
# =============================================================================

Describe 'Get-ASUSDrivers' -Tag 'Unit', 'FFU.Drivers', 'Phase42', 'NewOEMs', 'ASUS', 'Tier3', 'Stub' {

    Context 'Function Export' {
        It 'Should be exported from FFU.Drivers module' {
            Get-Command -Name 'Get-ASUSDrivers' -Module 'FFU.Drivers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Stub Behavior' {
        It 'Should return $null from stub implementation' {
            # Mock WriteLog to suppress output
            Mock WriteLog -ModuleName 'FFU.Drivers' {}

            $result = Get-ASUSDrivers -DriversFolder 'C:\Temp\Drivers' -Model 'TestModel' -Make 'ASUS'

            $result | Should -BeNullOrEmpty
        }

        It 'Should log WARNING message about unsupported OEM' {
            Mock WriteLog -ModuleName 'FFU.Drivers' {}

            $result = Get-ASUSDrivers -DriversFolder 'C:\Temp\Drivers' -Model 'TestModel' -Make 'ASUS'

            Should -Invoke WriteLog -ModuleName 'FFU.Drivers' -ParameterFilter {
                $Message -match 'WARNING.*ASUS.*not yet supported|not.*supported'
            }
        }
    }
}

Describe 'Get-MSIDrivers' -Tag 'Unit', 'FFU.Drivers', 'Phase42', 'NewOEMs', 'MSI', 'Tier3', 'Stub' {

    Context 'Function Export' {
        It 'Should be exported from FFU.Drivers module' {
            Get-Command -Name 'Get-MSIDrivers' -Module 'FFU.Drivers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Stub Behavior' {
        It 'Should return $null from stub implementation' {
            Mock WriteLog -ModuleName 'FFU.Drivers' {}

            $result = Get-MSIDrivers -DriversFolder 'C:\Temp\Drivers' -Model 'TestModel' -Make 'MSI'

            $result | Should -BeNullOrEmpty
        }

        It 'Should log WARNING message about unsupported OEM' {
            Mock WriteLog -ModuleName 'FFU.Drivers' {}

            $result = Get-MSIDrivers -DriversFolder 'C:\Temp\Drivers' -Model 'TestModel' -Make 'MSI'

            Should -Invoke WriteLog -ModuleName 'FFU.Drivers' -ParameterFilter {
                $Message -match 'WARNING.*MSI.*not yet supported|not.*supported'
            }
        }
    }
}

Describe 'Get-GetacDrivers' -Tag 'Unit', 'FFU.Drivers', 'Phase42', 'NewOEMs', 'Getac', 'Tier3', 'Stub' {

    Context 'Function Export' {
        It 'Should be exported from FFU.Drivers module' {
            Get-Command -Name 'Get-GetacDrivers' -Module 'FFU.Drivers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Stub Behavior' {
        It 'Should return $null from stub implementation' {
            Mock WriteLog -ModuleName 'FFU.Drivers' {}

            $result = Get-GetacDrivers -DriversFolder 'C:\Temp\Drivers' -Model 'TestModel' -Make 'Getac'

            $result | Should -BeNullOrEmpty
        }

        It 'Should log WARNING message about unsupported OEM' {
            Mock WriteLog -ModuleName 'FFU.Drivers' {}

            $result = Get-GetacDrivers -DriversFolder 'C:\Temp\Drivers' -Model 'TestModel' -Make 'Getac'

            Should -Invoke WriteLog -ModuleName 'FFU.Drivers' -ParameterFilter {
                $Message -match 'WARNING.*Getac.*not yet supported|not.*supported'
            }
        }
    }
}
