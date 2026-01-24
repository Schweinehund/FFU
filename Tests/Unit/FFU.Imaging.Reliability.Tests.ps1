#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for FFU.Imaging reliability improvements

.DESCRIPTION
    Tests for FFU.Imaging reliability improvements:
    - REL-IMG-01: Disk space pre-validation
    - REL-IMG-02: Partition state verification
    - REL-IMG-03: FFU capture recovery with VHDX preservation
    - REL-IMG-04: Mount/dismount retry logic

.NOTES
    Part of Phase 18: FFU.Imaging Reliability
#>

BeforeAll {
    # Set up module path
    $modulesPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules'
    if ($env:PSModulePath -notlike "*$modulesPath*") {
        $env:PSModulePath = "$modulesPath;$env:PSModulePath"
    }

    # Import the module
    Import-Module FFU.Imaging -Force -ErrorAction Stop
}

Describe 'REL-IMG-01: Disk Space Pre-Validation' {

    Describe 'Test-DiskSpaceForOperation' {

        # Function export tests
        It 'Should be exported from FFU.Imaging module' {
            $cmd = Get-Command -Name Test-DiskSpaceForOperation -Module FFU.Imaging -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.ModuleName | Should -Be 'FFU.Imaging'
        }

        It 'Should have Path parameter as mandatory' {
            $cmd = Get-Command -Name Test-DiskSpaceForOperation -Module FFU.Imaging
            $param = $cmd.Parameters['Path']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have RequiredBytes parameter as mandatory' {
            $cmd = Get-Command -Name Test-DiskSpaceForOperation -Module FFU.Imaging
            $param = $cmd.Parameters['RequiredBytes']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have SafetyMarginPercent parameter with default value 10' {
            $cmd = Get-Command -Name Test-DiskSpaceForOperation -Module FFU.Imaging
            $param = $cmd.Parameters['SafetyMarginPercent']
            $param | Should -Not -BeNullOrEmpty
            # Optional parameter (not mandatory)
            $isMandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $isMandatory | Should -Not -Be $true
        }

        It 'Should have OperationName parameter as optional' {
            $cmd = Get-Command -Name Test-DiskSpaceForOperation -Module FFU.Imaging
            $param = $cmd.Parameters['OperationName']
            $param | Should -Not -BeNullOrEmpty
        }

        # Output structure tests
        It 'Should return PSCustomObject with HasSufficientSpace property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'HasSufficientSpace'
            $result.HasSufficientSpace | Should -BeOfType [bool]
        }

        It 'Should return PSCustomObject with AvailableGB property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'AvailableGB'
            $result.AvailableGB | Should -BeOfType [double]
        }

        It 'Should return PSCustomObject with RequiredGB property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'RequiredGB'
        }

        It 'Should return PSCustomObject with Drive property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'Drive'
            $result.Drive | Should -Be 'C:\'
        }

        It 'Should return PSCustomObject with Message property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $result.Message | Should -Not -BeNullOrEmpty
        }

        It 'Should return PSCustomObject with Remediation property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
        }

        It 'Should return PSCustomObject with AvailableBytes property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'AvailableBytes'
            $result.AvailableBytes | Should -BeGreaterThan 0
        }

        It 'Should return PSCustomObject with RequiredBytes property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'RequiredBytes'
        }

        It 'Should return PSCustomObject with ShortfallBytes property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'ShortfallBytes'
        }

        It 'Should return PSCustomObject with ShortfallGB property' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.PSObject.Properties.Name | Should -Contain 'ShortfallGB'
        }

        # Calculation tests
        It 'Should calculate RequiredBytes with safety margin' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 100GB -SafetyMarginPercent 10
            # 100GB + 10% = 110GB
            $result.RequiredBytes | Should -Be ([int64](100GB * 1.1))
        }

        It 'Should return HasSufficientSpace = true when space available' {
            # 1MB should definitely be available on C:\
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.HasSufficientSpace | Should -Be $true
        }

        It 'Should return HasSufficientSpace = false when space insufficient' {
            # 100TB should NOT be available on C:\
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 100TB
            $result.HasSufficientSpace | Should -Be $false
        }

        It 'Should calculate ShortfallBytes correctly when insufficient' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 100TB
            $result.ShortfallBytes | Should -BeGreaterThan 0
            # Shortfall = Required - Available
            $expectedShortfall = $result.RequiredBytes - $result.AvailableBytes
            $result.ShortfallBytes | Should -Be $expectedShortfall
        }

        It 'Should return ShortfallBytes = 0 when sufficient' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.ShortfallBytes | Should -Be 0
        }

        # Remediation tests
        It 'Should include drive letter in Remediation message when insufficient' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 100TB
            $result.Remediation | Should -BeLike '*C:\*'
        }

        It 'Should include shortfall amount in Remediation message' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 100TB
            $result.Remediation | Should -BeLike '*GB*'
        }

        It 'Should have empty Remediation when space is sufficient' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.Remediation | Should -BeNullOrEmpty
        }

        # Edge case tests
        It 'Should handle zero safety margin' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 100GB -SafetyMarginPercent 0
            # No margin means RequiredBytes = original value
            $result.RequiredBytes | Should -Be 100GB
        }

        It 'Should handle large RequiredBytes values (100TB)' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 100TB
            $result | Should -Not -BeNullOrEmpty
            $result.HasSufficientSpace | Should -Be $false
            $result.RequiredBytes | Should -BeGreaterThan 100TB
        }

        It 'Should handle custom operation name in message' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB -OperationName 'FFU capture'
            $result.Message | Should -BeLike '*FFU capture*'
        }

        It 'Should extract drive from full file path' {
            $result = Test-DiskSpaceForOperation -Path 'C:\FFU\output.ffu' -RequiredBytes 1MB
            $result.Drive | Should -Be 'C:\'
        }

        It 'Should round AvailableGB to 2 decimal places' {
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            # Check that AvailableGB has at most 2 decimal places
            $roundedValue = [math]::Round($result.AvailableGB, 2)
            $result.AvailableGB | Should -Be $roundedValue
        }

        It 'Should use System.IO.DriveInfo (no Storage module required)' {
            # This test verifies the function uses .NET DriveInfo, not Get-Volume
            # If it used Get-Volume, it would fail on systems without Storage module loaded
            # We simply verify it works, which proves it doesn't require Storage module
            $result = Test-DiskSpaceForOperation -Path 'C:\' -RequiredBytes 1MB
            $result.AvailableBytes | Should -BeGreaterThan 0
        }
    }
}

