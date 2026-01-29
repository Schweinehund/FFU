# Phase 40: Dell Driver Refactoring (CatalogIndexPC) - Context

**Gathered:** 2026-01-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Refactor Dell driver download to use CatalogIndexPC.cab (~5-10MB lightweight index) instead of CatalogPC.cab (~160MB full catalog). CatalogIndexPC provides per-model catalog URLs, enabling download of only the model-specific cab (1-5MB) rather than the entire driver catalog. Windows Server continues using Catalog.cab (unchanged — no IndexPC variant exists for Server).

</domain>

<decisions>
## Implementation Decisions

### Helper Function Placement
- New functions (Get-DellCatalogIndex, Get-DellClientModels, Resolve-DellCabUrlFromModel) go **internal to FFU.Drivers.psm1** as non-exported helpers
- Follows existing pattern: alongside Get-CachedOEMCatalog, Invoke-DriverDownloadWithRetry
- Zero new files, zero new modules for the build layer
- UI layer (FFUUI.Core.Drivers.Dell.psm1) gets its **own duplicate parsing** — matches existing pattern where Get-DellDriversModelList (UI) and Get-DellDrivers (build) parse XML independently
- No cross-layer dependency between UI and build modules

### Naming Convention
- Match upstream function names exactly: `Get-DellCatalogIndex`, `Get-DellClientModels`, `Resolve-DellCabUrlFromModel`
- Preserves traceability to cherry-picked upstream commits (658c57e, 4ce9183)
- All new helpers remain **non-exported** (module-private) — no need for downstream phases

### Fallback Strategy
- **CatalogIndexPC download failure:** Fall back to CatalogPC.cab with WARNING log
- **Model not found in CatalogIndexPC:** Fall back to full CatalogPC.cab for that model with WARNING log
- **Model-specific cab URL failure:** Fall back to full CatalogPC.cab with WARNING log
- All fallback events logged as **WARNING** (matches PPKG copy fallback precedent from Phase 35)
- Rationale: builds should never fail due to Dell URL changes — 160MB safety net is acceptable

### Cache Behavior
- CatalogIndexPC.cab stored in same directory as old CatalogPC.cab (`$DriversFolder\Dell\`)
- Same 7-day TTL (168 hours) via existing `Get-CachedOEMCatalog` infrastructure
- Old CatalogPC.cab/xml files **kept for fallback** — not deleted on upgrade
- Old files naturally expire; only re-downloaded if fallback actually triggers
- Model-specific cab files also cached with same 7-day TTL in `$DriversFolder\Dell\`

### Persistence & JSON Schema
- Dell entries in Drivers.json gain two new optional fields: `SystemId` and `CabUrl`
  ```json
  { "Name": "Latitude 7490", "SystemId": "0798", "CabUrl": "https://..." }
  ```
- `CabRelativePath` NOT stored (redundant — full CabUrl is sufficient)
- Existing saved configs **silently upgraded on next use** — if SystemId/CabUrl missing, resolve from CatalogIndexPC during next build/model-list refresh and save back
- Follows Lenovo precedent in Import-DriversJson (silently parses missing ProductName/MachineType)
- DriverMapping.json (deploy-time): **SystemId only** — CabUrl is build-time-only concern; SystemId already supported from Phase 39

### Claude's Discretion
- Internal function organization within FFU.Drivers.psm1 (placement relative to existing helpers)
- XML streaming approach for CatalogIndexPC parsing (XmlReader vs DOM — performance tradeoff)
- Exact WARNING message text for fallback events
- Mock data structure for Pester tests (CatalogIndexPC XML samples)
- Whether Get-CachedOEMCatalog needs parameter changes or a new wrapper for model-specific cabs

</decisions>

<specifics>
## Specific Ideas

- Upstream commits to port: `658c57e` (URL/filename swap) and `4ce9183` (core Resolve-DellCabUrlFromModel refactoring)
- CatalogIndexPC entries contain SystemID in model display names as trailing `(XXXX)` — same regex pattern as Phase 39's Dell extraction: `'\(([0-9A-Fa-f]{4})\)\s*$'`
- Windows Server path unchanged — continues downloading `Catalog.cab` from `https://downloads.dell.com/catalog/Catalog.cab`
- Dell CatalogIndexPC URL: `https://downloads.dell.com/catalog/CatalogIndexPC.cab`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 40-dell-driver-refactoring*
*Context gathered: 2026-01-29*
