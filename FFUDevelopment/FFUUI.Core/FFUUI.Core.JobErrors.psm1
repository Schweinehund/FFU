<#
.SYNOPSIS
    Job error extraction and formatting functions for the FFU Builder UI.

.DESCRIPTION
    Provides functions to extract rich error context from background job failures:
    - Extracts structured errors from FFU.Messaging queue
    - Falls back to job error streams and state info
    - Classifies error types for appropriate handling
    - Formats errors for display via Show-FFUError

    Replaces ad-hoc error extraction with intelligent context extraction.

.NOTES
    Module: FFUUI.Core.JobErrors
    Version: 1.0.0
    Author: FFUBuilder Team
    Requires: PowerShell 7.0+
#>

#region Error Type Classification

function Get-ErrorTypeFromMessage {
    <#
    .SYNOPSIS
        Classifies error type from message text.

    .DESCRIPTION
        Uses pattern matching to classify error messages into categories:
        - DISMError: DISM, Mount, WIM, image operations
        - HypervisorError: Hyper-V, VM, Virtual operations
        - NetworkError: Network, connection, share, SMB issues
        - DiskError: Disk, space, storage issues
        - PermissionError: Permission, access denied, 0x80070005
        - BuildError: Default for unclassified errors

    .PARAMETER Message
        The error message text to classify.

    .OUTPUTS
        [string] - Error type classification.

    .EXAMPLE
        Get-ErrorTypeFromMessage -Message "DISM mount failed"
        # Returns: DISMError
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return 'BuildError'
    }

    # Pattern matching for error classification
    if ($Message -match 'DISM|Mount|WIM|image') {
        return 'DISMError'
    }

    if ($Message -match 'Hyper-V|VM|Virtual') {
        return 'HypervisorError'
    }

    if ($Message -match 'network|connection|share|SMB') {
        return 'NetworkError'
    }

    if ($Message -match 'disk|space|storage') {
        return 'DiskError'
    }

    if ($Message -match 'permission|access denied|0x80070005') {
        return 'PermissionError'
    }

    return 'BuildError'
}

#endregion

#region FFUMessage Conversion

function ConvertTo-FFUErrorInfo {
    <#
    .SYNOPSIS
        Converts an FFUMessage object to a standardized error info structure.

    .DESCRIPTION
        Extracts error information from an FFUMessage object (from FFU.Messaging queue):
        - Message -> Title (truncated if too long) and Message (full text)
        - Source -> Source
        - Data['Remediation'] -> Remediation (if present)
        - Data['ErrorType'] -> ErrorType (if present, else classified from message)
        - Data -> Details (minus Remediation/ErrorType)

    .PARAMETER FFUMessage
        The FFUMessage object from the messaging queue.

    .OUTPUTS
        [PSCustomObject] - Standardized error info structure.

    .EXAMPLE
        $errorInfo = ConvertTo-FFUErrorInfo -FFUMessage $msg
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$FFUMessage
    )

    # Extract base message
    $messageText = if ($null -ne $FFUMessage.Message) {
        $FFUMessage.Message.ToString()
    }
    else {
        ''
    }

    # Create title (truncate if too long)
    $maxTitleLength = 80
    $title = if ($messageText.Length -gt $maxTitleLength) {
        "Build Failed: $($messageText.Substring(0, $maxTitleLength - 3))..."
    }
    else {
        "Build Failed: $messageText"
    }

    # Extract source
    $source = if ($null -ne $FFUMessage.Source -and -not [string]::IsNullOrWhiteSpace($FFUMessage.Source)) {
        $FFUMessage.Source.ToString()
    }
    else {
        'Unknown'
    }

    # Initialize data extraction
    $remediation = @()
    $errorType = $null
    $details = @{}

    # Extract from Data hashtable if present
    if ($null -ne $FFUMessage.Data -and $FFUMessage.Data -is [hashtable]) {
        $data = $FFUMessage.Data

        # Extract Remediation
        if ($data.ContainsKey('Remediation')) {
            $remediation = @($data['Remediation'])
        }

        # Extract ErrorType
        if ($data.ContainsKey('ErrorType')) {
            $errorType = $data['ErrorType']
        }

        # Copy remaining keys to Details
        foreach ($key in $data.Keys) {
            if ($key -notin @('Remediation', 'ErrorType')) {
                $details[$key] = $data[$key]
            }
        }
    }

    # Classify error type from message if not in Data
    if ([string]::IsNullOrWhiteSpace($errorType)) {
        $errorType = Get-ErrorTypeFromMessage -Message $messageText
    }

    return [PSCustomObject]@{
        ErrorType         = $errorType
        Title             = $title
        Message           = $messageText
        Source            = $source
        Remediation       = $remediation
        Details           = $details
        LogPath           = $null
        OriginalException = $null
    }
}

