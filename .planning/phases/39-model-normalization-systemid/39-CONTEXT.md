# Phase 39: Model Name Normalization and SystemID - Context

**Gathered:** 2026-01-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Prevent duplicate brand prefixes in model names and improve SystemID/MachineType extraction for driver matching. Covers Dell, HP, and Lenovo. New OEM manufacturers are Phase 42. Driver matching logic that consumes these identifiers is Phase 41. This phase establishes the normalization and extraction foundations.

Upstream commits: `7dd0023`, `667edf3` (Dell brand dedup), `5071318` (HP AIO/inch normalization), `89601ef` (SystemID extraction in FFU.Common.Drivers), `1af3a0f` (vendor-specific identifiers in ApplyFFU), `489d53f` (Get-SystemIdentityMetadata refactor).

</domain>

<decisions>
## Implementation Decisions

### Normalization Rules
- OEM-specific normalization at catalog parse time (not a generic cross-OEM function)
- **Dell**: Port GroupManifest Display CDATA approach (commit `667edf3`) — prefer `GroupManifest/Display` CDATA stripped of "PDK Catalog for" prefix, falling back to brand+model assembly with StartsWith dedup. Adapt to our XmlReader streaming parser in FFUUI.Core.Drivers.Dell.psm1
- **HP**: Port AIO canonicalization and inch-unit stripping (commit `5071318`) into ConvertTo-ComparableModelName in ApplyFFU.ps1 — `All-in-One`/`AiO` variants to "AIO", strip `23.8-in`/`23.8 inch` to "23.8". Also hoist model normalization outside the matching loop for performance
- **Lenovo**: Leave as-is — no brand prefix duplication observed, existing ProductName + MachineType handling is correct
- Log normalization changes showing before/after strings (match upstream pattern)

### SystemID Extraction
- Match upstream's dual-location approach:
  - **Build-time** (FFU.Common.Drivers.psm1 `Update-DriverMappingJson`): Extract SystemID/MachineType from model name strings + HP PlatformList.xml lookup with caching
  - **Deploy-time** (ApplyFFU.ps1): Extract from WMI/BIOS via `Get-SystemIdentityMetadata` refactored function
- **Dell build-time**: Regex `\(([^)]+)\)\s*$` extracts parenthesized suffix from model name, stored as SystemId
- **Dell deploy-time**: `MS_SystemInformation.SystemSku` primary + `OEMStringArray` bracket-tag fallback
- **HP build-time**: PlatformList.xml lookup with auto-download refresh, 3-tier matching (exact case-insensitive, stripped-to-alphanumeric, contains), per-call hashtable cache
- **HP deploy-time**: `MS_SystemInformation.BaseBoardProduct`
- **Lenovo build-time**: Regex `\(([^)]+)\)\s*$` extracts MachineType from model name
- **Lenovo deploy-time**: First 4 chars of `Win32_ComputerSystem.Model`
- All identifiers normalized to `.Trim().ToUpperInvariant()`
- Port `Get-SystemIdentityMetadata` function to ApplyFFU.ps1 (commit `489d53f`) — returns structured object with ManufacturerNormalized, ModelNormalized, SystemSkuNormalized, FallbackSkuNormalized, MachineTypeNormalized, IdentifierLabel, IdentifierValue
- Port `Get-NormalizedManufacturer` function to ApplyFFU.ps1 — handles Dell, HP/Hewlett, Lenovo, Microsoft/Surface aliases
- Update DriverMapping.json schema: entries optionally include `SystemId` (HP, Dell) or `MachineType` (Lenovo) properties. Phase 41 consumes these for matching.

### Failure Behavior
- Match upstream non-throwing pattern throughout: log message + return `$null` on all failures
- Callers gracefully degrade to model-name-only matching when SystemID/MachineType unavailable
- Never halt a build over a missing SystemID or failed normalization
- HP PlatformList.xml: download failure logged + `$null` cached; parse failure logged + `$null` returned; no match logged + `$null` returned
- WMI unavailable: `-ErrorAction SilentlyContinue`, fields stay `$null`, display shows "Not Detected"

### OEM Coverage Scope
- Dell + HP + Lenovo only (match upstream Phase 39 scope)
- Microsoft minor regex fix (`-notmatch` to `[regex]::IsMatch`) deferred to Phase 41 (Driver Matching)
- 8 new OEMs deferred to Phase 42

### Claude's Discretion
- Exact adaptation of GroupManifest Display CDATA extraction to our XmlReader streaming parser architecture
- Test structure and mock strategy for PlatformList.xml parsing tests
- Whether to inline the HP name normalization scriptblock (upstream pattern) or extract as a proper function

</decisions>

<specifics>
## Specific Ideas

- All upstream commits analyzed and specific implementation patterns identified per commit
- Upstream uses scriptblock variables (`$normalizeHpName`, `$getHpSystemId`) as closures within `Update-DriverMappingJson` — this pattern works but may benefit from extraction to named functions in our modular architecture
- Upstream `Get-SystemIdentityMetadata` in commit `489d53f` is the "final form" — port this rather than the intermediate `1af3a0f` version
- Dell GroupManifest Display approach (commit `667edf3`) supersedes the simpler StartsWith check (commit `7dd0023`) — port the later version

</specifics>

<deferred>
## Deferred Ideas

- Microsoft Surface regex improvement (`-notmatch` to `[regex]::IsMatch`) — Phase 41
- Generic/family-level driver fallback using SystemID — Phase 41
- New OEM manufacturer SystemID patterns — Phase 42
- Module-level PlatformList.xml cache for session reuse — not in upstream, not needed

</deferred>

---

*Phase: 39-model-normalization-systemid*
*Context gathered: 2026-01-29*
