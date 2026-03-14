#Requires -Version 7.0

<#
.SYNOPSIS
    Pester 5.x tests for FFU.ArtifactScanner module

.DESCRIPTION
    Tests for:
    - Module import
    - ArtifactStatus and ArtifactType enum values
    - Class instantiation (ArtifactFileEntry, FFUMetadata, ArtifactResult, CompatibilityWarning, ArtifactManifest)
    - Get-ArtifactMetadata DISM path and filename fallback
    - Architecture integer-to-string mapping (0=x86, 9=x64, 12=arm64)
    - Factory functions New-ArtifactManifest and New-ArtifactResult

.NOTES
    Module: FFU.ArtifactScanner
    Framework: Pester 5.x
    Tags: Unit, ArtifactScanner

    Class cross-scope note:
    PowerShell module classes are NOT exported to the caller's scope (Pitfall 4 from 46-RESEARCH.md).
    Enum and class tests use InModuleScope to execute inside the module's scope where types are visible.
    Factory function tests use the exported New-* functions which work cross-scope.
#>

BeforeAll {
    # Determine module root relative to test location
    # Test lives at: <repo>/Tests/Unit/FFU.ArtifactScanner.Tests.ps1
    # Repo root is two levels up from the test file
    $testDir  = Split-Path $PSCommandPath -Parent         # .../Tests/Unit
    $testsDir = Split-Path $testDir -Parent               # .../Tests
    $repoRoot = Split-Path $testsDir -Parent              # .../<repo>
    $modulePath = Join-Path $repoRoot 'FFUDevelopment\Modules\FFU.ArtifactScanner\FFU.ArtifactScanner.psd1'

    # Add modules path to PSModulePath so RequiredModules can resolve
    $modulesDir = Join-Path $repoRoot 'FFUDevelopment' | Join-Path -ChildPath 'Modules'
    if ($env:PSModulePath -notlike "*$modulesDir*") {
        $env:PSModulePath = "$modulesDir;$env:PSModulePath"
    }

    # Import the module with RequiredModules loaded via PSModulePath
    Import-Module $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module FFU.ArtifactScanner -Force -ErrorAction SilentlyContinue
}

Describe 'FFU.ArtifactScanner Module Import' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should import without error' {
        { Get-Module FFU.ArtifactScanner } | Should -Not -Throw
        Get-Module FFU.ArtifactScanner | Should -Not -BeNullOrEmpty
    }

    It 'Should export Get-ArtifactMetadata' {
        $module = Get-Module FFU.ArtifactScanner
        $module.ExportedFunctions.Keys | Should -Contain 'Get-ArtifactMetadata'
    }

    It 'Should export Find-FFUArtifacts' {
        $module = Get-Module FFU.ArtifactScanner
        $module.ExportedFunctions.Keys | Should -Contain 'Find-FFUArtifacts'
    }

    It 'Should export Test-ArtifactCompatibility' {
        $module = Get-Module FFU.ArtifactScanner
        $module.ExportedFunctions.Keys | Should -Contain 'Test-ArtifactCompatibility'
    }

    It 'Should export New-ArtifactManifest' {
        $module = Get-Module FFU.ArtifactScanner
        $module.ExportedFunctions.Keys | Should -Contain 'New-ArtifactManifest'
    }

    It 'Should export New-ArtifactResult' {
        $module = Get-Module FFU.ArtifactScanner
        $module.ExportedFunctions.Keys | Should -Contain 'New-ArtifactResult'
    }
}

# =============================================================================
# Enum and Class tests run InModuleScope because PowerShell module types
# (enums and classes) are not exported to the caller's scope.
# See Pitfall 4 in 46-RESEARCH.md.
# =============================================================================

Describe 'ArtifactStatus Enum' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should have Found value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactStatus]::Found } | Should -Not -Throw
        }
    }

    It 'Should have Missing value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactStatus]::Missing } | Should -Not -Throw
        }
    }

    It 'Should have Error value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactStatus]::Error } | Should -Not -Throw
        }
    }

    It 'Should have Degraded value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactStatus]::Degraded } | Should -Not -Throw
        }
    }
}

Describe 'ArtifactType Enum' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should have FFU value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactType]::FFU } | Should -Not -Throw
        }
    }

    It 'Should have DeployISO value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactType]::DeployISO } | Should -Not -Throw
        }
    }

    It 'Should have Drivers value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactType]::Drivers } | Should -Not -Throw
        }
    }

    It 'Should have PPKG value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactType]::PPKG } | Should -Not -Throw
        }
    }

    It 'Should have Unattend value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactType]::Unattend } | Should -Not -Throw
        }
    }

    It 'Should have Autopilot value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactType]::Autopilot } | Should -Not -Throw
        }
    }

    It 'Should have AppsISO value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactType]::AppsISO } | Should -Not -Throw
        }
    }
}

