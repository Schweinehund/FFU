# Phase 42: New OEM Manufacturers - Research

**Produced:** 2026-02-02
**Sources:** Driver Automation Tool v8.0.0 source, web research, codebase exploration
**Consumed by:** gsd-planner for 42-0X-PLAN.md generation

---

## 1. Per-OEM Research

### 1.1 Acer (Tier 1 — XML Catalog)

| Field | Value |
|-------|-------|
| **Catalog URL** | `https://global-download.acer.com/GDFiles/Driver/SCCM/AcerCatalog.xml` |
| **Catalog Format** | XML (direct download, no CAB wrapping) |
| **Discovery Source** | Driver Automation Tool v8.0.0 — Acer added as 5th OEM |
| **Model List Retrieval** | Parse XML `<ModelList>/<Model>` nodes. Each `<Model>` has `name` attribute and child `<SCCM>` elements keyed by OS version. |
| **Driver Package Format** | CAB or ZIP (linked from `<SCCM>` URL in catalog XML) |
| **Silent Extraction** | `expand.exe` for CAB; `Expand-Archive` for ZIP |
| **Known Exit Codes** | Standard expand.exe codes (0=success). No vendor-specific codes documented. |
| **SCCM/MDT Support** | Yes — catalog is SCCM-native. DAT v8 uses it for SCCM deployment. |
| **Implementation Complexity** | **Low** — structured XML catalog, similar to Dell CatalogPC pattern |
| **UI Pattern** | Auto-populate dropdown (parse all `<Model>` names from catalog) |

**Catalog XML Schema (expected):**
```xml
<AcerCatalog>
  <ModelList>
    <Model name="Aspire 5 A515-56">
      <SCCM os="Windows 11" version="23H2">https://global-download.acer.com/.../drivers.cab</SCCM>
      <SCCM os="Windows 11" version="24H2">https://global-download.acer.com/.../drivers.cab</SCCM>
    </Model>
    <!-- ... -->
  </ModelList>
</AcerCatalog>
```

**Notes:**
- DAT v8 treats Acer identically to Dell/HP/Lenovo — full catalog parse, model selection, driver download.
- Exact XML schema should be validated during implementation by fetching the catalog.
- `Get-CachedOEMCatalog` can be reused directly with this URL.

---

### 1.2 Dynabook (Tier 1 — CAB→XML Catalog)

| Field | Value |
|-------|-------|
| **Catalog URL** | `https://content.us.dynabook.com/content/support/drivers/Dynabook_DriverPack_Catalog.cab` |
| **Catalog Format** | CAB containing XML (same pattern as Dell CatalogPC.cab → CatalogPC.xml) |
| **Discovery Source** | Direct URL confirmed accessible via web research |
| **Model List Retrieval** | Download CAB → extract XML → parse model nodes |
| **Driver Package Format** | CAB driver packs (SCCM-ready) |
| **Silent Extraction** | `expand.exe` for CAB extraction |
| **Known Exit Codes** | Standard expand.exe codes. No vendor-specific codes documented. |
| **SCCM/MDT Support** | Yes — CAB catalog is designed for SCCM integration |
| **Implementation Complexity** | **Low** — CAB→XML pattern identical to existing Dell implementation |
| **UI Pattern** | Auto-populate dropdown (parse model list from extracted XML) |

**Notes:**
- Dynabook (formerly Toshiba) provides enterprise-grade SCCM driver packs.
- CAB→XML extraction follows the exact same pattern as Dell `CatalogPC.cab`.
- Can likely reuse most of the Dell catalog parsing logic with minor schema adjustments.
- Exact XML schema inside the CAB needs to be validated during implementation.

---

### 1.3 Panasonic (Tier 1 — SCCM CAB Catalog)

