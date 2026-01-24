#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Updates reliability features (REL-UPD-*)

.DESCRIPTION
    Tests for reliability improvements in FFU.Updates module:
    - REL-UPD-01: Catalog Query Retry (Invoke-CatalogQueryWithRetry)
    - REL-UPD-02: MSU Download Integrity Validation (Test-MSUIntegrity, Save-KB integration)
    - REL-UPD-03: Update Application Isolation (Invoke-UpdatesWithIsolation)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Updates.Reliability.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Updates'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'

    # Add Modules folder to PSModulePath for proper dependency resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    Get-Module -Name 'FFU.Updates', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (required dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
    }

    if (-not (Test-Path "$ModulePath\FFU.Updates.psd1")) {
        throw "FFU.Updates module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Updates.psd1" -Force -ErrorAction Stop

    # Get the module object for accessing private functions
    $script:UpdatesModule = Get-Module -Name 'FFU.Updates'
}

AfterAll {
    Get-Module -Name 'FFU.Updates', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# REL-UPD-01: Catalog Query Retry Tests
# =============================================================================

Describe 'REL-UPD-01: Catalog Query Retry' -Tag 'Unit', 'FFU.Updates', 'Reliability', 'REL-UPD-01' {

    Context 'Invoke-CatalogQueryWithRetry function' {

        It 'Should be defined in the module (internal function)' {
            # Read the module file directly to check for internal function
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match 'function Invoke-CatalogQueryWithRetry'
        }

        It 'Should have correct parameters defined' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for required parameters (using [\s\S] to match across lines)
            $moduleContent | Should -Match '\[Parameter\(Mandatory\)\][\s\S]*?\[scriptblock\]\$Query'
            $moduleContent | Should -Match '\[string\]\$OperationName'
            $moduleContent | Should -Match '\[int\]\$MaxRetries'
            $moduleContent | Should -Match '\[int\]\$BaseDelaySeconds'
        }

        It 'Should implement exponential backoff with jitter' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for exponential backoff calculation
            $moduleContent | Should -Match '\[math\]::Pow\(2, \$attempt - 1\)'

            # Check for jitter
            $moduleContent | Should -Match 'Get-Random -Minimum 0 -Maximum 3'
        }

        It 'Should use ThreadJob-safe logging pattern' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for $function:WriteLog pattern within Invoke-CatalogQueryWithRetry
            $functionMatch = [regex]::Match($moduleContent, 'function Invoke-CatalogQueryWithRetry[\s\S]*?(?=\r?\nfunction )')
            if ($functionMatch.Success) {
                $functionContent = $functionMatch.Value
                $functionContent | Should -Match '\$function:WriteLog'
            } else {
                # If it's the last function, match to end of module
                $moduleContent | Should -Match 'Invoke-CatalogQueryWithRetry[\s\S]*\$function:WriteLog'
            }
        }

        It 'Should log warning messages with attempt count' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for attempt count in warning message
            $moduleContent | Should -Match 'attempt \$attempt of \$MaxRetries'
        }

        It 'Should throw after MaxRetries exhausted' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for throw at the end
            $moduleContent | Should -Match 'throw \$lastError'
        }

        It 'Should log error when all retries exhausted' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for error message about exhausted retries
            $moduleContent | Should -Match 'failed after \$MaxRetries attempts'
        }

        It 'Should have default MaxRetries of 3' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            $moduleContent | Should -Match '\[int\]\$MaxRetries = 3'
        }

        It 'Should have default BaseDelaySeconds of 10' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            $moduleContent | Should -Match '\[int\]\$BaseDelaySeconds = 10'
        }
    }

    Context 'Get-ProductsCab retry integration' {

        It 'Should use Invoke-CatalogQueryWithRetry for catalog search' {
            # Verify the function uses the retry wrapper for the main search request
            $source = (Get-Command Get-ProductsCab -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match 'Invoke-CatalogQueryWithRetry'
            $source | Should -Match "OperationName.*'Windows Update catalog search'"
        }

        It 'Should use Invoke-CatalogQueryWithRetry for metadata lookup' {
            $source = (Get-Command Get-ProductsCab -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match "OperationName.*'Update metadata lookup'"
        }

        It 'Should use reduced retries for metadata lookup (non-critical)' {
            $source = (Get-Command Get-ProductsCab -Module 'FFU.Updates').ScriptBlock.ToString()
            # Metadata lookup should have MaxRetries 2 (less than default 3)
            $source | Should -Match 'MaxRetries 2.*Update metadata lookup|Update metadata lookup.*MaxRetries 2'
        }

        It 'Should have REL-UPD-01 comment marker' {
            $source = (Get-Command Get-ProductsCab -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match 'REL-UPD-01'
        }
    }

    Context 'Documentation' {

        It 'Should have synopsis in function documentation' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Find the function and check for .SYNOPSIS
            $moduleContent | Should -Match 'function Invoke-CatalogQueryWithRetry[\s\S]*?\.SYNOPSIS'
        }

        It 'Should document REL-UPD-01 in description' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for REL-UPD-01 reference in documentation
            $moduleContent | Should -Match 'REL-UPD-01.*Catalog Query Retry'
        }

        It 'Should have examples in function documentation' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for .EXAMPLE in documentation
            $moduleContent | Should -Match 'function Invoke-CatalogQueryWithRetry[\s\S]*?\.EXAMPLE'
        }
    }

    Context 'Error Handling Behavior' {

        It 'Should return result immediately on first success (no retry needed)' {
            # Verify the function structure returns immediately on success
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check that result is returned after query execution
            $moduleContent | Should -Match 'result = & \$Query[\s\S]*?return \$result'
        }

        It 'Should store last error for re-throw' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check that error is captured
            $moduleContent | Should -Match '\$lastError = \$_'
        }

        It 'Should only sleep when more retries remain' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for conditional sleep
            $moduleContent | Should -Match 'if \(\$attempt -lt \$MaxRetries\)[\s\S]*?Start-Sleep'
        }
    }
}

