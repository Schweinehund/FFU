#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Drivers OEM driver logging (Phase 33)
.DESCRIPTION
    Verifies all OEM driver operations use WriteLog with structured [OEM][Model][Operation]
    prefixes for file logging, while preserving Write-Host for console visibility (dual output).
    Covers requirements LOG-01 through LOG-06.
.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.Logging.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths relative to test file location (same pattern as FFU.Drivers.Tests.ps1)
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Drivers'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Remove modules if loaded
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.Drivers module
    Import-Module "$ModulePath\FFU.Drivers.psd1" -Force -ErrorAction Stop

    # Store source file path for static analysis tests
    $Script:SourceFile = Join-Path $ModulesPath 'FFU.Drivers\FFU.Drivers.psm1'
    $Script:SourceContent = Get-Content -Path $Script:SourceFile -Raw
}

AfterAll {
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# LOG-02: Invoke-DriverDownloadWithRetry Logging
# =============================================================================

Describe 'Invoke-DriverDownloadWithRetry Logging' -Tag 'Unit', 'FFU.Drivers', 'Logging' {

    Context 'Structured Logging Pattern' {
        BeforeAll {
            $module = Get-Module -Name 'FFU.Drivers'
            $Script:RetryFunc = $module.Invoke({
                Get-Item function:Invoke-DriverDownloadWithRetry -ErrorAction SilentlyContinue
            })
        }

        It 'Should log success via WriteLog with [OEM][Download] structured prefix' {
            $funcBody = $Script:RetryFunc.ScriptBlock.ToString()
            $funcBody | Should -Match '\[OEM\]\[Download\].*completed successfully'
        }

        It 'Should log success via both WriteLog and Write-Verbose (dual output)' {
            $funcBody = $Script:RetryFunc.ScriptBlock.ToString()
            # Verify WriteLog and Write-Verbose appear near each other for success path
            $funcBody | Should -Match 'WriteLog \$successMsg'
            $funcBody | Should -Match 'Write-Verbose \$successMsg'
        }

        It 'Should log retry warning via WriteLog with WARNING prefix and [OEM][Download]' {
            $funcBody = $Script:RetryFunc.ScriptBlock.ToString()
            $funcBody | Should -Match 'WriteLog "WARNING: \$warningMsg"'
        }

        It 'Should log retry warning via both WriteLog and Write-Verbose (dual output)' {
            $funcBody = $Script:RetryFunc.ScriptBlock.ToString()
            $funcBody | Should -Match 'WriteLog "WARNING: \$warningMsg"'
            $funcBody | Should -Match 'Write-Verbose "WARNING: \$warningMsg"'
        }

        It 'Should include attempt number and max retries in warning messages' {
            $funcBody = $Script:RetryFunc.ScriptBlock.ToString()
            $funcBody | Should -Match 'failed \(attempt \$attempt of \$MaxRetries\)'
        }

        It 'Should include source URL in warning messages for diagnostics' {
            $funcBody = $Script:RetryFunc.ScriptBlock.ToString()
            $funcBody | Should -Match '\[Source: \$Source\]'
        }

        It 'Should log all retries exhausted via WriteLog with ERROR prefix' {
            $funcBody = $Script:RetryFunc.ScriptBlock.ToString()
            $funcBody | Should -Match 'WriteLog "ERROR: \$errorMsg"'
        }

        It 'Should include failed attempt count in exhaustion message' {
            $funcBody = $Script:RetryFunc.ScriptBlock.ToString()
            $funcBody | Should -Match 'failed after \$MaxRetries attempts'
        }
    }
}

# =============================================================================
# LOG-03: Get-DriverExtractionResult Logging
# =============================================================================

Describe 'Get-DriverExtractionResult Logging' -Tag 'Unit', 'FFU.Drivers', 'Logging' {

    Context 'HP Exit Code 1168 Structured Prefix' {
        BeforeAll {
            $module = Get-Module -Name 'FFU.Drivers'
        }

        It 'Should include [HP] structured prefix in 1168 message' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 1168 -DriverName 'TestDriver'
            })
            $result.Message | Should -Match '\[HP\]\[TestDriver\]\[Extract\]'
        }

        It 'Should include ERROR_NOT_FOUND description in 1168 message' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 1168 -DriverName 'TestDriver'
            })
            $result.Message | Should -Match 'ERROR_NOT_FOUND'
        }

        It 'Should include remediation steps in 1168 message' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 1168 -DriverName 'TestDriver'
            })
            $result.Message | Should -Match 'Remediation:'
            $result.Message | Should -Match 'Verify extracted files'
        }

        It 'Should include FFUDevelopment.log reference in 1168 remediation' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 1168 -DriverName 'TestDriver'
            })
            $result.Message | Should -Match 'FFUDevelopment\.log'
        }

        It 'Should include driver name in 1168 message' {
            $result = $module.Invoke({
                Get-DriverExtractionResult -Vendor 'HP' -ExitCode 1168 -DriverName 'sp99999'
            })
            $result.Message | Should -Match 'sp99999'
        }
    }
}

