#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for FFU.Core session recovery functionality (REL-CORE-03)

.DESCRIPTION
    Tests the Restore-FFUSession and Test-FFUSessionExists functions
    that provide session state recovery after unexpected interruption.

.NOTES
    Module: FFU.Core
    Functions: Restore-FFUSession, Test-FFUSessionExists
    Version: 1.0.20
#>

BeforeAll {
    # Set up module path for FFU modules
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    # Add modules folder to PSModulePath
    if ($env:PSModulePath -notlike "*$ModulePath*") {
        $env:PSModulePath = "$ModulePath;$env:PSModulePath"
    }

    # Import the module
    Import-Module FFU.Core -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Restore-FFUSession' -Tag 'Unit', 'FFU.Core', 'SessionRecovery' {

    BeforeAll {
        # Create test directory structure in TestDrive
        $script:TestFFUPath = Join-Path $TestDrive 'FFUDevelopment'
        New-Item -ItemType Directory -Path $script:TestFFUPath -Force | Out-Null
    }

    AfterEach {
        # Clean up session directory after each test
        $sessionDir = Join-Path $script:TestFFUPath '.session'
        if (Test-Path $sessionDir) {
            Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'No existing session' {

        It 'Returns WasRecovered=false when no session exists' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.WasRecovered | Should -BeFalse
        }

        It 'Returns empty Errors list when no session exists' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.Errors.Count | Should -Be 0
        }

        It 'Returns null RunStartUtc when no session exists' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.RunStartUtc | Should -BeNullOrEmpty
        }

        It 'Returns zero InProgressItems when no session exists' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.InProgressItems | Should -Be 0
        }
    }

    Context 'Valid session file' {

        BeforeEach {
            # Create session directory and valid manifest
            $sessionDir = Join-Path $script:TestFFUPath '.session'
            New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

            $script:TestRunStartUtc = (Get-Date).ToUniversalTime().ToString('o')
            $manifest = @{
                RunStartUtc      = $script:TestRunStartUtc
                JsonBackups      = @()
                OfficeXmlBackups = @()
            }
            $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $sessionDir 'currentRun.json')
        }

        It 'Returns WasRecovered=true when session exists' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.WasRecovered | Should -BeTrue
        }

        It 'Parses RunStartUtc correctly' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.RunStartUtc | Should -Not -BeNullOrEmpty
            $result.RunStartUtc | Should -BeOfType [datetime]
        }

        It 'Returns empty Errors list for valid session' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.Errors.Count | Should -Be 0
        }
    }

    Context 'Session with in-progress items' {

        BeforeEach {
            # Create session directory, manifest, and in-progress markers
            $sessionDir = Join-Path $script:TestFFUPath '.session'
            $inprogDir = Join-Path $sessionDir 'inprogress'
            New-Item -ItemType Directory -Path $inprogDir -Force | Out-Null

            $manifest = @{
                RunStartUtc      = (Get-Date).ToUniversalTime().ToString('o')
                JsonBackups      = @()
                OfficeXmlBackups = @()
            }
            $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $sessionDir 'currentRun.json')

            # Create some marker files
            @{ TargetPath = 'C:\Test\File1.cab'; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') } |
            ConvertTo-Json | Set-Content (Join-Path $inprogDir 'marker1.marker')

            @{ TargetPath = 'C:\Test\File2.exe'; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') } |
            ConvertTo-Json | Set-Content (Join-Path $inprogDir 'marker2.marker')
        }

        It 'Counts in-progress items correctly' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.InProgressItems | Should -Be 2
        }

        It 'Reports in-progress items without CleanupInProgress switch' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.InProgressItems | Should -BeGreaterThan 0
            $result.WasRecovered | Should -BeTrue
        }
    }

    Context 'Session with backups' {

        BeforeEach {
            # Create session directory, backups directory
            $sessionDir = Join-Path $script:TestFFUPath '.session'
            $backupDir = Join-Path $sessionDir 'backups'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

            # Create a backup file
            $originalPath = Join-Path $script:TestFFUPath 'config.json'
            $backupPath = Join-Path $backupDir 'config.json.bak'
            '{"original": true}' | Set-Content $originalPath
            '{"backup": true}' | Set-Content $backupPath

            $manifest = @{
                RunStartUtc      = (Get-Date).ToUniversalTime().ToString('o')
                JsonBackups      = @(
                    @{ Path = $originalPath; Backup = $backupPath }
                )
                OfficeXmlBackups = @()
            }
            $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $sessionDir 'currentRun.json')
        }

        It 'Does not restore backups without RestoreBackups switch' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.BackupsRestored | Should -Be 0
        }

        It 'Restores backups with RestoreBackups switch' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath -RestoreBackups
            $result.BackupsRestored | Should -Be 1
        }

        It 'Restored file contains backup content' {
            $originalPath = Join-Path $script:TestFFUPath 'config.json'
            $null = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath -RestoreBackups
            $content = Get-Content $originalPath -Raw | ConvertFrom-Json
            $content.backup | Should -BeTrue
        }
    }

    Context 'Corrupted session file' {

        BeforeEach {
            # Create session directory with corrupted manifest
            $sessionDir = Join-Path $script:TestFFUPath '.session'
            New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
            'not valid json{{{' | Set-Content (Join-Path $sessionDir 'currentRun.json')
        }

        It 'Handles corrupted JSON gracefully' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.WasRecovered | Should -BeFalse
        }

        It 'Adds error message for corrupted session' {
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.Errors | Should -Not -BeNullOrEmpty
            $result.Errors[0] | Should -Match 'corrupted'
        }

        It 'Removes corrupted session file' {
            $manifestPath = Join-Path $script:TestFFUPath '.session\currentRun.json'
            $null = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            Test-Path $manifestPath | Should -BeFalse
        }
    }

    Context 'Parameter validation' {

        It 'Requires FFUDevelopmentPath parameter' {
            { Restore-FFUSession } | Should -Throw -ErrorId 'MissingMandatoryParameter*'
        }

        It 'Validates FFUDevelopmentPath exists' {
            { Restore-FFUSession -FFUDevelopmentPath 'C:\NonExistent\Path\12345' } |
            Should -Throw
        }
    }
}

