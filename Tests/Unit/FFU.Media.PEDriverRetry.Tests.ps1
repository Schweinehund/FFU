#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for PE driver retry logic in FFU.Media module

.DESCRIPTION
    Tests for Phase 41 Plan 02 requirements (DRV-07).
    Verifies:
    1. [PE] prefix used for structured logging
    2. Retry loop with maxRetries variable exists
    3. Transient error detection via regex pattern
    4. Summary count logging after injection
    5. WARNING log for partial failures
    6. Add-WindowsDriver uses -ErrorAction Stop

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Media.PEDriverRetry.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # AST analysis of FFU.Media.psm1
    $modulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Media\FFU.Media.psm1'
    if (-not (Test-Path $modulePath)) {
        throw "FFU.Media.psm1 not found at $modulePath"
    }
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$null, [ref]$null)
}

Describe 'PE Driver Retry Logic in FFU.Media' {
    It 'Uses [PE] prefix for structured logging' {
        $peLogNodes = $ast.FindAll({
            param($node)
            $node.Extent.Text -match '\[PE\]'
        }, $true)
        $peLogNodes.Count | Should -BeGreaterOrEqual 3 -Because '[PE] prefix should be used for source, injection result, and completion logging'
    }

    It 'Implements retry loop with maxRetries variable' {
        $retryNodes = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Extent.Text -match 'maxRetries'
        }, $true)
        $retryNodes.Count | Should -BeGreaterThan 0 -Because 'maxRetries variable should be defined for retry logic'
    }

    It 'Detects transient errors via regex pattern' {
        $transientNodes = $ast.FindAll({
            param($node)
            $node.Extent.Text -match 'isTransient'
        }, $true)
        $transientNodes.Count | Should -BeGreaterThan 0 -Because 'Transient error detection variable should exist'
    }

    It 'Logs summary count after injection' {
        $summaryNodes = $ast.FindAll({
            param($node)
            $node.Extent.Text -match 'Injection result'
        }, $true)
        $summaryNodes.Count | Should -BeGreaterThan 0 -Because 'Summary count should be logged after PE driver injection'
    }

    It 'Logs WARNING for partial failure' {
        $warningNodes = $ast.FindAll({
            param($node)
            $node.Extent.Text -match 'WARNING.*PE driver injection'
        }, $true)
        $warningNodes.Count | Should -BeGreaterThan 0 -Because 'WARNING should be logged for partial PE driver injection failures'
    }

    It 'Uses Add-WindowsDriver with -ErrorAction Stop for explicit error handling' {
        $dismNodes = $ast.FindAll({
            param($node)
            $node.Extent.Text -match 'Add-WindowsDriver.*ErrorAction\s+Stop'
        }, $true)
        $dismNodes.Count | Should -BeGreaterThan 0 -Because 'Add-WindowsDriver should use -ErrorAction Stop for proper error handling'
    }
}

Describe 'PE Driver Retry Logic in Create-PEMedia' {
    BeforeAll {
        $legacyPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Create-PEMedia.ps1'
        if (Test-Path $legacyPath) {
            $legacyAst = [System.Management.Automation.Language.Parser]::ParseFile($legacyPath, [ref]$null, [ref]$null)
        }
        else {
            $legacyAst = $null
        }
    }

    It 'Uses [PE] prefix for structured logging' -Skip:($null -eq $legacyAst) {
        $peLogNodes = $legacyAst.FindAll({
            param($node)
            $node.Extent.Text -match '\[PE\]'
        }, $true)
        $peLogNodes.Count | Should -BeGreaterOrEqual 3 -Because '[PE] prefix should be used in legacy script'
    }

    It 'Implements retry loop with maxRetries variable' -Skip:($null -eq $legacyAst) {
        $retryNodes = $legacyAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Extent.Text -match 'maxRetries'
        }, $true)
        $retryNodes.Count | Should -BeGreaterThan 0 -Because 'maxRetries should exist in legacy script'
    }

    It 'Logs summary count after injection' -Skip:($null -eq $legacyAst) {
        $summaryNodes = $legacyAst.FindAll({
            param($node)
            $node.Extent.Text -match 'Injection result'
        }, $true)
        $summaryNodes.Count | Should -BeGreaterThan 0 -Because 'Summary count should be logged in legacy script'
    }
}
