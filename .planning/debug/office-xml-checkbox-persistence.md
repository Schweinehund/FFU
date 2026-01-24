---
status: resolved
trigger: "office-xml-checkbox-not-persisting"
created: 2026-01-24T10:00:00Z
updated: 2026-01-24T17:00:00Z
resolved: 2026-01-24T17:00:00Z
---

## Resolution

**Root Cause:** Config migration system incorrectly treated `CopyOfficeConfigXML` as deprecated and removed it during config load.

**Fix Applied:**
- Removed migration logic that deleted `CopyOfficeConfigXML` from FFU.ConfigMigration.psm1
- Removed deprecated flag from `CopyOfficeConfigXML` in ffubuilder-config.schema.json
- Updated manifest and help documentation

**Files Changed:**
- FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1
- FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psd1
- FFUDevelopment/config/ffubuilder-config.schema.json

## Original Investigation

hypothesis: CONFIRMED - Config migration removes CopyOfficeConfigXML property on config load
test: Traced code flow from config load through migration module
expecting: Migration module actively removes this property
result: Fixed by preserving the property during migration

## Symptoms

expected: The 'Copy Office Configuration XML' checkbox state should be saved to config.json and restored when the GUI is relaunched, like all other configuration settings.
actual: The checkbox state is lost between runs - it resets to its default value instead of the user's previous selection.
errors: None reported - this is a silent failure to persist state.
reproduction:
  1. Open FFU Builder UI
  2. Go to M365 Apps/Office tab
  3. Change the 'Copy Office Configuration XML' checkbox state
  4. Close and reopen the UI
  5. Observe the checkbox has reverted to default
started: Unknown when this started - may have never worked correctly.

## Eliminated

- hypothesis: Save logic missing for CopyOfficeConfigXML
  evidence: FFUUI.Core.Config.psm1 line 67 correctly saves the property
  timestamp: 2026-01-24T10:05:00Z

- hypothesis: Load logic missing for CopyOfficeConfigXML
  evidence: FFUUI.Core.Config.psm1 line 691 correctly calls Set-UIValue for this property
  timestamp: 2026-01-24T10:06:00Z

- hypothesis: Control binding issue
  evidence: Control name 'chkCopyOfficeConfigXML' matches between save/load/initialize code
  timestamp: 2026-01-24T10:07:00Z

## Evidence

- timestamp: 2026-01-24T10:03:00Z
  checked: FFUUI.Core.psm1 Get-GeneralDefaults function
  found: CopyOfficeConfigXML and OfficeConfigXMLFilePath both have defaults (lines 237-238)
  implication: Default handling exists and is correct

- timestamp: 2026-01-24T10:04:00Z
  checked: FFUUI.Core.Initialize.psm1 Initialize-UIDefaults function
  found: Lines 333-334 set checkbox from defaults correctly
  implication: Initialization is correct

- timestamp: 2026-01-24T10:05:00Z
  checked: FFUUI.Core.Config.psm1 Get-UIConfig function
  found: Line 67 saves CopyOfficeConfigXML from checkbox state
  implication: Save logic is complete and correct

- timestamp: 2026-01-24T10:06:00Z
  checked: FFUUI.Core.Config.psm1 Update-UIFromConfig function
  found: Line 691 loads CopyOfficeConfigXML via Set-UIValue
  implication: Load logic exists but may not execute if property removed

- timestamp: 2026-01-24T10:08:00Z
  checked: ffubuilder-config.schema.json deprecated properties section
  found: Lines 587-591 mark CopyOfficeConfigXML as "deprecated: true"
  implication: Property flagged for removal/migration

- timestamp: 2026-01-24T10:10:00Z
  checked: FFU.ConfigMigration.psm1 migration logic
  found: Lines 420-436 actively REMOVE CopyOfficeConfigXML during migration
  implication: ROOT CAUSE - migration strips this property before config is applied to UI

- timestamp: 2026-01-24T10:12:00Z
  checked: FFUUI.Core.Config.psm1 Invoke-AutoLoadPreviousEnvironment function
  found: Lines 1176-1206 call migration BEFORE Update-UIFromConfig
  implication: Property removed before UI load, causing checkbox to use default

## Resolution

root_cause: |
  The FFU.ConfigMigration module (FFU.ConfigMigration.psm1 lines 420-436) actively REMOVES the
  CopyOfficeConfigXML property during config migration, treating it as a deprecated property.

  The auto-load sequence on UI startup is:
  1. Invoke-AutoLoadPreviousEnvironment reads config.json
  2. Test-FFUConfigVersion triggers migration if version mismatch
  3. Invoke-FFUConfigMigration REMOVES CopyOfficeConfigXML property
  4. Migrated config (without CopyOfficeConfigXML) is passed to Update-UIFromConfig
  5. Set-UIValue for chkCopyOfficeConfigXML finds no matching key, skips loading
  6. Checkbox retains default value (false)

  INCONSISTENCY: The UI still has this checkbox and expects to save/load this property, but the
  migration system treats it as deprecated and removes it. This creates a contradiction:
  - Get-UIConfig saves CopyOfficeConfigXML to config.json
  - On next load, migration removes it
  - Checkbox appears unchecked regardless of saved state

  Files involved:
  - FFU.ConfigMigration.psm1 (lines 420-436) - removes property
  - FFUUI.Core.Config.psm1 (line 67) - saves property
  - FFUUI.Core.Config.psm1 (line 691) - tries to load property
  - ffubuilder-config.schema.json (lines 587-591) - marks deprecated

fix: |
  Two possible resolutions depending on intent:

  OPTION A: Keep the checkbox functional (recommended if feature still needed)
  1. Remove CopyOfficeConfigXML from deprecated properties section in schema
  2. Remove migration logic in FFU.ConfigMigration.psm1 lines 420-436
  3. The save/load logic already works correctly

  OPTION B: Remove the checkbox entirely (if feature truly deprecated)
  1. Remove chkCopyOfficeConfigXML checkbox from BuildFFUVM_UI.xaml
  2. Remove related controls (CopyOfficeConfigXMLStackPanel, etc.)
  3. Remove save logic from Get-UIConfig
  4. Remove load logic from Update-UIFromConfig
  5. Remove default from Get-GeneralDefaults
  6. Remove initialization from Initialize-UIDefaults
  7. Keep migration logic to clean up old configs

verification:
files_changed:
  - FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1
  - FFUDevelopment/config/ffubuilder-config.schema.json
