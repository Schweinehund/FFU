---
phase: 25-ffuui-core-reliability
plan: 03
subsystem: ui-job-errors
tags: [wpf, error-handling, background-jobs, messaging, remediation]

dependency-graph:
  requires: [25-01, 25-02]
  provides: [job-error-extraction, error-type-classification, messaging-integration]
  affects: [BuildFFUVM_UI.ps1]

tech-stack:
  added: []
  patterns: [priority-based-extraction, error-classification, message-queue-inspection]

key-files:
  created:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.JobErrors.psm1
    - Tests/Unit/FFUUI.Core.JobErrors.Tests.ps1
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1
    - FFUDevelopment/BuildFFUVM_UI.ps1
    - FFUDevelopment/version.json

decisions:
  - id: DEC-2503-01
    title: PSObject parameter type for testability
    choice: Use PSObject instead of System.Management.Automation.Job
    reason: Allows mock job objects in Pester tests without real job creation
    alternatives: [Real job creation in tests, Reflection-based mocking]

  - id: DEC-2503-02
    title: Priority-based error extraction
    choice: Check sources in priority order - MessagingContext first
    reason: FFU.Messaging queue contains the richest structured error info
    alternatives: [Check all sources and merge, Use only job error streams]

  - id: DEC-2503-03
    title: Error type classification via pattern matching
    choice: Regex patterns for DISM/Hyper-V/Network/Disk/Permission errors
    reason: Simple and reliable for common error categories
    alternatives: [Exception type checking, Error code lookup tables]

metrics:
  duration: 25m
  completed: 2026-01-24
---

# Phase 25 Plan 03: Job Failure Context Extraction Summary

Intelligent error extraction from background job failures using FFU.Messaging infrastructure.

## Objective

Replace the ad-hoc error extraction logic in BuildFFUVM_UI.ps1 (which often resulted in "An unknown error occurred") with intelligent extraction that pulls structured errors from FFU.Messaging queue. When the build job fails, the messaging context contains Error/Critical level messages with source, details, and potentially remediation guidance.

## Completed Tasks

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Create FFUUI.Core.JobErrors module | 45eeece | FFUUI.Core.JobErrors.psm1 |
| 2 | Integrate JobErrors into BuildFFUVM_UI.ps1 | c18f6f9 | FFUUI.Core.psd1, BuildFFUVM_UI.ps1 |
| 3 | Create Pester tests | 2b796b4 | FFUUI.Core.JobErrors.Tests.ps1 |

## Technical Implementation

### Get-FFUJobError Function

Main function to extract errors from background jobs using priority ordering:

```powershell
$errorInfo = Get-FFUJobError -Job $currentJob `
    -MessagingContext $script:uiState.Data.messagingContext `
    -LogPath $mainLogPath

Show-FFUError -Severity 'Error' `
    -Title $errorInfo.Title `
    -Description $errorInfo.Message `
    -Remediation $errorInfo.Remediation `
    -LogPath $errorInfo.LogPath
```

**Priority Order:**
1. **MessagingContext (Priority 1)** - Check FFU.Messaging queue for Error/Critical level messages
2. **Job.ChildJobs (Priority 2)** - Check ThreadJob child job error streams
3. **Job.JobStateInfo.Reason (Priority 3)** - Standard PowerShell job failure reason
4. **Job.Error stream (Priority 4)** - Direct job error stream
5. **Fallback (Priority 5)** - Generic message with remediation hints

### ConvertTo-FFUErrorInfo Function

Converts FFUMessage objects from the queue to standardized error info:

```powershell
[PSCustomObject]@{
    ErrorType         = 'DISMError'        # Classified from message or Data
    Title             = 'Build Failed: ...'
    Message           = 'Full error text'
    Source            = 'FFU.Imaging'       # Module that raised the error
    Remediation       = @('Step 1', 'Step 2')
    Details           = @{ ExitCode = 1234 }
    LogPath           = 'C:\FFUDevelopment\FFUDevelopment.log'
    OriginalException = $null
}
```

