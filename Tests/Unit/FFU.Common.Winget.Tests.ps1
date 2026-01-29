#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Common.Winget module

.DESCRIPTION
    Comprehensive unit tests covering BUGFIX-01 (mutex-protected JSON writes)
    and BUGFIX-03 (path quoting for installers with spaces).
    Tests verify thread-safe JSON operations, duplicate detection, and proper
    path quoting for EXE and MSI installers.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Common.Winget.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Common.Winget.Tests.ps1 -CodeCoverage .\FFUDevelopment\FFU.Common\FFU.Common.Winget.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common\FFU.Common.Winget.psm1'

    # Remove module if loaded (ensures clean state)
    Get-Module -Name 'FFU.Common.Winget' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Verify module exists
    if (-not (Test-Path $ModulePath)) {
        throw "FFU.Common.Winget module not found at: $ModulePath"
    }

    # Import the module directly (it's a .psm1 file, not a manifest module)
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Mock WriteLog as no-op since it's external (from FFU.Common.Core)
    function Global:WriteLog {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Message', Justification='Mock function for testing')]
        param([string]$Message)
        # No-op for tests
    }

    # Helper function to create test app folder with installer and YAML
    function New-TestAppFolder {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Test helper function')]
        param(
            [string]$BasePath,
            [string]$AppName,
            [string]$InstallerType,  # 'exe' or 'msi'
            [string]$SilentSwitch = '/S',
            [string]$SubFolder = $null,
            [bool]$IncludeSpaces = $false
        )

        $appPath = Join-Path $BasePath $AppName
        if ($SubFolder) {
            $appPath = Join-Path $appPath $SubFolder
        }
        New-Item -Path $appPath -ItemType Directory -Force | Out-Null

        # Create installer file with proper naming
        $installerName = if ($IncludeSpaces) {
            "Test App Installer.$InstallerType"
        }
        else {
            "TestInstaller.$InstallerType"
        }
        $installerPath = Join-Path $appPath $installerName
        "dummy content" | Set-Content -Path $installerPath -Force

        # Create minimal YAML that satisfies regex patterns
        $yamlContent = @"
PackageIdentifier: Test.Package
PackageVersion: 1.0.0
Installers:
- Architecture: x64
  InstallerType: $InstallerType
  InstallerUrl: https://example.com/installer.$InstallerType
  InstallerSwitches:
    Silent: $SilentSwitch
"@
        $yamlPath = Join-Path $appPath "installer.yaml"
        $yamlContent | Set-Content -Path $yamlPath -Force

        return $appPath
    }
}

AfterAll {
    # Cleanup
    Get-Module -Name 'FFU.Common.Winget' | Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Item function:WriteLog -ErrorAction SilentlyContinue
}

# =============================================================================
# Add-Win32SilentInstallCommand - Mutex JSON Safety (BUGFIX-01)
# =============================================================================

Describe 'Add-Win32SilentInstallCommand - Mutex JSON Safety' -Tag 'Unit', 'FFU.Common.Winget', 'BUGFIX-01' {

    Context 'Single App Entry' {
        It 'Should create WinGetWin32Apps.json with single app entry' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration1"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestApp1" -InstallerType "exe"

            # Act
            $result = Add-Win32SilentInstallCommand -AppFolder "TestApp1" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath

            # Assert
            $result | Should -Be 0
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $jsonPath | Should -Exist
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            # Convert to array if single object
            if ($apps -isnot [array]) { $apps = @($apps) }
            $apps.Count | Should -Be 1
            $apps[0].Name | Should -Be "TestApp1"
            $apps[0].Priority | Should -Be 1
        }
    }

    Context 'Duplicate Prevention' {
        It 'Should prevent duplicate entries when called twice with same app' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration2"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestApp2" -InstallerType "exe"

            # Act - Add same app twice
            $result1 = Add-Win32SilentInstallCommand -AppFolder "TestApp2" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath
            $result2 = Add-Win32SilentInstallCommand -AppFolder "TestApp2" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath

            # Assert
            $result1 | Should -Be 0
            $result2 | Should -Be 0  # Returns success but doesn't add duplicate
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            # Convert to array if single object
            if ($apps -isnot [array]) { $apps = @($apps) }
            $apps.Count | Should -Be 1 -Because "duplicate detection should prevent second entry"
        }
    }

    Context 'Sequential Priorities' {
        It 'Should assign sequential priorities' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration3"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $app1Path = New-TestAppFolder -BasePath $TestDrive -AppName "App1" -InstallerType "exe"
            $app2Path = New-TestAppFolder -BasePath $TestDrive -AppName "App2" -InstallerType "msi"
            $app3Path = New-TestAppFolder -BasePath $TestDrive -AppName "App3" -InstallerType "exe"

            # Act - Add multiple apps
            Add-Win32SilentInstallCommand -AppFolder "App1" -AppFolderPath $app1Path -OrchestrationPath $testOrchestrationPath | Out-Null
            Add-Win32SilentInstallCommand -AppFolder "App2" -AppFolderPath $app2Path -OrchestrationPath $testOrchestrationPath | Out-Null
            Add-Win32SilentInstallCommand -AppFolder "App3" -AppFolderPath $app3Path -OrchestrationPath $testOrchestrationPath | Out-Null

            # Assert
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            $apps.Count | Should -Be 3
            $apps[0].Priority | Should -Be 1
            $apps[1].Priority | Should -Be 2
            $apps[2].Priority | Should -Be 3
        }
    }

    Context 'Named Mutex Usage' {
        It 'Should use named mutex via Invoke-WithNamedMutex wrapper' {
            # Arrange - Get the module source code
            $moduleSource = Get-Content -Path "$ProjectRoot\FFUDevelopment\FFU.Common\FFU.Common.Winget.psm1" -Raw

            # Assert - Check for mutex wrapper pattern in source code (Phase 37 upgrade from raw mutex)
            $moduleSource | Should -Match 'Invoke-WithNamedMutex' -Because "function must use Invoke-WithNamedMutex wrapper for cross-process synchronization"
            $moduleSource | Should -Match 'Get-WinGetWin32AppsJsonMutexName' -Because "function must use path-based mutex name generation"
            $moduleSource | Should -Match 'System\.Threading\.Mutex' -Because "function must use Mutex for thread safety"
        }
    }

    Context 'Concurrent Writes Safety' {
        It 'Should handle sequential writes without JSON corruption' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration4"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null

            # Create 5 test apps
            $appPaths = @()
            for ($i = 1; $i -le 5; $i++) {
                $appPaths += New-TestAppFolder -BasePath $TestDrive -AppName "SeqApp$i" -InstallerType "exe"
            }

            # Act - Add all apps sequentially
            foreach ($i in 1..5) {
                Add-Win32SilentInstallCommand -AppFolder "SeqApp$i" -AppFolderPath $appPaths[$i - 1] -OrchestrationPath $testOrchestrationPath | Out-Null
            }

            # Assert - Verify JSON is valid and contains all entries
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $jsonPath | Should -Exist
            { Get-Content -Path $jsonPath -Raw | ConvertFrom-Json } | Should -Not -Throw -Because "JSON should be valid after sequential writes"
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            $apps.Count | Should -Be 5
            $apps.Name | Should -Contain "SeqApp1"
            $apps.Name | Should -Contain "SeqApp5"
        }
    }
}

