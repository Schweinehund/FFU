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