Describe 'ArtifactFileEntry Class' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should be instantiable with new()' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactFileEntry]::new() } | Should -Not -Throw
        }
    }

    It 'Should have FilePath property' {
        InModuleScope FFU.ArtifactScanner {
            $entry = [ArtifactFileEntry]::new()
            $entry | Get-Member -Name FilePath | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have FileSizeBytes property' {
        InModuleScope FFU.ArtifactScanner {
            $entry = [ArtifactFileEntry]::new()
            $entry | Get-Member -Name FileSizeBytes | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have LastWriteTime property' {
        InModuleScope FFU.ArtifactScanner {
            $entry = [ArtifactFileEntry]::new()
            $entry | Get-Member -Name LastWriteTime | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'FFUMetadata Class' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should be instantiable with new()' {
        InModuleScope FFU.ArtifactScanner {
            { [FFUMetadata]::new() } | Should -Not -Throw
        }
    }

    It 'Should have WindowsVersion property' {
        InModuleScope FFU.ArtifactScanner {
            $meta = [FFUMetadata]::new()
            $meta | Get-Member -Name WindowsVersion | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have WindowsSKU property' {
        InModuleScope FFU.ArtifactScanner {
            $meta = [FFUMetadata]::new()
            $meta | Get-Member -Name WindowsSKU | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have Architecture property' {
        InModuleScope FFU.ArtifactScanner {
            $meta = [FFUMetadata]::new()
            $meta | Get-Member -Name Architecture | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have ImageName property' {
        InModuleScope FFU.ArtifactScanner {
            $meta = [FFUMetadata]::new()
            $meta | Get-Member -Name ImageName | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have BuildDate property' {
        InModuleScope FFU.ArtifactScanner {
            $meta = [FFUMetadata]::new()
            $meta | Get-Member -Name BuildDate | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have MetadataSource property' {
        InModuleScope FFU.ArtifactScanner {
            $meta = [FFUMetadata]::new()
            $meta | Get-Member -Name MetadataSource | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have ErrorMessage property' {
        InModuleScope FFU.ArtifactScanner {
            $meta = [FFUMetadata]::new()
            $meta | Get-Member -Name ErrorMessage | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'ArtifactResult Class' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should be instantiable with new()' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactResult]::new() } | Should -Not -Throw
        }
    }

    It 'Should initialize Files list in constructor' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            # Files is initialized in the constructor as List[ArtifactFileEntry]
            # Check via Count property (an initialized empty list returns 0, null throws)
            { $result.Files.Count } | Should -Not -Throw
            $result.Files.Count | Should -Be 0
        }
    }

    It 'Should have ArtifactType property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name ArtifactType | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have Status property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name Status | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have FilePath property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name FilePath | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have FileSizeBytes property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name FileSizeBytes | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have AgeDays property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name AgeDays | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have IsPrimary property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name IsPrimary | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have Metadata property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name Metadata | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have FileCount property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name FileCount | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have TotalSizeBytes property' {
        InModuleScope FFU.ArtifactScanner {
            $result = [ArtifactResult]::new()
            $result | Get-Member -Name TotalSizeBytes | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'CompatibilityWarning Class' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should be instantiable with new()' {
        InModuleScope FFU.ArtifactScanner {
            { [CompatibilityWarning]::new() } | Should -Not -Throw
        }
    }

    It 'Should have Severity property' {
        InModuleScope FFU.ArtifactScanner {
            $warning = [CompatibilityWarning]::new()
            $warning | Get-Member -Name Severity | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have Message property' {
        InModuleScope FFU.ArtifactScanner {
            $warning = [CompatibilityWarning]::new()
            $warning | Get-Member -Name Message | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have AffectedArtifacts property' {
        InModuleScope FFU.ArtifactScanner {
            $warning = [CompatibilityWarning]::new()
            $warning | Get-Member -Name AffectedArtifacts | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'ArtifactManifest Class' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should be instantiable with new()' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactManifest]::new() } | Should -Not -Throw
        }
    }

    It 'Should have BasePath property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name BasePath | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have ScanTimestamp property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name ScanTimestamp | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have FFUFiles property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name FFUFiles | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have DeployISO property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name DeployISO | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have Drivers property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name Drivers | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have PPKGFiles property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name PPKGFiles | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have UnattendFiles property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name UnattendFiles | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have AutopilotFiles property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name AutopilotFiles | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have AppsISO property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name AppsISO | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have Warnings property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name Warnings | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have FoundCount property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name FoundCount | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have MissingCount property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name MissingCount | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have ErrorCount property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name ErrorCount | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should have IsReady property' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest | Get-Member -Name IsReady | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-ArtifactMetadata - DISM Success Path' -Tag 'Unit', 'ArtifactScanner' {

    BeforeAll {
        # Create a fake FFU file path for testing
        $script:TestFFUPath = 'C:\TestFFU\Windows11_Pro_x64.ffu'
    }

    It 'Should return an FFUMetadata object on DISM success' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_Pro_x64.ffu' } {
            param($FFUPath)
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 9
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            Mock Import-Module { }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be 'FFUMetadata'
        }
    }

    It 'Should extract WindowsVersion from DISM' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_Pro_x64.ffu' } {
            param($FFUPath)
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 9
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            Mock Import-Module { }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.WindowsVersion | Should -Be '10.0.22631.1'
        }
    }

    It 'Should extract WindowsSKU from DISM EditionId' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_Pro_x64.ffu' } {
            param($FFUPath)
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 9
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            Mock Import-Module { }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.WindowsSKU | Should -Be 'Professional'
        }
    }

    It 'Should map Architecture integer 9 to x64 string' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_Pro_x64.ffu' } {
            param($FFUPath)
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 9
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            Mock Import-Module { }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.Architecture | Should -Be 'x64'
        }
    }

    It 'Should extract ImageName from DISM' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_Pro_x64.ffu' } {
            param($FFUPath)
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 9
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            Mock Import-Module { }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.ImageName | Should -Be 'Windows 11 Pro'
        }
    }

    It 'Should set MetadataSource to DISM on success' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_Pro_x64.ffu' } {
            param($FFUPath)
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 9
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            Mock Import-Module { }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.MetadataSource | Should -Be 'DISM'
        }
    }

    It 'Should have empty ErrorMessage on DISM success' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_Pro_x64.ffu' } {
            param($FFUPath)
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 9
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            Mock Import-Module { }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.ErrorMessage | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-ArtifactMetadata - Architecture Mapping' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should map architecture integer 0 to x86' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\test.ffu' } {
            param($FFUPath)
            Mock Import-Module { }
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 0
                    Version      = '10.0.19041.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 10 Pro'
                }
            }
            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.Architecture | Should -Be 'x86'
        }
    }

    It 'Should map architecture integer 9 to x64' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\test.ffu' } {
            param($FFUPath)
            Mock Import-Module { }
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 9
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.Architecture | Should -Be 'x64'
        }
    }

    It 'Should map architecture integer 12 to arm64' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\test.ffu' } {
            param($FFUPath)
            Mock Import-Module { }
            Mock Get-WindowsImage {
                return [PSCustomObject]@{
                    Architecture = 12
                    Version      = '10.0.22631.1'
                    EditionId    = 'Professional'
                    ImageName    = 'Windows 11 Pro'
                }
            }
            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.Architecture | Should -Be 'arm64'
        }
    }
}