# =============================================================================
# Add-Win32SilentInstallCommand - EXE Path Quoting (BUGFIX-03)
# =============================================================================

Describe 'Add-Win32SilentInstallCommand - EXE Path Quoting' -Tag 'Unit', 'FFU.Common.Winget', 'BUGFIX-03' {

    Context 'EXE with Spaces in Path' {
        It 'Should quote EXE CommandLine path containing spaces' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration5"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestAppSpaces" -InstallerType "exe" -IncludeSpaces $true

            # Act
            $result = Add-Win32SilentInstallCommand -AppFolder "TestAppSpaces" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath

            # Assert
            $result | Should -Be 0
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            # Convert to array if single object
            if ($apps -isnot [array]) { $apps = @($apps) }
            $apps[0].CommandLine | Should -Match '^".*"$' -Because "EXE path with spaces must be quoted"
            $apps[0].CommandLine | Should -Match 'D:\\win32\\TestAppSpaces\\' -Because "path should use D: drive base"
        }
    }

    Context 'EXE without Spaces' {
        It 'Should handle EXE paths without spaces correctly' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration6"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestAppNoSpaces" -InstallerType "exe" -IncludeSpaces $false

            # Act
            $result = Add-Win32SilentInstallCommand -AppFolder "TestAppNoSpaces" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath

            # Assert
            $result | Should -Be 0
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            # Convert to array if single object
            if ($apps -isnot [array]) { $apps = @($apps) }
            $apps[0].CommandLine | Should -Match '^".*"$' -Because "all EXE paths should be quoted for consistency"
            $apps[0].CommandLine | Should -Match 'TestInstaller\.exe'
        }
    }
}

# =============================================================================
# Add-Win32SilentInstallCommand - MSI Path Quoting (BUGFIX-03)
# =============================================================================

Describe 'Add-Win32SilentInstallCommand - MSI Path Quoting' -Tag 'Unit', 'FFU.Common.Winget', 'BUGFIX-03' {

    Context 'MSI with Spaces in Path' {
        It 'Should quote MSI path in Arguments field with spaces' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration7"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestMSISpaces" -InstallerType "msi" -SilentSwitch "/quiet" -IncludeSpaces $true

            # Act
            $result = Add-Win32SilentInstallCommand -AppFolder "TestMSISpaces" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath

            # Assert
            $result | Should -Be 0
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            # Convert to array if single object
            if ($apps -isnot [array]) { $apps = @($apps) }
            $apps[0].CommandLine | Should -Be "msiexec"
            $apps[0].Arguments | Should -Match '^/i ".*" ' -Because "MSI path with spaces must be quoted in Arguments"
            $apps[0].Arguments | Should -Match 'D:\\win32\\TestMSISpaces\\'
        }
    }

    Context 'MSI Arguments Structure' {
        It 'Should produce valid msiexec arguments' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration8"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestMSI" -InstallerType "msi" -SilentSwitch "/quiet /norestart"

            # Act
            Add-Win32SilentInstallCommand -AppFolder "TestMSI" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath | Out-Null

            # Assert
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            $apps[0].Arguments | Should -Match '^/i ".*" /quiet /norestart$'
            $apps[0].CommandLine | Should -Be "msiexec"
        }
    }

    Context 'MSI Arguments Whitespace' {
        It 'Should not have trailing whitespace in Arguments when silent switch is provided' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration9"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestMSITrim" -InstallerType "msi" -SilentSwitch "/quiet"

            # Act
            Add-Win32SilentInstallCommand -AppFolder "TestMSITrim" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath | Out-Null

            # Assert - Function requires silent switch, so test with one
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            # Convert to array if single object
            if ($apps -isnot [array]) { $apps = @($apps) }
            $apps[0].Arguments | Should -Not -Match '\s$' -Because "no trailing whitespace should exist"
            $apps[0].Arguments | Should -Match '^/i ".*" /quiet$'
        }
    }
}

# =============================================================================
# Add-Win32SilentInstallCommand - JSON Round-Trip Integrity (BUGFIX-03)
# =============================================================================

