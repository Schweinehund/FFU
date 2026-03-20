# Phase 45: Config Schema Extension - Research

**Researched:** 2026-03-20
**Domain:** PowerShell JSON config schema versioning and migration (FFU.ConfigMigration, FFUUI.Core.Config)
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** New `USBMode` top-level section with nested `Artifacts` object keyed by artifact type
- **D-02:** One path per artifact type (not arrays) — USB Mode uses a single artifact per type
- **D-03:** Artifact keys match Phase 46's `[ArtifactType]` enum values: FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO
- **D-04:** Each artifact entry has two fields: `Path` (string or null) and `Disposition` (string enum: Reuse, Rebuild, Skip)
- **D-05:** Default disposition for all artifact types is `Reuse`
- **D-06:** Default path for all artifact types is `null`
- **D-07:** New `ActiveMode` field at top level (not inside USBMode section)
- **D-08:** Valid `ActiveMode` values: `"FullBuild"` or `"USBMode"`
- **D-09:** Default `ActiveMode`: `"FullBuild"` (preserves current behavior for existing configs)
- **D-10:** Existing `BuildUSBDrive`, `USBDriveList`, `MaxUSBDrives` remain at top level
- **D-11:** USB Mode reuses existing `USBDriveList` and `MaxUSBDrives` for drive selection
- **D-12:** `USBMode` section scoped to artifact paths and dispositions only
- **D-13:** Schema version bumps from 1.2 to 1.3
- **D-14:** Migration injects `ActiveMode: "FullBuild"` and full `USBMode.Artifacts` section with null paths and Reuse dispositions
- **D-15:** Existing config data preserved — no fields removed or renamed
- **D-16:** Backup created before migration (pattern: `config.json.backup-{timestamp}`)
- **D-17:** `Get-UIConfig` collects USBMode artifact paths and dispositions from UI state
- **D-18:** `Update-UIFromConfig` applies USBMode fields to UI controls (Phase 48/49 adds actual controls)
- **D-19:** Schema file (`ffubuilder-config.schema.json`) updated with USBMode section definition

### Claude's Discretion
- Internal migration function organization within FFU.ConfigMigration
- Schema JSON structure for `oneOf`/`enum` constraints on Disposition values
- Whether to add schema validation for ActiveMode values or rely on code-level validation
- Test fixture file structure for migration tests

### Deferred Ideas (OUT OF SCOPE)
- Auto-scan artifacts when restoring to USB Mode on startup — Phase 49 behavior
- Saved USB Mode profiles (named configurations per deployment scenario) — REBUILD-04, future requirement
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CONFIG-01 | Config schema extended with USB Mode fields (artifact paths, dispositions) | Schema JSON Draft-07 patterns verified; USBMode section structure defined via D-01 through D-12 |
| CONFIG-02 | Config migration adds USB Mode defaults for existing configs | Invoke-FFUConfigMigration pattern verified; v1.2→v1.3 step follows established additive-defaults pattern |
</phase_requirements>

## Summary

Phase 45 extends the FFU Builder config schema from version 1.2 to 1.3, adding a `USBMode` top-level section and an `ActiveMode` top-level field. The migration is purely additive — no existing keys are removed or renamed — following the exact pattern used by the v1.1 (IncludePreviewUpdates) and v1.2 (VMwareSettings) migrations.

The work touches four files: `FFU.ConfigMigration.psm1` (add migration step + bump `$script:CurrentConfigSchemaVersion`), `FFU.ConfigMigration.psd1` (bump module version), `ffubuilder-config.schema.json` (add `ActiveMode` and `USBMode` property definitions + relax `additionalProperties`), and `FFUUI.Core.Config.psm1` (add USBMode read/write stubs to `Get-UIConfig` and `Update-UIFromConfig`). The Pester migration test exercises the v1.2→v1.3 path with before/after hashtable fixtures; no JSON fixture files on disk are needed.

**Primary recommendation:** Follow the VMwareSettings v1.2 migration block exactly — guard with `ContainsKey`, inject full defaults in one `#region`, bump `$script:CurrentConfigSchemaVersion` to `"1.3"`, and update module version to `1.2.0`.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFU.ConfigMigration | 1.1.1 → 1.2.0 | Schema versioning, migration orchestration | Only migration module in project; established pattern |
| FFUUI.Core.Config | 0.0.20 (FFUUI.Core) | UI config read/write | Only UI config I/O module in project |
| ffubuilder-config.schema.json | JSON Schema Draft-07 | IDE validation, autocomplete | Existing schema file at `FFUDevelopment/config/` |
| Pester 5.x | 5.x | Unit/integration tests | Project standard test framework |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ConvertTo-HashtableRecursive | (in FFU.ConfigMigration) | PS5.1-safe JSON→hashtable | Used in all migration tests and integration flows |