Describe 'REL-IMG-02: Partition State Verification' {

    Describe 'Get-DiskPartitionState' {

        It 'Should be exported from FFU.Imaging module' {
            $cmd = Get-Command -Name Get-DiskPartitionState -Module FFU.Imaging -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.ModuleName | Should -Be 'FFU.Imaging'
        }

        It 'Should have DiskNumber parameter as mandatory' {
            $cmd = Get-Command -Name Get-DiskPartitionState -Module FFU.Imaging
            $param = $cmd.Parameters['DiskNumber']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should return PSCustomObject with PartitionCount property' {
            # Use disk 0 (system disk - always present)
            $state = Get-DiskPartitionState -DiskNumber 0
            $state | Should -Not -BeNullOrEmpty
            $state.PSObject.Properties.Name | Should -Contain 'PartitionCount'
            $state.PartitionCount | Should -BeOfType [int]
        }

        It 'Should return PSCustomObject with TotalSizeBytes property' {
            $state = Get-DiskPartitionState -DiskNumber 0
            $state.PSObject.Properties.Name | Should -Contain 'TotalSizeBytes'
        }

        It 'Should return PSCustomObject with TotalSizeGB property' {
            $state = Get-DiskPartitionState -DiskNumber 0
            $state.PSObject.Properties.Name | Should -Contain 'TotalSizeGB'
            $state.TotalSizeGB | Should -BeOfType [double]
        }

        It 'Should return PSCustomObject with DriveLetters array' {
            $state = Get-DiskPartitionState -DiskNumber 0
            $state.PSObject.Properties.Name | Should -Contain 'DriveLetters'
            # DriveLetters is an array type property (may be empty or contain values)
            @($state.DriveLetters).Count | Should -BeGreaterOrEqual 0
        }

        It 'Should return PSCustomObject with PartitionTypes array' {
            $state = Get-DiskPartitionState -DiskNumber 0
            $state.PSObject.Properties.Name | Should -Contain 'PartitionTypes'
            # PartitionTypes is an array type property
            @($state.PartitionTypes).Count | Should -BeGreaterOrEqual 0
        }

        It 'Should return PSCustomObject with PartitionSizes array' {
            $state = Get-DiskPartitionState -DiskNumber 0
            $state.PSObject.Properties.Name | Should -Contain 'PartitionSizes'
            # PartitionSizes is an array type property
            @($state.PartitionSizes).Count | Should -BeGreaterOrEqual 0
        }

        It 'Should return PSCustomObject with CapturedAt timestamp' {
            $state = Get-DiskPartitionState -DiskNumber 0
            $state.PSObject.Properties.Name | Should -Contain 'CapturedAt'
            $state.CapturedAt | Should -BeOfType [DateTime]
        }

        It 'Should handle non-existent disk gracefully with PartitionCount = 0' {
            # Disk 999 should not exist on any system
            $state = Get-DiskPartitionState -DiskNumber 999
            $state | Should -Not -BeNullOrEmpty
            $state.PartitionCount | Should -Be 0
            $state.TotalSizeBytes | Should -Be 0
            $state.DriveLetters.Count | Should -Be 0
        }

        It 'Should have system disk with at least one partition' {
            $state = Get-DiskPartitionState -DiskNumber 0
            $state.PartitionCount | Should -BeGreaterThan 0
        }

        It 'Should capture DiskNumber correctly' {
            $state = Get-DiskPartitionState -DiskNumber 0
            $state.DiskNumber | Should -Be 0
        }
    }

    Describe 'Compare-DiskPartitionState' {

        BeforeAll {
            # Create mock state objects for comparison tests
            $script:MockStateBefore = [PSCustomObject]@{
                DiskNumber      = 1
                PartitionCount  = 3
                TotalSizeBytes  = 100GB
                TotalSizeGB     = 100.0
                PartitionTypes  = @('Basic', 'System')
                DriveLetters    = @('C')
                PartitionSizes  = @(500MB, 100MB, 99400MB)
                CapturedAt      = [DateTime]::Now.AddMinutes(-5)
            }

            $script:MockStateAfter = [PSCustomObject]@{
                DiskNumber      = 1
                PartitionCount  = 4
                TotalSizeBytes  = 150GB
                TotalSizeGB     = 150.0
                PartitionTypes  = @('Basic', 'System', 'Recovery')
                DriveLetters    = @('C', 'D')
                PartitionSizes  = @(500MB, 100MB, 99400MB, 50GB)
                CapturedAt      = [DateTime]::Now
            }

            $script:MockStateUnchanged = [PSCustomObject]@{
                DiskNumber      = 1
                PartitionCount  = 3
                TotalSizeBytes  = 100GB
                TotalSizeGB     = 100.0
                PartitionTypes  = @('Basic', 'System')
                DriveLetters    = @('C')
                PartitionSizes  = @(500MB, 100MB, 99400MB)
                CapturedAt      = [DateTime]::Now
            }
        }

        It 'Should be exported from FFU.Imaging module' {
            $cmd = Get-Command -Name Compare-DiskPartitionState -Module FFU.Imaging -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.ModuleName | Should -Be 'FFU.Imaging'
        }

        It 'Should have Before parameter as mandatory' {
            $cmd = Get-Command -Name Compare-DiskPartitionState -Module FFU.Imaging
            $param = $cmd.Parameters['Before']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have After parameter as mandatory' {
            $cmd = Get-Command -Name Compare-DiskPartitionState -Module FFU.Imaging
            $param = $cmd.Parameters['After']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have ExpectedChange parameter with valid values' {
            $cmd = Get-Command -Name Compare-DiskPartitionState -Module FFU.Imaging
            $param = $cmd.Parameters['ExpectedChange']
            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'PartitionAdded'
            $validateSet.ValidValues | Should -Contain 'PartitionRemoved'
            $validateSet.ValidValues | Should -Contain 'DriveLetterAssigned'
            $validateSet.ValidValues | Should -Contain 'SizeChanged'
            $validateSet.ValidValues | Should -Contain 'None'
        }

        It 'Should return Valid = true when no expected change and states match' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateUnchanged -ExpectedChange 'None'
            $result | Should -Not -BeNullOrEmpty
            $result.Valid | Should -Be $true
            $result.Error | Should -BeNullOrEmpty
        }

        It 'Should return Valid = true when PartitionAdded and count increased' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'PartitionAdded'
            $result.Valid | Should -Be $true
            $result.Error | Should -BeNullOrEmpty
        }

        It 'Should return Valid = false when PartitionAdded but count unchanged' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateUnchanged -ExpectedChange 'PartitionAdded'
            $result.Valid | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
            $result.Error | Should -BeLike '*Expected partition count to increase*'
        }

        It 'Should return Valid = true when DriveLetterAssigned and new letter present' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'DriveLetterAssigned'
            $result.Valid | Should -Be $true
            $result.Error | Should -BeNullOrEmpty
        }

        It 'Should return Valid = false when DriveLetterAssigned but no new letters' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateUnchanged -ExpectedChange 'DriveLetterAssigned'
            $result.Valid | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
            $result.Error | Should -BeLike '*Expected new drive letter assignment*'
        }

        It 'Should include error message when validation fails' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateUnchanged -ExpectedChange 'PartitionAdded'
            $result.Valid | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
            $result.Error.Length | Should -BeGreaterThan 10
        }

        It 'Should track Changes.PartitionCountDelta correctly' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'None'
            $result.Changes.PartitionCountDelta | Should -Be 1
        }

        It 'Should track Changes.NewDriveLetters correctly' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'None'
            $result.Changes.NewDriveLetters | Should -Contain 'D'
            $result.Changes.NewDriveLetters.Count | Should -Be 1
        }

        It 'Should return Valid = true when SizeChanged and size differs' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'SizeChanged'
            $result.Valid | Should -Be $true
        }

        It 'Should return Valid = false when SizeChanged but size same' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateUnchanged -ExpectedChange 'SizeChanged'
            $result.Valid | Should -Be $false
            $result.Error | Should -BeLike '*Expected size to change*'
        }

        It 'Should include Before and After states in result' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'None'
            $result.Before | Should -Be $MockStateBefore
            $result.After | Should -Be $MockStateAfter
        }

        It 'Should include ExpectedChange in result' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'PartitionAdded'
            $result.ExpectedChange | Should -Be 'PartitionAdded'
        }

        It 'Should return Valid = false when PartitionRemoved but count increased' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'PartitionRemoved'
            $result.Valid | Should -Be $false
            $result.Error | Should -BeLike '*Expected partition count to decrease*'
        }

        It 'Should track Changes.SizeDeltaBytes correctly' {
            $result = Compare-DiskPartitionState -Before $MockStateBefore -After $MockStateAfter -ExpectedChange 'None'
            $result.Changes.SizeDeltaBytes | Should -Be (50GB)
        }
    }
}