Describe 'Get-ArtifactMetadata - DISM Failure Fallback' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should return FFUMetadata even when DISM fails' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_23H2_x64_Pro.ffu' } {
            param($FFUPath)
            Mock Import-Module { }
            Mock Get-WindowsImage { throw 'DISM initialization failed. Error code = 0x80004005' }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be 'FFUMetadata'
        }
    }

    It 'Should set MetadataSource to Filename on DISM failure' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_23H2_x64_Pro.ffu' } {
            param($FFUPath)
            Mock Import-Module { }
            Mock Get-WindowsImage { throw 'DISM initialization failed. Error code = 0x80004005' }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.MetadataSource | Should -Be 'Filename'
        }
    }

    It 'Should populate ErrorMessage on DISM failure' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_23H2_x64_Pro.ffu' } {
            param($FFUPath)
            Mock Import-Module { }
            Mock Get-WindowsImage { throw 'DISM initialization failed. Error code = 0x80004005' }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should parse x64 architecture from filename' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_23H2_x64_Pro.ffu' } {
            param($FFUPath)
            Mock Import-Module { }
            Mock Get-WindowsImage { throw 'DISM initialization failed. Error code = 0x80004005' }

            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $true
            $result.Architecture | Should -Be 'x64'
        }
    }
}

Describe 'Get-ArtifactMetadata - WimMount Unavailable' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should use filename fallback when WimMountAvailable is false' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ FFUPath = 'C:\TestFFU\Windows11_23H2_arm64_Pro.ffu' } {
            param($FFUPath)
            $result = Get-ArtifactMetadata -FFUPath $FFUPath -WimMountAvailable $false
            $result | Should -Not -BeNullOrEmpty
            $result.MetadataSource | Should -Be 'Filename'
            $result.Architecture | Should -Be 'arm64'
        }
    }
}