# =============================================================================
# LOG-01: HP Driver Selection Logging
# =============================================================================

Describe 'HP Driver Selection Logging' -Tag 'Unit', 'FFU.Drivers', 'Logging' {
    # Static analysis tests: Verify WriteLog call patterns exist in source code.
    # HP model selection functions have complex dependencies that make mock-based
    # testing impractical. Source pattern verification ensures structured prefixes are used.

    It 'Should have structured [HP][Model][Selection] prefix in model-not-found WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[HP\].*\[Selection\].*Model not found'
    }

    It 'Should have structured [HP][Model][Selection] prefix in model prompting WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[HP\].*\[Selection\].*Prompting user'
    }

    It 'Should have structured [HP] prefix in cab URL failure WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[HP\].*\[Download\].*cab URL.*not accessible'
    }

    It 'Should have structured [HP] prefix in SystemID-not-found WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[HP\].*\[Selection\].*SystemID not found'
    }

    It 'Should have structured [HP] prefix in invalid selection WriteLog calls' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[HP\].*\[Selection\].*Invalid'
    }
}

# =============================================================================
# LOG-01: Lenovo Driver Selection Logging
# =============================================================================

Describe 'Lenovo Driver Selection Logging' -Tag 'Unit', 'FFU.Drivers', 'Logging' {
    # Static analysis tests: Verify WriteLog call patterns exist in Lenovo source code.

    It 'Should have structured [Lenovo] prefix in no-machine-types-found WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[Lenovo\].*\[Selection\].*No machine types found'
    }

    It 'Should have structured [Lenovo] prefix in parameter guidance WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[Lenovo\].*\[Selection\].*Enter a valid model'
    }

    It 'Should have structured [Lenovo] prefix in catalog URL failure WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[Lenovo\].*\[Download\].*catalog URL.*not accessible'
    }

    It 'Should have structured [Lenovo] prefix in download failure WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Lenovo\].*\[Download\].*Failed to download'
    }

    It 'Should have structured [Lenovo] prefix in extraction failure WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Lenovo\].*\[Extract\].*Failed to extract'
    }
}

# =============================================================================
# LOG-02, LOG-05: Dell Catalog Failure Logging
# =============================================================================

Describe 'Dell Catalog Failure Logging' -Tag 'Unit', 'FFU.Drivers', 'Logging' {
    # Static analysis tests: Verify Dell catalog failure logging uses structured prefixes.

    It 'Should have structured [Dell] prefix in catalog download failure WriteLog calls' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Dell\].*\[Download\].*Catalog download failed'
    }

    It 'Should have structured [Dell] prefix in cab extraction failure WriteLog calls' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Dell\].*\[Download\].*Failed to extract catalog cab'
    }

    It 'Should have structured [Dell] prefix in missing XML after extraction WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Dell\].*\[Download\].*Catalog XML not found after extraction'
    }

    It 'Should have structured [Dell] prefix in XML parse failure WriteLog call' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Dell\].*\[Download\].*Failed to parse catalog XML'
    }

    It 'Should include remediation with build impact in Dell catalog failures' {
        $Script:SourceContent | Should -Match 'WriteLog.*Remediation.*build will continue without Dell drivers'
    }

    It 'Should include FFUDevelopment.log reference in Dell remediation messages' {
        $Script:SourceContent | Should -Match 'WriteLog.*\[Dell\].*FFUDevelopment\.log'
    }

    It 'Should indicate build continues without Dell drivers in all 4 failure paths' {
        $continueMatches = [regex]::Matches($Script:SourceContent, 'WriteLog.*\[Dell\].*build will continue without Dell drivers')
        $continueMatches.Count | Should -BeGreaterOrEqual 4 -Because 'all 4 Dell catalog failure paths should indicate build continues'
    }
}

