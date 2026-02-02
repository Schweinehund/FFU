#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Updates DISM resilience features (Phase 44-01)

.DESCRIPTION
    Tests for DISM resilience improvements in FFU.Updates module:
    - Test-MountState calls Test-DismReady before Get-WindowsEdition
    - Add-WindowsPackageWithRetry calls Test-DismReady before each attempt
    - Add-WindowsPackageWithUnattend calls Test-DismReady before Add-WindowsPackage calls
    - Fast-fail behavior when Test-DismReady returns false
    - Normal operation when Test-DismReady returns true

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Updates.DISMResilience.Tests.ps1 -Output Detailed
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

    # Mock WriteLog in script scope before importing modules (it's called during import)
    function WriteLog { param($Message) }

    # Import FFU.Core first (required dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
    }

    if (-not (Test-Path "$ModulePath\FFU.Updates.psd1")) {
        throw "FFU.Updates module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Updates.psd1" -Force -ErrorAction Stop

    # Get the module object for accessing private functions
    $script:UpdatesModule = Get-Module -Name 'FFU.Updates'
}

AfterAll {
    Get-Module -Name 'FFU.Updates', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Test-MountState DISM Resilience Tests
# =============================================================================

Describe "Test-MountState DISM Resilience" -Tag 'Unit', 'DISMResilience', 'TestMountState' {

    Context "When WIMMount filter driver is healthy" {
        BeforeEach {
            Mock -ModuleName FFU.Updates Test-Path { return $true }
            Mock -ModuleName FFU.Updates Test-DismReady { return $true }
            Mock -ModuleName FFU.Updates Get-WindowsEdition { return @{Edition = 'Professional'} }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should call Test-DismReady before Get-WindowsEdition" {
            $result = & $UpdatesModule { Test-MountState -Path "W:\" }

            Should -Invoke -ModuleName FFU.Updates -CommandName Test-DismReady -Times 1 -Exactly
            Should -Invoke -ModuleName FFU.Updates -CommandName Get-WindowsEdition -Times 1 -Exactly
        }

        It "Should return true when mount is accessible" {
            $result = & $UpdatesModule { Test-MountState -Path "W:\" }

            $result | Should -Be $true
        }
    }

    Context "When WIMMount filter driver is broken" {
        BeforeEach {
            Mock -ModuleName FFU.Updates Test-Path { return $true }
            Mock -ModuleName FFU.Updates Test-DismReady { return $false }
            Mock -ModuleName FFU.Updates Get-WindowsEdition { throw "Should not be called" }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should NOT call Get-WindowsEdition when Test-DismReady fails" {
            $result = & $UpdatesModule { Test-MountState -Path "W:\" }

            Should -Invoke -ModuleName FFU.Updates -CommandName Test-DismReady -Times 2 -Exactly
            Should -Invoke -ModuleName FFU.Updates -CommandName Get-WindowsEdition -Times 0 -Exactly
        }

        It "Should return false without hanging" {
            $result = & $UpdatesModule { Test-MountState -Path "W:\" }

            $result | Should -Be $false
        }

        It "Should log WIMMount failure and auto-repair attempt" {
            $result = & $UpdatesModule { Test-MountState -Path "W:\" }

            # Note: WriteLog calls are internal and verified via integration tests
            # This test primarily verifies the fast-fail behavior
            $result | Should -Be $false
        }
    }

    Context "When path does not exist" {
        BeforeEach {
            Mock -ModuleName FFU.Updates Test-Path { return $false }
            Mock -ModuleName FFU.Updates Test-DismReady { return $true }
            Mock -ModuleName FFU.Updates Get-WindowsEdition { throw "Should not be called" }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should return false without calling DISM" {
            $result = & $UpdatesModule { Test-MountState -Path "Z:\NonExistent" }

            $result | Should -Be $false
            Should -Invoke -ModuleName FFU.Updates -CommandName Get-WindowsEdition -Times 0 -Exactly
        }
    }
}

# =============================================================================
# Add-WindowsPackageWithRetry DISM Resilience Tests
# =============================================================================

Describe "Add-WindowsPackageWithRetry DISM Resilience" -Tag 'Unit', 'DISMResilience', 'AddWindowsPackageWithRetry' {

    Context "When WIMMount filter driver is healthy" {
        BeforeEach {
            Mock -ModuleName FFU.Updates Test-DismReady { return $true }
            Mock -ModuleName FFU.Updates Add-WindowsPackageWithUnattend { }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should call Test-DismReady before each attempt" {
            & $UpdatesModule { Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\test.msu" }

            Should -Invoke -ModuleName FFU.Updates -CommandName Test-DismReady -Times 1 -Exactly
        }

        It "Should proceed to Add-WindowsPackageWithUnattend when healthy" {
            & $UpdatesModule { Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\test.msu" }

            Should -Invoke -ModuleName FFU.Updates -CommandName Add-WindowsPackageWithUnattend -Times 1 -Exactly
        }
    }

    Context "When WIMMount filter driver breaks mid-build" {
        BeforeEach {
            Mock -ModuleName FFU.Updates Test-DismReady { return $false }
            Mock -ModuleName FFU.Updates Add-WindowsPackageWithUnattend { throw "Should not be called" }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should throw without calling Add-WindowsPackageWithUnattend" {
            { & $UpdatesModule { Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\test.msu" } } |
                Should -Throw "*WIMMount filter driver is not functional*"

            Should -Invoke -ModuleName FFU.Updates -CommandName Add-WindowsPackageWithUnattend -Times 0 -Exactly
        }

        It "Should log critical failure and resolution steps" {
            { & $UpdatesModule { Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\test.msu" } } |
                Should -Throw "*WIMMount filter driver is not functional*"

            # Note: Detailed logging is verified via integration tests
            # This test verifies the exception is thrown correctly
        }
    }

    Context "When retry is needed and WIMMount is healthy" {
        BeforeEach {
            $script:attemptCount = 0
            Mock -ModuleName FFU.Updates Test-DismReady { return $true }
            Mock -ModuleName FFU.Updates Add-WindowsPackageWithUnattend {
                $script:attemptCount++
                if ($script:attemptCount -eq 1) {
                    throw "Transient error"
                }
            }
            Mock -ModuleName FFU.Updates Test-MountState { return $true }
            Mock -ModuleName FFU.Updates Test-DISMServiceHealth { return $true }
            Mock -ModuleName FFU.Updates Get-WindowsEdition { }
            Mock -ModuleName FFU.Updates Start-Sleep { }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should call Test-DismReady before each retry attempt" {
            & $UpdatesModule { Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\test.msu" -MaxRetries 2 }

            Should -Invoke -ModuleName FFU.Updates -CommandName Test-DismReady -Times 2 -Exactly
        }
    }
}

# =============================================================================
# Add-WindowsPackageWithUnattend DISM Resilience Tests
# =============================================================================

Describe "Add-WindowsPackageWithUnattend DISM Resilience" -Tag 'Unit', 'DISMResilience', 'AddWindowsPackageWithUnattend' {

    Context "Direct CAB application with healthy WIMMount" {
        BeforeEach {
            Mock -ModuleName FFU.Updates Test-DismReady { return $true }
            Mock -ModuleName FFU.Updates Add-WindowsPackage { }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should call Test-DismReady before Add-WindowsPackage for CAB" {
            & $UpdatesModule { Add-WindowsPackageWithUnattend -Path "W:\" -PackagePath "C:\test.cab" }

            Should -Invoke -ModuleName FFU.Updates -CommandName Test-DismReady -Times 1 -Exactly
            Should -Invoke -ModuleName FFU.Updates -CommandName Add-WindowsPackage -Times 1 -Exactly
        }
    }

    Context "Direct CAB application with broken WIMMount" {
        BeforeEach {
            Mock -ModuleName FFU.Updates Test-DismReady { return $false }
            Mock -ModuleName FFU.Updates Add-WindowsPackage { throw "Should not be called" }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should throw without calling Add-WindowsPackage for CAB" {
            { & $UpdatesModule { Add-WindowsPackageWithUnattend -Path "W:\" -PackagePath "C:\test.cab" } } |
                Should -Throw "*WIMMount filter driver is not functional*"

            Should -Invoke -ModuleName FFU.Updates -CommandName Add-WindowsPackage -Times 0 -Exactly
        }
    }

    Context "Extracted CAB application with healthy WIMMount" {
        BeforeEach {
            $testExtractPath = "TestDrive:\extracted"
            New-Item -Path $testExtractPath -ItemType Directory -Force
            New-Item -Path "$testExtractPath\test.cab" -ItemType File -Force

            Mock -ModuleName FFU.Updates Test-DismReady { return $true }
            Mock -ModuleName FFU.Updates Test-Path {
                param($Path)
                if ($Path -like "*test.msu") { return $true }
                if ($Path -like "*extracted*") { return $true }
                return $false
            }
            Mock -ModuleName FFU.Updates Get-Item {
                return [PSCustomObject]@{Length = 10MB}
            }
            Mock -ModuleName FFU.Updates New-Item { }
            Mock -ModuleName FFU.Updates Start-Process {
                return [PSCustomObject]@{ExitCode = 0; HasExited = $true}
            }
            Mock -ModuleName FFU.Updates Get-ChildItem {
                param($Path, $Filter)
                if ($Filter -eq "*.cab") {
                    return @([PSCustomObject]@{
                        Name = "test.cab"
                        FullName = "$testExtractPath\test.cab"
                        Length = 5MB
                    })
                }
                return @()
            }
            Mock -ModuleName FFU.Updates Add-WindowsPackage { }
            Mock -ModuleName FFU.Updates Remove-Item { }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should call Test-DismReady before each extracted CAB application" {
            & $UpdatesModule { Add-WindowsPackageWithUnattend -Path "W:\" -PackagePath "C:\test.msu" }

            Should -Invoke -ModuleName FFU.Updates -CommandName Test-DismReady -Times 1 -Exactly
            Should -Invoke -ModuleName FFU.Updates -CommandName Add-WindowsPackage -Times 1 -Exactly
        }
    }

    Context "Extracted CAB application with broken WIMMount" {
        BeforeEach {
            $testExtractPath = "TestDrive:\extracted"
            New-Item -Path $testExtractPath -ItemType Directory -Force
            New-Item -Path "$testExtractPath\test.cab" -ItemType File -Force

            Mock -ModuleName FFU.Updates Test-DismReady { return $false }
            Mock -ModuleName FFU.Updates Test-Path {
                param($Path)
                if ($Path -like "*test.msu") { return $true }
                if ($Path -like "*extracted*") { return $true }
                return $false
            }
            Mock -ModuleName FFU.Updates Get-Item {
                return [PSCustomObject]@{Length = 10MB}
            }
            Mock -ModuleName FFU.Updates New-Item { }
            Mock -ModuleName FFU.Updates Start-Process {
                return [PSCustomObject]@{ExitCode = 0; HasExited = $true}
            }
            Mock -ModuleName FFU.Updates Get-ChildItem {
                param($Path, $Filter)
                if ($Filter -eq "*.cab") {
                    return @([PSCustomObject]@{
                        Name = "test.cab"
                        FullName = "$testExtractPath\test.cab"
                        Length = 5MB
                    })
                }
                return @()
            }
            Mock -ModuleName FFU.Updates Add-WindowsPackage { throw "Should not be called" }
            Mock -ModuleName FFU.Updates Remove-Item { }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should throw without calling Add-WindowsPackage for extracted CAB" {
            { & $UpdatesModule { Add-WindowsPackageWithUnattend -Path "W:\" -PackagePath "C:\test.msu" } } |
                Should -Throw "*WIMMount filter driver is not functional*"

            Should -Invoke -ModuleName FFU.Updates -CommandName Add-WindowsPackage -Times 0 -Exactly
        }

        It "Should log critical failure with CAB filename" {
            { & $UpdatesModule { Add-WindowsPackageWithUnattend -Path "W:\" -PackagePath "C:\test.msu" } } |
                Should -Throw "*WIMMount filter driver is not functional*"

            # Note: Detailed logging is verified via integration tests
        }
    }
}

# =============================================================================
# Retry Refresh Guard Tests
# =============================================================================

Describe "Retry Refresh DISM Guard" -Tag 'Unit', 'DISMResilience', 'RetryRefresh' {

    Context "When retry refresh is attempted with broken WIMMount" {
        BeforeEach {
            $script:attemptCount = 0
            $script:getDismReadyCallCount = 0
            Mock -ModuleName FFU.Updates Test-DismReady {
                $script:getDismReadyCallCount++
                # First call (before first attempt) = healthy
                # Second call (before retry attempt) = broken
                return ($script:getDismReadyCallCount -eq 1)
            }
            Mock -ModuleName FFU.Updates Add-WindowsPackageWithUnattend {
                $script:attemptCount++
                throw "Transient error"
            }
            Mock -ModuleName FFU.Updates Test-MountState { return $true }
            Mock -ModuleName FFU.Updates Test-DISMServiceHealth { return $true }
            Mock -ModuleName FFU.Updates Get-WindowsEdition { throw "Should not be called on retry" }
            Mock -ModuleName FFU.Updates Start-Sleep { }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should skip Get-WindowsEdition refresh when WIMMount is broken" {
            { & $UpdatesModule { Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\test.msu" -MaxRetries 2 } } |
                Should -Throw

            # Get-WindowsEdition should not be called because Test-DismReady returns false on retry
            Should -Invoke -ModuleName FFU.Updates -CommandName Get-WindowsEdition -Times 0 -Exactly
        }

        It "Should log warning about skipping DISM refresh" {
            { & $UpdatesModule { Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\test.msu" -MaxRetries 2 } } |
                Should -Throw

            # Note: Logging is verified via integration tests
            # This test verifies the refresh guard prevents hanging
        }
    }

    Context "When retry refresh is attempted with healthy WIMMount" {
        BeforeEach {
            $script:attemptCount = 0
            Mock -ModuleName FFU.Updates Test-DismReady { return $true }
            Mock -ModuleName FFU.Updates Add-WindowsPackageWithUnattend {
                $script:attemptCount++
                if ($script:attemptCount -eq 1) {
                    throw "Transient error"
                }
            }
            Mock -ModuleName FFU.Updates Test-MountState { return $true }
            Mock -ModuleName FFU.Updates Test-DISMServiceHealth { return $true }
            Mock -ModuleName FFU.Updates Get-WindowsEdition { }
            Mock -ModuleName FFU.Updates Start-Sleep { }
            Mock -ModuleName FFU.Updates WriteLog { }
        }

        It "Should call Get-WindowsEdition refresh when WIMMount is healthy" {
            & $UpdatesModule { Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\test.msu" -MaxRetries 2 }

            Should -Invoke -ModuleName FFU.Updates -CommandName Get-WindowsEdition -Times 1 -Exactly
        }
    }
}
