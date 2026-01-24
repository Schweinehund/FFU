# Phase 22 Plan 04: Tiered Check Severity Classification Summary

## Frontmatter

```yaml
phase: 22
plan: 04
subsystem: FFU.Preflight
tags: [preflight, severity, classification, REL-PRE-04]
requires: [22-01, 22-02, 22-03]
provides: [severity-parameter, severity-tracking, tiered-output]
affects: []
tech-stack:
  added: []
  patterns: [severity-classification, tiered-validation]
key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1
    - Tests/Unit/FFU.Preflight.Reliability.Tests.ps1
decisions:
  - decision: Three severity levels (Critical/Warning/Info)
    rationale: Clear distinction between build blockers, potential issues, and optional improvements
    date: 2026-01-24
  - decision: Only Critical failures block builds
    rationale: Warning/Info issues should not prevent builds, user can decide
    date: 2026-01-24
  - decision: Add-CheckToResult internal helper for severity tracking
    rationale: Encapsulates severity counting and error formatting in one place
    date: 2026-01-24
metrics:
  duration: ~30 minutes
  completed: 2026-01-24
```

## One-liner

Added Severity parameter (Critical/Warning/Info) to New-FFUCheckResult with Add-CheckToResult helper function tracking severity counts, where only Critical failures block builds while Warning/Info issues are displayed for user awareness.

## What Was Built

### Task 1: Severity Parameter on New-FFUCheckResult

Added Severity parameter to `New-FFUCheckResult` function:

```powershell
[Parameter()]
[ValidateSet('Critical', 'Warning', 'Info')]
[string]$Severity = 'Warning'
```

Updated all check functions with appropriate severity:

**Tier 1 Critical (all `Severity = 'Critical'`):**
- Test-FFUAdministrator: Failed results
- Test-FFUPowerShellVersion: Failed results
- Test-FFUHyperV: Failed results (2 locations)

**Tier 2 Feature-Dependent (mixed):**
- Test-FFUADK: `Severity = 'Critical'` for Failed (2 locations)
- Test-FFUDiskSpace: `Severity = 'Critical'` for Failed
- Test-FFUWimMount: `Severity = 'Critical'` for Failed
- Test-FFUNetwork: `Severity = 'Warning'` for Warning, `Severity = 'Critical'` for Failed
- Test-FFUConfigurationFile: `Severity = 'Critical'` for Failed
- Test-FFUHyperVSwitchConflict: `Severity = 'Critical'` for Failed
- Test-FFUVMwareBridgeConfiguration: `Severity = 'Warning'` for Failed
- Test-FFUVmxToolkit: `Severity = 'Info'` for Warning (optional)
- Test-FFUVMResources: `Severity = 'Critical'` for Failed
- Test-FFUScratchSpace: `Severity = 'Critical'` for Failed
- Test-FFUDISMState: `Severity = 'Warning'` for Failed

**Tier 3 Recommended:**
- Test-FFUAntivirusExclusions: `Severity = 'Info'` for Warning

**Tier 4 Cleanup:**
- Invoke-FFUDISMCleanup: `Severity = 'Info'` for all results

### Task 2: Add-CheckToResult Helper and Severity Tracking

Created internal `Add-CheckToResult` helper function:

```powershell
function Add-CheckToResult {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Result,
        [Parameter(Mandatory)][PSCustomObject]$CheckResult,
        [Parameter(Mandatory)][ValidateSet('1', '2', '3', '4')][string]$TierKey,
        [Parameter(Mandatory)][string]$ResultKey
    )

    # Add to tier results
    $Result."Tier${TierKey}Results"[$ResultKey] = $CheckResult

    # Track severity counts for failures
    if ($CheckResult.Status -eq 'Failed') {
        switch ($CheckResult.Severity) {
            'Critical' {
                $Result.CriticalCount++
                $Result.Errors.Add("[CRITICAL] $ResultKey`: $($CheckResult.Message)")
            }
            'Warning' {
                $Result.WarningCount++
                $Result.Warnings.Add("[WARNING] $ResultKey`: $($CheckResult.Message)")
            }
            'Info' {
                $Result.InfoCount++
                $Result.InfoMessages.Add("[INFO] $ResultKey`: $($CheckResult.Message)")
            }
        }

        # Only block on Critical failures
        if ($CheckResult.Severity -eq 'Critical') {
            $Result.IsValid = $false
        }
        # ... remediation handling
    }
}
```

Updated result object with new properties:
- `InfoMessages`: List for Info-level messages
- `CriticalCount`: Count of critical issues
- `WarningCount`: Count of warning issues
- `InfoCount`: Count of info issues

Enhanced summary output with severity breakdown:
```
CRITICAL ISSUES: 2 (build cannot proceed)
  - Administrator: Not running with Administrator privileges
  - HyperV: Hyper-V feature is not installed

