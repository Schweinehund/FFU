<#
.SYNOPSIS
    Retry wrapper for hypervisor operations that handles service interruptions.

.DESCRIPTION
    Wraps hypervisor operations with automatic retry logic when service interruptions
    are detected. Uses exponential backoff with jitter to avoid hammering the service.

    Service issues are detected by analyzing error messages for:
    - Hyper-V: "Virtual Machine Management Service is not running", RPC errors
    - VMware: "Unable to connect", process not found errors

    Non-service errors (like invalid parameters) are NOT retried.

.PARAMETER ScriptBlock
    The script block to execute. Should contain hypervisor operations.

.PARAMETER Provider
    The hypervisor provider: 'HyperV' or 'VMware'.

.PARAMETER MaxRetries
    Maximum number of retry attempts. Default is 3.

.PARAMETER BaseDelaySeconds
    Base delay between retries in seconds. Default is 5.
    Actual delay uses exponential backoff: BaseDelay * (2 ^ (attempt - 1))

.PARAMETER OperationName
    Name of the operation for logging. Default is 'Hypervisor operation'.

.PARAMETER PreCheckService
    If specified, validates service health before executing the script block.

.OUTPUTS
    The result of the ScriptBlock on success.

.EXAMPLE
    Invoke-WithHypervisorRetry -Provider 'HyperV' -OperationName 'StartVM' -ScriptBlock {
        Start-VM -Name $VMName -ErrorAction Stop
    }

.EXAMPLE
    $result = Invoke-WithHypervisorRetry -Provider 'VMware' -PreCheckService -ScriptBlock {
        $provider.GetVMState($VM)
    }

.NOTES
    Module: FFU.Hypervisor
    REL-HYP-04: Service recovery support
#>
function Invoke-WithHypervisorRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $true)]
        [ValidateSet('HyperV', 'VMware')]
        [string]$Provider,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false)]
        [int]$BaseDelaySeconds = 5,

        [Parameter(Mandatory = $false)]
        [string]$OperationName = 'Hypervisor operation',

        [Parameter(Mandatory = $false)]
        [switch]$PreCheckService
    )

    # Pre-check service if requested
    if ($PreCheckService) {
        $serviceStatus = Test-HypervisorService -Provider $Provider

        if (-not $serviceStatus.IsHealthy) {
            if ($function:WriteLog) {
                WriteLog "$OperationName: Service not healthy, waiting for recovery..."
            }

            # Wait for service to become ready
            $serviceStatus = Test-HypervisorService -Provider $Provider -WaitForReady -TimeoutSeconds 60

            if (-not $serviceStatus.IsHealthy) {
                $errorMessage = "$OperationName failed: $Provider service is not available."
                if ($serviceStatus.RecoveryAction) {
                    $errorMessage += " Recovery: $($serviceStatus.RecoveryAction)"
                }
                throw $errorMessage
            }
        }
    }

    # Track attempt information for error reporting
    $attempts = @()
    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            # Execute the script block
            $result = & $ScriptBlock

            # Success - return the result
            if ($attempt -gt 1 -and $function:WriteLog) {
                WriteLog "$OperationName succeeded on attempt $attempt"
            }

            return $result
        }
        catch {
            $lastError = $_
            $errorMessage = $_.Exception.Message

            # Track this attempt
            $attempts += @{
                Attempt = $attempt
                Time = [datetime]::Now
                Error = $errorMessage
            }

            # Check if this is a service-related error
            $isServiceError = Test-IsServiceError -Provider $Provider -ErrorMessage $errorMessage

            if (-not $isServiceError) {
                # Not a service error - rethrow immediately without retry
                if ($function:WriteLog) {
                    WriteLog "$OperationName failed (non-recoverable): $errorMessage"
                }
                throw
            }

            # Service error detected - log and prepare for retry
            if ($function:WriteLog) {
                WriteLog "$OperationName failed (attempt $attempt/$MaxRetries): Service may have restarted"
                WriteLog "  Error: $errorMessage"
            }

            # Check if we have retries left
            if ($attempt -ge $MaxRetries) {
                break
            }

            # Wait for service to recover
            if ($function:WriteLog) {
                WriteLog "Checking service status before retry..."
            }
            $serviceStatus = Test-HypervisorService -Provider $Provider -WaitForReady -TimeoutSeconds 60

            if (-not $serviceStatus.IsHealthy) {
                if ($function:WriteLog) {
                    WriteLog "WARNING: Service did not recover. Status: $($serviceStatus.ServiceStatus)"
                }
                # Try anyway - maybe it will work
            }

            # Calculate delay with exponential backoff and jitter
            $baseDelay = $BaseDelaySeconds * [math]::Pow(2, $attempt - 1)
            $jitter = Get-Random -Minimum 0 -Maximum ([int]($baseDelay * 0.3))
            $delay = [int]($baseDelay + $jitter)

            if ($function:WriteLog) {
                WriteLog "Waiting ${delay}s before retry..."
            }
            Start-Sleep -Seconds $delay
        }
    }

    # Max retries exhausted - build comprehensive error message
    $finalServiceStatus = Test-HypervisorService -Provider $Provider

    $errorBuilder = [System.Text.StringBuilder]::new()
    [void]$errorBuilder.AppendLine("$OperationName failed after $MaxRetries attempts.")
    [void]$errorBuilder.AppendLine("")
    [void]$errorBuilder.AppendLine("Attempt history:")
    foreach ($att in $attempts) {
        [void]$errorBuilder.AppendLine("  Attempt $($att.Attempt) at $($att.Time.ToString('HH:mm:ss')): $($att.Error)")
    }
    [void]$errorBuilder.AppendLine("")
    [void]$errorBuilder.AppendLine("Current service status: $($finalServiceStatus.ServiceStatus)")
    if ($finalServiceStatus.RecoveryAction) {
        [void]$errorBuilder.AppendLine("Suggested recovery: $($finalServiceStatus.RecoveryAction)")
    }

    if ($function:WriteLog) {
        WriteLog "ERROR: $($errorBuilder.ToString())"
    }

    throw $errorBuilder.ToString()
}

