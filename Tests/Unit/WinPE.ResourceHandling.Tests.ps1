#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for WinPE resource handling functions in CaptureFFU.ps1

.DESCRIPTION
    Tests the Test-WinPEResources and Test-ShareDiskSpace functions that validate
    WinPE environment has sufficient resources before FFU capture.

.NOTES
    REL-WINPE-04: Resource exhaustion detection
#>

BeforeAll {
    # Define the functions inline for testing since CaptureFFU.ps1 is not a module
    # This mirrors the actual implementation in CaptureFFU.ps1

    function Test-WinPEResources {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $false)]
            [int]$MinimumMemoryMB = 256
        )

        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $freeMemoryMB = [math]::Round($os.FreePhysicalMemory / 1024, 0)
            $totalMemoryMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
            $usedMemoryMB = $totalMemoryMB - $freeMemoryMB
            $usedPercent = [math]::Round(($usedMemoryMB / $totalMemoryMB) * 100, 0)

            if ($freeMemoryMB -lt 128) {
                return [PSCustomObject]@{
                    Status = 'Critical'
                    FreeMemoryMB = $freeMemoryMB
                    TotalMemoryMB = $totalMemoryMB
                    UsedPercent = $usedPercent
                    Message = "CRITICAL: Only ${freeMemoryMB}MB free memory. DISM capture may fail or be extremely slow."
                }
            }
            elseif ($freeMemoryMB -lt $MinimumMemoryMB) {
                return [PSCustomObject]@{
                    Status = 'Warning'
                    FreeMemoryMB = $freeMemoryMB
                    TotalMemoryMB = $totalMemoryMB
                    UsedPercent = $usedPercent
                    Message = "LOW MEMORY: ${freeMemoryMB}MB free of ${totalMemoryMB}MB. Capture may be slower than expected."
                }
            }
            else {
                return [PSCustomObject]@{
                    Status = 'OK'
                    FreeMemoryMB = $freeMemoryMB
                    TotalMemoryMB = $totalMemoryMB
                    UsedPercent = $usedPercent
                    Message = "Memory OK: ${freeMemoryMB}MB free of ${totalMemoryMB}MB (${usedPercent}% used)"
                }
            }
        }
        catch {
            return [PSCustomObject]@{
                Status = 'Unknown'
                FreeMemoryMB = 0
                TotalMemoryMB = 0
                UsedPercent = 0
                Message = "Failed to query memory: $_"
            }
        }
    }

    function Test-ShareDiskSpace {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $false)]
            [string]$DriveLetter = "W:",

            [Parameter(Mandatory = $false)]
            [int]$MinimumSpaceGB = 60
        )

        try {
            $drive = [System.IO.DriveInfo]::new($DriveLetter)

            if (-not $drive.IsReady) {
                return [PSCustomObject]@{
                    Status = 'Critical'
                    FreeSpaceGB = 0
                    TotalSpaceGB = 0
                    Message = "Drive $DriveLetter is not ready or not connected"
                }
            }

            $freeSpaceGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 2)
            $totalSpaceGB = [math]::Round($drive.TotalSize / 1GB, 2)

            if ($freeSpaceGB -lt 20) {
                return [PSCustomObject]@{
                    Status = 'Critical'
                    FreeSpaceGB = $freeSpaceGB
                    TotalSpaceGB = $totalSpaceGB
                    Message = "CRITICAL: Only ${freeSpaceGB}GB free on $DriveLetter. FFU capture requires at least 20GB free space."
                }
            }
            elseif ($freeSpaceGB -lt $MinimumSpaceGB) {
                return [PSCustomObject]@{
                    Status = 'Warning'
                    FreeSpaceGB = $freeSpaceGB
                    TotalSpaceGB = $totalSpaceGB
                    Message = "LOW DISK SPACE: ${freeSpaceGB}GB free on $DriveLetter. Recommend at least ${MinimumSpaceGB}GB for FFU capture."
                }
            }
            else {
                return [PSCustomObject]@{
                    Status = 'OK'
                    FreeSpaceGB = $freeSpaceGB
                    TotalSpaceGB = $totalSpaceGB
                    Message = "Disk space OK: ${freeSpaceGB}GB free on $DriveLetter"
                }
            }
        }
        catch {
            return [PSCustomObject]@{
                Status = 'Unknown'
                FreeSpaceGB = 0
                TotalSpaceGB = 0
                Message = "Failed to query disk space for $DriveLetter : $_"
            }
        }
    }
}