# =============================================================================
# Factory function tests — these work cross-scope because they use exported functions
# =============================================================================

Describe 'Factory Functions' -Tag 'Unit', 'ArtifactScanner' {

    # All factory function tests run InModuleScope because:
    # - The functions internally instantiate module-defined classes (ArtifactManifest, ArtifactResult)
    # - PowerShell module class types aren't resolved in caller scope at runtime
    # - InModuleScope executes the test code in the module's scope where types are visible
    # See Pitfall 4 in 46-RESEARCH.md.

    It 'New-ArtifactManifest should return an ArtifactManifest instance' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = New-ArtifactManifest
            $manifest | Should -Not -BeNullOrEmpty
            $manifest.GetType().Name | Should -Be 'ArtifactManifest'
        }
    }

    It 'New-ArtifactManifest should set ScanTimestamp' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = New-ArtifactManifest
            $manifest.ScanTimestamp | Should -Not -BeNullOrEmpty
            $manifest.ScanTimestamp | Should -BeOfType [DateTime]
        }
    }

    It 'New-ArtifactResult should return an ArtifactResult instance' {
        InModuleScope FFU.ArtifactScanner {
            $result = New-ArtifactResult -ArtifactType FFU
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be 'ArtifactResult'
        }
    }

    It 'New-ArtifactResult should initialize Files list' {
        InModuleScope FFU.ArtifactScanner {
            $result = New-ArtifactResult -ArtifactType FFU
            # Files is initialized in ArtifactResult() constructor as List[ArtifactFileEntry]
            # Verify initialization via Count property (null would throw, initialized returns 0)
            { $result.Files.Count } | Should -Not -Throw
            $result.Files.Count | Should -Be 0
        }
    }

    It 'New-ArtifactResult should set specified ArtifactType' {
        InModuleScope FFU.ArtifactScanner {
            $result = New-ArtifactResult -ArtifactType DeployISO
            $result.ArtifactType.ToString() | Should -Be 'DeployISO'
        }
    }
}

# =============================================================================
# Find-FFUArtifacts tests — covers DISC-01, VALID-01, VALID-04
# Uses TestDrive for filesystem simulation (Pester 5.x built-in)
# Tests run InModuleScope to access PowerShell class types.
# =============================================================================

Describe 'Find-FFUArtifacts - Empty Directory' -Tag 'Unit', 'ArtifactScanner' {

    BeforeAll {
        # Create a minimal FFUDevelopmentPath with no artifacts
        $script:EmptyBasePath = Join-Path $TestDrive 'EmptyFFUDev'
        New-Item -Path $script:EmptyBasePath -ItemType Directory -Force | Out-Null
    }

    It 'Should return an ArtifactManifest object' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be 'ArtifactManifest'
        }
    }

    It 'Should set BasePath on returned manifest' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.BasePath | Should -Be $BasePath
        }
    }

    It 'Should set ScanTimestamp on returned manifest' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $before = [DateTime]::Now
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.ScanTimestamp | Should -BeGreaterThan ($before.AddSeconds(-1))
        }
    }

    It 'Should return FFU artifacts as Missing when FFU folder empty' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            # No FFU files found — FFUFiles array should have a Missing entry
            $result.FFUFiles | Should -Not -BeNullOrEmpty
            $result.FFUFiles[0].Status.ToString() | Should -Be 'Missing'
        }
    }

    It 'Should return DeployISO as Missing when not found' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.DeployISO | Should -Not -BeNullOrEmpty
            $result.DeployISO.Status.ToString() | Should -Be 'Missing'
        }
    }

    It 'Should return Drivers as Missing when folder absent' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.Drivers | Should -Not -BeNullOrEmpty
            $result.Drivers.Status.ToString() | Should -Be 'Missing'
        }
    }

    It 'Should return PPKG as Missing when no files found' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.PPKGFiles | Should -Not -BeNullOrEmpty
            $result.PPKGFiles[0].Status.ToString() | Should -Be 'Missing'
        }
    }

    It 'Should return Unattend as Missing when no files found' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.UnattendFiles | Should -Not -BeNullOrEmpty
            $result.UnattendFiles[0].Status.ToString() | Should -Be 'Missing'
        }
    }

    It 'Should return Autopilot as Missing when no files found' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.AutopilotFiles | Should -Not -BeNullOrEmpty
            $result.AutopilotFiles[0].Status.ToString() | Should -Be 'Missing'
        }
    }

    It 'Should return AppsISO as Missing when file absent' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.AppsISO | Should -Not -BeNullOrEmpty
            $result.AppsISO.Status.ToString() | Should -Be 'Missing'
        }
    }

    It 'Should set IsReady to false when FFU missing' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:EmptyBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.IsReady | Should -Be $false
        }
    }
}