**Installation:** No new packages. All libraries already present in the repository.

## Architecture Patterns

### Recommended Project Structure

This phase modifies existing files only — no new files except test files:

```
FFUDevelopment/
├── Modules/FFU.ConfigMigration/
│   ├── FFU.ConfigMigration.psm1     # Add v1.3 migration block + bump $script:CurrentConfigSchemaVersion
│   └── FFU.ConfigMigration.psd1     # Bump ModuleVersion 1.1.1 → 1.2.0, add ReleaseNotes
├── FFUUI.Core/
│   └── FFUUI.Core.Config.psm1       # Add USBMode I/O stubs to Get-UIConfig / Update-UIFromConfig
└── config/
    └── ffubuilder-config.schema.json # Add ActiveMode + USBMode property definitions

Tests/Unit/
└── FFU.ConfigMigration.Tests.ps1    # Add v1.2→v1.3 migration test cases
```

### Pattern 1: Additive Migration Block (Existing Pattern)

Every migration step follows this structure in `Invoke-FFUConfigMigration`:

```powershell
# Source: FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1 lines 426-452
#region Migration: Add VMwareSettings defaults (v1.2)
if (-not $migrated.ContainsKey('VMwareSettings')) {
    $migrated['VMwareSettings'] = @{
        NetworkType = 'nat'
        NicType = 'e1000e'
    }
    $changes += "Added default 'VMwareSettings' (NetworkType=nat, NicType=e1000e)"
}
elseif ($migrated['VMwareSettings'] -is [hashtable]) {
    # Handle partial existing object — fill in missing keys
    if (-not $migrated['VMwareSettings'].ContainsKey('NetworkType')) {
        $migrated['VMwareSettings']['NetworkType'] = 'nat'
        $changes += "Added missing 'VMwareSettings.NetworkType=nat'"
    }
    if (-not $migrated['VMwareSettings'].ContainsKey('NicType')) {
        $migrated['VMwareSettings']['NicType'] = 'e1000e'
        $changes += "Added missing 'VMwareSettings.NicType=e1000e'"
    }
}
#endregion
```

**Apply for v1.3:** Two new `#region` blocks — one for `ActiveMode`, one for `USBMode`.

### Pattern 2: v1.3 Migration Blocks (New)

```powershell
#region Migration: Add ActiveMode default (v1.3)
if (-not $migrated.ContainsKey('ActiveMode')) {
    $migrated['ActiveMode'] = 'FullBuild'
    $changes += "Added default 'ActiveMode=FullBuild' (USB Mode support)"
}
#endregion

#region Migration: Add USBMode defaults (v1.3)
$artifactTypes = @('FFU', 'DeployISO', 'Drivers', 'PPKG', 'Unattend', 'Autopilot', 'AppsISO')
if (-not $migrated.ContainsKey('USBMode')) {
    $artifacts = @{}
    foreach ($type in $artifactTypes) {
        $artifacts[$type] = @{ Path = $null; Disposition = 'Reuse' }
    }
    $migrated['USBMode'] = @{ Artifacts = $artifacts }
    $changes += "Added default 'USBMode.Artifacts' with null paths and Reuse dispositions"
}
elseif ($migrated['USBMode'] -is [hashtable]) {
    # Handle partial USBMode — ensure Artifacts key exists
    if (-not $migrated['USBMode'].ContainsKey('Artifacts')) {
        $artifacts = @{}
        foreach ($type in $artifactTypes) {
            $artifacts[$type] = @{ Path = $null; Disposition = 'Reuse' }
        }
        $migrated['USBMode']['Artifacts'] = $artifacts
        $changes += "Added missing 'USBMode.Artifacts' section"
    }
    else {
        # Ensure all 7 artifact types exist
        foreach ($type in $artifactTypes) {
            if (-not $migrated['USBMode']['Artifacts'].ContainsKey($type)) {
                $migrated['USBMode']['Artifacts'][$type] = @{ Path = $null; Disposition = 'Reuse' }
                $changes += "Added missing USBMode artifact entry '$type'"
            }
        }
    }
}
#endregion
```

