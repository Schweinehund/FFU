<#
.SYNOPSIS
    Validates provider switching scenarios to prevent configuration corruption and orphaned VMs.

.DESCRIPTION
    When switching between hypervisor providers (Hyper-V and VMware), this function validates:
    - Orphaned VMs from the current provider (running VMs are blockers, stopped VMs are warnings)
    - Configuration compatibility (disk formats, TPM settings)
    - Target provider availability

    This prevents issues where partial configurations or running VMs from the previous
    provider can cause problems during a switch.

.PARAMETER FromProvider
    The current/previous provider type: 'HyperV' or 'VMware'

.PARAMETER ToProvider
    The target provider to switch to: 'HyperV' or 'VMware'

.PARAMETER Config
    Optional VMConfiguration object to validate for compatibility with ToProvider

.PARAMETER VMNamePattern
    Pattern to match VM names when checking for orphaned VMs. Default is '_FFU*' which
    matches FFU build VMs.

.EXAMPLE
    $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware'
    if ($result.CanSwitch) {
        $provider = Get-HypervisorProvider -Type 'VMware'
    }

.EXAMPLE
    # Check with configuration validation
    $config = New-VMConfiguration -Name '_FFU-Build' -DiskFormat 'VHDX' ...
    $result = Test-ProviderSwitch -FromProvider 'HyperV' -ToProvider 'VMware' -Config $config
    if (-not $result.CanSwitch) {
        Write-Host "Cannot switch: $($result.Blockers -join ', ')"
    }

.OUTPUTS
    hashtable with keys:
    - CanSwitch: boolean indicating if switch is safe
    - Warnings: array of warning messages (non-blocking)
    - Blockers: array of blocking issues (prevent switch)
    - OrphanedVMs: array of VM names/paths found from FromProvider
    - IncompatibleConfig: hashtable with IsIncompatible and Reason if config incompatible
    - RecommendedActions: array of suggested actions to resolve issues

.NOTES
    Module: FFU.Hypervisor
    Version: 1.3.7
    REL-HYP-03: Provider switch validation
