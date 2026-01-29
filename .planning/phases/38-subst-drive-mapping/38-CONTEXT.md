# Phase 38: SUBST Drive Mapping for Long Paths - Context

**Gathered:** 2026-01-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Map a SUBST virtual drive during driver operations to prevent long path failures (>260 chars). Covers both BuildFFUVM.ps1 (VM build) and ApplyFFU.ps1 (WinPE deployment) contexts. Includes INF parsing long-path improvements (\\?\ prefix, buffer expansion, GUID normalization) from upstream.

</domain>

<decisions>
## Implementation Decisions

### SUBST scope and mapping strategy
- Match upstream pattern: per-folder sequential loop with one reused drive letter
- Map individual driver folders (not entire Drivers root)
- Loop workflow: map folder -> operate (extract/inject) -> unmap -> repeat next folder
- SUBST used during both driver extraction (unpacking) and DISM injection
- Walk up directory tree if SUBST target path itself exceeds ~240 chars
- Deduplicate child folders when parent already covers them via /Recurse

### Helper function placement
- SUBST helper functions (Get-AvailableDriveLetter, New-DriverSubstMapping, Remove-DriverSubstMapping) live in FFU.Drivers module
- Same helpers used by both BuildFFUVM.ps1 and ApplyFFU.ps1 contexts
- ApplyFFU.ps1 uses the same try/finally pattern as BuildFFUVM.ps1

### Drive letter selection
- Scan Z->A using Get-PSDrive for first available letter (automatic, no config)
- If no letter available (all 26 in use): log WARNING and continue without SUBST — build may fail on deep paths but doesn't halt
- Always defensively remove existing mapping on chosen letter before creating (`subst X: /d` before `subst X: path`)

### Parallel task safety
- Driver downloads stay parallel (fast)
- SUBST-based operations (extraction + DISM injection) run sequentially after all downloads complete
- Single drive letter reused in sequential loop — no per-thread allocation needed

### Logging
- Log SUBST creation: which letter, mapped to what path
- Log SUBST removal: which letter removed
- Standard log level (not verbose-only)

### Lifecycle and cleanup
- Try/finally per operation — each map/unmap in its own try/finally block
- SUBST removal failure: log WARNING (non-blocking), continue build
- No registration with FFU.Common.Cleanup module — try/finally is sufficient

### INF parsing improvements (included in Phase 38)
- Add \\?\ long-path prefix for Win32 API calls (GetPrivateProfileString, Copy-Item)
- Expand GetPrivateProfileString buffer from 1KB to 64KB (auto-growing)
- GUID normalization: strip trailing comments from INF ClassGUID entries
- Use -LiteralPath in Copy-Item calls (skip wildcard expansion)
- DllImport explicit Unicode charset for INI/INF reading

### Claude's Discretion
- Exact implementation of the SUBST loop function (Invoke-DismDriverInjectionWithSubstLoop equivalent)
- How to structure the sequential injection phase after parallel downloads
- Buffer auto-growth strategy details (4KB increments vs doubling)
- Whether to add Pester tests in Phase 38 or defer to a separate test plan

</decisions>

<specifics>
## Specific Ideas

- Match upstream commit patterns (44aa4d3 for ApplyFFU.ps1 simple pattern, e9652da for BuildFFUVM.ps1 loop pattern)
- Upstream uses `cmd.exe /c subst D: "path"` for creation and `cmd.exe /c subst D: /d` for removal
- Upstream escapes quotes in paths: `$path -replace '"', '""'`
- DISM does NOT support \\?\ prefix directly — only use it for Win32 API calls
- SUBST has its own ~240-char path limit on the target path

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 38-subst-drive-mapping*
*Context gathered: 2026-01-28*