| Field | Value |
|-------|-------|
| **Catalog URL** | Available via Panasonic deployment tools portal (SCCM catalog CAB) |
| **Catalog Format** | SCCM CAB catalog (similar to Dell/Dynabook pattern) |
| **Discovery Source** | Panasonic SCCM deployment documentation, enterprise admin forums |
| **Model List Retrieval** | Download CAB → extract catalog XML → parse TOUGHBOOK/TOUGHPAD models |
| **Driver Package Format** | CAB driver packs |
| **Silent Extraction** | `expand.exe` for CAB |
| **Known Exit Codes** | Standard expand.exe codes. No vendor-specific codes documented. |
| **SCCM/MDT Support** | Yes — Panasonic provides official SCCM integration for TOUGHBOOK line |
| **Implementation Complexity** | **Low-Medium** — structured catalog, but URL may require portal access or registration |
| **UI Pattern** | Auto-populate dropdown (TOUGHBOOK model list is finite, ~20-30 current models) |

**Notes:**
- Panasonic focuses on rugged enterprise (TOUGHBOOK, TOUGHPAD). Model list is smaller than consumer OEMs.
- Deploy-time matching uses `BaseBoardProduct` (upstream d6688de).
- If catalog URL requires portal authentication, fall back to a known-models static list approach.
- Exact catalog URL needs validation during implementation — may need to scrape from Panasonic's partner portal.

---

### 1.4 Samsung (Tier 2 — HTML Portal)

| Field | Value |
|-------|-------|
| **Catalog URL** | `https://pcmanagement.biz.samsung.com` (Enterprise PC Management portal) |
| **Catalog Format** | HTML portal (no structured XML/CAB) |
| **Discovery Source** | Web research — Samsung Enterprise PC Management site |
| **Model List Retrieval** | Parse HTML support pages or use known Samsung PC models (Galaxy Book series) |
| **Driver Package Format** | ZIP driver packs available from portal |
| **Silent Extraction** | `Expand-Archive` for ZIP |
| **Known Exit Codes** | Standard ZIP extraction codes. No vendor-specific codes. |
| **SCCM/MDT Support** | Yes — Samsung provides SCCM/MDT deployment guides and driver pack ZIPs |
| **Implementation Complexity** | **Medium** — HTML parsing required, but good SCCM documentation exists |
| **UI Pattern** | Auto-populate dropdown (Galaxy Book model list is manageable, ~15-20 models) or search input |

**Notes:**
- Samsung's enterprise portal at `pcmanagement.biz.samsung.com` has driver packs specifically for SCCM/MDT.
- Galaxy Book Pro, Galaxy Book3, Galaxy Book4 series are the primary targets.
- HTML parsing may be fragile — consider a static model list with periodic updates as fallback.
- Deploy-time matching uses model name (upstream d6688de).

---

### 1.5 Fujitsu (Tier 2 — Portal with Server-Focused APIs)

| Field | Value |
|-------|-------|
| **Catalog URL** | Fujitsu support portal; REST APIs exist for PRIMERGY servers |
| **Catalog Format** | HTML portal for LIFEBOOK/STYLISTIC; REST API for servers |
| **Discovery Source** | Web research — Fujitsu support sites |
| **Model List Retrieval** | Parse Fujitsu support pages for LIFEBOOK/STYLISTIC models |
| **Driver Package Format** | EXE installers, ZIP archives (varies by model) |
| **Silent Extraction** | `/extract` or `/s /e` flags for EXE; `Expand-Archive` for ZIP |
| **Known Exit Codes** | Standard Windows Installer codes. No vendor-specific codes documented. |
| **SCCM/MDT Support** | Limited — Fujitsu provides some SCCM packs for enterprise models, not comprehensive |
| **Implementation Complexity** | **Medium-High** — fragmented catalog, mixed download formats |
| **UI Pattern** | Search input (Lenovo-style) due to large product range spanning regions |

**Notes:**
- Fujitsu was originally classified as Tier 1 but moved to Tier 2 because the REST APIs are server-focused (PRIMERGY), not client laptops (LIFEBOOK).
- LIFEBOOK and STYLISTIC (tablet) lines are the primary enterprise targets.
- May require region-specific URLs (Fujitsu has different support sites per region).
- Deploy-time matching uses `BaseBoard SKU` (upstream d6688de).
- Consider implementing as search-based (Lenovo pattern) with HTML scraping of results.

