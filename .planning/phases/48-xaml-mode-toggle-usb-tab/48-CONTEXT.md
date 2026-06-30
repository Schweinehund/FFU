# Phase 48: XAML Mode Toggle and USB Tab - Context

**Gathered:** 2026-03-21
**Status:** Ready for planning

<domain>
## Phase Boundary

The UI has a mode toggle that switches between Full Build and USB Mode views, and a USB Mode tab with artifact display structure. This phase is XAML structure only — no event wiring, no artifact scanning, no browse dialog logic. Phase 49 handles all code-behind interactivity.

</domain>

<decisions>
## Implementation Decisions

### Mode Toggle Control (Area A)
- **D-01:** RadioButton group placed in a new Grid row below the title row and above the TabControl — global mode switch, always visible
- **D-02:** Inline radio buttons, simple and compact — no icons, no descriptions underneath
- **D-03:** Labels: "Full Build" and "USB from Existing"
- **D-04:** GroupName binds to `ActiveMode` config field from Phase 45 ("FullBuild" / "USBMode")
- **D-05:** On startup, toggle reflects config value silently — no tip or first-run indicator
- **D-06:** x:Name values: `rbFullBuild` and `rbUSBMode` (for Phase 49 event binding)

### Tab Visibility Strategy (Area B)
- **D-07:** Full Build tabs (VM Settings, Windows Settings, Updates, Applications, M365 Apps/Office, Drivers, Build) collapse (`Visibility="Collapsed"`) when USB Mode is active
- **D-08:** Shared tabs remain visible in both modes: Home, Monitor, About
- **D-09:** USB Mode tab appears when USB Mode is selected, collapses when Full Build is selected
- **D-10:** On mode switch, auto-select the USB Mode tab (or first Full Build tab when switching back)
- **D-11:** Instant swap — no animation or transitions
- **D-12:** Tab collapse/show logic implemented in code-behind (Phase 49 wires the RadioButton Checked events), but the XAML defines all tabs with correct initial Visibility based on default FullBuild mode

### USB Mode Tab Layout (Area C)
- **D-13:** Stacked card layout grouped by importance — "Required Artifacts" section (FFU, DeployISO) at top, "Optional Artifacts" section (Drivers, PPKG, Unattend, Autopilot, AppsISO) below
- **D-14:** GroupBox controls with "Required Artifacts" and "Optional Artifacts" headers to visually separate sections
- **D-15:** Each artifact card includes: artifact type label, status TextBlock (placeholder "(scanning...)"), file path TextBlock (placeholder), file size TextBlock, age TextBlock, and artifact-specific metadata area (FFU gets version/SKU/architecture TextBlocks)
- **D-16:** Per-artifact CheckBox controls included now (disabled, `IsEnabled="False"`) — Phase 49 enables them when scanner populates data
- **D-17:** Per-artifact "Browse..." Button controls included now (disabled, `IsEnabled="False"`) — Phase 49 wires Click handlers and enables them
- **D-18:** USB tab initially `Visibility="Collapsed"` since default mode is FullBuild
- **D-19:** Tab position: after Build tab (index 8), before Monitor tab — follows workflow order

### Control Naming Convention
- **D-20:** All USB Mode controls use `usb` prefix for x:Name: `usbRequiredGroup`, `usbOptionalGroup`, `usbFFUStatus`, `usbFFUPath`, `usbFFUBrowse`, `usbFFUInclude`, etc.
- **D-21:** Artifact-specific controls follow pattern: `usb{ArtifactType}{Property}` — e.g., `usbDeployISOPath`, `usbDriversInclude`, `usbPPKGBrowse`
- **D-22:** USB Mode tab: `usbModeTab` (x:Name for programmatic visibility toggling)

### Claude's Discretion
- Exact Grid/StackPanel layout within each artifact card
- Spacing, margins, and padding within the USB Mode tab
- Whether to use a ScrollViewer wrapper for the USB tab content (recommended if content exceeds viewport)
- TextBlock placeholder text wording for each field
- RadioButton margin/padding for the mode toggle row