#>
function Test-ProviderSwitch {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HyperV', 'VMware')]
        [string]$FromProvider,

        [Parameter(Mandatory = $true)]
        [ValidateSet('HyperV', 'VMware')]
        [string]$ToProvider,

        [Parameter(Mandatory = $false)]
        [object]$Config,

        [Parameter(Mandatory = $false)]
        [string]$VMNamePattern = '_FFU*'
    )

    process {
        $result = @{
            CanSwitch = $true
            Warnings = @()
            Blockers = @()
            OrphanedVMs = @()
            IncompatibleConfig = @{
                IsIncompatible = $false
                Reason = $null
            }
            RecommendedActions = @()
        }

        WriteLog "=== Provider Switch Validation ==="
        WriteLog "  From: $FromProvider"
        WriteLog "  To: $ToProvider"
        WriteLog "  VM Pattern: $VMNamePattern"

        # Same provider switch is a no-op
        if ($FromProvider -eq $ToProvider) {
            WriteLog "  Same provider - no switch needed"
            return $result
        }

        #region Orphan Detection

        WriteLog "Checking for orphaned VMs from $FromProvider..."

        if ($FromProvider -eq 'HyperV') {
            # Check for Hyper-V VMs matching pattern
            $orphanedVMs = Get-OrphanedHyperVVMs -VMNamePattern $VMNamePattern
        }
        else {
            # Check for VMware VMX files matching pattern
            $orphanedVMs = Get-OrphanedVMwareVMs -VMNamePattern $VMNamePattern
        }

        if ($orphanedVMs.Count -gt 0) {
            foreach ($vm in $orphanedVMs) {
                $result.OrphanedVMs += $vm.Name

                if ($vm.State -eq 'Running') {
                    $result.Blockers += "Running VM found: '$($vm.Name)' ($FromProvider) - must be stopped before switching"
                    $result.RecommendedActions += "Stop VM '$($vm.Name)' using: Stop-HypervisorVM or Stop-VM (Hyper-V) / vmrun stop (VMware)"
                }
                else {
                    $result.Warnings += "Stopped VM found: '$($vm.Name)' ($FromProvider) - consider removing before switching"
                    $result.RecommendedActions += "Consider removing VM '$($vm.Name)' to avoid confusion after switch"
                }
            }
            WriteLog "  Found $($orphanedVMs.Count) orphaned VM(s): $($result.OrphanedVMs -join ', ')"
        }
        else {
            WriteLog "  No orphaned VMs found"
        }

        #endregion

        #region Configuration Compatibility

        if ($Config) {
            WriteLog "Validating configuration compatibility..."

            # Get disk format from config
            $diskFormat = $null
            if ($Config.DiskFormat) {
                $diskFormat = $Config.DiskFormat
            }
            elseif ($Config.VirtualDiskPath) {
                # Infer format from file extension
                $ext = [System.IO.Path]::GetExtension($Config.VirtualDiskPath)
                switch ($ext.ToLower()) {
                    '.vhdx' { $diskFormat = 'VHDX' }
                    '.vhd' { $diskFormat = 'VHD' }
                    '.vmdk' { $diskFormat = 'VMDK' }
                }
            }

            WriteLog "  Disk format: $diskFormat"

            # Check disk format compatibility
            if ($diskFormat) {
                if ($diskFormat -eq 'VHDX' -and $ToProvider -eq 'VMware') {
                    $result.Blockers += "Disk format 'VHDX' is not supported by VMware - only VHD and VMDK are supported"
                    $result.IncompatibleConfig = @{
                        IsIncompatible = $true
                        Reason = "VHDX format incompatible with VMware"
                    }
                    $result.RecommendedActions += "Convert VHDX to VHD or create new VHD disk for VMware"
                    WriteLog "  BLOCKER: VHDX not supported by VMware"
                }
                elseif ($diskFormat -eq 'VMDK' -and $ToProvider -eq 'HyperV') {
                    $result.Blockers += "Disk format 'VMDK' is not supported by Hyper-V - only VHD and VHDX are supported"
                    $result.IncompatibleConfig = @{
                        IsIncompatible = $true
                        Reason = "VMDK format incompatible with Hyper-V"
                    }
                    $result.RecommendedActions += "Convert VMDK to VHD/VHDX or create new disk for Hyper-V"
                    WriteLog "  BLOCKER: VMDK not supported by Hyper-V"
                }
                else {
                    WriteLog "  Disk format '$diskFormat' is compatible with $ToProvider"
                }
            }

            # Check TPM compatibility
            $enableTPM = $false
            if ($Config.EnableTPM -eq $true) {
                $enableTPM = $true
            }

            if ($enableTPM -and $ToProvider -eq 'VMware') {
                $result.Warnings += "TPM is enabled but VMware vTPM requires VM encryption which breaks vmrun automation"
                $result.RecommendedActions += "TPM will be automatically disabled for VMware VMs. TPM features work on target hardware after FFU deployment."
                WriteLog "  WARNING: TPM enabled but VMware vTPM requires encryption"
            }

            # Check if disk file exists
            if ($Config.VirtualDiskPath -and (Test-Path -Path $Config.VirtualDiskPath)) {
                WriteLog "  Disk file exists: $($Config.VirtualDiskPath)"
            }
            elseif ($Config.VirtualDiskPath) {
                WriteLog "  Disk file not found (may be created during build): $($Config.VirtualDiskPath)"
            }
        }
        else {
            WriteLog "  No configuration provided - skipping config validation"
        }

        #endregion

        #region Provider Availability

        WriteLog "Checking $ToProvider availability..."

        try {
            $toProviderInstance = $null
            if ($ToProvider -eq 'HyperV') {
                $toProviderInstance = [HyperVProvider]::new()
            }
            else {
                $toProviderInstance = [VMwareProvider]::new()
            }

            $availabilityDetails = $toProviderInstance.GetAvailabilityDetails()

            if (-not $availabilityDetails.IsAvailable) {
                $errorCode = $availabilityDetails.ErrorCode
                $issues = $availabilityDetails.Issues -join '; '
                $result.Blockers += "Target provider '$ToProvider' is not available ($errorCode): $issues"

                # Include remediation from provider
                if ($availabilityDetails.Remediation -and $availabilityDetails.Remediation.Count -gt 0) {
                    foreach ($step in $availabilityDetails.Remediation) {
                        $result.RecommendedActions += $step
                    }
                }
                WriteLog "  BLOCKER: $ToProvider not available - $issues"
            }
            else {
                WriteLog "  $ToProvider is available"
            }
        }
        catch {
            $result.Blockers += "Failed to check $ToProvider availability: $($_.Exception.Message)"
            WriteLog "  BLOCKER: Error checking availability - $($_.Exception.Message)"
        }

        #endregion

        # Determine final result
        $result.CanSwitch = ($result.Blockers.Count -eq 0)

        WriteLog "=== Validation Complete ==="
        WriteLog "  Can Switch: $($result.CanSwitch)"
        WriteLog "  Blockers: $($result.Blockers.Count)"
        WriteLog "  Warnings: $($result.Warnings.Count)"
        WriteLog "  Orphaned VMs: $($result.OrphanedVMs.Count)"

        return $result
    }
}