<#
.SYNOPSIS
    Tests if an error message indicates a service-related issue.

.DESCRIPTION
    Analyzes error messages to determine if they indicate a transient service
    issue that might be resolved by retrying after the service recovers.

.PARAMETER Provider
    The hypervisor provider: 'HyperV' or 'VMware'.

.PARAMETER ErrorMessage
    The error message to analyze.

.OUTPUTS
    Boolean - true if the error appears to be service-related.
#>
function Test-IsServiceError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HyperV', 'VMware')]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ErrorMessage
    )

    if ([string]::IsNullOrEmpty($ErrorMessage)) {
        return $false
    }

    $lowerError = $ErrorMessage.ToLower()

    if ($Provider -eq 'HyperV') {
        # Hyper-V service-related errors
        $hyperVServicePatterns = @(
            'virtual machine management service',
            'vmms',
            'the service has not been started',
            'rpc server is unavailable',
            'rpc server is too busy',
            'the hyper-v virtual machine management service',
            'failed to connect',
            'access is denied',  # Can happen during service restart
            'could not connect to the virtual machine',
            'the operation cannot be performed while the object is in use',
            'the requested operation cannot be performed on a file with a user-mapped section open'
        )

        foreach ($pattern in $hyperVServicePatterns) {
            if ($lowerError.Contains($pattern.ToLower())) {
                return $true
            }
        }
    }
    else {
        # VMware service-related errors
        $vmwareServicePatterns = @(
            'unable to connect',
            'vmrun',
            'process not found',
            'cannot connect',
            'connection refused',
            'vmware-vmx',
            'operation was canceled',
            'cannot open file',
            'unable to open file',
            'failed to lock',
            'cannot access'
        )

        foreach ($pattern in $vmwareServicePatterns) {
            if ($lowerError.Contains($pattern.ToLower())) {
                return $true
            }
        }
    }

    return $false
}