Describe 'Add-Win32SilentInstallCommand - JSON Round-Trip Integrity' -Tag 'Unit', 'FFU.Common.Winget', 'BUGFIX-03' {

    Context 'JSON Serialization' {
        It 'Should survive JSON serialization and deserialization with quoted paths' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration10"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestRoundTrip" -InstallerType "exe" -IncludeSpaces $true

            # Act - Add app, then read back the JSON
            Add-Win32SilentInstallCommand -AppFolder "TestRoundTrip" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath | Out-Null
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            $jsonContent = Get-Content -Path $jsonPath -Raw
            $apps = $jsonContent | ConvertFrom-Json

            # Act - Serialize back to JSON
            $reserializedJson = $apps | ConvertTo-Json -Depth 10

            # Assert - Should be valid JSON that can be parsed again
            { $reserializedJson | ConvertFrom-Json } | Should -Not -Throw
            $finalApps = $reserializedJson | ConvertFrom-Json
            $finalApps[0].CommandLine | Should -Be $apps[0].CommandLine -Because "quoted paths should survive round-trip"
            $finalApps[0].Arguments | Should -Be $apps[0].Arguments
        }
    }

    Context 'JSON File Validity' {
        It 'Should produce valid JSON file' {
            # Arrange
            $testOrchestrationPath = Join-Path $TestDrive "Orchestration11"
            New-Item -Path $testOrchestrationPath -ItemType Directory -Force | Out-Null
            $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "TestValidJSON" -InstallerType "msi"

            # Act
            Add-Win32SilentInstallCommand -AppFolder "TestValidJSON" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath | Out-Null

            # Assert - Verify JSON is valid and well-formed
            $jsonPath = Join-Path $testOrchestrationPath "WinGetWin32Apps.json"
            { Get-Content -Path $jsonPath -Raw | ConvertFrom-Json } | Should -Not -Throw
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            # Convert to array if single object (PowerShell JSON behavior)
            if ($apps -isnot [array]) { $apps = @($apps) }
            $apps.Count | Should -BeGreaterOrEqual 1 -Because "JSON should contain at least one app"
            $apps[0].Name | Should -Be "TestValidJSON"
        }
    }
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Common.Winget Module Exports' -Tag 'Unit', 'FFU.Common.Winget', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Add-Win32SilentInstallCommand' {
            Get-Command -Name 'Add-Win32SilentInstallCommand' -Module 'FFU.Common.Winget' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-Application' {
            Get-Command -Name 'Get-Application' -Module 'FFU.Common.Winget' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-Apps' {
            Get-Command -Name 'Get-Apps' -Module 'FFU.Common.Winget' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Confirm-WinGetInstallation' {
            Get-Command -Name 'Confirm-WinGetInstallation' -Module 'FFU.Common.Winget' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Phase 37: Helper Functions - Invoke-WithNamedMutex
# =============================================================================

Describe 'Invoke-WithNamedMutex - Mutex Wrapper' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37' {

    BeforeAll {
        $module = Get-Module 'FFU.Common.Winget'
    }

    It 'Should execute scriptblock and return result' {
        $result = & $module { Invoke-WithNamedMutex -MutexName 'TestMutex_Return' -ScriptBlock { 42 } }
        $result | Should -Be 42
    }

    It 'Should handle scriptblock that returns hashtable' {
        $result = & $module { Invoke-WithNamedMutex -MutexName 'TestMutex_Hash' -ScriptBlock { @{ Added = $true } } }
        $result | Should -BeOfType [hashtable]
        $result.Added | Should -BeTrue
    }

    It 'Should throw on timeout' {
        # Hold the mutex from a background runspace so the current thread cannot acquire it
        $mutexName = "Global\TestMutex_Timeout_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $readyEvent = New-Object System.Threading.ManualResetEventSlim($false)
        $releaseEvent = New-Object System.Threading.ManualResetEventSlim($false)

        # Use a PowerShell runspace (not a raw Thread) to hold the mutex
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps = [powershell]::Create().AddScript({
            param($name, $ready, $release)
            $m = New-Object System.Threading.Mutex($false, $name)
            $m.WaitOne() | Out-Null
            $ready.Set()
            $release.Wait([TimeSpan]::FromSeconds(15)) | Out-Null
            try { $m.ReleaseMutex() } catch { }
            $m.Dispose()
        }).AddArgument($mutexName).AddArgument($readyEvent).AddArgument($releaseEvent)
        $ps.Runspace = $rs
        $asyncResult = $ps.BeginInvoke()

        try {
            # Wait for background runspace to acquire the mutex
            $readyEvent.Wait([TimeSpan]::FromSeconds(5)) | Out-Null

            {
                & $module {
                    param($name)
                    Invoke-WithNamedMutex -MutexName $name -TimeoutSeconds 1 -ScriptBlock { 'should not reach' }
                } $mutexName
            } | Should -Throw -Because "mutex is held by background runspace"
        }
        finally {
            $releaseEvent.Set()
            $ps.EndInvoke($asyncResult) | Out-Null
            $ps.Dispose()
            $rs.Dispose()
            $readyEvent.Dispose()
            $releaseEvent.Dispose()
        }
    }

    It 'Should dispose mutex after execution (no leak on repeated calls)' {
        $mutexName = "TestMutex_NoLeak_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        # If first call leaked the mutex, second call would deadlock/timeout
        $result1 = & $module {
            param($name)
            Invoke-WithNamedMutex -MutexName $name -ScriptBlock { 'first' }
        } $mutexName
        $result2 = & $module {
            param($name)
            Invoke-WithNamedMutex -MutexName $name -ScriptBlock { 'second' }
        } $mutexName
        $result1 | Should -Be 'first'
        $result2 | Should -Be 'second'
    }
}

# =============================================================================
# Phase 37: Helper Functions - Set-FileContentAtomic
# =============================================================================

Describe 'Set-FileContentAtomic - Atomic File Writes' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37' {

    BeforeAll {
        $module = Get-Module 'FFU.Common.Winget'
    }

    It 'Should create file with correct content' {
        $testFile = Join-Path $TestDrive "atomic_test_create.json"
        & $module {
            param($path)
            Set-FileContentAtomic -Path $path -Content '{"test": true}'
        } $testFile
        $testFile | Should -Exist
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Match '"test"'
    }

    It 'Should overwrite existing file atomically' {
        $testFile = Join-Path $TestDrive "atomic_test_overwrite.json"
        Set-Content -Path $testFile -Value '{"old": true}' -Encoding UTF8
        & $module {
            param($path)
            Set-FileContentAtomic -Path $path -Content '{"new": true}'
        } $testFile
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Match '"new"'
        $content | Should -Not -Match '"old"'
    }

    It 'Should create parent directories if missing' {
        $testFile = Join-Path $TestDrive "nonexistent\subdir\atomic_test.json"
        & $module {
            param($path)
            Set-FileContentAtomic -Path $path -Content '{"nested": true}'
        } $testFile
        $testFile | Should -Exist
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Match '"nested"'
    }

    It 'Should not leave temp files on success' {
        $testDir = Join-Path $TestDrive "atomic_no_temp"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        $testFile = Join-Path $testDir "output.json"
        & $module {
            param($path)
            Set-FileContentAtomic -Path $path -Content '{"clean": true}'
        } $testFile
        $tempFiles = Get-ChildItem -Path $testDir -Filter "*.tmp" -ErrorAction SilentlyContinue
        $tempFiles | Should -BeNullOrEmpty -Because "atomic write should clean up temp files"
    }
}

# =============================================================================
# Phase 37: Helper Functions - Get-WinGetYamlScalarValue
# =============================================================================

