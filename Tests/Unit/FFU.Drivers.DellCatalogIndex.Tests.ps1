#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for Dell CatalogIndexPC functionality (Phase 40)

.DESCRIPTION
    Tests covering CatalogIndexPC XML parsing, SystemID extraction,
    three-tier fallback scenarios, Drivers.json schema extension,
    and Windows Server path preservation.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.DellCatalogIndex.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Drivers'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Remove and reimport modules
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path "$ModulePath\FFU.Drivers.psd1")) {
        throw "FFU.Drivers module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Drivers.psd1" -Force -ErrorAction Stop

    # Helper: Create mock CatalogIndexPC XML content
    function New-MockCatalogIndexXml {
        param(
            [Parameter(Mandatory)]
            [string]$OutputPath,

            [Parameter()]
            [PSCustomObject[]]$Models = @()
        )

        $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<ManifestIndex>
"@

        foreach ($model in $Models) {
            $xmlContent += @"

  <SystemConfiguration>
    <Model>$($model.Model)</Model>
    <Brand>$($model.Brand)</Brand>
    <systemID>$($model.SystemId)</systemID>
    <dellSystemCabUrl>$($model.CabUrl)</dellSystemCabUrl>
  </SystemConfiguration>
"@
        }

        $xmlContent += @"

</ManifestIndex>
"@

        Set-Content -Path $OutputPath -Value $xmlContent -Encoding UTF8
    }

    # Standard mock model data
    $script:MockModels = @(
        [PSCustomObject]@{
            Model    = 'Latitude 7490 (0798)'
            Brand    = 'Dell'
            SystemId = '0798'
            CabUrl   = 'https://downloads.dell.com/catalog/Model_Latitude_7490.cab'
        },
        [PSCustomObject]@{
            Model    = 'OptiPlex 7080 (09A4)'
            Brand    = 'Dell'
            SystemId = '09A4'
            CabUrl   = 'https://downloads.dell.com/catalog/Model_OptiPlex_7080.cab'
        },
        [PSCustomObject]@{
            Model    = 'Precision 5560 (0A24)'
            Brand    = 'Dell'
            SystemId = '0A24'
            CabUrl   = 'https://downloads.dell.com/catalog/Model_Precision_5560.cab'
        }
    )
}

AfterAll {
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Get-DellClientModels - CatalogIndexPC XML Parsing
# =============================================================================

Describe 'Get-DellClientModels - CatalogIndexPC XML Parsing' -Tag 'Unit', 'FFU.Drivers', 'Dell', 'CatalogIndexPC' {

    BeforeAll {
        $script:tempDir = Join-Path $TestDrive 'CatalogIndexTests'
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
    }

    Context 'Valid CatalogIndexPC XML with multiple models' {
        BeforeAll {
            $xmlPath = Join-Path $script:tempDir 'CatalogIndexPC_valid.xml'
            New-MockCatalogIndexXml -OutputPath $xmlPath -Models $script:MockModels
        }

        It 'Should return correct number of models' {
            InModuleScope 'FFU.Drivers' -Parameters @{ XmlPath = $xmlPath } {
                $result = Get-DellClientModels -CatalogIndexPath $XmlPath
                $result.Count | Should -Be 3
            }
        }

        It 'Should parse Model display name correctly' {
            InModuleScope 'FFU.Drivers' -Parameters @{ XmlPath = $xmlPath } {
                $result = Get-DellClientModels -CatalogIndexPath $XmlPath
                $result[0].Model | Should -Not -BeNullOrEmpty
                $result | Where-Object { $_.Model -like '*Latitude 7490*' } | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should parse SystemId correctly' {
            InModuleScope 'FFU.Drivers' -Parameters @{ XmlPath = $xmlPath } {
                $result = Get-DellClientModels -CatalogIndexPath $XmlPath
                $lat7490 = $result | Where-Object { $_.SystemId -eq '0798' }
                $lat7490 | Should -Not -BeNullOrEmpty
                $lat7490.SystemId | Should -Be '0798'
            }
        }

        It 'Should parse CabUrl correctly' {
            InModuleScope 'FFU.Drivers' -Parameters @{ XmlPath = $xmlPath } {
                $result = Get-DellClientModels -CatalogIndexPath $XmlPath
                $lat7490 = $result | Where-Object { $_.SystemId -eq '0798' }
                $lat7490.CabUrl | Should -BeLike '*Model_Latitude_7490*'
            }
        }

        It 'Should include Make property' {
            InModuleScope 'FFU.Drivers' -Parameters @{ XmlPath = $xmlPath } {
                $result = Get-DellClientModels -CatalogIndexPath $XmlPath
                $result[0].Make | Should -Be 'Dell'
            }
        }

        It 'Should return sorted results' {
            InModuleScope 'FFU.Drivers' -Parameters @{ XmlPath = $xmlPath } {
                $result = Get-DellClientModels -CatalogIndexPath $XmlPath
                $names = $result | ForEach-Object { $_.Model }
                $sortedNames = $names | Sort-Object
                $names | Should -Be $sortedNames
            }
        }
    }

    Context 'Empty CatalogIndexPC XML' {
        BeforeAll {
            $emptyXmlPath = Join-Path $script:tempDir 'CatalogIndexPC_empty.xml'
            Set-Content -Path $emptyXmlPath -Value '<?xml version="1.0"?><ManifestIndex></ManifestIndex>' -Encoding UTF8
        }

        It 'Should return empty list for XML with no SystemConfiguration entries' {
            InModuleScope 'FFU.Drivers' -Parameters @{ XmlPath = $emptyXmlPath } {
                $result = Get-DellClientModels -CatalogIndexPath $XmlPath
                $result.Count | Should -Be 0
            }
        }
    }

    Context 'Missing XML file' {
        It 'Should throw when CatalogIndexPath does not exist' {
            InModuleScope 'FFU.Drivers' {
                { Get-DellClientModels -CatalogIndexPath 'C:\nonexistent\CatalogIndexPC.xml' } | Should -Throw
            }
        }
    }

    Context 'Incomplete SystemConfiguration entries' {
        BeforeAll {
            $incompleteXmlPath = Join-Path $script:tempDir 'CatalogIndexPC_incomplete.xml'
            # Entry missing systemID
            $content = @"
<?xml version="1.0"?>
<ManifestIndex>
  <SystemConfiguration>
    <Model>Latitude 7490 (0798)</Model>
    <Brand>Dell</Brand>
    <dellSystemCabUrl>https://downloads.dell.com/catalog/Model_Latitude_7490.cab</dellSystemCabUrl>
  </SystemConfiguration>
  <SystemConfiguration>
    <Model>OptiPlex 7080 (09A4)</Model>
    <Brand>Dell</Brand>
    <systemID>09A4</systemID>
    <dellSystemCabUrl>https://downloads.dell.com/catalog/Model_OptiPlex_7080.cab</dellSystemCabUrl>
  </SystemConfiguration>
</ManifestIndex>
"@
            Set-Content -Path $incompleteXmlPath -Value $content -Encoding UTF8
        }

        It 'Should skip entries missing systemID and return only complete entries' {
            InModuleScope 'FFU.Drivers' -Parameters @{ XmlPath = $incompleteXmlPath } {
                $result = Get-DellClientModels -CatalogIndexPath $XmlPath
                $result.Count | Should -Be 1
                $result[0].SystemId | Should -Be '09A4'
            }
        }
    }
}
