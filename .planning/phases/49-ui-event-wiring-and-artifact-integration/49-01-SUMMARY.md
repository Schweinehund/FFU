---
phase: 49-ui-event-wiring-and-artifact-integration
plan: "01"
subsystem: UI/XAML/EventHandlers
tags: [usb-mode, artifact-scan, mode-switch, wpf, event-wiring]
dependency_graph:
  requires: [48-02, 46-01]
  provides: [artifact-scan-foundation, mode-switch-handlers, rescan-button]
  affects: [BuildFFUVM_UI.xaml, BuildFFUVM_UI.ps1, FFUUI.Core.Handlers.psm1]
tech_stack:
  added: []
  patterns: [typed-wpf-brushes, artifact-state-hashtable, isLoadingConfig-guard]
key_files:
  created: []
  modified:
    - FFUDevelopment/BuildFFUVM_UI.xaml
    - FFUDevelopment/BuildFFUVM_UI.ps1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1
decisions:
  - "Typed WPF Brushes and FontStyles (System.Windows.Media.Brushes::Color) used exclusively — no bare strings"
  - "isLoadingConfig flag added to Flags block to guard premature artifact scan during config load"
  - "usbArtifactState uses PSCustomObject per artifact type (source/path) for cleaner property access"
  - "Invoke-USBArtifactScan placed before Register-EventHandlers in same module file — no separate module needed"
metrics:
  duration: "~10 minutes"
  completed: "2026-03-24T21:26:00Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
---

# Phase 49 Plan 01: XAML Additions, State Init, and Mode Switch Handlers Summary

USB Mode foundation wired: Rescan button and Target USB Drive GroupBox added to XAML, artifact state initialized in UI host, FFU.ArtifactScanner imported, mode switch handlers and Invoke-USBArtifactScan implemented.

## What Was Built

### Task 1: XAML additions and state initialization

**BuildFFUVM_UI.xaml** — Two additions to the USB Mode tab StackPanel:

1. `usbRescanArtifacts` Button inserted after subtitle TextBlock, before "Required Artifacts" GroupBox. Uses `Margin="0,0,0,16"` (md spacing), `FontSize="13"`, `Width="140"`.

2. "Target USB Drive" GroupBox appended at bottom of USB Mode StackPanel, containing:
   - `usbCheckUSBDrives` Button (Check for USB Drives, Width=160)
   - `usbUSBDriveList` ListBox (Height=80, SelectionMode=Multiple)
   - `usbSelectAllDrives` CheckBox (Select All Drives)

**BuildFFUVM_UI.ps1** — Three changes:
- `usbArtifactState` hashtable added to `$script:uiState.Data` with 7 artifact types (FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO), each as PSCustomObject with `source='auto'` and `path=$null`.
- `isLoadingConfig = $false` flag added to `$script:uiState.Flags`.
- Conditional `Import-Module FFU.ArtifactScanner` added after existing module imports.

### Task 2: Mode switch handlers and artifact scan function

**FFUUI.Core.Handlers.psm1** — Four additions:

1. `Invoke-USBArtifactScan` function (before `Register-EventHandlers`):
   - Pre-condition checks: FFUDevelopmentPath must exist, isLoadingConfig guard
   - Sets `(scanning...)` with `Brushes::Gray` and `FontStyles::Italic` on auto-detect cards
   - Calls `Find-FFUArtifacts -FFUDevelopmentPath` (synchronous, UI thread)
   - Try/catch: on error sets "Scan error" + `Brushes::OrangeRed` on all cards
   - Per-card logic: user-source cards re-verify file existence without overwriting path; auto-source cards update from scan results
   - FFU metadata uses `$result.Metadata.WindowsSKU` (correct property, not `.SKU`)
   - All Foreground uses `[System.Windows.Media.Brushes]::Color`, all FontStyle uses `[System.Windows.FontStyles]::Style`
   - Null guards on usbFFUVersion, usbFFUSKU, usbFFUArch controls

2. `rbUSBMode.Add_Checked` handler: collapses 7 Full Build tabs, shows usbModeTab, selects usbModeTab, calls Invoke-USBArtifactScan, sets btnRun.Content = 'Create USB'

3. `rbFullBuild.Add_Checked` handler: shows 7 Full Build tabs, collapses usbModeTab, selects tabVMSettings, sets btnRun.Content = 'Build FFU'

4. `usbRescanArtifacts.Add_Click` handler: calls Invoke-USBArtifactScan

## Decisions Made

- Typed WPF Brushes and FontStyles (System.Windows.Media.Brushes::Color) used exclusively — no bare strings (prevents WPF type conversion failures)
- isLoadingConfig flag added to Flags block to guard premature artifact scan during config load (Pitfall 2 prevention)
- usbArtifactState uses PSCustomObject per artifact type for cleaner property access vs nested hashtables
- Invoke-USBArtifactScan placed before Register-EventHandlers in same .psm1 file — no separate module needed since it's called only from event handlers in the same file

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: XAML additions + state init | e02d3b3 | BuildFFUVM_UI.xaml, BuildFFUVM_UI.ps1 |
| Task 2: Mode switch handlers + scan function | 85f7079 | FFUUI.Core.Handlers.psm1 |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all 7 artifact card types wired with full Found/Missing status and metadata. The Invoke-USBArtifactScan function calls Find-FFUArtifacts directly; no stub logic or hardcoded return values.

## Self-Check: PASSED

- `FFUDevelopment/BuildFFUVM_UI.xaml` — usbRescanArtifacts, usbCheckUSBDrives, usbUSBDriveList, usbSelectAllDrives all present (verified via XPath)
- `FFUDevelopment/BuildFFUVM_UI.ps1` — usbArtifactState, isLoadingConfig, FFU.ArtifactScanner import all present
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` — Invoke-USBArtifactScan, rbUSBMode.Add_Checked, rbFullBuild.Add_Checked, usbRescanArtifacts.Add_Click, Find-FFUArtifacts, System.Windows.Media.Brushes, System.Windows.FontStyles, WindowsSKU all present
- Commits e02d3b3 and 85f7079 both verified in git log
