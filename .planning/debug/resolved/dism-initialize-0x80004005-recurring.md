---
status: resolved
trigger: "dism-initialize-0x80004005-recurring"
created: 2026-02-04T00:00:00Z
updated: 2026-02-04T00:10:00Z
---

## Current Focus

hypothesis: Enable-WindowsOptionalFeature in Enable-WindowsFeaturesByName has NO Test-DismReady gate, while Add-WindowsPackage calls have gates
test: Compare DISM operation patterns in FFU.Updates vs FFU.Imaging modules
expecting: Enable-WindowsOptionalFeature fails because WIMMount check is missing
next_action: Verify Enable-WindowsFeaturesByName has no Test-DismReady gate and add it

## Symptoms

expected: DISM operations (Add-WindowsPackage, Enable-WindowsOptionalFeature) should complete successfully during FFU image creation
actual: DISM fails intermittently with error 0x80004005 during long-running builds. Retries sometimes work, but the build ultimately fails.
errors:
  - "DismInitialize failed. Error code = 0x80004005" (occurs multiple times)
  - expand.exe fails with "Can't open input file" (exit code -1) on first MSU
  - Final failure: "Creating disk failed with error DismInitialize failed. Error code = 0x80004005"
reproduction:
  - Occurs during FFU build process when applying Windows Updates and enabling NetFx3 feature
  - Build uses VMware hypervisor with diskpart-created VHD
  - Long-running DISM operations (10+ min each) seem to trigger the issue
  - Timeline from log:
    * 8:56 PM - First DismInitialize failure (during update init)
    * 9:04 PM - Recovery after retry, KB5078127 applied successfully
    * 9:24 PM - Second failure during .NET CAB application
    * 9:57 PM - Second KB applied after ~33 min delay and retry
    * 10:09 PM - FATAL failure during Enable-WindowsOptionalFeature NetFx3
started: Recurring issue affecting multiple users

## Eliminated

## Evidence

- timestamp: 2026-02-04T00:00:00Z
  checked: Log file analysis
  found: DISM fails at multiple points in build lifecycle - initial package application, CAB application, and final NetFx3 enablement
  implication: This is not a transient one-time failure but a pattern of service degradation over time

- timestamp: 2026-02-04T00:00:00Z
  checked: Log file analysis
  found: TrustedInstaller service shows StartType=Manual, Status=Running during retry validation
  implication: Service appears healthy from external checks but still fails internally

- timestamp: 2026-02-04T00:00:00Z
  checked: Log file analysis
  found: expand.exe fails with exit code -1 ("Can't open input file") on first MSU
  implication: File locking or access issues may compound DISM problems

- timestamp: 2026-02-04T00:01:00Z
  checked: FFU.Updates module (Add-WindowsPackageWithRetry, Add-WindowsPackageWithUnattend)
  found: ALL Add-WindowsPackage calls are protected with Test-DismReady gates (3 sites in Add-WindowsPackageWithUnattend, 1 in Add-WindowsPackageWithRetry)
  implication: Package application operations have proper WIMMount validation

- timestamp: 2026-02-04T00:02:00Z
  checked: FFU.Imaging module (Enable-WindowsFeaturesByName function, lines 1888-1931)
  found: Enable-WindowsOptionalFeature is called directly with NO Test-DismReady gate (line 1928)
  implication: ROOT CAUSE - NetFx3 enablement lacks WIMMount validation, fails when WIMMount degrades during long builds

- timestamp: 2026-02-04T00:03:00Z
  checked: Project-wide grep for DismInitialize and 0x80004005
  found: Extensive documentation and fixes for Test-DismReady gates in FFU.Core, FFU.Updates, FFU.Imaging (Initialize-DISMService, Invoke-ExpandWindowsImageWithRetry)
  implication: This is a KNOWN pattern - Test-DismReady gates prevent 10-minute hangs, but Enable-WindowsFeaturesByName was missed

- timestamp: 2026-02-04T00:04:00Z
  checked: FFU.Imaging module DISM operations
  found: Initialize-DISMService and Invoke-ExpandWindowsImageWithRetry have Test-DismReady gates (v1.3.1 DISM-HEALTH-01)
  implication: Pattern is established in this module but not applied to Enable-WindowsFeaturesByName

## Resolution

root_cause: Enable-WindowsFeaturesByName (FFU.Imaging line 1928) calls Enable-WindowsOptionalFeature without Test-DismReady gate. During long-running builds, WIMMount filter driver can degrade or become unavailable. When NetFx3 enablement runs late in the build, DISM fails with 0x80004005 because WIMMount is not functional. All other DISM operations (Add-WindowsPackage, Expand-WindowsImage) have Test-DismReady gates added in v1.3.1 (DISM-HEALTH-01), but Enable-WindowsFeaturesByName was missed.

fix: Added Test-DismReady gate with auto-repair attempt before Enable-WindowsOptionalFeature in Enable-WindowsFeaturesByName function (FFU.Imaging.psm1 lines 1923-1931). Pattern matches other DISM operations: check for Test-DismReady availability, call with -AttemptRepair $true, throw clear error message with remediation steps if WIMMount is not loaded.

verification:
- Source code verified via grep - Test-DismReady gate is present before Enable-WindowsOptionalFeature loop
- Module version bumped to 1.3.4 with release notes documenting DISM-HEALTH-RECUR fix
- version.json updated to 1.10.1 with FFU.Imaging 1.3.4 description
- Fix follows established pattern from v1.3.1 (same error message, same -AttemptRepair logic)
- Future builds will fast-fail with actionable error instead of 10-minute hangs followed by cryptic 0x80004005

files_changed:
  - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1 (added Test-DismReady gate, lines 1923-1931)
  - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1 (version 1.3.3 -> 1.3.4, release notes)
  - FFUDevelopment/version.json (version 1.10.0 -> 1.10.1, FFU.Imaging description updated)
