---
status: resolved
trigger: "CaptureFFU.ps1 reports 'unable to connect to network share' when the actual error is insufficient disk space"
created: 2026-01-27T00:00:00Z
updated: 2026-01-27T00:00:00Z
resolved: 2026-03-11T00:00:00Z
---

## Current Focus

hypothesis: The error reporting architecture has no back-channel for the VM to communicate specific failure reasons to the host; the host infers "network failure" from the absence of an FFU file, regardless of the actual error.
test: Full code trace of error flow from CaptureFFU.ps1 -> VM shutdown -> host detection
expecting: Confirm there is no structured status communication between VM and host
next_action: Document findings and propose solutions

## Symptoms

expected: When CaptureFFU.ps1 fails due to insufficient disk space, the error should clearly state "insufficient disk space" both in the log and to the host/UI
actual: CaptureFFU.ps1 fails with disk space error but reports it as a network connection failure to the host. The actual error is only visible in the log file on the FFUCaptureShare.
errors: "Unable to connect to network share" (shown to user) vs "not enough free space (20GB required)" (in log file on share)
reproduction: Start an FFU build on a machine with insufficient disk space in the VM, observe the error message
started: Existing behavior - error reporting has always conflated failures

## Evidence

- timestamp: 2026-01-27T00:01:00Z
  checked: CaptureFFU.ps1 error handling structure (lines 984-1090 and 1092-1389)
  found: |
    The script has TWO distinct try/catch blocks:
    1. Lines 984-1090: Network initialization (Wait-For-NetworkReady + Connect-NetworkShareWithRetry)
       - Catch block (line 1080) prints "NETWORK CONNECTION FAILED" banner
       - This is the ONLY catch block that displays a network error banner
    2. Lines 1092-1389: Post-connection operations (disk validation, resource checks, registry, DISM capture)
       - These are NOT inside the first try/catch
       - The disk space check (Test-ShareDiskSpace) at line 1138 is OUTSIDE the network try/catch
       - When disk space is insufficient, the throw at line 1156 goes to the outer catch at line 1384
       - The outer catch at line 1384 only does: Write-Error "An unexpected error occurred: $_"
  implication: |
    CRITICAL FINDING: The disk space error does NOT trigger the "NETWORK CONNECTION FAILED" banner.
    The disk space check happens AFTER the network connection succeeds, in a separate code block.
    The throw at line 1156 ("Insufficient disk space on network share...") is caught by the
    outer catch at line 1384, which outputs a generic "An unexpected error occurred" message.

    This means the symptom description needs refinement: the "network connection failed" message
    may not be the one users actually see. The real issue is that the HOST SIDE cannot distinguish
    what happened in the VM because there is NO back-channel communication.

- timestamp: 2026-01-27T00:02:00Z
  checked: Host-side detection mechanism (FFU.Imaging.psm1 New-FFU function, lines 2297-2490)
  found: |
    When InstallApps=true, the host:
    1. Starts the VM with capture ISO attached (lines 2330-2348)
    2. Polls VM state until it reaches 'Off' (lines 2356-2374 or 2400-2418)
    3. After VM shutdown, checks for .ffu files in FFUCaptureLocation (line 2479)
    4. If no .ffu files found, throws at line 2489: "throw $_" (re-throws whatever exception exists)

    PROBLEM: The host has ZERO visibility into WHY the VM shut down. It only knows:
    - VM is off (could be: success, disk space error, network error, DISM failure, any error)
    - Whether .ffu files exist in the capture location

    If .ffu files are missing, it throws a generic error. The host NEVER reads the transcript
    log or DISM log that CaptureFFU.ps1 writes to the share.
  implication: |
    The host-side error detection is purely binary: FFU file exists = success, no FFU file = failure.
    There is no mechanism to determine the specific failure reason.

- timestamp: 2026-01-27T00:03:00Z
  checked: Transcript/log file handling on network share
  found: |
    CaptureFFU.ps1 writes these files to W:\ (the mapped network share):
    1. W:\CaptureFFU_YYYYMMDD_HHmmss.log (transcript, line 1070)
    2. W:\dism.log (DISM log copy, line 1341)
    3. W:\dism_capture.log (second DISM log copy, line 1369)

    BUT: The host (BuildFFUVM.ps1 / FFU.Imaging.psm1) NEVER reads these files after VM shutdown.
    The transcript contains the actual error message, but nobody reads it programmatically.
  implication: |
    The logs are written for human post-mortem debugging only. The host cannot use them
    to report specific errors to the user/UI.

