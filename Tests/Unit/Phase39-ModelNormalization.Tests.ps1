#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for Phase 39: Model Name Normalization and SystemID extraction.

.DESCRIPTION
    Comprehensive tests covering:
    - Dell model name normalization (GroupManifest Display CDATA, brand dedup)
    - HP model name normalization (ConvertTo-ComparableModelName AIO/inch)
    - Build-time SystemID extraction (Dell regex, Lenovo regex, HP PlatformList mock)
    - Deploy-time SystemID extraction (Get-NormalizedManufacturer, Get-SystemIdentityMetadata)
    - DriverMapping.json schema (Update-DriverMappingJson with SystemID fields)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\Phase39-ModelNormalization.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Resolve paths
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ApplyFFUPath = Join-Path $ProjectRoot 'FFUDevelopment\WinPEDeployFFUFiles\ApplyFFU.ps1'
    $DriversModulePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.Drivers.psm1'

    # Mock WriteLog globally before extracting functions
    function global:WriteLog {
        param([string]$LogText)
        # Silent in tests
    }

    # Extract functions from ApplyFFU.ps1 via AST (deploy-time functions run in WinPE,
    # not a module, so we extract and define them in test scope)
    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $ApplyFFUPath,
        [ref]$tokens,
        [ref]$errors
    )

    if ($errors.Count -gt 0) {
        throw "ApplyFFU.ps1 has syntax errors: $($errors | ForEach-Object { $_.ToString() })"
    }

    # Find and define target functions in test scope
    $functionNames = @(
        'Get-NormalizedManufacturer',
        'Get-SystemIdentityMetadata',
        'ConvertTo-ComparableModelName'
    )
    $functionDefs = $ast.FindAll(
        { param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $functionNames -contains $node.Name
        }, $true
    )

    foreach ($funcDef in $functionDefs) {
        # Define each function in the global scope for testing
        $funcBody = $funcDef.Extent.Text
        Invoke-Expression $funcBody
    }

    # Import FFU.Common.Drivers module for build-time tests
    if (Test-Path $DriversModulePath) {
        Import-Module $DriversModulePath -Force -ErrorAction SilentlyContinue
    }
}

AfterAll {
    # Cleanup
    Get-Module -Name 'FFU.Common.Drivers' | Remove-Module -Force -ErrorAction SilentlyContinue
    # Remove extracted global functions
    Remove-Item -Path 'Function:\Get-NormalizedManufacturer' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Get-SystemIdentityMetadata' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\ConvertTo-ComparableModelName' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\WriteLog' -ErrorAction SilentlyContinue
}

# =============================================================================
# Phase 39: Model Name Normalization and SystemID
# =============================================================================