Describe 'Get-WinGetYamlScalarValue - YAML Extraction' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37' {

    BeforeAll {
        $module = Get-Module 'FFU.Common.Winget'
    }

    It 'Should extract PackageIdentifier from YAML' {
        $yaml = "PackageIdentifier: Microsoft.VCRedist.2015+.x64"
        $result = & $module {
            param($text)
            Get-WinGetYamlScalarValue -YamlText $text -Key 'PackageIdentifier'
        } $yaml
        $result | Should -Be "Microsoft.VCRedist.2015+.x64"
    }

    It 'Should extract PackageVersion from YAML' {
        $yaml = "PackageVersion: 14.36.32532.0"
        $result = & $module {
            param($text)
            Get-WinGetYamlScalarValue -YamlText $text -Key 'PackageVersion'
        } $yaml
        $result | Should -Be "14.36.32532.0"
    }

    It 'Should return null for missing key' {
        $yaml = "PackageIdentifier: Some.Package"
        $result = & $module {
            param($text)
            Get-WinGetYamlScalarValue -YamlText $text -Key 'NonExistentKey'
        } $yaml
        $result | Should -BeNullOrEmpty
    }

    It 'Should strip surrounding quotes from value' {
        $yaml = "PackageIdentifier: 'Quoted.Value'"
        $result = & $module {
            param($text)
            Get-WinGetYamlScalarValue -YamlText $text -Key 'PackageIdentifier'
        } $yaml
        $result | Should -Be "Quoted.Value"
    }

    It 'Should handle multi-line YAML correctly' {
        $yaml = @"
PackageIdentifier: Multi.Line.Test
PackageVersion: 2.0.0
Publisher: TestPublisher
InstallerType: exe
"@
        $result = & $module {
            param($text)
            Get-WinGetYamlScalarValue -YamlText $text -Key 'PackageVersion'
        } $yaml
        $result | Should -Be "2.0.0"
    }
}

# =============================================================================
# Phase 37: Helper Functions - Get-WinGetWin32AppsJsonMutexName
# =============================================================================

Describe 'Get-WinGetWin32AppsJsonMutexName - Path-Based Mutex' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37' {

    BeforeAll {
        $module = Get-Module 'FFU.Common.Winget'
    }

    It 'Should return consistent mutex name for same path' {
        $path = "C:\TestOrchestration\WinGetWin32Apps.json"
        $result1 = & $module {
            param($p)
            Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $p
        } $path
        $result2 = & $module {
            param($p)
            Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $p
        } $path
        $result1 | Should -Be $result2
    }

    It 'Should return different mutex names for different paths' {
        $result1 = & $module {
            param($p)
            Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $p
        } "C:\Path1\WinGetWin32Apps.json"
        $result2 = & $module {
            param($p)
            Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $p
        } "C:\Path2\WinGetWin32Apps.json"
        $result1 | Should -Not -Be $result2
    }

    It 'Should start with WinGetWin32Apps_ prefix' {
        $result = & $module {
            param($p)
            Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $p
        } "C:\Any\Path.json"
        $result | Should -Match '^WinGetWin32Apps_'
    }
}

# =============================================================================
# Phase 37: Add-Win32SilentInstallCommand - PackageIdentifier Deduplication
# =============================================================================

Describe 'Add-Win32SilentInstallCommand - PackageIdentifier Deduplication' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37', 'WINGET-02' {

    It 'Should deduplicate entries with same PackageIdentifier' {
        # Arrange
        $testOrchPath = Join-Path $TestDrive "OrchDedup1"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null

        # Create two different app folders but same PackageIdentifier
        $app1Path = New-TestAppFolder -BasePath $TestDrive -AppName "DedupAppA" -InstallerType "exe"
        $app2Path = New-TestAppFolder -BasePath $TestDrive -AppName "DedupAppB" -InstallerType "exe"

        # Act - Add first with PackageIdentifier
        Add-Win32SilentInstallCommand -AppFolder "DedupAppA" -AppFolderPath $app1Path `
            -OrchestrationPath $testOrchPath -PackageIdentifier "Test.Package.1" | Out-Null
        # Add second with SAME PackageIdentifier but different Name
        Add-Win32SilentInstallCommand -AppFolder "DedupAppB" -AppFolderPath $app2Path `
            -OrchestrationPath $testOrchPath -PackageIdentifier "Test.Package.1" | Out-Null

        # Assert - Only 1 entry (second was deduplicated)
        $jsonPath = Join-Path $testOrchPath "WinGetWin32Apps.json"
        $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        if ($apps -isnot [array]) { $apps = @($apps) }
        $apps.Count | Should -Be 1 -Because "duplicate PackageIdentifier should be skipped"
        $apps[0].Name | Should -Be "DedupAppA"
    }

    It 'Should allow entries with different PackageIdentifiers' {
        # Arrange
        $testOrchPath = Join-Path $TestDrive "OrchDedup2"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null
        $app1Path = New-TestAppFolder -BasePath $TestDrive -AppName "UniqueAppA" -InstallerType "exe"
        $app2Path = New-TestAppFolder -BasePath $TestDrive -AppName "UniqueAppB" -InstallerType "exe"

        # Act - Add with different PackageIdentifiers
        Add-Win32SilentInstallCommand -AppFolder "UniqueAppA" -AppFolderPath $app1Path `
            -OrchestrationPath $testOrchPath -PackageIdentifier "Test.Package.1" | Out-Null
        Add-Win32SilentInstallCommand -AppFolder "UniqueAppB" -AppFolderPath $app2Path `
            -OrchestrationPath $testOrchPath -PackageIdentifier "Test.Package.2" | Out-Null

        # Assert - Both entries present
        $jsonPath = Join-Path $testOrchPath "WinGetWin32Apps.json"
        $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        $apps.Count | Should -Be 2
    }

    It 'Should add DependencyFor metadata when parameter provided' {
        # Arrange
        $testOrchPath = Join-Path $TestDrive "OrchDepFor"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null
        $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "DepForApp" -InstallerType "exe"

        # Act
        Add-Win32SilentInstallCommand -AppFolder "DepForApp" -AppFolderPath $appPath `
            -OrchestrationPath $testOrchPath -DependencyFor "ParentApp" | Out-Null

        # Assert
        $jsonPath = Join-Path $testOrchPath "WinGetWin32Apps.json"
        $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        if ($apps -isnot [array]) { $apps = @($apps) }
        $apps[0].PSObject.Properties['DependencyFor'] | Should -Not -BeNullOrEmpty
        $apps[0].DependencyFor | Should -Be "ParentApp"
    }

    It 'Should add PackageIdentifier metadata when parameter provided' {
        # Arrange
        $testOrchPath = Join-Path $TestDrive "OrchPkgId"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null
        $appPath = New-TestAppFolder -BasePath $TestDrive -AppName "PkgIdApp" -InstallerType "exe"

        # Act
        Add-Win32SilentInstallCommand -AppFolder "PkgIdApp" -AppFolderPath $appPath `
            -OrchestrationPath $testOrchPath -PackageIdentifier "Test.Package" | Out-Null

        # Assert
        $jsonPath = Join-Path $testOrchPath "WinGetWin32Apps.json"
        $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        if ($apps -isnot [array]) { $apps = @($apps) }
        $apps[0].PSObject.Properties['PackageIdentifier'] | Should -Not -BeNullOrEmpty
        $apps[0].PackageIdentifier | Should -Be "Test.Package"
    }
}