- timestamp: 2026-01-27T00:04:00Z
  checked: Error flow for disk space failure specifically
  found: |
    When disk space < 20GB, the exact flow is:
    1. CaptureFFU.ps1: Test-ShareDiskSpace returns Critical status (line 1147)
    2. CaptureFFU.ps1: throws "Insufficient disk space on network share: X.XXgb free, need at least 20GB" (line 1156)
    3. CaptureFFU.ps1: outer catch (line 1384) catches it, writes "An unexpected error occurred"
    4. CaptureFFU.ps1: tries to stop transcript (line 1387)
    5. WinPE: script exits, VM eventually shuts down or hangs at error
    6. Host: VM reaches Off state (or times out)
    7. Host: New-FFU checks for .ffu files, finds none
    8. Host: throws generic error "No .ffu files found in $FFUCaptureLocation"
    9. Host: BuildFFUVM.ps1 catches it as "FFU capture failed"

    KEY: The actual "Insufficient disk space" message is only in the transcript log on the share.
    The host NEVER sees this message. The user sees "FFU capture failed" or similar generic error.
  implication: |
    The misleading error chain is: specific error in VM -> VM shuts down -> host sees no FFU file
    -> host reports generic "capture failed" -> user has no idea the cause is disk space.

- timestamp: 2026-01-27T00:05:00Z
  checked: Existing status communication mechanisms between VM and host
  found: |
    There is NO structured communication channel between the VM and host:
    - No signal files (e.g., success.flag, error.json)
    - No exit code passing (WinPE shutdown doesn't pass exit codes)
    - No status files written to the share
    - The transcript IS written to the share but is never parsed by the host
    - The host's only signal is: VM is off + presence/absence of .ffu file
  implication: |
    This is an architectural gap. The VM operates as a black box from the host's perspective.
    Any solution must establish a structured communication channel.

- timestamp: 2026-01-27T00:06:00Z
  checked: What the user actually sees (tracing through BuildFFUVM.ps1)
  found: |
    In BuildFFUVM.ps1, when New-FFU throws:
    - Line 4843-4864 (InstallApps path): Invoke-BuildPhase wraps the call
    - Line 4866-4873: If not success, throws "FFU capture failed: $($ffuCaptureResult.Error.Message)"
    - Line 4901-4903: Outer catch: "FFU capture preparation failed with error $_"

    The user/UI sees: "FFU capture failed" or "FFU capture preparation failed" -
    both completely generic with no indication of the actual root cause.
  implication: The error message chain loses all specificity at the VM boundary.

## Eliminated

(No hypotheses eliminated - this was a direct code trace investigation)

## Resolution

root_cause: |
  ARCHITECTURAL GAP: There is no structured communication channel between the CaptureFFU.ps1
  script (running in WinPE inside the VM) and the host (BuildFFUVM.ps1 / FFU.Imaging.psm1).

  The host determines capture success/failure solely by checking whether .ffu files exist
  in the FFUCaptureLocation directory after the VM shuts down. When no .ffu file is found,
  the host reports a generic "FFU capture failed" error regardless of the actual cause.

  CaptureFFU.ps1 DOES correctly detect and log specific errors (disk space, network, DISM
  failures) to a transcript file on the network share. However, the host NEVER reads these
  log files, so the specific error information is lost in the reporting chain.

  Specific to the disk space case:
  - CaptureFFU.ps1 successfully connects to the share (network works fine)
  - CaptureFFU.ps1 correctly detects insufficient disk space (<20GB) via Test-ShareDiskSpace
  - CaptureFFU.ps1 throws with a clear "Insufficient disk space" message
  - This message is captured in the transcript log file on the share
  - The VM shuts down (no FFU file produced)
  - The host sees: no .ffu file -> "FFU capture failed" (generic)
  - The user never sees the disk space message

fix: (not applied - research mode)
verification: (not applicable - research mode)
files_changed: []

---

# DETAILED ANALYSIS AND SOLUTION PROPOSALS

## Error Flow Diagram

```
CaptureFFU.ps1 (VM/WinPE)              Host (BuildFFUVM.ps1 / FFU.Imaging)
================================        =====================================
1. Network init (OK)
2. Connect share (OK)
3. Start transcript on W:\
4. Test-ShareDiskSpace -> CRITICAL
5. throw "Insufficient disk space..."
6. Outer catch: "unexpected error"
7. Stop-Transcript (saves to W:\)
8. Script exits
9. WinPE shuts down VM
                                        10. Poll loop detects VM Off
                                        11. Check FFUCaptureLocation for .ffu
                                        12. No .ffu files found
                                        13. throw "No .ffu files found"
                                        14. UI shows: "FFU capture failed"

                               LOST: "Insufficient disk space" message
                               AVAILABLE BUT UNREAD: Transcript log on share
```

## Files Involved

| File | Role | Lines |
|------|------|-------|
| `FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1` | VM-side: detects errors, writes transcript | 984-1090 (network), 1111-1166 (resource check), 1384-1388 (outer catch) |
| `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` | Host-side: New-FFU function polls VM, checks for .ffu | 2297-2490 (New-FFU) |
| `FFUDevelopment/BuildFFUVM.ps1` | Orchestrator: calls New-FFU, reports errors to UI | 4843-4873 (capture invocation), 4901-4903 (error catch) |

## Proposed Solutions

### Solution A: Structured Status File on Network Share

**What changes:** CaptureFFU.ps1 writes a JSON status file (`W:\capture_status.json`) at each phase. The host reads this file after VM shutdown to determine the specific failure reason.

**Where changes are made:**
1. `CaptureFFU.ps1` - Add status file writes at key points
2. `FFU.Imaging.psm1` (New-FFU) - Read status file after VM shutdown, before checking for .ffu files

**CaptureFFU.ps1 changes:**
- Write status file after network connection: `{ "phase": "connected", "timestamp": "...", "status": "ok" }`
- Write status after disk space check: `{ "phase": "disk_check", "status": "critical", "error": "Insufficient disk space: 5.2GB free, need 20GB", "freeSpaceGB": 5.2 }`
- Write status after DISM capture: `{ "phase": "capture", "status": "ok", "ffuFile": "Win11_24H2_Pro_2026-01-27.ffu" }`
- Write status on any error: `{ "phase": "...", "status": "error", "error": "...", "errorType": "disk_space|network|dism|validation" }`

**FFU.Imaging.psm1 changes (New-FFU):**
- After VM shutdown, read `$FFUCaptureLocation\capture_status.json`
- Parse status and generate specific error message
- If status file exists with error, throw with the actual error message
- If status file doesn't exist, fall back to current behavior (generic "no .ffu files")

**Pros:**
- Rich structured data (JSON) allows detailed error reporting
- Extensible: can add more phases/metrics over time
- Host gets exact error type + message for UI display
- WinPE compatible (ConvertTo-Json works in WinPE PowerShell)
- Non-breaking: if status file is missing, falls back gracefully
- Status file persists on the share for post-mortem debugging

**Cons:**
- Requires changes in both VM-side and host-side code
- JSON serialization in WinPE needs testing (limited .NET)
- Status file could be partial if VM crashes mid-write (mitigated by atomic write pattern)
- Adds complexity to CaptureFFU.ps1 which runs in constrained WinPE environment

### Solution B: Host-Side Transcript Log Parsing

**What changes:** After VM shutdown, the host reads and parses the transcript log that CaptureFFU.ps1 already writes to the network share, extracting specific error information.

**Where changes are made:**
1. `FFU.Imaging.psm1` (New-FFU) - Add log parsing after VM shutdown
2. No changes to CaptureFFU.ps1 (already writes transcript)

**FFU.Imaging.psm1 changes:**
- After VM shutdown, scan `$FFUCaptureLocation\CaptureFFU_*.log` for known error patterns
- Pattern match against known error strings:
  - `"Insufficient disk space"` -> report disk space error
  - `"NETWORK CONNECTION FAILED"` -> report network error
  - `"DISM capture failed"` -> report DISM error
  - `"Target disk validation failed"` -> report disk validation error
  - `"CRITICAL: Only .* free memory"` -> report memory error
- Include the matched error context in the thrown exception
- If no log file exists, report "VM capture failed - no logs available (possible crash or boot failure)"

**Pros:**
- Zero changes to CaptureFFU.ps1 (already writes transcript)
- Leverages existing log infrastructure
- Simplest implementation (host-side only)
- No risk of breaking WinPE behavior

**Cons:**
- Fragile: depends on specific log message text patterns (brittle coupling)
- Log format changes would break parsing
- Transcript may be incomplete if VM crashes before Stop-Transcript
- Text parsing is less reliable than structured data
- Cannot distinguish between errors that happen at different phases if messages are similar
- Transcript file naming includes timestamp, must glob for most recent

### Solution C: Signal Files (Lightweight Status Markers)

**What changes:** CaptureFFU.ps1 writes simple marker files at key milestones. The host checks for these files to determine how far the capture progressed and what failed.

**Where changes are made:**
1. `CaptureFFU.ps1` - Write marker files at milestones
2. `FFU.Imaging.psm1` (New-FFU) - Check for marker files after VM shutdown

**Marker files on W:\ (network share):**
- `W:\.capture_connected` - Written after successful share connection
- `W:\.capture_diskcheck_ok` - Written after disk space validation passes
- `W:\.capture_started` - Written when DISM capture begins
- `W:\.capture_complete` - Written when DISM capture succeeds
- `W:\.capture_error` - Written on any error (contains error message as file content)

**Host-side logic:**
```
if (.capture_complete exists) -> Success
elif (.capture_error exists) -> Read error file content, report specific error
elif (.capture_started exists) -> "DISM capture failed (started but did not complete)"
elif (.capture_diskcheck_ok exists) -> "Capture failed after disk validation"
elif (.capture_connected exists) -> "Capture failed during pre-capture validation"
else -> "VM could not connect to share or crashed before connecting"
```

**Pros:**
- Very simple and robust (plain text files)
- Works reliably in WinPE (no JSON/serialization needed)
- Easy to understand the failure point (which milestone was reached)
- Error file can contain the actual error message
- Non-breaking: host gracefully handles missing marker files
- Easy to debug: just `ls` the capture location

**Cons:**
- Multiple files to manage and clean up
- Less structured than JSON (each file is a separate concern)
- Error file content is unstructured text
- Marker files accumulate across builds (need cleanup logic)
- Slightly more file I/O in WinPE

### Solution D: Pre-Flight Disk Space Check on Host Side

**What changes:** Before starting the VM for capture, the host checks the available disk space in FFUCaptureLocation and fails early with a clear message.

**Where changes are made:**
1. `BuildFFUVM.ps1` or `FFU.Imaging.psm1` - Add pre-capture disk space validation
2. No changes to CaptureFFU.ps1

**Host-side changes:**
- Before starting VM capture, check free space on the drive containing FFUCaptureLocation
- If < 20GB free, throw "Insufficient disk space for FFU capture: X GB free in $FFUCaptureLocation, need at least 20GB"
- This check runs on the HOST, not in the VM, so the error message goes directly to the UI

**Pros:**
- Fails fast with clear error BEFORE wasting time starting VM
- Zero changes to WinPE/CaptureFFU.ps1
- Error message goes directly to UI (no VM boundary to cross)
- Very simple to implement
- Consistent with existing pre-flight validation pattern (FFU.Preflight module)

**Cons:**
- Only addresses the disk space case, not other CaptureFFU errors (DISM, network from VM side, etc.)
- Does not solve the general problem of VM->host error communication
- Disk space could change between pre-check and actual capture
- The VM-side check would still report generically for other errors

## Recommendation

**Recommended approach: Solution A (Structured Status File) + Solution D (Pre-Flight Check)**

### Primary: Solution A - Structured Status File

This is the most robust and extensible solution. It establishes a proper communication channel between the VM and host using a JSON status file on the shared network drive.

**Reasoning:**
1. **Solves the general problem**: Not just disk space, but ALL error types from CaptureFFU.ps1 become reportable to the host.
2. **Structured data**: JSON is parseable, extensible, and unambiguous. No regex pattern matching against log text.
3. **Forward-compatible**: New error types or status phases can be added without changing the host parsing logic.
4. **WinPE compatible**: PowerShell's ConvertTo-Json is available in WinPE (part of Microsoft.PowerShell.Utility).
5. **Graceful degradation**: If the status file is missing (VM crash, network failure before connection), the host falls back to current behavior.
6. **Debugging benefit**: The status file serves as a structured post-mortem artifact alongside the transcript.

### Supplementary: Solution D - Pre-Flight Check

This is a complementary quick win that catches the most common case (disk space) before even starting the VM.

**Reasoning:**
1. **Fail-fast**: Saves the user potentially 30+ minutes of VM boot + capture attempt.
2. **Simple**: A few lines of code in the existing pre-flight validation framework.
3. **Consistent**: Fits naturally into the FFU.Preflight module's tiered validation pattern.
4. **Defense in depth**: Even with Solution A, catching errors before the VM starts is better UX.

### Implementation Priority

1. **Phase 1 (Quick Win)**: Implement Solution D - pre-flight disk space check on host. This immediately addresses the specific disk space scenario.
2. **Phase 2 (Architectural Fix)**: Implement Solution A - structured status file. This addresses the general problem of VM->host error communication for all failure types.

### Why NOT the other solutions:

- **Solution B (Log Parsing)**: Too fragile. Depends on exact text patterns that could change. Not structured enough for reliable error classification.
- **Solution C (Signal Files)**: Workable but less clean than a single JSON file. Multiple files to manage, no structure in error content.
