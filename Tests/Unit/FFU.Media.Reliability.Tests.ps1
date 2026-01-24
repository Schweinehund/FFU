#Requires -Module Pester
<#
.SYNOPSIS
    FFU.Media Reliability Tests - REL-MED-XX test coverage

.DESCRIPTION
    Pester 5.x tests for FFU.Media reliability improvements.
    - REL-MED-02: DISM/ADK Error Remediation (Get-ADKToolFailureRemediation)
    - REL-MED-04: Architecture Capability Validation (Test-ArchitectureCapability)

.NOTES
    Part of Phase 19: FFU.Media Reliability
    Run with: Invoke-Pester -Path Tests/Unit/FFU.Media.Reliability.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Setup module path for FFU.Media and dependencies
    $script:ModulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules'
    $env:PSModulePath = "$script:ModulePath;$env:PSModulePath"

    # Import the module under test
    Import-Module 'FFU.Media' -Force -ErrorAction Stop
}

AfterAll {
    # Cleanup
    Remove-Module 'FFU.Media' -Force -ErrorAction SilentlyContinue
}

Describe 'REL-MED-02: ADK/DISM Error Remediation' {

    Describe 'Get-ADKToolFailureRemediation' {

        Context 'Function Export and Parameters' {

            It 'Should be exported from FFU.Media module' {
                $cmd = Get-Command Get-ADKToolFailureRemediation -Module FFU.Media -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNullOrEmpty
                $cmd.Module.Name | Should -Be 'FFU.Media'
            }

            It 'Should have ErrorMessage parameter as mandatory' {
                $cmd = Get-Command Get-ADKToolFailureRemediation
                $param = $cmd.Parameters['ErrorMessage']
                $param | Should -Not -BeNullOrEmpty
                $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Contain $true
            }

            It 'Should have ToolName parameter with default value DISM' {
                $cmd = Get-Command Get-ADKToolFailureRemediation
                $param = $cmd.Parameters['ToolName']
                $param | Should -Not -BeNullOrEmpty
                # Test the default by calling without ToolName
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Test error'
                $result.ToolName | Should -Be 'DISM'
            }
        }

        Context 'Output Structure' {

            BeforeAll {
                $script:TestResult = Get-ADKToolFailureRemediation -ErrorMessage 'Error 0x800704DB: test'
            }

            It 'Should return PSCustomObject with ErrorCode property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'ErrorCode'
            }

            It 'Should return PSCustomObject with ErrorName property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'ErrorName'
            }

            It 'Should return PSCustomObject with Message property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'Message'
            }

            It 'Should return PSCustomObject with Remediation property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'Remediation'
            }

            It 'Should return PSCustomObject with ToolName property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'ToolName'
            }

            It 'Should return PSCustomObject with IsKnown property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'IsKnown'
            }
        }

        Context 'Error 0x800704DB (ServiceNotExist)' {

            It 'Should match WIMMount service error' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Error 0x800704DB: The specified service does not exist'
                $result.ErrorCode | Should -Be '0x800704DB'
                $result.ErrorName | Should -Be 'ServiceNotExist'
                $result.IsKnown | Should -Be $true
            }

            It 'Should include fltmc load in remediation' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'DISM failed with 0x800704DB'
                $result.Remediation | Should -Match 'fltmc load WimMount'
            }

            It 'Should include sc create wimmount in remediation' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x800704DB error'
                $result.Remediation | Should -Match 'sc create wimmount'
            }

            It 'Should mention ADK repair option' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x800704DB'
                $result.Remediation | Should -Match 'adksetup.exe /repair'
            }
        }

        Context 'Error 0x80070005 (AccessDenied)' {

            It 'Should match access denied error' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Error 0x80070005'
                $result.ErrorCode | Should -Be '0x80070005'
                $result.ErrorName | Should -Be 'AccessDenied'
                $result.IsKnown | Should -Be $true
            }

            It 'Should include Administrator remediation' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x80070005'
                $result.Remediation | Should -Match 'Administrator'
            }

            It 'Should mention antivirus in remediation' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x80070005'
                $result.Remediation | Should -Match 'antivirus'
            }

            It 'Should provide short message about access denied' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x80070005'
                $result.Message | Should -Match 'Access denied'
            }
        }

        Context 'Error 0x800F081F (SourceNotFound)' {

            It 'Should match source not found error' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'DISM returned 0x800F081F'
                $result.ErrorCode | Should -Be '0x800F081F'
                $result.ErrorName | Should -Be 'SourceNotFound'
                $result.IsKnown | Should -Be $true
            }

            It 'Should mention winpe.wim in remediation' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x800F081F'
                $result.Remediation | Should -Match 'winpe\.wim'
            }

            It 'Should suggest reinstalling WinPE add-on' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x800F081F'
                $result.Remediation | Should -Match 'WinPE add-on'
            }
        }

        Context 'Error 0xc1510114 (MountCorrupted)' {

            It 'Should match mount corrupted error' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Error 0xc1510114: Mount point corrupted'
                $result.ErrorCode | Should -Be '0xc1510114'
                $result.ErrorName | Should -Be 'MountCorrupted'
                $result.IsKnown | Should -Be $true
            }

            It 'Should include Cleanup-Mountpoints in remediation' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0xc1510114'
                $result.Remediation | Should -Match 'Cleanup-Mountpoints'
            }

            It 'Should mention TrustedInstaller service' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0xc1510114'
                $result.Remediation | Should -Match 'TrustedInstaller'
            }
        }

        Context 'Error 0x800700b7 (AlreadyMounted)' {

            It 'Should match already mounted error' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Error 0x800700b7'
                $result.ErrorCode | Should -Be '0x800700b7'
                $result.ErrorName | Should -Be 'AlreadyMounted'
                $result.IsKnown | Should -Be $true
            }

            It 'Should suggest Get-WindowsImage -Mounted' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x800700b7'
                $result.Remediation | Should -Match 'Get-WindowsImage -Mounted'
            }

            It 'Should provide Dismount-WindowsImage command' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x800700b7'
                $result.Remediation | Should -Match 'Dismount-WindowsImage'
            }
        }

        Context 'Error 0x80070070 (DiskFull)' {

            It 'Should match disk full error' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Failed with 0x80070070'
                $result.ErrorCode | Should -Be '0x80070070'
                $result.ErrorName | Should -Be 'DiskFull'
                $result.IsKnown | Should -Be $true
            }

            It 'Should mention minimum space requirement' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x80070070'
                $result.Remediation | Should -Match '15 GB'
            }

            It 'Should suggest Disk Cleanup' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x80070070'
                $result.Remediation | Should -Match 'Disk Cleanup'
            }

            It 'Should provide DISM scratch cleanup command' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage '0x80070070'
                $result.Remediation | Should -Match 'DISM\*'
            }
        }

        Context 'Unknown error codes' {

            It 'Should return IsKnown=false for unknown errors' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Error 0xDEADBEEF: Some unknown error'
                $result.IsKnown | Should -Be $false
                $result.ErrorCode | Should -Be 'Unknown'
            }

            It 'Should return UnclassifiedError as ErrorName for unknown errors' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Mystery failure XYZ'
                $result.ErrorName | Should -Be 'UnclassifiedError'
            }

            It 'Should include original error in remediation for unknown errors' {
                $errorMsg = 'Mystery failure XYZ'
                $result = Get-ADKToolFailureRemediation -ErrorMessage $errorMsg
                $result.Remediation | Should -Match 'Mystery failure XYZ'
            }

            It 'Should include generic troubleshooting steps' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Unknown error'
                $result.Remediation | Should -Match 'Cleanup-Mountpoints'
            }

            It 'Should suggest checking DISM logs for unknown errors' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Unknown error'
                $result.Remediation | Should -Match 'dism\.log'
            }

            It 'Should suggest UpdateADK for unknown errors' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Unknown error'
                $result.Remediation | Should -Match 'UpdateADK'
            }
        }

        Context 'ToolName parameter' {

            It 'Should default to DISM' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Some error'
                $result.ToolName | Should -Be 'DISM'
            }

            It 'Should accept custom ToolName' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Error' -ToolName 'oscdimg'
                $result.ToolName | Should -Be 'oscdimg'
            }

            It 'Should include custom ToolName in unknown error message' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Error' -ToolName 'copype'
                $result.Message | Should -Match 'copype'
            }

            It 'Should include custom ToolName in unknown error remediation' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'Unknown' -ToolName 'makewinpemedia'
                $result.Remediation | Should -Match 'makewinpemedia'
            }
        }

        Context 'Case sensitivity and partial matches' {

            It 'Should match case-insensitive error codes' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'error 0X800704DB occurred'
                $result.IsKnown | Should -Be $true
                $result.ErrorCode | Should -Be '0x800704DB'
            }

            It 'Should match error code anywhere in message' {
                $result = Get-ADKToolFailureRemediation -ErrorMessage 'The operation failed because of error 0x80070070 which is a disk space issue'
                $result.IsKnown | Should -Be $true
                $result.ErrorName | Should -Be 'DiskFull'
            }
        }
    }
}

