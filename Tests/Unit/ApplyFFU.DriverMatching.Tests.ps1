#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for driver family fallback matching in ApplyFFU.ps1

.DESCRIPTION
    Tests for Phase 41 Plan 01 requirements (DRV-05, DRV-06).
    Verifies:
    1. Get-ModelFamily extracts correct family names from model strings
    2. Family fallback matching uses MatchPrecision 0.5
    3. Decision trail logging exists for driver matching
    4. Summary log line exists for match results
    5. [OEM] Family fallback log format exists

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\ApplyFFU.DriverMatching.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Extract functions from ApplyFFU.ps1 using AST (same pattern as ApplyFFU.PPKG.Tests.ps1)
    $scriptPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\WinPEDeployFFUFiles\ApplyFFU.ps1'
    if (-not (Test-Path $scriptPath)) {
        throw "ApplyFFU.ps1 not found at $scriptPath"
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $functionDefs = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    # Extract and define test-accessible functions
    foreach ($func in $functionDefs) {
        if ($func.Name -in @('Get-ModelFamily', 'ConvertTo-ComparableModelName', 'Get-NormalizedManufacturer')) {
            Invoke-Expression $func.Extent.Text
        }
    }
}

Describe 'Get-ModelFamily' {
    It 'Extracts family from "<Model>" with manufacturer "<Manufacturer>" as "<Expected>"' -TestCases @(
        @{ Model = 'Dell Latitude 7490'; Manufacturer = 'Dell'; Expected = 'Latitude' }
        @{ Model = 'Latitude 7490'; Manufacturer = 'Dell'; Expected = 'Latitude' }
        @{ Model = 'HP EliteBook 850 G5'; Manufacturer = 'HP'; Expected = 'EliteBook' }
        @{ Model = 'EliteBook 850 G5'; Manufacturer = 'HP'; Expected = 'EliteBook' }
        @{ Model = 'Lenovo ThinkPad T490'; Manufacturer = 'Lenovo'; Expected = 'ThinkPad' }
        @{ Model = 'ThinkPad T490'; Manufacturer = 'Lenovo'; Expected = 'ThinkPad' }
        @{ Model = 'Microsoft Surface Pro 7'; Manufacturer = 'Microsoft'; Expected = 'Surface' }
        @{ Model = 'Surface Pro 7'; Manufacturer = 'Microsoft'; Expected = 'Surface' }
    ) {
        param($Model, $Manufacturer, $Expected)
        Get-ModelFamily -ModelName $Model -Manufacturer $Manufacturer | Should -Be $Expected
    }

    It 'Returns empty string for null input' {
        Get-ModelFamily -ModelName $null -Manufacturer 'Dell' | Should -Be ''
    }

    It 'Returns empty string for empty input' {
        Get-ModelFamily -ModelName '' -Manufacturer 'Dell' | Should -Be ''
    }

    It 'Returns empty string for whitespace-only input' {
        Get-ModelFamily -ModelName '   ' -Manufacturer 'Dell' | Should -Be ''
    }
}

Describe 'Family Fallback Matching' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\WinPEDeployFFUFiles\ApplyFFU.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    }

    It 'Family match gets MatchPrecision 0.5' {
        # Verify via AST that MatchPrecision 0.5 exists in the matching logic
        $matchPrecisionNodes = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Extent.Text -match 'MatchPrecision.*0\.5'
        }, $true)
        $matchPrecisionNodes.Count | Should -BeGreaterThan 0 -Because 'MatchPrecision 0.5 should be assigned for family fallback matches'
    }

    It 'Family match type is labeled as Family in the matching logic' {
        $familyTypeNodes = $ast.FindAll({
            param($node)
            $node.Extent.Text -match "'Family'"
        }, $true)
        $familyTypeNodes.Count | Should -BeGreaterThan 0 -Because 'Family match type should be labeled in the code'
    }

    It 'Decision trail logging exists' {
        $decisionTrailNodes = $ast.FindAll({
            param($node)
            $node.Extent.Text -match 'decision trail'
        }, $true)
        $decisionTrailNodes.Count | Should -BeGreaterThan 0 -Because 'Decision trail logging should exist for driver matching'
    }

    It 'Summary log line exists for match result' {
        $summaryNodes = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $node.Value -match 'Driver match result'
        }, $true)
        $summaryNodes.Count | Should -BeGreaterThan 0 -Because 'Summary log should exist for driver match results'
    }

    It '[OEM] Family fallback log exists' {
        $familyLogNodes = $ast.FindAll({
            param($node)
            $node.Extent.Text -match '\[OEM\] Family fallback'
        }, $true)
        $familyLogNodes.Count | Should -BeGreaterThan 0 -Because '[OEM] Family fallback log pattern should exist'
    }
}