### Pattern 3: Schema Version Constant Update

```powershell
# Source: FFU.ConfigMigration.psm1 line 27 — ONLY place to change version
$script:CurrentConfigSchemaVersion = "1.3"  # was "1.2"
```

**Critical:** `Get-FFUConfigSchemaVersion` returns this variable. `Test-FFUConfigVersion` uses this function. The fallback string literal in `FFUUI.Core.Config.psm1` line 27 must also be updated to `"1.3"`.

### Pattern 4: JSON Schema Property Definitions

The schema uses `"additionalProperties": false` at the root level (line 654). Any new top-level key must be added to `"properties"`.

**ActiveMode** (top-level, string enum):
```json
"ActiveMode": {
    "type": "string",
    "enum": ["FullBuild", "USBMode"],
    "default": "FullBuild",
    "description": "Active operational mode. 'FullBuild' = standard FFU build pipeline. 'USBMode' = assemble USB from existing artifacts without rebuilding."
}
```

**USBMode** (top-level object with nested Artifacts):
```json
"USBMode": {
    "type": "object",
    "description": "USB Mode configuration — artifact paths and dispositions for USB assembly from existing artifacts.",
    "properties": {
        "Artifacts": {
            "type": "object",
            "description": "Per-artifact-type path overrides and dispositions. Keys match ArtifactType enum: FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO.",
            "properties": {
                "FFU":       { "$ref": "#/definitions/ArtifactEntry" },
                "DeployISO": { "$ref": "#/definitions/ArtifactEntry" },
                "Drivers":   { "$ref": "#/definitions/ArtifactEntry" },
                "PPKG":      { "$ref": "#/definitions/ArtifactEntry" },
                "Unattend":  { "$ref": "#/definitions/ArtifactEntry" },
                "Autopilot": { "$ref": "#/definitions/ArtifactEntry" },
                "AppsISO":   { "$ref": "#/definitions/ArtifactEntry" }
            }
        }
    },
    "required": ["Artifacts"]
}
```

**ArtifactEntry definition** (add to schema `"definitions"` section — the current schema has no `definitions` section, so it must be added):
```json
"definitions": {
    "ArtifactEntry": {
        "type": "object",
        "properties": {
            "Path": {
                "oneOf": [
                    { "type": "string" },
                    { "type": "null" }
                ],
                "default": null,
                "description": "Override path for this artifact. Null = use default discovery from FFUDevelopmentPath."
            },
            "Disposition": {
                "type": "string",
                "enum": ["Reuse", "Rebuild", "Skip"],
                "default": "Reuse",
                "description": "Build disposition: 'Reuse' = use existing artifact as-is, 'Rebuild' = regenerate this artifact, 'Skip' = exclude from USB."
            }
        },
        "required": ["Disposition"]
    }
}
```

**Alternative:** If avoiding `$ref` (to keep the schema self-contained), inline the ArtifactEntry definition directly in each artifact key. This is verbose (7x repetition) but avoids adding a `definitions` section to an existing schema that has none. Research recommendation: use `$ref` + `definitions` — JSON Schema Draft-07 fully supports it.

### Pattern 5: Get-UIConfig USB Mode Stubs

In `FFUUI.Core.Config.psm1`, `Get-UIConfig` builds an ordered hashtable. Add at the end of the hashtable literal (after line 163):

```powershell
# Phase 49 will populate these from browse dialogs and disposition controls.
# For now, write null/default values so the config round-trips without error.
ActiveMode = 'FullBuild'  # Phase 48 will write the actual mode state
USBMode    = @{
    Artifacts = @{
        FFU       = @{ Path = $null; Disposition = 'Reuse' }
        DeployISO = @{ Path = $null; Disposition = 'Reuse' }
        Drivers   = @{ Path = $null; Disposition = 'Reuse' }
        PPKG      = @{ Path = $null; Disposition = 'Reuse' }
        Unattend  = @{ Path = $null; Disposition = 'Reuse' }
        Autopilot = @{ Path = $null; Disposition = 'Reuse' }
        AppsISO   = @{ Path = $null; Disposition = 'Reuse' }
    }
}
```

Phase 49 will replace these stubs with live UI control reads. Phase 48 will write `ActiveMode` from the mode toggle state.

### Pattern 6: Update-UIFromConfig USB Mode Stubs

