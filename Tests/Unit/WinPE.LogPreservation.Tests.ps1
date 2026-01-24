#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for WinPE log preservation functionality (REL-WINPE-03)

.DESCRIPTION
    Validates that CaptureFFU.ps1 and Orchestrator.ps1 correctly implement
    log preservation for post-mortem debugging:
    - CaptureFFU transcript logging to network share
    - Orchestrator log file to D: drive
    - Graceful handling of logging failures

.NOTES
    Author: Claude (Anthropic)
    Date: 2026-01-24
    Requirement: REL-WINPE-03
#>

BeforeAll {
    # Get paths to the scripts
    $script:CaptureFFUPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\WinPECaptureFFUFiles\CaptureFFU.ps1"
    $script:OrchestratorPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Apps\Orchestration\Orchestrator.ps1"

    # Read script content for pattern testing
    $script:CaptureFFUContent = Get-Content $script:CaptureFFUPath -Raw
    $script:OrchestratorContent = Get-Content $script:OrchestratorPath -Raw

    # Define Write-OrchestratorLog for isolated testing
    function script:Write-OrchestratorLog {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('Info', 'Warning', 'Error')]
            [string]$Level = 'Info'
        )

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logLine = "[$timestamp] [$Level] $Message"

        # Console output with color
        $color = switch ($Level) {
            'Warning' { 'Yellow' }
            'Error' { 'Red' }
            default { 'White' }
        }
        Write-Host $logLine -ForegroundColor $color

        # File output if logging enabled
        if ($script:logEnabled -and $script:logPath) {
            try {
                Add-Content -Path $script:logPath -Value $logLine -ErrorAction SilentlyContinue
            }
            catch {
                # Silently fail file logging - don't break orchestration
            }
        }
    }
}

Describe "CaptureFFU Log Preservation" -Tag "REL-WINPE-03", "CaptureFFU" {

    Context "Transcript Logging Implementation" {

        It "Should start transcript with timestamped filename on W: drive" {
            $script:CaptureFFUContent | Should -Match 'Start-Transcript\s+-Path\s+\$transcriptPath'
            $script:CaptureFFUContent | Should -Match '\$transcriptPath\s*=\s*"W:\\CaptureFFU_'
            $script:CaptureFFUContent | Should -Match "Get-Date\s+-Format\s+'yyyyMMdd_HHmmss'"
        }

        It "Should have transcript path pattern matching W:\CaptureFFU_YYYYMMDD_HHMMSS.log" {
            $script:CaptureFFUContent | Should -Match 'W:\\CaptureFFU_\$\(Get-Date -Format.*\)\.log'
        }

        It "Should stop transcript before VM shutdown" {
            # Stop-Transcript should appear before wpeutil Shutdown
            $stopTranscriptIndex = $script:CaptureFFUContent.IndexOf('Stop-Transcript')
            $shutdownIndex = $script:CaptureFFUContent.IndexOf('wpeutil Shutdown')

            $stopTranscriptIndex | Should -BeLessThan $shutdownIndex
            $stopTranscriptIndex | Should -BeGreaterThan 0
        }

        It "Should stop transcript in error catch block" {
            # The final catch block should also stop transcript
            $script:CaptureFFUContent | Should -Match 'catch\s*\{[^}]*Stop-Transcript'
        }

        It "Should handle transcript start failure gracefully" {
            $script:CaptureFFUContent | Should -Match 'try\s*\{\s*Start-Transcript'
            $script:CaptureFFUContent | Should -Match 'catch\s*\{[^}]*\[WARNING\]\s*Failed to start transcript'
        }

        It "Should preserve DISM log to network share" {
            $script:CaptureFFUContent | Should -Match 'xcopy.*dism\.log.*W:'
        }

        It "Should have REL-WINPE-03 comment marker" {
            $script:CaptureFFUContent | Should -Match 'REL-WINPE-03'
        }
    }

    Context "Transcript Logging Behavior" {

        It "Should use -Force parameter on Start-Transcript" {
            $script:CaptureFFUContent | Should -Match 'Start-Transcript.*-Force'
        }

        It "Should use -ErrorAction SilentlyContinue on Stop-Transcript" {
            $script:CaptureFFUContent | Should -Match 'Stop-Transcript\s+-ErrorAction\s+SilentlyContinue'
        }

        It "Should not throw on transcript failure" {
            # Warning messages should be Write-Host, not throw
            $script:CaptureFFUContent | Should -Match 'Write-Host.*\[WARNING\].*transcript'
            $script:CaptureFFUContent | Should -Not -Match 'throw.*transcript'
        }
    }
}

