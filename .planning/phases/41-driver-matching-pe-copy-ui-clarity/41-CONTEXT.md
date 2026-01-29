# Phase 41: Driver Matching, PE Copy, and UI Clarity - Context

**Gathered:** 2026-01-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Add a family-level driver fallback tier to deploy-time matching, add retry logic with verification to PE driver copy, and add a status text indicator in the UI showing the active driver source. Logging improvements across all three areas.

</domain>

<decisions>
## Implementation Decisions

### Fallback strategy (DRV-05)
- Add a third matching tier: SystemID (precision 2) -> ModelName (precision 1) -> **Family match (precision 0.5)**
- Family extraction: first word after the normalized brand name (e.g., "Dell Latitude 7490" -> family "Latitude")
- When multiple family matches exist, pick the most recent/highest model number
- Family fallback is silent (auto-select, no user prompt) with a log message explaining the decision
- If family match also fails, fall back to manual selection (existing behavior)

### PE copy retry behavior (DRV-06)
- Add retry logic (1-2 retries) for PE driver injection, consistent with existing Invoke-CopyPEWithRetry pattern
- Retry only on transient errors: access denied, file-in-use, sharing violations
- Fail immediately (no retry) on permanent errors: missing files, corrupted drivers, DISM errors
- PE driver copy remains non-blocking — build continues if PE drivers fail
- After injection, log a summary count of drivers injected vs source folder count
- Partial failure shows WARNING with counts: "WARNING: PE driver injection: 12/15 drivers injected, 3 failed (access denied)"

### Driver source UI indicators (DRV-07)
- Add a TextBlock status label on the Drivers tab showing the active driver source
- Status text includes source type + count + warnings:
  - "Dell CatalogIndexPC: 2 models selected"
  - "Local folder: 5 driver packages found"
  - "No driver source configured"
- Update reactively on config changes: Make dropdown change, model selection, folder path set, Drivers.json load
- UI shows build-time configuration only — deploy-time matching mode (SystemID vs ModelName vs Family) is logged but not shown in UI (happens in WinPE, not the desktop UI)

### Logging and diagnostics
- Deploy-time driver matching logs a decision trail: each tier attempted and its outcome
  - Example: "SystemID A0B1 -> no match, ModelName Latitude 7490 -> matched, using Latitude7490.wim"
- Family fallback uses same [OEM] prefix format as existing tiers (not WARNING level)
  - Example: "[Dell] Family fallback: Latitude -> matched Latitude7490.wim"
- Add a summary log line after matching completes:
  - Example: "Driver match result: Latitude7490.wim (Tier: Family)" or "Driver match result: Manual selection (no automatic match)"
- PE driver copy uses [PE] prefix for structured logging:
  - "[PE] Driver source: C:\PEDrivers (15 INF files)"
  - "[PE] Injection result: 15/15 succeeded"
  - Consistent with existing [OEM] and [SUBST] prefixed logging patterns

### Claude's Discretion
- Exact transient error detection logic (specific HRESULT codes for access/sharing violations)
- Family extraction regex implementation details
- "Most recent" heuristic for multi-match family selection (timestamp vs model number parsing)
- TextBlock placement and styling within the Drivers tab XAML
- Summary count implementation approach (pre-count INFs vs post-inject diff)

</decisions>

<specifics>
## Specific Ideas

- User emphasized minimal changes consistent with existing codebase patterns
- Family match fits naturally as a new tier in the existing SystemID -> ModelName chain in ApplyFFU.ps1 (lines 765-814)
- PE retry should follow the same pattern as Invoke-CopyPEWithRetry in FFU.Media.psm1
- UI status label is a simple TextBlock addition, not a new control paradigm
- All logging follows existing [PREFIX] format conventions ([OEM], [SUBST], [PE])

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 41-driver-matching-pe-copy-ui-clarity*
*Context gathered: 2026-01-29*