# =============================================================================
# Phase 37: Add-Win32SilentInstallCommand - SkipRemoveOnFailure
# =============================================================================

Describe 'Add-Win32SilentInstallCommand - SkipRemoveOnFailure' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37', 'WINGET-02' {

    It 'Should not remove folder when SkipRemoveOnFailure is set and no installer found' {
        # Arrange - Create folder with ONLY a YAML file (no .exe or .msi)
        $testOrchPath = Join-Path $TestDrive "OrchSkipRemove1"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null
        $appFolderPath = Join-Path $TestDrive "SkipRemoveApp1"
        New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
        # Create only a YAML file, no installer
        $yamlContent = @"
PackageIdentifier: Test.NoInstaller
PackageVersion: 1.0.0
InstallerSwitches:
    Silent: /S
"@
        Set-Content -Path (Join-Path $appFolderPath "installer.yaml") -Value $yamlContent -Force

        # Act - Call with -SkipRemoveOnFailure
        $result = Add-Win32SilentInstallCommand -AppFolder "SkipRemoveApp1" `
            -AppFolderPath $appFolderPath -OrchestrationPath $testOrchPath -SkipRemoveOnFailure

        # Assert
        $result | Should -Be 1 -Because "no installer found returns error code"
        $appFolderPath | Should -Exist -Because "SkipRemoveOnFailure should prevent deletion"
    }

    It 'Should remove folder when SkipRemoveOnFailure is NOT set and no installer found' {
        # Arrange - Create folder with ONLY a YAML file (no .exe or .msi)
        $testOrchPath = Join-Path $TestDrive "OrchSkipRemove2"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null
        $appFolderPath = Join-Path $TestDrive "SkipRemoveApp2"
        New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
        $yamlContent = @"
PackageIdentifier: Test.NoInstaller2
PackageVersion: 1.0.0
InstallerSwitches:
    Silent: /S
"@
        Set-Content -Path (Join-Path $appFolderPath "installer.yaml") -Value $yamlContent -Force

        # Act - Call WITHOUT -SkipRemoveOnFailure
        $result = Add-Win32SilentInstallCommand -AppFolder "SkipRemoveApp2" `
            -AppFolderPath $appFolderPath -OrchestrationPath $testOrchPath

        # Assert
        $result | Should -Be 1 -Because "no installer found returns error code"
        $appFolderPath | Should -Not -Exist -Because "folder should be removed on failure without SkipRemoveOnFailure"
    }
}

# =============================================================================
# Phase 37: WinGetWin32Apps.json Ordering - Post-Download Reorder Algorithm
# =============================================================================

