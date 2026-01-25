---
status: verifying
trigger: "BUG-WINGET-02: Winget source package not registered for elevated admin"
created: 2026-01-24T20:00:00Z
updated: 2026-01-24T20:15:00Z
---

## Current Focus

hypothesis: CONFIRMED - Microsoft.Winget.Source_8wekyb3d8bbwe needs registration for elevated admin
test: Fix implemented in Install-WingetComponents
expecting: After clicking "Check Winget Status", winget search will work in elevated context
next_action: User verification - test search in elevated UI context

## Symptoms

expected: When using the FFU Builder UI's "Search" function in the Applications tab, Winget should successfully search the winget community repository and return results.
actual: Search returns no results and logs show "Error during Winget search: An error occurred while connecting to the catalog." The winget CLI search fails with "Failed when searching source; results will not be included: winget" and error code 0x8a15000f "Data required by the source is missing".
errors: |
  From FFUDevelopment_UI.log:
  - "Error during Winget search: An error occurred while connecting to the catalog."

  From winget CLI:
  - "Failed when searching source; results will not be included: winget"
  - "0x8a15000f : Data required by the source is missing"

  From winget verbose log (admin account):
  - "Did not find extension: PFN = Microsoft.Winget.Source_8wekyb3d8bbwe, ID = IndexDB"
  - "Package not found Microsoft.Winget.Source_8wekyb3d8bbwe"
  - "Failed to open available source: winget"
reproduction: |
  1. Launch FFU Builder UI (runs elevated as admin-joanderson)
  2. Go to Applications tab
  3. Check "Install Winget Applications"
  4. Click "Check Winget Status" - now succeeds after BUG-WINGET-01 fix
  5. Type "7zip" in search box and click Search
  6. No results returned, error in log
started: Discovered immediately after BUG-WINGET-01 fix

## Eliminated

(none - root cause was provided and confirmed)

## Evidence

- timestamp: 2026-01-24T20:00:00Z
  checked: Manual testing of root cause
  found: User confirmed Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.Winget.Source_8wekyb3d8bbwe fixes the issue
  implication: Source package needs same registration treatment as DesktopAppInstaller

- timestamp: 2026-01-24T20:00:00Z
  checked: BUG-WINGET-01 fix implementation
  found: Install-WingetComponents only registers Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
  implication: Need to add Microsoft.Winget.Source_8wekyb3d8bbwe registration to same location

- timestamp: 2026-01-24T20:00:00Z
  checked: Winget verbose log from admin account
  found: "Package not found Microsoft.Winget.Source_8wekyb3d8bbwe" shows source package not registered
  implication: Confirms root cause - source index package not available in elevated context

## Resolution

root_cause: |
  After BUG-WINGET-01 fix, the Winget CLI (Microsoft.DesktopAppInstaller) is registered for the
  elevated admin user. However, winget search still fails because the winget source index
  (Microsoft.Winget.Source_8wekyb3d8bbwe) is also a separate APPX package that needs registration.

  The source package contains the winget community repository database index. Without it,
  winget can execute commands but cannot access any package sources for search/install.

  PACKAGES NEEDED FOR ELEVATED ADMIN:
  1. Microsoft.DesktopAppInstaller_8wekyb3d8bbwe (CLI) - fixed in BUG-WINGET-01
  2. Microsoft.Winget.Source_8wekyb3d8bbwe (Source index) - needs fix now

fix: |
  Extended Install-WingetComponents to register both required packages:
  1. Microsoft.DesktopAppInstaller_8wekyb3d8bbwe (CLI) - already fixed in BUG-WINGET-01
  2. Microsoft.Winget.Source_8wekyb3d8bbwe (Source index) - NEW in this fix

  Implementation details:
  - Check if source package already registered via Get-AppxPackage
  - If not registered, check if provisioned via Get-AppxProvisionedPackage
  - If provisioned, register using Add-AppxPackage -RegisterByFamilyName
  - If not provisioned, log warning (source reset will handle)

  Also added source agreement handling:
  - winget source reset --force (accept agreements, reset sources)
  - winget source update (refresh source index)

  Comprehensive logging added for each step:
  - "Checking Winget Source package registration..."
  - "Winget Source package already registered (v...)"
  - "Winget Source package not registered for current user. Attempting registration..."
  - "Found provisioned Winget Source package (v...). Registering..."
  - "Successfully registered Winget Source package."
  - "Initializing Winget sources..."
  - "Winget source reset result: ..."
  - "Winget source update result: ..."
  - "Winget sources initialized successfully."

  Version updates:
  - FFUUI.Core: 0.0.19 -> 0.0.20
  - Main version: 1.8.41 -> 1.8.42

verification: |
  Automated verification:
  - Module imports successfully (FFUUI.Core v0.0.20)
  - PSScriptAnalyzer shows no new errors
  - Only pre-existing style warnings (plural nouns, ShouldProcess)

  User verification needed:
  1. Launch FFU Builder UI (elevated as admin account)
  2. Go to Applications tab
  3. Check "Install Winget Applications"
  4. Click "Check Winget Status" - should show source initialization in log
  5. Search for "7zip" - should return results

files_changed:
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.Winget.psm1 (v0.0.20 - Source package registration + initialization)
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1 (version 0.0.20, release notes)
  - FFUDevelopment/version.json (main version 1.8.42, FFUUI.Core description)
  - .planning/debug/BUG-WINGET-01-elevated-context.md (added related issues reference)
