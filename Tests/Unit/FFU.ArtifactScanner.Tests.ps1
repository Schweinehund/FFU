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