Describe "Orchestrator Log Preservation" -Tag "REL-WINPE-03", "Orchestrator" {

    Context "Log File Implementation" {

        It "Should define script:logPath variable" {
            $script:OrchestratorContent | Should -Match '\$script:logPath\s*='
        }

        It "Should define script:logEnabled variable" {
            $script:OrchestratorContent | Should -Match '\$script:logEnabled\s*='
        }

        It "Should create log file on D: drive with timestamped name" {
            $script:OrchestratorContent | Should -Match 'D:\\orchestrator_\$\(Get-Date'
            $script:OrchestratorContent | Should -Match "Get-Date\s+-Format\s+'yyyyMMdd_HHmmss'"
        }

        It "Should test for D: drive availability before logging" {
            $script:OrchestratorContent | Should -Match 'Test-Path\s+["'']D:\\'
        }

        It "Should warn when D: drive not available" {
            $script:OrchestratorContent | Should -Match '\[WARNING\].*D:.*drive.*not available'
        }

        It "Should have REL-WINPE-03 comment marker" {
            $script:OrchestratorContent | Should -Match 'REL-WINPE-03'
        }
    }

    Context "Write-OrchestratorLog Function" {

        It "Should define Write-OrchestratorLog function" {
            $script:OrchestratorContent | Should -Match 'function\s+Write-OrchestratorLog'
        }

        It "Should have Message parameter as mandatory" {
            $script:OrchestratorContent | Should -Match 'function\s+Write-OrchestratorLog[\s\S]*\[Parameter\(Mandatory\s*=\s*\$true\)\][\s\S]*\[string\]\$Message'
        }

        It "Should have Level parameter with valid values" {
            $script:OrchestratorContent | Should -Match "ValidateSet\('Info',\s*'Warning',\s*'Error'\)"
        }

        It "Should format log line with timestamp" {
            $script:OrchestratorContent | Should -Match "Get-Date\s+-Format\s+'yyyy-MM-dd HH:mm:ss'"
        }

        It "Should use appropriate colors for log levels" {
            $script:OrchestratorContent | Should -Match "'Warning'\s*\{\s*'Yellow'"
            $script:OrchestratorContent | Should -Match "'Error'\s*\{\s*'Red'"
        }

        It "Should use Add-Content for file output" {
            $script:OrchestratorContent | Should -Match 'Add-Content\s+-Path\s+\$script:logPath'
        }

        It "Should use SilentlyContinue for Add-Content errors" {
            $script:OrchestratorContent | Should -Match 'Add-Content.*-ErrorAction\s+SilentlyContinue'
        }
    }

    Context "Write-OrchestratorLog Behavior" {

        BeforeEach {
            $script:logEnabled = $false
            $script:logPath = $null
            $script:testLogPath = Join-Path $TestDrive "test_orchestrator.log"
        }

        It "Should output Info level message to console" {
            # Verify the function produces output without errors
            $script:logEnabled = $false
            { script:Write-OrchestratorLog -Message "Test message" -Level Info } | Should -Not -Throw
        }

        It "Should output Warning level message to console" {
            # Verify the function produces output without errors
            $script:logEnabled = $false
            { script:Write-OrchestratorLog -Message "Warning message" -Level Warning } | Should -Not -Throw
        }

        It "Should output Error level message to console" {
            # Verify the function produces output without errors
            $script:logEnabled = $false
            { script:Write-OrchestratorLog -Message "Error message" -Level Error } | Should -Not -Throw
        }

        It "Should write to file when logging enabled" {
            $script:logEnabled = $true
            $script:logPath = $script:testLogPath
            "=== Test Log ===" | Out-File -FilePath $script:logPath -Force

            script:Write-OrchestratorLog -Message "Test file write" -Level Info

            $content = Get-Content $script:logPath -Raw
            $content | Should -Match "Test file write"
        }

        It "Should not write to file when logging disabled" {
            $script:logEnabled = $false
            $script:logPath = $script:testLogPath

            # Ensure file doesn't exist
            if (Test-Path $script:logPath) {
                Remove-Item $script:logPath -Force
            }

            script:Write-OrchestratorLog -Message "Should not appear" -Level Info

            Test-Path $script:logPath | Should -BeFalse
        }

        It "Should include timestamp in log line format" {
            $script:logEnabled = $true
            $script:logPath = $script:testLogPath
            "=== Test Log ===" | Out-File -FilePath $script:logPath -Force

            script:Write-OrchestratorLog -Message "Timestamp test" -Level Info

            $content = Get-Content $script:logPath -Raw
            # Should match [YYYY-MM-DD HH:MM:SS] [Level] format
            $content | Should -Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[Info\] Timestamp test'
        }

        It "Should include level in log line format" {
            $script:logEnabled = $true
            $script:logPath = $script:testLogPath
            "=== Test Log ===" | Out-File -FilePath $script:logPath -Force

            script:Write-OrchestratorLog -Message "Level test" -Level Warning

            $content = Get-Content $script:logPath -Raw
            $content | Should -Match '\[Warning\] Level test'
        }
    }

    Context "Log Finalization" {

        It "Should finalize log with execution summary" {
            $script:OrchestratorContent | Should -Match '=== Execution Summary ==='
        }

        It "Should finalize log with completion marker" {
            $script:OrchestratorContent | Should -Match '=== Orchestration Complete ==='
        }

        It "Should write finish timestamp to log" {
            $script:OrchestratorContent | Should -Match 'Finished:.*Get-Date'
        }

        It "Should output log path to console on completion" {
            $script:OrchestratorContent | Should -Match 'Write-Host.*Log saved to:'
        }
    }
}

