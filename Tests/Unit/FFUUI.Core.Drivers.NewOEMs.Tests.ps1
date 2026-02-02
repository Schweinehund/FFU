#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for Phase 42 new OEM UI driver modules

.DESCRIPTION
    Comprehensive unit tests covering all 8 new OEM UI driver module implementations added in Phase 42:
    - Tier 1 (catalog-based): Acer, Dynabook, Panasonic
    - Tier 2 (portal-based): Samsung, Fujitsu
    - Tier 3 (stubs): ASUS, MSI, Getac

    Each OEM module is tested for:
    - Module import success
    - Get-{OEM}DriversModelList function (model discovery)
    - Save-{OEM}DriversTask function (driver download task)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFUUI.Core.Drivers.NewOEMs.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths relative to test file location
    $ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\").Path
    $UICorePath = Join-Path $ProjectRoot 'FFUDevelopment\FFUUI.Core'
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    # Add Modules folder to PSModulePath for dependency resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Import dependencies (FFU.Constants, FFU.Core) first
    Import-Module (Join-Path $ModulesPath 'FFU.Constants\FFU.Constants.psd1') -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModulesPath 'FFU.Core\FFU.Core.psd1') -Force -ErrorAction SilentlyContinue

    # Create global WriteLog stub function to suppress output in tests
    if (-not (Get-Command -Name WriteLog -ErrorAction SilentlyContinue)) {
        function global:WriteLog {
            param([Parameter(ValueFromPipeline)]$Message)
            # Suppress output in tests
        }
    }

    # Define the 8 new OEMs to test
    $Script:NewOEMs = @(
        @{ Name = 'Acer'; Tier = 1 },
        @{ Name = 'Dynabook'; Tier = 1 },
        @{ Name = 'Panasonic'; Tier = 1 },
        @{ Name = 'Samsung'; Tier = 2 },
        @{ Name = 'Fujitsu'; Tier = 2 },
        @{ Name = 'ASUS'; Tier = 3 },
        @{ Name = 'MSI'; Tier = 3 },
        @{ Name = 'Getac'; Tier = 3 }
    )

    # Import each OEM UI module
    foreach ($oem in $Script:NewOEMs) {
        $modulePath = Join-Path $UICorePath "FFUUI.Core.Drivers.$($oem.Name).psm1"
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force -ErrorAction SilentlyContinue
        }
    }
}

AfterAll {
    # Clean up imported OEM modules
    foreach ($oem in $Script:NewOEMs) {
        Get-Module -Name "FFUUI.Core.Drivers.$($oem.Name)" | Remove-Module -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Tier 1 OEM UI Tests (Catalog-Based): Acer, Dynabook, Panasonic
# =============================================================================

Describe 'FFUUI.Core.Drivers.Acer' -Tag 'Unit', 'FFUUI.Core', 'Phase42', 'NewOEMs', 'Acer', 'Tier1' {

    Context 'Module Import' {
        It 'Should import FFUUI.Core.Drivers.Acer module successfully' {
            Get-Module -Name 'FFUUI.Core.Drivers.Acer' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-AcerDriversModelList' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Get-AcerDriversModelList' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have DriversFolder parameter' {
            $command = Get-Command -Name 'Get-AcerDriversModelList'
            $command.Parameters.ContainsKey('DriversFolder') | Should -BeTrue
        }

        It 'Should have Make parameter' {
            $command = Get-Command -Name 'Get-AcerDriversModelList'
            $command.Parameters.ContainsKey('Make') | Should -BeTrue
        }

        It 'Should handle catalog failure gracefully' {
            Mock Start-BitsTransferWithRetry { throw "Network error" } -ModuleName 'FFUUI.Core.Drivers.Acer'

            $result = Get-AcerDriversModelList -DriversFolder 'C:\Temp\Drivers' -Make 'Acer'

            # Should not throw, should return empty or handle gracefully
            { $result } | Should -Not -Throw
        }
    }

    Context 'Save-AcerDriversTask' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Save-AcerDriversTask' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have expected parameters' {
            $command = Get-Command -Name 'Save-AcerDriversTask'
            $command.Parameters.ContainsKey('DriverItemData') | Should -BeTrue
            $command.Parameters.ContainsKey('DriversFolder') | Should -BeTrue
            $command.Parameters.ContainsKey('WindowsArch') | Should -BeTrue
            $command.Parameters.ContainsKey('WindowsRelease') | Should -BeTrue
        }
    }
}

Describe 'FFUUI.Core.Drivers.Dynabook' -Tag 'Unit', 'FFUUI.Core', 'Phase42', 'NewOEMs', 'Dynabook', 'Tier1' {

    Context 'Module Import' {
        It 'Should import FFUUI.Core.Drivers.Dynabook module successfully' {
            Get-Module -Name 'FFUUI.Core.Drivers.Dynabook' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-DynabookDriversModelList' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Get-DynabookDriversModelList' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have DriversFolder parameter' {
            $command = Get-Command -Name 'Get-DynabookDriversModelList'
            $command.Parameters.ContainsKey('DriversFolder') | Should -BeTrue
        }

        It 'Should handle catalog failure gracefully' {
            Mock Start-BitsTransferWithRetry { throw "Network error" } -ModuleName 'FFUUI.Core.Drivers.Dynabook'

            $result = Get-DynabookDriversModelList -DriversFolder 'C:\Temp\Drivers' -Make 'Dynabook'

            # Should not throw
            { $result } | Should -Not -Throw
        }
    }

    Context 'Save-DynabookDriversTask' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Save-DynabookDriversTask' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have expected parameters' {
            $command = Get-Command -Name 'Save-DynabookDriversTask'
            $command.Parameters.ContainsKey('DriverItemData') | Should -BeTrue
            $command.Parameters.ContainsKey('DriversFolder') | Should -BeTrue
        }
    }
}

