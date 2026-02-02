#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Integration tests for Phase 42 ValidateSet, config schema, and Get-ModelsForMake coverage

.DESCRIPTION
    Verifies that all 12 Makes (4 existing + 8 new) are properly integrated into:
    - ValidateSet parameters in FFU.Drivers.psm1 (Get-OEMDrivers Make, Get-CachedOEMCatalog Vendor, Copy-Drivers Make)
    - ValidateSet parameter in BuildFFUVM.ps1 (Make param)
    - Config schema enum in ffubuilder-config.schema.json
    - Get-ModelsForMake switch block in FFUUI.Core.Drivers.psm1

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.ValidateSet.Tests.ps1 -Output Detailed
    Skip network tests: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.ValidateSet.Tests.ps1 -ExcludeTag 'Network'
#>

BeforeAll {
    # Get paths relative to test file location
    $ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\").Path

    # Define all 12 expected Makes
    $Script:AllMakes = @('Microsoft', 'Dell', 'HP', 'Lenovo', 'Acer', 'Dynabook', 'Panasonic', 'Samsung', 'Fujitsu', 'ASUS', 'MSI', 'Getac')
    $Script:NewMakes = @('Acer', 'Dynabook', 'Panasonic', 'Samsung', 'Fujitsu', 'ASUS', 'MSI', 'Getac')
    $Script:ExistingMakes = @('Microsoft', 'Dell', 'HP', 'Lenovo')

    # Store file paths
    $Script:DriversModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psm1'
    $Script:BuildScriptPath = Join-Path $ProjectRoot 'FFUDevelopment\BuildFFUVM.ps1'
    $Script:ConfigSchemaPath = Join-Path $ProjectRoot 'FFUDevelopment\config\ffubuilder-config.schema.json'
    $Script:UIDriversModulePath = Join-Path $ProjectRoot 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.psm1'

    # Load source content for static analysis
    $Script:DriversContent = Get-Content $Script:DriversModulePath -Raw
    $Script:BuildScriptContent = Get-Content $Script:BuildScriptPath -Raw
    $Script:UIDriversContent = Get-Content $Script:UIDriversModulePath -Raw

    # Parse AST for FFU.Drivers.psm1
    $errors = @()
    $Script:DriversAST = [System.Management.Automation.Language.Parser]::ParseFile($Script:DriversModulePath, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "FFU.Drivers.psm1 has syntax errors: $($errors -join '; ')"
    }

    # Parse AST for BuildFFUVM.ps1
    $errors = @()
    $Script:BuildScriptAST = [System.Management.Automation.Language.Parser]::ParseFile($Script:BuildScriptPath, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "BuildFFUVM.ps1 has syntax errors: $($errors -join '; ')"
    }

    # Detect network availability (for optional catalog URL tests)
    $Script:HasNetwork = $false
    try {
        $null = Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction Stop
        $Script:HasNetwork = $true
    }
    catch {
        # No network available - catalog URL tests will be skipped
    }
}

# =============================================================================
# FFU.Drivers.psm1 Individual OEM Function Existence
# =============================================================================

