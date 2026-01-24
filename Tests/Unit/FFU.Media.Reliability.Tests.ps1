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