---

### 1.6 ASUS (Tier 3 — Stub)

| Field | Value |
|-------|-------|
| **Catalog URL** | None — undocumented reverse-engineered JSON APIs only |
| **Catalog Format** | No official structured catalog |
| **Discovery Source** | Web research — community reverse-engineering efforts |
| **Model List Retrieval** | N/A for initial implementation (stub) |
| **Driver Package Format** | EXE installers from ASUS support site |
| **Silent Extraction** | Unknown per-driver — ASUS uses various installer technologies |
| **Known Exit Codes** | Unknown — no documented enterprise deployment codes |
| **SCCM/MDT Support** | No official SCCM/MDT support |
| **Implementation Complexity** | **High** — no official API, reverse-engineered only |
| **UI Pattern** | Stub — returns empty model list with log message |

**Notes:**
- ASUS has no public enterprise driver catalog. Community efforts have reverse-engineered JSON APIs but these are undocumented and may change without notice.
- Originally classified as Tier 2 but moved to Tier 3 due to lack of any official catalog.
- Stub provider: `Get-ASUSDriversModelList` returns empty list, logs "ASUS driver automation not yet supported — no official catalog available."
- Can be upgraded later if ASUS releases enterprise tools.

---

### 1.7 MSI (Tier 3 — Stub)

| Field | Value |
|-------|-------|
| **Catalog URL** | MSI SDK requires authentication; no public catalog |
| **Catalog Format** | No public structured catalog |
| **Discovery Source** | Web research — MSI developer portal |
| **Model List Retrieval** | N/A for initial implementation (stub) |
| **Driver Package Format** | EXE installers from MSI support site |
| **Silent Extraction** | Unknown per-driver — MSI uses various installer technologies |
| **Known Exit Codes** | Unknown — no documented enterprise deployment codes |
| **SCCM/MDT Support** | No official SCCM/MDT support (gaming/creator focus) |
| **Implementation Complexity** | **High** — SDK requires auth, primarily gaming/creator hardware |
| **UI Pattern** | Stub — returns empty model list with log message |

**Notes:**
- MSI focuses on gaming and creator hardware, not enterprise deployment.
- The MSI SDK exists but requires authentication and is not publicly documented.
- Originally classified as Tier 2 but moved to Tier 3 due to auth requirements and gaming focus.
- Stub provider: `Get-MSIDriversModelList` returns empty list, logs "MSI driver automation not yet supported — SDK requires authentication."
- Low priority for future implementation given MSI's non-enterprise focus.

---

### 1.8 Getac (Tier 3 — Stub)

| Field | Value |
|-------|-------|
| **Catalog URL** | None — SmartUpdate CLI only |
| **Catalog Format** | No structured catalog |
| **Discovery Source** | Web research — Getac support tools |
| **Model List Retrieval** | N/A for initial implementation (stub) |
| **Driver Package Format** | Getac SmartUpdate packages |
| **Silent Extraction** | SmartUpdate CLI has silent flags but requires proprietary tooling |
| **Known Exit Codes** | SmartUpdate-specific codes — not documented publicly |
| **SCCM/MDT Support** | Limited — Getac provides some SCCM integration via SmartUpdate |
| **Implementation Complexity** | **High** — proprietary tooling required |
| **UI Pattern** | Stub — returns empty model list with log message |

**Notes:**
- Getac's rugged devices (B360, V110, F110, K120, UX10) are enterprise-focused but use proprietary SmartUpdate tool.
- Deploy-time matching uses `BaseBoardProduct` (upstream d6688de).
- Stub provider: `Get-GetacDriversModelList` returns empty list, logs "Getac driver automation not yet supported — requires SmartUpdate CLI."
- Could potentially be upgraded later by wrapping SmartUpdate CLI if Getac provides silent operation flags.

---

## 2. Shared Infrastructure Analysis

### 2.1 Codebase Touchpoints (Required Changes)

