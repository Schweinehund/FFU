---
status: resolved
trigger: "config-migration-always-triggered - UI always shows migration required after BUG-OFFICE-01 fix"
created: 2026-01-24T00:00:00Z
updated: 2026-01-24T17:15:00Z
resolved: 2026-01-24T17:15:00Z
---

## Resolution

**Root Cause:** `Get-UIConfig` did not include `configSchemaVersion` when building config for save. Saved configs had no version, so they were treated as version "0.0" and always triggered migration.

**Fix Applied:**
- Added `configSchemaVersion` to the config hashtable in `Get-UIConfig`
- Uses `Get-FFUConfigSchemaVersion` if available, fallback to "1.2"

**Files Changed:**
- FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1

## Original Investigation

hypothesis: CONFIRMED - Get-UIConfig does not include configSchemaVersion when building config for save
test: Traced save flow: Invoke-SaveConfiguration -> Get-UIConfig -> ConvertTo-Json -> Set-Content
expecting: configSchemaVersion should be in saved config but is missing
result: Fixed by adding configSchemaVersion to Get-UIConfig output

## Symptoms

expected: After saving a config, subsequent UI launches should not show migration required message
actual: "Configuration Migration Required" message appears on every UI launch
errors: No errors - just the migration prompt appearing when it shouldn't
reproduction: Save config -> Close UI -> Reopen UI -> Migration message appears
started: Immediately after BUG-OFFICE-01 fix (commit ceb77eb) that preserved CopyOfficeConfigXML

## Eliminated

(none - root cause found on first hypothesis)

## Evidence

- timestamp: 2026-01-24T00:00:30Z
  checked: FFU.ConfigMigration.psm1 - Test-FFUConfigVersion function
  found: Current schema version is "1.2" (line 27). Configs without configSchemaVersion are treated as "0.0" (line 195-197)
  implication: Any saved config missing configSchemaVersion will trigger migration

- timestamp: 2026-01-24T00:00:45Z
  checked: FFUUI.Core.Config.psm1 - Invoke-SaveConfiguration function (lines 918-948)
  found: Calls Get-UIConfig to build config hashtable, then saves to JSON
  implication: Save flow depends entirely on Get-UIConfig output

- timestamp: 2026-01-24T00:01:00Z
  checked: FFUUI.Core.Config.psm1 - Get-UIConfig function (lines 13-186)
  found: Builds config from UI controls but DOES NOT include configSchemaVersion property
  implication: ROOT CAUSE - Every saved config is missing configSchemaVersion, so every load triggers migration

- timestamp: 2026-01-24T00:01:15Z
  checked: Grep for "configSchemaVersion" in FFUUI.Core folder
  found: Zero matches
  implication: Confirms configSchemaVersion is never set in the UI save path

## Resolution

root_cause: Get-UIConfig function (FFUUI.Core.Config.psm1 lines 13-186) does not include configSchemaVersion when building the config hashtable. When Invoke-SaveConfiguration saves the config, it lacks configSchemaVersion. On next UI launch, Invoke-AutoLoadPreviousEnvironment calls Test-FFUConfigVersion which treats missing configSchemaVersion as "0.0" (pre-versioning), triggering migration from "0.0" to "1.2".

fix: Add configSchemaVersion to Get-UIConfig function. Should call Get-FFUConfigSchemaVersion to get current version.

verification: (pending fix)

files_changed: []
