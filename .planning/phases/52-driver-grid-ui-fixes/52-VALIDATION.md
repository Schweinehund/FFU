---
phase: 52
slug: driver-grid-ui-fixes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-28
---

# Phase 52 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Custom `Write-TestResult` framework (NOT Pester — all existing `FFUDevelopment/Tests/Test-Phase*.ps1` use this; no `.Tests.ps1` exist) |
| **Config file** | None — standalone script |
| **Quick run command** | `powershell -NoProfile -ExecutionPolicy Bypass -File .\FFUDevelopment\Tests\Test-Phase52DriverGridFixes.ps1` |
| **Full suite command** | Same — phase test is self-contained |
| **Estimated runtime** | ~5 seconds (source-content + logic assertions; no UI launch) |

---

## Sampling Rate

- **After every task commit:** Run the quick command above
- **After every plan wave:** Run the same (single self-contained file)
- **Before `/gsd-verify-work`:** All automated checks green + verify-app BLOCKING gate + manual UAT completed
- **Max feedback latency:** ~5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 52-W0-01 | 00 | 0 | DGRID-01/02/03 | — | N/A | scaffold | create `Test-Phase52DriverGridFixes.ps1` | ❌ W0 | ⬜ pending |
| DGRID-01 src | — | — | DGRID-01 | — | Filter-capture preamble present in `Invoke-ListViewSort` | content | quick cmd | ❌ W0 | ⬜ pending |
| DGRID-02 save | — | — | DGRID-02 | — | `Save-DriversJson` reads `allDriverModels` when non-null | content+logic | quick cmd | ❌ W0 | ⬜ pending |
| DGRID-02 switch | — | — | DGRID-02 | — | `-HeaderSelectionAffectsVisibleItemsOnly` present; only line-457 call opts in | content | quick cmd | ❌ W0 | ⬜ pending |
| DGRID-03 throw | — | — | DGRID-03 | — | Throw present, `-not $USBOnlyMode` guarded, in END block after config load (line > 775) | source regex + line check | quick cmd | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `FFUDevelopment/Tests/Test-Phase52DriverGridFixes.ps1` — automated assertions for DGRID-01/02/03 (content-match + logic), using the custom `Write-TestResult` framework (model on `Test-Phase51Correctness.ps1` / `Test-DriverValidationMessages.ps1`).

*This file does not exist yet — create in Wave 0 (or a dedicated Wave-1 task before implementation tasks).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Filter persists after column sort | DGRID-01 | WPF CollectionView not headlessly testable | Drivers tab → type filter term → click column header to sort → rows stay filtered (no reset to full list) |
| Select-all scoped to visible rows | DGRID-02 | Requires live WPF UI with active filter | With filter active, click header checkbox → only visible rows toggle; hidden rows keep prior state |
| Header tri-state correctness | DGRID-02 | Requires live WPF UI | 3 visible (1 sel, 2 unsel): click header → all 3 selected; click again → all cleared; deselect one → header indeterminate |
| Save preserves hidden selections | DGRID-02 | Requires live WPF filter state | Select 2 in full list → filter to hide one selected → Save → saved JSON includes the hidden selected row |
| Header checkbox alignment | DGRID-02 | Visual inspection | Drivers tab → header checkbox horizontally centered & vertically aligned with row checkboxes |
| CopyDrivers/BuildUSBDrive error | DGRID-03 | End-to-end build start | UI: CopyDrivers=true, BuildUSBDrive=false → start build → clear thrown error surfaced to UI log |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers the MISSING test file
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
