# Phase 42: New OEM Manufacturers - Context

**Gathered:** 2026-01-29
**Updated:** 2026-02-02 (DAT v8 + web research corrections)
**Status:** Ready for planning

<domain>
## Phase Boundary

Add driver download, model listing, and extraction support for 8 new OEM manufacturers: Panasonic, Fujitsu, Getac, Dynabook, Samsung, Acer, ASUS, MSI. Each OEM gets a functional build-time driver download path (catalog, model selection, extraction), UI Make dropdown entry, structured logging, and Pester tests. Deploy-time support already exists upstream (commit d6688de — `Get-NormalizedManufacturer`, `Get-SystemIdentityMetadata` in ApplyFFU.ps1).

</domain>

<decisions>
## Implementation Decisions

### OEM Prioritization and Grouping
- **Tiered approach** (revised 2026-02-02 based on DAT v8 + web research):
  - **Tier 1 (XML/CAB catalog):** Acer, Dynabook, Panasonic — have confirmed structured driver catalogs.
    - Acer: `global-download.acer.com/.../AcerCatalog.xml` (XML, confirmed via DAT v8.0.0)
    - Dynabook: `content.us.dynabook.com/.../Dynabook_DriverPack_Catalog.cab` (CAB→XML, direct URL confirmed)
    - Panasonic: SCCM CAB catalog via deployment tools portal
  - **Tier 2 (Portal + docs):** Samsung, Fujitsu — have support portals with driver packs but no structured XML/CAB catalog.
    - Samsung: HTML portal at `pcmanagement.biz.samsung.com` with SCCM/MDT deployment guides, ZIP driver packs
    - Fujitsu: REST APIs exist but are server-focused (PRIMERGY), unclear for LIFEBOOK laptops
  - **Tier 3 (Stub):** ASUS, MSI, Getac — no reliable automated catalog available.
    - ASUS: Undocumented reverse-engineered JSON APIs only, no official catalog
    - MSI: SDK requires authentication, gaming focus, no public enterprise catalog
    - Getac: SmartUpdate CLI only, no structured catalog
- **Tier changes from original:**
  - Acer: Tier 2 → **Tier 1** (DAT v8 confirmed XML catalog)
  - Fujitsu: Tier 1 → **Tier 2** (REST APIs are server-focused, not client laptops)
  - ASUS: Tier 2 → **Tier 3** (no documented catalog, reverse-engineered only)
  - MSI: Tier 2 → **Tier 3** (SDK requires auth, gaming focus)
- **DAT reference**: Driver Automation Tool v8.0.0 supports Dell, HP, Lenovo, Microsoft, and Acer (new in v8). None of the other 7 Phase 42 targets are supported by any major enterprise driver tool.
- **Plan structure**: Tier-grouped plans (Tier 1 first, then Tier 2, then Tier 3 stubs) + UI integration/tests plan. Revised from 9 individual plans.
- **Drop policy**: If an OEM has no usable catalog, create a stub provider that returns an empty model list with a log message. Can be filled in later without re-architecture.
- **Getac stays Tier 3**: Limited catalog availability, even though it's enterprise/rugged like Panasonic.

### Catalog Source Strategy
- **Tier 1 approach**: Structured XML/CAB catalog download and parsing (like Dell/HP). Acer XML, Dynabook CAB→XML, Panasonic SCCM CAB.
- **Tier 2 approach**: Support page scraping (HTML parsing), following the Microsoft Surface pattern. Samsung and Fujitsu have support portals.
- **Tier 3 approach**: Stub providers returning empty model lists with log messages. ASUS, MSI, Getac lack reliable automated catalogs.
- **No upstream build-time implementations exist**: Upstream commit d6688de provides deploy-time matching only. Build-time catalog/download strategy is entirely ours.
- **Caching**: Reuse existing `Get-CachedOEMCatalog` function (7-day TTL, fallback URL) for Tier 1 and Tier 2 OEMs. Add OEM-specific catalog URLs as FFUConstants.
- **Research requirement**: Each OEM's research phase must identify catalog URL, page structure, and model list format.

### Model Listing Interaction
- **Pattern selection**: Claude's discretion per OEM — auto-populate dropdown (Dell/HP style) where catalogs allow, or search input (Lenovo style) where needed. Based on catalog research findings.
- **UI module structure**: One file per OEM (FFUUI.Core.Drivers.{OEM}.psm1) with `Get-{OEM}DriversModelList` and `Save-{OEM}DriversTask`. Consistent with existing Dell.psm1, HP.psm1, etc.
- **Schema**: Use existing `ConvertTo-StandardizedDriverModel` schema as-is. Map OEM-specific identifiers to the existing `Id` field. No schema changes.
- **Model filtering**: Show all models (no enterprise-only filtering). Users see the full list and scroll to find their model.

### Extraction and Packaging
- **Extraction tools**: Existing tools only — expand.exe (CAB), Expand-Archive (ZIP), Start-Process with /s /e flags (EXE), msiexec /a (MSI). No new dependencies.
- **Installer EXEs**: Use silent extract flags (/s /e, /extract) wherever possible. If an EXE doesn't support silent extraction, skip that driver with a WARNING log.
- **WIM compression**: Yes, same as existing OEMs. Reuse the existing CompressToWim parameter in Save-*DriversTask.
- **Exit codes**: Research all known exit codes per OEM upfront during research phase, then extend `Get-DriverExtractionResult` with OEM-specific classifications.

### Claude's Discretion
- Model listing pattern per OEM (auto-populate vs search input)
- Exact HTML parsing selectors and catalog structure per OEM
- Internal helper function design per OEM
- Order of OEM implementation within each tier
- Whether to create tier-specific shared helper functions or keep each OEM fully independent

</decisions>

<specifics>
## Specific Ideas

- Follow the Microsoft Surface pattern (support page scraping) as the default for OEMs without structured XML/CAB catalogs
- Keep changes minimal and consistent with the existing codebase — no new architectural patterns
- Deploy-time matching already exists in ApplyFFU.ps1 (upstream d6688de): BaseBoardProduct for Panasonic/Getac, BaseBoard SKU for Fujitsu, model name for Samsung/Acer/ASUS/MSI
- Upstream identifies these OEMs: Panasonic Corporation, Fujitsu, Getac, Dynabook (ex-Toshiba), Samsung, Acer, ASUS, MSI

</specifics>

<deferred>
## Deferred Ideas

- **Windows Sandbox driver extraction**: For OEMs that only provide installer EXEs without extraction flags, investigate running the installer silently inside Windows Sandbox and extracting the installed drivers from there for packaging into the driver .wim file. This would enable support for OEMs with non-extractable installer-only drivers.

</deferred>

---

*Phase: 42-new-oem-manufacturers*
*Context gathered: 2026-01-29*
*Context updated: 2026-02-02 (DAT v8 research + tier corrections)*
