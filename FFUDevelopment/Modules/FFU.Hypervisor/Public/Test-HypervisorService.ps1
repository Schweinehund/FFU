<#
.SYNOPSIS
    Tests hypervisor service health and reports recovery options.

.DESCRIPTION
    Checks the health of the hypervisor service for either Hyper-V or VMware.
    Returns a hashtable with service status, health indicator, and recovery guidance.

    For Hyper-V:
    - Checks vmms (Virtual Machine Management) service status
    - Checks vmcompute (Hyper-V Host Compute Service) if available
    - Service must be 'Running' to be healthy

    For VMware:
    - Checks for vmware-vmx.exe processes
    - Checks VMAuthdService if exists
    - Checks if vmrun.exe is accessible
    - VMware is considered healthy if vmrun is accessible (doesn't require running service)

.PARAMETER Provider
    The hypervisor provider to check: 'HyperV' or 'VMware'.

.PARAMETER WaitForReady
    If specified and service is not healthy, poll until ready or timeout.

.PARAMETER TimeoutSeconds
    Maximum time to wait for service to become ready when WaitForReady is specified.
    Default is 60 seconds.

.OUTPUTS
    Hashtable with:
    - IsHealthy: boolean - true if service is ready for operations
    - ServiceStatus: string - 'Running', 'Stopped', 'Starting', etc.
    - CanRecover: boolean - true if service can be started automatically
    - RecoveryAction: string - command/action to recover (e.g., "Start-Service vmms")
    - LastCheckTime: datetime

.EXAMPLE
    $result = Test-HypervisorService -Provider 'HyperV'
    if ($result.IsHealthy) { Write-Host "Hyper-V is ready" }

.EXAMPLE
    $result = Test-HypervisorService -Provider 'VMware' -WaitForReady -TimeoutSeconds 30
    if (-not $result.IsHealthy) { Write-Host "VMware not ready: $($result.RecoveryAction)" }

.NOTES
    Module: FFU.Hypervisor
    REL-HYP-04: Service recovery support
#>
function Test-HypervisorService {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HyperV', 'VMware')]
        [string]$Provider,

        [Parameter(Mandatory = $false)]
        [switch]$WaitForReady,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 60
    )

    $result = @{
        IsHealthy = $false
        ServiceStatus = 'Unknown'
        CanRecover = $false
        RecoveryAction = $null
        LastCheckTime = [datetime]::Now
    }

    # Perform the check based on provider
    if ($Provider -eq 'HyperV') {
        $result = Test-HyperVServiceHealth
    }
    else {
        $result = Test-VMwareServiceHealth
    }

    # If not healthy and WaitForReady specified, poll until ready or timeout
    if (-not $result.IsHealthy -and $WaitForReady) {
        if ($function:WriteLog) {
            WriteLog "Waiting for $Provider service to become ready (timeout: ${TimeoutSeconds}s)..."
        }

        $pollIntervalMs = 1000
        $elapsed = 0
        $maxMs = $TimeoutSeconds * 1000

        while ($elapsed -lt $maxMs) {
            Start-Sleep -Milliseconds $pollIntervalMs
            $elapsed += $pollIntervalMs

            # Re-check
            if ($Provider -eq 'HyperV') {
                $result = Test-HyperVServiceHealth
            }
            else {
                $result = Test-VMwareServiceHealth
            }

            if ($result.IsHealthy) {
                if ($function:WriteLog) {
                    WriteLog "$Provider service became ready after $([int]($elapsed/1000))s"
                }
                break
            }

            # Log progress every 10 seconds
            if (($elapsed % 10000) -eq 0) {
                if ($function:WriteLog) {
                    WriteLog "Still waiting for $Provider service... ($([int]($elapsed/1000))s elapsed)"
                }
            }
        }

        if (-not $result.IsHealthy) {
            if ($function:WriteLog) {
                WriteLog "WARNING: $Provider service did not become ready within ${TimeoutSeconds}s"
            }
        }
    }

    return $result
}

