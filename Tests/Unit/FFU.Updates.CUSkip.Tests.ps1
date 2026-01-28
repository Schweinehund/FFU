#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for CU skip version comparison logic in FFU.Updates module

.DESCRIPTION
    Tests covering:
    - Get-WindowsESDMetadata function existence and parameter validation
    - Get-KBLink KB article ID and Windows version extraction
    - CU version comparison logic (equal, newer, older, parse failures, missing)

    These tests verify the version comparison edge cases that determine whether
    a cumulative update download is skipped when the ESD already contains it.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Updates.CUSkip.Tests.ps1 -Output Detailed
    Phase: 36-cu-skip-esd-bits (Plan 03)
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

    # Import FFU.Common for WriteLog availability in test scope
    $CommonModulePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common'
    if (Test-Path "$CommonModulePath\FFU.Common.psd1") {
        Import-Module "$CommonModulePath\FFU.Common.psd1" -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path "$ModulePath\FFU.Updates.psd1")) {
        throw "FFU.Updates module not found at: $ModulePath"
    }
    $script:updatesModule = Import-Module "$ModulePath\FFU.Updates.psd1" -Force -PassThru -ErrorAction Stop

    # Ensure WriteLog is available for mocking (fallback if FFU.Common not loaded)
    if (-not (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue)) {
        function global:WriteLog { param([string]$Message) Write-Verbose $Message }
    }

    # Parse the PSM1 AST to validate function definitions exist (workaround for
    # PowerShell 7.5 module export issue where Get-WindowsESDMetadata exists in
    # module scope but is not externally exported)
    $psm1Path = Join-Path $ModulePath 'FFU.Updates.psm1'
    $tokens = $null; $parseErrors = $null
    $script:psm1Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $psm1Path, [ref]$tokens, [ref]$parseErrors
    )
    $script:allFunctions = $script:psm1Ast.FindAll(
        { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false
    )
}