</decisions>

<specifics>
## Specific Ideas

- Card layout per artifact mirrors the existing tab style (Drivers tab, Applications tab use grouped sections with varied controls per section)
- Including all controls now (CheckBoxes, Browse buttons, TextBlocks) means Phase 49 is pure code-behind — no XAML modifications needed, only event wiring and data binding
- Required/Optional grouping aligns with ArtifactManifest.IsReady logic (FFU + DeployISO = ready)

</specifics>

<canonical_refs>
## Canonical References

### XAML structure
- `FFUDevelopment/BuildFFUVM_UI.xaml` — Main XAML file (1,004 lines), TabControl at line 75, Grid rows at lines 56-72, tab definitions lines 77-958
- `FFUDevelopment/BuildFFUVM_UI.ps1` — XAML loading (lines 170-179), control registration via FindName (line 208), uiState.Controls hashtable

### UI framework
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1` — Control initialization patterns, defaults
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` — Get-UIConfig (line 13), Update-UIFromConfig (line 505) — will need USB Mode field support in Phase 49
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` — Event handler registration patterns

### Data model (Phase 46)
- `FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1` — ArtifactType enum (7 types), ArtifactResult properties (Status, FilePath, FileSizeBytes, AgeDays), FFUMetadata properties (WindowsVersion, WindowsSKU, Architecture)

### Config schema (Phase 45)
- `FFUDevelopment/config/ffubuilder-config.schema.json` — ActiveMode field, USBMode.Artifacts section (v1.3 schema)

### Prior phase context
- `.planning/phases/45-config-schema-extension/45-CONTEXT.md` — D-07 through D-09: ActiveMode at top level, values FullBuild/USBMode, default FullBuild
- `.planning/phases/46-ffu-artifactscanner-module/46-CONTEXT.md` — Artifact types, data model, ArtifactManifest structure

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- TabControl with x:Name="MainTabControl" (line 75): Established tab management pattern
- GroupBox pattern: Used in existing tabs for visual grouping (e.g., Drivers tab line 587+)
- Grid row layout: Consistent pattern across all tabs for form-style layouts
- $script:uiState.Controls hashtable: Standard registration for all named controls

### Established Patterns
- Tab definition: `<TabItem Header="Name" x:Name="tabName">` with ScrollViewer wrapper for long content
- Control grouping: GroupBox with Header for logical sections within tabs
- Form layout: Grid with Label in column 0, control in column 1, consistent margins
- CheckBox pattern: `<CheckBox x:Name="chkName" Content="Label" IsEnabled="False"/>` for initially disabled controls
- Button pattern: `<Button x:Name="btnName" Content="Browse..." IsEnabled="False" Width="75"/>` for action buttons

### Integration Points
- Phase 49: Wires RadioButton.Checked events to toggle tab visibility and enable controls
- Phase 49: Wires Browse button Click handlers to file/folder dialogs
- Phase 49: Enables CheckBoxes after scanner populates data
- Phase 49: Binds TextBlock.Text properties to ArtifactResult data
- Phase 50: Adds disposition controls (Reuse/Rebuild/Skip) per artifact — may need XAML additions

</code_context>

<deferred>
## Deferred Ideas

- Artifact scanning and data binding to controls — Phase 49: UI Event Wiring
- Browse dialog event handlers — Phase 49: UI Event Wiring
- CheckBox enable/disable based on scan results — Phase 49: UI Event Wiring
- Per-artifact disposition controls (Reuse/Rebuild/Skip) — Phase 50: Selective Rebuild Pipeline
- USB drive selection dropdown in USB Mode — Phase 49 (reuses existing drive detection)
- "Create USB" button in USB Mode tab — Phase 49 (triggers BuildFFUVM.ps1 -USBOnlyMode)

</deferred>

---

*Phase: 48-xaml-mode-toggle-usb-tab*
*Context gathered: 2026-03-21*
