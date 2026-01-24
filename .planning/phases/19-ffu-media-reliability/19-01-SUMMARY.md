---
phase: 19-ffu-media-reliability
plan: 01
subsystem: media
tags: [reliability, pre-validation, winpe, adk]

dependency-graph:
  requires:
    - FFU.Imaging (Test-DiskSpaceForOperation)
    - FFU.ADK (Test-ADKPrerequisites)
    - FFU.Preflight (Test-FFUWimMount)
  provides:
    - Test-WinPEMediaReadiness function
    - REL-MED-01 implementation
  affects:
    - 19-02 (DISM/ADK error classification)
    - 19-03 (WinPE creation resilience)

tech-stack:
  added: []
  patterns:
    - Pre-operation validation with fail-fast
    - Structured result objects with remediation
    - ThreadJob-compatible function availability check

files:
  key-files:
    created: []
    modified:
      - FFUDevelopment/Modules/FFU.Media/FFU.Media.psm1
      - FFUDevelopment/Modules/FFU.Media/FFU.Media.psd1
      - FFUDevelopment/version.json
      - Tests/Unit/FFU.Media.Reliability.Tests.ps1

decisions:
  - id: DECISION-19-01-01
    title: "InvokeCommand.GetCommand for ThreadJob compatibility"
    choice: "Use $ExecutionContext.InvokeCommand.GetCommand instead of Get-Command"
    rationale: "Ensures function availability checks work in ThreadJob runspaces where Get-Command may fail"
    impact: "Consistent behavior in both interactive and background job contexts"

metrics:
  duration: "~25 minutes"
  completed: "2026-01-23"
---

# Phase 19 Plan 01: WinPE Dependency Pre-Validation Summary

**REL-MED-01:** WinPE creation validates all dependencies before starting operations.

## One-Liner

Test-WinPEMediaReadiness validates ADK, WIMMount, architecture tools, and disk space before WinPE media creation, with structured fail-fast results and remediation guidance.

## What Was Built

### Test-WinPEMediaReadiness Function

**Location:** `FFUDevelopment/Modules/FFU.Media/FFU.Media.psm1`

**Signature:**
```powershell
function Test-WinPEMediaReadiness {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture,

        [Parameter(Mandatory)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory)]
        [string]$ADKPath,

        [switch]$CreateCapture,
        [switch]$CreateDeploy,
        [string]$CaptureISOPath,
        [string]$DeployISOPath
    )
}
```

**Validation Sequence (fail-fast):**
1. ADK Prerequisites - Calls Test-ADKPrerequisites
2. WIMMount Service - Calls Test-FFUWimMount
3. Architecture Tools - Verifies oscdimg.exe and winpe.wim for target architecture
4. WinPE Working Space - 15GB required via Test-DiskSpaceForOperation
5. ISO Output Space - 1GB per ISO if paths provided

**Return Structure:**
```powershell
[PSCustomObject]@{
    Ready         = $true/$false
    FailureReason = $null/'ADKValidation'/'WIMMount'/'ArchitectureMissing'/'InsufficientSpace'/'ISOSpaceInsufficient'
    Message       = "Human-readable status"
    Remediation   = "Steps to fix (from underlying check)"
    Details       = @{
        ADKPath      = $ADKPath
        Architecture = $Architecture
        ADKVersion   = $adkResult.ADKVersion
        Checks       = @{ ADK = ...; WIMMount = ...; Space = ... }
    }
}
```

### Integration in New-PEMedia

Test-WinPEMediaReadiness is called at the start of New-PEMedia, before any DISM cleanup operations. If validation fails, the function throws with clear error message and remediation guidance.

### Test Coverage

**File:** `Tests/Unit/FFU.Media.Reliability.Tests.ps1`

- 31 new tests for REL-MED-01
- Function export and parameter validation
- Output structure verification
- ADK path failure handling
- Architecture folder mapping (amd64 vs arm64)
- oscdimg.exe and winpe.wim missing scenarios
- Fail-fast behavior verification

Total test file: 102 tests, all passing.

## Commits

| Hash | Message |
|------|---------|
| 7b68bfe | feat(19-01): add Test-WinPEMediaReadiness function |
| b000d53 | chore(19-01): bump FFU.Media to v1.7.0 and main to v1.8.26 |

## Version Updates

| Component | Old Version | New Version |
|-----------|-------------|-------------|
| FFU.Media | 1.6.0 | 1.7.0 |
| Main FFU Builder | 1.8.25 | 1.8.26 |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added FFU.Imaging module dependency**
- **Found during:** Task 1
- **Issue:** Test-DiskSpaceForOperation requires FFU.Imaging module
- **Fix:** Added FFU.Imaging to RequiredModules in FFU.Media.psd1
- **Files modified:** FFU.Media.psd1
- **Commit:** 7b68bfe

**2. [Rule 3 - Blocking] WriteLog stub for tests**
- **Found during:** Task 2
- **Issue:** Test-ADKPrerequisites internally calls WriteLog which isn't available in test context
- **Fix:** Added global WriteLog stub in test BeforeAll block
- **Files modified:** FFU.Media.Reliability.Tests.ps1
- **Commit:** Part of test file

### Concurrent Work Integration

During execution, other plans in Phase 19 were also being executed (19-02, 19-04). The following was already done when this plan started executing:
- REL-MED-02 (Get-ADKToolFailureRemediation) was already implemented
- REL-MED-04 (Test-ArchitectureCapability) was already implemented
- Pre-validation was already integrated in New-PEMedia

This plan added REL-MED-01 on top of the existing implementations.

## Next Phase Readiness

- REL-MED-01 provides foundation for 19-02 (error classification can use structured results)
- Test-WinPEMediaReadiness integrates with existing Test-ArchitectureCapability
- All tests passing, module loads correctly

## Impact

- **Prevents mid-operation failures:** Validates all dependencies before any cleanup or creation work
- **Saves debugging time:** Clear error messages with specific remediation steps
- **ThreadJob compatible:** Uses InvokeCommand.GetCommand for function availability checks
- **Fail-fast:** Returns immediately on first validation failure