#endregion

#region Main Job Error Extraction

function Get-FFUJobError {
    <#
    .SYNOPSIS
        Extracts rich error context from a background job failure.

    .DESCRIPTION
        Main function to extract error information from a failed PowerShell job.
        Uses multiple sources in priority order:

        1. MessagingContext (most reliable) - Structured errors from FFU.Messaging
        2. Job.ChildJobs error streams (ThreadJob pattern)
        3. Job.JobStateInfo.Reason (standard PowerShell job failure)
        4. Job output error patterns (fallback)
        5. Generic message (last resort)

        Returns a structured PSCustomObject suitable for Show-FFUError display.

    .PARAMETER Job
        The PowerShell job to extract error from.

    .PARAMETER MessagingContext
        Synchronized messaging context from FFU.Messaging. Contains MessageQueue
        with structured error messages.

    .PARAMETER LogPath
        Path to log file for inclusion in error info.

    .OUTPUTS
        [PSCustomObject] - Structured error info with:
        - ErrorType: DISMError, HypervisorError, NetworkError, DiskError, PermissionError, BuildError, Unknown
        - Title: Brief error summary
        - Message: Detailed error description
        - Source: Module/phase that raised the error
        - Remediation: Array of remediation steps (may be empty)
        - Details: Hashtable of additional info (may be empty)
        - LogPath: Log file path (if provided)
        - OriginalException: Exception object (if available)

    .EXAMPLE
        $errorInfo = Get-FFUJobError -Job $currentJob -MessagingContext $syncHash -LogPath $logPath
        Show-FFUError -Severity 'Error' -Title $errorInfo.Title -Description $errorInfo.Message `
            -Remediation $errorInfo.Remediation -LogPath $errorInfo.LogPath
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Accept PSObject to allow mocking in tests; at runtime this is always a Job
        [Parameter(Mandatory)]
        [PSObject]$Job,

        [Parameter()]
        [hashtable]$MessagingContext,

        [Parameter()]
        [string]$LogPath
    )

    # Initialize result structure
    $result = [PSCustomObject]@{
        ErrorType         = 'Unknown'
        Title             = 'Build Failed'
        Message           = ''
        Source            = 'Unknown'
        Remediation       = @()
        Details           = @{}
        LogPath           = $LogPath
        OriginalException = $null
    }

    #region Priority 1: Check MessagingContext

    if ($null -ne $MessagingContext -and $MessagingContext.ContainsKey('MessageQueue')) {
        $queue = $MessagingContext['MessageQueue']

        if ($null -ne $queue) {
            # Collect error/critical messages from queue (peek without consuming)
            $errorMessages = [System.Collections.Generic.List[PSObject]]::new()

            # Convert queue to array to inspect without modifying
            $queueArray = $queue.ToArray()

            foreach ($msg in $queueArray) {
                # Check for Error (5) or Critical (6) level
                if ($null -ne $msg.Level) {
                    $level = 0
                    if ($msg.Level -is [int]) {
                        $level = $msg.Level
                    }
                    elseif ($msg.Level.GetType().IsEnum) {
                        $level = [int]$msg.Level
                    }

                    if ($level -ge 5) {
                        $errorMessages.Add($msg)
                    }
                }
            }

            # Use the last (most recent) error message
            if ($errorMessages.Count -gt 0) {
                $lastError = $errorMessages[$errorMessages.Count - 1]
                $result = ConvertTo-FFUErrorInfo -FFUMessage $lastError
                $result.LogPath = $LogPath
                return $result
            }
        }
    }

    #endregion

    #region Priority 2: Check Job.ChildJobs (ThreadJob pattern)

    if ($null -ne $Job.ChildJobs -and $Job.ChildJobs.Count -gt 0) {
        foreach ($childJob in $Job.ChildJobs) {
            if ($null -ne $childJob.Error -and $childJob.Error.Count -gt 0) {
                $lastError = $childJob.Error | Select-Object -Last 1
                if ($null -ne $lastError) {
                    $errorMessage = $lastError.ToString()

                    $result.ErrorType = Get-ErrorTypeFromMessage -Message $errorMessage
                    $result.Title = "Build Failed: $($result.ErrorType -replace 'Error$', ' Error')"
                    $result.Message = $errorMessage
                    $result.Source = 'ChildJob'

                    if ($lastError -is [System.Management.Automation.ErrorRecord]) {
                        $result.OriginalException = $lastError.Exception
                        if ($null -ne $lastError.TargetObject) {
                            $result.Details['TargetObject'] = $lastError.TargetObject.ToString()
                        }
                    }

                    return $result
                }
            }
        }
    }

    #endregion

    #region Priority 3: Check Job.JobStateInfo.Reason

    if ($null -ne $Job.JobStateInfo -and $null -ne $Job.JobStateInfo.Reason) {
        $reason = $Job.JobStateInfo.Reason

        if ($null -ne $reason.Message -and -not [string]::IsNullOrWhiteSpace($reason.Message)) {
            $errorMessage = $reason.Message

            $result.ErrorType = Get-ErrorTypeFromMessage -Message $errorMessage
            $result.Title = "Build Failed: $($result.ErrorType -replace 'Error$', ' Error')"
            $result.Message = $errorMessage
            $result.Source = 'JobStateInfo'
            $result.OriginalException = $reason

            return $result
        }
    }

    #endregion

    #region Priority 4: Check Job.Error stream directly

    if ($null -ne $Job.Error -and $Job.Error.Count -gt 0) {
        $lastError = $Job.Error | Select-Object -Last 1
        if ($null -ne $lastError) {
            $errorMessage = $lastError.ToString()

            $result.ErrorType = Get-ErrorTypeFromMessage -Message $errorMessage
            $result.Title = "Build Failed: $($result.ErrorType -replace 'Error$', ' Error')"
            $result.Message = $errorMessage
            $result.Source = 'JobError'

            if ($lastError -is [System.Management.Automation.ErrorRecord]) {
                $result.OriginalException = $lastError.Exception
            }

            return $result
        }
    }

    #endregion

    #region Priority 5: Fallback to generic message

    # Check job state for additional context
    $stateInfo = ''
    if ($null -ne $Job.State) {
        $stateInfo = "Job state: $($Job.State)"
    }

    $result.ErrorType = 'Unknown'
    $result.Title = 'Build Failed: Unknown Error'

    if (-not [string]::IsNullOrWhiteSpace($LogPath) -and (Test-Path -Path $LogPath -ErrorAction SilentlyContinue)) {
        $result.Message = "An unknown error occurred during the build process. $stateInfo"
        $result.Remediation = @(
            'Check the log file for detailed error information',
            'Verify all prerequisites are installed',
            'Ensure sufficient disk space is available',
            'Try running the build again'
        )
    }
    else {
        $result.Message = "An unknown error occurred during the build process. $stateInfo`n`nNo log file was created, which usually indicates an early failure before logging started."
        $result.Remediation = @(
            'Verify FFUDevelopmentPath exists and is accessible',
            'Check that all parameters are valid',
            'Ensure you have administrator privileges',
            'Try running the build again'
        )
    }

    $result.Source = 'Unknown'

    return $result

    #endregion
}

#endregion

#region Module Export

Export-ModuleMember -Function @(
    'Get-FFUJobError',
    'ConvertTo-FFUErrorInfo',
    'Get-ErrorTypeFromMessage'
)

#endregion