# =============================================================================
# REL-UPD-02: MSU Download Integrity Validation Tests
# =============================================================================

Describe 'REL-UPD-02: MSU Download Integrity Validation' -Tag 'Unit', 'FFU.Updates', 'Reliability', 'REL-UPD-02' {

    BeforeAll {
        # Create test directory
        $script:TestDir = Join-Path $TestDrive 'MSUTests'
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
    }

    Context 'Test-MSUIntegrity function' {

        It 'Should be exported from FFU.Updates module' {
            Get-Command -Name 'Test-MSUIntegrity' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory FilePath parameter' {
            $cmd = Get-Command -Name 'Test-MSUIntegrity' -Module 'FFU.Updates'
            $param = $cmd.Parameters['FilePath']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_.Mandatory -eq $true } | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional ExpectedHash parameter' {
            $cmd = Get-Command -Name 'Test-MSUIntegrity' -Module 'FFU.Updates'
            $param = $cmd.Parameters['ExpectedHash']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional ExpectedSize parameter' {
            $cmd = Get-Command -Name 'Test-MSUIntegrity' -Module 'FFU.Updates'
            $param = $cmd.Parameters['ExpectedSize']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional MinimumSizeBytes parameter with default 1MB' {
            $cmd = Get-Command -Name 'Test-MSUIntegrity' -Module 'FFU.Updates'
            $param = $cmd.Parameters['MinimumSizeBytes']
            $param | Should -Not -BeNullOrEmpty

            # Check default value
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match '\[int64\]\$MinimumSizeBytes = 1MB'
        }

        It 'Should return Valid=false when file does not exist' {
            $result = Test-MSUIntegrity -FilePath 'C:\NonExistent\fake.msu'

            $result.Valid | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
            $result.Errors[0] | Should -Match 'not found'
        }

        It 'Should return Valid=false for empty file (0 bytes)' {
            $emptyFile = Join-Path $script:TestDir 'empty.msu'
            New-Item -Path $emptyFile -ItemType File -Force | Out-Null

            $result = Test-MSUIntegrity -FilePath $emptyFile

            $result.Valid | Should -Be $false
            $result.Errors | Should -Contain 'File is empty (0 bytes) - indicates download corruption or incomplete transfer'
            $result.FileSize | Should -Be 0
        }

        It 'Should return Valid=false for file below minimum size' {
            $smallFile = Join-Path $script:TestDir 'small.msu'
            # Create a 100KB file (below 1MB default minimum)
            $content = [byte[]]::new(100KB)
            [System.IO.File]::WriteAllBytes($smallFile, $content)

            $result = Test-MSUIntegrity -FilePath $smallFile

            $result.Valid | Should -Be $false
            $result.Errors[0] | Should -Match 'suspiciously small'
        }

        It 'Should return Valid=true for file meeting minimum size' {
            $normalFile = Join-Path $script:TestDir 'normal.msu'
            # Create a 2MB file (above 1MB minimum)
            $content = [byte[]]::new(2MB)
            [System.IO.File]::WriteAllBytes($normalFile, $content)

            $result = Test-MSUIntegrity -FilePath $normalFile

            $result.Valid | Should -Be $true
            $result.FileSize | Should -Be 2MB
        }

        It 'Should accept custom MinimumSizeBytes' {
            $smallFile = Join-Path $script:TestDir 'custom.msu'
            # Create a 500KB file
            $content = [byte[]]::new(500KB)
            [System.IO.File]::WriteAllBytes($smallFile, $content)

            # With default 1MB minimum - should fail
            $resultFail = Test-MSUIntegrity -FilePath $smallFile
            $resultFail.Valid | Should -Be $false

            # With 100KB minimum - should pass
            $resultPass = Test-MSUIntegrity -FilePath $smallFile -MinimumSizeBytes 100KB
            $resultPass.Valid | Should -Be $true
        }

        It 'Should validate expected size when provided' {
            $testFile = Join-Path $script:TestDir 'sizecheck.msu'
            $content = [byte[]]::new(2MB)
            [System.IO.File]::WriteAllBytes($testFile, $content)

            # Correct size - should pass
            $resultCorrect = Test-MSUIntegrity -FilePath $testFile -ExpectedSize 2MB
            $resultCorrect.Valid | Should -Be $true

            # Wrong size - should fail
            $resultWrong = Test-MSUIntegrity -FilePath $testFile -ExpectedSize 3MB
            $resultWrong.Valid | Should -Be $false
            $resultWrong.Errors[0] | Should -Match 'Size mismatch'
        }

        It 'Should compute and return ActualHash when ExpectedHash provided' {
            $testFile = Join-Path $script:TestDir 'hashtest.msu'
            $content = [byte[]]::new(2MB)
            # Fill with non-zero content for realistic hash
            for ($i = 0; $i -lt $content.Length; $i++) {
                $content[$i] = [byte]($i % 256)
            }
            [System.IO.File]::WriteAllBytes($testFile, $content)

            # Calculate expected hash
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $fs = [System.IO.File]::OpenRead($testFile)
            $hashBytes = $sha256.ComputeHash($fs)
            $fs.Close()
            $sha256.Dispose()
            $expectedHash = [Convert]::ToBase64String($hashBytes)

            $result = Test-MSUIntegrity -FilePath $testFile -ExpectedHash $expectedHash

            $result.Valid | Should -Be $true
            $result.ActualHash | Should -Be $expectedHash
        }

        It 'Should return Valid=false on hash mismatch' {
            $testFile = Join-Path $script:TestDir 'hashmismatch.msu'
            $content = [byte[]]::new(2MB)
            [System.IO.File]::WriteAllBytes($testFile, $content)

            $wrongHash = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='

            $result = Test-MSUIntegrity -FilePath $testFile -ExpectedHash $wrongHash

            $result.Valid | Should -Be $false
            $result.Errors | Where-Object { $_ -match 'Hash mismatch' } | Should -Not -BeNullOrEmpty
            $result.ActualHash | Should -Not -BeNullOrEmpty
            $result.ActualHash | Should -Not -Be $wrongHash
        }

        It 'Should return structured result object with all expected properties' {
            $testFile = Join-Path $script:TestDir 'structure.msu'
            $content = [byte[]]::new(2MB)
            [System.IO.File]::WriteAllBytes($testFile, $content)

            $result = Test-MSUIntegrity -FilePath $testFile

            $result.PSObject.Properties.Name | Should -Contain 'Valid'
            $result.PSObject.Properties.Name | Should -Contain 'FilePath'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'FileSize'
            $result.PSObject.Properties.Name | Should -Contain 'ActualHash'

            $result.FilePath | Should -Be $testFile
        }

        It 'Should return empty Errors list when validation passes' {
            $testFile = Join-Path $script:TestDir 'noerrors.msu'
            $content = [byte[]]::new(2MB)
            [System.IO.File]::WriteAllBytes($testFile, $content)

            $result = Test-MSUIntegrity -FilePath $testFile

            $result.Valid | Should -Be $true
            $result.Errors.Count | Should -Be 0
        }

        It 'Should return ActualHash as null when ExpectedHash not provided' {
            $testFile = Join-Path $script:TestDir 'nohash.msu'
            $content = [byte[]]::new(2MB)
            [System.IO.File]::WriteAllBytes($testFile, $content)

            $result = Test-MSUIntegrity -FilePath $testFile

            $result.ActualHash | Should -BeNullOrEmpty
        }
    }

    Context 'Save-KB integrity integration' {

        It 'Should have MaxValidationRetries parameter' {
            $cmd = Get-Command -Name 'Save-KB' -Module 'FFU.Updates'
            $param = $cmd.Parameters['MaxValidationRetries']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have MaxValidationRetries default of 2' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match '\[int\]\$MaxValidationRetries = 2'
        }

        It 'Should have Invoke-ValidatedDownload helper in Save-KB' {
            $source = (Get-Command Save-KB -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match 'function Invoke-ValidatedDownload'
        }

        It 'Should call Test-MSUIntegrity in Save-KB' {
            $source = (Get-Command Save-KB -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match 'Test-MSUIntegrity'
        }

        It 'Should have REL-UPD-02 comment marker in Save-KB' {
            $source = (Get-Command Save-KB -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match 'REL-UPD-02'
        }

        It 'Should delete corrupted file before re-download' {
            $source = (Get-Command Save-KB -Module 'FFU.Updates').ScriptBlock.ToString()
            # Check that file is deleted when validation fails
            $source | Should -Match 'Remove-Item.*Force'
            $source | Should -Match 'Deleting corrupted file'
        }

        It 'Should log validation success with file size' {
            $source = (Get-Command Save-KB -Module 'FFU.Updates').ScriptBlock.ToString()
            $source | Should -Match 'Integrity validation passed.*Size'
        }

        It 'Should document REL-UPD-02 in Save-KB description' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for REL-UPD-02 in Save-KB documentation
            $saveKbMatch = [regex]::Match($moduleContent, 'function Save-KB[\s\S]*?\.DESCRIPTION[\s\S]*?(?=\.PARAMETER)')
            if ($saveKbMatch.Success) {
                $saveKbMatch.Value | Should -Match 'REL-UPD-02'
            } else {
                throw "Could not find Save-KB function with .DESCRIPTION"
            }
        }
    }

    Context 'Documentation' {

        It 'Should have synopsis in Test-MSUIntegrity documentation' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match 'function Test-MSUIntegrity[\s\S]*?\.SYNOPSIS'
        }

        It 'Should document REL-UPD-02 in Test-MSUIntegrity description' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Find Test-MSUIntegrity and check for REL-UPD-02
            $functionMatch = [regex]::Match($moduleContent, 'function Test-MSUIntegrity[\s\S]*?\.DESCRIPTION[\s\S]*?(?=\.PARAMETER)')
            if ($functionMatch.Success) {
                $functionMatch.Value | Should -Match 'REL-UPD-02'
            } else {
                throw "Could not find Test-MSUIntegrity function with .DESCRIPTION"
            }
        }

        It 'Should have examples in Test-MSUIntegrity documentation' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match 'function Test-MSUIntegrity[\s\S]*?\.EXAMPLE'
        }

        It 'Should have OutputType attribute on Test-MSUIntegrity' {
            $cmd = Get-Command -Name 'Test-MSUIntegrity' -Module 'FFU.Updates'
            $cmd.OutputType | Should -Not -BeNullOrEmpty
        }

        It 'Should document hash validation pattern from Get-ProductsCab' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw
            $moduleContent | Should -Match 'Get-ProductsCab'
        }
    }
}

