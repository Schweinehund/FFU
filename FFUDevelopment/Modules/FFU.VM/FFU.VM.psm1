<#
.SYNOPSIS
    FFU Builder Hyper-V Virtual Machine Management Module

.DESCRIPTION
    Hyper-V virtual machine lifecycle management for FFU Builder.
    Provides VM creation, configuration, and cleanup operations for FFU build VMs.
    Handles VM networking, VHDX attachment, and environment validation.

.NOTES
    Module: FFU.VM
    Version: 1.0.0
    Dependencies: FFU.Core (for WriteLog function and common variables)
    Requires: Administrator privileges and Hyper-V feature enabled
#>

#Requires -Version 7.0
#Requires -RunAsAdministrator

#region Cross-Version Local User Management Helper Functions
# These functions use .NET DirectoryServices APIs to work in both PowerShell 5.1 and 7+
# Replaces Get-LocalUser, New-LocalUser, Remove-LocalUser cmdlets which have compatibility issues in PowerShell 7

function Get-LocalUserAccount {
    <#
    .SYNOPSIS
    Gets a local user account using .NET DirectoryServices API

    .DESCRIPTION
    Cross-version compatible replacement for Get-LocalUser cmdlet.
    Works in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).

    .PARAMETER Username
    Name of the local user account to retrieve

    .EXAMPLE
    $user = Get-LocalUserAccount -Username "ffu_user"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username
    )

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        $context.Dispose()

        if ($user) {
            # Return user object
            $user
            return
        }

        $null
    }
    catch {
        $null
    }
}

function New-LocalUserAccount {
    <#
    .SYNOPSIS
    Creates a local user account using .NET DirectoryServices API

    .DESCRIPTION
    Cross-version compatible replacement for New-LocalUser cmdlet.
    Works in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).
    Avoids TelemetryAPI errors in PowerShell 7.

    .PARAMETER Username
    Name of the local user account to create

    .PARAMETER Password
    SecureString password for the user account

    .PARAMETER FullName
    Full name/display name for the user

    .PARAMETER Description
    Description of the user account

    .EXAMPLE
    $password = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
    New-LocalUserAccount -Username "ffu_user" -Password $password -FullName "FFU User" -Description "FFU Capture User"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [SecureString]$Password,

        [Parameter(Mandatory = $false)]
        [string]$FullName = "",

        [Parameter(Mandatory = $false)]
        [string]$Description = ""
    )

    try {
        # SECURITY: SecureString to plaintext conversion with BSTR cleanup
        # Pattern: Convert -> Use in finally block scope -> ZeroFreeBSTR + null variable
        # The PrincipalContext.SetPassword() API requires plaintext string
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

        try {
            # Create user via DirectoryServices
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement

            $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
                [System.DirectoryServices.AccountManagement.ContextType]::Machine
            )

            $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::new($context)
            $user.Name = $Username
            $user.SetPassword($plainPassword)
            $user.DisplayName = $FullName
            $user.Description = $Description
            $user.UserCannotChangePassword = $false
            $user.PasswordNeverExpires = $true
            $user.Save()

            $context.Dispose()
            $user.Dispose()

            $true
        }
        finally {
            # Always clear password from memory
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            if ($plainPassword) {
                $plainPassword = $null
            }
        }
    }
    catch {
        throw "Failed to create local user account: $($_.Exception.Message)"
    }
}

function Remove-LocalUserAccount {
    <#
    .SYNOPSIS
    Removes a local user account using .NET DirectoryServices API

    .DESCRIPTION
    Cross-version compatible replacement for Remove-LocalUser cmdlet.
    Works in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).

    .PARAMETER Username
    Name of the local user account to remove

    .EXAMPLE
    Remove-LocalUserAccount -Username "ffu_user"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username
    )

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        if ($user) {
            $user.Delete()
            $user.Dispose()
        }

        $context.Dispose()

        $true
    }
    catch {
        throw "Failed to remove local user account: $($_.Exception.Message)"
    }
}

function Set-LocalUserPassword {
    <#
    .SYNOPSIS
    Sets the password for an existing local user account using .NET DirectoryServices API

    .DESCRIPTION
    Cross-version compatible function to reset a local user's password.
    Works in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).
    This function is used to ensure the ffu_user password matches what's written
    to CaptureFFU.ps1, preventing "Password is incorrect" errors (Error 86).

    .PARAMETER Username
    Name of the local user account to update

    .PARAMETER Password
    New password as SecureString

    .EXAMPLE
    $password = ConvertTo-SecureString "NewP@ssw0rd" -AsPlainText -Force
    Set-LocalUserPassword -Username "ffu_user" -Password $password
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [SecureString]$Password
    )

    # SECURITY: SecureString to plaintext conversion with BSTR cleanup
    # Pattern: Convert -> Use -> ZeroFreeBSTR + null variable (in finally block)
    # The PrincipalContext.SetPassword() API requires plaintext string
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        if (-not $user) {
            throw "User '$Username' not found"
        }

        # Set the new password
        $user.SetPassword($plainPassword)
        $user.Save()

        $user.Dispose()
        $context.Dispose()

        $true
    }
    catch {
        throw "Failed to set password for user '$Username': $($_.Exception.Message)"
    }
    finally {
        # Secure cleanup of sensitive data
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        if ($plainPassword) {
            $plainPassword = $null
        }
    }
}

function Set-LocalUserAccountExpiry {
    <#
    .SYNOPSIS
    Sets the account expiration date for a local user account

    .DESCRIPTION
    Cross-version compatible function to set account expiry using .NET DirectoryServices API.
    This is a security measure to ensure temporary accounts are automatically disabled
    even if cleanup fails. Works in both PowerShell 5.1 and 7+.

    .PARAMETER Username
    Name of the local user account to update

    .PARAMETER ExpiryDate
    DateTime when the account should expire. If not specified, defaults to 4 hours from now.

    .PARAMETER ExpiryHours
    Number of hours from now when the account should expire. Ignored if ExpiryDate is specified.
    Default is 4 hours.

    .EXAMPLE
    Set-LocalUserAccountExpiry -Username "ffu_user" -ExpiryHours 2

    .EXAMPLE
    Set-LocalUserAccountExpiry -Username "ffu_user" -ExpiryDate (Get-Date).AddHours(6)

    .NOTES
    SECURITY: This provides a failsafe to ensure temporary FFU capture accounts
    are automatically disabled even if the script fails to clean up properly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $false)]
        [DateTime]$ExpiryDate,

        [Parameter(Mandatory = $false)]
        [int]$ExpiryHours = 4
    )

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        if (-not $user) {
            throw "User '$Username' not found"
        }

        # Calculate expiry date
        if (-not $ExpiryDate) {
            $ExpiryDate = (Get-Date).AddHours($ExpiryHours)
        }

        # Set account expiration
        $user.AccountExpirationDate = $ExpiryDate
        $user.Save()

        $user.Dispose()
        $context.Dispose()

        $ExpiryDate
    }
    catch {
        throw "Failed to set account expiry for user '$Username': $($_.Exception.Message)"
    }
}

#endregion Cross-Version Local User Management Helper Functions

#region VM Creation Diagnostics

function Get-VMCreationDiagnostics {
    <#
    .SYNOPSIS
    Analyzes VM creation failures and returns actionable guidance.

    .DESCRIPTION
    Pattern-matches common VM creation errors and provides classified error types,
    remediation guidance, and information about resources that may need cleanup.
    This function supports the REL-VM-01 reliability requirement.

    .PARAMETER ErrorMessage
    The exception message from the failed operation.

    .PARAMETER FailedStep
    Which step failed during VM creation.
    Valid values: CreateVM, ConfigureProcessor, MountISO, ConfigureTPM, StartVM, ConfigureBoot

    .PARAMETER VMName
    Name of the VM being created.

    .PARAMETER VMPath
    Path where VM was being created (optional).

    .OUTPUTS
    PSCustomObject with properties:
    - ErrorType: Classified error type (AlreadyExists, InsufficientResources, PathNotFound, AccessDenied, HypervisorNotAvailable, TPMConfiguration, Unknown)
    - FailedStep: Which step failed
    - OriginalError: The original error message
    - Remediation: Actionable guidance string
    - IsCritical: Boolean - false for TPM errors, true for others
    - ResourcesCreated: Array of resources that may need cleanup

    .EXAMPLE
    $diagnostics = Get-VMCreationDiagnostics -ErrorMessage "A virtual machine with the same name already exists" `
                                              -FailedStep "CreateVM" -VMName "FFU-Build-VM"

    .NOTES
    REL-VM-01: Provides detailed failure analysis for VM creation errors
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $true)]
        [ValidateSet('CreateVM', 'ConfigureProcessor', 'MountISO', 'ConfigureTPM', 'StartVM', 'ConfigureBoot')]
        [string]$FailedStep,

        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $false)]
        [string]$VMPath
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        ErrorType        = 'Unknown'
        FailedStep       = $FailedStep
        OriginalError    = $ErrorMessage
        Remediation      = ''
        IsCritical       = $true
        ResourcesCreated = @()
    }

    # Determine which resources may have been created based on failed step
    switch ($FailedStep) {
        'StartVM' {
            $result.ResourcesCreated = @('VM', 'HGSGuardian', 'TPM')
        }
        'ConfigureTPM' {
            $result.ResourcesCreated = @('VM')
        }
        'ConfigureBoot' {
            $result.ResourcesCreated = @('VM')
        }
        'MountISO' {
            $result.ResourcesCreated = @('VM')
        }
        'ConfigureProcessor' {
            $result.ResourcesCreated = @('VM')
        }
        'CreateVM' {
            $result.ResourcesCreated = @()
        }
    }

    # Pattern match common errors and classify
    $lowerError = $ErrorMessage.ToLower()

    # Already exists error
    if ($lowerError -match 'already exists' -or $lowerError -match 'name is already in use') {
        $result.ErrorType = 'AlreadyExists'
        $result.Remediation = "A VM with this name already exists. Remove it with: Remove-VM -Name '$VMName' -Force"
        $result.IsCritical = $true
    }
    # Insufficient memory/resources
    elseif ($lowerError -match 'insufficient memory' -or $lowerError -match 'not enough memory' -or
            $lowerError -match 'insufficient.*resource' -or $lowerError -match 'out of memory') {
        $result.ErrorType = 'InsufficientResources'
        $result.Remediation = "Not enough memory available. Close applications or reduce VM memory allocation. Current system memory usage may be too high."
        $result.IsCritical = $true
    }
    # Path not found
    elseif ($lowerError -match 'cannot find path' -or $lowerError -match 'path.*does not exist' -or
            $lowerError -match 'directory not found' -or $lowerError -match 'could not find.*path') {
        $result.ErrorType = 'PathNotFound'
        $pathInfo = if ($VMPath) { " at '$VMPath'" } else { '' }
        $result.Remediation = "Path does not exist$pathInfo. Create the directory or verify the path exists before creating the VM."
        $result.IsCritical = $true
    }
    # Access denied
    elseif ($lowerError -match 'access denied' -or $lowerError -match 'access is denied' -or
            $lowerError -match 'unauthorized' -or $lowerError -match 'permission') {
        $result.ErrorType = 'AccessDenied'
        $result.Remediation = "Access denied. Run PowerShell as Administrator or check folder permissions for the VM path."
        $result.IsCritical = $true
    }
    # Hyper-V not enabled/available
    elseif ($lowerError -match 'hyper-v.*not.*enabled' -or $lowerError -match 'hypervisor.*not.*running' -or
            $lowerError -match 'virtualization.*not.*enabled' -or $lowerError -match 'vmms.*not.*running' -or
            $lowerError -match 'hyper-v.*not.*available') {
        $result.ErrorType = 'HypervisorNotAvailable'
        $result.Remediation = "Hyper-V is not available. Enable with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All`nThen restart the computer."
        $result.IsCritical = $true
    }
    # TPM/HGS/Guardian errors (non-critical)
    elseif ($lowerError -match 'hgs' -or $lowerError -match 'guardian' -or $lowerError -match 'key protector' -or
            $lowerError -match 'tpm' -or $lowerError -match 'shielded' -or $lowerError -match 'attestation') {
        $result.ErrorType = 'TPMConfiguration'
        $result.Remediation = "TPM/HGS configuration failed. This is non-critical - the VM can work without TPM. Some Windows features like BitLocker may be limited."
        $result.IsCritical = $false
    }
    # Disk/VHDX errors
    elseif ($lowerError -match 'vhdx' -or $lowerError -match 'virtual hard disk' -or $lowerError -match 'disk.*in use') {
        $result.ErrorType = 'DiskError'
        $result.Remediation = "Virtual disk error. The VHDX may be in use by another process or corrupted. Check if another VM is using this disk."
        $result.IsCritical = $true
    }
    # Unknown error
    else {
        $result.ErrorType = 'Unknown'
        $result.Remediation = "Unknown error occurred at step '$FailedStep'. Original error: $ErrorMessage"
        $result.IsCritical = $true
    }

    # Log diagnostics
    WriteLog "VM Creation Diagnostics:"
    WriteLog "  Error Type: $($result.ErrorType)"
    WriteLog "  Failed Step: $($result.FailedStep)"
    WriteLog "  Is Critical: $($result.IsCritical)"
    WriteLog "  Remediation: $($result.Remediation)"
    if ($result.ResourcesCreated.Count -gt 0) {
        WriteLog "  Resources to cleanup: $($result.ResourcesCreated -join ', ')"
    }

    return $result
}

#endregion VM Creation Diagnostics