#### ValidateSet Updates (4 locations)

| File | Line | Current Value | Add Values |
|------|------|---------------|------------|
| `FFU.Drivers.psm1` | 171 | `'Dell', 'HP', 'Lenovo', 'Microsoft'` | `'Acer', 'Dynabook', 'Panasonic', 'Samsung', 'Fujitsu', 'ASUS', 'MSI', 'Getac'` |
| `FFU.Drivers.psm1` | 372 | `'Dell', 'HP', 'Lenovo'` | `'Acer', 'Dynabook', 'Panasonic', 'Samsung', 'Fujitsu'` (Tier 1+2 only, catalog-based) |
| `FFU.Drivers.psm1` | 744 | `'Dell', 'HP', 'Lenovo', 'Microsoft'` | `'Acer', 'Dynabook', 'Panasonic', 'Samsung', 'Fujitsu', 'ASUS', 'MSI', 'Getac'` |
| `BuildFFUVM.ps1` | 343 | `'Microsoft', 'Dell', 'HP', 'Lenovo'` | `'Acer', 'Dynabook', 'Panasonic', 'Samsung', 'Fujitsu', 'ASUS', 'MSI', 'Getac'` |

#### New Functions Required (FFU.Drivers.psm1)

| Function | Tier | Pattern |
|----------|------|---------|
| `Get-AcerDrivers` | 1 | XML catalog parse → driver CAB download → expand.exe |
| `Get-DynabookDrivers` | 1 | CAB→XML catalog parse → driver CAB download → expand.exe |
| `Get-PanasonicDrivers` | 1 | SCCM CAB catalog parse → driver CAB download → expand.exe |
| `Get-SamsungDrivers` | 2 | HTML portal parse → ZIP download → Expand-Archive |
| `Get-FujitsuDrivers` | 2 | HTML portal parse → EXE/ZIP download → extract |
| `Get-ASUSDrivers` | 3 | Stub — logs warning, returns empty |
| `Get-MSIDrivers` | 3 | Stub — logs warning, returns empty |
| `Get-GetacDrivers` | 3 | Stub — logs warning, returns empty |

#### New UI Module Files (FFUUI.Core)

Each OEM needs a `FFUUI.Core.Drivers.{OEM}.psm1` file with:
- `Get-{OEM}DriversModelList` — returns model list for dropdown
- `Save-{OEM}DriversTask` — downloads and extracts drivers for selected model

| File | Functions | Pattern |
|------|-----------|---------|
| `FFUUI.Core.Drivers.Acer.psm1` | `Get-AcerDriversModelList`, `Save-AcerDriversTask` | Dell/HP pattern (auto-populate) |
| `FFUUI.Core.Drivers.Dynabook.psm1` | `Get-DynabookDriversModelList`, `Save-DynabookDriversTask` | Dell pattern (CAB→XML) |
| `FFUUI.Core.Drivers.Panasonic.psm1` | `Get-PanasonicDriversModelList`, `Save-PanasonicDriversTask` | HP pattern (CAB catalog) |
| `FFUUI.Core.Drivers.Samsung.psm1` | `Get-SamsungDriversModelList`, `Save-SamsungDriversTask` | Microsoft pattern (HTML parse) |
| `FFUUI.Core.Drivers.Fujitsu.psm1` | `Get-FujitsuDriversModelList`, `Save-FujitsuDriversTask` | Lenovo pattern (search input) |
| `FFUUI.Core.Drivers.ASUS.psm1` | `Get-ASUSDriversModelList`, `Save-ASUSDriversTask` | Stub (empty list + log) |
| `FFUUI.Core.Drivers.MSI.psm1` | `Get-MSIDriversModelList`, `Save-MSIDriversTask` | Stub (empty list + log) |
| `FFUUI.Core.Drivers.Getac.psm1` | `Get-GetacDriversModelList`, `Save-GetacDriversTask` | Stub (empty list + log) |

#### Get-ModelsForMake Switch Update

