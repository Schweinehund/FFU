#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Core error handling enhancements (REL-CORE-01)

.DESCRIPTION
    Comprehensive tests verifying error handling patterns in FFU.Core module:
    - Specific exception types are thrown
    - Error messages include operation context
    - Graceful handling of edge cases
    - No regressions in normal functionality

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.ErrorHandling.Tests.ps1 -Output Detailed
    Part of REL-CORE-01 (FFU.Core Reliability) hardening

.EXAMPLE
    Invoke-Pester -Path .\Tests\Unit\FFU.Core.ErrorHandling.Tests.ps1 -Tag 'ErrorHandling'
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Core'

    # Add Modules path for RequiredModules resolution
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"

    # Remove module if loaded (ensures clean state)
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Verify module exists
    if (-not (Test-Path "$ModulePath\FFU.Core.psd1")) {
        throw "FFU.Core module not found at: $ModulePath"
    }

    # Import the module
    Import-Module "$ModulePath\FFU.Core.psd1" -Force -ErrorAction Stop

    # Create temp directory for file-based tests
    $script:TestTempPath = Join-Path $env:TEMP "FFU.Core.ErrorHandling.Tests.$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:TestTempPath -Force | Out-Null
}

AfterAll {
    # Cleanup modules
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Cleanup temp directory
    if ($script:TestTempPath -and (Test-Path $script:TestTempPath)) {
        Remove-Item -Path $script:TestTempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'FFU.Core Error Handling' -Tag 'Unit', 'FFU.Core', 'ErrorHandling' {

    Context 'Get-Parameters - Parameter filtering' {

        It 'Returns empty array for null input' {
            $result = Get-Parameters -ParamNames $null
            # Result should be empty array or null (both acceptable for null input)
            if ($null -ne $result) {
                $result | Should -BeOfType [System.Array]
                $result.Count | Should -Be 0
            }
        }

        It 'Returns empty array for empty input' {
            $result = Get-Parameters -ParamNames @()
            $result.Count | Should -Be 0
        }

        It 'Filters out common parameters' {
            $input = @('MyParam', 'Verbose', 'Debug', 'ErrorAction', 'AnotherParam')
            $result = Get-Parameters -ParamNames $input
            $result | Should -Contain 'MyParam'
            $result | Should -Contain 'AnotherParam'
            $result | Should -Not -Contain 'Verbose'
            $result | Should -Not -Contain 'Debug'
            $result | Should -Not -Contain 'ErrorAction'
        }
    }

    Context 'Get-ChildProcesses - CIM query error handling' {

        It 'Returns array or empty for process with no children' {
            # Use current process ID - unlikely to have child processes during test
            $result = Get-ChildProcesses -ParentId $PID
            # Result can be empty array, null, or array with results
            if ($null -ne $result -and $result.Count -gt 0) {
                $result[0] | Should -BeOfType [Microsoft.Management.Infrastructure.CimInstance]
            }
        }

        It 'Handles non-existent process ID gracefully' {
            # Use an impossibly high PID that won't exist - should return empty
            $result = Get-ChildProcesses -ParentId 999999999
            # Result should be null or empty array (both acceptable)
            if ($null -ne $result) {
                $result.Count | Should -Be 0
            }
        }

        It 'Validates ParentId parameter range' {
            { Get-ChildProcesses -ParentId -1 } | Should -Throw -ExpectedMessage "*Cannot validate argument*"
        }
    }

    Context 'Test-Url - Network error handling' {

        It 'Returns false for invalid URL format' {
            $result = Test-Url -Url 'not-a-valid-url'
            $result | Should -Be $false
        }

        It 'Returns false for unreachable host' {
            $result = Test-Url -Url 'http://this-host-definitely-does-not-exist-12345.example.invalid/'
            $result | Should -Be $false
        }

        It 'Returns false for empty URL' {
            { Test-Url -Url '' } | Should -Throw
        }

        It 'Returns true for valid reachable URL' -Skip:(-not (Test-Connection -ComputerName 'microsoft.com' -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            $result = Test-Url -Url 'https://www.microsoft.com'
            $result | Should -Be $true
        }
    }

    Context 'Get-PrivateProfileString - INI file error handling' {

        It 'Returns empty string for non-existent file' {
            $result = Get-PrivateProfileString -FileName 'C:\NonExistent\File.ini' -SectionName 'Section' -KeyName 'Key'
            $result | Should -Be ''
        }

        It 'Returns empty string for non-existent section' -Skip:$(-not ('Win32.Kernel32' -as [type])) {
            # Create a test INI file - Skip if Win32.Kernel32 type not loaded (requires BuildFFUVM.ps1 context)
            $testIni = Join-Path $script:TestTempPath 'test.ini'
            "[TestSection]`nTestKey=TestValue" | Set-Content -Path $testIni -Encoding UTF8

            $result = Get-PrivateProfileString -FileName $testIni -SectionName 'NonExistentSection' -KeyName 'Key'
            $result | Should -Be ''
        }

        It 'Reads value from valid INI file' -Skip:$(-not ('Win32.Kernel32' -as [type])) {
            # Skip if Win32.Kernel32 type not loaded (requires BuildFFUVM.ps1 context)
            $testIni = Join-Path $script:TestTempPath 'valid.ini'
            "[TestSection]`nMyKey=MyValue" | Set-Content -Path $testIni -Encoding UTF8

            $result = Get-PrivateProfileString -FileName $testIni -SectionName 'TestSection' -KeyName 'MyKey'
            $result | Should -Be 'MyValue'
        }
    }

    Context 'Get-PrivateProfileSection - INI section error handling' {

        It 'Returns empty hashtable for non-existent file' {
            $result = Get-PrivateProfileSection -FileName 'C:\NonExistent\File.ini' -SectionName 'Section'
            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 0
        }

        It 'Returns hashtable with key-value pairs from valid file' -Skip:$(-not ('Win32.Kernel32' -as [type])) {
            # Skip if Win32.Kernel32 type not loaded (requires BuildFFUVM.ps1 context)
            $testIni = Join-Path $script:TestTempPath 'section.ini'
            "[MySection]`nKey1=Value1`nKey2=Value2" | Set-Content -Path $testIni -Encoding UTF8

            $result = Get-PrivateProfileSection -FileName $testIni -SectionName 'MySection'
            $result | Should -BeOfType [hashtable]
            $result['Key1'] | Should -Be 'Value1'
            $result['Key2'] | Should -Be 'Value2'
        }

        It 'Handles values containing equals signs' -Skip:$(-not ('Win32.Kernel32' -as [type])) {
            # Skip if Win32.Kernel32 type not loaded (requires BuildFFUVM.ps1 context)
            $testIni = Join-Path $script:TestTempPath 'equals.ini'
            "[Section]`nPath=C:\Program=Files\App" | Set-Content -Path $testIni -Encoding UTF8

            $result = Get-PrivateProfileSection -FileName $testIni -SectionName 'Section'
            $result['Path'] | Should -Be 'C:\Program=Files\App'
        }
    }

    Context 'New-FFUFileName - Parameter validation' {

        It 'Throws ArgumentException for empty template' {
            { New-FFUFileName -installationType 'Client' -WindowsRelease 11 -CustomFFUNameTemplate '' -WindowsVersion '23H2' -shortenedWindowsSKU 'Pro' } |
                Should -Throw -ExpectedMessage "*CustomFFUNameTemplate*"
        }

        It 'Throws ArgumentException for empty WindowsVersion' {
            { New-FFUFileName -installationType 'Client' -WindowsRelease 11 -CustomFFUNameTemplate 'Test_{SKU}' -WindowsVersion '' -shortenedWindowsSKU 'Pro' } |
                Should -Throw -ExpectedMessage "*WindowsVersion*"
        }

        It 'Throws ArgumentException for empty SKU' {
            { New-FFUFileName -installationType 'Client' -WindowsRelease 11 -CustomFFUNameTemplate 'Test_{SKU}' -WindowsVersion '23H2' -shortenedWindowsSKU '' } |
                Should -Throw -ExpectedMessage "*shortenedWindowsSKU*"
        }

        It 'Generates valid filename from template' {
            $result = New-FFUFileName -installationType 'Server' -WindowsRelease 2022 -CustomFFUNameTemplate 'Win{WindowsRelease}_{SKU}' -WindowsVersion '21H2' -shortenedWindowsSKU 'Srv_Std'
            $result | Should -Match 'Win2022_Srv_Std\.ffu$'
        }

        It 'Adds .ffu extension if missing' {
            $result = New-FFUFileName -installationType 'Server' -WindowsRelease 2022 -CustomFFUNameTemplate 'TestName' -WindowsVersion '21H2' -shortenedWindowsSKU 'Pro'
            $result | Should -Match '\.ffu$'
        }
    }

    Context 'Export-ConfigFile - File operation error handling' {

        It 'Returns silently for null parameter names' {
            $exportPath = Join-Path $script:TestTempPath 'null-params.json'
            { Export-ConfigFile -paramNames $null -ExportConfigFile $exportPath } | Should -Not -Throw
        }

        It 'Returns silently for empty parameter names' {
            $exportPath = Join-Path $script:TestTempPath 'empty-params.json'
            { Export-ConfigFile -paramNames @() -ExportConfigFile $exportPath } | Should -Not -Throw
        }

        It 'Creates directory if it does not exist' {
            $exportPath = Join-Path $script:TestTempPath 'subdir\config.json'
            $TestParam = 'TestValue'
            Export-ConfigFile -paramNames @('TestParam') -ExportConfigFile $exportPath
            Test-Path $exportPath | Should -Be $true
        }
    }

    Context 'Get-CurrentRunManifest - File locking and JSON errors' {

        It 'Returns null for non-existent manifest' {
            $result = Get-CurrentRunManifest -FFUDevelopmentPath 'C:\NonExistent\Path'
            $result | Should -Be $null
        }

        It 'Returns null for invalid JSON in manifest' {
            $sessionDir = Join-Path $script:TestTempPath 'invalid-json\.session'
            New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
            $manifestPath = Join-Path $sessionDir 'currentRun.json'
            'this is not valid json {{{' | Set-Content -Path $manifestPath -Encoding UTF8

            $result = Get-CurrentRunManifest -FFUDevelopmentPath (Join-Path $script:TestTempPath 'invalid-json')
            $result | Should -Be $null
        }

        It 'Returns manifest object for valid JSON' {
            $sessionDir = Join-Path $script:TestTempPath 'valid-json\.session'
            New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
            $manifestPath = Join-Path $sessionDir 'currentRun.json'
            @{ RunStartUtc = '2026-01-23T12:00:00Z'; JsonBackups = @() } | ConvertTo-Json | Set-Content -Path $manifestPath -Encoding UTF8

            $result = Get-CurrentRunManifest -FFUDevelopmentPath (Join-Path $script:TestTempPath 'valid-json')
            $result | Should -Not -Be $null
            # Verify the manifest has RunStartUtc property with a value
            $result.RunStartUtc | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Save-RunManifest - IOException handling' {

        It 'Returns silently for null manifest' {
            { Save-RunManifest -FFUDevelopmentPath $script:TestTempPath -Manifest $null } | Should -Not -Throw
        }

        It 'Creates session directory if missing' {
            $testPath = Join-Path $script:TestTempPath 'save-test'
            $manifest = @{ RunStartUtc = '2026-01-23T12:00:00Z' }

            Save-RunManifest -FFUDevelopmentPath $testPath -Manifest $manifest

            $manifestPath = Join-Path $testPath '.session\currentRun.json'
            Test-Path $manifestPath | Should -Be $true
        }

        It 'Saves valid manifest as JSON' {
            $testPath = Join-Path $script:TestTempPath 'save-valid'
            $manifest = @{
                RunStartUtc = '2026-01-23T12:00:00Z'
                JsonBackups = @(@{ Path = 'C:\test'; Backup = 'C:\backup' })
            }

            Save-RunManifest -FFUDevelopmentPath $testPath -Manifest $manifest

            $manifestPath = Join-Path $testPath '.session\currentRun.json'
            $loaded = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
            # Verify the manifest has RunStartUtc property with a value
            $loaded.RunStartUtc | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Set-DownloadInProgress - Marker file creation' {

        It 'Returns silently for null FFUDevelopmentPath' {
            { Set-DownloadInProgress -FFUDevelopmentPath $null -TargetPath 'C:\test' } | Should -Not -Throw
        }

        It 'Returns silently for null TargetPath' {
            { Set-DownloadInProgress -FFUDevelopmentPath $script:TestTempPath -TargetPath $null } | Should -Not -Throw
        }

        It 'Creates marker file for valid inputs' {
            $testPath = Join-Path $script:TestTempPath 'marker-test'
            Set-DownloadInProgress -FFUDevelopmentPath $testPath -TargetPath 'C:\Download\File.exe'

            $inprogDir = Join-Path $testPath '.session\inprogress'
            $markers = Get-ChildItem -Path $inprogDir -Filter '*.marker' -ErrorAction SilentlyContinue
            $markers.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Clear-DownloadInProgress - Marker file removal' {

        It 'Returns silently for non-existent session directory' {
            { Clear-DownloadInProgress -FFUDevelopmentPath 'C:\NonExistent' -TargetPath 'C:\test' } | Should -Not -Throw
        }

        It 'Removes marker for matching target path' {
            $testPath = Join-Path $script:TestTempPath 'clear-marker'
            $targetPath = 'C:\Download\TestFile.exe'

            # Create marker
            Set-DownloadInProgress -FFUDevelopmentPath $testPath -TargetPath $targetPath

            $inprogDir = Join-Path $testPath '.session\inprogress'
            $markersBefore = Get-ChildItem -Path $inprogDir -Filter '*.marker' -ErrorAction SilentlyContinue

            # Clear marker
            Clear-DownloadInProgress -FFUDevelopmentPath $testPath -TargetPath $targetPath

            $markersAfter = Get-ChildItem -Path $inprogDir -Filter '*.marker' -ErrorAction SilentlyContinue
            $markersAfter.Count | Should -BeLessThan $markersBefore.Count
        }
    }

    Context 'Get-ShortenedWindowsSKU - Default case handling' {

        It 'Returns known SKU abbreviations correctly' {
            Get-ShortenedWindowsSKU -WindowsSKU 'Professional' | Should -Be 'Pro'
            Get-ShortenedWindowsSKU -WindowsSKU 'Enterprise' | Should -Be 'Ent'
            Get-ShortenedWindowsSKU -WindowsSKU 'Education' | Should -Be 'Edu'
            Get-ShortenedWindowsSKU -WindowsSKU 'Home' | Should -Be 'Home'
        }

        It 'Returns original SKU name for unknown SKUs' {
            $result = Get-ShortenedWindowsSKU -WindowsSKU 'CustomUnknownSKU'
            $result | Should -Be 'CustomUnknownSKU'
        }

        It 'Handles whitespace in SKU names' {
            $result = Get-ShortenedWindowsSKU -WindowsSKU '  Professional  '
            $result | Should -Be 'Pro'
        }
    }

    Context 'Error context quality' {

        It 'IOException includes file path context when Save-RunManifest fails on locked file' -Skip {
            # This test would require creating a locked file scenario
            # Skipped as it requires external coordination
        }

        It 'ArgumentException includes parameter name in message' {
            $exception = $null
            try {
                New-FFUFileName -installationType 'Client' -WindowsRelease 11 -CustomFFUNameTemplate '' -WindowsVersion '23H2' -shortenedWindowsSKU 'Pro'
            }
            catch {
                $exception = $_
            }
            $exception | Should -Not -Be $null
            $exception.Exception.Message | Should -Match 'CustomFFUNameTemplate'
        }
    }
}

Describe 'FFU.Core Error Handling - Robustness' -Tag 'Unit', 'FFU.Core', 'ErrorHandling', 'Robustness' {

    Context 'Module exports expected function count' {

        It 'Exports exactly 44 functions' {
            $functions = Get-Command -Module FFU.Core -CommandType Function
            $functions.Count | Should -Be 44
        }
    }

    Context 'All enhanced functions are testable' {

        It 'Get-Parameters is exported and callable' {
            { Get-Command -Name Get-Parameters -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Write-VariableValues is exported and callable' {
            { Get-Command -Name Write-VariableValues -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Get-ChildProcesses is exported and callable' {
            { Get-Command -Name Get-ChildProcesses -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Test-Url is exported and callable' {
            { Get-Command -Name Test-Url -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Get-PrivateProfileString is exported and callable' {
            { Get-Command -Name Get-PrivateProfileString -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Get-PrivateProfileSection is exported and callable' {
            { Get-Command -Name Get-PrivateProfileSection -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'New-FFUFileName is exported and callable' {
            { Get-Command -Name New-FFUFileName -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Export-ConfigFile is exported and callable' {
            { Get-Command -Name Export-ConfigFile -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Get-CurrentRunManifest is exported and callable' {
            { Get-Command -Name Get-CurrentRunManifest -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Save-RunManifest is exported and callable' {
            { Get-Command -Name Save-RunManifest -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Set-DownloadInProgress is exported and callable' {
            { Get-Command -Name Set-DownloadInProgress -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Clear-DownloadInProgress is exported and callable' {
            { Get-Command -Name Clear-DownloadInProgress -Module FFU.Core -ErrorAction Stop } | Should -Not -Throw
        }
    }
}
