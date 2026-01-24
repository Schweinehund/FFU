#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Test-CaptureTargetDisk function in CaptureFFU.ps1

.DESCRIPTION
    Tests the disk validation logic that prevents accidental capture of wrong disks
    (USB drives, physical hardware) when boot order changes or multiple disks are present.

.NOTES
    CaptureFFU.ps1 is a WinPE script (not module-based), so we define the function
    inline for testing purposes. This mirrors the actual function in CaptureFFU.ps1.
#>

BeforeAll {
    # Define the function inline for testing (WinPE scripts are not module-based)
    # This is a copy of the function from CaptureFFU.ps1 for unit testing
    function Test-CaptureTargetDisk {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $false)]
            [int]$DiskNumber = 0
        )

        try {
            Write-Host "Validating target disk $DiskNumber for FFU capture..." -ForegroundColor Cyan

            $disk = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop |
                Where-Object { $_.DeviceID -eq "\\.\PHYSICALDRIVE$DiskNumber" }

            if (-not $disk) {
                # Get list of available disks for helpful error message
                $availableDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue |
                    ForEach-Object { "$($_.DeviceID) ($($_.Model))" }
                $diskList = if ($availableDisks) { $availableDisks -join ', ' } else { 'None found' }

                return [PSCustomObject]@{
                    Valid = $false
                    DiskInfo = $null
                    Error = "Disk $DiskNumber not found. Available disks: $diskList"
                }
            }

            # Verify it's a virtual disk (Hyper-V or VMware)
            # Hyper-V: "Microsoft Virtual Disk"
            # VMware: "VMware Virtual disk", "VMware, VMware Virtual S"
            if ($disk.Model -notmatch 'Virtual|VMware') {
                return [PSCustomObject]@{
                    Valid = $false
                    DiskInfo = $disk
                    Error = "Disk $DiskNumber is NOT a virtual disk (Model: $($disk.Model)). FFU capture requires a Hyper-V or VMware virtual disk to prevent accidental data loss on physical hardware."
                }
            }

            # Additional info for logging
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            Write-Host "  Disk validated: $($disk.Model), Size: ${sizeGB}GB" -ForegroundColor Green

            return [PSCustomObject]@{
                Valid = $true
                DiskInfo = $disk
                Error = $null
            }
        }
        catch {
            return [PSCustomObject]@{
                Valid = $false
                DiskInfo = $null
                Error = "Failed to query disk information: $_"
            }
        }
    }
}