`Update-UIFromConfig` uses `Set-UIValue` for simple controls and inline PSObject property checks for complex ones (see the VMwareNetworkType/NicType pattern at lines 568-584). For Phase 45, add a stub that reads the fields silently (no control to apply to yet):

```powershell
# USB Mode fields — controls added in Phase 48/49
# Stub: read and log for now; Phase 48 will apply ActiveMode to mode toggle
if ($ConfigContent.PSObject.Properties.Match('ActiveMode').Count -gt 0) {
    WriteLog "LoadConfig: ActiveMode='$($ConfigContent.ActiveMode)' (Phase 48 will apply to toggle)."
}
if ($ConfigContent.PSObject.Properties.Match('USBMode').Count -gt 0) {
    WriteLog "LoadConfig: USBMode section present (Phase 49 will apply to artifact controls)."
}
```

### Anti-Patterns to Avoid

- **Hardcoding "1.2" as the fallback version:** The fallback string in `FFUUI.Core.Config.psm1` line 27 must be updated to `"1.3"` — it exists precisely because `Get-FFUConfigSchemaVersion` may not be importable.
- **Skipping partial-USBMode guard:** The v1.2 VMwareSettings migration checks for a partial object with missing keys. The v1.3 migration must do the same for `USBMode` lacking `Artifacts`, and for `Artifacts` lacking individual type keys.
- **Using typed `[ArtifactType]` enum in migration:** The migration module does NOT import FFU.ArtifactScanner — use bare string keys `'FFU'`, `'DeployISO'`, etc. (matches enum string representation).
- **Setting `additionalProperties: false` on nested USBMode:** Leave it open so Phase 48/49 can add fields without another migration.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config version comparison | Custom string compare | `[System.Version]::Parse()` (already in Test-FFUConfigVersion) | Handles 1.9 < 1.10 correctly; string compare fails |
| PS5.1 JSON hashtable | `ConvertFrom-Json -AsHashtable` | `ConvertTo-HashtableRecursive` (already exported) | PS5.1 lacks `-AsHashtable`; existing function handles nested objects |
| JSON serialization | Custom | `ConvertTo-Json -Depth 10` | Already used in `Invoke-SaveConfiguration` line 991 |
| Migration backup | Custom timestamp logic | `Get-Date -Format 'yyyyMMdd-HHmmss'` (lines 338-341) | Exact pattern already established; don't deviate |

**Key insight:** This phase is ~90% wiring existing infrastructure. The migration pattern is fully established — the only net-new logic is the two `#region` blocks and the JSON schema additions.

## Common Pitfalls

### Pitfall 1: Fallback Version Literal Not Updated
**What goes wrong:** `FFUUI.Core.Config.psm1` line 27 has a hardcoded `"1.2"` fallback. If `Get-FFUConfigSchemaVersion` fails to load (e.g. early in session), the saved config writes `configSchemaVersion: "1.2"`, triggering migration on every load.
**Why it happens:** The fallback was introduced to handle module load timing. It mirrors the constant.
**How to avoid:** Update the fallback string to `"1.3"` in the same plan as bumping `$script:CurrentConfigSchemaVersion`.
**Warning signs:** Tests that save and reload a config find `NeedsMigration=$true` immediately after save.

### Pitfall 2: `additionalProperties: false` at Schema Root
**What goes wrong:** Adding `ActiveMode` or `USBMode` to a config without updating the schema causes JSON Schema validation to reject the config in IDEs.
**Why it happens:** Line 654 of `ffubuilder-config.schema.json` reads `"additionalProperties": false`.
**How to avoid:** Add both new property definitions to the `"properties"` object before any test save.
**Warning signs:** VSCode shows red squiggles on `ActiveMode` or `USBMode` in config files.

### Pitfall 3: Migration Runs on Already-Migrated v1.3 Configs
**What goes wrong:** If the `ContainsKey` guard is missing for the full `USBMode` block, an already-migrated config gets a change entry logged and the backup timestamp changes on every load.
**Why it happens:** The v1.2 VMwareSettings block uses `if (-not $migrated.ContainsKey('VMwareSettings'))` — if omitted, the block always runs.
**How to avoid:** Wrap the entire v1.3 injection in `if (-not $migrated.ContainsKey('USBMode'))` and a corresponding `if (-not $migrated.ContainsKey('ActiveMode'))`.
**Warning signs:** `$result.Changes` contains entries for a config that was already v1.3.

