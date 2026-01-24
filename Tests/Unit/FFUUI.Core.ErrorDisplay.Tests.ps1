#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for FFUUI.Core.ErrorDisplay module.

.DESCRIPTION
    Tests for Show-FFUError, Show-FFUValidationErrors, and Format-FFUErrorMessage functions
    that provide structured error display in the FFU Builder UI.
#>

BeforeAll {
    # Load WPF assemblies for types
    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue

    # Import the module under test
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../FFUDevelopment/FFUUI.Core/FFUUI.Core.ErrorDisplay.psm1'
    Import-Module $script:modulePath -Force
}

Describe 'FFUUI.Core.ErrorDisplay Module' {

    Context 'Module Import' {
        It 'Module imports successfully' {
            { Import-Module $script:modulePath -Force } | Should -Not -Throw
        }

        It 'Exports Show-FFUError function' {
            Get-Command -Module 'FFUUI.Core.ErrorDisplay' -Name 'Show-FFUError' |
                Should -Not -BeNullOrEmpty
        }

        It 'Exports Show-FFUValidationErrors function' {
            Get-Command -Module 'FFUUI.Core.ErrorDisplay' -Name 'Show-FFUValidationErrors' |
                Should -Not -BeNullOrEmpty
        }

        It 'Exports Format-FFUErrorMessage function' {
            Get-Command -Module 'FFUUI.Core.ErrorDisplay' -Name 'Format-FFUErrorMessage' |
                Should -Not -BeNullOrEmpty
        }

        It 'Exports Show-MessageBox function' {
            Get-Command -Module 'FFUUI.Core.ErrorDisplay' -Name 'Show-MessageBox' |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'Show-FFUError - Severity Validation' {
        BeforeAll {
            Mock -ModuleName 'FFUUI.Core.ErrorDisplay' Show-MessageBox {
                return [System.Windows.MessageBoxResult]::OK
            }
        }

        It 'Accepts Critical severity' {
            { Show-FFUError -Severity 'Critical' -Title 'Test' -Description 'Test description' } |
                Should -Not -Throw
        }

        It 'Accepts Error severity' {
            { Show-FFUError -Severity 'Error' -Title 'Test' -Description 'Test description' } |
                Should -Not -Throw
        }

        It 'Accepts Warning severity' {
            { Show-FFUError -Severity 'Warning' -Title 'Test' -Description 'Test description' } |
                Should -Not -Throw
        }

        It 'Accepts Info severity' {
            { Show-FFUError -Severity 'Info' -Title 'Test' -Description 'Test description' } |
                Should -Not -Throw
        }

        It 'Rejects invalid severity' {
            { Show-FFUError -Severity 'Invalid' -Title 'Test' -Description 'Test description' } |
                Should -Throw
        }
    }

    Context 'Show-FFUError - Message Content via InModuleScope' {
        It 'Includes Title in message' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Error' -Title 'My Error Title' -Description 'Description'
                $script:capturedMessage | Should -Match 'My Error Title'
            }
        }

        It 'Includes Description in message' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Error' -Title 'Title' -Description 'This is the error description'
                $script:capturedMessage | Should -Match 'This is the error description'
            }
        }

        It 'Includes Remediation steps when provided' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc' -Remediation @('Step one')
                $script:capturedMessage | Should -Match 'Step one'
                $script:capturedMessage | Should -Match 'WHAT TO DO'
            }
        }

        It 'Formats multiple remediation steps as numbered list' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc' `
                    -Remediation @('First step', 'Second step', 'Third step')
                $script:capturedMessage | Should -Match '1\.\s*First step'
                $script:capturedMessage | Should -Match '2\.\s*Second step'
                $script:capturedMessage | Should -Match '3\.\s*Third step'
            }
        }

        It 'Includes log path when LogPath provided and file exists' {
            $tempLog = [System.IO.Path]::GetTempFileName()
            try {
                InModuleScope 'FFUUI.Core.ErrorDisplay' -Parameters @{ tempLog = $tempLog } {
                    $capturedMessage = $null
                    Mock Show-MessageBox {
                        param($Message, $Title, $Button, $Icon)
                        $script:capturedMessage = $Message
                        return [System.Windows.MessageBoxResult]::OK
                    }
                    Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc' -LogPath $tempLog
                    $script:capturedMessage | Should -Match 'LOG FILE'
                }
            }
            finally {
                Remove-Item -Path $tempLog -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Omits log path when file does not exist' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc' -LogPath 'C:\NonExistent\Path\file.log'
                $script:capturedMessage | Should -Not -Match 'LOG FILE'
            }
        }

        It 'Handles empty remediation array' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                { Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc' -Remediation @() } |
                    Should -Not -Throw
                $script:capturedMessage | Should -Not -Match 'WHAT TO DO'
            }
        }

        It 'Includes ErrorRecord details when provided' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                try { throw 'Test exception message' } catch { $errorRecord = $_ }
                Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc' -ErrorRecord $errorRecord
                $script:capturedMessage | Should -Match 'TECHNICAL DETAILS'
                $script:capturedMessage | Should -Match 'Test exception message'
            }
        }

        It 'Handles null ErrorRecord gracefully' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                { Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc' -ErrorRecord $null } |
                    Should -Not -Throw
                $script:capturedMessage | Should -Not -Match 'TECHNICAL DETAILS'
            }
        }

        It 'Includes additional Details when provided' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc' `
                    -Details @{ 'KeyOne' = 'ValueOne' }
                $script:capturedMessage | Should -Match 'DETAILS'
                $script:capturedMessage | Should -Match 'ValueOne'
            }
        }
    }

    Context 'Show-FFUError - MessageBox Icon' {
        It 'Uses Error icon for Critical severity' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedIcon = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedIcon = $Icon
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Critical' -Title 'Title' -Description 'Desc'
                $script:capturedIcon | Should -Be ([System.Windows.MessageBoxImage]::Error)
            }
        }

        It 'Uses Error icon for Error severity' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedIcon = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedIcon = $Icon
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc'
                $script:capturedIcon | Should -Be ([System.Windows.MessageBoxImage]::Error)
            }
        }

        It 'Uses Warning icon for Warning severity' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedIcon = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedIcon = $Icon
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Warning' -Title 'Title' -Description 'Desc'
                $script:capturedIcon | Should -Be ([System.Windows.MessageBoxImage]::Warning)
            }
        }

        It 'Uses Information icon for Info severity' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedIcon = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedIcon = $Icon
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Info' -Title 'Title' -Description 'Desc'
                $script:capturedIcon | Should -Be ([System.Windows.MessageBoxImage]::Information)
            }
        }
    }

    Context 'Show-FFUValidationErrors - Error Display' {
        It 'Shows errors with (X) prefix' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUValidationErrors -Errors @('Error message one', 'Error message two')
                $script:capturedMessage | Should -Match '\(X\)\s*Error message one'
                $script:capturedMessage | Should -Match '\(X\)\s*Error message two'
            }
        }

        It 'Shows warnings with (!) prefix' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUValidationErrors -Errors @() -Warnings @('Warning one', 'Warning two')
                $script:capturedMessage | Should -Match '\(!\)\s*Warning one'
                $script:capturedMessage | Should -Match '\(!\)\s*Warning two'
            }
        }

        It 'Includes config path when provided' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUValidationErrors -Errors @('Error') -ConfigPath 'C:\config.json'
                $script:capturedMessage | Should -Match 'Config file:.*C:\\config\.json'
            }
        }

        It 'Handles empty errors array with warnings only' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                { Show-FFUValidationErrors -Errors @() -Warnings @('Warning message') } |
                    Should -Not -Throw
                $script:capturedMessage | Should -Match '\(!\)\s*Warning message'
            }
        }

        It 'Uses Error icon when errors present' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedIcon = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedIcon = $Icon
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUValidationErrors -Errors @('Error message')
                $script:capturedIcon | Should -Be ([System.Windows.MessageBoxImage]::Error)
            }
        }

        It 'Uses Warning icon when only warnings present' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedIcon = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedIcon = $Icon
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUValidationErrors -Errors @() -Warnings @('Warning message')
                $script:capturedIcon | Should -Be ([System.Windows.MessageBoxImage]::Warning)
            }
        }

        It 'Shows "errors were found" header when errors present' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUValidationErrors -Errors @('Error')
                $script:capturedMessage | Should -Match 'errors were found'
            }
        }

        It 'Shows "warnings were found" header when only warnings' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUValidationErrors -Errors @() -Warnings @('Warning')
                $script:capturedMessage | Should -Match 'warnings were found'
            }
        }

        It 'Uses custom title when provided' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedTitle = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedTitle = $Title
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUValidationErrors -Errors @('Error') -Title 'Custom Validation Title'
                $script:capturedTitle | Should -Be 'Custom Validation Title'
            }
        }
    }

    Context 'Format-FFUErrorMessage - Message Formatting' {
        It 'Formats basic message correctly' {
            $result = Format-FFUErrorMessage -Description 'Test description'
            $result | Should -Match 'Test description'
        }

        It 'Includes all sections in correct order' {
            $result = Format-FFUErrorMessage -Description 'Desc' `
                -Remediation @('Fix step') `
                -Details @{ 'Key' = 'Value' }

            # Description comes first, then Details, then Remediation
            $descIndex = $result.IndexOf('Desc')
            $detailsIndex = $result.IndexOf('DETAILS')
            $remediationIndex = $result.IndexOf('WHAT TO DO')

            $descIndex | Should -BeLessThan $detailsIndex
            $detailsIndex | Should -BeLessThan $remediationIndex
        }

        It 'Handles missing optional parameters' {
            { Format-FFUErrorMessage -Description 'Only description' } |
                Should -Not -Throw
            $result = Format-FFUErrorMessage -Description 'Only description'
            $result | Should -Match 'Only description'
            $result | Should -Not -Match 'WHAT TO DO'
            $result | Should -Not -Match 'DETAILS'
        }

        It 'Handles special characters in messages' {
            $specialDesc = 'Path: C:\Users\Test & "quotes" <angle> brackets'
            { Format-FFUErrorMessage -Description $specialDesc } | Should -Not -Throw
            $result = Format-FFUErrorMessage -Description $specialDesc
            $result | Should -Match 'C:\\Users\\Test'
            $result | Should -Match '"quotes"'
        }

        It 'Returns empty string trimmed when no content' {
            $result = Format-FFUErrorMessage -Description '' -Remediation @() -Details @{}
            $result | Should -Be ''
        }

        It 'Formats single remediation step without numbering' {
            $result = Format-FFUErrorMessage -Description 'Desc' -Remediation @('Single step')
            $result | Should -Match 'Single step'
            $result | Should -Not -Match '^\s*1\.'
        }
    }

    Context 'Show-FFUError - Return Value' {
        It 'Returns MessageBoxResult' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                Mock Show-MessageBox { return [System.Windows.MessageBoxResult]::OK }
                $result = Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc'
                $result | Should -Be ([System.Windows.MessageBoxResult]::OK)
            }
        }
    }

    Context 'Show-FFUValidationErrors - Return Value' {
        It 'Returns MessageBoxResult' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                Mock Show-MessageBox { return [System.Windows.MessageBoxResult]::OK }
                $result = Show-FFUValidationErrors -Errors @('Error')
                $result | Should -Be ([System.Windows.MessageBoxResult]::OK)
            }
        }
    }

    Context 'Show-FFUError - Severity Header' {
        It 'Includes severity tag in message for Critical' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Critical' -Title 'Title' -Description 'Desc'
                $script:capturedMessage | Should -Match '\[Critical\]'
            }
        }

        It 'Includes severity tag in message for Error' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Error' -Title 'Title' -Description 'Desc'
                $script:capturedMessage | Should -Match '\[Error\]'
            }
        }

        It 'Includes severity tag in message for Warning' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Warning' -Title 'Title' -Description 'Desc'
                $script:capturedMessage | Should -Match '\[Warning\]'
            }
        }

        It 'Includes severity tag in message for Info' {
            InModuleScope 'FFUUI.Core.ErrorDisplay' {
                $capturedMessage = $null
                Mock Show-MessageBox {
                    param($Message, $Title, $Button, $Icon)
                    $script:capturedMessage = $Message
                    return [System.Windows.MessageBoxResult]::OK
                }
                Show-FFUError -Severity 'Info' -Title 'Title' -Description 'Desc'
                $script:capturedMessage | Should -Match '\[Info\]'
            }
        }
    }
}