Describe "Test-CaptureTargetDisk" {

    Context "Virtual Disk Validation" {

        It "Should return Valid=true for Hyper-V virtual disk" {
            # Arrange - Mock Hyper-V virtual disk
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Microsoft Virtual Disk'
                        Size = 53687091200  # 50GB
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeTrue
            $result.Error | Should -BeNullOrEmpty
            $result.DiskInfo | Should -Not -BeNullOrEmpty
            $result.DiskInfo.Model | Should -Be 'Microsoft Virtual Disk'
        }

        It "Should return Valid=true for VMware virtual disk" {
            # Arrange - Mock VMware virtual disk
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'VMware Virtual disk'
                        Size = 53687091200  # 50GB
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeTrue
            $result.Error | Should -BeNullOrEmpty
            $result.DiskInfo.Model | Should -Be 'VMware Virtual disk'
        }

        It "Should return Valid=true for VMware disk with variant model name" {
            # Arrange - Mock VMware with alternate naming
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'VMware, VMware Virtual S SCSI Disk Device'
                        Size = 107374182400  # 100GB
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeTrue
            $result.DiskInfo.Model | Should -Match 'VMware'
        }

        It "Should handle case-insensitive model matching for Virtual" {
            # Arrange - Mock with lowercase 'virtual'
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Some virtual Disk Device'
                        Size = 53687091200
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeTrue -Because "PowerShell -match is case-insensitive by default"
        }

        It "Should handle case-insensitive model matching for VMware" {
            # Arrange - Mock with different casing
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'VMWARE VIRTUAL DISK'
                        Size = 53687091200
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeTrue -Because "PowerShell -match is case-insensitive by default"
        }
    }

    Context "Physical Disk Rejection" {

        It "Should return Valid=false for physical disk (Samsung SSD)" {
            # Arrange - Mock physical SSD
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Samsung SSD 970 EVO Plus 1TB'
                        Size = 1000204886016
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeFalse
            $result.Error | Should -Not -BeNullOrEmpty
            $result.DiskInfo | Should -Not -BeNullOrEmpty
        }

        It "Should return Valid=false for physical disk (WD HDD)" {
            # Arrange - Mock physical HDD
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'WDC WD10EZEX-00WN4A0'
                        Size = 1000204886016
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeFalse
        }

        It "Should return Valid=false for USB flash drive" {
            # Arrange - Mock USB drive
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'SanDisk Ultra USB 3.0'
                        Size = 32212254720  # 30GB
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeFalse
            $result.Error | Should -Match 'NOT a virtual disk'
        }

        It "Should include safety warning in error message for physical disk" {
            # Arrange - Mock physical disk
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'KINGSTON SA400S37240G'
                        Size = 240057409536
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Error | Should -Match 'prevent accidental data loss'
            $result.Error | Should -Match 'physical hardware'
        }

        It "Should include actual model name in error message" {
            # Arrange
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Seagate Barracuda 2TB'
                        Size = 2000398934016
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Error | Should -Match 'Seagate Barracuda 2TB'
        }
    }

    Context "Missing Disk Handling" {

        It "Should return Valid=false for non-existent disk number" {
            # Arrange - Mock with disk 0 but request disk 5
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Microsoft Virtual Disk'
                        Size = 53687091200
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 5

            # Assert
            $result.Valid | Should -BeFalse
            $result.Error | Should -Match 'Disk 5 not found'
            $result.DiskInfo | Should -BeNullOrEmpty
        }

        It "Should list available disks in error message when disk not found" {
            # Arrange - Multiple disks, but not the one requested
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Microsoft Virtual Disk'
                        Size = 53687091200
                    },
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE1'
                        Model = 'USB Storage Device'
                        Size = 16106127360
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 99

            # Assert
            $result.Valid | Should -BeFalse
            $result.Error | Should -Match 'Available disks:'
            $result.Error | Should -Match 'PHYSICALDRIVE0'
            $result.Error | Should -Match 'Microsoft Virtual Disk'
        }

        It "Should handle no disks found scenario" {
            # Arrange - No disks at all
            Mock Get-CimInstance { @() }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeFalse
            $result.Error | Should -Match 'Disk 0 not found'
            $result.Error | Should -Match 'Available disks:'
        }
    }

    Context "Error Handling" {

        It "Should return Valid=false when Get-CimInstance throws" {
            # Arrange - WMI query fails
            Mock Get-CimInstance { throw "WMI service unavailable" }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeFalse
            $result.Error | Should -Match 'Failed to query disk information'
            $result.DiskInfo | Should -BeNullOrEmpty
        }

        It "Should include original error in failure message" {
            # Arrange
            Mock Get-CimInstance { throw "Access denied to WMI namespace" }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Error | Should -Match 'Access denied'
        }
    }

    Context "Default Parameters" {

        It "Should default to disk 0 when no parameter specified" {
            # Arrange
            $mockCalled = $false
            Mock Get-CimInstance {
                $mockCalled = $true
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Microsoft Virtual Disk'
                        Size = 53687091200
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk  # No parameter

            # Assert
            $result.Valid | Should -BeTrue
            $result.DiskInfo.DeviceID | Should -Be '\\.\PHYSICALDRIVE0'
        }
    }

    Context "DiskInfo Property" {

        It "Should return DiskInfo with disk details on valid disk" {
            # Arrange
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Microsoft Virtual Disk'
                        Size = 53687091200
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.DiskInfo | Should -Not -BeNullOrEmpty
            $result.DiskInfo.DeviceID | Should -Be '\\.\PHYSICALDRIVE0'
            $result.DiskInfo.Model | Should -Be 'Microsoft Virtual Disk'
            $result.DiskInfo.Size | Should -Be 53687091200
        }

        It "Should return DiskInfo even when validation fails for physical disk" {
            # Arrange - Physical disk info is still useful for debugging
            Mock Get-CimInstance {
                @(
                    [PSCustomObject]@{
                        DeviceID = '\\.\PHYSICALDRIVE0'
                        Model = 'Samsung SSD 970 EVO'
                        Size = 500107862016
                    }
                )
            }

            # Act
            $result = Test-CaptureTargetDisk -DiskNumber 0

            # Assert
            $result.Valid | Should -BeFalse
            $result.DiskInfo | Should -Not -BeNullOrEmpty
            $result.DiskInfo.Model | Should -Be 'Samsung SSD 970 EVO'
        }
    }
}

Describe "CaptureFFU.ps1 Disk Validation Integration" {

    Context "Function Existence in Source File" {

        It "Should have Test-CaptureTargetDisk function defined in CaptureFFU.ps1" {
            # Arrange
            $captureFFUPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\WinPECaptureFFUFiles\CaptureFFU.ps1"
            $resolvedPath = Resolve-Path $captureFFUPath -ErrorAction SilentlyContinue

            if (-not $resolvedPath) {
                Set-ItResult -Skipped -Because "CaptureFFU.ps1 not found at expected path"
                return
            }

            # Act
            $content = Get-Content $resolvedPath -Raw

            # Assert
            $content | Should -Match 'function Test-CaptureTargetDisk'
        }

        It "Should call Test-CaptureTargetDisk before diskpart in CaptureFFU.ps1" {
            # Arrange
            $captureFFUPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\WinPECaptureFFUFiles\CaptureFFU.ps1"
            $resolvedPath = Resolve-Path $captureFFUPath -ErrorAction SilentlyContinue

            if (-not $resolvedPath) {
                Set-ItResult -Skipped -Because "CaptureFFU.ps1 not found at expected path"
                return
            }

            # Act
            $content = Get-Content $resolvedPath -Raw

            # Find positions
            $diskValidationPos = $content.IndexOf('$diskValidation = Test-CaptureTargetDisk')
            $diskpartPos = $content.IndexOf('diskpart.exe')

            # Assert
            $diskValidationPos | Should -BeGreaterThan 0 -Because "Disk validation call should exist"
            $diskpartPos | Should -BeGreaterThan 0 -Because "Diskpart call should exist"
            $diskValidationPos | Should -BeLessThan $diskpartPos -Because "Disk validation should happen before diskpart"
        }

        It "Should use Get-CimInstance Win32_DiskDrive for WinPE compatibility" {
            # Arrange
            $captureFFUPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\WinPECaptureFFUFiles\CaptureFFU.ps1"
            $resolvedPath = Resolve-Path $captureFFUPath -ErrorAction SilentlyContinue

            if (-not $resolvedPath) {
                Set-ItResult -Skipped -Because "CaptureFFU.ps1 not found at expected path"
                return
            }

            # Act
            $content = Get-Content $resolvedPath -Raw

            # Assert - Should use WinPE-compatible CIM query
            $content | Should -Match 'Get-CimInstance -ClassName Win32_DiskDrive'
        }
    }
}
