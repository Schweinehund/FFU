# Phase 52: Driver-Grid UI Fixes - Context

**Gathered:** 2026-06-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix three correctness bugs in the Drivers-tab grid of the FFU Builder WPF UI so no
driver selections are silently lost and no invalid CopyDrivers configuration can start
a build:

- **DGRID-01** — sorting the driver list while a filter is active must keep the filter applied (not reset to all rows).
- **DGRID-02** — selecting/deselecting drivers while filtered, then saving, must preserve selections for hidden rows; select-all header checkbox scope + alignment.
- **DGRID-03** — the UI/CLI must prevent an invalid CopyDrivers config by requiring BuildUSBDrive when CopyDrivers is enabled.

All three are **PORT** tasks — porting verified upstream fixes (rbalsleyMSFT/FFU). The
fork is currently at the pre-fix bug state for all of them. **No new grid capabilities**
are in scope.

</domain>

<decisions>
## Implementation Decisions

These decisions were settled by an adversarial design review (Proposer → Adversary →
Referee) in which the Adversary and Referee **verified the actual upstream commit diffs
via `git show`**. For PORT tasks the ground truth is what upstream did — verbatim where
possible, with the fork-specific adaptations called out below.

### DGRID-03 — CopyDrivers validation (port `dc801e9`)
- **D-01:** Port the dependency-validation `throw` into the CLI `BuildFFUVM.ps1` (NOT a UI-only MessageBox). This guards both CLI users and the UI (the UI launches `BuildFFUVM.ps1`). Keep upstream's `WriteLog` + `throw` wording verbatim.
- **D-02:** **Fork adaptation (critical — both Proposer and Adversary missed this; Referee caught it):** the fork refactored `BuildFFUVM.ps1` into `BEGIN`/`END` blocks. BEGIN (~line 593) runs *before* config-file load (config merges at ~line 775, inside END). The throw MUST be placed in the **END block AFTER config load (>line 775)** so it validates the effective config-merged values, matching upstream's post-config placement — not in BEGIN (which would see CLI args only).
- **D-03:** **Fork adaptation:** guard the throw with `-and -not $USBOnlyMode`. USBOnlyMode auto-sets `$BuildUSBDrive = $true` (~2219) and `$CopyDrivers = $true` (~2242); an unguarded throw would fire on valid USB-only builds whose config carries `CopyDrivers=$true`/`BuildUSBDrive=$false` before those assignments.
- **D-04:** Do NOT add a disable/grey-out of the CopyDrivers checkbox (rejected option A3). It is not in upstream and creates a config-load trap: `Config.psm1:835` loads `CopyDrivers` independently of `BuildUSBDrive`, so a load handler would either contradict a loaded `CopyDrivers=true` or silently uncheck it. (A UI MessageBox pre-check was considered as optional polish and explicitly NOT required — CLI throw is the load-bearing fix.)

### DGRID-02 — select-all scope + save path (port `f09c989`, then `42ed281`)
- **D-05:** Scope the header select-all checkbox to the **VISIBLE/filtered rows** (option B1), NOT all rows. The Proposer's "apply to all rows" was literally the bug — under a filter the current handler iterates `ItemsSource` (full master list), so select-all silently (de)selects hidden rows. Implement via upstream's `-HeaderSelectionAffectsVisibleItemsOnly` switch added to the shared `Add-SelectableGridViewColumn` (`FFUUI.Core.Shared.psm1`); the **driver grid opts in** at `FFUUI.Core.Initialize.psm1:457`; the other five callers (winget, BYO apps, script vars, USB drives, additional FFUs) keep full-list behavior unchanged.
- **D-06:** Port the matching `Update-SelectAllHeaderCheckBoxState` change together with D-05 (it reads the switch off `HeaderCheckBox.Tag`); otherwise the header tri-state desyncs from the new scope.
- **D-07:** Fix `Save-DriversJson` (`FFUUI.Core.Drivers.psm1:221`) to read from `$State.Data.allDriverModels` (full master list) instead of `lstDriverModels.Items` (which, under a CollectionView filter, returns only visible rows → the save-path data leak). Use upstream's null-guarded form: `if ($null -ne $State.Data.allDriverModels) {...} else {lstDriverModels.Items}`. This fix is independent of the select-all scope and affirmed by all three reviewers.
- **D-08:** Port `42ed281` (header checkbox alignment) **after** `f09c989` — it wraps the header checkbox in `Border`→`Grid`→`GridViewColumnHeader` with zeroed padding/margin + centered alignment and builds directly on the f09c989 header region.

