---
status: resolved
trigger: "bitspriority-config-validation-failure"
created: 2026-02-02T00:00:00Z
updated: 2026-02-02T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED - BitsPriority is a valid script parameter but missing from JSON schema
test: Add BitsPriority to schema, verify validation passes
expecting: Validation should pass once BitsPriority is in schema
next_action: Add BitsPriority property to ffubuilder-config.schema.json

## Symptoms

expected: Build should start successfully, BitsPriority should be a valid config property
actual: Pre-flight validation FAILS with "Unknown property 'BitsPriority' is not allowed in configuration"
errors: "Configuration file validation failed with 1 error(s)" and "Unknown property 'BitsPriority' is not allowed in configuration. To fix: Remove this property or check spelling. Run Get-FFUConfigurationSchema to see all valid properties."
reproduction: Run a build via BuildFFUVM_UI.ps1 with a config file that has BitsPriority property
started: After v1.10.0 milestone. The user had a working config before the milestone.

## Eliminated

## Evidence

- timestamp: 2026-02-02T00:01:00Z
  checked: User's config file at C:\FFUDevelopment\config\FFUConfig.json
  found: Config does NOT contain BitsPriority property
  implication: Error message is misleading - the property doesn't exist in user's config

- timestamp: 2026-02-02T00:02:00Z
  checked: Schema file ffubuilder-config.schema.json (650 lines)
  found: BitsPriority is NOT defined in the schema (searched entire file, not present)
  implication: BitsPriority is not a valid config property according to schema

- timestamp: 2026-02-02T00:03:00Z
  checked: BuildFFUVM.ps1 parameter block (lines 464-468)
  found: BitsPriority IS a valid parameter with ValidateSet('Foreground', 'High', 'Normal', 'Low'), default 'Normal'
  implication: This is a legitimate parameter that should be configurable via JSON

- timestamp: 2026-02-02T00:04:00Z
  checked: UI config saving code FFUUI.Core.Config.psm1 line 140
  found: UI SAVES BitsPriority to config: "BitsPriority = $State.Controls.cmbBitsPriority.SelectedItem"
  implication: The UI creates config files with BitsPriority property

- timestamp: 2026-02-02T00:05:00Z
  checked: Phase 36 implementation (FFU.Common.BitsPriority.Tests.ps1)
  found: Complete Pester test suite for BitsPriority functionality (391 lines, 50 tests)
  implication: This feature was fully implemented and tested in milestone v1.10.0

- timestamp: 2026-02-02T00:06:00Z
  checked: Milestone audit v1.10.0-MILESTONE-AUDIT.md line 129
  found: "| 36 | FFU.Updates.CUSkip.Tests.ps1, FFU.Common.BitsPriority.Tests.ps1 | 50 | 100% |"
  implication: Phase 36 was completed and tested, but schema was never updated

## Resolution

root_cause: BitsPriority parameter was added in Phase 36 during v1.10.0 milestone. The UI saves this property to config files, and BuildFFUVM.ps1 accepts it as a parameter, but the JSON schema (ffubuilder-config.schema.json) was never updated to include it as a valid property. This causes pre-flight validation to reject any config file saved by the UI.
fix: Add BitsPriority property to ffubuilder-config.schema.json with enum validation for ['Foreground', 'High', 'Normal', 'Low'] and default 'Normal'
verification:
  - Created standalone test validating all 4 BitsPriority enum values (Foreground, High, Normal, Low) - ALL PASS
  - Tested invalid BitsPriority value correctly rejected with helpful error message
  - Tested config file (simulating user scenario) with BitsPriority - VALIDATED SUCCESSFULLY
  - Ran full Pester test suite: 48/49 tests pass (1 unrelated failure in Make validation)
  - Schema is valid JSON with correct enum definition
files_changed:
  - FFUDevelopment/config/ffubuilder-config.schema.json