# =============================================================================
# REL-UPD-03: Update Application Isolation Tests
# =============================================================================

Describe 'REL-UPD-03: Update Application Isolation' -Tag 'Unit', 'FFU.Updates', 'Reliability', 'REL-UPD-03' {

    Context 'Invoke-UpdatesWithIsolation function' {

        BeforeAll {
            # Mock Add-WindowsPackageWithRetry to control behavior
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates { }
        }

        It 'Should be exported from FFU.Updates module' {
            Get-Command -Name 'Invoke-UpdatesWithIsolation' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory MountPath parameter' {
            $cmd = Get-Command -Name 'Invoke-UpdatesWithIsolation' -Module 'FFU.Updates'
            $param = $cmd.Parameters['MountPath']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_.Mandatory -eq $true } | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory Updates parameter' {
            $cmd = Get-Command -Name 'Invoke-UpdatesWithIsolation' -Module 'FFU.Updates'
            $param = $cmd.Parameters['Updates']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_.Mandatory -eq $true } | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional StopOnCriticalFailure switch' {
            $cmd = Get-Command -Name 'Invoke-UpdatesWithIsolation' -Module 'FFU.Updates'
            $param = $cmd.Parameters['StopOnCriticalFailure']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -Be $true
        }

        It 'Should return structured result with TotalCount, SuccessCount, FailureCount' {
            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'CU'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.TotalCount | Should -Be 1
            $result.SuccessCount | Should -Be 1
            $result.FailureCount | Should -Be 0
            $result.AllSucceeded | Should -Be $true
        }

        It 'Should continue after non-required update failure' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates {
                param($Path, $PackagePath)
                if ($PackagePath -match 'fail') {
                    throw "Simulated failure"
                }
            }

            $updates = @(
                [PSCustomObject]@{ Name = 'FailUpdate'; Path = 'C:\test\fail.msu'; Type = 'CU'; Required = $false }
                [PSCustomObject]@{ Name = 'SuccessUpdate'; Path = 'C:\test\success.msu'; Type = 'NET'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.SuccessCount | Should -Be 1
            $result.FailureCount | Should -Be 1
            $result.AllSucceeded | Should -Be $false
            $result.HasCriticalFailure | Should -Be $false

            # Verify second update was attempted
            $result.Results | Where-Object Name -eq 'SuccessUpdate' |
                Select-Object -ExpandProperty Status | Should -Be 'Success'
        }

        It 'Should set HasCriticalFailure when required update fails' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates {
                throw "Simulated failure"
            }

            $updates = @(
                [PSCustomObject]@{ Name = 'RequiredUpdate'; Path = 'C:\test\required.msu'; Type = 'CU'; Required = $true }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.HasCriticalFailure | Should -Be $true
        }

        It 'Should stop on critical failure when StopOnCriticalFailure is set' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates {
                throw "Simulated failure"
            }

            $updates = @(
                [PSCustomObject]@{ Name = 'RequiredUpdate'; Path = 'C:\test\required.msu'; Type = 'CU'; Required = $true }
                [PSCustomObject]@{ Name = 'AfterUpdate'; Path = 'C:\test\after.msu'; Type = 'NET'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates -StopOnCriticalFailure

            $result.Results.Count | Should -Be 1  # Only first update attempted
            $result.HasCriticalFailure | Should -Be $true
        }

        It 'Should track duration for each update' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates { }

            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'CU'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.Results[0].Duration | Should -Not -BeNullOrEmpty
            $result.Results[0].Duration | Should -BeOfType [double]
        }

        It 'Should capture error message on failure' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates {
                throw "Specific error message"
            }

            $updates = @(
                [PSCustomObject]@{ Name = 'FailUpdate'; Path = 'C:\test\fail.msu'; Type = 'CU'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.Results[0].Error | Should -Match 'Specific error message'
        }

        It 'Should include Path property in results' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates { }

            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'CU'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.Results[0].Path | Should -Be 'C:\test\update1.msu'
        }

        It 'Should include Type property in results' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates { }

            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'NET'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.Results[0].Type | Should -Be 'NET'
        }

        It 'Should handle empty updates array gracefully' {
            $updates = @()

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.TotalCount | Should -Be 0
            $result.SuccessCount | Should -Be 0
            $result.FailureCount | Should -Be 0
            $result.AllSucceeded | Should -Be $true
        }

        It 'Should process all updates when none are required and some fail' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates {
                param($Path, $PackagePath)
                # Fail every other update
                if ($PackagePath -match 'update[13]') {
                    throw "Simulated failure"
                }
            }

            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'CU'; Required = $false }
                [PSCustomObject]@{ Name = 'Update2'; Path = 'C:\test\update2.msu'; Type = 'NET'; Required = $false }
                [PSCustomObject]@{ Name = 'Update3'; Path = 'C:\test\update3.msu'; Type = 'SSU'; Required = $false }
                [PSCustomObject]@{ Name = 'Update4'; Path = 'C:\test\update4.msu'; Type = 'DEF'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.TotalCount | Should -Be 4
            $result.Results.Count | Should -Be 4  # All 4 were attempted
            $result.SuccessCount | Should -Be 2
            $result.FailureCount | Should -Be 2
        }

        It 'Should continue after required update fails without StopOnCriticalFailure' {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates {
                param($Path, $PackagePath)
                if ($PackagePath -match 'required') {
                    throw "Required update failed"
                }
            }

            $updates = @(
                [PSCustomObject]@{ Name = 'RequiredUpdate'; Path = 'C:\test\required.msu'; Type = 'CU'; Required = $true }
                [PSCustomObject]@{ Name = 'OptionalUpdate'; Path = 'C:\test\optional.msu'; Type = 'NET'; Required = $false }
            )

            # Without -StopOnCriticalFailure, should continue
            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.Results.Count | Should -Be 2  # Both updates were attempted
            $result.HasCriticalFailure | Should -Be $true
            $result.Results[1].Status | Should -Be 'Success'
        }
    }

    Context 'Documentation' {

        It 'Should have synopsis in function documentation' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Find the function and check for .SYNOPSIS
            $moduleContent | Should -Match 'function Invoke-UpdatesWithIsolation[\s\S]*?\.SYNOPSIS'
        }

        It 'Should document REL-UPD-03 in description' {
            $psm1Path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content $psm1Path -Raw

            # Check for REL-UPD-03 reference in documentation
            $moduleContent | Should -Match 'REL-UPD-03'
        }

        It 'Should have OutputType attribute' {
            $cmd = Get-Command -Name 'Invoke-UpdatesWithIsolation' -Module 'FFU.Updates'
            $cmd.OutputType | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Result Structure' {

        BeforeAll {
            Mock Add-WindowsPackageWithRetry -ModuleName FFU.Updates { }
        }

        It 'Should return PSCustomObject' {
            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'CU'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result | Should -BeOfType [PSCustomObject]
        }

        It 'Should have Results property as collection' {
            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'CU'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.Results | Should -Not -BeNullOrEmpty
            # Results should be enumerable
            $result.Results.Count | Should -BeGreaterOrEqual 1
        }

        It 'Should have boolean AllSucceeded property' {
            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'CU'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.AllSucceeded | Should -BeOfType [bool]
        }

        It 'Should have boolean HasCriticalFailure property' {
            $updates = @(
                [PSCustomObject]@{ Name = 'Update1'; Path = 'C:\test\update1.msu'; Type = 'CU'; Required = $false }
            )

            $result = Invoke-UpdatesWithIsolation -MountPath 'W:\' -Updates $updates

            $result.HasCriticalFailure | Should -BeOfType [bool]
        }
    }
}