# Internal helper for Hyper-V service health check
function Test-HyperVServiceHealth {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{
        IsHealthy = $false
        ServiceStatus = 'Unknown'
        CanRecover = $false
        RecoveryAction = $null
        LastCheckTime = [datetime]::Now
    }

    try {
        # Check vmms (Virtual Machine Management) service - primary service
        $vmmsService = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue

        if (-not $vmmsService) {
            $result.ServiceStatus = 'NotInstalled'
            $result.CanRecover = $false
            $result.RecoveryAction = 'Hyper-V is not installed. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart'
            return $result
        }

        $result.ServiceStatus = $vmmsService.Status.ToString()

        if ($vmmsService.Status -eq 'Running') {
            $result.IsHealthy = $true
            $result.CanRecover = $false
            $result.RecoveryAction = $null
        }
        elseif ($vmmsService.Status -eq 'Stopped') {
            $result.CanRecover = $true
            $result.RecoveryAction = 'Start-Service vmms'
        }
        elseif ($vmmsService.Status -eq 'StartPending' -or $vmmsService.Status -eq 'Starting') {
            $result.ServiceStatus = 'Starting'
            $result.CanRecover = $false  # Already starting, just wait
            $result.RecoveryAction = 'Service is starting, wait for it to complete'
        }
        elseif ($vmmsService.Status -eq 'StopPending' -or $vmmsService.Status -eq 'Stopping') {
            $result.ServiceStatus = 'Stopping'
            $result.CanRecover = $true  # Can restart after it stops
            $result.RecoveryAction = 'Wait for service to stop, then run: Start-Service vmms'
        }
        else {
            # Other statuses (Paused, etc.)
            $result.CanRecover = $true
            $result.RecoveryAction = 'Restart-Service vmms -Force'
        }

        # Also check vmcompute if it exists (Windows Server / newer Windows 10+)
        $vmcomputeService = Get-Service -Name 'vmcompute' -ErrorAction SilentlyContinue
        if ($vmcomputeService -and $vmcomputeService.Status -ne 'Running') {
            # vmcompute not running can affect some operations
            if ($result.IsHealthy) {
                # vmms is running but vmcompute isn't - still functional but note it
                if ($function:WriteLog) {
                    WriteLog "Note: vmcompute service is $($vmcomputeService.Status) (may affect container/isolation features)"
                }
            }
        }
    }
    catch {
        $result.ServiceStatus = 'Error'
        $result.CanRecover = $false
        $result.RecoveryAction = "Error checking service: $($_.Exception.Message)"
    }

    return $result
}

# Internal helper for VMware service health check
function Test-VMwareServiceHealth {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{
        IsHealthy = $false
        ServiceStatus = 'Unknown'
        CanRecover = $false
        RecoveryAction = $null
        LastCheckTime = [datetime]::Now
    }

    try {
        # VMware doesn't require a persistent service for vmrun to work
        # Check if vmrun.exe is accessible - that's the primary requirement
        $vmrunPath = Get-VmrunPath
        if ([string]::IsNullOrEmpty($vmrunPath)) {
            $result.ServiceStatus = 'NotInstalled'
            $result.CanRecover = $false
            $result.RecoveryAction = 'VMware Workstation not found. Install VMware Workstation Pro 17.x or later.'
            return $result
        }

        # vmrun exists - VMware is functional for our purposes
        $result.IsHealthy = $true
        $result.ServiceStatus = 'Available'

        # Check VMAuthdService (optional, used for shared VMs)
        $vmAuthService = Get-Service -Name 'VMAuthdService' -ErrorAction SilentlyContinue
        if ($vmAuthService) {
            if ($vmAuthService.Status -eq 'Running') {
                $result.ServiceStatus = 'Running'
            }
            elseif ($vmAuthService.Status -eq 'Stopped') {
                # VMAuthdService stopped is fine for local VMs
                $result.ServiceStatus = 'PartiallyRunning'
            }
        }

        # Check for vmware-vmx processes (indicates VMs are actually running)
        $vmxProcesses = Get-Process -Name 'vmware-vmx' -ErrorAction SilentlyContinue
        if ($vmxProcesses) {
            $result.ServiceStatus = "Running ($($vmxProcesses.Count) VM(s) active)"
        }

        $result.CanRecover = $false
        $result.RecoveryAction = $null

        # Note: If VMware processes crash, they self-recover when you try to start a VM
        # So there's no explicit recovery action needed for VMware
    }
    catch {
        $result.ServiceStatus = 'Error'
        $result.IsHealthy = $false
        $result.CanRecover = $false
        $result.RecoveryAction = "Error checking VMware: $($_.Exception.Message)"
    }

    return $result
}