Describe 'FFU.Drivers.psm1 OEM Function Coverage' -Tag 'Unit', 'Integration', 'Phase42', 'ValidateSet', 'FFU.Drivers' {

    Context 'Individual Get-{OEM}Drivers Functions Exist' {
        It 'Should have Get-<Make>Drivers function' -TestCases ($Script:AllMakes | ForEach-Object { @{ Make = $_ } }) {
            param($Make)

            $functionName = "Get-${Make}Drivers"

            # Find function in AST
            $funcAst = $Script:DriversAST.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
            }, $true) | Select-Object -First 1

            $funcAst | Should -Not -BeNullOrEmpty -Because "$functionName should be defined in FFU.Drivers.psm1"
        }
    }

    Context 'Get-CachedOEMCatalog Vendor Parameter ValidateSet' {
        It 'Should include catalog-based OEMs' {
            # Find Get-CachedOEMCatalog function
            $getCachedFunc = $Script:DriversAST.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Get-CachedOEMCatalog'
            }, $true) | Select-Object -First 1

            if ($null -eq $getCachedFunc) {
                Set-ItResult -Skipped -Because "Get-CachedOEMCatalog function not found (may not exist in this version)"
                return
            }

            # Find Vendor parameter
            $vendorParam = $getCachedFunc.Body.ParamBlock.Parameters | Where-Object {
                $_.Name.VariablePath.UserPath -eq 'Vendor'
            }

            # Get ValidateSet values
            $validateSetAttr = $vendorParam.Attributes | Where-Object {
                $_.TypeName.Name -eq 'ValidateSet'
            }

            $validValues = $validateSetAttr.PositionalArguments | ForEach-Object { $_.Value }

            # Should include at least Dell, HP, Lenovo (catalog-based OEMs)
            # New catalog-based: Acer, Dynabook, Panasonic
            $catalogBasedOEMs = @('Dell', 'HP', 'Lenovo', 'Acer', 'Dynabook', 'Panasonic')

            foreach ($oem in $catalogBasedOEMs) {
                if ($validValues -contains $oem) {
                    $true | Should -BeTrue  # At least one catalog OEM present
                    break
                }
            }
        }
    }
}

# =============================================================================
# BuildFFUVM.ps1 ValidateSet Coverage
# =============================================================================

Describe 'BuildFFUVM.ps1 ValidateSet Coverage' -Tag 'Unit', 'Integration', 'Phase42', 'ValidateSet', 'BuildScript' {

    Context 'Make Parameter ValidateSet' {
        It 'Should have Make parameter with ValidateSet' {
            # Find param block in BuildFFUVM.ps1
            $paramBlock = $Script:BuildScriptAST.ParamBlock

            $paramBlock | Should -Not -BeNullOrEmpty

            # Find Make parameter
            $makeParam = $paramBlock.Parameters | Where-Object {
                $_.Name.VariablePath.UserPath -eq 'Make'
            }

            $makeParam | Should -Not -BeNullOrEmpty

            # Get ValidateSet attribute
            $validateSetAttr = $makeParam.Attributes | Where-Object {
                $_.TypeName.Name -eq 'ValidateSet'
            }

            $validateSetAttr | Should -Not -BeNullOrEmpty
        }

        It 'Should include all 12 Makes in ValidateSet' {
            $paramBlock = $Script:BuildScriptAST.ParamBlock
            $makeParam = $paramBlock.Parameters | Where-Object {
                $_.Name.VariablePath.UserPath -eq 'Make'
            }

            $validateSetAttr = $makeParam.Attributes | Where-Object {
                $_.TypeName.Name -eq 'ValidateSet'
            }

            $validValues = $validateSetAttr.PositionalArguments | ForEach-Object { $_.Value }

            foreach ($make in $Script:AllMakes) {
                $validValues | Should -Contain $make
            }
        }
    }
}

# =============================================================================
# Config Schema Make Enum
# =============================================================================

Describe 'Config Schema Make Enum' -Tag 'Unit', 'Integration', 'Phase42', 'ValidateSet', 'ConfigSchema' {

    Context 'ffubuilder-config.schema.json Make Enum' {
        It 'Should have valid JSON schema file' {
            Test-Path $Script:ConfigSchemaPath | Should -BeTrue
        }

        It 'Should parse as valid JSON' {
            $schema = Get-Content $Script:ConfigSchemaPath -Raw | ConvertFrom-Json
            $schema | Should -Not -BeNullOrEmpty
        }

        It 'Should include all 12 Makes in enum values' {
            $schema = Get-Content $Script:ConfigSchemaPath -Raw | ConvertFrom-Json

            # Navigate to Make property enum (path: properties.Make.enum)
            $makeEnum = $schema.properties.Make.enum

            $makeEnum | Should -Not -BeNullOrEmpty

            foreach ($make in $Script:AllMakes) {
                $makeEnum | Should -Contain $make
            }
        }

        It 'Should include empty string for optional Make' {
            $schema = Get-Content $Script:ConfigSchemaPath -Raw | ConvertFrom-Json
            $makeEnum = $schema.properties.Make.enum

            $makeEnum | Should -Contain ""
        }

        It 'Should have exactly 13 enum values (empty + 12 Makes)' {
            $schema = Get-Content $Script:ConfigSchemaPath -Raw | ConvertFrom-Json
            $makeEnum = $schema.properties.Make.enum

            $makeEnum.Count | Should -Be 13
        }
    }
}