Describe 'Test-FFUSessionExists' -Tag 'Unit', 'FFU.Core', 'SessionRecovery' {

    BeforeAll {
        $script:TestFFUPath = Join-Path $TestDrive 'FFUDevelopment'
        New-Item -ItemType Directory -Path $script:TestFFUPath -Force | Out-Null
    }

    AfterEach {
        $sessionDir = Join-Path $script:TestFFUPath '.session'
        if (Test-Path $sessionDir) {
            Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'No session exists' {

        It 'Returns false when no session exists' {
            $result = Test-FFUSessionExists -FFUDevelopmentPath $script:TestFFUPath
            $result | Should -BeFalse
        }

        It 'Returns false when session directory exists but manifest is missing' {
            $sessionDir = Join-Path $script:TestFFUPath '.session'
            New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
            $result = Test-FFUSessionExists -FFUDevelopmentPath $script:TestFFUPath
            $result | Should -BeFalse
        }
    }

    Context 'Session exists' {

        BeforeEach {
            $sessionDir = Join-Path $script:TestFFUPath '.session'
            New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
            '{}' | Set-Content (Join-Path $sessionDir 'currentRun.json')
        }

        It 'Returns true when session manifest exists' {
            $result = Test-FFUSessionExists -FFUDevelopmentPath $script:TestFFUPath
            $result | Should -BeTrue
        }
    }

    Context 'Parameter validation' {

        It 'Requires FFUDevelopmentPath parameter' {
            { Test-FFUSessionExists } | Should -Throw -ErrorId 'MissingMandatoryParameter*'
        }
    }
}

Describe 'Session Recovery Integration' -Tag 'Unit', 'FFU.Core', 'SessionRecovery', 'Integration' {

    BeforeAll {
        $script:TestFFUPath = Join-Path $TestDrive 'FFUDevelopment'
        New-Item -ItemType Directory -Path $script:TestFFUPath -Force | Out-Null
    }

    AfterEach {
        $sessionDir = Join-Path $script:TestFFUPath '.session'
        if (Test-Path $sessionDir) {
            Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Full recovery workflow' {

        It 'Test-FFUSessionExists and Restore-FFUSession work together' {
            # Initially no session
            Test-FFUSessionExists -FFUDevelopmentPath $script:TestFFUPath | Should -BeFalse

            # Create a session
            $sessionDir = Join-Path $script:TestFFUPath '.session'
            New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
            @{
                RunStartUtc      = (Get-Date).ToUniversalTime().ToString('o')
                JsonBackups      = @()
                OfficeXmlBackups = @()
            } | ConvertTo-Json | Set-Content (Join-Path $sessionDir 'currentRun.json')

            # Now session exists
            Test-FFUSessionExists -FFUDevelopmentPath $script:TestFFUPath | Should -BeTrue

            # Recovery succeeds
            $result = Restore-FFUSession -FFUDevelopmentPath $script:TestFFUPath
            $result.WasRecovered | Should -BeTrue
        }
    }
}