function New-FFUVM {
    <#
    .SYNOPSIS
    Creates a new Generation 2 Hyper-V virtual machine for FFU build process

    .DESCRIPTION
    Creates and configures a new Hyper-V VM with TPM, mounts the Apps ISO,
    configures boot settings, and starts the VM with vmconnect.

    .PARAMETER VMName
    Name of the virtual machine to create

    .PARAMETER VMPath
    Path where the VM configuration files will be stored

    .PARAMETER Memory
    Memory allocation for the VM in bytes (e.g., 8GB = 8589934592)

    .PARAMETER VHDXPath
    Path to the VHDX file to attach to the VM

    .PARAMETER Processors
    Number of virtual processors to assign to the VM

    .PARAMETER AppsISO
    Path to the Apps ISO file to mount to the VM

    .EXAMPLE
    New-FFUVM -VMName "_FFU-Build-Win11" -VMPath "C:\FFU\VM" -Memory 8GB `
              -VHDXPath "C:\FFU\VM\disk.vhdx" -Processors 4 -AppsISO "C:\FFU\Apps\Apps.iso"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [uint64]$Memory,

        [Parameter(Mandatory = $true)]
        [string]$VHDXPath,

        [Parameter(Mandatory = $true)]
        [int]$Processors,

        [Parameter(Mandatory = $true)]
        [string]$AppsISO
    )

    $VM = $null
    $vmCreated = $false
    $guardianCreated = $false
    $vmCleanupId = $null
    $guardianCleanupId = $null
    $currentStep = 'CreateVM'

    try {
        # Create new Gen2 VM
        WriteLog "Creating VM: $VMName"
        try {
            $VM = New-VM -Name $VMName -Path $VMPath -MemoryStartupBytes $Memory -VHDPath $VHDXPath -Generation 2 -ErrorAction Stop
            $vmCreated = $true
            WriteLog "VM created successfully"

            # Register VM cleanup immediately after creation (REL-VM-01)
            $vmCleanupId = Register-VMCleanup -VMName $VMName
            WriteLog "Registered VM cleanup action: $vmCleanupId"
        }
        catch {
            throw "Failed to create VM '$VMName': $($_.Exception.Message)"
        }

        # Configure VM processor
        $currentStep = 'ConfigureProcessor'
        try {
            Set-VMProcessor -VMName $VMName -Count $Processors -ErrorAction Stop
            WriteLog "VM processor configured: $Processors cores"
        }
        catch {
            throw "Failed to configure VM processor: $($_.Exception.Message)"
        }

        # Mount AppsISO
        $currentStep = 'MountISO'
        try {
            Add-VMDvdDrive -VMName $VMName -Path $AppsISO -ErrorAction Stop
            WriteLog "Apps ISO mounted: $AppsISO"
        }
        catch {
            throw "Failed to mount Apps ISO '$AppsISO': $($_.Exception.Message)"
        }

        # Set Hard Drive as boot device
        $currentStep = 'ConfigureBoot'
        try {
            $VMHardDiskDrive = Get-VMHarddiskdrive -VMName $VMName -ErrorAction Stop
            Set-VMFirmware -VMName $VMName -FirstBootDevice $VMHardDiskDrive -ErrorAction Stop
            Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -StaticMemory -ErrorAction Stop
            WriteLog "VM boot configuration set"
        }
        catch {
            throw "Failed to configure VM boot settings: $($_.Exception.Message)"
        }

        # Configure TPM
        $currentStep = 'ConfigureTPM'
        try {
            New-HgsGuardian -Name $VMName -GenerateCertificates -ErrorAction Stop
            $guardianCreated = $true

            # Register HGS Guardian cleanup immediately after creation (REL-VM-01)
            $localVMName = $VMName  # Capture for closure
            $guardianCleanupId = Register-CleanupAction -Name "Remove HGS Guardian: $VMName" -ResourceType 'HGS' -ResourceId $VMName -Action {
                Remove-HgsGuardian -Name $using:localVMName -ErrorAction SilentlyContinue
                Get-ChildItem 'Cert:\LocalMachine\Shielded VM Local Certificates\' -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Subject -like "*$using:localVMName*" } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }.GetNewClosure()
            WriteLog "Registered HGS Guardian cleanup action: $guardianCleanupId"

            $owner = Get-HgsGuardian -Name $VMName -ErrorAction Stop
            $kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot -ErrorAction Stop
            Set-VMKeyProtector -VMName $VMName -KeyProtector $kp.RawData -ErrorAction Stop
            Enable-VMTPM -VMName $VMName -ErrorAction Stop
            WriteLog "TPM configured successfully"
        }
        catch {
            # TPM configuration is non-critical - log warning but continue
            WriteLog "WARNING: TPM configuration failed (non-critical): $($_.Exception.Message)"
            WriteLog "VM will continue without TPM. Some Windows features may be limited."
        }

        # Connect to VM
        WriteLog "Starting vmconnect localhost $VMName"
        & vmconnect localhost "$VMName"

        # Start VM
        $currentStep = 'StartVM'
        try {
            Start-VM -Name $VMName -ErrorAction Stop
            WriteLog "VM started successfully"
        }
        catch {
            throw "Failed to start VM '$VMName': $($_.Exception.Message)"
        }

        # VM creation successful - unregister cleanup handlers (REL-VM-01)
        WriteLog "VM creation successful - unregistering cleanup handlers"
        if ($vmCleanupId) {
            Unregister-CleanupAction -CleanupId $vmCleanupId -ErrorAction SilentlyContinue
        }
        if ($guardianCleanupId) {
            Unregister-CleanupAction -CleanupId $guardianCleanupId -ErrorAction SilentlyContinue
        }
        WriteLog "Cleanup handlers unregistered - VM is now managed by caller"

        $VM
    }
    catch {
        WriteLog "ERROR in New-FFUVM: $($_.Exception.Message)"

        # Get classified diagnostics for the failure (REL-VM-01)
        $diagnostics = Get-VMCreationDiagnostics -ErrorMessage $_.Exception.Message `
                                                  -FailedStep $currentStep `
                                                  -VMName $VMName `
                                                  -VMPath $VMPath
        WriteLog "ERROR DIAGNOSIS:"
        WriteLog "  Type: $($diagnostics.ErrorType)"
        WriteLog "  Critical: $($diagnostics.IsCritical)"
        WriteLog "  Remediation: $($diagnostics.Remediation)"

        # Cleanup on failure (existing code provides fallback for when cleanup registration wasn't reached)
        if ($vmCreated) {
            WriteLog "Attempting cleanup of failed VM creation..."
            WriteLog "Resources that may need cleanup: $($diagnostics.ResourcesCreated -join ', ')"
            try {
                Stop-VM -Name $VMName -Force -TurnOff -ErrorAction SilentlyContinue
                Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
                WriteLog "Failed VM removed"
            }
            catch {
                WriteLog "WARNING: Failed to cleanup VM: $($_.Exception.Message)"
            }
        }

        if ($guardianCreated) {
            try {
                Remove-HgsGuardian -Name $VMName -ErrorAction SilentlyContinue
                WriteLog "HGS Guardian removed"

                # Also clean up certificates
                Get-ChildItem 'Cert:\LocalMachine\Shielded VM Local Certificates\' -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Subject -like "*$VMName*" } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                WriteLog "HGS certificates cleaned up"
            }
            catch {
                WriteLog "WARNING: Failed to cleanup HGS Guardian: $($_.Exception.Message)"
            }
        }

        throw
    }
}

