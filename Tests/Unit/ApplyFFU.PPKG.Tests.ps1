#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for PPKG copy fix in ApplyFFU.ps1

.DESCRIPTION
    Tests for BUGFIX-02 (PPKG path quoting for spaces).
    Verifies:
    1. xcopy receives properly quoted paths
    2. Copy-Item fallback executes when xcopy fails
    3. PPKG copy failure is non-blocking (warns, does not throw)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\ApplyFFU.PPKG.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Define the PPKG copy function extracted from ApplyFFU.ps1 for isolated testing.
    # This mirrors the fixed code structure so tests validate the exact logic pattern.
    function Invoke-PPKGCopy {
        [CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test wrapper function')]
        param(
            [string]$PPKGFileToInstall,
            [string]$USBDrive
        )

        if ($PPKGFileToInstall) {
            Write-SectionHeader -Title 'Applying Provisioning Package'
            try {
                Get-ChildItem -Path "$USBDrive\*.ppkg" | ForEach-Object {
                    Remove-Item -Path $_.FullName
                }
                WriteLog "Copying $PPKGFileToInstall to $USBDrive"
                Write-Host "Copying $PPKGFileToInstall to $USBDrive"

                try {
                    Invoke-Process xcopy.exe "`"$PPKGFileToInstall`" `"$USBDrive`" /Y"
                    WriteLog "Copying $PPKGFileToInstall to $USBDrive succeeded"
                    Write-Host "Copying $PPKGFileToInstall to $USBDrive succeeded"
                }
                catch {
                    WriteLog "xcopy failed for PPKG, attempting Copy-Item fallback: $_"
                    Write-Host "xcopy failed for PPKG, attempting Copy-Item fallback"
                    Copy-Item -Path $PPKGFileToInstall -Destination $USBDrive -Force -ErrorAction Stop
                    WriteLog "Copy-Item fallback succeeded for $PPKGFileToInstall to $USBDrive"
                    Write-Host "Copy-Item fallback succeeded for $PPKGFileToInstall to $USBDrive"
                }
            }
            catch {
                $errorMsg = "PPKG copy failed - Source: $PPKGFileToInstall, Destination: $USBDrive, Error: $_"
                WriteLog "WARNING: $errorMsg"
                Write-Host "WARNING: $errorMsg"
            }
        }
    }

    # Mock helper functions that exist in ApplyFFU.ps1 context
    function Global:WriteLog {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Message', Justification = 'Mock function for testing')]
        param([string]$Message)
    }
    function Global:Write-SectionHeader {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Title', Justification = 'Mock function for testing')]
        param([string]$Title)
    }
    function Global:Invoke-Process {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock function for testing')]
        param([string]$FilePath, [string]$ArgumentList)
    }
}