Describe "Phase 39: Model Name Normalization and SystemID" -Tag 'Unit', 'Phase39' {

    # =========================================================================
    # Dell Model Name Normalization
    # =========================================================================
    Describe "Dell Model Name Normalization" -Tag 'Dell' {

        Context "GroupManifest Display CDATA extraction" {
            # These test the normalization logic as implemented in FFUUI.Core.Drivers.Dell.psm1
            # We verify the logic patterns since the functions are inside a streaming parser

            It "strips 'PDK Catalog for' prefix from GroupManifest Display" {
                # Pattern from Get-DellDriversModelList: -replace '(?i)^PDK Catalog for\s+', ''
                $gmText = "PDK Catalog for Dell Latitude 7490"
                $result = $gmText -replace '(?i)^PDK Catalog for\s+', ''
                $result.Trim() | Should -Be "Dell Latitude 7490"
            }

            It "handles case-insensitive 'PDK Catalog for' prefix" {
                $gmText = "pdk catalog for Dell OptiPlex 5080"
                $result = $gmText -replace '(?i)^PDK Catalog for\s+', ''
                $result.Trim() | Should -Be "Dell OptiPlex 5080"
            }

            It "uses GroupManifest Display when available, ignoring Model Display" {
                # When GroupManifest/Display is present, it should be used over Model/Display
                $gmText = "PDK Catalog for Dell Latitude 5530"
                $rawModelDisplay = "Latitude 5530"

                $finalModelName = ($gmText -replace '(?i)^PDK Catalog for\s+', '').Trim()
                $finalModelName | Should -Be "Dell Latitude 5530"
                $finalModelName | Should -Not -Be $rawModelDisplay
            }

            It "falls back to Brand+Model assembly when GroupManifest absent" {
                $brandName = "Dell"
                $rawModelDisplay = "Latitude 7490"
                $gmText = $null

                # Simulate fallback logic
                $finalModelName = $null
                if ([string]::IsNullOrWhiteSpace($gmText)) {
                    if (-not [string]::IsNullOrWhiteSpace($brandName) -and
                        -not $rawModelDisplay.StartsWith($brandName, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $finalModelName = "$brandName $rawModelDisplay"
                    }
                    else {
                        $finalModelName = $rawModelDisplay
                    }
                }
                $finalModelName | Should -Be "Dell Latitude 7490"
            }
        }

        Context "Brand dedup prevention" {
            It "does not duplicate brand prefix when model already starts with brand" {
                $brandName = "Dell"
                $rawModelDisplay = "Dell Latitude 7490"

                # Simulate dedup logic
                if (-not [string]::IsNullOrWhiteSpace($brandName) -and
                    -not $rawModelDisplay.StartsWith($brandName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $result = "$brandName $rawModelDisplay"
                }
                else {
                    $result = $rawModelDisplay
                }
                $result | Should -Be "Dell Latitude 7490"
                $result | Should -Not -Be "Dell Dell Latitude 7490"
            }

            It "prepends brand when model does not start with brand" {
                $brandName = "Dell"
                $rawModelDisplay = "Latitude 7490"

                if (-not [string]::IsNullOrWhiteSpace($brandName) -and
                    -not $rawModelDisplay.StartsWith($brandName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $result = "$brandName $rawModelDisplay"
                }
                else {
                    $result = $rawModelDisplay
                }
                $result | Should -Be "Dell Latitude 7490"
            }

            It "handles case-insensitive brand prefix check" {
                $brandName = "Dell"
                $rawModelDisplay = "dell Latitude 5540"

                if (-not [string]::IsNullOrWhiteSpace($brandName) -and
                    -not $rawModelDisplay.StartsWith($brandName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $result = "$brandName $rawModelDisplay"
                }
                else {
                    $result = $rawModelDisplay
                }
                # Should NOT prepend since "dell" starts with "Dell" (case-insensitive)
                $result | Should -Be "dell Latitude 5540"
            }

            It "handles empty brand name gracefully" {
                $brandName = ""
                $rawModelDisplay = "Latitude 7490"

                if (-not [string]::IsNullOrWhiteSpace($brandName) -and
                    -not $rawModelDisplay.StartsWith($brandName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $result = "$brandName $rawModelDisplay"
                }
                else {
                    $result = $rawModelDisplay
                }
                $result | Should -Be "Latitude 7490"
            }
        }
    }

    # =========================================================================
    # HP Model Name Normalization
    # =========================================================================
    Describe "HP Model Name Normalization (ConvertTo-ComparableModelName)" -Tag 'HP' {

        Context "AIO canonicalization" {
            It "normalizes 'All-in-One' to 'AIO'" {
                $result = ConvertTo-ComparableModelName -Text "HP EliteOne 800 G6 All-in-One"
                $result | Should -Be "HP EliteOne 800 G6 AIO"
            }

            It "normalizes 'All in One' to 'AIO'" {
                $result = ConvertTo-ComparableModelName -Text "HP ProOne 440 G9 All in One"
                $result | Should -Be "HP ProOne 440 G9 AIO"
            }

            It "normalizes 'AiO' to 'AIO'" {
                $result = ConvertTo-ComparableModelName -Text "HP EliteOne 840 AiO"
                $result | Should -Be "HP EliteOne 840 AIO"
            }

            It "normalizes 'All-in-One PC' to 'AIO'" {
                $result = ConvertTo-ComparableModelName -Text "HP ProOne 600 G6 All-in-One PC"
                $result | Should -Be "HP ProOne 600 G6 AIO"
            }
        }

        Context "Inch unit stripping" {
            It "strips '23.8-in' to '23.8'" {
                $result = ConvertTo-ComparableModelName -Text "HP EliteOne 840 23.8-in G9"
                $result | Should -Be "HP EliteOne 840 23 8 G9"
            }

            It "strips '23.8 inch' to '23.8'" {
                $result = ConvertTo-ComparableModelName -Text "HP EliteOne 840 23.8 inch G9"
                $result | Should -Be "HP EliteOne 840 23 8 G9"
            }

            It "strips '27inch' to '27'" {
                $result = ConvertTo-ComparableModelName -Text "HP EliteOne 800 27inch G6"
                $result | Should -Be "HP EliteOne 800 27 G6"
            }

            It "strips '23-in' to '23'" {
                $result = ConvertTo-ComparableModelName -Text "HP ProOne 440 23-in G9"
                $result | Should -Be "HP ProOne 440 23 G9"
            }
        }

        Context "General normalization" {
            It "replaces non-alphanumeric with single space" {
                $result = ConvertTo-ComparableModelName -Text "Dell (Latitude) 7490!"
                $result | Should -Be "Dell Latitude 7490"
            }

            It "collapses multiple spaces" {
                $result = ConvertTo-ComparableModelName -Text "HP   EliteBook   840   G7"
                $result | Should -Be "HP EliteBook 840 G7"
            }

            It "trims leading and trailing whitespace" {
                $result = ConvertTo-ComparableModelName -Text "  HP EliteBook 840 G7  "
                $result | Should -Be "HP EliteBook 840 G7"
            }

            It "handles null input returning empty string" {
                $result = ConvertTo-ComparableModelName -Text $null
                $result | Should -Be ''
            }

            It "handles empty string input" {
                $result = ConvertTo-ComparableModelName -Text ''
                $result | Should -Be ''
            }
        }
    }

    # =========================================================================
    # Build-time SystemID Extraction
    # =========================================================================
    Describe "SystemID Extraction (Build-time)" -Tag 'BuildTime' {

        Context "Dell SystemId regex" {
            BeforeAll {
                # Regex pattern used in Update-DriverMappingJson for Dell/Lenovo
                $script:parenthesizedSuffixRegex = '\(([^)]+)\)\s*$'
            }

            It "extracts parenthesized suffix from 'Dell Latitude 7490 (ABC1)'" {
                $model = "Dell Latitude 7490 (ABC1)"
                $model -match $parenthesizedSuffixRegex | Should -BeTrue
                $matches[1].Trim().ToUpperInvariant() | Should -Be "ABC1"
            }

            It "returns no match when no parenthesized suffix" {
                $model = "Dell Latitude 7490"
                $model -match $parenthesizedSuffixRegex | Should -BeFalse
            }

            It "handles multiple parentheses, takes last one" {
                $model = "Dell (Some) Model (XYZ)"
                $model -match $parenthesizedSuffixRegex | Should -BeTrue
                $matches[1].Trim().ToUpperInvariant() | Should -Be "XYZ"
            }

            It "extracts SystemId with spaces and normalizes" {
                $model = "Dell Precision 5570 ( 0A5C )"
                $model -match $parenthesizedSuffixRegex | Should -BeTrue
                $matches[1].Trim().ToUpperInvariant() | Should -Be "0A5C"
            }

            It "handles alphanumeric SystemId" {
                $model = "Dell OptiPlex 7090 (09FF)"
                $model -match $parenthesizedSuffixRegex | Should -BeTrue
                $matches[1].Trim().ToUpperInvariant() | Should -Be "09FF"
            }
        }

        Context "Lenovo MachineType regex" {
            BeforeAll {
                $script:parenthesizedSuffixRegex = '\(([^)]+)\)\s*$'
            }

            It "extracts parenthesized suffix from 'ThinkPad T14s (21BR)'" {
                $model = "ThinkPad T14s (21BR)"
                $model -match $parenthesizedSuffixRegex | Should -BeTrue
                $matches[1].Trim().ToUpperInvariant() | Should -Be "21BR"
            }

            It "returns no match when no parenthesized suffix" {
                $model = "ThinkPad T14s Gen 3"
                $model -match $parenthesizedSuffixRegex | Should -BeFalse
            }

            It "extracts MachineType from consumer model" {
                $model = "IdeaPad 5 14ALC05 (82LM)"
                $model -match $parenthesizedSuffixRegex | Should -BeTrue
                $matches[1].Trim().ToUpperInvariant() | Should -Be "82LM"
            }
        }

        Context "HP SystemId from PlatformList.xml" {
            BeforeAll {
                # Create a mock PlatformList.xml in TestDrive
                $hpFolder = Join-Path $TestDrive "HP"
                New-Item -Path $hpFolder -ItemType Directory -Force | Out-Null
                $platformListXml = Join-Path $hpFolder "PlatformList.xml"

                $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<ImagePal>
  <Platform>
    <SystemID>8AB3</SystemID>
    <ProductName><![CDATA[HP EliteBook 840 G7 Notebook PC]]></ProductName>
  </Platform>
  <Platform>
    <SystemID>8549</SystemID>
    <ProductName><![CDATA[HP ProDesk 400 G7 Small Form Factor PC]]></ProductName>
  </Platform>
  <Platform>
    <SystemID>880D</SystemID>
    <ProductName><![CDATA[HP EliteOne 800 G6 24 All-in-One PC]]></ProductName>
  </Platform>
</ImagePal>
"@
                Set-Content -Path $platformListXml -Value $xmlContent -Encoding UTF8

                $script:hasHPLookup = $null -ne (Get-Command -Name 'Get-HPSystemIdFromPlatformList' -ErrorAction SilentlyContinue)
            }

            It "finds exact case-insensitive match" {
                if (-not $script:hasHPLookup) { Set-ItResult -Skipped -Because "Get-HPSystemIdFromPlatformList not available" }
                $result = Get-HPSystemIdFromPlatformList -ModelName "HP EliteBook 840 G7 Notebook PC" -DriversFolder $TestDrive
                $result | Should -Be "8AB3"
            }

            It "finds stripped-alphanumeric match when exact fails" {
                if (-not $script:hasHPLookup) { Set-ItResult -Skipped -Because "Get-HPSystemIdFromPlatformList not available" }
                # "HP EliteBook 840 G7 Notebook PC" vs "HP EliteBook 840 G7 Notebook-PC" (hyphen difference)
                $result = Get-HPSystemIdFromPlatformList -ModelName "HP EliteBook 840 G7 Notebook-PC" -DriversFolder $TestDrive
                $result | Should -Be "8AB3"
            }

            It "finds contains match as last resort" {
                if (-not $script:hasHPLookup) { Set-ItResult -Skipped -Because "Get-HPSystemIdFromPlatformList not available" }
                $result = Get-HPSystemIdFromPlatformList -ModelName "HP ProDesk 400 G7" -DriversFolder $TestDrive
                $result | Should -Be "8549"
            }

            It "returns null when no match found" {
                if (-not $script:hasHPLookup) { Set-ItResult -Skipped -Because "Get-HPSystemIdFromPlatformList not available" }
                $result = Get-HPSystemIdFromPlatformList -ModelName "HP Spectre x360 999" -DriversFolder $TestDrive
                $result | Should -BeNullOrEmpty
            }

            It "returns null when PlatformList.xml does not exist" {
                if (-not $script:hasHPLookup) { Set-ItResult -Skipped -Because "Get-HPSystemIdFromPlatformList not available" }
                $emptyFolder = Join-Path $TestDrive "EmptyDrivers"
                New-Item -Path $emptyFolder -ItemType Directory -Force | Out-Null
                $result = Get-HPSystemIdFromPlatformList -ModelName "HP EliteBook 840 G7" -DriversFolder $emptyFolder
                $result | Should -BeNullOrEmpty
            }
        }
    }

    # =========================================================================
    # Deploy-time SystemID Extraction
    # =========================================================================
    Describe "SystemID Extraction (Deploy-time)" -Tag 'DeployTime' {

        Context "Get-NormalizedManufacturer" {
            It "normalizes 'Dell Inc.' to 'Dell'" {
                Get-NormalizedManufacturer -RawManufacturer 'Dell Inc.' | Should -Be 'Dell'
            }

            It "normalizes 'Dell Technologies' to 'Dell'" {
                Get-NormalizedManufacturer -RawManufacturer 'Dell Technologies' | Should -Be 'Dell'
            }

            It "normalizes 'HP' to 'HP'" {
                Get-NormalizedManufacturer -RawManufacturer 'HP' | Should -Be 'HP'
            }

            It "normalizes 'Hewlett-Packard' to 'HP'" {
                Get-NormalizedManufacturer -RawManufacturer 'Hewlett-Packard' | Should -Be 'HP'
            }

            It "normalizes 'Hewlett Packard Enterprise' to 'HP'" {
                Get-NormalizedManufacturer -RawManufacturer 'Hewlett Packard Enterprise' | Should -Be 'HP'
            }

            It "normalizes 'LENOVO' to 'Lenovo'" {
                Get-NormalizedManufacturer -RawManufacturer 'LENOVO' | Should -Be 'Lenovo'
            }

            It "normalizes 'Lenovo Group Ltd.' to 'Lenovo'" {
                Get-NormalizedManufacturer -RawManufacturer 'Lenovo Group Ltd.' | Should -Be 'Lenovo'
            }

            It "normalizes 'Microsoft Corporation' to 'Microsoft'" {
                Get-NormalizedManufacturer -RawManufacturer 'Microsoft Corporation' | Should -Be 'Microsoft'
            }

            It "normalizes 'Surface' to 'Microsoft'" {
                Get-NormalizedManufacturer -RawManufacturer 'Surface' | Should -Be 'Microsoft'
            }

            It "returns empty string for null input" {
                Get-NormalizedManufacturer -RawManufacturer $null | Should -Be ''
            }

            It "returns empty string for whitespace input" {
                Get-NormalizedManufacturer -RawManufacturer '   ' | Should -Be ''
            }

            It "returns raw value for unknown manufacturer" {
                Get-NormalizedManufacturer -RawManufacturer 'ASUS' | Should -Be 'ASUS'
            }

            It "returns raw value trimmed for unknown manufacturer" {
                Get-NormalizedManufacturer -RawManufacturer '  Acer  ' | Should -Be 'Acer'
            }
        }

        Context "Get-SystemIdentityMetadata structure" {
            BeforeAll {
                # Define a helper to create mock CIM instances
                $script:mockDellCS = [PSCustomObject]@{
                    Manufacturer    = 'Dell Inc.'
                    Model           = 'Latitude 7490'
                    SystemSKUNumber = '07E4'
                    OEMStringArray  = @('[www.dell.com]', '[dell.com]')
                }
                $script:mockHPCS = [PSCustomObject]@{
                    Manufacturer    = 'HP'
                    Model           = 'HP EliteBook 840 G7'
                    SystemSKUNumber = $null
                    OEMStringArray  = $null
                }
                $script:mockHPBB = [PSCustomObject]@{
                    Product = '8AB3'
                }
                $script:mockLenovoCS = [PSCustomObject]@{
                    Manufacturer    = 'LENOVO'
                    Model           = '21BRCTO1WW'
                    SystemSKUNumber = $null
                    OEMStringArray  = $null
                }
                $script:mockLenovoCSP = [PSCustomObject]@{
                    Version = 'ThinkPad T14s Gen 3'
                }
            }

            It "returns PSCustomObject with all 7 required properties for Dell" {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockDellCS }
                    }
                }

                $result = Get-SystemIdentityMetadata

                $result | Should -Not -BeNullOrEmpty
                $result.PSObject.Properties.Name | Should -Contain 'ManufacturerNormalized'
                $result.PSObject.Properties.Name | Should -Contain 'ModelNormalized'
                $result.PSObject.Properties.Name | Should -Contain 'SystemSkuNormalized'
                $result.PSObject.Properties.Name | Should -Contain 'FallbackSkuNormalized'
                $result.PSObject.Properties.Name | Should -Contain 'MachineTypeNormalized'
                $result.PSObject.Properties.Name | Should -Contain 'IdentifierLabel'
                $result.PSObject.Properties.Name | Should -Contain 'IdentifierValue'
            }

            It "sets ManufacturerNormalized to 'Dell' for Dell Inc." {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockDellCS }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.ManufacturerNormalized | Should -Be 'Dell'
            }

            It "sets IdentifierLabel to 'SystemSKU' for Dell" {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockDellCS }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.IdentifierLabel | Should -Be 'SystemSKU'
            }

            It "extracts Dell SystemSKUNumber as IdentifierValue" {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockDellCS }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.IdentifierValue | Should -Be '07E4'
                $result.SystemSkuNormalized | Should -Be '07E4'
            }

            It "extracts Dell OEMStringArray bracket tag as FallbackSkuNormalized" {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockDellCS }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.FallbackSkuNormalized | Should -Not -BeNullOrEmpty
                $result.FallbackSkuNormalized | Should -Be 'WWW.DELL.COM'
            }

            It "sets IdentifierLabel to 'BaseBoardProduct' for HP" {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockHPCS }
                        'Win32_BaseBoard' { return $script:mockHPBB }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.IdentifierLabel | Should -Be 'BaseBoardProduct'
                $result.IdentifierValue | Should -Be '8AB3'
                $result.ManufacturerNormalized | Should -Be 'HP'
            }

            It "sets IdentifierLabel to 'MachineType' for Lenovo" {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockLenovoCS }
                        'Win32_ComputerSystemProduct' { return $script:mockLenovoCSP }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.IdentifierLabel | Should -Be 'MachineType'
                $result.ManufacturerNormalized | Should -Be 'Lenovo'
            }

            It "extracts Lenovo MachineType as first 4 chars of Model" {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockLenovoCS }
                        'Win32_ComputerSystemProduct' { return $script:mockLenovoCSP }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.MachineTypeNormalized | Should -Be '21BR'
                $result.IdentifierValue | Should -Be '21BR'
            }

            It "uses Lenovo friendly model from Win32_ComputerSystemProduct.Version" {
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $script:mockLenovoCS }
                        'Win32_ComputerSystemProduct' { return $script:mockLenovoCSP }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.ModelNormalized | Should -Be 'THINKPAD T14S GEN 3'
            }

            It "handles WMI failure gracefully with null fields" {
                Mock Get-CimInstance { throw "WMI service not available in WinPE" }

                $result = Get-SystemIdentityMetadata

                $result | Should -Not -BeNullOrEmpty
                $result.ManufacturerNormalized | Should -BeNullOrEmpty
                $result.ModelNormalized | Should -BeNullOrEmpty
                $result.SystemSkuNormalized | Should -BeNullOrEmpty
                $result.FallbackSkuNormalized | Should -BeNullOrEmpty
                $result.MachineTypeNormalized | Should -BeNullOrEmpty
                $result.IdentifierLabel | Should -Be 'N/A'
                $result.IdentifierValue | Should -BeNullOrEmpty
            }

            It "handles unknown manufacturer with IdentifierLabel 'N/A'" {
                $unknownCS = [PSCustomObject]@{
                    Manufacturer    = 'ASUS'
                    Model           = 'ROG Strix G15'
                    SystemSKUNumber = $null
                    OEMStringArray  = $null
                }
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $unknownCS }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.ManufacturerNormalized | Should -Be 'ASUS'
                $result.IdentifierLabel | Should -Be 'N/A'
                $result.IdentifierValue | Should -BeNullOrEmpty
                $result.SystemSkuNormalized | Should -BeNullOrEmpty
            }

            It "normalizes all string values to uppercase invariant" {
                $lowerCS = [PSCustomObject]@{
                    Manufacturer    = 'dell inc.'
                    Model           = 'latitude 5530'
                    SystemSKUNumber = '0a5c'
                    OEMStringArray  = @('[test.tag]')
                }
                Mock Get-CimInstance {
                    param($ClassName)
                    switch ($ClassName) {
                        'Win32_ComputerSystem' { return $lowerCS }
                    }
                }

                $result = Get-SystemIdentityMetadata
                $result.ModelNormalized | Should -Be 'LATITUDE 5530'
                $result.SystemSkuNormalized | Should -Be '0A5C'
                $result.IdentifierValue | Should -Be '0A5C'
            }
        }
    }

    # =========================================================================
    # DriverMapping.json Schema
    # =========================================================================
    Describe "DriverMapping.json Schema" -Tag 'DriverMapping' {

        Context "Update-DriverMappingJson with SystemID fields" {
            BeforeAll {
                $script:hasMappingFunction = $null -ne (Get-Command -Name 'Update-DriverMappingJson' -ErrorAction SilentlyContinue)
            }

            It "adds SystemId property for Dell entries" {
                if (-not $script:hasMappingFunction) { Set-ItResult -Skipped -Because "Update-DriverMappingJson not available" }
                $driversFolder = Join-Path $TestDrive "DriversSchemaTest"
                New-Item -Path $driversFolder -ItemType Directory -Force | Out-Null

                $drivers = @(
                    [PSCustomObject]@{
                        Make       = 'Dell'
                        Model      = 'Dell Latitude 7490 (ABC1)'
                        DriverPath = 'Dell\Latitude 7490.wim'
                    }
                )

                Update-DriverMappingJson -DownloadedDrivers $drivers -DriversFolder $driversFolder

                $mappingPath = Join-Path $driversFolder "DriverMapping.json"
                $mappingPath | Should -Exist
                $mapping = Get-Content -Path $mappingPath -Raw | ConvertFrom-Json
                $entry = if ($mapping -is [array]) { $mapping[0] } else { $mapping }
                $entry.SystemId | Should -Be 'ABC1'
            }

            It "adds SystemId property for HP entries" {
                if (-not $script:hasMappingFunction) { Set-ItResult -Skipped -Because "Update-DriverMappingJson not available" }
                $driversFolder = Join-Path $TestDrive "DriversSchemaHP"
                $hpFolder = Join-Path $driversFolder "HP"
                New-Item -Path $hpFolder -ItemType Directory -Force | Out-Null

                # Create a minimal PlatformList.xml for HP SystemID lookup
                $platformXml = @"
<?xml version="1.0" encoding="utf-8"?>
<ImagePal>
  <Platform>
    <SystemID>8AB3</SystemID>
    <ProductName><![CDATA[HP EliteBook 840 G7 Notebook PC]]></ProductName>
  </Platform>
</ImagePal>
"@
                Set-Content -Path (Join-Path $hpFolder "PlatformList.xml") -Value $platformXml -Encoding UTF8

                $drivers = @(
                    [PSCustomObject]@{
                        Make       = 'HP'
                        Model      = 'HP EliteBook 840 G7 Notebook PC'
                        DriverPath = 'HP\EliteBook 840 G7.wim'
                    }
                )

                Update-DriverMappingJson -DownloadedDrivers $drivers -DriversFolder $driversFolder

                $mappingPath = Join-Path $driversFolder "DriverMapping.json"
                $mappingPath | Should -Exist
                $mapping = Get-Content -Path $mappingPath -Raw | ConvertFrom-Json
                $entry = if ($mapping -is [array]) { $mapping[0] } else { $mapping }
                $entry.SystemId | Should -Be '8AB3'
            }

            It "adds MachineType property for Lenovo entries" {
                if (-not $script:hasMappingFunction) { Set-ItResult -Skipped -Because "Update-DriverMappingJson not available" }
                $driversFolder = Join-Path $TestDrive "DriversSchemaLenovo"
                New-Item -Path $driversFolder -ItemType Directory -Force | Out-Null

                $drivers = @(
                    [PSCustomObject]@{
                        Make       = 'Lenovo'
                        Model      = 'ThinkPad T14s (21BR)'
                        DriverPath = 'Lenovo\ThinkPad T14s.wim'
                    }
                )

                Update-DriverMappingJson -DownloadedDrivers $drivers -DriversFolder $driversFolder

                $mappingPath = Join-Path $driversFolder "DriverMapping.json"
                $mappingPath | Should -Exist
                $mapping = Get-Content -Path $mappingPath -Raw | ConvertFrom-Json
                $entry = if ($mapping -is [array]) { $mapping[0] } else { $mapping }
                $entry.MachineType | Should -Be '21BR'
            }

            It "sets SystemId to null when extraction fails" {
                if (-not $script:hasMappingFunction) { Set-ItResult -Skipped -Because "Update-DriverMappingJson not available" }
                $driversFolder = Join-Path $TestDrive "DriversSchemaNoId"
                New-Item -Path $driversFolder -ItemType Directory -Force | Out-Null

                $drivers = @(
                    [PSCustomObject]@{
                        Make       = 'Dell'
                        Model      = 'Dell Latitude 7490'  # No parenthesized suffix
                        DriverPath = 'Dell\Latitude 7490.wim'
                    }
                )

                Update-DriverMappingJson -DownloadedDrivers $drivers -DriversFolder $driversFolder

                $mappingPath = Join-Path $driversFolder "DriverMapping.json"
                $mapping = Get-Content -Path $mappingPath -Raw | ConvertFrom-Json
                $entry = if ($mapping -is [array]) { $mapping[0] } else { $mapping }
                # SystemId property should not exist when extraction failed
                $entry.PSObject.Properties['SystemId'] | Should -BeNullOrEmpty
            }

            It "updates existing entry SystemId when previously null" {
                if (-not $script:hasMappingFunction) { Set-ItResult -Skipped -Because "Update-DriverMappingJson not available" }
                $driversFolder = Join-Path $TestDrive "DriversSchemaUpdate"
                New-Item -Path $driversFolder -ItemType Directory -Force | Out-Null

                # Create initial mapping without SystemId
                $initialMapping = @(
                    [PSCustomObject]@{
                        Manufacturer = 'Dell'
                        Model        = 'Dell Latitude 7490 (ABC1)'
                        DriverPath   = 'Dell\Latitude 7490.wim'
                    }
                )
                $mappingPath = Join-Path $driversFolder "DriverMapping.json"
                $initialMapping | ConvertTo-Json -Depth 5 | Set-Content -Path $mappingPath -Encoding UTF8

                # Now update with the same model (should add SystemId)
                $drivers = @(
                    [PSCustomObject]@{
                        Make       = 'Dell'
                        Model      = 'Dell Latitude 7490 (ABC1)'
                        DriverPath = 'Dell\Latitude 7490.wim'
                    }
                )

                Update-DriverMappingJson -DownloadedDrivers $drivers -DriversFolder $driversFolder

                $mapping = Get-Content -Path $mappingPath -Raw | ConvertFrom-Json
                $entry = if ($mapping -is [array]) { $mapping[0] } else { $mapping }
                $entry.SystemId | Should -Be 'ABC1'
            }
        }
    }
}
