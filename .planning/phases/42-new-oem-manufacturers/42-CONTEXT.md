# Phase 42: New OEM Manufacturers - Context

**Gathered:** 2026-01-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Add driver download, model listing, and extraction support for 8 new OEM manufacturers: Panasonic, Fujitsu, Getac, Dynabook, Samsung, Acer, ASUS, MSI. Each OEM gets a functional build-time driver download path (catalog, model selection, extraction), UI Make dropdown entry, structured logging, and Pester tests. Deploy-time support already exists upstream (commit d6688de — `Get-NormalizedManufacturer`, `Get-SystemIdentityMetadata` in ApplyFFU.ps1).

</domain>

<decisions>
## Implementation Decisions

### OEM Prioritization and Grouping
- **Tiered approach**: Tier 1 (catalog-based): Panasonic, Fujitsu, Dynabook — have public driver catalogs. Tier 2 (scrape-based): ASUS, Acer, Samsung, MSI — require page scraping or manual. Tier 3 (rugged niche): Getac — limited enterprise catalog.
- **Plan structure**: 1 OEM per plan (8 plans for OEMs + UI integration/tests plan = 9 plans total). Departs from original 5-plan estimate for better granularity.
- **Drop policy**: If an OEM has no usable catalog, create a stub provider that returns an empty model list with a log message. Can be filled in later without re-architecture.
- **Getac stays Tier 3**: Separate plan due to limited catalog availability, even though it's enterprise/rugged like Panasonic.

### Catalog Source Strategy
- **Primary approach**: Support page scraping (HTML parsing), following the Microsoft Surface pattern. Most OEMs have public support/download pages.
- **No upstream build-time implementations exist**: Upstream commit d6688de provides deploy-time matching only. Build-time catalog/download strategy is entirely ours.
- **Caching**: Reuse existing `Get-CachedOEMCatalog` function (7-day TTL, fallback URL) for all new OEMs. Add OEM-specific catalog URLs as FFUConstants.
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