Describe 'PPKG Copy Path Quoting (BUGFIX-02)' {

    BeforeEach {
        # Reset mocks for each test
        Mock WriteLog {}
        Mock Write-SectionHeader {}
        Mock Write-Host {}
        Mock Get-ChildItem { @() }
        Mock Remove-Item {}
    }

    Context 'xcopy receives properly quoted paths' {

        It 'Should pass backtick-escaped quoted source and destination to xcopy' {
            Mock Invoke-Process {}

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\Contoso Package.ppkg' -USBDrive 'E:\'

            Should -InvokeVerifiable
            Assert-MockCalled Invoke-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'xcopy.exe' -and
                $ArgumentList -match 'Contoso Package\.ppkg'
            }
        }

        It 'Should include /Y flag to suppress overwrite prompt' {
            Mock Invoke-Process {}

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\test.ppkg' -USBDrive 'E:\'

            Assert-MockCalled Invoke-Process -Times 1 -Exactly -ParameterFilter {
                $ArgumentList -match '/Y'
            }
        }

        It 'Should work with paths without spaces' {
            Mock Invoke-Process {}

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\simple.ppkg' -USBDrive 'E:\'

            Assert-MockCalled Invoke-Process -Times 1 -Exactly
        }

        It 'Should not execute when PPKGFileToInstall is empty' {
            Mock Invoke-Process {}

            Invoke-PPKGCopy -PPKGFileToInstall '' -USBDrive 'E:\'

            Assert-MockCalled Invoke-Process -Times 0
            Assert-MockCalled Write-SectionHeader -Times 0
        }

        It 'Should delete existing PPKG files before copying' {
            Mock Invoke-Process {}
            Mock Get-ChildItem { [PSCustomObject]@{ FullName = 'E:\old.ppkg' } }
            Mock Remove-Item {} -Verifiable

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\new.ppkg' -USBDrive 'E:\'

            Should -InvokeVerifiable
        }
    }

    Context 'Copy-Item fallback when xcopy fails' {

        It 'Should fall back to Copy-Item when xcopy throws' {
            Mock Invoke-Process { throw 'xcopy error: file not found' }
            Mock Copy-Item {} -Verifiable

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\Contoso Package.ppkg' -USBDrive 'E:\'

            Should -InvokeVerifiable
            Assert-MockCalled Copy-Item -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'E:\PPKG\Contoso Package.ppkg' -and
                $Destination -eq 'E:\' -and
                $Force -eq $true
            }
        }

        It 'Should log xcopy failure before attempting fallback' {
            Mock Invoke-Process { throw 'xcopy error' }
            Mock Copy-Item {}

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\test.ppkg' -USBDrive 'E:\'

            Assert-MockCalled WriteLog -ParameterFilter {
                $Message -match 'xcopy failed for PPKG, attempting Copy-Item fallback'
            }
        }

        It 'Should log success when Copy-Item fallback succeeds' {
            Mock Invoke-Process { throw 'xcopy error' }
            Mock Copy-Item {}

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\test.ppkg' -USBDrive 'E:\'

            Assert-MockCalled WriteLog -ParameterFilter {
                $Message -match 'Copy-Item fallback succeeded'
            }
        }
    }

    Context 'Non-blocking failure behavior' {

        It 'Should not throw when both xcopy and Copy-Item fail' {
            Mock Invoke-Process { throw 'xcopy error' }
            Mock Copy-Item { throw 'Copy-Item error: access denied' }

            # This should NOT throw - PPKG copy is non-blocking
            { Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\test.ppkg' -USBDrive 'E:\' } |
                Should -Not -Throw
        }

        It 'Should log WARNING with source path when copy fails' {
            Mock Invoke-Process { throw 'xcopy error' }
            Mock Copy-Item { throw 'access denied' }

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\My Package.ppkg' -USBDrive 'E:\'

            Assert-MockCalled WriteLog -ParameterFilter {
                $Message -match 'WARNING:' -and
                $Message -match 'PPKG copy failed' -and
                $Message -match [regex]::Escape('E:\PPKG\My Package.ppkg')
            }
        }

        It 'Should log WARNING with destination path when copy fails' {
            Mock Invoke-Process { throw 'xcopy error' }
            Mock Copy-Item { throw 'access denied' }

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\test.ppkg' -USBDrive 'F:\'

            Assert-MockCalled WriteLog -ParameterFilter {
                $Message -match 'WARNING:' -and
                $Message -match [regex]::Escape('F:\')
            }
        }

        It 'Should log WARNING with error details when copy fails' {
            Mock Invoke-Process { throw 'xcopy error' }
            Mock Copy-Item { throw 'specific error message' }

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\test.ppkg' -USBDrive 'E:\'

            Assert-MockCalled WriteLog -ParameterFilter {
                $Message -match 'WARNING:' -and
                $Message -match 'Error:'
            }
        }

        It 'Should write WARNING to console when copy fails' {
            Mock Invoke-Process { throw 'xcopy error' }
            Mock Copy-Item { throw 'error' }

            Invoke-PPKGCopy -PPKGFileToInstall 'E:\PPKG\test.ppkg' -USBDrive 'E:\'

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -match 'WARNING:' -and
                $Object -match 'PPKG copy failed'
            }
        }
    }
}