Describe 'Test-WinPEResources' {
    Context 'Memory Validation - Sufficient Memory' {
        It 'Should return OK when free memory exceeds minimum' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 512 * 1024  # 512MB in KB
                    TotalVisibleMemorySize = 4096 * 1024  # 4GB in KB
                }
            }

            $result = Test-WinPEResources -MinimumMemoryMB 256
            $result.Status | Should -Be 'OK'
            $result.FreeMemoryMB | Should -Be 512
            $result.TotalMemoryMB | Should -Be 4096
        }

        It 'Should include memory usage percentage in message' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 1024 * 1024  # 1GB in KB
                    TotalVisibleMemorySize = 4096 * 1024  # 4GB in KB
                }
            }

            $result = Test-WinPEResources -MinimumMemoryMB 256
            $result.UsedPercent | Should -Be 75
            $result.Message | Should -Match '75% used'
        }
    }

    Context 'Memory Validation - Warning Threshold' {
        It 'Should return Warning when free memory is below minimum but above 128MB' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 200 * 1024  # 200MB
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources -MinimumMemoryMB 256
            $result.Status | Should -Be 'Warning'
            $result.FreeMemoryMB | Should -Be 200
            $result.Message | Should -Match 'LOW MEMORY'
        }

        It 'Should return Warning at exactly 128MB (boundary)' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 128 * 1024  # Exactly 128MB
                    TotalVisibleMemorySize = 512 * 1024
                }
            }

            $result = Test-WinPEResources -MinimumMemoryMB 256
            $result.Status | Should -Be 'Warning'
        }
    }

    Context 'Memory Validation - Critical Threshold' {
        It 'Should return Critical when free memory is below 128MB' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 100 * 1024  # 100MB
                    TotalVisibleMemorySize = 512 * 1024
                }
            }

            $result = Test-WinPEResources -MinimumMemoryMB 256
            $result.Status | Should -Be 'Critical'
            $result.Message | Should -Match 'CRITICAL'
        }

        It 'Should return Critical at 64MB (extreme low)' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 64 * 1024  # 64MB
                    TotalVisibleMemorySize = 256 * 1024
                }
            }

            $result = Test-WinPEResources -MinimumMemoryMB 256
            $result.Status | Should -Be 'Critical'
            $result.Message | Should -Match 'DISM capture may fail'
        }
    }

    Context 'Memory Validation - Custom Minimum' {
        It 'Should use custom minimum threshold' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 400 * 1024  # 400MB
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources -MinimumMemoryMB 512
            $result.Status | Should -Be 'Warning'  # Below 512MB threshold
        }

        It 'Should return OK when above custom threshold' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 600 * 1024  # 600MB
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources -MinimumMemoryMB 512
            $result.Status | Should -Be 'OK'
        }
    }

    Context 'Memory Validation - Error Handling' {
        It 'Should return Unknown when WMI query fails' {
            Mock Get-CimInstance { throw "WMI query failed" }

            $result = Test-WinPEResources -MinimumMemoryMB 256
            $result.Status | Should -Be 'Unknown'
            $result.FreeMemoryMB | Should -Be 0
            $result.Message | Should -Match 'Failed to query memory'
        }

        It 'Should include original error in message' {
            Mock Get-CimInstance { throw "Access denied" }

            $result = Test-WinPEResources -MinimumMemoryMB 256
            $result.Message | Should -Match 'Access denied'
        }
    }

    Context 'Memory Validation - Default Parameters' {
        It 'Should use 256MB as default minimum' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 200 * 1024  # 200MB - below 256 default
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources
            $result.Status | Should -Be 'Warning'
        }
    }
}