### Pitfall 4: Test Expects `$result.Config.configSchemaVersion -eq '1.0'`
**What goes wrong:** Existing integration test at `FFU.ConfigMigration.Integration.Tests.ps1` line 67 asserts `$result.Config.configSchemaVersion | Should -Be '1.0'`. After bumping `$script:CurrentConfigSchemaVersion` to `"1.3"`, this test will fail.
**Why it happens:** The test was written when 1.0 was target version; it now needs to assert `1.3`.
**How to avoid:** Update the assertion in the existing integration test. Also update `It 'returns "1.2" as current version'` in `FFU.ConfigMigration.Tests.ps1` line 69 to assert `"1.3"`.
**Warning signs:** Existing migration tests fail in the Pester run before any new tests are written.

### Pitfall 5: USBMode Artifacts Nested in Alphabetical Sort
**What goes wrong:** `Invoke-SaveConfiguration` sorts top-level keys alphabetically (line 990). Nested hashtable keys inside `USBMode.Artifacts` are NOT sorted. Consumers in Phase 49/50 must not depend on key order within `Artifacts`.
**Why it happens:** The alphabetical sort only runs on `$config.Keys` (top level). `ConvertTo-Json -Depth 10` serializes nested hashtables in insertion order.
**How to avoid:** Document that `Artifacts` key order is unspecified; always access by key name, not index.
**Warning signs:** Phase 50 code using `$config.USBMode.Artifacts[0]` instead of `$config.USBMode.Artifacts['FFU']`.

## Code Examples

### Example 1: v1.3 Migration Round-Trip (Test Pattern)

```powershell
# Pattern used in FFU.ConfigMigration.Tests.ps1 and .Integration.Tests.ps1
$v12Config = @{
    configSchemaVersion = '1.2'
    FFUDevelopmentPath  = 'C:\FFU'
    VMwareSettings      = @{ NetworkType = 'nat'; NicType = 'e1000e' }
    IncludePreviewUpdates = $false
}
$result = Invoke-FFUConfigMigration -Config $v12Config

$result.Config.configSchemaVersion      | Should -Be '1.3'
$result.Config.ActiveMode               | Should -Be 'FullBuild'
$result.Config.ContainsKey('USBMode')   | Should -BeTrue
$result.Config.USBMode.Artifacts.ContainsKey('FFU')       | Should -BeTrue
$result.Config.USBMode.Artifacts.FFU.Disposition          | Should -Be 'Reuse'
$result.Config.USBMode.Artifacts.FFU.Path                 | Should -BeNullOrEmpty
# Existing data preserved
$result.Config.VMwareSettings.NetworkType | Should -Be 'nat'
$result.Config.FFUDevelopmentPath         | Should -Be 'C:\FFU'
```

### Example 2: Legacy Config (0.0) Migrates All the Way to 1.3

```powershell
# The migration function runs ALL additive blocks regardless of source version
$legacy = @{
    FFUDevelopmentPath = 'C:\FFU'
    AppsPath           = 'C:\FFU\Apps'
    InstallWingetApps  = $true
}
$result = Invoke-FFUConfigMigration -Config $legacy
$result.Config.configSchemaVersion | Should -Be '1.3'
$result.Config.ContainsKey('USBMode') | Should -BeTrue
```

### Example 3: Get-UIConfig USBMode Stub (Phase 45 form)

```powershell
# In the Get-UIConfig ordered hashtable, after line 163
# Source: FFUUI.Core/FFUUI.Core.Config.psm1 — to be added
ActiveMode = 'FullBuild'
USBMode    = @{
    Artifacts = @{
        FFU       = @{ Path = $null; Disposition = 'Reuse' }
        DeployISO = @{ Path = $null; Disposition = 'Reuse' }
        Drivers   = @{ Path = $null; Disposition = 'Reuse' }
        PPKG      = @{ Path = $null; Disposition = 'Reuse' }
        Unattend  = @{ Path = $null; Disposition = 'Reuse' }
        Autopilot = @{ Path = $null; Disposition = 'Reuse' }
        AppsISO   = @{ Path = $null; Disposition = 'Reuse' }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `[System.Version]` string compare | Already using `[System.Version]::Parse()` | v1.0 (initial) | Handles 1.9 < 1.10 correctly |
| `ConvertFrom-Json -AsHashtable` | `ConvertTo-HashtableRecursive` for PS5.1 compat | v1.0 (initial) | No change needed |
| Hardcoded migration target | `$script:CurrentConfigSchemaVersion` constant | v1.0 (initial) | No change needed |

**No deprecated approaches in scope.** This phase is purely additive.

## Open Questions

1. **Should `$ref` + `definitions` be used in the schema, or inline repetition?**
   - What we know: JSON Schema Draft-07 supports `$ref`. The current schema at line 1 declares `"$schema": "http://json-schema.org/draft-07/schema#"`. No `definitions` section exists yet.
   - What's unclear: Whether VS Code's JSON Schema validator in this project handles `$ref` to `#/definitions/` correctly (it should for Draft-07).
   - Recommendation: Use `$ref` + `definitions`. It's DRY and the schema already declares Draft-07. If VS Code tooling has issues, fall back to inline repetition in a subsequent fixup.