<#
.SYNOPSIS
    Internal helper to find orphaned Hyper-V VMs matching a pattern.
#>
function Get-OrphanedHyperVVMs {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMNamePattern
    )

    $orphanedVMs = @()

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -Name Hyper-V -ListAvailable -ErrorAction SilentlyContinue
        if (-not $hyperVModule) {
            WriteLog "  Hyper-V module not available - cannot check for orphaned VMs"
            return $orphanedVMs
        }

        # Get VMs matching pattern
        $vms = Get-VM -Name $VMNamePattern -ErrorAction SilentlyContinue

        foreach ($vm in $vms) {
            $vmState = 'Stopped'
            if ($vm.State -eq 'Running') {
                $vmState = 'Running'
            }

            $orphanedVMs += @{
                Name = $vm.Name
                State = $vmState
                Path = $vm.Path
                HypervisorType = 'HyperV'
            }
        }
    }
    catch {
        WriteLog "  Error checking Hyper-V VMs: $($_.Exception.Message)"
    }

    return $orphanedVMs
}

<#
.SYNOPSIS
    Internal helper to find orphaned VMware VMs matching a pattern.
#>
function Get-OrphanedVMwareVMs {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMNamePattern
    )

    $orphanedVMs = @()

    # Convert wildcard pattern to regex for matching
    $regexPattern = '^' + ($VMNamePattern -replace '\*', '.*' -replace '\?', '.') + '$'

    try {
        # Search common VMware VM locations
        $searchPaths = @()

        # VMware default VM directory from preferences
        $prefsPath = Join-Path $env:APPDATA 'VMware\preferences.ini'
        if (Test-Path $prefsPath) {
            $prefs = Get-Content $prefsPath -ErrorAction SilentlyContinue
            $defaultVMPath = $prefs | Where-Object { $_ -match 'prefvmx\.defaultVMPath\s*=\s*"([^"]+)"' } |
                ForEach-Object { $Matches[1] }
            if ($defaultVMPath -and (Test-Path $defaultVMPath)) {
                $searchPaths += $defaultVMPath
            }
        }

        # Common default locations
        $commonPaths = @(
            (Join-Path $env:USERPROFILE 'Documents\Virtual Machines'),
            (Join-Path $env:USERPROFILE 'Virtual Machines'),
            'C:\VMs',
            'D:\VMs'
        )
        $searchPaths += $commonPaths | Where-Object { Test-Path $_ }

        # Get running VMs from vmrun list
        $runningVMXPaths = @()
        $vmrunPath = Get-VmrunPath
        if ($vmrunPath) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $vmrunPath
            $psi.Arguments = "-T ws list"
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.CreateNoWindow = $true

            $process = [System.Diagnostics.Process]::Start($psi)
            $output = $process.StandardOutput.ReadToEnd()
            $process.WaitForExit()

            $lines = $output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^Total running VMs:' }
            $runningVMXPaths = $lines
        }

        # Search for VMX files
        foreach ($path in ($searchPaths | Select-Object -Unique)) {
            $vmxFiles = Get-ChildItem -Path $path -Filter '*.vmx' -Recurse -Depth 2 -ErrorAction SilentlyContinue

            foreach ($vmxFile in $vmxFiles) {
                $vmName = $vmxFile.BaseName

                # Check if name matches pattern
                if ($vmName -match $regexPattern) {
                    $vmState = 'Stopped'

                    # Check if running
                    foreach ($runningPath in $runningVMXPaths) {
                        if ($runningPath -eq $vmxFile.FullName) {
                            $vmState = 'Running'
                            break
                        }
                    }

                    $orphanedVMs += @{
                        Name = $vmName
                        State = $vmState
                        Path = $vmxFile.FullName
                        HypervisorType = 'VMware'
                    }
                }
            }
        }
    }
    catch {
        WriteLog "  Error checking VMware VMs: $($_.Exception.Message)"
    }

    return $orphanedVMs
}

<#
.SYNOPSIS
    Returns the previously used hypervisor provider type.

.DESCRIPTION
    Returns the type name of the last provider returned by Get-HypervisorProvider.
    Useful for checking if a provider switch is about to occur.

.EXAMPLE
    $previous = Get-PreviousHypervisorType
    if ($previous -and $previous -ne 'VMware') {
        $result = Test-ProviderSwitch -FromProvider $previous -ToProvider 'VMware'
    }

.OUTPUTS
    String or $null if no previous provider has been used.

.NOTES
    Module: FFU.Hypervisor
    Version: 1.3.7
    REL-HYP-03: Provider switch validation
#>
function Get-PreviousHypervisorType {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:PreviousProviderType
}
