---
status: resolved
trigger: "BUG-WINGET-01: Winget CLI not available in elevated context"
created: 2026-01-24T00:00:00Z
updated: 2026-01-24T00:10:00Z
---

## Current Focus

hypothesis: CONFIRMED - Winget CLI now installed system-wide with -AllUsers flag
test: Module imports, syntax verification, PSScriptAnalyzer
expecting: All verification passes
next_action: Ready for manual testing in elevated UI context

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
  1. FFU.Common.Winget.psm1 Install-WinGet (line 515): Add-AppxPackage without -AllUsers installs per-user
  2. FFUUI.Core.Winget.psm1 Install-WingetComponents: Only installs PowerShell module, not CLI packages
  3. VCLibs and UIXaml dependencies also need -AllUsers for elevated context visibility

fix: |
  Applied changes to both modules:

  1. FFU.Common.Winget.psm1 Install-WinGet (line 517):
     - Changed: `Add-AppxPackage -Path $destination -AllUsers -ErrorAction SilentlyContinue`
     - Added comment explaining BUG-WINGET-01 fix
     - Updated log messages to reflect "for all users" installation

  2. FFUUI.Core.Winget.psm1 Install-WingetComponents (lines 268-312):
     - Added CLI installation capability using Test-WingetCLI check
     - Downloads and installs VCLibs, UIXaml, and WinGet MSIX packages
     - Uses Invoke-WebRequest for reliable downloads
     - All packages installed with Add-AppxPackage -AllUsers
     - PowerShell module installation remains unchanged (-Scope AllUsers)

  3. Version updates:
     - FFU.Common: 0.0.12 -> 0.0.13
     - FFUUI.Core: 0.0.17 -> 0.0.18
     - Main version: 1.8.39 -> 1.8.40

verification: |
  PASSED:
  - Module import tests: Both modules import successfully
  - JSON validation: version.json is valid
  - PSScriptAnalyzer: No new warnings or errors introduced

  PENDING (manual testing required):
  - UI testing in elevated context to confirm winget.exe is accessible
  - Test reproduction steps from symptoms section

files_changed:
  - FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.Winget.psm1
  - FFUDevelopment/FFU.Common/FFU.Common.psd1
  - FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1
  - FFUDevelopment/version.json
