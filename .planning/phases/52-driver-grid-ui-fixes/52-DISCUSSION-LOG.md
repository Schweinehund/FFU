# Phase 52: Driver-Grid UI Fixes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-28
**Phase:** 52-driver-grid-ui-fixes
**Areas discussed:** CopyDrivers validation UX, Select-all scope when filtered, Filter+sort mechanism, Verification approach

**Method:** User selected all four gray areas and requested an adversarial review
(`/adversarial-review`) to recommend the best option in each. A three-agent
Proposer → Adversary → Referee chain (Opus) ran; the Adversary and Referee verified the
actual upstream commit diffs (`git show`) since all three requirements are PORT tasks.
Final verdict: Adversary correct on all four (A amend, B overturn, C overturn, D amend).

---

## CopyDrivers validation UX (DGRID-03)

| Option | Description | Selected |
|--------|-------------|----------|
| A1 | Hard-block at build start (UI MessageBox idiom, BuildFFUVM_UI.ps1:782) | partial |
| A2 | Auto-enable BuildUSBDrive when CopyDrivers checked | |
| A3 | Disable/grey-out CopyDrivers until BuildUSBDrive on | |
| A4 | Inline warning, allow proceed | |
| **Final** | **Port `dc801e9` `throw` into CLI BuildFFUVM.ps1 END block (post-config, USBOnlyMode-guarded)** | ✓ |

**User's choice:** Lock as recommended.
**Notes:** Hard-block disposition correct (A2/A4 rejected), but the load-bearing fix belongs in the CLI (which the UI also runs), not a UI-only MessageBox. A3 dropped (config-load trap, not upstream). Referee caught the fork-specific BEGIN/END + USBOnlyMode adaptation both other agents missed.

---

## Select-all scope when filtered (DGRID-02)

| Option | Description | Selected |
|--------|-------------|----------|
| B2 | Apply select-all to ALL rows including hidden (Proposer's pick — was the bug) | |
| **B1** | **Apply select-all to VISIBLE/filtered rows only (port `f09c989` `-HeaderSelectionAffectsVisibleItemsOnly`)** | ✓ |

**User's choice:** Lock as recommended.
**Notes:** Upstream f09c989 explicitly scopes select-all to visible items to prevent accidental (de)selection of hidden rows — the current full-list behavior IS the defect. Includes `Update-SelectAllHeaderCheckBoxState` update, `Save-DriversJson` source fix (read `allDriverModels` not `.Items`), and `42ed281` header alignment layered on top.

---

## Filter+sort mechanism (DGRID-01)

| Option | Description | Selected |
|--------|-------------|----------|
| C2 | New CollectionView SortDescriptions, driver-grid only, don't touch shared fn (Proposer's pick) | |
| **C1/upstream** | **Port `b4305a1`: fix the SHARED `Invoke-ListViewSort` — capture filter, sort filtered set, reassign, re-apply filter** | ✓ |

**User's choice:** Lock as recommended.
**Notes:** Upstream fixed the shared function; backward-compatible (no-filter path unchanged), preserves selected-pinned-on-top ordering, fewer lines than SortDescriptions rewrite. SortDescriptions would change UX (rows jump on toggle).

---

## Verification approach

| Option | Description | Selected |
|--------|-------------|----------|
| D2 | Full Pester incl. mocked WPF/CollectionView | |
| D3 | Manual UAT only | |
| **D1 (inline)** | **Pester the testable logic (inline ports, no fork-only extraction) + manual UAT for WPF/visual behavior** | ✓ |

**User's choice:** Lock as recommended.
**Notes:** Keep ports inline matching upstream to avoid sync merge friction on these exact files. Thin Pester for save source + CLI throw; manual UAT for filter/sort/select-all/alignment (not headless-testable). verify-app remains the blocking gate.

## Claude's Discretion

- Exact Pester test file placement/naming and UAT script wording (follow `Tests/` conventions).
- Optional UI MessageBox pre-check for DGRID-03 — nice-to-have, not required.

## Deferred Ideas

None — discussion stayed within phase scope.