### Get-ErrorTypeFromMessage Function

Classifies errors based on message patterns:

| Pattern | ErrorType |
|---------|-----------|
| DISM, Mount, WIM, image | DISMError |
| Hyper-V, VM, Virtual | HypervisorError |
| network, connection, share, SMB | NetworkError |
| disk, space, storage | DiskError |
| permission, access denied, 0x80070005 | PermissionError |
| (default) | BuildError |

### BuildFFUVM_UI.ps1 Integration

Replaced 30+ lines of ad-hoc error extraction with structured approach:

**Before:**
```powershell
if ($hasErrors) {
    $reason = $null
    if ($null -ne $jobErrors -and $jobErrors.Count -gt 0) {
        $reason = ($jobErrors | Select-Object -Last 1).ToString()
    }
    # ... 25 more lines of fallback attempts ...
    [System.Windows.MessageBox]::Show($errorMsg, "Build Error", "OK", "Error")
}
```

**After:**
```powershell
if ($hasErrors) {
    $errorInfo = Get-FFUJobError -Job $currentJob `
        -MessagingContext $script:uiState.Data.messagingContext `
        -LogPath $mainLogPath

    Show-FFUError -Severity 'Error' `
        -Title $errorInfo.Title `
        -Description $errorInfo.Message `
        -Remediation $errorInfo.Remediation `
        -LogPath $errorInfo.LogPath `
        -Details $errorInfo.Details

    Reset-FFUUIToIdle -State $script:uiState -StatusMessage "Build failed. Check log for details."
}
```

## Deviations from Plan

None - plan executed exactly as written.

## Test Coverage

**57 Pester tests covering:**

- Module Import (4 tests)
- Get-ErrorTypeFromMessage (20 tests) - All error type classifications
- ConvertTo-FFUErrorInfo (12 tests) - Message extraction and formatting
- Get-FFUJobError (21 tests):
  - MessagingContext priority (7 tests)
  - Job error fallbacks (4 tests)
  - Null/empty handling (3 tests)
  - LogPath handling (2 tests)
  - Error type classification (2 tests)
  - Return structure (3 tests)

All tests pass, PSScriptAnalyzer clean.

## Version Changes

| Component | Old Version | New Version | Notes |
|-----------|-------------|-------------|-------|
| FFUUI.Core | 0.0.15 | 0.0.16 | Added JobErrors module |
| FFU Builder | 1.8.37 | 1.8.38 | PATCH for module change |

## Verification Results

- Module imports without error
- Get-FFUJobError, ConvertTo-FFUErrorInfo exported
- 57/57 Pester tests pass
- PSScriptAnalyzer: 0 warnings/errors
- BuildFFUVM_UI.ps1 uses Get-FFUJobError and Show-FFUError

## Next Phase Readiness

**Ready for 25-04:** Load-Time Config Validation
- Job error extraction complete
- Error display infrastructure in place (Show-FFUError from 25-02)
- UI state recovery functional (Reset-FFUUIToIdle from 25-01)
- No blockers identified

## Files Created

1. **FFUUI.Core.JobErrors.psm1** (417 lines)
   - Get-FFUJobError: Priority-based error extraction
   - ConvertTo-FFUErrorInfo: FFUMessage to error info conversion
   - Get-ErrorTypeFromMessage: Pattern-based error classification

2. **FFUUI.Core.JobErrors.Tests.ps1** (494 lines)
   - Comprehensive test coverage
   - Mock job and messaging context helpers
   - Tests all priority levels and edge cases

## Addresses Requirements

- **REL-UI-05**: Job failures show specific error message, not "An unknown error occurred"
- **REL-UI-05**: Job failures include error source (which module/phase failed)
- **REL-UI-05**: Job failures include remediation when available from FFU.Messaging
- **REL-UI-05**: Structured errors from FFU.Messaging are extracted and displayed