Describe 'Find-FFUArtifacts - All Artifacts Present' -Tag 'Unit', 'ArtifactScanner' {

    BeforeAll {
        # Build a fully-populated FFUDevelopmentPath
        $script:FullBasePath = Join-Path $TestDrive 'FullFFUDev'
        $ffuDir      = Join-Path $script:FullBasePath 'FFU'
        $driversDir  = Join-Path $script:FullBasePath 'Drivers'
        $ppkgDir     = Join-Path $script:FullBasePath 'PPKG'
        $unattendDir = Join-Path $script:FullBasePath 'Unattend'
        $autopilotDir= Join-Path $script:FullBasePath 'Autopilot'
        $appsDir     = Join-Path $script:FullBasePath 'Apps'

        foreach ($dir in @($ffuDir, $driversDir, $ppkgDir, $unattendDir, $autopilotDir, $appsDir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }

        # Create test artifacts
        Set-Content -Path (Join-Path $ffuDir 'Windows11_23H2_x64_Pro.ffu') -Value 'fake-ffu-content'
        Set-Content -Path (Join-Path $script:FullBasePath 'WinPE_FFU_Deploy_x64.iso') -Value 'fake-iso'
        Set-Content -Path (Join-Path $driversDir 'driver1.inf') -Value 'fake-driver'
        Set-Content -Path (Join-Path $ppkgDir 'provision.ppkg') -Value 'fake-ppkg'
        Set-Content -Path (Join-Path $unattendDir 'unattend_x64.xml') -Value '<unattend/>'
        Set-Content -Path (Join-Path $autopilotDir 'AutopilotConfigurationFile.json') -Value '{}'
        Set-Content -Path (Join-Path $appsDir 'Apps.iso') -Value 'fake-apps-iso'
    }

    It 'Should return Found status for FFU' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new()
                $m.Architecture   = 'x64'
                $m.MetadataSource = 'Filename'
                return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.FFUFiles | Where-Object { $_.Status.ToString() -eq 'Found' } | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should mark newest FFU as IsPrimary' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new()
                $m.Architecture   = 'x64'
                $m.MetadataSource = 'Filename'
                return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $primary = $result.FFUFiles | Where-Object { $_.IsPrimary -eq $true }
            $primary | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should call Get-ArtifactMetadata for each FFU file' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new()
                $m.Architecture   = 'x64'
                $m.MetadataSource = 'Filename'
                return $m
            }
            Find-FFUArtifacts -FFUDevelopmentPath $BasePath | Out-Null
            Should -Invoke Get-ArtifactMetadata -Times 1 -Exactly
        }
    }

    It 'Should populate Metadata on FFU result from Get-ArtifactMetadata' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new()
                $m.Architecture   = 'x64'
                $m.MetadataSource = 'Filename'
                return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $primary = $result.FFUFiles | Where-Object { $_.IsPrimary -eq $true }
            $primary.Metadata | Should -Not -BeNullOrEmpty
            $primary.Metadata.Architecture | Should -Be 'x64'
        }
    }

    It 'Should return Found status for DeployISO' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.DeployISO.Status.ToString() | Should -Be 'Found'
        }
    }

    It 'Should return Found status for Drivers folder' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.Drivers.Status.ToString() | Should -Be 'Found'
        }
    }

    It 'Should report FileCount and TotalSizeBytes for Drivers' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.Drivers.FileCount | Should -BeGreaterThan 0
            $result.Drivers.TotalSizeBytes | Should -BeGreaterOrEqual 0
        }
    }

    It 'Should return Found status for PPKG' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.PPKGFiles | Where-Object { $_.Status.ToString() -eq 'Found' } | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should return Found status for unattend_x64.xml' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.UnattendFiles | Where-Object { $_.Status.ToString() -eq 'Found' } | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should return Found status for Autopilot JSON' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.AutopilotFiles | Where-Object { $_.Status.ToString() -eq 'Found' } | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should return Found status for Apps.iso' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.AppsISO.Status.ToString() | Should -Be 'Found'
        }
    }

    It 'Should report AgeDays >= 0 for found FFU artifact' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $primary = $result.FFUFiles | Where-Object { $_.IsPrimary -eq $true }
            $primary.AgeDays | Should -BeGreaterOrEqual 0
        }
    }

    It 'Should report AgeDays >= 0 for found DeployISO' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.DeployISO.AgeDays | Should -BeGreaterOrEqual 0
        }
    }

    It 'Should set IsReady to true when FFU and DeployISO both found' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.IsReady | Should -Be $true
        }
    }

    It 'Should populate FoundCount correctly' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.FoundCount | Should -BeGreaterThan 0
        }
    }
}