2. **Where should `ActiveMode` and `USBMode` appear in alphabetical key order in saved configs?**
   - What we know: `Invoke-SaveConfiguration` sorts top-level keys alphabetically (line 990). `A` < `U`, so `ActiveMode` sorts near the top; `USBMode` sorts after `UpdateLatestNet48`.
   - What's unclear: Nothing — this is deterministic.
   - Recommendation: No action needed; the sort is automatic.

3. **Does `FFUUI.Core.Config.psm1` need updating beyond the stub?**
   - What we know: Phase 49 adds browse dialog controls that will write to `USBMode.Artifacts.{type}.Path`. Phase 48 adds the mode toggle that writes `ActiveMode`. This phase only needs the schema + migration + stubs.
   - What's unclear: Nothing — CONTEXT.md D-17/D-18 explicitly state stubs only.
   - Recommendation: Add stubs now (write defaults out, log on read); full I/O in Phases 48/49.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Pester 5.x |
| Config file | No dedicated pester.ps1 — tests run via `Invoke-PesterTests.ps1` |
| Quick run command | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ConfigMigration'` |
| Full suite command | `.\Tests\Unit\Invoke-PesterTests.ps1` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONFIG-01 | Schema has `ActiveMode` and `USBMode.Artifacts` properties | unit | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ConfigMigration'` | ❌ Wave 0 — add to FFU.ConfigMigration.Tests.ps1 |
| CONFIG-02 | v1.2→v1.3 migration injects defaults without data loss | unit | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ConfigMigration'` | ❌ Wave 0 — add to FFU.ConfigMigration.Tests.ps1 |
| CONFIG-02 | Legacy (0.0) config reaches v1.3 via single migration call | unit | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ConfigMigration'` | ❌ Wave 0 |
| CONFIG-02 | Already-v1.3 config not re-migrated | unit | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ConfigMigration'` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ConfigMigration'`
- **Per wave merge:** `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] New `Describe 'v1.3 Migration'` block in `Tests/Unit/FFU.ConfigMigration.Tests.ps1`
- [ ] Update `It 'returns "1.2" as current version'` → `"1.3"` in existing tests
- [ ] Update existing integration test assertion `Should -Be '1.0'` → `'1.3'` in `FFU.ConfigMigration.Integration.Tests.ps1` line 67
- [ ] No new test files needed — extend existing migration test files

## Sources

### Primary (HIGH confidence)
- `FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1` — migration pattern (lines 426-452 for VMwareSettings v1.2 block, line 27 for version constant)
- `FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psd1` — module version 1.1.1, release notes pattern
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` — Get-UIConfig (lines 13-203), Update-UIFromConfig (lines 505-966), fallback version literal (line 27)
- `FFUDevelopment/config/ffubuilder-config.schema.json` — `additionalProperties: false` at root (line 654), VMwareSettings example (lines 197-215), Draft-07 declaration
- `FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1` — `enum ArtifactType` (lines 29-37): FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO
- `Tests/Unit/FFU.ConfigMigration.Tests.ps1` — test structure, version assertion at line 69
- `Tests/Unit/FFU.ConfigMigration.Integration.Tests.ps1` — integration test, version assertion at line 67

### Secondary (MEDIUM confidence)
- `.planning/phases/45-config-schema-extension/45-CONTEXT.md` — all locked decisions D-01 through D-19

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in project, no new dependencies
- Architecture: HIGH — v1.3 migration pattern is a direct application of the verified v1.2 VMwareSettings pattern
- Pitfalls: HIGH — discovered by reading existing code and tests, not speculation

**Research date:** 2026-03-20
**Valid until:** 2026-06-20 (stable migration module; no fast-moving dependencies)