function Remove-FFUVM {
    <#
    .SYNOPSIS
    Removes FFU build VM and associated resources

    .DESCRIPTION
    Removes the Hyper-V VM, HGS Guardian, certificates, VHDX files, and cleans up
    orphaned mounted images. Can be called with or without VMName for different
    cleanup scenarios.

    .PARAMETER VMName
    Optional name of the VM to remove. If not specified, only VHDX cleanup is performed.

    .PARAMETER VMPath
    Path to the VM configuration directory to remove

    .PARAMETER InstallApps
    Boolean indicating if apps were installed (affects cleanup behavior)

    .PARAMETER VhdxDisk
    VHDX disk object for cleanup validation

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for mount folder cleanup

    .PARAMETER Username
    Optional username for FFU capture user cleanup (default: ffu_user)

    .PARAMETER ShareName
    Optional share name for FFU capture share cleanup (default: FFUCaptureShare)

    .EXAMPLE
    Remove-FFUVM -VMName "_FFU-Build-Win11" -VMPath "C:\FFU\VM\_FFU-Build-Win11" `
                 -InstallApps $true -VhdxDisk $disk -FFUDevelopmentPath "C:\FFU" `
                 -Username "ffu_user" -ShareName "FFUCaptureShare"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [bool]$InstallApps,

        [Parameter(Mandatory = $false)]
        $VhdxDisk,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$Username = "ffu_user",

        [Parameter(Mandatory = $false)]
        [string]$ShareName = "FFUCaptureShare"
    )
    #Get the VM object and remove the VM, the HGSGuardian, and the certs
    If ($VMName) {
        try {
            $FFUVM = Get-VM -Name $VMName -ErrorAction Stop | Where-Object { $_.state -ne 'running' }
        }
        catch [Microsoft.HyperV.PowerShell.VirtualizationException] {
            WriteLog "WARNING: Hyper-V error retrieving VM '$VMName': $($_.Exception.Message)"
            $FFUVM = $null
        }
        catch [System.Management.Automation.ItemNotFoundException] {
            WriteLog "VM '$VMName' not found - may have already been removed"
            $FFUVM = $null
        }
        catch {
            WriteLog "WARNING: Unexpected error retrieving VM '$VMName': $($_.Exception.Message)"
            $FFUVM = $null
        }
    }
    If ($null -ne $FFUVM) {
        WriteLog 'Cleaning up VM'
        $certPath = 'Cert:\LocalMachine\Shielded VM Local Certificates\'
        $VMName = $FFUVM.Name

        # Remove the VM with error handling
        WriteLog "Removing VM: $VMName"
        try {
            Remove-VM -Name $VMName -Force -ErrorAction Stop
            WriteLog 'VM removal complete'
        }
        catch [Microsoft.HyperV.PowerShell.VirtualizationException] {
            WriteLog "WARNING: Hyper-V error removing VM '$VMName': $($_.Exception.Message)"
        }
        catch {
            WriteLog "WARNING: Failed to remove VM '$VMName': $($_.Exception.Message)"
        }

        # Remove VM path
        WriteLog "Removing $VMPath"
        if (-not [string]::IsNullOrWhiteSpace($VMPath)) {
            try {
                Remove-Item -Path $VMPath -Force -Recurse -ErrorAction Stop
                WriteLog 'VM path removal complete'
            }
            catch [System.IO.IOException] {
                WriteLog "WARNING: IO error removing VM path (files may be in use): $($_.Exception.Message)"
            }
            catch [System.UnauthorizedAccessException] {
                WriteLog "WARNING: Access denied removing VM path: $($_.Exception.Message)"
            }
            catch {
                WriteLog "WARNING: Failed to remove VM path: $($_.Exception.Message)"
            }
        }

        # Remove HGS Guardian with error handling
        WriteLog "Removing HGSGuardian for $VMName"
        try {
            Remove-HgsGuardian -Name $VMName -ErrorAction Stop -WarningAction SilentlyContinue
            WriteLog 'HGS Guardian removal complete'
        }
        catch {
            WriteLog "WARNING: Failed to remove HGS Guardian (may not exist): $($_.Exception.Message)"
        }

        # Clean up HGS Guardian certificates
        WriteLog 'Cleaning up HGS Guardian certs'
        try {
            if (Test-Path -Path $certPath) {
                $certs = Get-ChildItem -Path $certPath -Recurse -ErrorAction Stop | Where-Object { $_.Subject -like "*$VMName*" }
                foreach ($cert in $Certs) {
                    try {
                        Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop | Out-Null
                    }
                    catch {
                        WriteLog "WARNING: Failed to remove certificate $($cert.Subject): $($_.Exception.Message)"
                    }
                }
                WriteLog 'Cert removal complete'
            }
            else {
                WriteLog 'Certificate path does not exist - skipping cert cleanup'
            }
        }
        catch {
            WriteLog "WARNING: Error during certificate cleanup: $($_.Exception.Message)"
        }

        # Clean up VMware lock files if present (REL-VM-02)
        WriteLog 'Checking for VMware lock files'
        try {
            if (-not [string]::IsNullOrWhiteSpace($VMPath) -and (Test-Path -Path $VMPath)) {
                $lockDirs = Get-ChildItem -Path $VMPath -Filter '*.lck' -Directory -Recurse -ErrorAction SilentlyContinue
                foreach ($lockDir in $lockDirs) {
                    try {
                        # Only remove if no vmware-vmx process is running for this VM
                        $vmxRunning = Get-Process -Name 'vmware-vmx' -ErrorAction SilentlyContinue |
                            Where-Object { $_.Path -like "*$VMPath*" }

                        if (-not $vmxRunning) {
                            WriteLog "Removing orphaned lock directory: $($lockDir.FullName)"
                            Remove-Item $lockDir.FullName -Recurse -Force -ErrorAction Stop
                            WriteLog 'Lock directory removed'
                        }
                        else {
                            WriteLog "WARNING: Lock directory in use by running process, skipping: $($lockDir.Name)"
                        }
                    }
                    catch {
                        WriteLog "WARNING: Failed to remove lock directory: $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            WriteLog "WARNING: Error scanning for VMware lock files: $($_.Exception.Message)"
        }

        # Clean up orphaned AVHDX files (checkpoint leftovers - REL-VM-02)
        WriteLog 'Checking for orphaned checkpoint files'
        try {
            if (-not [string]::IsNullOrWhiteSpace($VMPath) -and (Test-Path -Path $VMPath)) {
                $avhdxFiles = Get-ChildItem -Path $VMPath -Filter '*.avhdx' -Recurse -ErrorAction SilentlyContinue
                foreach ($avhdx in $avhdxFiles) {
                    try {
                        # Check if this AVHDX is part of an active checkpoint
                        $isOrphaned = $true
                        if ($VMName) {
                            $snapshots = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue
                            foreach ($snap in $snapshots) {
                                $snapVHDs = Get-VMHardDiskDrive -VMSnapshot $snap -ErrorAction SilentlyContinue
                                if ($snapVHDs.Path -contains $avhdx.FullName) {
                                    $isOrphaned = $false
                                    break
                                }
                            }
                        }

                        if ($isOrphaned) {
                            WriteLog "Removing orphaned checkpoint file: $($avhdx.Name)"
                            Remove-Item $avhdx.FullName -Force -ErrorAction Stop
                            WriteLog 'Orphaned checkpoint file removed'
                        }
                    }
                    catch {
                        WriteLog "WARNING: Failed to remove orphaned checkpoint file: $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            WriteLog "WARNING: Error scanning for AVHDX files: $($_.Exception.Message)"
        }
    }

    #If just building the FFU from vhdx, remove the vhdx path
    If (-not $InstallApps -and $VhdxDisk) {
        WriteLog 'Cleaning up VHDX'
        WriteLog "Removing $VMPath"
        if (-not [string]::IsNullOrWhiteSpace($VMPath)) {
            try {
                Remove-Item -Path $VMPath -Force -Recurse -ErrorAction Stop | Out-Null
                WriteLog 'VHDX path removal complete'
            }
            catch [System.IO.IOException] {
                WriteLog "WARNING: IO error removing VHDX path (files may be in use): $($_.Exception.Message)"
            }
            catch {
                WriteLog "WARNING: Failed to remove VHDX path: $($_.Exception.Message)"
            }
        }
    }

    #Remove orphaned mounted images
    # v1.0.3: Guard DISM operations with Test-DismReady to prevent 10-minute hangs
    $dismReadyForRemove = $false
    if ($ExecutionContext.InvokeCommand.GetCommand('Test-DismReady', 'Function')) {
        $dismReadyForRemove = Test-DismReady -AttemptRepair $true
    }
    else {
        try {
            $fltmcOut = & fltmc.exe filters 2>&1
            $dismReadyForRemove = [bool]($fltmcOut -match 'WimMount')
        }
        catch { $dismReadyForRemove = $false }
    }

    if ($dismReadyForRemove) {
        try {
            $mountedImages = Get-WindowsImage -Mounted -ErrorAction Stop
            if ($mountedImages) {
                foreach ($image in $mountedImages) {
                    $mountPath = $image.Path
                    WriteLog "Dismounting image at $mountPath"
                    try {
                        Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop
                        WriteLog "Successfully dismounted image at $mountPath"
                    }
                    catch [System.Runtime.InteropServices.COMException] {
                        WriteLog "WARNING: COM error dismounting image at $mountPath (may already be dismounted): $($_.Exception.Message)"
                    }
                    catch {
                        WriteLog "WARNING: Failed to dismount image at $mountPath : $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            WriteLog "WARNING: Error retrieving mounted images: $($_.Exception.Message)"
        }
    }
    else {
        WriteLog "WARNING: WIMMount not loaded - using non-DISM fallback for mount cleanup in Remove-FFUVM"
        if ($ExecutionContext.InvokeCommand.GetCommand('Clear-OrphanedMountPointsWithoutDism', 'Function')) {
            Clear-OrphanedMountPointsWithoutDism
        }
    }

    #Remove Mount folder if it exists
    If (Test-Path -Path "$FFUDevelopmentPath\Mount") {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        try {
            Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force -ErrorAction Stop
            WriteLog 'Mount folder removed'
        }
        catch {
            WriteLog "WARNING: Failed to remove Mount folder: $($_.Exception.Message)"
        }
    }

    #Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    try {
        Invoke-Process cmd "/c mountvol /r" | Out-Null
        WriteLog 'Mountpoint cleanup complete'
    }
    catch {
        WriteLog "WARNING: Failed to remove unused mountpoints: $($_.Exception.Message)"
    }
}

function Get-FFUEnvironment {
    <#
    .SYNOPSIS
    Cleans up FFU build environment after failed or incomplete builds

    .DESCRIPTION
    Performs comprehensive environment cleanup including VMs, VHDXs, mounted images,
    stale downloads, user accounts, and temporary files. Called when dirty.txt is detected
    or when explicit cleanup is requested.

    When ResumeCheckpoint is provided, artifacts referenced by the checkpoint (VM, VHDX,
    VM folder, drivers folder, .session) are preserved so the resumed build can continue
    from where it left off. All other transient state (mounts, registry, mountpoints) is
    still cleaned.

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path

    .PARAMETER CleanupCurrentRunDownloads
    Boolean indicating whether to clean up current run downloads

    .PARAMETER VMLocation
    Path to VM storage location (defaults to FFUDevelopmentPath\VM if not provided)

    .PARAMETER UserName
    FFU user account name to remove

    .PARAMETER RemoveApps
    Boolean indicating whether to remove Apps folder

    .PARAMETER AppsPath
    Path to Apps folder

    .PARAMETER RemoveUpdates
    Boolean indicating whether to remove Updates folder

    .PARAMETER KBPath
    Path to KB updates folder

    .PARAMETER AppsISO
    Path to Apps ISO file

    .PARAMETER ResumeCheckpoint
    Optional hashtable from checkpoint resume. When provided, artifacts referenced by the
    checkpoint (VM, VHDX, VM folder, drivers folder, .session) are preserved. Structure
    expected: @{ paths = @{ VHDXPath; VMPath; DriversFolder }; configuration = @{ VMName } }

    .EXAMPLE
    Get-FFUEnvironment -FFUDevelopmentPath "C:\FFU" -CleanupCurrentRunDownloads $true `
                       -VMLocation "C:\FFU\VM" -UserName "ffu_user" -RemoveApps $false `
                       -AppsPath "C:\FFU\Apps" -RemoveUpdates $false -KBPath "C:\FFU\KB" `
                       -AppsISO "C:\FFU\Apps\Apps.iso"

    .EXAMPLE
    # Resume-aware cleanup preserving checkpoint artifacts
    Get-FFUEnvironment -FFUDevelopmentPath "C:\FFU" -CleanupCurrentRunDownloads $false `
                       -VMLocation "C:\FFU\VM" -UserName "ffu_user" -RemoveApps $false `
                       -AppsPath "C:\FFU\Apps" -RemoveUpdates $false -KBPath "C:\FFU\KB" `
                       -AppsISO "C:\FFU\Apps\Apps.iso" -ResumeCheckpoint $checkpoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [bool]$CleanupCurrentRunDownloads,

        [Parameter(Mandatory = $false)]
        [string]$VMLocation,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [bool]$RemoveApps,

        [Parameter(Mandatory = $true)]
        [string]$AppsPath,

        [Parameter(Mandatory = $true)]
        [bool]$RemoveUpdates,

        [Parameter(Mandatory = $true)]
        [string]$KBPath,

        [Parameter(Mandatory = $true)]
        [string]$AppsISO,

        [Parameter(Mandatory = $false)]
        $HypervisorProvider = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$ResumeCheckpoint = $null
    )

    # Build protected paths set from checkpoint when resuming
    $protectedVMName = $null
    $protectedPaths = @{}
    if ($null -ne $ResumeCheckpoint) {
        WriteLog "RESUME CLEANUP: Checkpoint provided - building protected artifact set"
        $cpPaths = $ResumeCheckpoint.paths
        $cpConfig = $ResumeCheckpoint.configuration

        if ($cpConfig -and $cpConfig.VMName) {
            $protectedVMName = $cpConfig.VMName
            WriteLog "RESUME CLEANUP: Protected VM name: $protectedVMName"
        }

        if ($cpPaths) {
            if ($cpPaths.VHDXPath -and (Test-Path -Path $cpPaths.VHDXPath)) {
                $protectedPaths[$cpPaths.VHDXPath] = 'VHDXFile'
                $vhdxParent = Split-Path -Parent $cpPaths.VHDXPath
                if ($vhdxParent) {
                    $protectedPaths[$vhdxParent] = 'VHDXParentFolder'
                }
                WriteLog "RESUME CLEANUP: Protected VHDX: $($cpPaths.VHDXPath)"
            }

            if ($cpPaths.VMPath -and (Test-Path -Path $cpPaths.VMPath)) {
                $protectedPaths[$cpPaths.VMPath] = 'VMFolder'
                WriteLog "RESUME CLEANUP: Protected VM folder: $($cpPaths.VMPath)"
            }

            if ($cpPaths.DriversFolder -and (Test-Path -Path $cpPaths.DriversFolder)) {
                $protectedPaths[$cpPaths.DriversFolder] = 'DriversFolder'
                WriteLog "RESUME CLEANUP: Protected drivers folder: $($cpPaths.DriversFolder)"
            }
        }

        $protectedCount = $protectedPaths.Count
        if ($protectedVMName) { $protectedCount++ }
        WriteLog "RESUME CLEANUP: Total protected artifacts: $protectedCount"
    }

    WriteLog 'Dirty.txt file detected. Last run did not complete succesfully. Will clean environment'
    try {
        Remove-InProgressItems -FFUDevelopmentPath $FFUDevelopmentPath `
                              -DriversFolder "$FFUDevelopmentPath\Drivers" `
                              -OfficePath "$FFUDevelopmentPath\Office"
    }
    catch {
        WriteLog "Remove-InProgressItems failed: $($_.Exception.Message)"
    }
    if ($CleanupCurrentRunDownloads) {
        try {
            Clear-CurrentRunDownloads -FFUDevelopmentPath $FFUDevelopmentPath `
                                      -AppsPath $AppsPath -DefenderPath "$FFUDevelopmentPath\Defender" `
                                      -MSRTPath "$FFUDevelopmentPath\MSRT" -OneDrivePath "$FFUDevelopmentPath\OneDrive" `
                                      -EdgePath "$FFUDevelopmentPath\Edge" -KBPath $KBPath `
                                      -DriversFolder "$FFUDevelopmentPath\Drivers" `
                                      -orchestrationPath "$FFUDevelopmentPath\Orchestration" `
                                      -OfficePath "$FFUDevelopmentPath\Office"
        }
        catch {
            WriteLog "Clear-CurrentRunDownloads failed: $($_.Exception.Message)"
        }
        try {
            Restore-RunJsonBackups -FFUDevelopmentPath $FFUDevelopmentPath `
                                  -DriversFolder "$FFUDevelopmentPath\Drivers" `
                                  -orchestrationPath "$FFUDevelopmentPath\Orchestration"
        }
        catch {
            WriteLog "Restore-RunJsonBackups failed: $($_.Exception.Message)"
        }
    }

    # Check for running VMs that start with '_FFU-'
    # Use hypervisor provider if available, otherwise fall back to Hyper-V cmdlets
    if ($null -ne $HypervisorProvider) {
        WriteLog "Using hypervisor provider for VM cleanup: $($HypervisorProvider.Name)"
        try {
            $vms = $HypervisorProvider.GetAllVMs()
            WriteLog "Found $($vms.Count) VMs via provider"
        }
        catch {
            WriteLog "WARNING: Failed to get VMs from provider: $($_.Exception.Message)"
            $vms = @()
        }

        foreach ($vm in $vms) {
            if ($vm.Name.StartsWith("_FFU-")) {
                # Guard: skip VMs protected by checkpoint
                if ($protectedVMName -and $vm.Name -eq $protectedVMName) {
                    WriteLog "RESUME CLEANUP: Skipping protected VM: $($vm.Name)"
                    continue
                }
                WriteLog "Found FFU VM: $($vm.Name) (State: $($vm.State))"
                # Use Test-VMStateRunning factory function since [VMState] enum isn't accessible from FFU.VM module
                if (Test-VMStateRunning -State $vm.State) {
                    try {
                        WriteLog "Stopping running VM: $($vm.Name)"
                        $HypervisorProvider.StopVM($vm, $true)  # Force stop
                        WriteLog "VM $($vm.Name) stopped successfully"
                    }
                    catch {
                        WriteLog "WARNING: Failed to stop VM '$($vm.Name)': $($_.Exception.Message)"
                    }
                }
                # Remove the VM
                $vmPath = Join-Path $FFUDevelopmentPath "VM\$($vm.Name)"
                try {
                    WriteLog "Removing VM: $($vm.Name)"
                    $HypervisorProvider.RemoveVM($vm, $true)  # Remove with disks
                    WriteLog "VM removed via provider"
                    # Clean up remaining artifacts
                    Remove-FFUBuildArtifacts -VMPath $vmPath -FFUDevelopmentPath $FFUDevelopmentPath
                }
                catch {
                    WriteLog "WARNING: Provider cleanup failed for '$($vm.Name)': $($_.Exception.Message)"
                    # Fall back to Remove-FFUVM
                    try {
                        Remove-FFUVM -VMName $vm.Name -VMPath $vmPath -InstallApps $true `
                                     -VhdxDisk $null -FFUDevelopmentPath $FFUDevelopmentPath
                    }
                    catch {
                        WriteLog "WARNING: Remove-FFUVM also failed: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
    else {
        # Fallback to Hyper-V cmdlets (original behavior)
        WriteLog "Using Hyper-V cmdlets for VM cleanup (no provider available)"
        try {
            $vms = Get-VM -ErrorAction Stop
        }
        catch [Microsoft.HyperV.PowerShell.VirtualizationException] {
            WriteLog "WARNING: Hyper-V error retrieving VMs: $($_.Exception.Message)"
            $vms = @()
        }
        catch {
            WriteLog "WARNING: Failed to retrieve VMs: $($_.Exception.Message)"
            $vms = @()
        }

        # Loop through each VM
        foreach ($vm in $vms) {
            if ($vm.Name.StartsWith("_FFU-")) {
                # Guard: skip VMs protected by checkpoint
                if ($protectedVMName -and $vm.Name -eq $protectedVMName) {
                    WriteLog "RESUME CLEANUP: Skipping protected VM: $($vm.Name)"
                    continue
                }
                if ($vm.State -eq 'Running') {
                    try {
                        WriteLog "Stopping running VM: $($vm.Name)"
                        Stop-VM -Name $vm.Name -TurnOff -Force -ErrorAction Stop
                        WriteLog "VM $($vm.Name) stopped successfully"
                    }
                    catch [Microsoft.HyperV.PowerShell.VirtualizationException] {
                        WriteLog "WARNING: Hyper-V error stopping VM '$($vm.Name)': $($_.Exception.Message)"
                    }
                    catch {
                        WriteLog "WARNING: Failed to stop VM '$($vm.Name)': $($_.Exception.Message)"
                    }
                }
                # If conditions are met, delete the VM
                # Note: For old VMs we may not have VMPath, so we derive it
                $vmPath = Join-Path $FFUDevelopmentPath "VM\$($vm.Name)"
                try {
                    Remove-FFUVM -VMName $vm.Name -VMPath $vmPath -InstallApps $true `
                                 -VhdxDisk $null -FFUDevelopmentPath $FFUDevelopmentPath
                }
                catch {
                    WriteLog "WARNING: Failed to remove VM '$($vm.Name)': $($_.Exception.Message)"
                }
            }
        }
    }

    # Check for MSFT Virtual disks where location contains FFUDevelopment in the path
    try {
        $disks = Get-Disk -FriendlyName *virtual* -ErrorAction Stop
    }
    catch {
        WriteLog "WARNING: Failed to retrieve virtual disks: $($_.Exception.Message)"
        $disks = @()
    }

    foreach ($disk in $disks) {
        $diskNumber = $disk.Number
        $vhdLocation = $disk.Location
        if ($vhdLocation -like "*FFUDevelopment*") {
            # Guard: skip disks protected by checkpoint
            if ($protectedPaths.Count -gt 0 -and $protectedPaths.ContainsKey($vhdLocation)) {
                WriteLog "RESUME CLEANUP: Skipping protected virtual disk $diskNumber at $vhdLocation"
                continue
            }
            WriteLog "Dismounting Virtual Disk $diskNumber with Location $vhdLocation"
            try {
                Dismount-ScratchVhdx -VhdxPath $vhdLocation -ErrorAction Stop
            }
            catch {
                WriteLog "WARNING: Failed to dismount virtual disk $diskNumber : $($_.Exception.Message)"
            }
            $parentFolder = Split-Path -Parent $vhdLocation
            # Guard: skip parent folder removal if protected by checkpoint
            if ($protectedPaths.Count -gt 0 -and $protectedPaths.ContainsKey($parentFolder)) {
                WriteLog "RESUME CLEANUP: Skipping protected folder $parentFolder"
            }
            elseif (-not [string]::IsNullOrWhiteSpace($parentFolder)) {
                WriteLog "Removing folder $parentFolder"
                try {
                    Remove-Item -Path $parentFolder -Recurse -Force -ErrorAction Stop
                }
                catch [System.IO.IOException] {
                    WriteLog "WARNING: IO error removing folder (files may be in use): $($_.Exception.Message)"
                }
                catch {
                    WriteLog "WARNING: Failed to remove folder: $($_.Exception.Message)"
                }
            }
        }
    }

    # Check for mounted DiskImages
    try {
        $volumes = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveType -eq 'CD-ROM' }
    }
    catch {
        WriteLog "WARNING: Failed to retrieve volumes: $($_.Exception.Message)"
        $volumes = @()
    }

    foreach ($volume in $volumes) {
        $letter = $volume.DriveLetter
        if ($letter) {
            WriteLog "Dismounting DiskImage for volume $letter"
            try {
                Get-Volume $letter -ErrorAction Stop | Get-DiskImage -ErrorAction Stop | Dismount-DiskImage -ErrorAction Stop | Out-Null
                WriteLog "Dismounting complete for volume $letter"
            }
            catch {
                WriteLog "WARNING: Failed to dismount DiskImage for volume $letter : $($_.Exception.Message)"
            }
        }
    }

    # Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    try {
        Invoke-Process cmd "/c mountvol /r" | Out-Null
        WriteLog 'Mountpoint cleanup complete'
    }
    catch {
        WriteLog "WARNING: Failed to remove unused mountpoints: $($_.Exception.Message)"
    }

    # Check for content in the VM folder and delete any folders that start with _FFU-
    if ([string]::IsNullOrWhiteSpace($VMLocation)) {
        $VMLocation = Join-Path $FFUDevelopmentPath 'VM'
        WriteLog "VMLocation not set; defaulting to $VMLocation"
    }
    if (Test-Path -Path $VMLocation) {
        try {
            $folders = Get-ChildItem -Path $VMLocation -Directory -ErrorAction Stop
            foreach ($folder in $folders) {
                if ($folder.Name -like '_FFU-*') {
                    # Guard: skip folders protected by checkpoint
                    if ($protectedPaths.Count -gt 0 -and $protectedPaths.ContainsKey($folder.FullName)) {
                        WriteLog "RESUME CLEANUP: Skipping protected VM folder: $($folder.FullName)"
                        continue
                    }
                    WriteLog "Removing folder $($folder.FullName)"
                    try {
                        Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
                        WriteLog "Folder removed: $($folder.FullName)"
                    }
                    catch [System.IO.IOException] {
                        WriteLog "WARNING: IO error removing folder (files may be in use): $($_.Exception.Message)"
                    }
                    catch {
                        WriteLog "WARNING: Failed to remove folder $($folder.FullName): $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            WriteLog "WARNING: Failed to enumerate VM location folders: $($_.Exception.Message)"
        }
    }
    else {
        WriteLog "VMLocation path $VMLocation not found; skipping VM folder cleanup"
    }

    # Remove orphaned mounted images
    # v1.0.3: Guard DISM operations with Test-DismReady to prevent 10-minute hangs
    # when WIMMount filter driver is not loaded (DismInitialize 0x80004005)
    $dismReady = $false
    if ($ExecutionContext.InvokeCommand.GetCommand('Test-DismReady', 'Function')) {
        $dismReady = Test-DismReady -AttemptRepair $true
    }
    else {
        # Fallback: quick fltmc check if Test-DismReady not available
        try {
            $fltmcOutput = & fltmc.exe filters 2>&1
            $dismReady = [bool]($fltmcOutput -match 'WimMount')
        }
        catch { $dismReady = $false }
    }

    if ($dismReady) {
        try {
            $mountedImages = Get-WindowsImage -Mounted -ErrorAction Stop
            if ($mountedImages) {
                foreach ($image in $mountedImages) {
                    $mountPath = $image.Path
                    WriteLog "Dismounting image at $mountPath"
                    try {
                        Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop | Out-Null
                        WriteLog "Successfully dismounted image at $mountPath"
                    }
                    catch [System.Runtime.InteropServices.COMException] {
                        WriteLog "WARNING: COM error dismounting image (may already be dismounted): $($_.Exception.Message)"
                    }
                    catch {
                        WriteLog "WARNING: Failed to dismount image at $mountPath : $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            WriteLog "WARNING: Error retrieving mounted images: $($_.Exception.Message)"
        }
    }
    else {
        WriteLog "WARNING: WIMMount not loaded - using non-DISM fallback for mount point cleanup"
        if ($ExecutionContext.InvokeCommand.GetCommand('Clear-OrphanedMountPointsWithoutDism', 'Function')) {
            Clear-OrphanedMountPointsWithoutDism
        }
    }

    # Remove Mount folder if it exists
    if (Test-Path -Path "$FFUDevelopmentPath\Mount") {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        try {
            Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force -ErrorAction Stop
            WriteLog 'Mount folder removed'
        }
        catch {
            WriteLog "WARNING: Failed to remove Mount folder: $($_.Exception.Message)"
        }
    }

    #Clear any corrupt Windows mount points
    # v1.0.3: Only use DISM-based cleanup if WIMMount is functional
    if ($dismReady) {
        WriteLog 'Clearing any corrupt Windows mount points'
        try {
            Clear-WindowsCorruptMountPoint -ErrorAction Stop | Out-Null
            WriteLog 'Corrupt mount point cleanup complete'
        }
        catch {
            WriteLog "WARNING: Failed to clear corrupt mount points: $($_.Exception.Message)"
        }
    }
    else {
        WriteLog "WARNING: Skipping Clear-WindowsCorruptMountPoint (WIMMount not loaded - would hang for 10 minutes)"
    }

    #Clean up registry
    if (Test-Path -Path 'HKLM:\FFU') {
        WriteLog 'Found HKLM:\FFU, removing it'
        try {
            Invoke-Process reg "unload HKLM\FFU" | Out-Null
            WriteLog 'Registry hive unloaded'
        }
        catch {
            WriteLog "WARNING: Failed to unload registry hive HKLM:\FFU: $($_.Exception.Message)"
        }
    }

    #Remove FFU User and Share (using .NET API for PowerShell 7 compatibility)
    try {
        $UserExists = Get-LocalUserAccount -Username $Username
        if ($UserExists) {
            WriteLog "Removing FFU User and Share"
            $UserExists.Dispose()
            try {
                Remove-FFUUserShare -Username $Username -ShareName $ShareName
                WriteLog 'FFU User and Share removal complete'
            }
            catch {
                WriteLog "WARNING: Failed to remove FFU User and Share: $($_.Exception.Message)"
            }
        }
    }
    catch {
        WriteLog "WARNING: Error checking for FFU User: $($_.Exception.Message)"
    }

    if ($RemoveApps) {
        WriteLog "Removing Apps in $AppsPath"
        try {
            Remove-Apps
            WriteLog 'Apps removal complete'
        }
        catch {
            WriteLog "WARNING: Failed to remove Apps: $($_.Exception.Message)"
        }
    }

    # Clean up $KBPath only if RemoveUpdates is true (matches Apps folder behavior)
    If ($RemoveUpdates -and (Test-Path -Path $KBPath)) {
        WriteLog "Removing $KBPath (RemoveUpdates=true)"
        try {
            Remove-Item -Path $KBPath -Recurse -Force -ErrorAction Stop
            WriteLog 'KB path removal complete'
        }
        catch {
            WriteLog "WARNING: Failed to remove KB path: $($_.Exception.Message)"
        }
    } elseif (Test-Path -Path $KBPath) {
        try {
            $kbFiles = Get-ChildItem -Path $KBPath -Recurse -File -ErrorAction Stop
            if ($kbFiles -and $kbFiles.Count -gt 0) {
                $kbSize = ($kbFiles | Measure-Object -Property Length -Sum).Sum
                WriteLog "Keeping $KBPath ($($kbFiles.Count) files, $([math]::Round($kbSize/1MB, 2)) MB) for future builds - RemoveUpdates=false"
            }
        }
        catch {
            WriteLog "WARNING: Error checking KB files: $($_.Exception.Message)"
        }
    }

    # Remove existing Apps.iso
    if (Test-Path -Path $AppsISO) {
        WriteLog "Removing $AppsISO"
        try {
            Remove-Item -Path $AppsISO -Force -ErrorAction Stop
            WriteLog 'Apps ISO removal complete'
        }
        catch {
            WriteLog "WARNING: Failed to remove Apps ISO: $($_.Exception.Message)"
        }
    }

    # Remove per-run session folder if present (Cancel/-Cleanup scenario)
    # Guard: preserve .session when resuming from checkpoint (contains checkpoint data)
    $sessionDir = Join-Path $FFUDevelopmentPath '.session'
    if ($null -ne $ResumeCheckpoint) {
        WriteLog "RESUME CLEANUP: Preserving .session folder for checkpoint resume"
    }
    elseif (Test-Path -Path $sessionDir) {
        WriteLog 'Removing .session folder'
        try {
            Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction Stop
            WriteLog 'Session folder removal complete'
        }
        catch {
            WriteLog "WARNING: Failed to remove session folder: $($_.Exception.Message)"
        }
    }

    # Remove dirty.txt file
    WriteLog 'Removing dirty.txt file'
    $dirtyPath = Join-Path $FFUDevelopmentPath "dirty.txt"
    if (Test-Path -Path $dirtyPath) {
        try {
            Remove-Item -Path $dirtyPath -Force -ErrorAction Stop
            WriteLog 'dirty.txt removed'
        }
        catch {
            WriteLog "WARNING: Failed to remove dirty.txt: $($_.Exception.Message)"
        }
    }
    WriteLog "Cleanup complete"
}

function Set-CaptureFFU {
    <#
    .SYNOPSIS
    Creates FFU capture user account and network share

    .DESCRIPTION
    Creates a local user account and SMB share for FFU capture operations.
    The share is created with full control permissions for the specified user,
    allowing the FFU VM to write captured FFU files to the host machine.

    .PARAMETER Username
    Name of the local user account to create (default: ffu_user)

    .PARAMETER ShareName
    Name of the SMB share to create (default: FFUCaptureShare)

    .PARAMETER FFUCaptureLocation
    Local path on the host to share for FFU capture

    .PARAMETER Password
    Optional SecureString password for the user account.
    If not provided, a random secure password will be generated.

    .EXAMPLE
    Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $false)]
        [string]$ShareName = "FFUCaptureShare",

        [Parameter(Mandatory = $true)]
        [string]$FFUCaptureLocation,

        [Parameter(Mandatory = $false)]
        [SecureString]$Password
    )

    WriteLog "Setting up FFU capture user and share"

    try {
        # Generate cryptographically secure password if not provided
        # SECURITY: Uses New-SecureRandomPassword which generates directly to SecureString
        # Password never exists as plain text during generation
        if (-not $Password) {
            WriteLog "Generating cryptographically secure password for user $Username"
            $Password = New-SecureRandomPassword -Length 20 -IncludeSpecialChars $true
            WriteLog "Password generated (20 chars, cryptographic RNG, direct to SecureString)"
        }

        # Check if user already exists (using .NET API for PowerShell 7 compatibility)
        $existingUser = Get-LocalUserAccount -Username $Username

        if ($existingUser) {
            WriteLog "User $Username already exists, resetting password to ensure sync with CaptureFFU.ps1"
            $existingUser.Dispose()
            # CRITICAL FIX: Reset the password on existing user to prevent "Password is incorrect" error (Error 86)
            # This ensures the password in CaptureFFU.ps1 always matches the user's actual password
            Set-LocalUserPassword -Username $Username -Password $Password
            WriteLog "Password reset successfully for existing user $Username"
        }
        else {
            WriteLog "Creating local user account: $Username"
            New-LocalUserAccount -Username $Username -Password $Password `
                                -FullName "FFU Capture User" `
                                -Description "User account for FFU capture operations" | Out-Null
            WriteLog "User account $Username created successfully"

            # Register cleanup for user account in case of failure
            # Uses InvokeCommand.GetCommand for ThreadJob compatibility (v1.0.3)
            if ($ExecutionContext.InvokeCommand.GetCommand('Register-UserAccountCleanup', 'Function')) {
                $null = Register-UserAccountCleanup -Username $Username
                WriteLog "Registered user account cleanup handler"
            }
        }

        # SECURITY: Set account expiry as failsafe (4 hours from now)
        # This ensures the temporary account is automatically disabled even if cleanup fails
        try {
            $expiryDate = Set-LocalUserAccountExpiry -Username $Username -ExpiryHours 4
            WriteLog "SECURITY: Account $Username set to expire at $($expiryDate.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        catch {
            WriteLog "WARNING: Failed to set account expiry (non-critical): $($_.Exception.Message)"
            # Continue - this is a security enhancement, not a requirement
        }

        # Create FFU capture directory if it doesn't exist
        if (-not (Test-Path $FFUCaptureLocation)) {
            WriteLog "Creating FFU capture directory: $FFUCaptureLocation"
            New-Item -Path $FFUCaptureLocation -ItemType Directory -Force | Out-Null
            WriteLog "Directory created successfully"
        }
        else {
            WriteLog "FFU capture directory already exists: $FFUCaptureLocation"
        }

        # Check if share already exists
        $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue

        if ($existingShare) {
            WriteLog "Share $ShareName already exists, skipping share creation"
        }
        else {
            WriteLog "Creating SMB share: $ShareName pointing to $FFUCaptureLocation"
            New-SmbShare -Name $ShareName -Path $FFUCaptureLocation -FullAccess $Username `
                        -Description "FFU Capture Share" -ErrorAction Stop | Out-Null
            WriteLog "SMB share $ShareName created successfully"

            # Register cleanup for network share in case of failure
            # Uses InvokeCommand.GetCommand for ThreadJob compatibility (v1.0.3)
            if ($ExecutionContext.InvokeCommand.GetCommand('Register-NetworkShareCleanup', 'Function')) {
                $null = Register-NetworkShareCleanup -ShareName $ShareName
                WriteLog "Registered network share cleanup handler"
            }
        }

        # Grant user full control to the share (in case share already existed)
        WriteLog "Granting $Username full control to share $ShareName"
        Grant-SmbShareAccess -Name $ShareName -AccountName $Username -AccessRight Full -Force -ErrorAction Stop | Out-Null
        WriteLog "Share permissions granted successfully"

        WriteLog "FFU capture user and share setup complete"
        WriteLog "  User: $Username"
        WriteLog "  Share: \\$env:COMPUTERNAME\$ShareName"
        WriteLog "  Path: $FFUCaptureLocation"
    }
    catch {
        WriteLog "ERROR: Failed to set up FFU capture user and share: $($_.Exception.Message)"
        throw $_
    }
}

function Remove-FFUUserShare {
    <#
    .SYNOPSIS
    Removes FFU capture user account and network share

    .DESCRIPTION
    Cleans up the local user account and SMB share created by Set-CaptureFFU.
    This function is called during cleanup to remove temporary resources.

    .PARAMETER Username
    Name of the local user account to remove

    .PARAMETER ShareName
    Name of the SMB share to remove

    .EXAMPLE
    Remove-FFUUserShare -Username "ffu_user" -ShareName "FFUCaptureShare"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $false)]
        [string]$ShareName = "FFUCaptureShare"
    )

    WriteLog "Cleaning up FFU capture user and share"

    try {
        # Remove SMB share if it exists
        $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue

        if ($existingShare) {
            WriteLog "Removing SMB share: $ShareName"
            Remove-SmbShare -Name $ShareName -Force -ErrorAction Stop
            WriteLog "SMB share removed successfully"
        }
        else {
            WriteLog "SMB share $ShareName does not exist, skipping removal"
        }

        # Remove local user if it exists (using .NET API for PowerShell 7 compatibility)
        $existingUser = Get-LocalUserAccount -Username $Username

        if ($existingUser) {
            WriteLog "Removing local user account: $Username"
            $existingUser.Dispose()
            Remove-LocalUserAccount -Username $Username
            WriteLog "User account removed successfully"
        }
        else {
            WriteLog "User $Username does not exist, skipping removal"
        }

        WriteLog "FFU capture user and share cleanup complete"
    }
    catch {
        WriteLog "WARNING: Failed to clean up FFU capture user and share: $($_.Exception.Message)"
        # Don't throw - cleanup failures shouldn't break the build
    }
}

function Remove-SensitiveCaptureMedia {
    <#
    .SYNOPSIS
    Securely removes sensitive data from capture media files

    .DESCRIPTION
    After FFU capture is complete, this function removes or sanitizes files
    that contain sensitive credentials (passwords) from the capture media
    and working directories. This is a security best practice to minimize
    credential exposure.

    SECURITY NOTE: The CaptureFFU.ps1 script on capture media contains
    plain text credentials required for WinPE to connect to the FFU share.
    This function should be called after capture is complete to sanitize
    these files.

    .PARAMETER FFUDevelopmentPath
    Path to the FFU development folder

    .PARAMETER SanitizeScript
    If true, overwrites credentials in CaptureFFU.ps1 with placeholder values.
    If false, deletes backup files but leaves the main script intact.
    Default is $true.

    .PARAMETER RemoveBackups
    If true, removes backup files of CaptureFFU.ps1 that may contain credentials.
    Default is $true.

    .EXAMPLE
    Remove-SensitiveCaptureMedia -FFUDevelopmentPath "C:\FFUDevelopment"

    .EXAMPLE
    Remove-SensitiveCaptureMedia -FFUDevelopmentPath "C:\FFUDevelopment" -SanitizeScript $true -RemoveBackups $true

    .NOTES
    SECURITY: This function helps minimize credential exposure by cleaning up
    sensitive data after the FFU capture process is complete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [bool]$SanitizeScript = $true,

        [Parameter(Mandatory = $false)]
        [bool]$RemoveBackups = $true
    )

    WriteLog "SECURITY: Starting sensitive capture media cleanup"

    try {
        $captureScriptPath = Join-Path $FFUDevelopmentPath "WinPECaptureFFUFiles\CaptureFFU.ps1"
        $cleanupCount = 0

        # Remove backup files that may contain credentials
        if ($RemoveBackups) {
            $backupPattern = Join-Path $FFUDevelopmentPath "WinPECaptureFFUFiles\CaptureFFU.ps1.backup-*"
            $backupFiles = Get-ChildItem -Path $backupPattern -ErrorAction SilentlyContinue

            foreach ($backup in $backupFiles) {
                try {
                    # Overwrite with random data before deleting (secure delete)
                    $randomData = -join ((1..($backup.Length / 2)) | ForEach-Object { [char](Get-Random -Minimum 32 -Maximum 127) })
                    Set-Content -Path $backup.FullName -Value $randomData -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $backup.FullName -Force -ErrorAction Stop
                    $cleanupCount++
                    WriteLog "SECURITY: Removed backup file: $($backup.Name)"
                }
                catch {
                    WriteLog "WARNING: Failed to remove backup file $($backup.Name): $($_.Exception.Message)"
                }
            }
        }

        # Sanitize the main script by replacing credentials with placeholders
        if ($SanitizeScript -and (Test-Path $captureScriptPath)) {
            WriteLog "SECURITY: Sanitizing credentials in CaptureFFU.ps1"

            try {
                $scriptContent = Get-Content -Path $captureScriptPath -Raw

                # Replace password with placeholder
                $scriptContent = $scriptContent -replace "(\`$Password\s*=\s*)['\`"][^'\`"]*['\`"]", "`$1'CREDENTIAL_REMOVED_FOR_SECURITY'"

                # Replace IP address with placeholder (optional, for extra privacy)
                # $scriptContent = $scriptContent -replace "(\`$VMHostIPAddress\s*=\s*)['\`"][^'\`"]*['\`"]", "`$1'0.0.0.0'"

                Set-Content -Path $captureScriptPath -Value $scriptContent -Force
                $cleanupCount++
                WriteLog "SECURITY: CaptureFFU.ps1 credentials sanitized"
            }
            catch {
                WriteLog "WARNING: Failed to sanitize CaptureFFU.ps1: $($_.Exception.Message)"
            }
        }

        WriteLog "SECURITY: Capture media cleanup complete ($cleanupCount items processed)"
    }
    catch {
        WriteLog "WARNING: Capture media cleanup encountered errors: $($_.Exception.Message)"
        # Don't throw - cleanup failures shouldn't break the build
    }
}

function Update-CaptureFFUScript {
    <#
    .SYNOPSIS
    Updates CaptureFFU.ps1 script with runtime configuration values

    .DESCRIPTION
    Replaces placeholder values in the CaptureFFU.ps1 template script with actual
    runtime values (VMHostIPAddress, ShareName, Username, Password, etc.).
    This function should be called after Set-CaptureFFU and before New-PEMedia
    to ensure the WinPE capture script has the correct connection parameters.

    .PARAMETER VMHostIPAddress
    IP address of the Hyper-V host that will host the FFU capture share

    .PARAMETER ShareName
    Name of the SMB share for FFU capture (e.g., FFUCaptureShare)

    .PARAMETER Username
    Username for authenticating to the FFU capture share

    .PARAMETER Password
    Password for authenticating to the FFU capture share (plain text or SecureString)

    .PARAMETER FFUDevelopmentPath
    Path to the FFU development folder containing WinPECaptureFFUFiles

    .PARAMETER CustomFFUNameTemplate
    Optional custom FFU naming template with placeholders

    .EXAMPLE
    # Using SecureString for password (recommended)
    $securePassword = New-SecureRandomPassword
    Update-CaptureFFUScript -VMHostIPAddress "192.168.1.100" -ShareName "FFUCaptureShare" `
                            -Username "ffu_user" -Password $securePassword `
                            -FFUDevelopmentPath "C:\FFUDevelopment"

    .EXAMPLE
    # Using Read-Host for interactive password entry
    $securePassword = Read-Host -Prompt "Enter password" -AsSecureString
    Update-CaptureFFUScript -VMHostIPAddress "192.168.1.100" -ShareName "FFUCaptureShare" `
                            -Username "ffu_user" -Password $securePassword `
                            -FFUDevelopmentPath "C:\FFUDevelopment"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMHostIPAddress,

        [Parameter(Mandatory = $false)]
        [string]$ShareName = "FFUCaptureShare",

        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        $Password,  # Can be string or SecureString

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$CustomFFUNameTemplate,

        [Parameter(Mandatory = $false)]
        [string]$VMwareNetworkType
    )

    WriteLog "Updating CaptureFFU.ps1 script with runtime configuration"

    try {
        # Construct path to CaptureFFU.ps1 script
        $captureFFUScriptPath = Join-Path $FFUDevelopmentPath "WinPECaptureFFUFiles\CaptureFFU.ps1"

        # Validate script file exists
        if (-not (Test-Path -Path $captureFFUScriptPath -PathType Leaf)) {
            $errorMsg = "CaptureFFU.ps1 script not found at expected location: $captureFFUScriptPath"
            WriteLog "ERROR: $errorMsg"
            throw $errorMsg
        }

        WriteLog "Found CaptureFFU.ps1 at: $captureFFUScriptPath"

        # Create backup of original script (for safety)
        $backupPath = "$captureFFUScriptPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        WriteLog "Creating backup: $backupPath"
        Copy-Item -Path $captureFFUScriptPath -Destination $backupPath -Force
        WriteLog "Backup created successfully"

        # Read current script content
        WriteLog "Reading current script content"
        $scriptContent = Get-Content -Path $captureFFUScriptPath -Raw

        # Validate script contains expected placeholder variables
        $requiredVariables = @('$VMHostIPAddress', '$ShareName', '$UserName', '$Password')
        $missingVariables = @()

        foreach ($variable in $requiredVariables) {
            if ($scriptContent -notmatch [regex]::Escape($variable)) {
                $missingVariables += $variable
            }
        }

        if ($missingVariables.Count -gt 0) {
            $errorMsg = "CaptureFFU.ps1 is missing expected placeholder variables: $($missingVariables -join ', ')"
            WriteLog "WARNING: $errorMsg"
            WriteLog "Script may have been modified. Proceeding with update but results may be unexpected."
        }

        # SECURITY: Convert SecureString to plaintext for script injection
        # WinPE cannot use SecureString/DPAPI, so plaintext is unavoidable in CaptureFFU.ps1
        # Pattern: Convert -> Use -> Clear immediately
        $plainPassword = $null
        if ($Password -is [SecureString]) {
            WriteLog "Converting SecureString password to plain text for script injection"
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            try {
                $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        else {
            $plainPassword = $Password
        }

        # Perform replacements using regex to match variable assignment pattern
        WriteLog "Replacing placeholder values with runtime configuration:"
        WriteLog "  VMHostIPAddress: $VMHostIPAddress"
        WriteLog "  ShareName: $ShareName"
        WriteLog "  Username: $Username"
        WriteLog "  Password: [REDACTED - length $($plainPassword.Length)]"

        # Replace each variable assignment (pattern: $VarName = 'value' or $VarName = "value")
        $scriptContent = $scriptContent -replace '(\$VMHostIPAddress\s*=\s*)[''"].*?[''"]', "`$1'$VMHostIPAddress'"
        $scriptContent = $scriptContent -replace '(\$ShareName\s*=\s*)[''"].*?[''"]', "`$1'$ShareName'"
        $scriptContent = $scriptContent -replace '(\$UserName\s*=\s*)[''"].*?[''"]', "`$1'$Username'"
        $scriptContent = $scriptContent -replace '(\$Password\s*=\s*)[''"].*?[''"]', "`$1'$plainPassword'"

        # Update CustomFFUNameTemplate if provided
        if (![string]::IsNullOrEmpty($CustomFFUNameTemplate)) {
            WriteLog "  CustomFFUNameTemplate: $CustomFFUNameTemplate"
            $scriptContent = $scriptContent -replace '(\$CustomFFUNameTemplate\s*=\s*)[''"].*?[''"]', "`$1'$CustomFFUNameTemplate'"
        }

        # Update VMwareNetworkType if provided (for diagnostics inside WinPE)
        if (![string]::IsNullOrEmpty($VMwareNetworkType)) {
            WriteLog "  VMwareNetworkType: $VMwareNetworkType"
            $scriptContent = $scriptContent -replace '(\$VMwareNetworkType\s*=\s*)[''"].*?[''"]', "`$1'$VMwareNetworkType'"
        }

        # Write updated content back to script file
        WriteLog "Writing updated script content to: $captureFFUScriptPath"
        Set-Content -Path $captureFFUScriptPath -Value $scriptContent -Force -Encoding UTF8

        WriteLog "CaptureFFU.ps1 script updated successfully"

        # SECURITY: Clear plaintext password from memory immediately after use
        # This minimizes the time the password exists in memory as plaintext
        if ($plainPassword) {
            $plainPassword = $null
        }

        # Verify the update by re-reading and checking values
        WriteLog "Verifying script update..."
        $verifyContent = Get-Content -Path $captureFFUScriptPath -Raw

        $verificationPassed = $true
        if ($verifyContent -notmatch [regex]::Escape($VMHostIPAddress)) {
            WriteLog "WARNING: VMHostIPAddress not found in updated script"
            $verificationPassed = $false
        }
        if ($verifyContent -notmatch [regex]::Escape($ShareName)) {
            WriteLog "WARNING: ShareName not found in updated script"
            $verificationPassed = $false
        }
        if ($verifyContent -notmatch [regex]::Escape($Username)) {
            WriteLog "WARNING: Username not found in updated script"
            $verificationPassed = $false
        }

        if ($verificationPassed) {
            WriteLog "Script update verification PASSED"
        }
        else {
            WriteLog "WARNING: Script update verification had issues. Check the script manually."
        }

        WriteLog "Update-CaptureFFUScript completed successfully"
    }
    catch {
        WriteLog "ERROR: Failed to update CaptureFFU.ps1 script: $($_.Exception.Message)"
        WriteLog "Stack trace: $($_.ScriptStackTrace)"
        throw $_
    }
    finally {
        # SECURITY: Ensure plaintext password is always cleared, even on error
        if ($plainPassword) {
            $plainPassword = $null
        }
    }
}

function Get-OrphanedVMResources {
    <#
    .SYNOPSIS
    Scans for and reports orphaned FFU build resources

    .DESCRIPTION
    Detects orphaned FFU build artifacts that may have been left behind after
    failed or interrupted builds (e.g., Ctrl+C during VM creation). Scans for:
    - Orphaned Hyper-V VMs (names starting with _FFU-)
    - Orphaned VHDX files (not attached to any VM)
    - Orphaned HGS Guardians
    - Orphaned certificates in Shielded VM store
    - VMware lock directories (*.lck)
    - Orphaned checkpoint files (*.avhdx)

    .PARAMETER FFUDevelopmentPath
    Root path to FFUDevelopment folder for scanning

    .PARAMETER VMLocation
    Optional VM folder path (defaults to $FFUDevelopmentPath\VM)

    .PARAMETER IncludeVMware
    Include VMware artifacts in the scan

    .PARAMETER ScanOnly
    Only report orphans, don't generate cleanup actions

    .OUTPUTS
    PSCustomObject with orphan details and optional cleanup actions

    .EXAMPLE
    Get-OrphanedVMResources -FFUDevelopmentPath "C:\FFUDevelopment"

    .EXAMPLE
    Get-OrphanedVMResources -FFUDevelopmentPath "C:\FFU" -IncludeVMware -ScanOnly
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$VMLocation,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeVMware,

        [Parameter(Mandatory = $false)]
        [switch]$ScanOnly
    )

    WriteLog "Scanning for orphaned FFU build resources in $FFUDevelopmentPath"

    # Initialize result object
    $result = [PSCustomObject]@{
        OrphanedVMs              = @()
        OrphanedVHDX             = @()
        OrphanedGuardians        = @()
        OrphanedCertificates     = @()
        OrphanedLockFiles        = @()
        OrphanedCheckpointFiles  = @()
        TotalOrphans             = 0
        CleanupActions           = @()
    }

    # Set default VM location
    if ([string]::IsNullOrWhiteSpace($VMLocation)) {
        $VMLocation = Join-Path $FFUDevelopmentPath 'VM'
    }

    # 1. Detect orphaned Hyper-V VMs
    WriteLog 'Scanning for orphaned Hyper-V VMs'
    try {
        $orphanedVMs = Get-VM -ErrorAction SilentlyContinue |
            Where-Object { $_.Name.StartsWith('_FFU-') }

        if ($orphanedVMs) {
            $result.OrphanedVMs = @($orphanedVMs | ForEach-Object { $_.Name })
            WriteLog "Found $($result.OrphanedVMs.Count) orphaned VMs: $($result.OrphanedVMs -join ', ')"

            if (-not $ScanOnly) {
                foreach ($vm in $orphanedVMs) {
                    $result.CleanupActions += "Stop-VM -Name '$($vm.Name)' -TurnOff -Force -ErrorAction SilentlyContinue; Remove-VM -Name '$($vm.Name)' -Force"
                }
            }
        }
    }
    catch {
        WriteLog "WARNING: Error scanning for VMs: $($_.Exception.Message)"
    }

    # 2. Detect orphaned VHDX files
    WriteLog 'Scanning for orphaned VHDX files'
    try {
        if (Test-Path -Path $VMLocation) {
            $vhdxFiles = Get-ChildItem -Path $VMLocation -Filter '*.vhdx' -Recurse -ErrorAction SilentlyContinue

            foreach ($vhdx in $vhdxFiles) {
                $isOrphaned = $true

                # Check if VHDX is attached to any VM
                try {
                    $vhdInfo = Get-VHD -Path $vhdx.FullName -ErrorAction SilentlyContinue
                    if ($vhdInfo -and $vhdInfo.Attached) {
                        # Get the VM using this VHD
                        $attachedVMs = Get-VM -ErrorAction SilentlyContinue | ForEach-Object {
                            $vmHDs = Get-VMHardDiskDrive -VMName $_.Name -ErrorAction SilentlyContinue
                            if ($vmHDs.Path -contains $vhdx.FullName) {
                                $_
                            }
                        }

                        if ($attachedVMs) {
                            # Attached to a VM that exists - not orphaned
                            $isOrphaned = $false
                        }
                    }
                }
                catch {
                    # If we can't get VHD info, assume it's orphaned
                }

                if ($isOrphaned) {
                    $result.OrphanedVHDX += $vhdx.FullName
                    if (-not $ScanOnly) {
                        $result.CleanupActions += "Remove-Item -Path '$($vhdx.FullName)' -Force"
                    }
                }
            }

            if ($result.OrphanedVHDX.Count -gt 0) {
                WriteLog "Found $($result.OrphanedVHDX.Count) orphaned VHDX files"
            }
        }
    }
    catch {
        WriteLog "WARNING: Error scanning for VHDX files: $($_.Exception.Message)"
    }

    # 3. Detect orphaned HGS Guardians
    WriteLog 'Scanning for orphaned HGS Guardians'
    try {
        $orphanedGuardians = Get-HgsGuardian -ErrorAction SilentlyContinue |
            Where-Object { $_.Name.StartsWith('_FFU-') }

        if ($orphanedGuardians) {
            $result.OrphanedGuardians = @($orphanedGuardians | ForEach-Object { $_.Name })
            WriteLog "Found $($result.OrphanedGuardians.Count) orphaned HGS Guardians"

            if (-not $ScanOnly) {
                foreach ($guardian in $orphanedGuardians) {
                    $result.CleanupActions += "Remove-HgsGuardian -Name '$($guardian.Name)' -ErrorAction SilentlyContinue"
                }
            }
        }
    }
    catch {
        WriteLog "WARNING: Error scanning for HGS Guardians: $($_.Exception.Message)"
    }

    # 4. Detect orphaned certificates
    WriteLog 'Scanning for orphaned Shielded VM certificates'
    try {
        $certPath = 'Cert:\LocalMachine\Shielded VM Local Certificates\'
        if (Test-Path -Path $certPath) {
            $orphanedCerts = Get-ChildItem -Path $certPath -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -like '*_FFU-*' }

            if ($orphanedCerts) {
                $result.OrphanedCertificates = @($orphanedCerts | ForEach-Object { $_.PSPath })
                WriteLog "Found $($result.OrphanedCertificates.Count) orphaned certificates"

                if (-not $ScanOnly) {
                    foreach ($cert in $orphanedCerts) {
                        $result.CleanupActions += "Remove-Item -Path '$($cert.PSPath)' -Force"
                    }
                }
            }
        }
    }
    catch {
        WriteLog "WARNING: Error scanning for certificates: $($_.Exception.Message)"
    }

    # 5. Detect VMware lock directories (if IncludeVMware)
    if ($IncludeVMware) {
        WriteLog 'Scanning for VMware lock directories'
        try {
            if (Test-Path -Path $VMLocation) {
                $lockDirs = Get-ChildItem -Path $VMLocation -Filter '*.lck' -Directory -Recurse -ErrorAction SilentlyContinue

                if ($lockDirs) {
                    # Filter to only include locks not associated with running VMware processes
                    $orphanedLocks = @()
                    foreach ($lockDir in $lockDirs) {
                        $vmxRunning = Get-Process -Name 'vmware-vmx' -ErrorAction SilentlyContinue |
                            Where-Object { $_.Path -like "*$(Split-Path $lockDir.FullName -Parent)*" }

                        if (-not $vmxRunning) {
                            $orphanedLocks += $lockDir.FullName
                            if (-not $ScanOnly) {
                                $result.CleanupActions += "Remove-Item -Path '$($lockDir.FullName)' -Recurse -Force"
                            }
                        }
                    }

                    $result.OrphanedLockFiles = $orphanedLocks
                    if ($orphanedLocks.Count -gt 0) {
                        WriteLog "Found $($orphanedLocks.Count) orphaned VMware lock directories"
                    }
                }
            }
        }
        catch {
            WriteLog "WARNING: Error scanning for VMware lock files: $($_.Exception.Message)"
        }
    }

    # 6. Detect orphaned AVHDX files (checkpoint leftovers)
    WriteLog 'Scanning for orphaned checkpoint files (AVHDX)'
    try {
        if (Test-Path -Path $VMLocation) {
            $avhdxFiles = Get-ChildItem -Path $VMLocation -Filter '*.avhdx' -Recurse -ErrorAction SilentlyContinue

            foreach ($avhdx in $avhdxFiles) {
                $isOrphaned = $true

                # Try to find if this AVHDX is part of any active snapshot
                try {
                    $allVMs = Get-VM -ErrorAction SilentlyContinue
                    foreach ($vm in $allVMs) {
                        $snapshots = Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue
                        foreach ($snap in $snapshots) {
                            $snapVHDs = Get-VMHardDiskDrive -VMSnapshot $snap -ErrorAction SilentlyContinue
                            if ($snapVHDs.Path -contains $avhdx.FullName) {
                                $isOrphaned = $false
                                break
                            }
                        }
                        if (-not $isOrphaned) { break }
                    }
                }
                catch {
                    # If we can't check, assume orphaned
                }

                if ($isOrphaned) {
                    $result.OrphanedCheckpointFiles += $avhdx.FullName
                    if (-not $ScanOnly) {
                        $result.CleanupActions += "Remove-Item -Path '$($avhdx.FullName)' -Force"
                    }
                }
            }

            if ($result.OrphanedCheckpointFiles.Count -gt 0) {
                WriteLog "Found $($result.OrphanedCheckpointFiles.Count) orphaned checkpoint files"
            }
        }
    }
    catch {
        WriteLog "WARNING: Error scanning for AVHDX files: $($_.Exception.Message)"
    }

    # Calculate total orphans
    $result.TotalOrphans = $result.OrphanedVMs.Count +
                           $result.OrphanedVHDX.Count +
                           $result.OrphanedGuardians.Count +
                           $result.OrphanedCertificates.Count +
                           $result.OrphanedLockFiles.Count +
                           $result.OrphanedCheckpointFiles.Count

    WriteLog "Orphan scan complete. Total orphans found: $($result.TotalOrphans)"

    $result
}

function Remove-FFUBuildArtifacts {
    <#
    .SYNOPSIS
    Removes FFU build artifacts that are not VM-specific

    .DESCRIPTION
    Cleans up mounted images, mount folder, mountpoints, and VM path artifacts.
    This function handles cleanup that is common across all hypervisors (Hyper-V, VMware, etc.)
    and should be called after the hypervisor provider's RemoveVM method.

    Use this with the hypervisor provider's RemoveVM for complete cleanup:
    1. Call $provider.RemoveVM($vm, $true) to remove VM and disks
    2. Call Remove-FFUBuildArtifacts for remaining cleanup

    .PARAMETER VMPath
    Path to the VM configuration directory to remove

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for mount folder cleanup

    .PARAMETER CleanupVMPath
    If true, removes the VMPath directory (default: true)

    .PARAMETER CleanupMountedImages
    If true, dismounts orphaned mounted images (default: true)

    .PARAMETER CleanupMountFolder
    If true, removes the Mount folder (default: true)

    .PARAMETER CleanupMountpoints
    If true, removes unused mountpoints (default: true)

    .EXAMPLE
    # After provider removes VM
    $provider.RemoveVM($vm, $true)
    Remove-FFUBuildArtifacts -VMPath "C:\FFU\VM\_FFU-Build" -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [bool]$CleanupVMPath = $true,

        [Parameter(Mandatory = $false)]
        [bool]$CleanupMountedImages = $true,

        [Parameter(Mandatory = $false)]
        [bool]$CleanupMountFolder = $true,

        [Parameter(Mandatory = $false)]
        [bool]$CleanupMountpoints = $true
    )

    WriteLog "Starting FFU build artifact cleanup"

    # Remove VM path if specified
    if ($CleanupVMPath -and -not [string]::IsNullOrWhiteSpace($VMPath)) {
        WriteLog "Removing $VMPath"
        try {
            if (Test-Path -Path $VMPath) {
                Remove-Item -Path $VMPath -Force -Recurse -ErrorAction Stop
                WriteLog 'VM path removal complete'
            }
            else {
                WriteLog "VM path $VMPath does not exist, skipping"
            }
        }
        catch [System.IO.IOException] {
            WriteLog "WARNING: IO error removing VM path (files may be in use): $($_.Exception.Message)"
        }
        catch [System.UnauthorizedAccessException] {
            WriteLog "WARNING: Access denied removing VM path: $($_.Exception.Message)"
        }
        catch {
            WriteLog "WARNING: Failed to remove VM path: $($_.Exception.Message)"
        }
    }

    # Remove orphaned mounted images
    # v1.0.3: Guard DISM operations with Test-DismReady to prevent 10-minute hangs
    if ($CleanupMountedImages) {
        $dismReadyForArtifacts = $false
        if ($ExecutionContext.InvokeCommand.GetCommand('Test-DismReady', 'Function')) {
            $dismReadyForArtifacts = Test-DismReady -AttemptRepair $true
        }
        else {
            try {
                $fltmcArt = & fltmc.exe filters 2>&1
                $dismReadyForArtifacts = [bool]($fltmcArt -match 'WimMount')
            }
            catch { $dismReadyForArtifacts = $false }
        }

        if ($dismReadyForArtifacts) {
            try {
                $mountedImages = Get-WindowsImage -Mounted -ErrorAction Stop
                if ($mountedImages) {
                    foreach ($image in $mountedImages) {
                        $mountPath = $image.Path
                        WriteLog "Dismounting image at $mountPath"
                        try {
                            Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop
                            WriteLog "Successfully dismounted image at $mountPath"
                        }
                        catch [System.Runtime.InteropServices.COMException] {
                            WriteLog "WARNING: COM error dismounting image at $mountPath (may already be dismounted): $($_.Exception.Message)"
                        }
                        catch {
                            WriteLog "WARNING: Failed to dismount image at $mountPath : $($_.Exception.Message)"
                        }
                    }
                }
            }
            catch {
                WriteLog "WARNING: Error retrieving mounted images: $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "WARNING: WIMMount not loaded - using non-DISM fallback for artifact cleanup"
            if ($ExecutionContext.InvokeCommand.GetCommand('Clear-OrphanedMountPointsWithoutDism', 'Function')) {
                Clear-OrphanedMountPointsWithoutDism
            }
        }
    }

    # Remove Mount folder if it exists
    if ($CleanupMountFolder) {
        $mountFolder = "$FFUDevelopmentPath\Mount"
        if (Test-Path -Path $mountFolder) {
            WriteLog "Remove $mountFolder folder"
            try {
                Remove-Item -Path $mountFolder -Recurse -Force -ErrorAction Stop
                WriteLog 'Mount folder removed'
            }
            catch {
                WriteLog "WARNING: Failed to remove Mount folder: $($_.Exception.Message)"
            }
        }
    }

    # Remove unused mountpoints
    if ($CleanupMountpoints) {
        WriteLog 'Remove unused mountpoints'
        try {
            Invoke-Process cmd "/c mountvol /r" | Out-Null
            WriteLog 'Mountpoint cleanup complete'
        }
        catch {
            WriteLog "WARNING: Failed to remove unused mountpoints: $($_.Exception.Message)"
        }
    }

    WriteLog "FFU build artifact cleanup complete"
}

function Remove-FFUVMWithProvider {
    <#
    .SYNOPSIS
    Removes FFU VM using the hypervisor provider with fallback to Remove-FFUVM

    .DESCRIPTION
    Hypervisor-agnostic VM cleanup helper that:
    1. Uses the provided hypervisor provider if available
    2. Falls back to Remove-FFUVM for Hyper-V-specific cleanup if provider fails
    3. Always calls Remove-FFUBuildArtifacts for non-VM cleanup

    This function is exported from FFU.VM to ensure availability in ThreadJob
    contexts where script-scope functions are not accessible.

    .PARAMETER VM
    The VMInfo object returned from CreateVM (optional - can cleanup by name if null)

    .PARAMETER VMName
    Name of the VM to remove

    .PARAMETER VMPath
    Path to the VM configuration directory

    .PARAMETER InstallApps
    Whether apps were installed (affects VHDX cleanup)

    .PARAMETER VhdxDisk
    VHDX disk object for cleanup

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path

    .PARAMETER HypervisorProvider
    The hypervisor provider object (was $script:HypervisorProvider in BuildFFUVM.ps1)

    .EXAMPLE
    Remove-FFUVMWithProvider -VM $FFUVM -VMName $VMName -VMPath $VMPath `
                             -InstallApps $true -FFUDevelopmentPath $FFUDevelopmentPath `
                             -HypervisorProvider $provider
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $VM,

        [Parameter(Mandatory = $false)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [bool]$InstallApps,

        [Parameter(Mandatory = $false)]
        $VhdxDisk,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        $HypervisorProvider
    )

    WriteLog "Starting hypervisor-agnostic VM cleanup"

    $vmRemoved = $false

    # Try hypervisor provider first if available
    if ($null -ne $HypervisorProvider) {
        try {
            if ($null -ne $VM) {
                WriteLog "Removing VM via hypervisor provider: $($VM.Name)"
                $HypervisorProvider.RemoveVM($VM, $true)  # $true = remove disks
                $vmRemoved = $true
                WriteLog "VM removed via hypervisor provider"
            }
            elseif (-not [string]::IsNullOrWhiteSpace($VMName)) {
                # Try to get VM by name from provider
                WriteLog "Attempting to get VM '$VMName' from provider for cleanup"
                $existingVM = $HypervisorProvider.GetVM($VMName)
                if ($null -ne $existingVM) {
                    WriteLog "Found VM, removing via hypervisor provider"
                    $HypervisorProvider.RemoveVM($existingVM, $true)
                    $vmRemoved = $true
                    WriteLog "VM removed via hypervisor provider"
                }
                else {
                    WriteLog "VM '$VMName' not found by provider - may already be removed"
                    $vmRemoved = $true  # Consider it success if VM doesn't exist
                }
            }
        }
        catch {
            WriteLog "WARNING: Hypervisor provider cleanup failed: $($_.Exception.Message)"
            WriteLog "Falling back to Remove-FFUVM for cleanup"
        }
    }

    # Fall back to Remove-FFUVM if provider cleanup failed or not available
    if (-not $vmRemoved) {
        WriteLog "Using Remove-FFUVM for Hyper-V-specific cleanup"
        try {
            Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
                         -VhdxDisk $VhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath
        }
        catch {
            WriteLog "WARNING: Remove-FFUVM failed: $($_.Exception.Message)"
        }
    }
    else {
        # Provider removed VM, but we still need to clean up build artifacts
        WriteLog "Running Remove-FFUBuildArtifacts for remaining cleanup"
        try {
            Remove-FFUBuildArtifacts -VMPath $VMPath -FFUDevelopmentPath $FFUDevelopmentPath
        }
        catch {
            WriteLog "WARNING: Remove-FFUBuildArtifacts failed: $($_.Exception.Message)"
        }
    }

    WriteLog "VM cleanup complete"
}

#region REL-VM-03: Transient Error Detection and Retry

function Test-IsTransientVMError {
    <#
    .SYNOPSIS
        Tests if a VM operation error is transient and retryable.

    .DESCRIPTION
        Analyzes error messages to determine if they indicate a transient
        condition (disk busy, file locked, network timeout) that might succeed
        on retry, versus permanent errors that should fail immediately.

    .PARAMETER ErrorMessage
        The error message to analyze.

    .OUTPUTS
        Boolean - true if the error appears to be transient/retryable.

    .EXAMPLE
        if (Test-IsTransientVMError -ErrorMessage $_.Exception.Message) {
            # Retry the operation
        }

    .NOTES
        Module: FFU.VM
        REL-VM-03: Transient error retry support
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ErrorMessage
    )

    if ([string]::IsNullOrEmpty($ErrorMessage)) {
        return $false
    }

    $lowerError = $ErrorMessage.ToLower()

    # Transient patterns - these are worth retrying
    $transientPatterns = @(
        'disk.*busy',
        'file.*locked',
        'file.*in use',
        'access.*denied',          # Can be transient during resource contention
        'network.*timeout',
        'rpc.*unavailable',
        'rpc.*server.*busy',
        'cannot access',
        'the process cannot access',
        'being used by another process',
        'the handle is invalid',
        'sharing violation',
        'device is not ready',
        'system cannot find the file',  # Can be transient during disk operations
        'operation timed out',
        'the operation was canceled',
        'try again',
        'temporarily unavailable'
    )

    # Permanent patterns - these should NOT be retried
    $permanentPatterns = @(
        'already exists',
        'does not exist',
        'not found',
        'invalid parameter',
        'invalid argument',
        'invalid value',
        'hyper-v.*not enabled',
        'feature.*not available',
        'not supported',
        'insufficient memory',
        'out of memory',
        'disk full',
        'insufficient disk space',
        'quota exceeded'
    )

    # Check permanent patterns first - if matches, NOT transient
    foreach ($pattern in $permanentPatterns) {
        if ($lowerError -match $pattern) {
            return $false
        }
    }

    # Check transient patterns
    foreach ($pattern in $transientPatterns) {
        if ($lowerError -match $pattern) {
            return $true
        }
    }

    # Default to not transient for unknown errors (fail fast)
    return $false
}

function Invoke-VMOperationWithRetry {
    <#
    .SYNOPSIS
        Retry wrapper for VM operations that handles transient failures.

    .DESCRIPTION
        Wraps VM operations with automatic retry logic when transient errors
        (disk busy, file locked, network timeout) are detected. Uses exponential
        backoff with jitter to avoid hammering the system.

        For hypervisor-level errors (service issues), delegates to
        Invoke-WithHypervisorRetry. For VM-specific transient errors,
        handles retry internally.

    .PARAMETER ScriptBlock
        The script block containing the VM operation to execute.

    .PARAMETER OperationName
        Name of the operation for logging purposes.

    .PARAMETER MaxRetries
        Maximum number of retry attempts. Default is 3.

    .PARAMETER BaseDelaySeconds
        Base delay between retries in seconds. Default is 2.
        Actual delay uses exponential backoff: BaseDelay * (2 ^ (attempt - 1))

    .PARAMETER UseHypervisorRetry
        If specified, also check for hypervisor service errors via
        Invoke-WithHypervisorRetry pattern.

    .PARAMETER Provider
        Hypervisor provider ('HyperV' or 'VMware') - required if UseHypervisorRetry.

    .OUTPUTS
        The result of the ScriptBlock on success.

    .EXAMPLE
        Invoke-VMOperationWithRetry -OperationName 'Dismount VHDX' -ScriptBlock {
            Dismount-VHD -Path $vhdxPath -ErrorAction Stop
        }

    .NOTES
        Module: FFU.VM
        REL-VM-03: Transient error retry support
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [string]$OperationName = 'VM operation',

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false)]
        [int]$BaseDelaySeconds = 2,

        [Parameter(Mandatory = $false)]
        [switch]$UseHypervisorRetry,

        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware')]
        [string]$Provider = 'HyperV'
    )

    $attempts = @()
    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $result = & $ScriptBlock

            if ($attempt -gt 1) {
                if ($function:WriteLog) {
                    WriteLog "$OperationName succeeded on attempt $attempt"
                }
            }

            return $result
        }
        catch {
            $lastError = $_
            $errorMessage = $_.Exception.Message

            $attempts += @{
                Attempt = $attempt
                Time = [datetime]::Now
                Error = $errorMessage
            }

            # Check if this is a transient VM error
            $isTransient = Test-IsTransientVMError -ErrorMessage $errorMessage

            # If using hypervisor retry, also check for service errors
            if ($UseHypervisorRetry -and -not $isTransient) {
                $isServiceError = Test-IsServiceError -Provider $Provider -ErrorMessage $errorMessage
                $isTransient = $isServiceError
            }

            if (-not $isTransient) {
                # Permanent error - fail immediately
                if ($function:WriteLog) {
                    WriteLog "$OperationName failed (non-recoverable): $errorMessage"
                }
                throw
            }

            # Transient error - prepare for retry
            if ($function:WriteLog) {
                WriteLog "$OperationName failed (attempt $attempt/$MaxRetries): $errorMessage"
            }

            if ($attempt -ge $MaxRetries) {
                break
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

    # Max retries exhausted
    $errorBuilder = [System.Text.StringBuilder]::new()
    [void]$errorBuilder.AppendLine("$OperationName failed after $MaxRetries attempts.")
    [void]$errorBuilder.AppendLine("")
    [void]$errorBuilder.AppendLine("Attempt history:")
    foreach ($att in $attempts) {
        [void]$errorBuilder.AppendLine("  Attempt $($att.Attempt) at $($att.Time.ToString('HH:mm:ss')): $($att.Error)")
    }
    [void]$errorBuilder.AppendLine("")
    [void]$errorBuilder.AppendLine("Last error: $($lastError.Exception.Message)")

    if ($function:WriteLog) {
        WriteLog "ERROR: $($errorBuilder.ToString())"
    }

    throw $errorBuilder.ToString()
}

#endregion REL-VM-03

#region REL-VM-04: Checkpoint Disk Space Validation

function Test-CheckpointDiskSpace {
    <#
    .SYNOPSIS
        Validates sufficient disk space exists for checkpoint operation.

    .DESCRIPTION
        Checks available disk space on the drive containing the VM's VHDX files
        against the required space for a checkpoint. Checkpoints create differential
        disks (AVHDX) that can grow to the size of the original VHDX, so we validate
        with a configurable margin.

    .PARAMETER VMName
        Name of the VM to check. Uses this to find VHDX location.

    .PARAMETER VHDXPath
        Direct path to VHDX file. Alternative to VMName.

    .PARAMETER MarginPercent
        Additional space margin as percentage. Default is 100 (2x required space).
        This accounts for checkpoint growth during operation.

    .PARAMETER RequiredSpaceGB
        Override automatic calculation with explicit space requirement in GB.

    .OUTPUTS
        PSCustomObject with:
        - HasSufficientSpace: Boolean
        - AvailableGB: Available space in GB
        - RequiredGB: Required space in GB
        - Drive: Drive letter checked
        - Message: Human-readable status
        - Remediation: What to do if insufficient (only if HasSufficientSpace is false)

    .EXAMPLE
        $check = Test-CheckpointDiskSpace -VMName 'FFU-Build' -MarginPercent 50
        if (-not $check.HasSufficientSpace) {
            throw $check.Message
        }

    .NOTES
        Module: FFU.VM
        REL-VM-04: Checkpoint disk space validation
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByVMName')]
        [string]$VMName,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath')]
        [string]$VHDXPath,

        [Parameter(Mandatory = $false)]
        [int]$MarginPercent = 100,

        [Parameter(Mandatory = $false)]
        [double]$RequiredSpaceGB
    )

    try {
        # Get VHDX path from VM if not directly provided
        if ($PSCmdlet.ParameterSetName -eq 'ByVMName') {
            $vm = Get-VM -Name $VMName -ErrorAction Stop
            $vhd = $vm | Get-VMHardDiskDrive | Select-Object -First 1

            if (-not $vhd) {
                return [PSCustomObject]@{
                    HasSufficientSpace = $false
                    AvailableGB = 0
                    RequiredGB = 0
                    Drive = 'Unknown'
                    Message = "No hard disk drives found on VM '$VMName'"
                    Remediation = "Verify VM has a VHDX attached"
                }
            }

            $VHDXPath = $vhd.Path
        }

        # Validate VHDX exists
        if (-not (Test-Path $VHDXPath)) {
            return [PSCustomObject]@{
                HasSufficientSpace = $false
                AvailableGB = 0
                RequiredGB = 0
                Drive = 'Unknown'
                Message = "VHDX not found: $VHDXPath"
                Remediation = "Verify the VHDX file exists at the specified path"
            }
        }

        # Get VHDX size
        $vhdInfo = Get-VHD -Path $VHDXPath -ErrorAction Stop
        $vhdxSizeBytes = $vhdInfo.FileSize

        # If VHDX is dynamic, use the maximum size for calculation (worst case)
        if ($vhdInfo.VhdType -eq 'Dynamic') {
            $vhdxSizeBytes = $vhdInfo.Size
        }

        # Calculate required space with margin
        if ($RequiredSpaceGB) {
            $requiredBytes = $RequiredSpaceGB * 1GB
        }
        else {
            $requiredBytes = $vhdxSizeBytes * (1 + $MarginPercent / 100)
        }

        # Get available space on the drive
        $drive = [System.IO.Path]::GetPathRoot($VHDXPath)
        $driveInfo = [System.IO.DriveInfo]::new($drive)
        $availableBytes = $driveInfo.AvailableFreeSpace

        # Calculate values for output
        $availableGB = [math]::Round($availableBytes / 1GB, 2)
        $requiredGB = [math]::Round($requiredBytes / 1GB, 2)
        $hasSufficientSpace = $availableBytes -ge $requiredBytes

        if ($hasSufficientSpace) {
            return [PSCustomObject]@{
                HasSufficientSpace = $true
                AvailableGB = $availableGB
                RequiredGB = $requiredGB
                Drive = $drive
                Message = "Sufficient disk space: $availableGB GB available, $requiredGB GB required"
                Remediation = $null
            }
        }
        else {
            $shortfallGB = [math]::Round(($requiredBytes - $availableBytes) / 1GB, 2)
            return [PSCustomObject]@{
                HasSufficientSpace = $false
                AvailableGB = $availableGB
                RequiredGB = $requiredGB
                Drive = $drive
                Message = "Insufficient disk space on $drive for checkpoint. Required: $requiredGB GB, Available: $availableGB GB (need $shortfallGB GB more)"
                Remediation = "Free up at least $shortfallGB GB on drive $drive, or move VM storage to a drive with more space"
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            HasSufficientSpace = $false
            AvailableGB = 0
            RequiredGB = 0
            Drive = 'Unknown'
            Message = "Failed to check disk space: $($_.Exception.Message)"
            Remediation = "Verify Hyper-V cmdlets are available and VM exists"
        }
    }
}

function New-FFUVMCheckpoint {
    <#
    .SYNOPSIS
        Creates a VM checkpoint with disk space pre-validation.

    .DESCRIPTION
        Wrapper around Checkpoint-VM that validates disk space before starting
        and cleans up orphaned AVHDX files if the operation fails. This prevents
        the common issue of checkpoint failure leaving partial files.

    .PARAMETER VMName
        Name of the VM to checkpoint.

    .PARAMETER SnapshotName
        Optional name for the checkpoint. Defaults to timestamp-based name.

    .PARAMETER MarginPercent
        Disk space margin for validation. Default is 100 (2x buffer).

    .PARAMETER SkipDiskCheck
        Skip disk space validation (use with caution).

    .OUTPUTS
        The checkpoint object on success.

    .EXAMPLE
        New-FFUVMCheckpoint -VMName 'FFU-Build' -SnapshotName 'Before-Apps'

    .NOTES
        Module: FFU.VM
        REL-VM-04: Checkpoint disk space validation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $false)]
        [string]$SnapshotName,

        [Parameter(Mandatory = $false)]
        [int]$MarginPercent = 100,

        [Parameter(Mandatory = $false)]
        [switch]$SkipDiskCheck
    )

    # Generate default snapshot name if not provided
    if ([string]::IsNullOrEmpty($SnapshotName)) {
        $SnapshotName = "FFU-Checkpoint-$([DateTime]::Now.ToString('yyyyMMdd-HHmmss'))"
    }

    if ($function:WriteLog) {
        WriteLog "Creating checkpoint '$SnapshotName' for VM '$VMName'"
    }

    # Pre-validation: Check disk space
    if (-not $SkipDiskCheck) {
        if ($function:WriteLog) {
            WriteLog "Validating disk space for checkpoint operation..."
        }

        $spaceCheck = Test-CheckpointDiskSpace -VMName $VMName -MarginPercent $MarginPercent

        if (-not $spaceCheck.HasSufficientSpace) {
            $errorMsg = "Cannot create checkpoint: $($spaceCheck.Message)"
            if ($spaceCheck.Remediation) {
                $errorMsg += "`nRemediation: $($spaceCheck.Remediation)"
            }

            if ($function:WriteLog) {
                WriteLog "ERROR: $errorMsg"
            }

            throw $errorMsg
        }

        if ($function:WriteLog) {
            WriteLog "Disk space check passed: $($spaceCheck.AvailableGB) GB available"
        }
    }

    # Get VM info for cleanup if needed
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    $vhdPath = ($vm | Get-VMHardDiskDrive | Select-Object -First 1).Path
    $vmFolder = Split-Path $vhdPath -Parent

    # Track existing AVHDX files before checkpoint (for orphan detection)
    $existingAvhdx = Get-ChildItem -Path $vmFolder -Filter '*.avhdx' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName

    try {
        # Create the checkpoint
        if ($function:WriteLog) {
            WriteLog "Executing Checkpoint-VM..."
        }

        $checkpoint = Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName -ErrorAction Stop -PassThru

        if ($function:WriteLog) {
            WriteLog "Checkpoint '$SnapshotName' created successfully"
        }

        return $checkpoint
    }
    catch {
        $errorMsg = $_.Exception.Message
        if ($function:WriteLog) {
            WriteLog "ERROR: Checkpoint creation failed: $errorMsg"
        }

        # Check for disk space error (0x80070070 = ERROR_DISK_FULL)
        $enhancedMsg = $null
        if ($errorMsg -match '0x80070070' -or $errorMsg -match 'disk full' -or $errorMsg -match 'not enough.*space') {
            if ($function:WriteLog) {
                WriteLog "DISK FULL: Checkpoint failed due to insufficient disk space"
            }

            # Get current space for better error message
            $currentSpace = Test-CheckpointDiskSpace -VMName $VMName -MarginPercent 0
            $enhancedMsg = "Checkpoint failed: Disk full. Available: $($currentSpace.AvailableGB) GB on $($currentSpace.Drive). " +
                           "Free up space and retry, or move VM to a larger drive."

            if ($function:WriteLog) {
                WriteLog "Remediation: $enhancedMsg"
            }
        }

        # Cleanup orphaned AVHDX files
        if ($function:WriteLog) {
            WriteLog "Checking for orphaned checkpoint files..."
        }

        $currentAvhdx = Get-ChildItem -Path $vmFolder -Filter '*.avhdx' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName

        # Find new AVHDX files that appeared during failed operation
        $orphanedFiles = $currentAvhdx | Where-Object { $_ -notin $existingAvhdx }

        foreach ($orphan in $orphanedFiles) {
            try {
                if ($function:WriteLog) {
                    WriteLog "Removing orphaned checkpoint file: $(Split-Path $orphan -Leaf)"
                }
                Remove-Item $orphan -Force -ErrorAction Stop
                if ($function:WriteLog) {
                    WriteLog "Orphaned file removed successfully"
                }
            }
            catch {
                if ($function:WriteLog) {
                    WriteLog "WARNING: Failed to remove orphaned file: $($_.Exception.Message)"
                }
            }
        }

        # Re-throw with enhanced message if disk full
        if ($enhancedMsg) {
            throw $enhancedMsg
        }

        throw
    }
}

#endregion REL-VM-04

# Export module members
Export-ModuleMember -Function @(
    'Get-LocalUserAccount',
    'New-LocalUserAccount',
    'Remove-LocalUserAccount',
    'Set-LocalUserPassword',
    'Set-LocalUserAccountExpiry',
    'Get-VMCreationDiagnostics',
    'Get-OrphanedVMResources',
    'Test-IsTransientVMError',
    'Invoke-VMOperationWithRetry',
    'Test-CheckpointDiskSpace',
    'New-FFUVMCheckpoint',
    'New-FFUVM',
    'Remove-FFUVM',
    'Remove-FFUBuildArtifacts',
    'Remove-FFUVMWithProvider',
    'Get-FFUEnvironment',
    'Set-CaptureFFU',
    'Remove-FFUUserShare',
    'Update-CaptureFFUScript',
    'Remove-SensitiveCaptureMedia'
)