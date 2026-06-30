---
status: resolved
trigger: "HP driver downloads fail with exit code 1168 on driver extraction"
created: 2026-01-27T00:00:00Z
updated: 2026-01-27T00:05:00Z
---

## Current Focus

hypothesis: CONFIRMED - Root cause found and fix applied
test: PSScriptAnalyzer clean, all related Pester tests pass
expecting: HP driver extraction in UI no longer aborts on exit code 1168
next_action: Archive session

## Symptoms

expected: HP driver .exe files should extract successfully when run with `/s /e /f "target_folder"` arguments
actual: First driver extraction attempt fails with exit code 1168 (ERROR_NOT_FOUND)
errors: Process 'sp112041.exe' exited with code 1168. No error output captured.
reproduction: Select HP model in FFU Builder UI, download drivers - extraction fails
started: Recurring issue - user says "still receiving the 1168 error"

## Eliminated

- hypothesis: Extraction arguments are wrong (/s /e /f format)
  evidence: Both code paths use the same /s /e /f arguments. The FFU.Drivers.psm1 build path explicitly classifies exit code 1168 as Success=true, meaning extraction actually works but returns this non-zero code.
  timestamp: 2026-01-27T00:01:00Z

- hypothesis: Path too long (MAX_PATH issue)
  evidence: Path is ~129 chars, well under limit. The error is specifically exit code 1168, not a path error.
  timestamp: 2026-01-27T00:01:00Z

## Evidence

- timestamp: 2026-01-27T00:01:00Z
  checked: FFUUI.Core.Drivers.HP.psm1 line 355-358 (UI code path)
  found: Uses Invoke-Process which throws on any non-zero exit code. No exit code classification. The throw propagates to the catch block at line 386 which marks successState=false and removes the partial folder.
  implication: This is the failing code path. 1168 is treated as fatal when it should be non-fatal.

- timestamp: 2026-01-27T00:01:00Z
  checked: FFU.Drivers.psm1 lines 1181-1194 (build code path)
  found: Uses Start-Process -PassThru then Get-DriverExtractionResult to classify exit codes. 1168 is explicitly handled as Success=true with Action='Continue'.
  implication: The build code path already has the correct fix. The UI code path was never updated.

- timestamp: 2026-01-27T00:01:00Z
  checked: FFU.Common.Core.psm1 Invoke-Process function (line 280-351)
  found: Invoke-Process throws on ANY non-zero exit code (line 316-327). There is no way to pass in exit code classifications.
  implication: Using Invoke-Process for HP extraction is inherently incompatible with non-zero "success" exit codes like 1168.

- timestamp: 2026-01-27T00:01:00Z
  checked: Get-DriverExtractionResult function in FFU.Drivers.psm1 (line 131-228)
  found: Comprehensive exit code classification for HP - 0=success, 1=warn, 2=fail, 3=warn, 1641=success, 3010=success, 1168=success, default=warn
  implication: HP SoftPaqs routinely return non-zero codes that are actually successful extractions. The UI must handle these.

- timestamp: 2026-01-27T00:05:00Z
  checked: PSScriptAnalyzer on modified file
  found: No new warnings or errors from the change. Only pre-existing warning about unused $osReleaseIdFileName variable.
  implication: Fix is clean.

- timestamp: 2026-01-27T00:05:00Z
  checked: Pester tests - FFU.Drivers.Logging.Tests.ps1 (41 tests)
  found: 41/41 passed including all HP exit code 1168 classification tests
  implication: Build-time code path is unchanged and working correctly.

- timestamp: 2026-01-27T00:05:00Z
  checked: Pester tests - FFU.Drivers.Tests.ps1 (107 tests)
  found: 102/107 passed. 5 failures are all pre-existing issues unrelated to this change (Invoke-DriverDownloadWithRetry ThreadJob logging and Dell catalog remediation patterns).
  implication: No regressions from this change.

## Resolution

root_cause: FFUUI.Core.Drivers.HP.psm1 Save-HPDriversTask uses Invoke-Process (line 358) for HP SoftPaq extraction, which treats ALL non-zero exit codes as fatal errors by throwing an exception. Exit code 1168 (ERROR_NOT_FOUND) is a common non-fatal HP SoftPaq exit code that means extraction succeeded but some registry entries weren't found. The build-time code path (FFU.Drivers.psm1) already handles this correctly via Get-DriverExtractionResult, but the UI code path was never updated with the same classification logic. The thrown exception propagates to the outer catch block (line 386) which marks the entire model as failed and removes the partially-downloaded folder.

fix: Replaced Invoke-Process call with Start-Process -PassThru -Wait -NoNewWindow and added inline HP SoftPaq exit code classification that mirrors the logic in FFU.Drivers.psm1 Get-DriverExtractionResult. Exit codes 0, 1168, 1641, 3010 are treated as success; 1, 3 as warnings (log and continue); 2 as fatal (skip driver only, not entire model); unknown codes as warnings (log and continue). No code throws an exception for non-zero exit codes anymore, so the driver loop continues processing all 25 drivers even if some return non-zero exit codes.

verification: PSScriptAnalyzer clean (no new warnings/errors). 41/41 FFU.Drivers.Logging tests pass. 102/107 FFU.Drivers tests pass (5 pre-existing failures unrelated to change).

files_changed:
- FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.HP.psm1