# =============================================================================
# LOG-06: No Console-Only Driver Logging
# =============================================================================

Describe 'No Console-Only Driver Logging' -Tag 'Unit', 'FFU.Drivers', 'Logging' {
    # Verifies Phase 33 removed all $function:WriteLog guard patterns and that
    # WriteLog is used directly (not conditionally) throughout the module.

    It 'Should not have $function:WriteLog guard pattern (removed in Phase 33)' {
        $Script:SourceContent | Should -Not -Match '\$function:WriteLog'
    }

    It 'Should have more WriteLog calls than Write-Host calls in driver functions' {
        $writeLogCount = (Select-String -Path $Script:SourceFile -Pattern 'WriteLog' -AllMatches).Matches.Count
        $writeHostCount = (Select-String -Path $Script:SourceFile -Pattern 'Write-Host' -AllMatches).Matches.Count
        $writeLogCount | Should -BeGreaterThan $writeHostCount
    }

    It 'Should have significant WriteLog usage (minimum 50 calls)' {
        $writeLogCount = (Select-String -Path $Script:SourceFile -Pattern 'WriteLog' -AllMatches).Matches.Count
        $writeLogCount | Should -BeGreaterOrEqual 50 -Because 'comprehensive driver logging requires many WriteLog calls'
    }
}

# =============================================================================
# LOG-04: Dual Output Preservation
# =============================================================================

Describe 'Dual Output Pattern Preservation' -Tag 'Unit', 'FFU.Drivers', 'Logging' {
    # Verifies that Write-Host calls are preserved alongside WriteLog for console visibility.
    # The dual output pattern ensures interactive users see key messages while
    # all messages are also written to FFUDevelopment.log via WriteLog.

    It 'Should preserve Write-Host calls for console visibility' {
        $writeHostCount = (Select-String -Path $Script:SourceFile -Pattern 'Write-Host' -AllMatches).Matches.Count
        $writeHostCount | Should -BeGreaterThan 0 -Because 'Write-Host is preserved for interactive console output'
    }

    It 'Should use Write-Verbose alongside WriteLog in retry function (dual output)' {
        $module = Get-Module -Name 'FFU.Drivers'
        $retryFunc = $module.Invoke({
            Get-Item function:Invoke-DriverDownloadWithRetry -ErrorAction SilentlyContinue
        })
        $funcBody = $retryFunc.ScriptBlock.ToString()
        $funcBody | Should -Match 'WriteLog'
        $funcBody | Should -Match 'Write-Verbose'
    }
}

# =============================================================================
# LOG-05: Error Path Remediation Messages
# =============================================================================

Describe 'Error Path Remediation Messages' -Tag 'Unit', 'FFU.Drivers', 'Logging' {
    # Verifies all error paths include actionable remediation messages via WriteLog.

    It 'Should include remediation in HP exit code 1168 messages' {
        $module = Get-Module -Name 'FFU.Drivers'
        $result = $module.Invoke({
            Get-DriverExtractionResult -Vendor 'HP' -ExitCode 1168 -DriverName 'TestDriver'
        })
        $result.Message | Should -Match 'Remediation:'
    }

    It 'Should include remediation in Dell catalog download failure messages' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Dell\].*Remediation:.*network connectivity'
    }

    It 'Should include remediation in Dell cab extraction failure messages' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Dell\].*Remediation:.*corrupt or truncated'
    }

    It 'Should include remediation in Dell missing XML failure messages' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Dell\].*Remediation:.*may not contain the expected XML'
    }

    It 'Should include remediation in Dell XML parse failure messages' {
        $Script:SourceContent | Should -Match 'WriteLog.*WARNING.*\[Dell\].*Remediation:.*malformed or empty'
    }

    It 'Should include log file pointer in remediation messages' {
        # Verify FFUDevelopment.log is referenced in remediation
        $logRefCount = [regex]::Matches($Script:SourceContent, 'WriteLog.*FFUDevelopment\.log').Count
        $logRefCount | Should -BeGreaterOrEqual 5 -Because 'multiple error paths should reference the log file'
    }
}
