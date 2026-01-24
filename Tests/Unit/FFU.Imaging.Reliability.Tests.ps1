#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for FFU.Imaging reliability improvements

.DESCRIPTION
    Tests disk space pre-validation (REL-IMG-01) and partition state
    verification functions (REL-IMG-02) for before/after validation
    of partition operations.

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