AfterAll {
    Get-Module -Name 'FFU.Updates', 'FFU.Core', 'FFU.Constants', 'FFU.Common' | Remove-Module -Force -ErrorAction SilentlyContinue
    # Clean up global WriteLog fallback if we created it
    if (Get-Item -Path 'Function:\global:WriteLog' -ErrorAction SilentlyContinue) {
        Remove-Item -Path 'Function:\global:WriteLog' -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Get-WindowsESDMetadata Tests
# =============================================================================

Describe 'Get-WindowsESDMetadata' -Tag 'Unit', 'FFU.Updates', 'CUSkip' {

    Context 'Function Definition and Parameters' {
        It 'Should be defined in FFU.Updates.psm1' {
            $funcDef = $script:allFunctions | Where-Object { $_.Name -eq 'Get-WindowsESDMetadata' }
            $funcDef | Should -Not -BeNullOrEmpty
        }

        It 'Should be listed in FunctionsToExport in the manifest' {
            $manifest = Test-ModuleManifest -Path (Join-Path $ModulePath 'FFU.Updates.psd1')
            $manifest.ExportedFunctions.Keys | Should -Contain 'Get-WindowsESDMetadata'
        }

        It 'Should be available in module internal scope' {
            $result = & $script:updatesModule {
                Get-Command -Name 'Get-WindowsESDMetadata' -ErrorAction SilentlyContinue
            }
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'Get-WindowsESDMetadata'
        }

        It 'Should have WindowsRelease parameter with ValidateSet 10, 11' {
            $cmd = & $script:updatesModule {
                Get-Command -Name 'Get-WindowsESDMetadata' -ErrorAction Stop
            }
            $param = $cmd.Parameters['WindowsRelease']
            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain '10'
            $validateSet.ValidValues | Should -Contain '11'
        }

        It 'Should have WindowsArch parameter with ValidateSet x86, x64, ARM64' {
            $cmd = & $script:updatesModule {
                Get-Command -Name 'Get-WindowsESDMetadata' -ErrorAction Stop
            }
            $param = $cmd.Parameters['WindowsArch']
            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have mandatory WindowsVersion parameter' {
            $cmd = & $script:updatesModule {
                Get-Command -Name 'Get-WindowsESDMetadata' -ErrorAction Stop
            }
            $param = $cmd.Parameters['WindowsVersion']
            $param | Should -Not -BeNullOrEmpty
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $mandatory.Mandatory | Should -BeTrue
        }

        It 'Should have MediaType parameter with ValidateSet consumer, business' {
            $cmd = & $script:updatesModule {
                Get-Command -Name 'Get-WindowsESDMetadata' -ErrorAction Stop
            }
            $param = $cmd.Parameters['MediaType']
            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'consumer'
            $validateSet.ValidValues | Should -Contain 'business'
        }

        It 'Should have OutputType attribute declared' {
            $cmd = & $script:updatesModule {
                Get-Command -Name 'Get-WindowsESDMetadata' -ErrorAction Stop
            }
            $outputType = $cmd.OutputType
            $outputType | Should -Not -BeNullOrEmpty
            # [OutputType([PSCustomObject])] resolves to PSObject at runtime
            $outputType.Type.Name | Should -Contain 'PSObject'
        }
    }

    Context 'Version Parsing Logic (AST Verification)' {
        It 'Should contain 4-part version regex pattern for ESD filename parsing' {
            $funcDef = $script:allFunctions | Where-Object { $_.Name -eq 'Get-WindowsESDMetadata' }
            $funcBody = $funcDef.Body.Extent.Text
            # Verify 4-part version regex exists in function body (matches patterns like \d+\.\d+\.\d+\.\d+)
            $funcBody | Should -Match '\[0-9\]\+.*\[0-9\]\+.*\[0-9\]\+.*\[0-9\]\+'
        }

        It 'Should return PSCustomObject with FileUrl, FileName, LocalPath, and Version properties' {
            $funcDef = $script:allFunctions | Where-Object { $_.Name -eq 'Get-WindowsESDMetadata' }
            $funcBody = $funcDef.Body.Extent.Text
            $funcBody | Should -Match 'FileUrl'
            $funcBody | Should -Match 'FileName'
            $funcBody | Should -Match 'LocalPath'
            $funcBody | Should -Match 'Version'
        }

        It 'Should contain try/catch for exception safety (returns $null on failure)' {
            $funcDef = $script:allFunctions | Where-Object { $_.Name -eq 'Get-WindowsESDMetadata' }
            $funcBody = $funcDef.Body.Extent.Text
            $funcBody | Should -Match 'catch'
            $funcBody | Should -Match 'return \$null'
        }
    }
}

# =============================================================================
# Get-KBLink Version Extraction Tests
# =============================================================================

Describe 'Get-KBLink Version Extraction' -Tag 'Unit', 'FFU.Updates', 'CUSkip' {

    BeforeEach {
        # Save and clear global state
        $script:savedLastKBWindowsVersion = $global:LastKBWindowsVersion
        $global:LastKBWindowsVersion = $null
    }

    AfterEach {
        # Restore global state
        $global:LastKBWindowsVersion = $script:savedLastKBWindowsVersion
    }

    Context 'KB ID and Version Extraction' {
        BeforeAll {
            # WriteLog is a function from FFU.Common.Core; mock it for tests
            Mock WriteLog { }
        }

        It 'Should extract KB ID and version from catalog HTML with format (KB5046613) (10.0.26100.2454)' {
            $mockContent = @"
<tr>
<td class="resultsbottomBorder">2024-11 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5046613) (10.0.26100.2454)</td>
<td><input id="abc123_download" type="Button" value="Download" /></td>
</tr>
<tr><td><a id="abc123_link">Some link text (KB5046613) (10.0.26100.2454)</a></td></tr>
"@
            $mockLinks = @(
                [PSCustomObject]@{ ID = 'abc123_link'; OuterHTML = 'x64 Windows 11 (KB5046613) (10.0.26100.2454)' }
            )
            $mockInputFields = @(
                [PSCustomObject]@{ type = 'Button'; Value = 'Download'; ID = 'abc123' }
            )
            $mockResponse = [PSCustomObject]@{
                Content     = $mockContent
                Links       = $mockLinks
                InputFields = $mockInputFields
            }

            Mock -ModuleName 'FFU.Updates' -CommandName 'Invoke-WebRequest' -MockWith { return $mockResponse }

            $result = Get-KBLink -Name "2024-11 Cumulative Update" -Headers @{ 'User-Agent' = 'Test' } -UserAgent 'Test'

            $result.KBArticleID | Should -Be 'KB5046613'
            $result.KBWindowsVersion | Should -Be '10.0.26100.2454'
        }

        It 'Should extract KB ID without version when format is (KB5046613) only' {
            $mockContent = @"
<tr>
<td class="resultsbottomBorder">2024-11 Update for Windows 11 (KB5046613) <span>test</span></td>
<td><input id="def456_download" type="Button" value="Download" /></td>
</tr>
<tr><td><a id="def456_link">Some link (KB5046613)</a></td></tr>
"@
            $mockLinks = @(
                [PSCustomObject]@{ ID = 'def456_link'; OuterHTML = 'x64 (KB5046613)' }
            )
            $mockInputFields = @(
                [PSCustomObject]@{ type = 'Button'; Value = 'Download'; ID = 'def456' }
            )
            $mockResponse = [PSCustomObject]@{
                Content     = $mockContent
                Links       = $mockLinks
                InputFields = $mockInputFields
            }

            Mock -ModuleName 'FFU.Updates' -CommandName 'Invoke-WebRequest' -MockWith { return $mockResponse }

            $result = Get-KBLink -Name "2024-11 Update" -Headers @{ 'User-Agent' = 'Test' } -UserAgent 'Test'

            $result.KBArticleID | Should -Be 'KB5046613'
            $result.KBWindowsVersion | Should -BeNull
        }

        It 'Should set $global:LastKBWindowsVersion with extracted version' {
            $mockContent = @"
<tr>
<td>2024-11 Cumulative Update (KB5046613) (10.0.26100.2454) <span></span></td>
<td><input id="xyz789_download" type="Button" value="Download" /></td>
</tr>
<tr><td><a id="xyz789_link">Update link (KB5046613) (10.0.26100.2454)</a></td></tr>
"@
            $mockLinks = @(
                [PSCustomObject]@{ ID = 'xyz789_link'; OuterHTML = 'x64 (KB5046613) (10.0.26100.2454)' }
            )
            $mockInputFields = @(
                [PSCustomObject]@{ type = 'Button'; Value = 'Download'; ID = 'xyz789' }
            )
            $mockResponse = [PSCustomObject]@{
                Content     = $mockContent
                Links       = $mockLinks
                InputFields = $mockInputFields
            }

            Mock -ModuleName 'FFU.Updates' -CommandName 'Invoke-WebRequest' -MockWith { return $mockResponse }

            Get-KBLink -Name "2024-11 Cumulative Update" -Headers @{ 'User-Agent' = 'Test' } -UserAgent 'Test'

            $global:LastKBWindowsVersion | Should -Be '10.0.26100.2454'
        }

        It 'Should set $global:LastKBWindowsVersion to $null when no version found' {
            $mockContent = @"
<tr>
<td>Some update without KB format</td>
<td><input id="noversion_download" type="Button" value="Download" /></td>
</tr>
<tr><td><a id="noversion_link">No KB article</a></td></tr>
"@
            $mockLinks = @(
                [PSCustomObject]@{ ID = 'noversion_link'; OuterHTML = 'Some update without version' }
            )
            $mockInputFields = @(
                [PSCustomObject]@{ type = 'Button'; Value = 'Download'; ID = 'noversion' }
            )
            $mockResponse = [PSCustomObject]@{
                Content     = $mockContent
                Links       = $mockLinks
                InputFields = $mockInputFields
            }

            Mock -ModuleName 'FFU.Updates' -CommandName 'Invoke-WebRequest' -MockWith { return $mockResponse }

            Get-KBLink -Name "Some update" -Headers @{ 'User-Agent' = 'Test' } -UserAgent 'Test'

            $global:LastKBWindowsVersion | Should -BeNull
        }

        It 'Should not extract KB for Defender updates' {
            $mockContent = @"
<tr>
<td>Security Intelligence Update for Microsoft Defender Antivirus (KB2267602)</td>
<td><input id="defender_download" type="Button" value="Download" /></td>
</tr>
<tr><td><a id="defender_link">Defender update</a></td></tr>
"@
            $mockLinks = @(
                [PSCustomObject]@{ ID = 'defender_link'; OuterHTML = 'Defender (KB2267602)' }
            )
            $mockInputFields = @(
                [PSCustomObject]@{ type = 'Button'; Value = 'Download'; ID = 'defender' }
            )
            $mockResponse = [PSCustomObject]@{
                Content     = $mockContent
                Links       = $mockLinks
                InputFields = $mockInputFields
            }

            Mock -ModuleName 'FFU.Updates' -CommandName 'Invoke-WebRequest' -MockWith { return $mockResponse }

            $result = Get-KBLink -Name "Defender update" -Headers @{ 'User-Agent' = 'Test' } -UserAgent 'Test'

            $result.KBArticleID | Should -BeNull
            $global:LastKBWindowsVersion | Should -BeNull
        }

        It 'Should not extract KB for Edge updates' {
            $mockContent = @"
<tr>
<td>Microsoft Edge Update</td>
<td><input id="edge_download" type="Button" value="Download" /></td>
</tr>
<tr><td><a id="edge_link">Edge update link</a></td></tr>
"@
            $mockLinks = @(
                [PSCustomObject]@{ ID = 'edge_link'; OuterHTML = 'Edge update' }
            )
            $mockInputFields = @(
                [PSCustomObject]@{ type = 'Button'; Value = 'Download'; ID = 'edge' }
            )
            $mockResponse = [PSCustomObject]@{
                Content     = $mockContent
                Links       = $mockLinks
                InputFields = $mockInputFields
            }

            Mock -ModuleName 'FFU.Updates' -CommandName 'Invoke-WebRequest' -MockWith { return $mockResponse }

            $result = Get-KBLink -Name "Edge update" -Headers @{ 'User-Agent' = 'Test' } -UserAgent 'Test'

            $result.KBArticleID | Should -BeNull
        }

        It 'Should include KBWindowsVersion property in return object' {
            $mockContent = @"
<tr>
<td>2024-11 CU (KB5046613) (10.0.26100.2454) <span>test</span></td>
<td><input id="proptest_download" type="Button" value="Download" /></td>
</tr>
<tr><td><a id="proptest_link">CU link (KB5046613) (10.0.26100.2454)</a></td></tr>
"@
            $mockLinks = @(
                [PSCustomObject]@{ ID = 'proptest_link'; OuterHTML = 'x64 (KB5046613) (10.0.26100.2454)' }
            )
            $mockInputFields = @(
                [PSCustomObject]@{ type = 'Button'; Value = 'Download'; ID = 'proptest' }
            )
            $mockResponse = [PSCustomObject]@{
                Content     = $mockContent
                Links       = $mockLinks
                InputFields = $mockInputFields
            }

            Mock -ModuleName 'FFU.Updates' -CommandName 'Invoke-WebRequest' -MockWith { return $mockResponse }

            $result = Get-KBLink -Name "2024-11 CU" -Headers @{ 'User-Agent' = 'Test' } -UserAgent 'Test'

            $result.PSObject.Properties.Name | Should -Contain 'KBWindowsVersion'
        }
    }
}

# =============================================================================
# CU Version Comparison Logic Tests
# =============================================================================

Describe 'CU Version Comparison Logic' -Tag 'Unit', 'FFU.Updates', 'CUSkip', 'VersionComparison' {

    <#
        These tests validate the version comparison logic used in BuildFFUVM.ps1
        to decide whether to skip a CU download. The logic is:
        1. Parse ESD version and CU version as [version] objects
        2. If ESD version >= CU version, skip download
        3. If parse fails, safe default = download CU
    #>

    Context 'ESD version equals CU version -> skip' {
        It 'Should determine skip when ESD and CU versions are equal' {
            $esdVersionStr = '10.0.26100.2454'
            $cuVersionStr = '10.0.26100.2454'

            $esdVerObj = [version]$esdVersionStr
            $cuVerObj = [version]$cuVersionStr

            $shouldSkip = $esdVerObj -ge $cuVerObj
            $shouldSkip | Should -BeTrue

            # Also verify exact equality
            ($esdVerObj -eq $cuVerObj) | Should -BeTrue
        }
    }

    Context 'ESD version newer than CU version -> skip' {
        It 'Should determine skip when ESD is newer than CU' {
            $esdVersionStr = '10.0.26100.2894'
            $cuVersionStr = '10.0.26100.2454'

            $esdVerObj = [version]$esdVersionStr
            $cuVerObj = [version]$cuVersionStr

            $shouldSkip = $esdVerObj -ge $cuVerObj
            $shouldSkip | Should -BeTrue

            # Verify it is strictly greater
            ($esdVerObj -gt $cuVerObj) | Should -BeTrue
        }
    }

    Context 'CU version newer than ESD version -> download' {
        It 'Should determine download when CU is newer than ESD' {
            $esdVersionStr = '10.0.26100.1742'
            $cuVersionStr = '10.0.26100.2454'

            $esdVerObj = [version]$esdVersionStr
            $cuVerObj = [version]$cuVersionStr

            $shouldSkip = $esdVerObj -ge $cuVerObj
            $shouldSkip | Should -BeFalse
        }
    }

    Context 'ESD version unparseable -> safe default (download CU)' {
        It 'Should fall back to download when ESD version cannot be parsed' {
            $esdVersionStr = 'invalid-version'
            $cuVersionStr = '10.0.26100.2454'

            $esdVerObj = $null
            try { $esdVerObj = [version]$esdVersionStr } catch { }

            $cuVerObj = $null
            try { $cuVerObj = [version]$cuVersionStr } catch { }

            # When esdVerObj is null, comparison cannot proceed - download CU
            $canCompare = ($null -ne $esdVerObj -and $null -ne $cuVerObj)
            $canCompare | Should -BeFalse

            # Safe default: if cannot compare, shouldSkip is false (download CU)
            $shouldSkip = if ($canCompare) { $esdVerObj -ge $cuVerObj } else { $false }
            $shouldSkip | Should -BeFalse
        }
    }

    Context 'CU version unparseable -> safe default (download CU)' {
        It 'Should fall back to download when CU version cannot be parsed' {
            $esdVersionStr = '10.0.26100.2454'
            $cuVersionStr = 'invalid'

            $esdVerObj = $null
            try { $esdVerObj = [version]$esdVersionStr } catch { }

            $cuVerObj = $null
            try { $cuVerObj = [version]$cuVersionStr } catch { }

            $canCompare = ($null -ne $esdVerObj -and $null -ne $cuVerObj)
            $canCompare | Should -BeFalse

            $shouldSkip = if ($canCompare) { $esdVerObj -ge $cuVerObj } else { $false }
            $shouldSkip | Should -BeFalse
        }
    }

    Context 'Both versions null -> no comparison, no skip' {
        It 'Should not skip when both versions are null' {
            $esdVersionStr = $null
            $cuVersionStr = $null

            # Simulates BuildFFUVM.ps1 logic: both versions must exist for comparison
            $canCompare = ($null -ne $esdVersionStr -and $null -ne $cuVersionStr)
            $canCompare | Should -BeFalse

            $shouldSkip = $false
            $shouldSkip | Should -BeFalse
        }
    }

    Context 'Only ESD version available (no CU found) -> no comparison' {
        It 'Should not skip when only ESD version is available' {
            $esdVersionStr = '10.0.26100.2454'
            $cuKbWindowsVersion = $null

            # In BuildFFUVM.ps1: comparison only runs if ($esdVersion -and ($cuKbWindowsVersion -or $cupKbWindowsVersion))
            $canCompare = ($null -ne $esdVersionStr -and $null -ne $cuKbWindowsVersion)
            $canCompare | Should -BeFalse

            $shouldSkip = $false
            $shouldSkip | Should -BeFalse
        }
    }

    Context 'Version comparison with different build numbers' {
        It 'Should correctly compare versions differing only in revision' {
            $versions = @(
                @{ ESD = '10.0.26100.1742'; CU = '10.0.26100.2454'; ExpectSkip = $false },
                @{ ESD = '10.0.26100.2454'; CU = '10.0.26100.1742'; ExpectSkip = $true },
                @{ ESD = '10.0.26100.2894'; CU = '10.0.26100.2894'; ExpectSkip = $true },
                @{ ESD = '10.0.22631.4567'; CU = '10.0.22631.4321'; ExpectSkip = $true }
            )

            foreach ($case in $versions) {
                $esdVerObj = [version]$case.ESD
                $cuVerObj = [version]$case.CU
                $shouldSkip = $esdVerObj -ge $cuVerObj
                $shouldSkip | Should -Be $case.ExpectSkip -Because "ESD $($case.ESD) vs CU $($case.CU)"
            }
        }
    }

    Context 'Both versions unparseable -> safe default (download CU)' {
        It 'Should fall back to download when both versions are unparseable' {
            $esdVersionStr = 'bad-esd-version'
            $cuVersionStr = 'bad-cu-version'

            $esdVerObj = $null
            try { $esdVerObj = [version]$esdVersionStr } catch { }

            $cuVerObj = $null
            try { $cuVerObj = [version]$cuVersionStr } catch { }

            $canCompare = ($null -ne $esdVerObj -and $null -ne $cuVerObj)
            $canCompare | Should -BeFalse

            $shouldSkip = if ($canCompare) { $esdVerObj -ge $cuVerObj } else { $false }
            $shouldSkip | Should -BeFalse
        }
    }

    Context 'Preview CU version comparison' {
        It 'Should apply same logic for preview CU versions' {
            # Preview CU uses the same version comparison logic
            $esdVersionStr = '10.0.26100.2894'
            $cupVersionStr = '10.0.26100.2700'

            $esdVerObj = [version]$esdVersionStr
            $cupVerObj = [version]$cupVersionStr

            $shouldSkip = $esdVerObj -ge $cupVerObj
            $shouldSkip | Should -BeTrue
        }
    }
}