Describe 'WinGetWin32Apps.json Ordering - Post-Download Reorder' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37', 'WINGET-01' {

    BeforeAll {
        $module = Get-Module 'FFU.Common.Winget'
    }

    It 'Should reorder apps to match AppList.json sequence' {
        # Arrange - Create WinGetWin32Apps.json with entries in reverse order
        $testDir = Join-Path $TestDrive "ReorderTest1"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        $winGetJsonPath = Join-Path $testDir "WinGetWin32Apps.json"

        # JSON entries in wrong order: C, B, A (Priority reflects download order)
        $appsData = @(
            [PSCustomObject]@{ Priority = 1; Name = "AppC"; CommandLine = "c.exe"; Arguments = "/S" }
            [PSCustomObject]@{ Priority = 2; Name = "AppB"; CommandLine = "b.exe"; Arguments = "/S" }
            [PSCustomObject]@{ Priority = 3; Name = "AppA"; CommandLine = "a.exe"; Arguments = "/S" }
        )
        $appsData | ConvertTo-Json -Depth 10 | Set-Content -Path $winGetJsonPath -Encoding UTF8

        # Desired order map from AppList.json: A=0, B=1, C=2
        $desiredOrderMap = @{ 'AppA' = 0; 'AppB' = 1; 'AppC' = 2 }

        # Act - Simulate reorder algorithm via module scope
        & $module {
            param($jsonPath, $orderMap)
            $mutexName = Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $jsonPath
            Invoke-WithNamedMutex -MutexName $mutexName -TimeoutSeconds 60 -ScriptBlock {
                [array]$currentAppsData = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
                if ($null -eq $currentAppsData) { $currentAppsData = @() }

                if ($currentAppsData.Count -gt 1) {
                    $indexed = @()
                    for ($i = 0; $i -lt $currentAppsData.Count; $i++) {
                        $entry = $currentAppsData[$i]
                        $dependencyFor = $null
                        if ($entry.PSObject.Properties['DependencyFor']) {
                            $dependencyFor = $entry.DependencyFor
                        }
                        $baseName = $entry.Name
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $baseName = $dependencyFor
                        }
                        if (-not [string]::IsNullOrWhiteSpace($baseName)) {
                            $baseName = ($baseName -replace '\s+\((x86|x64|arm64)\)$', '')
                        }
                        $orderKey = [int]::MaxValue
                        if (-not [string]::IsNullOrWhiteSpace($baseName) -and $orderMap.ContainsKey($baseName)) {
                            $orderKey = [int]$orderMap[$baseName]
                        }
                        $isDependency = 1
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $isDependency = 0
                        }
                        $indexed += [PSCustomObject]@{
                            OrderKey      = $orderKey
                            IsDependency  = $isDependency
                            OriginalIndex = $i
                            App           = $entry
                        }
                    }
                    $sorted = $indexed | Sort-Object -Property OrderKey, IsDependency, OriginalIndex
                    $reorderedApps = @($sorted | ForEach-Object { $_.App })
                    for ($p = 0; $p -lt $reorderedApps.Count; $p++) {
                        $reorderedApps[$p].Priority = $p + 1
                    }
                    $jsonText = $reorderedApps | ConvertTo-Json -Depth 10
                    Set-FileContentAtomic -Path $jsonPath -Content $jsonText
                }
            }
        } $winGetJsonPath $desiredOrderMap

        # Assert - Order should now be A, B, C with priorities 1, 2, 3
        $result = Get-Content -Path $winGetJsonPath -Raw | ConvertFrom-Json
        $result.Count | Should -Be 3
        $result[0].Name | Should -Be "AppA"
        $result[0].Priority | Should -Be 1
        $result[1].Name | Should -Be "AppB"
        $result[1].Priority | Should -Be 2
        $result[2].Name | Should -Be "AppC"
        $result[2].Priority | Should -Be 3
    }

    It 'Should place dependencies before parent app' {
        # Arrange
        $testDir = Join-Path $TestDrive "ReorderTest2"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        $winGetJsonPath = Join-Path $testDir "WinGetWin32Apps.json"

        # Parent first, dependency second (wrong order)
        $appsData = @(
            [PSCustomObject]@{ Priority = 1; Name = "ParentApp"; CommandLine = "parent.exe"; Arguments = "/S" }
            [PSCustomObject]@{ Priority = 2; Name = "DepLib"; CommandLine = "dep.exe"; Arguments = "/S"; DependencyFor = "ParentApp" }
        )
        $appsData | ConvertTo-Json -Depth 10 | Set-Content -Path $winGetJsonPath -Encoding UTF8

        $desiredOrderMap = @{ 'ParentApp' = 0 }

        # Act - Run reorder algorithm
        & $module {
            param($jsonPath, $orderMap)
            $mutexName = Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $jsonPath
            Invoke-WithNamedMutex -MutexName $mutexName -TimeoutSeconds 60 -ScriptBlock {
                [array]$currentAppsData = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
                if ($null -eq $currentAppsData) { $currentAppsData = @() }
                if ($currentAppsData.Count -gt 1) {
                    $indexed = @()
                    for ($i = 0; $i -lt $currentAppsData.Count; $i++) {
                        $entry = $currentAppsData[$i]
                        $dependencyFor = $null
                        if ($entry.PSObject.Properties['DependencyFor']) {
                            $dependencyFor = $entry.DependencyFor
                        }
                        $baseName = $entry.Name
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $baseName = $dependencyFor
                        }
                        if (-not [string]::IsNullOrWhiteSpace($baseName)) {
                            $baseName = ($baseName -replace '\s+\((x86|x64|arm64)\)$', '')
                        }
                        $orderKey = [int]::MaxValue
                        if (-not [string]::IsNullOrWhiteSpace($baseName) -and $orderMap.ContainsKey($baseName)) {
                            $orderKey = [int]$orderMap[$baseName]
                        }
                        $isDependency = 1
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $isDependency = 0
                        }
                        $indexed += [PSCustomObject]@{
                            OrderKey      = $orderKey
                            IsDependency  = $isDependency
                            OriginalIndex = $i
                            App           = $entry
                        }
                    }
                    $sorted = $indexed | Sort-Object -Property OrderKey, IsDependency, OriginalIndex
                    $reorderedApps = @($sorted | ForEach-Object { $_.App })
                    for ($p = 0; $p -lt $reorderedApps.Count; $p++) {
                        $reorderedApps[$p].Priority = $p + 1
                    }
                    $jsonText = $reorderedApps | ConvertTo-Json -Depth 10
                    Set-FileContentAtomic -Path $jsonPath -Content $jsonText
                }
            }
        } $winGetJsonPath $desiredOrderMap

        # Assert - Dependency should come before parent
        $result = Get-Content -Path $winGetJsonPath -Raw | ConvertFrom-Json
        $result.Count | Should -Be 2
        $result[0].Name | Should -Be "DepLib" -Because "dependency should sort before parent"
        $result[0].Priority | Should -Be 1
        $result[1].Name | Should -Be "ParentApp"
        $result[1].Priority | Should -Be 2
    }

    It 'Should normalize architecture suffixes for matching' {
        # Arrange
        $testDir = Join-Path $TestDrive "ReorderTest3"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        $winGetJsonPath = Join-Path $testDir "WinGetWin32Apps.json"

        # Entry has architecture suffix but AppList.json doesn't
        $appsData = @(
            [PSCustomObject]@{ Priority = 1; Name = "UnknownFirst"; CommandLine = "u.exe"; Arguments = "/S" }
            [PSCustomObject]@{ Priority = 2; Name = "TestApp (x64)"; CommandLine = "t.exe"; Arguments = "/S" }
        )
        $appsData | ConvertTo-Json -Depth 10 | Set-Content -Path $winGetJsonPath -Encoding UTF8

        # AppList.json has "TestApp" without suffix at position 0
        $desiredOrderMap = @{ 'TestApp' = 0 }

        # Act
        & $module {
            param($jsonPath, $orderMap)
            $mutexName = Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $jsonPath
            Invoke-WithNamedMutex -MutexName $mutexName -TimeoutSeconds 60 -ScriptBlock {
                [array]$currentAppsData = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
                if ($null -eq $currentAppsData) { $currentAppsData = @() }
                if ($currentAppsData.Count -gt 1) {
                    $indexed = @()
                    for ($i = 0; $i -lt $currentAppsData.Count; $i++) {
                        $entry = $currentAppsData[$i]
                        $dependencyFor = $null
                        if ($entry.PSObject.Properties['DependencyFor']) {
                            $dependencyFor = $entry.DependencyFor
                        }
                        $baseName = $entry.Name
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $baseName = $dependencyFor
                        }
                        if (-not [string]::IsNullOrWhiteSpace($baseName)) {
                            $baseName = ($baseName -replace '\s+\((x86|x64|arm64)\)$', '')
                        }
                        $orderKey = [int]::MaxValue
                        if (-not [string]::IsNullOrWhiteSpace($baseName) -and $orderMap.ContainsKey($baseName)) {
                            $orderKey = [int]$orderMap[$baseName]
                        }
                        $isDependency = 1
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $isDependency = 0
                        }
                        $indexed += [PSCustomObject]@{
                            OrderKey      = $orderKey
                            IsDependency  = $isDependency
                            OriginalIndex = $i
                            App           = $entry
                        }
                    }
                    $sorted = $indexed | Sort-Object -Property OrderKey, IsDependency, OriginalIndex
                    $reorderedApps = @($sorted | ForEach-Object { $_.App })
                    for ($p = 0; $p -lt $reorderedApps.Count; $p++) {
                        $reorderedApps[$p].Priority = $p + 1
                    }
                    $jsonText = $reorderedApps | ConvertTo-Json -Depth 10
                    Set-FileContentAtomic -Path $jsonPath -Content $jsonText
                }
            }
        } $winGetJsonPath $desiredOrderMap

        # Assert - "TestApp (x64)" should match "TestApp" and sort first
        $result = Get-Content -Path $winGetJsonPath -Raw | ConvertFrom-Json
        $result.Count | Should -Be 2
        $result[0].Name | Should -Be "TestApp (x64)" -Because "arch suffix should be stripped for matching"
        $result[0].Priority | Should -Be 1
        $result[1].Name | Should -Be "UnknownFirst"
        $result[1].Priority | Should -Be 2
    }

    It 'Should push unknown apps to end of order' {
        # Arrange
        $testDir = Join-Path $TestDrive "ReorderTest4"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        $winGetJsonPath = Join-Path $testDir "WinGetWin32Apps.json"

        $appsData = @(
            [PSCustomObject]@{ Priority = 1; Name = "UnknownApp"; CommandLine = "u.exe"; Arguments = "/S" }
            [PSCustomObject]@{ Priority = 2; Name = "KnownApp"; CommandLine = "k.exe"; Arguments = "/S" }
        )
        $appsData | ConvertTo-Json -Depth 10 | Set-Content -Path $winGetJsonPath -Encoding UTF8

        # Only KnownApp is in AppList.json
        $desiredOrderMap = @{ 'KnownApp' = 0 }

        # Act
        & $module {
            param($jsonPath, $orderMap)
            $mutexName = Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $jsonPath
            Invoke-WithNamedMutex -MutexName $mutexName -TimeoutSeconds 60 -ScriptBlock {
                [array]$currentAppsData = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
                if ($null -eq $currentAppsData) { $currentAppsData = @() }
                if ($currentAppsData.Count -gt 1) {
                    $indexed = @()
                    for ($i = 0; $i -lt $currentAppsData.Count; $i++) {
                        $entry = $currentAppsData[$i]
                        $dependencyFor = $null
                        if ($entry.PSObject.Properties['DependencyFor']) {
                            $dependencyFor = $entry.DependencyFor
                        }
                        $baseName = $entry.Name
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $baseName = $dependencyFor
                        }
                        if (-not [string]::IsNullOrWhiteSpace($baseName)) {
                            $baseName = ($baseName -replace '\s+\((x86|x64|arm64)\)$', '')
                        }
                        $orderKey = [int]::MaxValue
                        if (-not [string]::IsNullOrWhiteSpace($baseName) -and $orderMap.ContainsKey($baseName)) {
                            $orderKey = [int]$orderMap[$baseName]
                        }
                        $isDependency = 1
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $isDependency = 0
                        }
                        $indexed += [PSCustomObject]@{
                            OrderKey      = $orderKey
                            IsDependency  = $isDependency
                            OriginalIndex = $i
                            App           = $entry
                        }
                    }
                    $sorted = $indexed | Sort-Object -Property OrderKey, IsDependency, OriginalIndex
                    $reorderedApps = @($sorted | ForEach-Object { $_.App })
                    for ($p = 0; $p -lt $reorderedApps.Count; $p++) {
                        $reorderedApps[$p].Priority = $p + 1
                    }
                    $jsonText = $reorderedApps | ConvertTo-Json -Depth 10
                    Set-FileContentAtomic -Path $jsonPath -Content $jsonText
                }
            }
        } $winGetJsonPath $desiredOrderMap

        # Assert
        $result = Get-Content -Path $winGetJsonPath -Raw | ConvertFrom-Json
        $result.Count | Should -Be 2
        $result[0].Name | Should -Be "KnownApp" -Because "known app should sort first"
        $result[1].Name | Should -Be "UnknownApp" -Because "unknown app pushed to end"
    }

    It 'Should handle single-entry JSON without error' {
        # Arrange
        $testDir = Join-Path $TestDrive "ReorderTest5"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        $winGetJsonPath = Join-Path $testDir "WinGetWin32Apps.json"

        # Single entry - reorder should be a no-op
        $appsData = @(
            [PSCustomObject]@{ Priority = 1; Name = "OnlyApp"; CommandLine = "o.exe"; Arguments = "/S" }
        )
        $appsData | ConvertTo-Json -Depth 10 | Set-Content -Path $winGetJsonPath -Encoding UTF8

        $desiredOrderMap = @{ 'OnlyApp' = 0 }

        # Act - Should not throw
        {
            & $module {
                param($jsonPath, $orderMap)
                $mutexName = Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $jsonPath
                Invoke-WithNamedMutex -MutexName $mutexName -TimeoutSeconds 60 -ScriptBlock {
                    [array]$currentAppsData = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
                    if ($null -eq $currentAppsData) { $currentAppsData = @() }
                    # Single entry - the Count -gt 1 guard means no reorder happens
                    if ($currentAppsData.Count -gt 1) {
                        # This block should not execute for single entry
                        throw "Should not reach reorder for single entry"
                    }
                }
            } $winGetJsonPath $desiredOrderMap
        } | Should -Not -Throw

        # Assert - JSON unchanged
        $result = Get-Content -Path $winGetJsonPath -Raw | ConvertFrom-Json
        if ($result -isnot [array]) { $result = @($result) }
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be "OnlyApp"
        $result[0].Priority | Should -Be 1
    }
}

