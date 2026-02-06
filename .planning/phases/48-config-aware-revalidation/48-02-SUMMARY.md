---
phase: 48-config-aware-revalidation
plan: 02
subsystem: ui-dashboard
tags: [xaml, wpf, ui-controls, phase48]

# Dependency graph
requires: [48-01]
provides:
  - Staleness banner XAML structure
  - Export Diagnostics button XAML
  - Phase 48 control registrations in Initialize-UIControls
affects: [48-03]

# Tech tracking
tech-stack:
  added: []
  patterns: [WPF control registration]

# File tracking
key-files:
  created: []
  modified:
    - FFUDevelopment/BuildFFUVM_UI.xaml
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1

# Decisions
decisions:
  - id: CFG-02-COLORS
    choice: Amber/orange banner (#FFF8E1 background, #F57F17 text)
    rationale: Consistent with dashboard warning color scheme (not critical, needs attention)
  - id: CFG-02-PLACEMENT
    choice: Staleness banner between hypervisor info and progress panel
    rationale: Top of dashboard area for high visibility without blocking results
  - id: CFG-02-INITIAL-STATE
    choice: Export button starts disabled, staleness banner starts collapsed
    rationale: No diagnostics to export until checks run, no staleness until config changes

# Metrics
duration: 3 minutes
completed: 2026-02-06
---

# Phase 48 Plan 02: XAML Structure for Staleness & Diagnostics Summary

**One-liner:** Added staleness banner and Export Diagnostics button XAML elements to Home tab dashboard with control registrations.

## What Was Built

### Staleness Banner (CFG-02)
- **Element:** `borderStaleResults` Border with `txtStaleResults` TextBlock
- **Location:** Lines 94-100 in BuildFFUVM_UI.xaml, between hypervisor info banner and progress panel
- **Styling:** Amber/orange (`#FFF8E1` background, `#F57F17` foreground) with warning icon (⚠ U+26A0)
- **Initial state:** `Visibility="Collapsed"` — shown only when config changes detected

### Export Diagnostics Button (CFG-02)
- **Element:** `btnExportDiagnostics` Button in horizontal StackPanel with Refresh button
- **Location:** Lines 108-112 in BuildFFUVM_UI.xaml, adjacent to existing Refresh Checks button
- **Dimensions:** Width 160px (vs Refresh 140px) to accommodate longer text
- **Initial state:** `IsEnabled="False"` — grayed out until first check completes

### Control Registration
- **Module:** FFUUI.Core.Initialize.psm1 lines 210-213
- **Controls registered:** `borderStaleResults`, `txtStaleResults`, `btnExportDiagnostics`
- **Organization:** Added Phase 48 section comment for clear separation from Phase 47 controls
- **Access pattern:** All controls accessible via `$State.Controls.*` for event handlers

## Technical Implementation

### XAML Structure
```xml
<!-- Staleness Banner (Phase 48: CFG-02) -->
<Border x:Name="borderStaleResults" Background="#FFF8E1" Padding="8" CornerRadius="3" Margin="0,4,0,4" Visibility="Collapsed">
    <StackPanel Orientation="Horizontal">
        <TextBlock Text="&#x26A0;" FontSize="14" Foreground="#F57F17" Margin="0,0,6,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="txtStaleResults" Text="" Foreground="#F57F17" FontSize="12" VerticalAlignment="Center"/>
    </StackPanel>
</Border>

<!-- Action Buttons (Phase 48: Export Diagnostics next to Refresh) -->
<StackPanel Orientation="Horizontal" Margin="0,0,0,10">
    <Button x:Name="btnRefreshChecks" Content="Refresh Checks" Width="140" Padding="8,4"/>
    <Button x:Name="btnExportDiagnostics" Content="Export Diagnostics" Width="160" Margin="8,0,0,0" Padding="8,4" IsEnabled="False"/>
</StackPanel>
```

### Control Registration Pattern
```powershell
# ---------- Phase 48: Config-Aware Revalidation Controls ----------
$State.Controls.borderStaleResults = $window.FindName('borderStaleResults')
$State.Controls.txtStaleResults = $window.FindName('txtStaleResults')
$State.Controls.btnExportDiagnostics = $window.FindName('btnExportDiagnostics')
```

## Verification Results

**XAML Validation:**
- ✅ All 3 x:Name attributes found in BuildFFUVM_UI.xaml
- ✅ Staleness banner positioned between hypervisor info (line 87) and progress panel (line 102)
- ✅ Export button positioned next to Refresh button (lines 108-112)
- ✅ Export button starts disabled (`IsEnabled="False"`)
- ✅ Staleness banner starts collapsed (`Visibility="Collapsed"`)
- ✅ Refresh button still exists and functional (unchanged content/behavior)

**Control Registration:**
- ✅ All 3 FindName calls present in FFUUI.Core.Initialize.psm1
- ✅ Phase 48 section comment added for organization
- ✅ Controls accessible via `$State.Controls` namespace

## Commits

| Commit | Message | Files |
|--------|---------|-------|
| 20ce995 | feat(48-02): add staleness banner and Export Diagnostics button to XAML | BuildFFUVM_UI.xaml |
| 485c708 | feat(48-02): register Phase 48 controls in Initialize-UIControls | FFUUI.Core.Initialize.psm1 |

## Deviations from Plan

None — plan executed exactly as written.

## Next Steps

**Plan 48-03** will wire the behavior for these UI elements:
- Hypervisor dropdown SelectionChanged event → auto-revalidation
- Staleness banner visibility logic with elapsed time display
- Export Diagnostics button click handler → Export-DashboardDiagnostics function
- Category dimming during revalidation
- Summary banner "Rechecking..." state during revalidation

## Integration Points

**Ready for Plan 48-03:**
- `$State.Controls.borderStaleResults` — visibility controlled by SelectionChanged handler
- `$State.Controls.txtStaleResults.Text` — populated with "Results may be outdated..." message
- `$State.Controls.btnExportDiagnostics.IsEnabled` — enabled after DASHBOARD_COMPLETE message
- `$State.Controls.btnExportDiagnostics.Add_Click()` — wired to Export-DashboardDiagnostics

**Existing controls modified:**
- `btnRefreshChecks` — now in horizontal StackPanel (no functional change, still works)

## Notes

- Staleness banner uses amber/orange consistent with existing dashboard color scheme (green=success, yellow=warning, red=failure, amber=attention)
- Export button width (160px) chosen to prevent text wrapping while maintaining visual balance with Refresh (140px)
- Phase 48 comment section in Initialize-UIControls ensures clear separation from Phase 47 controls (good practice from Phase 47 pattern)
- All XAML changes are additive — no existing controls removed or functionally altered