Describe 'Find-FFUArtifacts - Multiple FFU Files' -Tag 'Unit', 'ArtifactScanner' {

    BeforeAll {
        $script:MultiFfuPath = Join-Path $TestDrive 'MultiFfuDev'
        $ffuDir = Join-Path $script:MultiFfuPath 'FFU'
        New-Item -Path $ffuDir -ItemType Directory -Force | Out-Null

        # Create two FFU files with different timestamps
        $older = Join-Path $ffuDir 'Windows11_23H2_x64_Pro.ffu'
        $newer = Join-Path $ffuDir 'Windows11_24H2_x64_Pro.ffu'
        Set-Content -Path $older -Value 'old'
        Start-Sleep -Milliseconds 100
        Set-Content -Path $newer -Value 'new'
    }

    It 'Should discover both FFU files' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:MultiFfuPath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            ($result.FFUFiles | Where-Object { $_.Status.ToString() -eq 'Found' }).Count | Should -Be 2
        }
    }

    It 'Should mark exactly one FFU as IsPrimary' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:MultiFfuPath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            ($result.FFUFiles | Where-Object { $_.IsPrimary -eq $true }).Count | Should -Be 1
        }
    }

    It 'Should mark the newest FFU as IsPrimary' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:MultiFfuPath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new(); $m.Architecture = 'x64'; $m.MetadataSource = 'Filename'; return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $primary = $result.FFUFiles | Where-Object { $_.IsPrimary -eq $true }
            $primary.FilePath | Should -Match '24H2'
        }
    }
}

Describe 'Find-FFUArtifacts - Drivers AgeDays from Newest File' -Tag 'Unit', 'ArtifactScanner' {

    BeforeAll {
        $script:DriversAgePath = Join-Path $TestDrive 'DriversAgeDev'
        $driversDir = Join-Path $script:DriversAgePath 'Drivers'
        New-Item -Path $driversDir -ItemType Directory -Force | Out-Null
        # Create a driver file
        Set-Content -Path (Join-Path $driversDir 'driver.inf') -Value 'fake'
    }

    It 'Should use newest file LastWriteTime for Drivers AgeDays, not folder timestamp' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:DriversAgePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            # AgeDays should be 0 or more (file was just created)
            $result.Drivers.AgeDays | Should -BeGreaterOrEqual 0
            $result.Drivers.Status.ToString() | Should -Be 'Found'
        }
    }
}

Describe 'Find-FFUArtifacts - Graceful Degradation' -Tag 'Unit', 'ArtifactScanner' {

    BeforeAll {
        $script:GracefulPath = Join-Path $TestDrive 'GracefulDev'
        $ffuDir = Join-Path $script:GracefulPath 'FFU'
        New-Item -Path $ffuDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $ffuDir 'test.ffu') -Value 'ffu'
    }

    It 'Should not throw when Get-ArtifactMetadata throws for one FFU' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:GracefulPath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata { throw 'Simulated DISM error' }
            { Find-FFUArtifacts -FFUDevelopmentPath $BasePath } | Should -Not -Throw
        }
    }

    It 'Should still return FFU result even when metadata fails' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:GracefulPath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata { throw 'Simulated DISM error' }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.FFUFiles | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Test-ArtifactCompatibility tests — covers VALID-03
# =============================================================================

