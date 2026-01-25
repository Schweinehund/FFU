---
status: diagnosed
trigger: "dism-initialize-0x80004005"
created: 2026-01-23T00:00:00Z
updated: 2026-01-23T00:02:00Z
---

## Current Focus

hypothesis: CONFIRMED - DismInitialize 0x80004005 has multiple root causes; WIMMount is NOT the issue
test: Researched DISM error causes and code path analysis
expecting: Identified 3 most likely root causes for user's scenario
next_action: Provide diagnosis and recommendations to user

## Symptoms

expected: Build should create VHDX and apply Windows base image successfully
actual: Build fails at "Creating VHDX and applying base Windows image" with DismInitialize error
errors: "DismInitialize failed. Error code = 0x80004005" (E_FAIL - generic failure)
reproduction: Run FFU build - fails consistently at progress step 15 (Creating VHDX)
started: Every build attempt; WIMMount repairs already attempted

Key log entries:
- Line 208: [PROGRESS] 15 | Creating VHDX and applying base Windows image...
- Line 210: The path to the install file is: F:\sources\install.wim
- Line 211: Creating disk failed with error DismInitialize failed. Error code = 0x80004005
- Line 212-217: Cleanup occurs, VHD file not found (never created)

User confirmed:
1. WIMMount service is running
2. WIMMount appears in 'fltmc filters' list
3. Already ran Repair-WimmountService.ps1
4. Already ran Reinstall-Wimmountdriver.ps1

## Eliminated

- hypothesis: WIMMount service not running
  evidence: User confirmed service is running and appears in fltmc filters
  timestamp: 2026-01-23

- hypothesis: WIMMount driver corrupted
  evidence: User already ran Repair-WimmountService.ps1 and Reinstall-Wimmountdriver.ps1 without success
  timestamp: 2026-01-23

## Evidence

- timestamp: 2026-01-23T00:00:30Z
  checked: Codebase - where error originates
  found: Error occurs in Invoke-ExpandWindowsImageWithRetry (FFU.Imaging.psm1 lines 345-375) when calling PowerShell's Expand-WindowsImage cmdlet. The error "DismInitialize failed" comes from the underlying DISM service that the cmdlet uses.
  implication: This is a DISM service initialization failure, not a cmdlet syntax issue

- timestamp: 2026-01-23T00:00:45Z
  checked: Previous fix for same error (v1.2.2)
  found: FIXED_ISSUES_ARCHIVE.md documents v1.2.2 fix for same error. Root cause was "Hyper-V feature check internally calls DISM API (DismInitialize) BEFORE logging was initialized." Fix included: 1) Early logging init, 2) DISM cleanup before check (dism.exe /Cleanup-Mountpoints), 3) Retry logic with delays, 4) Actionable error messages.
  implication: The v1.2.2 fix addressed one scenario but the error can have multiple root causes

- timestamp: 2026-01-23T00:01:00Z
  checked: Web research on 0x80004005 causes
  found: Error 0x80004005 is E_FAIL (generic failure) with multiple causes:
    1. Another DISM operation already in progress (conflicting DISM session)
    2. Antivirus/EDR software blocking DISM operations
    3. TrustedInstaller service issues (Windows Modules Installer)
    4. Stale DISM mount points from failed previous operations
    5. Insufficient permissions or UAC issues
    6. Corrupted Windows component store
  implication: WIMMount being operational rules out only one possible cause

- timestamp: 2026-01-23T00:01:15Z
  checked: Code path analysis
  found: F:\sources\install.wim indicates ISO is mounted to F: drive. Expand-WindowsImage is being called with path to WIM file on mounted ISO. DISM must initialize its service before accessing the WIM.
  implication: ISO mount itself seems fine (path is found), but DISM service init is failing

- timestamp: 2026-01-23T00:01:30Z
  checked: DISM log guidance
  found: Windows DISM log at C:\Windows\Logs\DISM\dism.log contains detailed error info. This log would reveal the specific initialization failure reason.
  implication: User should check DISM log for definitive root cause

## Resolution

root_cause: One of three most likely causes (in order of probability):
  1. Antivirus/EDR blocking DISM - Corporate security software (Defender, CrowdStrike, etc.) intercepting DISM operations
  2. Stale DISM session - Previous failed DISM operation left incomplete state
  3. TrustedInstaller service issue - Windows Modules Installer service (trustedinstaller) not ready or stuck

fix: See recommendations below
verification: Build completes progress step 15 successfully
files_changed: []
