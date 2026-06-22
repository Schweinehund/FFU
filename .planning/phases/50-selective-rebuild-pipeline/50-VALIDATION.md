---
phase: 50
slug: selective-rebuild-pipeline
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-22
---

# Phase 50 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 5.x |
| **Config file** | `Tests/Unit/Invoke-PesterTests.ps1` |
| **Quick run command** | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ArtifactScanner'` |
| **Full suite command** | `.\Tests\Unit\Invoke-PesterTests.ps1` |
| **Estimated runtime** | ~120 seconds (full), ~10s (single module) |

---

## Sampling Rate

- **After every task commit:** Run the relevant module test (`USBOnlyMode.Tests.ps1`, `FFU.ArtifactScanner.Tests.ps1`, `FFUUI.Core.Handlers.Tests.ps1`, or `FFUUI.Core.ConfigValidation.Tests.ps1`)
- **After every plan wave:** Run `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Before `/gsd-verify-work`:** Full suite must be green + `Invoke-ScriptAnalyzer` clean on changed files
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Concern | Requirement | Test Type | Automated Command | Status |
|---------|---------|-------------|-----------|-------------------|--------|
| (planner-assigned) | ComboBox disposition control replaces include checkbox; per-card item set | REBUILD-01 | unit | `FFUUI.Core.Handlers.Tests.ps1` | ⬜ pending |
| (planner-assigned) | Config round-trip of `Disposition` per artifact (save/load) | REBUILD-01 | unit | `FFUUI.Core.ConfigValidation.Tests.ps1` / `FFU.ConfigMigration.Tests.ps1` | ⬜ pending |
| (planner-assigned) | USB-Mode gate reads `Disposition` (not `Include`); Reuse/Skip/Rebuild routing (F2) | REBUILD-02 | unit | `USBOnlyMode.Tests.ps1` | ⬜ pending |
| (planner-assigned) | Selective per-phase execution: only Rebuild artifact's phase runs (F3) | REBUILD-02 | unit | `USBOnlyMode.Tests.ps1` | ⬜ pending |
| (planner-assigned) | AppsISO copy path added to `New-DeploymentUSB` (F1) | REBUILD-03 | unit | `USBOnlyMode.Tests.ps1` | ⬜ pending |
| (planner-assigned) | Rebuilt + reused artifacts combined into final USB | REBUILD-03 | unit | `USBOnlyMode.Tests.ps1` | ⬜ pending |
| (planner-assigned) | 4-status scanner rendering (Found/Degraded/Error/Missing) (F7) | REBUILD-01 | unit | `FFUUI.Core.Handlers.Tests.ps1` | ⬜ pending |
| (planner-assigned) | Missing-required→block; missing-optional→Skip defaults (D-10) | REBUILD-01 | unit | `USBOnlyMode.Tests.ps1` / `FFU.ArtifactScanner.Tests.ps1` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Extend `Tests/Unit/USBOnlyMode.Tests.ps1` with disposition-gate + selective-execution + AppsISO-copy cases
- [ ] Extend `Tests/Unit/FFUUI.Core.Handlers.Tests.ps1` with ComboBox disposition + 4-status rendering cases
- [ ] Extend `Tests/Unit/FFUUI.Core.ConfigValidation.Tests.ps1` (or `FFU.ConfigMigration.Tests.ps1`) with Disposition round-trip cases

*Existing infrastructure (Pester 5.x + Invoke-PesterTests.ps1) covers all phase requirements — no new framework install needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ComboBox renders correct item set per card tier; required artifacts show single disabled "Reuse" | REBUILD-01 | WPF visual rendering not unit-testable headlessly | Launch `BuildFFUVM_UI.ps1`, switch to USB Mode, confirm each card's disposition options match its tier; FFU/DeployISO are disabled "Reuse" |
| Inline helper text for FFU rebuild redirect to Full Build (D-09) | REBUILD-01 | Visual/UX copy | Confirm helper text appears on the FFU card pointing to Full Build mode |
| End-to-end: mark Drivers=Rebuild, FFU=Reuse → only driver phase runs, USB assembled | REBUILD-02/03 | Requires real build environment (Hyper-V/ADK/USB) | Run a real USB-Mode build with mixed dispositions; confirm only the rebuild phase executes and the USB contains rebuilt + reused artifacts |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
