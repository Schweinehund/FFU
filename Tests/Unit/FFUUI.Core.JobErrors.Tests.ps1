#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5.x tests for FFUUI.Core.JobErrors module.

.DESCRIPTION
    Comprehensive tests for job error extraction functions:
    - Get-FFUJobError: Main function to extract errors from background jobs
    - ConvertTo-FFUErrorInfo: Converts FFUMessage to standardized error info
    - Get-ErrorTypeFromMessage: Classifies error type from message text
#>

BeforeAll {
    # Import the module under test
    $modulePath = "$PSScriptRoot/../../FFUDevelopment/FFUUI.Core/FFUUI.Core.JobErrors.psm1"
    Import-Module $modulePath -Force

    # Helper to create mock job
    function New-MockJob {
        param(
            [string]$State = 'Failed',
            [string]$Reason = $null,
            [object[]]$Errors = @(),
            [object[]]$ChildJobErrors = @()
        )
        $job = [PSCustomObject]@{
            State        = $State
            JobStateInfo = [PSCustomObject]@{
                State  = $State
                Reason = if ($Reason) { [PSCustomObject]@{ Message = $Reason } } else { $null }
            }
            Error        = [System.Collections.ArrayList]::new($Errors)
            ChildJobs    = @()
        }

        # Add child jobs if errors provided
        if ($ChildJobErrors.Count -gt 0) {
            $childJob = [PSCustomObject]@{
                Error = [System.Collections.ArrayList]::new($ChildJobErrors)
            }
            $job.ChildJobs = @($childJob)
        }

        return $job
    }

    # Helper to create mock messaging context
    function New-MockMessagingContext {
        param([PSObject[]]$Messages = @())
        $queue = [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()
        foreach ($msg in $Messages) { $queue.Enqueue($msg) }
        return @{ MessageQueue = $queue }
    }

    # Helper to create mock FFUMessage
    function New-MockFFUMessage {
        param(
            [string]$Message,
            [int]$Level = 5,
            # 5 = Error
            [string]$Source = 'Test',
            [hashtable]$Data = @{}
        )
        [PSCustomObject]@{
            Timestamp = [datetime]::UtcNow
            Level     = $Level
            Message   = $Message
            Source    = $Source
            Data      = $Data
            MessageId = 'test123'
        }
    }
}

Describe 'FFUUI.Core.JobErrors Module' {

    Describe 'Module Import' {
        It 'Imports without error' {
            { Import-Module $modulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Exports Get-FFUJobError' {
            Get-Command -Module FFUUI.Core.JobErrors -Name Get-FFUJobError -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Exports ConvertTo-FFUErrorInfo' {
            Get-Command -Module FFUUI.Core.JobErrors -Name ConvertTo-FFUErrorInfo -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Exports Get-ErrorTypeFromMessage' {
            Get-Command -Module FFUUI.Core.JobErrors -Name Get-ErrorTypeFromMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Get-ErrorTypeFromMessage' {

        It 'Returns DISMError for DISM-related messages' {
            Get-ErrorTypeFromMessage -Message 'DISM mount operation failed' | Should -Be 'DISMError'
        }

        It 'Returns DISMError for Mount-related messages' {
            Get-ErrorTypeFromMessage -Message 'Mount-WindowsImage failed' | Should -Be 'DISMError'
        }

        It 'Returns DISMError for WIM-related messages' {
            Get-ErrorTypeFromMessage -Message 'Error processing WIM file' | Should -Be 'DISMError'
        }

        It 'Returns DISMError for image-related messages' {
            Get-ErrorTypeFromMessage -Message 'Failed to apply image' | Should -Be 'DISMError'
        }

        It 'Returns HypervisorError for Hyper-V messages' {
            Get-ErrorTypeFromMessage -Message 'Hyper-V service not running' | Should -Be 'HypervisorError'
        }

        It 'Returns HypervisorError for VM messages' {
            Get-ErrorTypeFromMessage -Message 'VM failed to start' | Should -Be 'HypervisorError'
        }

        It 'Returns HypervisorError for Virtual messages' {
            Get-ErrorTypeFromMessage -Message 'Virtual switch not found' | Should -Be 'HypervisorError'
        }

        It 'Returns NetworkError for network messages' {
            Get-ErrorTypeFromMessage -Message 'Network connection failed' | Should -Be 'NetworkError'
        }

        It 'Returns NetworkError for connection messages' {
            Get-ErrorTypeFromMessage -Message 'Lost connection to server' | Should -Be 'NetworkError'
        }

        It 'Returns NetworkError for share messages' {
            Get-ErrorTypeFromMessage -Message 'Cannot access share path' | Should -Be 'NetworkError'
        }

        It 'Returns NetworkError for SMB messages' {
            Get-ErrorTypeFromMessage -Message 'SMB protocol error' | Should -Be 'NetworkError'
        }

        It 'Returns DiskError for disk messages' {
            Get-ErrorTypeFromMessage -Message 'Disk error occurred' | Should -Be 'DiskError'
        }

        It 'Returns DiskError for space messages' {
            Get-ErrorTypeFromMessage -Message 'Not enough space on disk' | Should -Be 'DiskError'
        }

        It 'Returns DiskError for storage messages' {
            Get-ErrorTypeFromMessage -Message 'Storage subsystem failure' | Should -Be 'DiskError'
        }

        It 'Returns PermissionError for permission messages' {
            Get-ErrorTypeFromMessage -Message 'Permission denied' | Should -Be 'PermissionError'
        }

        It 'Returns PermissionError for access denied messages' {
            Get-ErrorTypeFromMessage -Message 'Access denied to file' | Should -Be 'PermissionError'
        }

        It 'Returns PermissionError for 0x80070005 messages' {
            Get-ErrorTypeFromMessage -Message 'Error 0x80070005: Access is denied' | Should -Be 'PermissionError'
        }

        It 'Returns BuildError for unclassified messages' {
            Get-ErrorTypeFromMessage -Message 'Some random error occurred' | Should -Be 'BuildError'
        }

        It 'Returns BuildError for empty messages' {
            Get-ErrorTypeFromMessage -Message '' | Should -Be 'BuildError'
        }

        It 'Returns BuildError for whitespace-only messages' {
            Get-ErrorTypeFromMessage -Message '   ' | Should -Be 'BuildError'
        }
    }

    Describe 'ConvertTo-FFUErrorInfo' {

        It 'Extracts Message correctly' {
            $msg = New-MockFFUMessage -Message 'Test error message'
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.Message | Should -Be 'Test error message'
        }

        It 'Extracts Source correctly' {
            $msg = New-MockFFUMessage -Message 'Error' -Source 'FFU.Imaging'
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.Source | Should -Be 'FFU.Imaging'
        }

        It 'Creates Title with Build Failed prefix' {
            $msg = New-MockFFUMessage -Message 'Short error'
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.Title | Should -BeLike 'Build Failed:*'
        }

        It 'Truncates long messages in Title' {
            $longMessage = 'A' * 100
            $msg = New-MockFFUMessage -Message $longMessage
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.Title.Length | Should -BeLessOrEqual 100
            $result.Title | Should -Match '\.\.\.$'
        }

        It 'Extracts Remediation from Data' {
            $msg = New-MockFFUMessage -Message 'Error' -Data @{
                Remediation = @('Step 1', 'Step 2')
            }
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.Remediation | Should -Contain 'Step 1'
            $result.Remediation | Should -Contain 'Step 2'
        }

        It 'Extracts ErrorType from Data' {
            $msg = New-MockFFUMessage -Message 'Error' -Data @{
                ErrorType = 'DISMError'
            }
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.ErrorType | Should -Be 'DISMError'
        }

        It 'Classifies ErrorType from message when not in Data' {
            $msg = New-MockFFUMessage -Message 'DISM operation failed'
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.ErrorType | Should -Be 'DISMError'
        }

        It 'Returns BuildError when ErrorType not specified and message unclassified' {
            $msg = New-MockFFUMessage -Message 'Something went wrong'
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.ErrorType | Should -Be 'BuildError'
        }

        It 'Copies remaining Data keys to Details' {
            $msg = New-MockFFUMessage -Message 'Error' -Data @{
                Remediation = @('Fix it')
                ErrorType   = 'DISMError'
                ExitCode    = 1234
                Command     = 'dism.exe'
            }
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.Details['ExitCode'] | Should -Be 1234
            $result.Details['Command'] | Should -Be 'dism.exe'
            $result.Details.ContainsKey('Remediation') | Should -BeFalse
            $result.Details.ContainsKey('ErrorType') | Should -BeFalse
        }

        It 'Handles missing Data gracefully' {
            $msg = [PSCustomObject]@{
                Message = 'Error'
                Source  = 'Test'
                Data    = $null
            }
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.Details.Count | Should -Be 0
            $result.Remediation.Count | Should -Be 0
        }

        It 'Returns Unknown Source when Source is empty' {
            $msg = [PSCustomObject]@{
                Message = 'Error'
                Source  = ''
                Data    = @{}
            }
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.Source | Should -Be 'Unknown'
        }

        It 'Returns all expected properties' {
            $msg = New-MockFFUMessage -Message 'Error'
            $result = ConvertTo-FFUErrorInfo -FFUMessage $msg
            $result.PSObject.Properties.Name | Should -Contain 'ErrorType'
            $result.PSObject.Properties.Name | Should -Contain 'Title'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $result.PSObject.Properties.Name | Should -Contain 'Source'
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
            $result.PSObject.Properties.Name | Should -Contain 'Details'
            $result.PSObject.Properties.Name | Should -Contain 'LogPath'
            $result.PSObject.Properties.Name | Should -Contain 'OriginalException'
        }
    }

    Describe 'Get-FFUJobError' {

        Context 'MessagingContext Priority' {

            It 'Extracts error from MessagingContext Error messages' {
                $msg = New-MockFFUMessage -Message 'Build failed: DISM error' -Level 5 -Source 'FFU.Imaging'
                $context = New-MockMessagingContext -Messages @($msg)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Build failed: DISM error'
                $result.Source | Should -Be 'FFU.Imaging'
            }

            It 'Extracts error from MessagingContext Critical messages' {
                $msg = New-MockFFUMessage -Message 'Critical failure' -Level 6 -Source 'FFU.Core'
                $context = New-MockMessagingContext -Messages @($msg)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Critical failure'
            }

            It 'Ignores Info messages when looking for errors' {
                $infoMsg = New-MockFFUMessage -Message 'Info message' -Level 1
                $errorMsg = New-MockFFUMessage -Message 'Error message' -Level 5
                $context = New-MockMessagingContext -Messages @($infoMsg, $errorMsg)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Error message'
            }

            It 'Ignores Warning messages when looking for errors' {
                $warnMsg = New-MockFFUMessage -Message 'Warning message' -Level 4
                $errorMsg = New-MockFFUMessage -Message 'Error message' -Level 5
                $context = New-MockMessagingContext -Messages @($warnMsg, $errorMsg)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Error message'
            }

            It 'Uses last error message when multiple errors present' {
                $error1 = New-MockFFUMessage -Message 'First error' -Level 5
                $error2 = New-MockFFUMessage -Message 'Last error' -Level 5
                $context = New-MockMessagingContext -Messages @($error1, $error2)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Last error'
            }

            It 'Includes Remediation from message Data' {
                $msg = New-MockFFUMessage -Message 'Error' -Level 5 -Data @{
                    Remediation = @('Try this', 'Then that')
                }
                $context = New-MockMessagingContext -Messages @($msg)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Remediation | Should -Contain 'Try this'
            }

            It 'Includes ErrorType from message Data' {
                $msg = New-MockFFUMessage -Message 'Error' -Level 5 -Data @{
                    ErrorType = 'NetworkError'
                }
                $context = New-MockMessagingContext -Messages @($msg)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.ErrorType | Should -Be 'NetworkError'
            }
        }

        Context 'Job Error Fallbacks' {

            It 'Falls back to Job.JobStateInfo.Reason when no messaging errors' {
                $context = New-MockMessagingContext -Messages @()
                $job = New-MockJob -State 'Failed' -Reason 'Job state reason message'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Job state reason message'
                $result.Source | Should -Be 'JobStateInfo'
            }

            It 'Falls back to Job.ChildJobs errors when no other sources' {
                $context = New-MockMessagingContext -Messages @()
                $job = New-MockJob -State 'Failed' -ChildJobErrors @('Child job error message')

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Child job error message'
                $result.Source | Should -Be 'ChildJob'
            }

            It 'Falls back to Job.Error stream when no other sources' {
                $context = New-MockMessagingContext -Messages @()
                $job = New-MockJob -State 'Failed' -Errors @('Job error message')

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Job error message'
                $result.Source | Should -Be 'JobError'
            }

            It 'Returns generic message when all sources empty' {
                $context = New-MockMessagingContext -Messages @()
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Match 'unknown error occurred'
                $result.ErrorType | Should -Be 'Unknown'
            }
        }

        Context 'Null/Empty Handling' {

            It 'Handles null MessagingContext gracefully' {
                $job = New-MockJob -State 'Failed' -Reason 'Some error'
                $result = Get-FFUJobError -Job $job -MessagingContext $null
                $result.Message | Should -Be 'Some error'
            }

            It 'Handles empty MessagingContext queue' {
                $context = New-MockMessagingContext -Messages @()
                $job = New-MockJob -State 'Failed' -Reason 'Fallback reason'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Fallback reason'
            }

            It 'Handles MessagingContext without MessageQueue key' {
                $context = @{ SomeOtherKey = 'value' }
                $job = New-MockJob -State 'Failed' -Reason 'Reason message'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.Message | Should -Be 'Reason message'
            }
        }

        Context 'LogPath Handling' {

            It 'Includes LogPath in result when provided' {
                $job = New-MockJob -State 'Failed'
                $result = Get-FFUJobError -Job $job -LogPath 'C:\test\log.txt'
                $result.LogPath | Should -Be 'C:\test\log.txt'
            }

            It 'Provides remediation hints when log file does not exist' {
                $job = New-MockJob -State 'Failed'
                $result = Get-FFUJobError -Job $job -LogPath 'C:\nonexistent\path.log'
                $result.Remediation | Should -Contain 'Verify FFUDevelopmentPath exists and is accessible'
            }
        }

        Context 'Error Type Classification' {

            It 'Classifies error type from message text' {
                $msg = New-MockFFUMessage -Message 'DISM mount failed' -Level 5
                $context = New-MockMessagingContext -Messages @($msg)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.ErrorType | Should -Be 'DISMError'
            }

            It 'Uses ErrorType from Data if present' {
                $msg = New-MockFFUMessage -Message 'Generic error' -Level 5 -Data @{
                    ErrorType = 'HypervisorError'
                }
                $context = New-MockMessagingContext -Messages @($msg)
                $job = New-MockJob -State 'Failed'

                $result = Get-FFUJobError -Job $job -MessagingContext $context
                $result.ErrorType | Should -Be 'HypervisorError'
            }
        }

        Context 'Return Structure' {

            It 'Returns structured PSCustomObject with all expected properties' {
                $job = New-MockJob -State 'Failed'
                $result = Get-FFUJobError -Job $job

                $result.PSObject.Properties.Name | Should -Contain 'ErrorType'
                $result.PSObject.Properties.Name | Should -Contain 'Title'
                $result.PSObject.Properties.Name | Should -Contain 'Message'
                $result.PSObject.Properties.Name | Should -Contain 'Source'
                $result.PSObject.Properties.Name | Should -Contain 'Remediation'
                $result.PSObject.Properties.Name | Should -Contain 'Details'
                $result.PSObject.Properties.Name | Should -Contain 'LogPath'
                $result.PSObject.Properties.Name | Should -Contain 'OriginalException'
            }

            It 'Returns Remediation as array' {
                $job = New-MockJob -State 'Failed'
                $result = Get-FFUJobError -Job $job

                # Remediation should be an array (possibly empty or with items)
                , $result.Remediation | Should -BeOfType [array]
            }

            It 'Returns Details as hashtable' {
                $job = New-MockJob -State 'Failed'
                $result = Get-FFUJobError -Job $job

                $result.Details | Should -BeOfType [hashtable]
            }
        }
    }
}