# =============================================================================
# Module Version Verification
# =============================================================================

Describe 'FFU.Updates Module Version' -Tag 'Unit', 'FFU.Updates', 'Version' {

    It 'Should have version 1.0.6 or higher (includes REL-UPD-01, REL-UPD-02, REL-UPD-03)' {
        $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psd1'
        $manifest = Test-ModuleManifest -Path $ManifestPath
        $version = [Version]$manifest.Version
        $version | Should -BeGreaterOrEqual ([Version]'1.0.6')
    }

    It 'Should have REL-UPD-01 mentioned in release notes' {
        $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psd1'
        $manifestContent = Get-Content $ManifestPath -Raw
        $manifestContent | Should -Match 'REL-UPD-01'
    }

    It 'Should have REL-UPD-02 mentioned in release notes' {
        $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psd1'
        $manifestContent = Get-Content $ManifestPath -Raw
        $manifestContent | Should -Match 'REL-UPD-02'
    }

    It 'Should export Test-MSUIntegrity (REL-UPD-02)' {
        $cmd = Get-Command -Name 'Test-MSUIntegrity' -Module 'FFU.Updates' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }

    It 'Should export Invoke-UpdatesWithIsolation (REL-UPD-03)' {
        $cmd = Get-Command -Name 'Invoke-UpdatesWithIsolation' -Module 'FFU.Updates' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }
}