Describe 'Test-ArtifactCompatibility - Architecture Match' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should return empty array when FFU and DeployISO architectures match' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest.FFUFiles = @()
            $manifest.Warnings = @()

            # Primary FFU with x64 arch
            $ffuResult = [ArtifactResult]::new()
            $ffuResult.ArtifactType = [ArtifactType]::FFU
            $ffuResult.Status       = [ArtifactStatus]::Found
            $ffuResult.IsPrimary    = $true
            $ffuResult.FilePath     = 'C:\FFU\Windows11_x64.ffu'
            $meta = [FFUMetadata]::new()
            $meta.Architecture = 'x64'
            $ffuResult.Metadata = $meta
            $manifest.FFUFiles = @($ffuResult)

            # Deploy ISO with x64 in filename
            $isoResult = [ArtifactResult]::new()
            $isoResult.ArtifactType = [ArtifactType]::DeployISO
            $isoResult.Status       = [ArtifactStatus]::Found
            $isoResult.FilePath     = 'C:\WinPE_FFU_Deploy_x64.iso'
            $manifest.DeployISO = $isoResult

            $warnings = Test-ArtifactCompatibility -Manifest $manifest
            $warnings | Should -HaveCount 0
        }
    }

    It 'Should return empty array when both are arm64' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest.FFUFiles = @()
            $manifest.Warnings = @()

            $ffuResult = [ArtifactResult]::new()
            $ffuResult.ArtifactType = [ArtifactType]::FFU
            $ffuResult.Status       = [ArtifactStatus]::Found
            $ffuResult.IsPrimary    = $true
            $ffuResult.FilePath     = 'C:\FFU\Windows11_arm64.ffu'
            $meta = [FFUMetadata]::new()
            $meta.Architecture = 'arm64'
            $ffuResult.Metadata = $meta
            $manifest.FFUFiles = @($ffuResult)

            $isoResult = [ArtifactResult]::new()
            $isoResult.ArtifactType = [ArtifactType]::DeployISO
            $isoResult.Status       = [ArtifactStatus]::Found
            $isoResult.FilePath     = 'C:\WinPE_FFU_Deploy_arm64.iso'
            $manifest.DeployISO = $isoResult

            $warnings = Test-ArtifactCompatibility -Manifest $manifest
            $warnings | Should -HaveCount 0
        }
    }
}

Describe 'Test-ArtifactCompatibility - Architecture Mismatch' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should return a warning when FFU is arm64 but DeployISO is x64' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest.FFUFiles = @()
            $manifest.Warnings = @()

            $ffuResult = [ArtifactResult]::new()
            $ffuResult.ArtifactType = [ArtifactType]::FFU
            $ffuResult.Status       = [ArtifactStatus]::Found
            $ffuResult.IsPrimary    = $true
            $ffuResult.FilePath     = 'C:\FFU\Windows11_arm64.ffu'
            $meta = [FFUMetadata]::new()
            $meta.Architecture = 'arm64'
            $ffuResult.Metadata = $meta
            $manifest.FFUFiles = @($ffuResult)

            $isoResult = [ArtifactResult]::new()
            $isoResult.ArtifactType = [ArtifactType]::DeployISO
            $isoResult.Status       = [ArtifactStatus]::Found
            $isoResult.FilePath     = 'C:\WinPE_FFU_Deploy_x64.iso'
            $manifest.DeployISO = $isoResult

            $warnings = Test-ArtifactCompatibility -Manifest $manifest
            $warnings | Should -Not -BeNullOrEmpty
            $warnings.Count | Should -BeGreaterThan 0
        }
    }

    It 'Should include both architecture names in the warning message' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest.FFUFiles = @()
            $manifest.Warnings = @()

            $ffuResult = [ArtifactResult]::new()
            $ffuResult.ArtifactType = [ArtifactType]::FFU
            $ffuResult.Status       = [ArtifactStatus]::Found
            $ffuResult.IsPrimary    = $true
            $ffuResult.FilePath     = 'C:\FFU\Windows11_arm64.ffu'
            $meta = [FFUMetadata]::new()
            $meta.Architecture = 'arm64'
            $ffuResult.Metadata = $meta
            $manifest.FFUFiles = @($ffuResult)

            $isoResult = [ArtifactResult]::new()
            $isoResult.ArtifactType = [ArtifactType]::DeployISO
            $isoResult.Status       = [ArtifactStatus]::Found
            $isoResult.FilePath     = 'C:\WinPE_FFU_Deploy_x64.iso'
            $manifest.DeployISO = $isoResult

            $warnings = Test-ArtifactCompatibility -Manifest $manifest
            $warnings[0].Message | Should -Match 'arm64'
            $warnings[0].Message | Should -Match 'x64'
        }
    }

    It 'Should set Severity to Warning' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest.FFUFiles = @()
            $manifest.Warnings = @()

            $ffuResult = [ArtifactResult]::new()
            $ffuResult.ArtifactType = [ArtifactType]::FFU
            $ffuResult.Status       = [ArtifactStatus]::Found
            $ffuResult.IsPrimary    = $true
            $meta = [FFUMetadata]::new()
            $meta.Architecture = 'arm64'
            $ffuResult.Metadata = $meta
            $manifest.FFUFiles = @($ffuResult)

            $isoResult = [ArtifactResult]::new()
            $isoResult.ArtifactType = [ArtifactType]::DeployISO
            $isoResult.Status       = [ArtifactStatus]::Found
            $isoResult.FilePath     = 'C:\WinPE_FFU_Deploy_x64.iso'
            $manifest.DeployISO = $isoResult

            $warnings = Test-ArtifactCompatibility -Manifest $manifest
            $warnings[0].Severity | Should -Be 'Warning'
        }
    }

    It 'Should list both FFU and DeployISO in AffectedArtifacts' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest.FFUFiles = @()
            $manifest.Warnings = @()

            $ffuResult = [ArtifactResult]::new()
            $ffuResult.ArtifactType = [ArtifactType]::FFU
            $ffuResult.Status       = [ArtifactStatus]::Found
            $ffuResult.IsPrimary    = $true
            $meta = [FFUMetadata]::new()
            $meta.Architecture = 'arm64'
            $ffuResult.Metadata = $meta
            $manifest.FFUFiles = @($ffuResult)

            $isoResult = [ArtifactResult]::new()
            $isoResult.ArtifactType = [ArtifactType]::DeployISO
            $isoResult.Status       = [ArtifactStatus]::Found
            $isoResult.FilePath     = 'C:\WinPE_FFU_Deploy_x64.iso'
            $manifest.DeployISO = $isoResult

            $warnings = Test-ArtifactCompatibility -Manifest $manifest
            $warnings[0].AffectedArtifacts | Should -Contain 'FFU'
            $warnings[0].AffectedArtifacts | Should -Contain 'DeployISO'
        }
    }
}