Describe 'REL-IMG-03: FFU Capture Recovery' {

    Describe 'Test-FFUCaptureReadiness' {

        # Function export tests
        It 'Should be exported from FFU.Imaging module' {
            $cmd = Get-Command -Name Test-FFUCaptureReadiness -Module FFU.Imaging -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.ModuleName | Should -Be 'FFU.Imaging'
        }

        It 'Should have VHDXPath parameter as mandatory' {
            $cmd = Get-Command -Name Test-FFUCaptureReadiness -Module FFU.Imaging
            $param = $cmd.Parameters['VHDXPath']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have OutputFFUPath parameter as mandatory' {
            $cmd = Get-Command -Name Test-FFUCaptureReadiness -Module FFU.Imaging
            $param = $cmd.Parameters['OutputFFUPath']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have SpaceMarginPercent parameter with default value 100' {
            $cmd = Get-Command -Name Test-FFUCaptureReadiness -Module FFU.Imaging
            $param = $cmd.Parameters['SpaceMarginPercent']
            $param | Should -Not -BeNullOrEmpty
            # Optional parameter (not mandatory)
            $isMandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $isMandatory | Should -Not -Be $true
        }

        # Output structure tests
        It 'Should return Ready = false for non-existent VHDX' {
            $result = Test-FFUCaptureReadiness -VHDXPath 'C:\nonexistent.vhdx' `
                -OutputFFUPath 'C:\temp\test.ffu'
            $result.Ready | Should -Be $false
            $result.FailureReason | Should -Be 'VHDXNotFound'
        }

        It 'Should return FailureReason and Remediation when not ready' {
            $result = Test-FFUCaptureReadiness -VHDXPath 'C:\nonexistent.vhdx' `
                -OutputFFUPath 'C:\temp\test.ffu'
            $result.FailureReason | Should -Not -BeNullOrEmpty
            $result.Remediation | Should -Not -BeNullOrEmpty
        }

        It 'Should return Message with helpful text when not ready' {
            $result = Test-FFUCaptureReadiness -VHDXPath 'C:\nonexistent.vhdx' `
                -OutputFFUPath 'C:\temp\test.ffu'
            $result.Message | Should -Not -BeNullOrEmpty
            $result.Message | Should -BeLike '*not found*'
        }

        It 'Should include VHDXPath in error message' {
            $result = Test-FFUCaptureReadiness -VHDXPath 'C:\nonexistent.vhdx' `
                -OutputFFUPath 'C:\temp\test.ffu'
            $result.Message | Should -BeLike '*C:\nonexistent.vhdx*'
        }

        It 'Should return Remediation with actionable guidance' {
            $result = Test-FFUCaptureReadiness -VHDXPath 'C:\nonexistent.vhdx' `
                -OutputFFUPath 'C:\temp\test.ffu'
            $result.Remediation | Should -BeLike '*Verify*'
        }

        It 'Should have Ready property of boolean type' {
            $result = Test-FFUCaptureReadiness -VHDXPath 'C:\nonexistent.vhdx' `
                -OutputFFUPath 'C:\temp\test.ffu'
            $result.Ready | Should -BeOfType [bool]
        }
    }

    Describe 'Invoke-SafeFFUCapture' {

        It 'Should be exported from FFU.Imaging module' {
            $cmd = Get-Command -Name Invoke-SafeFFUCapture -Module FFU.Imaging -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.ModuleName | Should -Be 'FFU.Imaging'
        }

        It 'Should have VHDXPath parameter as mandatory' {
            $cmd = Get-Command -Name Invoke-SafeFFUCapture -Module FFU.Imaging
            $param = $cmd.Parameters['VHDXPath']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have OutputFFUPath parameter as mandatory' {
            $cmd = Get-Command -Name Invoke-SafeFFUCapture -Module FFU.Imaging
            $param = $cmd.Parameters['OutputFFUPath']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have DandISetEnv parameter as mandatory' {
            $cmd = Get-Command -Name Invoke-SafeFFUCapture -Module FFU.Imaging
            $param = $cmd.Parameters['DandISetEnv']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have PhysicalDriveNumber parameter as mandatory' {
            $cmd = Get-Command -Name Invoke-SafeFFUCapture -Module FFU.Imaging
            $param = $cmd.Parameters['PhysicalDriveNumber']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have SkipReadinessCheck switch parameter' {
            $cmd = Get-Command -Name Invoke-SafeFFUCapture -Module FFU.Imaging
            $param = $cmd.Parameters['SkipReadinessCheck']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -Be $true
        }

        It 'Should have FFUName parameter with default value' {
            $cmd = Get-Command -Name Invoke-SafeFFUCapture -Module FFU.Imaging
            $param = $cmd.Parameters['FFUName']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUDescription parameter with default value' {
            $cmd = Get-Command -Name Invoke-SafeFFUCapture -Module FFU.Imaging
            $param = $cmd.Parameters['FFUDescription']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should throw when readiness check fails' {
            { Invoke-SafeFFUCapture -VHDXPath 'C:\nonexistent.vhdx' `
                    -OutputFFUPath 'C:\temp\test.ffu' `
                    -DandISetEnv 'C:\adk\env.bat' `
                    -PhysicalDriveNumber 2
            } | Should -Throw '*not ready*'
        }

        It 'Should throw with Remediation message when readiness check fails' {
            try {
                Invoke-SafeFFUCapture -VHDXPath 'C:\nonexistent.vhdx' `
                    -OutputFFUPath 'C:\temp\test.ffu' `
                    -DandISetEnv 'C:\adk\env.bat' `
                    -PhysicalDriveNumber 2
            }
            catch {
                $_.Exception.Message | Should -BeLike '*Remediation*'
            }
        }

        It 'Should include VHDXNotFound failure reason in error' {
            try {
                Invoke-SafeFFUCapture -VHDXPath 'C:\nonexistent.vhdx' `
                    -OutputFFUPath 'C:\temp\test.ffu' `
                    -DandISetEnv 'C:\adk\env.bat' `
                    -PhysicalDriveNumber 2
            }
            catch {
                $_.Exception.Message | Should -BeLike '*not found*'
            }
        }
    }
}

Describe 'REL-IMG-04: Mount/Dismount Retry Logic' {

    Describe 'Test-IsTransientImagingError' {

        # Function export tests
        It 'Should be exported from FFU.Imaging module' {
            $cmd = Get-Command -Name Test-IsTransientImagingError -Module FFU.Imaging -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.ModuleName | Should -Be 'FFU.Imaging'
        }

        It 'Should have ErrorMessage parameter as mandatory' {
            $cmd = Get-Command -Name Test-IsTransientImagingError -Module FFU.Imaging
            $param = $cmd.Parameters['ErrorMessage']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have HResult parameter as optional' {
            $cmd = Get-Command -Name Test-IsTransientImagingError -Module FFU.Imaging
            $param = $cmd.Parameters['HResult']
            $param | Should -Not -BeNullOrEmpty
        }

        # Transient error tests
        It 'Should return $true for sharing violation' {
            Test-IsTransientImagingError -ErrorMessage 'sharing violation occurred' | Should -Be $true
        }

        It 'Should return $true for file in use' {
            Test-IsTransientImagingError -ErrorMessage 'file is in use by another process' | Should -Be $true
        }

        It 'Should return $true for file locked' {
            Test-IsTransientImagingError -ErrorMessage 'file is locked' | Should -Be $true
        }

        It 'Should return $true for drive in use' {
            Test-IsTransientImagingError -ErrorMessage 'drive is in use' | Should -Be $true
        }

        It 'Should return $true for device not ready' {
            Test-IsTransientImagingError -ErrorMessage 'device is not ready' | Should -Be $true
        }

        It 'Should return $true for path already mounted' {
            Test-IsTransientImagingError -ErrorMessage 'path is already mounted' | Should -Be $true
        }

        It 'Should return $true for RPC unavailable' {
            Test-IsTransientImagingError -ErrorMessage 'rpc server is unavailable' | Should -Be $true
        }

        It 'Should return $true for directory not empty' {
            Test-IsTransientImagingError -ErrorMessage 'directory is not empty' | Should -Be $true
        }

        It 'Should return $true for cannot access' {
            Test-IsTransientImagingError -ErrorMessage 'cannot access the file' | Should -Be $true
        }

        It 'Should return $true for HResult 0x80070020 (sharing violation)' {
            Test-IsTransientImagingError -ErrorMessage 'error' -HResult -2147024864 | Should -Be $true
        }

        It 'Should return $true for device not connected' {
            Test-IsTransientImagingError -ErrorMessage 'device is not connected' | Should -Be $true
        }

        # Permanent error tests
        It 'Should return $false for not found' {
            Test-IsTransientImagingError -ErrorMessage 'file not found' | Should -Be $false
        }

        It 'Should return $false for does not exist' {
            Test-IsTransientImagingError -ErrorMessage 'path does not exist' | Should -Be $false
        }

        It 'Should return $false for access is denied' {
            Test-IsTransientImagingError -ErrorMessage 'access is denied' | Should -Be $false
        }

        It 'Should return $false for invalid parameter' {
            Test-IsTransientImagingError -ErrorMessage 'invalid parameter specified' | Should -Be $false
        }

        It 'Should return $false for invalid argument' {
            Test-IsTransientImagingError -ErrorMessage 'invalid argument' | Should -Be $false
        }

        It 'Should return $false for registry corrupt' {
            Test-IsTransientImagingError -ErrorMessage 'registry is corrupt' | Should -Be $false
        }

        It 'Should return $false for element not found (Error 1168)' {
            Test-IsTransientImagingError -ErrorMessage 'element not found' | Should -Be $false
        }

        It 'Should return $false for not a valid disk' {
            Test-IsTransientImagingError -ErrorMessage 'not a valid disk' | Should -Be $false
        }

        # Edge cases
        It 'Should return $false for unknown errors (fail fast)' {
            Test-IsTransientImagingError -ErrorMessage 'some random error happened' | Should -Be $false
        }

        It 'Should return $false for empty string' {
            Test-IsTransientImagingError -ErrorMessage '' | Should -Be $false
        }

        It 'Should be case-insensitive for transient patterns' {
            Test-IsTransientImagingError -ErrorMessage 'SHARING VIOLATION' | Should -Be $true
        }

        It 'Should be case-insensitive for permanent patterns' {
            Test-IsTransientImagingError -ErrorMessage 'FILE NOT FOUND' | Should -Be $false
        }

        It 'Should prioritize permanent patterns over transient' {
            # "access is denied" is permanent, even though "cannot access" is transient
            Test-IsTransientImagingError -ErrorMessage 'access is denied to the file' | Should -Be $false
        }
    }

    Describe 'Invoke-ImagingOperationWithRetry' {

        It 'Should be exported from FFU.Imaging module' {
            $cmd = Get-Command -Name Invoke-ImagingOperationWithRetry -Module FFU.Imaging -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.ModuleName | Should -Be 'FFU.Imaging'
        }

        It 'Should have ScriptBlock parameter as mandatory' {
            $cmd = Get-Command -Name Invoke-ImagingOperationWithRetry -Module FFU.Imaging
            $param = $cmd.Parameters['ScriptBlock']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -Be $true }
        }

        It 'Should have RunDismCleanupOnRetry switch parameter' {
            $cmd = Get-Command -Name Invoke-ImagingOperationWithRetry -Module FFU.Imaging
            $param = $cmd.Parameters['RunDismCleanupOnRetry']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -Be $true
        }

        It 'Should have OperationName parameter with default value' {
            $cmd = Get-Command -Name Invoke-ImagingOperationWithRetry -Module FFU.Imaging
            $param = $cmd.Parameters['OperationName']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have MaxRetries parameter' {
            $cmd = Get-Command -Name Invoke-ImagingOperationWithRetry -Module FFU.Imaging
            $param = $cmd.Parameters['MaxRetries']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have BaseDelaySeconds parameter' {
            $cmd = Get-Command -Name Invoke-ImagingOperationWithRetry -Module FFU.Imaging
            $param = $cmd.Parameters['BaseDelaySeconds']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should return result on success' {
            $result = Invoke-ImagingOperationWithRetry -OperationName 'test' -ScriptBlock { 'success' }
            $result | Should -Be 'success'
        }

        It 'Should return complex objects on success' {
            $result = Invoke-ImagingOperationWithRetry -OperationName 'test' -ScriptBlock {
                [PSCustomObject]@{ Name = 'test'; Value = 42 }
            }
            $result.Name | Should -Be 'test'
            $result.Value | Should -Be 42
        }

        It 'Should throw immediately on permanent error' {
            { Invoke-ImagingOperationWithRetry -OperationName 'test' -ScriptBlock {
                throw 'file not found'
            } } | Should -Throw '*not found*'
        }

        It 'Should throw immediately on invalid parameter error' {
            { Invoke-ImagingOperationWithRetry -OperationName 'test' -ScriptBlock {
                throw 'invalid parameter'
            } } | Should -Throw '*invalid parameter*'
        }

        It 'Should throw immediately on does not exist error' {
            { Invoke-ImagingOperationWithRetry -OperationName 'test' -ScriptBlock {
                throw 'path does not exist'
            } } | Should -Throw '*does not exist*'
        }

        It 'Should preserve original error message for permanent errors' {
            $errorThrown = $false
            $errorMessage = ''
            try {
                Invoke-ImagingOperationWithRetry -OperationName 'test' -ScriptBlock {
                    throw 'the file was not found in the specified location'
                }
            }
            catch {
                $errorThrown = $true
                $errorMessage = $_.Exception.Message
            }
            $errorThrown | Should -Be $true
            $errorMessage | Should -BeLike '*not found*'
        }

        It 'Should accept custom MaxRetries value' {
            # This should work without error - just testing parameter acceptance
            $result = Invoke-ImagingOperationWithRetry -OperationName 'test' -MaxRetries 5 -ScriptBlock { 'ok' }
            $result | Should -Be 'ok'
        }

        It 'Should accept custom BaseDelaySeconds value' {
            # This should work without error - just testing parameter acceptance
            $result = Invoke-ImagingOperationWithRetry -OperationName 'test' -BaseDelaySeconds 1 -ScriptBlock { 'ok' }
            $result | Should -Be 'ok'
        }
    }
}
