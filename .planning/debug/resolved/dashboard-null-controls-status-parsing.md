---
status: resolved
trigger: "Two bugs: dashboard controls null on UI launch, status parsing concatenates multiple values"
created: 2026-02-06T00:00:00Z
updated: 2026-02-06T00:05:00Z
---

## Current Focus

hypothesis: BOTH CONFIRMED AND FIXED
test: Pester tests pass (71/74 in Preflight, 29/29 in DismServiceStates; 2 pre-existing failures)
expecting: N/A
next_action: Archive session

## Symptoms

expected: UI launches cleanly, dashboard runs pre-flight checks, each check gets individual status update
actual: Multiple null reference errors on dashboard controls, then Status validation errors ("Passed Passed Passed Failed" instead of single "Passed")
errors: |
  BUG 1 - Null controls (3 event handler + 5 property access failures)
  BUG 2 - Status "Passed Passed Passed Failed" not in ValidateSet
reproduction: Launch BuildFFUVM_UI.ps1 from C:\FFUDevelopment
started: After Phase 46-48 dashboard features added

## Eliminated

- hypothesis: BUG1 - Controls missing from dev XAML
  evidence: grep confirms all controls exist in dev XAML AND in FFUUI.Core.Initialize.psm1
  timestamp: 2026-02-06T00:00:30Z

- hypothesis: BUG2 - Pipe-delimited split logic is wrong
  evidence: Split uses -split '\|', 7 which is correct
  timestamp: 2026-02-06T00:00:45Z

## Evidence

- timestamp: 2026-02-06T00:00:30Z
  checked: C:\FFUDevelopment\BuildFFUVM_UI.xaml for dashboard controls
  found: NO MATCHES - runtime XAML has zero dashboard controls
  implication: BUG 1 root cause - runtime XAML is upstream copy

- timestamp: 2026-02-06T00:00:50Z
  checked: Test-FFUNetwork, Test-FFUConfigurationFile, Test-FFUAntivirusExclusions for return statements
  found: 6 early-exit New-FFUCheckResult calls missing return keyword
  implication: BUG 2 root cause - functions emit multiple results, Status becomes array

- timestamp: 2026-02-06T00:04:00Z
  checked: Pester tests after fixes
  found: FFU.Preflight.Tests.ps1: 71 passed, 2 failed (pre-existing), 1 skipped. FFU.Core.DismServiceStates.Tests.ps1: 29 passed, 0 failed.
  implication: Fixes are safe, no regressions

## Resolution

root_cause: |
  BUG 1: Runtime XAML at C:\FFUDevelopment is stale (upstream version without Phase 46-48 dashboard controls).
  Code also lacked null-safety guards on dashboard control access, causing crashes when controls are absent.

  BUG 2: Three functions in FFU.Preflight.psm1 have missing `return` on early-exit New-FFUCheckResult calls.
  Without return, execution falls through and emits multiple result objects. $check.Status becomes an array
  ("Passed Passed Passed Failed"), which fails the ValidateSet on Update-DashboardCheckUI.

fix: |
  BUG 1: Added null-safety guards throughout BuildFFUVM_UI.ps1:
  - Start-DashboardChecks: Early return if critical dashboard controls are null
  - borderHypervisorInfo, btnExportDiagnostics, btnRun: Individual null checks
  - borderStaleResults: Null checks in DASHBOARD_COMPLETE and DASHBOARD_ERROR handlers
  - btnRefreshChecks.Add_Click: Wrapped in null check
  - cmbHypervisorType.Add_SelectionChanged: Wrapped in null check
  - btnExportDiagnostics.Add_Click: Wrapped in null check

  BUG 2: Added `return` keyword to 6 early-exit New-FFUCheckResult calls:
  - Test-FFUNetwork: lines 1355 (Skipped), 1377 (Failed DNS)
  - Test-FFUConfigurationFile: lines 1506 (Skipped), 1514 (Failed not found)
  - Test-FFUAntivirusExclusions: lines 3085 (Skipped no Defender), 3095 (Skipped RTP disabled)

verification: |
  Pester tests: FFU.Preflight.Tests.ps1 71/74 (2 pre-existing failures unrelated to changes),
  FFU.Core.DismServiceStates.Tests.ps1 29/29 all pass. No regressions introduced.

files_changed:
  - FFUDevelopment/BuildFFUVM_UI.ps1
  - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1