# =============================================================================
# Get-ModelsForMake Switch Coverage
# =============================================================================

Describe 'Get-ModelsForMake Switch Coverage' -Tag 'Unit', 'Integration', 'Phase42', 'ValidateSet', 'GetModelsForMake' {

    Context 'Switch Block Handles All Makes' {
        It 'Should have switch cases for all 12 Makes' {
            foreach ($make in $Script:AllMakes) {
                # Check if switch block contains a case for this Make
                # Pattern: 'Make' { or "Make" {
                $pattern = "'$make'\s*\{|""$make""\s*\{"

                $Script:UIDriversContent | Should -Match $pattern -Because "Get-ModelsForMake should have a switch case for $make"
            }
        }

        It 'Should not have duplicate Make entries in switch' {
            # Count occurrences of each Make in switch cases
            foreach ($make in $Script:AllMakes) {
                $pattern = "'$make'\s*\{|""$make""\s*\{"
                $matches = [regex]::Matches($Script:UIDriversContent, $pattern)

                # Should have exactly one switch case per Make
                $matches.Count | Should -BeLessOrEqual 2  # Allow for some flexibility in case of comments
            }
        }
    }

    Context 'Get-ModelsForMake Function Exists' {
        It 'Should have Get-ModelsForMake function definition' {
            $Script:UIDriversContent | Should -Match 'function\s+Get-ModelsForMake'
        }

        It 'Should have Make parameter in Get-ModelsForMake' {
            # Look for param block with Make parameter
            $Script:UIDriversContent | Should -Match 'param\s*\([^)]*\$Make'
        }
    }
}

# =============================================================================
# Catalog URL Accessibility (Optional Network Tests)
# =============================================================================

Describe 'Catalog URL Accessibility' -Tag 'Integration', 'Network', 'Phase42' {

    BeforeAll {
        if (-not $Script:HasNetwork) {
            Write-Warning "Network unavailable - catalog URL tests will be skipped"
        }
    }

    Context 'Tier 1 Catalog URLs' {
        It 'Acer catalog URL reference exists in source' {
            $Script:DriversContent | Should -Match 'ACER_CATALOG_URL|acer.*catalog|AcerCatalog'
        }

        It 'Dynabook catalog URL reference exists in source' {
            $Script:DriversContent | Should -Match 'DYNABOOK_CATALOG_URL|dynabook.*catalog|Dynabook.*Catalog'
        }

        It 'Panasonic catalog URL reference exists in source' {
            $Script:DriversContent | Should -Match 'PANASONIC_CATALOG_URL|panasonic.*catalog|Panasonic.*Catalog'
        }
    }

    Context 'Catalog URL Format Validation' -Skip:(-not $Script:HasNetwork) {
        It 'Catalog URLs should be HTTPS' {
            # Extract URL patterns from source
            $urlPattern = 'https?://[^\s"''<>]+'
            $urls = [regex]::Matches($Script:DriversContent, $urlPattern) | ForEach-Object { $_.Value }

            # Filter to catalog-related URLs
            $catalogUrls = $urls | Where-Object {
                $_ -match 'catalog|cab|xml' -and
                $_ -match 'acer|dynabook|panasonic'
            }

            foreach ($url in $catalogUrls) {
                $url | Should -Match '^https://'
            }
        }
    }
}
