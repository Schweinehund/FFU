<#
.SYNOPSIS
    Factory function to get a hypervisor provider instance

.DESCRIPTION
    Returns an appropriate hypervisor provider based on the specified type.
    Supports 'HyperV', 'VMware', and 'Auto' (auto-detect best available).

    When a provider is unavailable, error messages include actionable remediation
    steps to help users resolve the issue.

.PARAMETER Type
    The type of hypervisor provider to return:
    - 'HyperV': Microsoft Hyper-V provider
    - 'VMware': VMware Workstation Pro provider (uses vmrun/vmxtoolkit)
    - 'Auto': Automatically detect and return the best available provider

.PARAMETER Validate
    If specified, validates that the provider is available before returning it.
    Throws an error if the requested provider is not available.

.EXAMPLE
    $provider = Get-HypervisorProvider -Type 'HyperV'
    $vm = $provider.CreateVM($config)

.EXAMPLE
    $provider = Get-HypervisorProvider -Type 'Auto' -Validate
    # Returns the first available provider

.EXAMPLE
    $provider = Get-HypervisorProvider -Type 'VMware'
    # Returns VMware provider (uses vmrun.exe, no credentials needed)

.OUTPUTS
    IHypervisorProvider

.NOTES
    Module: FFU.Hypervisor
    Version: 1.3.0
    VMware provider uses vmrun.exe/vmxtoolkit (no REST API/credentials required)
    Enhanced error messages with remediation guidance (REL-HYP-01)
#>
function Get-HypervisorProvider {
    [CmdletBinding()]
    [OutputType([object])]  # Returns IHypervisorProvider-derived class
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$Type = 'Auto',

        [Parameter(Mandatory = $false)]
        [switch]$Validate
    )

    process {
        $provider = $null

        switch ($Type) {
            'HyperV' {
                $provider = [HyperVProvider]::new()
            }
            'VMware' {
                # VMware provider uses vmrun.exe/vmxtoolkit - no credentials needed
                $provider = [VMwareProvider]::new()
            }
            'Auto' {
                # Try providers in order of preference: Hyper-V first, then VMware
                # Collect availability details for both for better error messages
                $hyperv = [HyperVProvider]::new()
                $hypervDetails = $hyperv.GetAvailabilityDetails()

                if ($hypervDetails.IsAvailable) {
                    $provider = $hyperv
                    WriteLog "Auto-detected hypervisor: Hyper-V"
                }
                else {
                    # Log why Hyper-V failed, then try VMware
                    $hypervReason = if ($hypervDetails.Issues.Count -gt 0) { $hypervDetails.Issues[0] } else { 'Unknown issue' }
                    WriteLog "Hyper-V not available: $hypervReason. Checking VMware..."

                    $vmware = [VMwareProvider]::new()
                    $vmwareDetails = $vmware.GetAvailabilityDetails()

                    if ($vmwareDetails.IsAvailable) {
                        $provider = $vmware
                        WriteLog "Auto-detected hypervisor: VMware Workstation"
                    }
                    else {
                        # Neither available - build comprehensive error message with remediation
                        $errorMessage = Format-ProviderUnavailableError -HypervDetails $hypervDetails -VmwareDetails $vmwareDetails
                        throw $errorMessage
                    }
                }
            }
        }

        if ($Validate -and $provider) {
            $available = $provider.TestAvailable()
            if (-not $available) {
                $details = $provider.GetAvailabilityDetails()
                $errorMessage = Format-SingleProviderError -ProviderDetails $details
                throw $errorMessage
            }
        }

        return $provider
    }
}

<#
.SYNOPSIS
    Formats error message for a single provider that is unavailable

.DESCRIPTION
    Internal helper function that creates a detailed error message with
    ErrorCode and remediation steps for a single provider.
#>
function Format-SingleProviderError {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ProviderDetails
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("Hypervisor '$($ProviderDetails.ProviderName)' is not available.")
    [void]$sb.AppendLine()

    # Add error code if present
    if ($ProviderDetails.ErrorCode) {
        [void]$sb.AppendLine("Error Code: $($ProviderDetails.ErrorCode)")
    }

    # Add issues
    if ($ProviderDetails.Issues.Count -gt 0) {
        [void]$sb.AppendLine("Issues:")
        foreach ($issue in $ProviderDetails.Issues) {
            [void]$sb.AppendLine("  - $issue")
        }
    }

    # Add remediation steps
    if ($ProviderDetails.Remediation -and $ProviderDetails.Remediation.Count -gt 0) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("Remediation:")
        foreach ($step in $ProviderDetails.Remediation) {
            [void]$sb.AppendLine("  $step")
        }
    }

    return $sb.ToString().TrimEnd()
}

<#
.SYNOPSIS
    Formats error message when no hypervisor is available (Auto mode)

.DESCRIPTION
    Internal helper function that creates a detailed error message with
    ErrorCode and remediation steps for both Hyper-V and VMware when
    neither is available.
#>
function Format-ProviderUnavailableError {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$HypervDetails,

        [Parameter(Mandatory = $true)]
        [hashtable]$VmwareDetails
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("No supported hypervisor available.")
    [void]$sb.AppendLine()

    # Hyper-V section
    $hypervErrorCode = if ($HypervDetails.ErrorCode) { " ($($HypervDetails.ErrorCode))" } else { "" }
    [void]$sb.AppendLine("Hyper-V${hypervErrorCode}:")
    if ($HypervDetails.Issues.Count -gt 0) {
        foreach ($issue in $HypervDetails.Issues) {
            [void]$sb.AppendLine("  - $issue")
        }
    }
    if ($HypervDetails.Remediation -and $HypervDetails.Remediation.Count -gt 0) {
        [void]$sb.AppendLine("  Remediation:")
        foreach ($step in $HypervDetails.Remediation) {
            [void]$sb.AppendLine("    $step")
        }
    }

    [void]$sb.AppendLine()

    # VMware section
    $vmwareErrorCode = if ($VmwareDetails.ErrorCode) { " ($($VmwareDetails.ErrorCode))" } else { "" }
    [void]$sb.AppendLine("VMware${vmwareErrorCode}:")
    if ($VmwareDetails.Issues.Count -gt 0) {
        foreach ($issue in $VmwareDetails.Issues) {
            [void]$sb.AppendLine("  - $issue")
        }
    }
    if ($VmwareDetails.Remediation -and $VmwareDetails.Remediation.Count -gt 0) {
        [void]$sb.AppendLine("  Remediation:")
        foreach ($step in $VmwareDetails.Remediation) {
            [void]$sb.AppendLine("    $step")
        }
    }

    return $sb.ToString().TrimEnd()
}