`FFUUI.Core.Drivers.psm1:37-60` — Add 8 new cases to the switch block:

```powershell
# Tier 1
'Acer'      { $rawModels = Get-AcerDriversModelList -DriversFolder $localDriversFolder -Make $SelectedMake }
'Dynabook'  { $rawModels = Get-DynabookDriversModelList -DriversFolder $localDriversFolder -Make $SelectedMake }
'Panasonic' { $rawModels = Get-PanasonicDriversModelList -DriversFolder $localDriversFolder -Make $SelectedMake }
# Tier 2
'Samsung'   { $rawModels = Get-SamsungDriversModelList -Headers $Headers -UserAgent $UserAgent }
'Fujitsu'   {
    $modelSearchTerm = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Enter Fujitsu Model Name (e.g., LIFEBOOK U7412):", "Fujitsu Model Search", "")
    if ([string]::IsNullOrWhiteSpace($modelSearchTerm)) { return @() }
    $rawModels = Get-FujitsuDriversModelList -ModelSearchTerm $modelSearchTerm -Headers $Headers -UserAgent $UserAgent
}
# Tier 3 (stubs)
'ASUS'      { $rawModels = Get-ASUSDriversModelList }
'MSI'       { $rawModels = Get-MSIDriversModelList }
'Getac'     { $rawModels = Get-GetacDriversModelList }
```

#### Config Schema Update

`config/ffubuilder-config.schema.json:275`:
```json
"enum": ["", "Microsoft", "Dell", "HP", "Lenovo", "Acer", "Dynabook", "Panasonic", "Samsung", "Fujitsu", "ASUS", "MSI", "Getac"]
```

#### XAML Tooltip Update

`BuildFFUVM_UI.xaml:677`:
```xml
ToolTip="Make of the device to download drivers. Accepted values are: 'Microsoft', 'Dell', 'HP', 'Lenovo', 'Acer', 'Dynabook', 'Panasonic', 'Samsung', 'Fujitsu', 'ASUS', 'MSI', 'Getac'. Note: ASUS, MSI, and Getac are stub implementations."
```

#### FFUConstants New Entries

```powershell
# Acer driver catalog URL (source: DAT v8.0.0)
static [string] $ACER_CATALOG_URL = "https://global-download.acer.com/GDFiles/Driver/SCCM/AcerCatalog.xml"

# Dynabook driver catalog URL
static [string] $DYNABOOK_CATALOG_URL = "https://content.us.dynabook.com/content/support/drivers/Dynabook_DriverPack_Catalog.cab"

# Panasonic SCCM catalog URL (TBD — validate during implementation)
static [string] $PANASONIC_CATALOG_URL = ""

# Samsung enterprise PC management portal
static [string] $SAMSUNG_PORTAL_URL = "https://pcmanagement.biz.samsung.com"

# Fujitsu support portal (TBD — validate during implementation)
static [string] $FUJITSU_PORTAL_URL = ""
```

#### Get-DriverExtractionResult Updates

`FFU.Drivers.psm1:131` — Extend ValidateSet and add OEM-specific exit code handling:

- **Acer, Dynabook, Panasonic**: Standard expand.exe codes (0=success, 1=failure). No vendor-specific codes.
- **Samsung**: Standard ZIP extraction codes. No vendor-specific codes.
- **Fujitsu**: Standard Windows Installer codes (0, 1641, 3010=success; 1603, 1618=failure).
- **ASUS, MSI, Getac**: No exit code handling needed (stub implementations).

#### FFU.Drivers.psd1 Export Updates

`FunctionsToExport` array needs 8 new entries:
```powershell
'Get-AcerDrivers',
'Get-DynabookDrivers',
'Get-PanasonicDrivers',
'Get-SamsungDrivers',
'Get-FujitsuDrivers',
'Get-ASUSDrivers',
'Get-MSIDrivers',
'Get-GetacDrivers'
```

### 2.2 Existing Patterns to Reuse

