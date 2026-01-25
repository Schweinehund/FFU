---
status: resolved
trigger: "BUG-WINGET-01: Winget CLI not available in elevated context"
created: 2026-01-24T00:00:00Z
updated: 2026-01-24T19:15:00Z
resolved: 2026-01-24T19:15:00Z
---

## Current Focus

hypothesis: CONFIRMED - Winget CLI registered from provisioned package for elevated admin user
test: RegisterByFamilyName approach tested manually, then implemented in code
expecting: Fast registration without download when package is provisioned
next_action: Complete - ready for commit

## Symptoms

expected: When clicking "Check Winget Status" in the FFU Builder UI (which runs elevated), the Winget CLI should be detected and available for use.
actual: Error message "Winget component installation/update failed or is incomplete" appears. The CLI check fails because winget.exe is not found in the elevated context.
errors: In elevated prompt: "'winget' is not recognized as an internal or external command". In normal user prompt: "v1.12.460" (works fine).
reproduction: 1. Launch FFU Builder UI (runs elevated). 2. Go to Applications tab. 3. Check "Install Winget Applications". 4. Click "Check Winget Status" button. 5. Error appears.
started: Always been an issue - per-user installation vs elevated context

## Eliminated

(none yet - root cause was confirmed from initial analysis)

## Evidence

- timestamp: 2026-01-24T00:00:00Z
  checked: Root cause analysis from ticket
  found: Add-AppxPackage without -AllUsers flag installs per-user only
  implication: Elevated processes cannot see per-user installed packages

- timestamp: 2026-01-24T00:01:00Z
  checked: FFU.Common.Winget.psm1 Install-WinGet function (lines 499-522)
  found: Line 515 uses `Add-AppxPackage -Path $destination -ErrorAction SilentlyContinue` without -AllUsers
  implication: VCLibs, UIXaml, and WinGet MSIX packages installed per-user only

- timestamp: 2026-01-24T00:01:00Z
  checked: FFUUI.Core.Winget.psm1 Install-WingetComponents function (lines 257-300)
  found: Only installs PowerShell module with -Scope AllUsers (line 284), but does NOT install CLI packages
  implication: UI component installer handles module correctly but omits CLI installation

- timestamp: 2026-01-24T00:01:00Z
  checked: Confirm-WingetInstallationUI function (lines 304-380)
  found: Checks CLI status via Test-WingetCLI but Install-WingetComponents doesn't install CLI
  implication: CLI check fails because Install-WingetComponents never installs CLI packages

- timestamp: 2026-01-24T00:05:00Z
  checked: Module import test after fix
  found: Both FFU.Common and FFUUI.Core modules import successfully
  implication: Fix is syntactically correct and modules load properly

- timestamp: 2026-01-24T00:10:00Z
  checked: PSScriptAnalyzer on modified files
  found: No new warnings or errors introduced; only pre-existing style warnings
  implication: Fix adheres to PowerShell best practices

## Resolution

root_cause: |
  The FFU Builder UI runs elevated (as an admin account like "admin-joanderson"), which is a
  different user context than the normal login user ("JoAnderson"). Winget was:

  1. Provisioned system-wide (available for new users)
  2. Installed for the normal user (JoAnderson) - works in normal prompt
  3. NOT registered for the elevated admin user (admin-joanderson) - fails in elevated prompt

  The original fix (v0.0.18) tried Add-AppxPackage -AllUsers, but this doesn't register the
  package for existing users who don't have it - it only provisions for future users.

  Key insight: When Winget is already provisioned, we can use -RegisterByFamilyName to
  instantly register it for the current user without downloading anything.

fix: |
  Two-phase fix applied:

  Phase 1 (v0.0.18 - bfd6943): Added CLI installation with -AllUsers
  - FFU.Common.Winget.psm1: Add-AppxPackage -AllUsers for build-time installation
  - FFUUI.Core.Winget.psm1: Added CLI package download/install capability
  - Result: Works for fresh installs, but doesn't help when package is provisioned

  Phase 2 (v0.0.19 - current): Register from provisioned package first
  - FFUUI.Core.Winget.psm1 Install-WingetComponents now uses two strategies:
    * Strategy 1 (fast): Check if package is provisioned via Get-AppxProvisionedPackage
      If provisioned, use Add-AppxPackage -RegisterByFamilyName (instant, no download)
    * Strategy 2 (fallback): If not provisioned, download and install with -AllUsers
  - This handles the common enterprise scenario where Winget is provisioned but not
    registered for the specific elevated admin account running the UI

  Version updates (cumulative):
  - FFU.Common: 0.0.12 -> 0.0.13
  - FFUUI.Core: 0.0.17 -> 0.0.19
  - Main version: 1.8.39 -> 1.8.41

verification: |
  Manual testing confirmed:
  - User verified: winget --version in normal prompt = v1.12.460
  - User verified: winget --version in elevated prompt = NOT recognized (before fix)
  - User verified: Add-AppxPackage -RegisterByFamilyName worked instantly
  - User verified: winget --version in elevated prompt = v1.12.460 (after registration)

files_changed:
  - FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1 (v0.0.13 - -AllUsers flag)
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.Winget.psm1 (v0.0.19 - RegisterByFamilyName strategy)
  - FFUDevelopment/FFU.Common/FFU.Common.psd1
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1
  - FFUDevelopment/version.json