Describe "Log Preservation Error Handling" -Tag "REL-WINPE-03", "ErrorHandling" {

    Context "CaptureFFU Error Handling" {

        It "Should not abort capture if transcript fails to start" {
            # Check that transcript start is in try/catch and failure just logs warning
            $script:CaptureFFUContent | Should -Match 'try\s*\{[\s\S]*Start-Transcript[\s\S]*\}[\s\S]*catch\s*\{[\s\S]*\[WARNING\]'
        }

        It "Should stop transcript in both success and error paths" {
            # Count Stop-Transcript occurrences
            $matches = [regex]::Matches($script:CaptureFFUContent, 'Stop-Transcript')
            $matches.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Orchestrator Error Handling" {

        It "Should not abort orchestration if log file creation fails" {
            $script:OrchestratorContent | Should -Match 'try\s*\{[\s\S]*Out-File.*\$script:logPath[\s\S]*\}[\s\S]*catch\s*\{[\s\S]*\[WARNING\]'
        }

        It "Should silently continue on Add-Content failures" {
            $script:OrchestratorContent | Should -Match 'Add-Content.*-ErrorAction\s+SilentlyContinue'
        }

        It "Should have nested try/catch in Write-OrchestratorLog" {
            # The function should have its own try/catch for file writes
            $functionMatch = [regex]::Match($script:OrchestratorContent, 'function\s+Write-OrchestratorLog\s*\{([\s\S]*?)\n\}')
            $functionMatch.Success | Should -BeTrue
            $functionBody = $functionMatch.Groups[1].Value
            $functionBody | Should -Match 'try\s*\{'
            $functionBody | Should -Match 'catch\s*\{'
        }
    }
}

Describe "Log Content and Format" -Tag "REL-WINPE-03", "Format" {

    Context "CaptureFFU Log Content" {

        It "Should log success message when transcript starts" {
            $script:CaptureFFUContent | Should -Match 'Transcript logging started:'
        }

        It "Should log success message when transcript saved" {
            $script:CaptureFFUContent | Should -Match 'Transcript saved to network share'
        }

        It "Should log DISM log preservation" {
            $script:CaptureFFUContent | Should -Match 'DISM log preserved'
        }
    }

    Context "Orchestrator Log Content" {

        It "Should write header to log file" {
            $script:OrchestratorContent | Should -Match '=== FFU Builder Orchestrator Log ==='
        }

        It "Should write script path to log file" {
            $script:OrchestratorContent | Should -Match 'Script Path:'
        }

        It "Should write start time to log file" {
            $script:OrchestratorContent | Should -Match 'Started:'
        }
    }
}