| Pattern | Source | Reuse For |
|---------|--------|-----------|
| XML catalog download + parse | Dell `Get-DellDrivers` | Acer (XML is direct, no CAB wrapping) |
| CAB→XML catalog download + expand + parse | Dell `CatalogPC.cab` flow | Dynabook, Panasonic |
| HTML page scraping | Microsoft `Get-MicrosoftDriversModelList` | Samsung, Fujitsu |
| Search input (InputBox) | Lenovo `Get-LenovoDriversModelList` | Fujitsu |
| Auto-populate dropdown | Dell/HP model lists | Acer, Dynabook, Panasonic, Samsung |
| `Get-CachedOEMCatalog` 7-day TTL | FFU.Drivers.psm1:332 | Acer, Dynabook, Panasonic |
| `ConvertTo-StandardizedDriverModel` | FFUUI.Core.Drivers.psm1:77 | All OEMs (no schema changes needed) |
| `Invoke-DriverDownloadWithRetry` | FFU.Drivers.psm1:21 | All OEMs with downloadable drivers |
| `Get-DriverExtractionResult` | FFU.Drivers.psm1:131 | All OEMs (extend exit code handling) |

### 2.3 Testing Strategy

Each OEM needs:
1. **Unit tests** for `Get-{OEM}Drivers` (mock catalog download, verify parsing)
2. **Unit tests** for `Get-{OEM}DriversModelList` (mock catalog, verify model list output)
3. **Unit tests** for `Save-{OEM}DriversTask` (mock download, verify extraction)
4. **Integration test** for catalog URL accessibility (ping test, not full download)
5. **Stub tests** for Tier 3 (verify empty list returned, log message generated)

**Test file naming:** `Tests/Unit/FFU.Drivers.{OEM}.Tests.ps1` and `Tests/Unit/FFUUI.Core.Drivers.{OEM}.Tests.ps1`

---

## 3. Recommended Plan Structure

Based on research findings, the following plan structure is recommended:

| Plan | Title | Scope | Tier |
|------|-------|-------|------|
| 42-01 | Acer Driver Support | Full implementation — XML catalog, model list, download, extraction | Tier 1 |
| 42-02 | Dynabook Driver Support | Full implementation — CAB→XML catalog, model list, download, extraction | Tier 1 |
| 42-03 | Panasonic Driver Support | Full implementation — SCCM CAB catalog, model list, download, extraction | Tier 1 |
| 42-04 | Samsung Driver Support | Full implementation — HTML portal, model list, download, extraction | Tier 2 |
| 42-05 | Fujitsu Driver Support | Full implementation — HTML portal, search input, download, extraction | Tier 2 |
| 42-06 | Tier 3 Stub Implementations | ASUS + MSI + Getac stubs with empty model lists and log messages | Tier 3 |
| 42-07 | UI Integration + Config | ValidateSet updates, config schema, XAML tooltip, FFUConstants, Make dropdown | All |
| 42-08 | Pester Tests | Unit + integration tests for all 8 OEMs | All |

**Execution order:** 42-07 (infrastructure) → 42-01 through 42-06 (OEMs) → 42-08 (tests)

**Note:** 42-07 should be first because it sets up the ValidateSet, config schema, and XAML changes that all OEM implementations depend on. Alternatively, each OEM plan could include its own ValidateSet additions, but centralized infrastructure avoids merge conflicts.

---

## 4. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Acer XML catalog schema differs from expected | Low | Low | Fetch catalog during implementation, adapt parser |
| Dynabook CAB URL becomes inaccessible | Low | Medium | Cache the catalog; add backup URL if available |
| Panasonic catalog requires portal auth | Medium | Medium | Fall back to static model list; attempt public SCCM URL |
| Samsung portal structure changes | Medium | Low | Use stable selectors; add fallback static list |
| Fujitsu LIFEBOOK APIs don't exist | High | Low | Implement as HTML scraper with search input (Lenovo pattern) |
| Stub OEMs receive user complaints | Low | Low | Clear log messages explaining unavailability |

---

*Research for Phase 42-new-oem-manufacturers*
*Produced: 2026-02-02*