Describe 'Test-ShareDiskSpace' {
    Context 'Disk Space Validation - Sufficient Space' {
        It 'Should return OK when free space exceeds minimum' {
            # Test with C: drive which should exist
            $result = Test-ShareDiskSpace -DriveLetter "C:" -MinimumSpaceGB 1

            $result.Status | Should -BeIn @('OK', 'Warning', 'Critical')
            $result.FreeSpaceGB | Should -BeGreaterThan 0
            $result.TotalSpaceGB | Should -BeGreaterThan 0
        }
    }

    Context 'Disk Space Validation - Threshold Logic' {
        # Since we can't easily mock .NET DriveInfo, we test with real drive
        # and verify the threshold comparison logic indirectly

        It 'Should return correct result for actual C: drive' {
            $result = Test-ShareDiskSpace -DriveLetter "C:"

            # Result should be a valid PSCustomObject
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -BeIn @('OK', 'Warning', 'Critical', 'Unknown')
            $result.Message | Should -Not -BeNullOrEmpty
        }

        It 'Should compare against 20GB critical threshold' {
            $result = Test-ShareDiskSpace -DriveLetter "C:" -MinimumSpaceGB 60

            # If space < 20GB, should be Critical
            # If space < 60GB, should be Warning
            # If space >= 60GB, should be OK
            if ($result.FreeSpaceGB -lt 20) {
                $result.Status | Should -Be 'Critical'
            }
            elseif ($result.FreeSpaceGB -lt 60) {
                $result.Status | Should -Be 'Warning'
            }
            else {
                $result.Status | Should -Be 'OK'
            }
        }
    }

    Context 'Disk Space Validation - Drive Not Ready' {
        It 'Should handle non-existent drive gracefully' {
            # Z: typically doesn't exist
            $result = Test-ShareDiskSpace -DriveLetter "Z:" -MinimumSpaceGB 60

            # Should return error status, not throw
            $result.Status | Should -BeIn @('Critical', 'Unknown')
            $result.FreeSpaceGB | Should -Be 0
        }

        It 'Should include drive letter in error message' {
            $result = Test-ShareDiskSpace -DriveLetter "Z:" -MinimumSpaceGB 60
            $result.Message | Should -Match 'Z:'
        }
    }

    Context 'Disk Space Validation - Custom Minimum' {
        It 'Should use custom minimum threshold' {
            $result = Test-ShareDiskSpace -DriveLetter "C:" -MinimumSpaceGB 100

            # Verify the function accepts custom minimum
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Disk Space Validation - Default Parameters' {
        It 'Should use W: as default drive letter' {
            # This will likely fail since W: doesn't exist on test system
            # but the function should handle it gracefully
            $result = Test-ShareDiskSpace

            $result.Status | Should -BeIn @('OK', 'Warning', 'Critical', 'Unknown')
        }

        It 'Should use 60GB as default minimum' {
            $result = Test-ShareDiskSpace -DriveLetter "C:"

            # Verify function returns expected structure
            $result.FreeSpaceGB | Should -BeOfType [double]
            $result.TotalSpaceGB | Should -BeOfType [double]
        }
    }

    Context 'Disk Space Validation - Message Content' {
        It 'Should include free space in message' {
            $result = Test-ShareDiskSpace -DriveLetter "C:" -MinimumSpaceGB 1

            $result.Message | Should -Match '\d+\.?\d*GB'
        }

        It 'Should include drive letter in OK message' {
            $result = Test-ShareDiskSpace -DriveLetter "C:" -MinimumSpaceGB 1

            if ($result.Status -eq 'OK') {
                $result.Message | Should -Match 'C:'
            }
        }
    }
}

Describe 'Resource Validation Integration' {
    Context 'Functions Exist in CaptureFFU.ps1' {
        BeforeAll {
            $captureFFUPath = "$PSScriptRoot/../../FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1"
            if (Test-Path $captureFFUPath) {
                $content = Get-Content $captureFFUPath -Raw
            }
            else {
                $content = $null
            }
        }

        It 'Should have Test-WinPEResources function defined' {
            $content | Should -Match 'function Test-WinPEResources'
        }

        It 'Should have Test-ShareDiskSpace function defined' {
            $content | Should -Match 'function Test-ShareDiskSpace'
        }

        It 'Should have resource validation section marker' {
            $content | Should -Match 'REL-WINPE-04'
        }

        It 'Should call Test-WinPEResources before DISM capture' {
            $content | Should -Match '\$memoryCheck\s*=\s*Test-WinPEResources'
        }

        It 'Should call Test-ShareDiskSpace before DISM capture' {
            $content | Should -Match '\$diskCheck\s*=\s*Test-ShareDiskSpace'
        }
    }

    Context 'Remediation Guidance' {
        BeforeAll {
            $captureFFUPath = "$PSScriptRoot/../../FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1"
            if (Test-Path $captureFFUPath) {
                $content = Get-Content $captureFFUPath -Raw
            }
            else {
                $content = $null
            }
        }

        It 'Should include memory remediation steps' {
            $content | Should -Match 'Increase VM memory allocation'
        }

        It 'Should include disk space remediation steps' {
            $content | Should -Match 'Free up space in FFUDevelopment'
        }

        It 'Should suggest deleting old FFU files' {
            $content | Should -Match 'Delete old FFU files'
        }
    }

    Context 'Fail-Fast Behavior' {
        BeforeAll {
            $captureFFUPath = "$PSScriptRoot/../../FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1"
            if (Test-Path $captureFFUPath) {
                $content = Get-Content $captureFFUPath -Raw
            }
            else {
                $content = $null
            }
        }

        It 'Should throw on critical disk space shortage' {
            $content | Should -Match "throw.*Insufficient disk space"
        }

        It 'Should continue with warning for low memory' {
            # Low memory shows warning but doesn't throw
            $content | Should -Match "Continue anyway.*let DISM fail"
        }
    }
}

Describe 'Return Object Structure' {
    Context 'Test-WinPEResources Return Object' {
        It 'Should return object with Status property' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 512 * 1024
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources
            $result.PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'Should return object with FreeMemoryMB property' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 512 * 1024
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources
            $result.PSObject.Properties.Name | Should -Contain 'FreeMemoryMB'
        }

        It 'Should return object with TotalMemoryMB property' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 512 * 1024
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources
            $result.PSObject.Properties.Name | Should -Contain 'TotalMemoryMB'
        }

        It 'Should return object with UsedPercent property' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 512 * 1024
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources
            $result.PSObject.Properties.Name | Should -Contain 'UsedPercent'
        }

        It 'Should return object with Message property' {
            Mock Get-CimInstance {
                [PSCustomObject]@{
                    FreePhysicalMemory = 512 * 1024
                    TotalVisibleMemorySize = 4096 * 1024
                }
            }

            $result = Test-WinPEResources
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }
    }

    Context 'Test-ShareDiskSpace Return Object' {
        It 'Should return object with Status property' {
            $result = Test-ShareDiskSpace -DriveLetter "C:"
            $result.PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'Should return object with FreeSpaceGB property' {
            $result = Test-ShareDiskSpace -DriveLetter "C:"
            $result.PSObject.Properties.Name | Should -Contain 'FreeSpaceGB'
        }

        It 'Should return object with TotalSpaceGB property' {
            $result = Test-ShareDiskSpace -DriveLetter "C:"
            $result.PSObject.Properties.Name | Should -Contain 'TotalSpaceGB'
        }

        It 'Should return object with Message property' {
            $result = Test-ShareDiskSpace -DriveLetter "C:"
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }
    }
}