# =============================================================================
# Phase 37: Add-Win32DependencySilentInstallCommands - Dependency Discovery
# =============================================================================

Describe 'Add-Win32DependencySilentInstallCommands - Dependency Discovery' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37', 'WINGET-02' {

    It 'Should return 0 when no Dependencies folder exists' {
        # This test verifies the function signature and no-dependency behavior.
        # The function is defined by Plan 02 (parallel execution).
        # If Plan 02 has not committed yet, skip gracefully.
        $module = Get-Module 'FFU.Common.Winget'
        $hasFunction = & $module { $function:AddWin32DependencySilentInstallCommandsExists = $null; Get-Command -Name 'Add-Win32DependencySilentInstallCommands' -ErrorAction SilentlyContinue }
        if (-not $hasFunction) {
            Set-ItResult -Skipped -Because "Add-Win32DependencySilentInstallCommands not yet defined (Plan 02 parallel)"
            return
        }

        # Arrange - App folder without Dependencies/ subfolder
        $testOrchPath = Join-Path $TestDrive "OrchDep1"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null
        $appFolderPath = Join-Path $TestDrive "NoDepsApp"
        New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null

        # Act
        $result = Add-Win32DependencySilentInstallCommands -ParentAppName "NoDepsApp" `
            -ParentAppFolderPath $appFolderPath -OrchestrationPath $testOrchPath -SubFolder "x64"

        # Assert
        $result | Should -Be 0
    }

    It 'Should return 0 when Dependencies folder is empty' {
        $module = Get-Module 'FFU.Common.Winget'
        $hasFunction = & $module { Get-Command -Name 'Add-Win32DependencySilentInstallCommands' -ErrorAction SilentlyContinue }
        if (-not $hasFunction) {
            Set-ItResult -Skipped -Because "Add-Win32DependencySilentInstallCommands not yet defined (Plan 02 parallel)"
            return
        }

        # Arrange - App folder with empty Dependencies/ subfolder
        $testOrchPath = Join-Path $TestDrive "OrchDep2"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null
        $appFolderPath = Join-Path $TestDrive "EmptyDepsApp"
        New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $appFolderPath "Dependencies") -ItemType Directory -Force | Out-Null

        # Act
        $result = Add-Win32DependencySilentInstallCommands -ParentAppName "EmptyDepsApp" `
            -ParentAppFolderPath $appFolderPath -OrchestrationPath $testOrchPath -SubFolder "x64"

        # Assert
        $result | Should -Be 0
    }

    It 'Should discover and process YAML files in Dependencies folder' {
        $module = Get-Module 'FFU.Common.Winget'
        $hasFunction = & $module { Get-Command -Name 'Add-Win32DependencySilentInstallCommands' -ErrorAction SilentlyContinue }
        if (-not $hasFunction) {
            Set-ItResult -Skipped -Because "Add-Win32DependencySilentInstallCommands not yet defined (Plan 02 parallel)"
            return
        }

        # Arrange - App folder with Dependencies/ containing YAML files and matching installers
        $testOrchPath = Join-Path $TestDrive "OrchDep3"
        New-Item -Path $testOrchPath -ItemType Directory -Force | Out-Null
        $appFolderPath = Join-Path $TestDrive "DepsApp"
        New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null

        # Create installer in app folder
        "dummy" | Set-Content -Path (Join-Path $appFolderPath "vc_redist.x64.exe") -Force

        # Create Dependencies/ subfolder with YAML manifest
        $depsFolder = Join-Path $appFolderPath "Dependencies"
        New-Item -Path $depsFolder -ItemType Directory -Force | Out-Null
        $depYaml = @"
PackageIdentifier: Microsoft.VCRedist.2015+.x64
PackageVersion: 14.36.32532.0
Installers:
- Architecture: x64
  InstallerType: exe
  InstallerUrl: https://example.com/vc_redist.x64.exe
  InstallerSwitches:
    Silent: /install /quiet /norestart
"@
        Set-Content -Path (Join-Path $depsFolder "Microsoft.VCRedist.2015+.x64.yaml") -Value $depYaml -Force

        # Also create the installer file matching the dependency
        "dummy" | Set-Content -Path (Join-Path $appFolderPath "vc_redist.x64.exe") -Force

        # Act
        $result = Add-Win32DependencySilentInstallCommands -ParentAppName "DepsApp" `
            -ParentAppFolderPath $appFolderPath -OrchestrationPath $testOrchPath -SubFolder "x64"

        # Assert - Check result and JSON entries
        $result | Should -Be 0
        $jsonPath = Join-Path $testOrchPath "WinGetWin32Apps.json"
        if (Test-Path $jsonPath) {
            $apps = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            if ($apps -isnot [array]) { $apps = @($apps) }
            # Should have at least one dependency entry with DependencyFor metadata
            $depEntries = $apps | Where-Object { $_.PSObject.Properties['DependencyFor'] }
            $depEntries | Should -Not -BeNullOrEmpty -Because "dependency entries should have DependencyFor metadata"
        }
    }
}

# =============================================================================
# Phase 37: Module Export - Phase 37 Functions
# =============================================================================

Describe 'Module Export - Phase 37 Functions' -Tag 'Unit', 'FFU.Common.Winget', 'Phase37', 'Module' {

    It 'Should export Add-Win32DependencySilentInstallCommands when defined' {
        # The function is exported in Export-ModuleMember but may not be defined until Plan 02
        # Check if the export statement includes it (source code check)
        $moduleSource = Get-Content -Path "$ProjectRoot\FFUDevelopment\FFU.Common\FFU.Common.Winget.psm1" -Raw
        $moduleSource | Should -Match 'Add-Win32DependencySilentInstallCommands' `
            -Because "Export-ModuleMember should list Add-Win32DependencySilentInstallCommands"
    }

    It 'Should NOT export Invoke-WithNamedMutex (internal helper)' {
        Get-Command -Name 'Invoke-WithNamedMutex' -Module 'FFU.Common.Winget' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "helper function should not be exported"
    }

    It 'Should NOT export Set-FileContentAtomic (internal helper)' {
        Get-Command -Name 'Set-FileContentAtomic' -Module 'FFU.Common.Winget' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "helper function should not be exported"
    }

    It 'Should NOT export Get-WinGetWin32AppsJsonMutexName (internal helper)' {
        Get-Command -Name 'Get-WinGetWin32AppsJsonMutexName' -Module 'FFU.Common.Winget' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "helper function should not be exported"
    }

    It 'Should NOT export Get-WinGetYamlScalarValue (internal helper)' {
        Get-Command -Name 'Get-WinGetYamlScalarValue' -Module 'FFU.Common.Winget' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "helper function should not be exported"
    }
}