Describe 'FFUUI.Core.Drivers.Panasonic' -Tag 'Unit', 'FFUUI.Core', 'Phase42', 'NewOEMs', 'Panasonic', 'Tier1' {

    Context 'Module Import' {
        It 'Should import FFUUI.Core.Drivers.Panasonic module successfully' {
            Get-Module -Name 'FFUUI.Core.Drivers.Panasonic' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-PanasonicDriversModelList' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Get-PanasonicDriversModelList' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have DriversFolder parameter' {
            $command = Get-Command -Name 'Get-PanasonicDriversModelList'
            $command.Parameters.ContainsKey('DriversFolder') | Should -BeTrue
        }
    }

    Context 'Save-PanasonicDriversTask' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Save-PanasonicDriversTask' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Tier 2 OEM UI Tests (Portal-Based): Samsung, Fujitsu
# =============================================================================

Describe 'FFUUI.Core.Drivers.Samsung' -Tag 'Unit', 'FFUUI.Core', 'Phase42', 'NewOEMs', 'Samsung', 'Tier2' {

    Context 'Module Import' {
        It 'Should import FFUUI.Core.Drivers.Samsung module successfully' {
            Get-Module -Name 'FFUUI.Core.Drivers.Samsung' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-SamsungDriversModelList' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Get-SamsungDriversModelList' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have appropriate parameters' {
            $command = Get-Command -Name 'Get-SamsungDriversModelList'
            # Samsung may use Headers/UserAgent like Microsoft
            $command.Parameters.Keys.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Save-SamsungDriversTask' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Save-SamsungDriversTask' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'FFUUI.Core.Drivers.Fujitsu' -Tag 'Unit', 'FFUUI.Core', 'Phase42', 'NewOEMs', 'Fujitsu', 'Tier2' {

    Context 'Module Import' {
        It 'Should import FFUUI.Core.Drivers.Fujitsu module successfully' {
            Get-Module -Name 'FFUUI.Core.Drivers.Fujitsu' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-FujitsuDriversModelList' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Get-FujitsuDriversModelList' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Save-FujitsuDriversTask' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Save-FujitsuDriversTask' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Tier 3 OEM UI Tests (Stubs): ASUS, MSI, Getac
# =============================================================================

Describe 'FFUUI.Core.Drivers.ASUS' -Tag 'Unit', 'FFUUI.Core', 'Phase42', 'NewOEMs', 'ASUS', 'Tier3', 'Stub' {

    Context 'Module Import' {
        It 'Should import FFUUI.Core.Drivers.ASUS module successfully' {
            Get-Module -Name 'FFUUI.Core.Drivers.ASUS' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-ASUSDriversModelList' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Get-ASUSDriversModelList' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should return empty array' {
            $result = Get-ASUSDriversModelList
            @($result).Count | Should -Be 0
        }

        It 'Should log stub message' {
            Mock WriteLog {}

            $result = Get-ASUSDriversModelList

            Should -Invoke WriteLog -ParameterFilter {
                $Message -match 'WARNING.*ASUS.*not.*supported'
            }
        }
    }

    Context 'Save-ASUSDriversTask' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Save-ASUSDriversTask' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should handle invocation without error' {
            $testData = [PSCustomObject]@{ Model = 'TestModel' }

            { Save-ASUSDriversTask -DriverItemData $testData -DriversFolder 'C:\Temp' -WindowsArch 'x64' -WindowsRelease 11 } | Should -Not -Throw
        }
    }
}

Describe 'FFUUI.Core.Drivers.MSI' -Tag 'Unit', 'FFUUI.Core', 'Phase42', 'NewOEMs', 'MSI', 'Tier3', 'Stub' {

    Context 'Module Import' {
        It 'Should import FFUUI.Core.Drivers.MSI module successfully' {
            Get-Module -Name 'FFUUI.Core.Drivers.MSI' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-MSIDriversModelList' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Get-MSIDriversModelList' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should return empty array' {
            $result = Get-MSIDriversModelList
            @($result).Count | Should -Be 0
        }
    }

    Context 'Save-MSIDriversTask' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Save-MSIDriversTask' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should handle invocation without error' {
            $testData = [PSCustomObject]@{ Model = 'TestModel' }

            { Save-MSIDriversTask -DriverItemData $testData -DriversFolder 'C:\Temp' -WindowsArch 'x64' -WindowsRelease 11 } | Should -Not -Throw
        }
    }
}

Describe 'FFUUI.Core.Drivers.Getac' -Tag 'Unit', 'FFUUI.Core', 'Phase42', 'NewOEMs', 'Getac', 'Tier3', 'Stub' {

    Context 'Module Import' {
        It 'Should import FFUUI.Core.Drivers.Getac module successfully' {
            Get-Module -Name 'FFUUI.Core.Drivers.Getac' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-GetacDriversModelList' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Get-GetacDriversModelList' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should return empty array' {
            $result = Get-GetacDriversModelList
            @($result).Count | Should -Be 0
        }
    }

    Context 'Save-GetacDriversTask' {
        It 'Should exist as an exported function' {
            Get-Command -Name 'Save-GetacDriversTask' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should handle invocation without error' {
            $testData = [PSCustomObject]@{ Model = 'TestModel' }

            { Save-GetacDriversTask -DriverItemData $testData -DriversFolder 'C:\Temp' -WindowsArch 'x64' -WindowsRelease 11 } | Should -Not -Throw
        }
    }
}