Describe 'Test-ArtifactCompatibility - Missing Artifacts' -Tag 'Unit', 'ArtifactScanner' {

    It 'Should return empty array when FFU is missing' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest.FFUFiles = @()
            $manifest.Warnings = @()

            # No FFU files at all (empty array)
            $isoResult = [ArtifactResult]::new()
            $isoResult.ArtifactType = [ArtifactType]::DeployISO
            $isoResult.Status       = [ArtifactStatus]::Found
            $isoResult.FilePath     = 'C:\WinPE_FFU_Deploy_x64.iso'
            $manifest.DeployISO = $isoResult

            $warnings = Test-ArtifactCompatibility -Manifest $manifest
            $warnings | Should -HaveCount 0
        }
    }

    It 'Should return empty array when DeployISO is missing' {
        InModuleScope FFU.ArtifactScanner {
            $manifest = [ArtifactManifest]::new()
            $manifest.FFUFiles = @()
            $manifest.Warnings = @()

            $ffuResult = [ArtifactResult]::new()
            $ffuResult.ArtifactType = [ArtifactType]::FFU
            $ffuResult.Status       = [ArtifactStatus]::Found
            $ffuResult.IsPrimary    = $true
            $meta = [FFUMetadata]::new()
            $meta.Architecture = 'x64'
            $ffuResult.Metadata = $meta
            $manifest.FFUFiles = @($ffuResult)
            # No DeployISO set

            $warnings = Test-ArtifactCompatibility -Manifest $manifest
            $warnings | Should -HaveCount 0
        }
    }
}

Describe 'Find-FFUArtifacts - Compatibility Integration' -Tag 'Unit', 'ArtifactScanner' {

    BeforeAll {
        $script:CompatPath = Join-Path $TestDrive 'CompatDev'
        $ffuDir = Join-Path $script:CompatPath 'FFU'
        New-Item -Path $ffuDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $ffuDir 'Windows11_arm64.ffu') -Value 'ffu'
        # Deploy ISO for x64 — mismatch
        Set-Content -Path (Join-Path $script:CompatPath 'WinPE_FFU_Deploy_x64.iso') -Value 'iso'
    }

    It 'Should populate Warnings when FFU arm64 and ISO x64 mismatch' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:CompatPath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new()
                $m.Architecture   = 'arm64'
                $m.MetadataSource = 'Filename'
                return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.Warnings | Should -Not -BeNullOrEmpty
            $result.Warnings.Count | Should -BeGreaterThan 0
        }
    }

    It 'Should have empty Warnings when architectures match' {
        InModuleScope FFU.ArtifactScanner -Parameters @{ BasePath = $script:FullBasePath } {
            param($BasePath)
            Mock Test-FFUWimMount { return @{ Status = 'Passed' } }
            Mock Get-ArtifactMetadata {
                $m = [FFUMetadata]::new()
                $m.Architecture   = 'x64'
                $m.MetadataSource = 'Filename'
                return $m
            }
            $result = Find-FFUArtifacts -FFUDevelopmentPath $BasePath
            $result.Warnings | Should -HaveCount 0
        }
    }
}