### DGRID-01 — filter + sort coexistence (port `b4305a1`)
- **D-09:** Fix the **SHARED** `Invoke-ListViewSort` (`FFUUI.Core.Shared.psm1:501`), NOT a driver-grid-only path and NOT a SortDescriptions rewrite (Proposer's C2 rejected). Upstream `b4305a1` captures the active filter predicate, sorts only the filtered view, reassigns `ItemsSource`, then re-applies the captured filter. The no-filter branch is unchanged (backward compatible for all grids), the existing "selected-pinned-on-top" ordering is preserved, and it is fewer lines / lower risk than C2. Diff applies cleanly (fork is at the pre-`b4305a1` base).

### Verification approach
- **D-10:** D1 philosophy with **inline ports** matching upstream — do NOT extract fork-only helper functions purely for testability (creates merge friction on the next upstream sync of these exact files). Cover the non-WPF logic with thin Pester (the `Save-DriversJson` selection source; the CopyDrivers/BuildUSBDrive throw, guarded for USBOnlyMode). Route the WPF/visual behavior (filter-persists-after-sort, select-all-under-filter scope, header tri-state, header alignment) to **manual UAT** — WPF CollectionView/Dispatcher is not unit-testable headlessly, and mocking it tests the mock, not the framework.
- **D-11:** verify-app remains the BLOCKING gate; PSScriptAnalyzer clean; version.json + affected `.psd1` bumps + CHANGELOG_FORK entry per project standards. Run targeted tests, not the full env-dependent suite.

### Implementation order (commits layer on each other)
1. `b4305a1` (DGRID-01, D-09) — oldest base; later commits assume it (avoids re-introducing whitespace churn as conflicts).
2. `f09c989` (DGRID-02, D-05/06/07) — switch + `Update-SelectAllHeaderCheckBoxState` + save-source; opt in only `Initialize.psm1:457`.
3. `42ed281` (DGRID-02 header alignment, D-08) — depends on f09c989.
4. `dc801e9` (DGRID-03, D-01..04) — independent; END-block placement + USBOnlyMode guard.
5. Thin Pester (save source + CLI throw) + manual UAT for the three WPF behaviors.

### Claude's Discretion
- Exact Pester test file placement/naming and UAT script wording — follow existing `Tests/` conventions.
- Whether to add the optional UI MessageBox pre-check for DGRID-03 (nice-to-have UX; not required — user chose "lock all as recommended" without it).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Upstream PORT commits (read the diff: `git show <hash>`)
- `dc801e9` (upstream/rbalsleyMSFT/FFU) — DGRID-03 CopyDrivers↔BuildUSBDrive dependency validation. Target: `FFUDevelopment/BuildFFUVM.ps1` (fork: END block post-config-load, USBOnlyMode-guarded).
- `f09c989` (upstream) — DGRID-02 select-all visible-scope + `Save-DriversJson` source. Targets: `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1`, `FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1` (line 457), `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1` (line 221).
- `b4305a1` (upstream) — DGRID-01 sort-after-filter. Target: `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` `Invoke-ListViewSort` (line 501).
- `42ed281` (upstream) — DGRID-02 header checkbox alignment. Target: `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` `Add-SelectableGridViewColumn` (depends on f09c989). `upstream` remote = https://github.com/rbalsleyMSFT/FFU.git.

### Phase / project specs
- `.planning/ROADMAP.md` §"Phase 52: Driver-Grid UI Fixes" — goal + success criteria.
- `.planning/REQUIREMENTS.md` — DGRID-01/02/03 definitions (lines 25-27) with PORT commit citations.

### Fork code touchpoints
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.psm1` — `Save-DriversJson` (221), `Search-DriverModels` (167), `Invoke-GetModels` (509).
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Shared.psm1` — `Invoke-ListViewSort` (~501), `Add-SelectableGridViewColumn`/`Update-SelectAllHeaderCheckBoxState` (~327-353).
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1` — driver grid column build (~457).
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` — CopyDrivers persist (78) / load (835).
- `FFUDevelopment/BuildFFUVM.ps1` — BEGIN cross-param validation (~593), config load (~775), USBOnlyMode auto-sets (~2219/2242), existing PARAMETER VALIDATION block (~2606-2665).
- `FFUDevelopment/BuildFFUVM_UI.ps1` — existing UI validation idiom (~782).
- `FFUDevelopment/Tests/Test-DriverValidationMessages.ps1` — existing (non-Pester) driver-validation test pattern for reference.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Add-SelectableGridViewColumn` (Shared.psm1) — the shared select-all column builder; gains the `-HeaderSelectionAffectsVisibleItemsOnly` switch. Only the driver grid opts in.
- `Invoke-ListViewSort` (Shared.psm1) — shared sort used by 5+ grids; the b4305a1 fix is backward-compatible (no-filter path unchanged).
- Existing CLI PARAMETER VALIDATION block (`BuildFFUVM.ps1` ~2606-2665) already validates the Drivers folder for `InstallDrivers -or CopyDrivers` — the new dependency throw slots near it (END block).

### Established Patterns
- WPF CollectionView filtering via `[System.Windows.Data.CollectionViewSource]::GetDefaultView(...)` with a `.Filter` predicate (Search-DriverModels).
- `Search-DriverModels` enforces an invariant that resets `ItemsSource` back to `allDriverModels` (Drivers.psm1:180-182) — this is why a naive "re-call Search-DriverModels after sort" fix silently undoes the sort. b4305a1 sidesteps it by carrying the filter predicate through the sort instead.
- `Save-DriversJson` is the only consumer reading `.Items`; `Invoke-DownloadSelectedDrivers` already reads the full `allDriverModels` — so the save fix aligns it with existing correct behavior.

### Integration Points
- DGRID-03 throw integrates at the CLI build entry (END block) so both UI and CLI paths are covered.
- DGRID-02 switch integrates at the single driver-grid column build site (Initialize.psm1:457).

</code_context>

<specifics>
## Specific Ideas

Port the four upstream commits as the reference implementation; the only deliberate
divergences from verbatim are the two fork adaptations for `dc801e9` (END-block
placement + `-not $USBOnlyMode` guard) required by the fork's BEGIN/END refactor and
USBOnlyMode auto-set. Everything else should match upstream to minimize sync friction.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Optional UI MessageBox pre-check for
DGRID-03 was considered and explicitly left out per user's "lock all as recommended".)

</deferred>

---

*Phase: 52-driver-grid-ui-fixes*
*Context gathered: 2026-06-28*