# =============================================================================
# REL-MED-04: Architecture Capability Validation
# =============================================================================

Describe 'REL-MED-04: Architecture Capability Validation' {

    Describe 'Test-ArchitectureCapability' {

        BeforeAll {
            # Create temp ADK structure for testing
            $script:testADK = Join-Path $env:TEMP "TestADK_$(Get-Random)"
            $script:oscdimgPath = Join-Path $script:testADK 'Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg'
            $script:winPEPath = Join-Path $script:testADK 'Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us'

            New-Item -Path $script:oscdimgPath -ItemType Directory -Force | Out-Null
            New-Item -Path $script:winPEPath -ItemType Directory -Force | Out-Null

            # Create dummy files for x64/amd64
            '' | Set-Content (Join-Path $script:oscdimgPath 'oscdimg.exe')
            '' | Set-Content (Join-Path $script:winPEPath 'winpe.wim')
        }

        AfterAll {
            Remove-Item -Path $script:testADK -Recurse -Force -ErrorAction SilentlyContinue
        }

        Context 'Function Export and Parameters' {

            It 'Should be exported from FFU.Media module' {
                $cmd = Get-Command Test-ArchitectureCapability -Module FFU.Media -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNullOrEmpty
                $cmd.Module.Name | Should -Be 'FFU.Media'
            }

            It 'Should have TargetArchitecture parameter as mandatory' {
                $cmd = Get-Command Test-ArchitectureCapability
                $param = $cmd.Parameters['TargetArchitecture']
                $param | Should -Not -BeNullOrEmpty
                $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Contain $true
            }

            It 'Should have ADKPath parameter as mandatory' {
                $cmd = Get-Command Test-ArchitectureCapability
                $param = $cmd.Parameters['ADKPath']
                $param | Should -Not -BeNullOrEmpty
                $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Contain $true
            }

            It 'Should accept x64 and arm64 for TargetArchitecture' {
                $cmd = Get-Command Test-ArchitectureCapability
                $param = $cmd.Parameters['TargetArchitecture']
                $validateSet = $param.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] })
                $validateSet | Should -Not -BeNullOrEmpty
                $validateSet.ValidValues | Should -Contain 'x64'
                $validateSet.ValidValues | Should -Contain 'arm64'
            }
        }

        Context 'Output Structure' {

            BeforeAll {
                $script:TestResult = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
            }

            It 'Should return PSCustomObject with CanBuild property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'CanBuild'
            }

            It 'Should return PSCustomObject with TargetArchitecture property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'TargetArchitecture'
            }

            It 'Should return PSCustomObject with HostArchitecture property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'HostArchitecture'
            }

            It 'Should return PSCustomObject with MissingComponents property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'MissingComponents'
            }

            It 'Should return PSCustomObject with Message property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'Message'
            }

            It 'Should return PSCustomObject with Remediation property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'Remediation'
            }

            It 'Should return PSCustomObject with Details property' {
                $script:TestResult.PSObject.Properties.Name | Should -Contain 'Details'
            }
        }

        Context 'ADK folder naming' {

            It 'Should use amd64 folder for x64 architecture' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.Details.ADKArchFolder | Should -Be 'amd64'
            }

            It 'Should use arm64 folder for arm64 architecture' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'arm64' -ADKPath $script:testADK
                $result.Details.ADKArchFolder | Should -Be 'arm64'
            }
        }

        Context 'When ADK has required components' {

            It 'Should return CanBuild=true for x64' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.CanBuild | Should -Be $true
            }

            It 'Should have empty MissingComponents' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.MissingComponents | Should -HaveCount 0
            }

            It 'Should have null Remediation' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.Remediation | Should -BeNullOrEmpty
            }

            It 'Should include OscdimgExists=true in Details' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.Details.OscdimgExists | Should -Be $true
            }

            It 'Should include WinPEExists=true in Details' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.Details.WinPEExists | Should -Be $true
            }
        }

        Context 'When oscdimg.exe is missing' {

            BeforeAll {
                $script:oscdimgFile = Join-Path $script:oscdimgPath 'oscdimg.exe'
                $script:oscdimgBackup = Join-Path $script:oscdimgPath 'oscdimg.exe.bak'
                if (Test-Path $script:oscdimgFile) {
                    Rename-Item -Path $script:oscdimgFile -NewName 'oscdimg.exe.bak' -ErrorAction SilentlyContinue
                }
            }

            AfterAll {
                if (Test-Path $script:oscdimgBackup) {
                    Rename-Item -Path $script:oscdimgBackup -NewName 'oscdimg.exe' -ErrorAction SilentlyContinue
                } else {
                    '' | Set-Content (Join-Path $script:oscdimgPath 'oscdimg.exe')
                }
            }

            It 'Should return CanBuild=false' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.CanBuild | Should -Be $false
            }

            It 'Should list oscdimg.exe in MissingComponents' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.MissingComponents | Should -Contain 'oscdimg.exe (amd64)'
            }

            It 'Should include OscdimgExists=false in Details' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.Details.OscdimgExists | Should -Be $false
            }
        }

        Context 'When winpe.wim is missing' {

            BeforeAll {
                $script:winpeFile = Join-Path $script:winPEPath 'winpe.wim'
                $script:winpeBackup = Join-Path $script:winPEPath 'winpe.wim.bak'
                if (Test-Path $script:winpeFile) {
                    Rename-Item -Path $script:winpeFile -NewName 'winpe.wim.bak' -ErrorAction SilentlyContinue
                }
            }

            AfterAll {
                if (Test-Path $script:winpeBackup) {
                    Rename-Item -Path $script:winpeBackup -NewName 'winpe.wim' -ErrorAction SilentlyContinue
                } else {
                    '' | Set-Content (Join-Path $script:winPEPath 'winpe.wim')
                }
            }

            It 'Should return CanBuild=false' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.CanBuild | Should -Be $false
            }

            It 'Should list winpe.wim in MissingComponents' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.MissingComponents | Should -Contain 'winpe.wim (amd64)'
            }

            It 'Should include WinPEExists=false in Details' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.Details.WinPEExists | Should -Be $false
            }
        }

        Context 'When architecture not installed' {

            It 'Should return CanBuild=false for arm64 (not in test ADK)' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'arm64' -ADKPath $script:testADK
                $result.CanBuild | Should -Be $false
            }

            It 'Should include reinstall guidance in Remediation' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'arm64' -ADKPath $script:testADK
                $result.Remediation | Should -Match 'adksetup.exe'
            }

            It 'Should mention WinPE add-on in Remediation' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'arm64' -ADKPath $script:testADK
                $result.Remediation | Should -Match 'WinPE add-on'
            }

            It 'Should list both oscdimg.exe and winpe.wim as missing' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'arm64' -ADKPath $script:testADK
                $result.MissingComponents | Should -HaveCount 2
                $result.MissingComponents | Should -Contain 'oscdimg.exe (arm64)'
                $result.MissingComponents | Should -Contain 'winpe.wim (arm64)'
            }
        }

        Context 'Host architecture detection' {

            It 'Should detect host architecture' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.HostArchitecture | Should -BeIn @('x64', 'arm64', 'x86', 'unknown')
            }

            It 'Should include IsCrossArch in Details when CanBuild is true' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                # Details is a hashtable, so check its Keys
                $result.Details.Keys | Should -Contain 'IsCrossArch'
            }
        }

        Context 'Error message clarity' {

            It 'Should have descriptive Message when CanBuild is true' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'x64' -ADKPath $script:testADK
                $result.Message | Should -Match 'ADK supports x64'
            }

            It 'Should have descriptive Message when CanBuild is false' {
                $result = Test-ArchitectureCapability -TargetArchitecture 'arm64' -ADKPath $script:testADK
                $result.Message | Should -Match 'Missing ADK components'
            }
        }
    }
}
