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
        param([string]$Message)
        # No-op for tests
    }

    # Helper function to create test app folder with installer and YAML
    function New-TestAppFolder {
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
        It 'Should use named mutex WinGetWin32AppsJsonLock' {
            # Arrange - Get the module source code
            $moduleSource = Get-Content -Path "$ProjectRoot\FFUDevelopment\FFU.Common\FFU.Common.Winget.psm1" -Raw

            # Assert - Check for mutex lock name in source code
            $moduleSource | Should -Match 'WinGetWin32AppsJsonLock' -Because "function must use named mutex for cross-process synchronization"
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
            $result = Add-Win32SilentInstallCommand -AppFolder "TestMSI" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath

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
            $result = Add-Win32SilentInstallCommand -AppFolder "TestMSITrim" -AppFolderPath $appPath -OrchestrationPath $testOrchestrationPath

            # Assert - Function requires silent switch, so test with one
            $result | Should -Be 0
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