WARNINGS: 1 (build may have issues)
  - DISMState: DISM state may need cleanup

INFO: 1 (optional improvements)
  - VmxToolkit: vmxtoolkit module not installed
```

### Task 3: REL-PRE-04 Pester Tests

Added 23 tests in `Describe 'REL-PRE-04: Tiered Check Severity Classification'`:

| Context | Tests | Coverage |
|---------|-------|----------|
| New-FFUCheckResult Severity parameter | 5 | Accept all values, default, output object |
| Tier 1 checks use Critical severity | 3 | Admin, PowerShell, HyperV |
| Tier 2 checks use appropriate severity | 4 | ADK, VmxToolkit, DiskSpace, WimMount |
| Invoke-FFUPreflight severity tracking | 7 | Counts, InfoMessages, Add-CheckToResult, blocking logic |
| Severity display in summary | 4 | Prefixes, breakdown |

## Commits

| Commit | Description | Files |
|--------|-------------|-------|
| 3b7c789 | feat(22-04): add Severity parameter to New-FFUCheckResult | FFU.Preflight.psm1 |
| 461210f | feat(22-04): complete Severity parameter for all check functions | FFU.Preflight.psm1 |
| ccfc3a9 | feat(22-04): add severity tracking to Invoke-FFUPreflight result | FFU.Preflight.psm1 |
| d60afcd | test(22-04): add REL-PRE-04 Pester tests and finalize Severity parameter | FFU.Preflight.psm1, Tests |

## Verification

All REL-PRE-04 tests passing:
```
Invoke-Pester -TagFilter 'REL-PRE-04' -Output Detailed
Tests Passed: 23, Failed: 0, Skipped: 0
```

All FFU.Preflight.Reliability tests passing:
```
Invoke-Pester -Path Tests/Unit/FFU.Preflight.Reliability.Tests.ps1 -Output Detailed
Tests Passed: 96, Failed: 0, Skipped: 0
```

Module verification:
```powershell
Import-Module FFU.Preflight -Force  # No errors
$result = New-FFUCheckResult -CheckName 'Test' -Status 'Failed' -Message 'Test' -Severity 'Critical'
$result.Severity  # Returns 'Critical'

$module = Get-Module FFU.Preflight
$helper = $module.Invoke({ ${function:Add-CheckToResult} })
$helper | Should -Not -BeNullOrEmpty  # PASSED
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed missing Severity parameter on Test-FFUHyperV Failed calls**
- **Found during:** Task 3 test execution
- **Issue:** Two Failed calls in Test-FFUHyperV (lines 556, 578) were missing Severity 'Critical'
- **Fix:** Added `-Severity 'Critical'` to both calls
- **Files modified:** FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1
- **Commit:** d60afcd

**2. [Rule 1 - Bug] Fixed missing Severity parameter on Test-FFUADK Failed calls**
- **Found during:** Task 3 test execution
- **Issue:** Two Failed calls in Test-FFUADK (lines 778, 787) were missing Severity 'Critical'
- **Fix:** Added `-Severity 'Critical'` to both calls
- **Files modified:** FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1
- **Commit:** d60afcd

**3. [Rule 1 - Bug] Fixed test assertions for prefix location**
- **Found during:** Task 3 test execution
- **Issue:** Tests looked for [CRITICAL]/[WARNING]/[INFO] prefixes in Invoke-FFUPreflight ScriptBlock, but prefixes are in Add-CheckToResult
- **Fix:** Updated tests to check Add-CheckToResult helper function
- **Files modified:** Tests/Unit/FFU.Preflight.Reliability.Tests.ps1
- **Commit:** d60afcd

## Success Criteria Met

- [x] New-FFUCheckResult includes Severity parameter (Critical/Warning/Info)
- [x] Tier 1 Critical checks use Severity = 'Critical'
- [x] Optional/recommended checks use Severity = 'Info'
- [x] Invoke-FFUPreflight tracks severity counts in result
- [x] Summary output clearly shows Critical vs Warning vs Info issues
- [x] Only Critical failures block the build (IsValid = $false)
- [x] All REL-PRE-04 Pester tests pass (23/23)
- [x] Module version at 1.3.0 (bumped in 22-01)

## Phase 22 Completion

Phase 22 (FFU.Preflight Reliability) is now complete with all 4 plans executed:

| Plan | Name | REL Requirement | Tests |
|------|------|-----------------|-------|
| 22-01 | VMware Pre-flight Enhancements | REL-PRE-01 | 30 tests |
| 22-02 | Remediation Steps Quality | REL-PRE-02 | 21 tests |
| 22-03 | WIMMount Repair Resilience | REL-PRE-03 | 22 tests |
| 22-04 | Tiered Check Severity Classification | REL-PRE-04 | 23 tests |

**Total:** 96 REL-PRE-* tests, all passing

FFU.Preflight module version: 1.3.0 (includes all REL-PRE-* improvements)
