---
status: resolved
trigger: "bits-priority-parameter-download-failure"
created: 2026-02-02T00:00:00Z
updated: 2026-02-02T00:20:00Z
---

## Current Focus

hypothesis: VERIFIED - Fix applied successfully
test: Pester tests confirm priority parameter chain is intact
expecting: All downloads will use configured BitsPriority value
next_action: Final verification and commit

## Symptoms

expected: Downloads work with BitsPriority setting (Normal, High, Foreground, Low)
actual: Resilient download fails with "A parameter cannot be found that matches parameter name 'Priority'". Falls back to legacy BITS which fails with 0x800704DD. Build crashes.
errors: "Resilient download failed: A parameter cannot be found that matches parameter name 'Priority'." repeated 3 times per attempt
reproduction: Run any build with BitsPriority configured (or default Normal). Any download that uses resilient download path will fail.
started: After v1.10.0 milestone. BitsPriority feature added in Phase 36.

## Eliminated

## Evidence

- timestamp: 2026-02-02T00:05:00Z
  checked: Start-BitsTransferWithRetry function signature (FFU.Common.Core.psm1:402-469)
  found: Function HAS -Priority parameter (line 468)
  implication: Start-BitsTransferWithRetry is NOT the problem

- timestamp: 2026-02-02T00:06:00Z
  checked: Start-BitsTransferWithRetry resilient download call (FFU.Common.Core.psm1:497-525)
  found: Lines 520-522 pass -Priority to Start-ResilientDownload
  implication: Start-BitsTransferWithRetry is passing -Priority to Start-ResilientDownload

- timestamp: 2026-02-02T00:07:00Z
  checked: Start-ResilientDownload function signature (FFU.Common.Download.psm1:40-99)
  found: NO -Priority parameter in param block
  implication: ROOT CAUSE FOUND - Start-ResilientDownload doesn't accept -Priority parameter

- timestamp: 2026-02-02T00:08:00Z
  checked: Start-ResilientDownload internal BITS call (FFU.Common.Download.psm1:212-216)
  found: Line 215 hardcodes Priority = 'Normal'
  implication: Priority is hardcoded instead of being a parameter

## Resolution

root_cause: Start-ResilientDownload function (FFU.Common.Download.psm1) does not have a -Priority parameter, but Start-BitsTransferWithRetry (FFU.Common.Core.psm1:520-522) passes -Priority to it. When BitsPriority is configured, Start-BitsTransferWithRetry resolves the priority value and passes it to Start-ResilientDownload via splatting, causing "parameter cannot be found" error.

fix: Added -Priority parameter to download chain:
1. Start-ResilientDownload: Added -Priority parameter with ValidateSet (Foreground, High, Normal, Low), default 'Normal'
2. Invoke-BITSDownload: Added -Priority parameter with ValidateSet, default 'Normal'
3. Updated Start-ResilientDownload to pass -Priority to Invoke-BITSDownload (line 127)
4. Updated Invoke-BITSDownload to use $Priority instead of hardcoded 'Normal' in $bitsParams (line 215)

verification: PASSED
- FFU.Common.BitsPriority.Tests.ps1: All 22 tests PASSED
- FFU.Common.Download.Priority.Tests.ps1: 3/3 code structure tests PASSED
  - Priority parameter used instead of hardcoded 'Normal' ✓
  - Priority passed from Start-ResilientDownload to Invoke-BITSDownload ✓
  - Priority passed from Start-BitsTransferWithRetry to Start-ResilientDownload ✓
- No regressions in existing BitsPriority functionality

files_changed:
- FFUDevelopment\FFU.Common\FFU.Common.Download.psm1
