---
phase: 51
slug: capture-boot-correctness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-26
---

# Phase 51 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from 51-RESEARCH.md "## Validation Architecture". These are mostly
> pure-logic ports with strong unit seams; the irreducibly physical criteria
> (real non-English media, Secure-Boot-2023 hardware boot) are manual-only.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 5.x (PowerShell) |
| **Config file** | `FFUDevelopment/Tests/Unit/Invoke-PesterTests.ps1` |
| **Quick run command** | `.\FFUDevelopment\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.Imaging'` |
| **Full suite command** | `.\FFUDevelopment\Tests\Unit\Invoke-PesterTests.ps1` |
| **Estimated runtime** | ~30–90 seconds (targeted module runs; full suite has known slow env-dependent reds — verify with targeted files) |

> Note: module-internal functions (`Get-Index`/`Get-WindowsImageSelection`, `Add-BootFiles`, the year-normalization helper) require `InModuleScope` in Pester — module types/functions are not exported to caller scope (STATE.md Phase 46 note). `Get-WindowsImage` must be mocked (no real WIM in CI).

---

## Sampling Rate

- **After every task commit:** Run the quick (per-module) command for the touched module (`FFU.Imaging` or `FFU.Drivers`).
- **After every plan wave:** Run the full suite (targeted to changed modules where the full suite is environmentally red).
- **Before `/gsd-verify-work`:** Targeted module suites green + PSScriptAnalyzer clean (no new errors) + all modules import (verify-app).
- **Max feedback latency:** ~90 seconds.

---

## Per-Task Verification Map

> Scaffold — the planner fills exact task IDs/commands. Test-type intent per requirement:

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 51-01-xx | 01 | 1 | CORRECT-04 | — | EditionId/InstallationType selection picks correct index on mocked multi-edition (incl. non-English ImageName) media; SKU→EditionId map covers every `$clientSKUs`/`$LTSCSKUs`/`$ServerSKUs` value | unit (InModuleScope, mocked Get-WindowsImage) | `Invoke-PesterTests.ps1 -Module 'FFU.Imaging'` | ❌ W0 | ⬜ pending |
| 51-01-xx | 01 | 1 | CORRECT-01 | — | Single relevant candidate → auto-select + `ResolvedWindowsSKU` returned and propagated; ≥2 candidates → editions WriteLog'd then throw; Read-Host loop removed | unit (InModuleScope, mocked Get-WindowsImage) | `Invoke-PesterTests.ps1 -Module 'FFU.Imaging'` | ❌ W0 | ⬜ pending |
| 51-02-xx | 02 | 1 | CORRECT-03 | — | `Add-BootFiles` invokes ADK bcdboot path; throws actionable error when ADK bcdboot absent; pre-flight (`Test-FFUADK`) flags missing bcdboot | unit (mock Test-Path / Invoke-Process) | `Invoke-PesterTests.ps1 -Module 'FFU.Imaging'` + `-Module 'FFU.Preflight'` | ❌ W0 | ⬜ pending |
| 51-03-xx | 03 | 1 | CORRECT-02 | — | `Get-EffectiveDriverWindowsRelease` (pure fn): 2016/2019/2021→10, 2024→11 when LTSC; Server 2019 stays 2019; global `$WindowsRelease` unchanged | unit (pure function, table-driven) | `Invoke-PesterTests.ps1 -Module 'FFU.Drivers'` (or Core, per planner) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `FFUDevelopment/Tests/Unit/FFU.Imaging.GetIndex.Tests.ps1` — InModuleScope tests for Get-Index/Get-WindowsImageSelection (EditionId selection + fallback branches), mocked `Get-WindowsImage`.
- [ ] `FFUDevelopment/Tests/Unit/FFU.Imaging.AddBootFiles.Tests.ps1` — ADK bcdboot path resolution + hard-fail-on-missing.
- [ ] Year-normalization tests (table-driven) for `Get-EffectiveDriverWindowsRelease` — LTSC vs Server 2019 collision.
- [ ] SKU→EditionId map completeness assertion — every friendly SKU has a mapping (test gate per CONTEXT D-06).

*Existing `FFUDevelopment/Tests/Unit` infrastructure (Invoke-PesterTests.ps1) covers framework/harness — only the per-function test files above are new.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Correct edition captured from real non-English / multi-edition ISO | CORRECT-04 | Requires real localized Windows media; cannot synthesize a faithful non-English WIM in CI | Build from a non-English (e.g. de-DE) multi-edition ISO; confirm the captured FFU is the requested edition |
| Single-edition ISO salvage (auto-select + correct FFU naming) | CORRECT-01 | Needs a real single-edition VL ISO + full build | Build with a SKU absent from a single-edition ISO; confirm build proceeds and FFU is named for the present edition (not the requested one) |
| FFU boots on Secure-Boot-2023-cert hardware | CORRECT-03 | Requires physical device with the 2023 cert in its Secure Boot DB | Apply the FFU to a 2023-cert device; confirm it boots (no Secure Boot violation) |
| LTSC driver download end-to-end | CORRECT-02 | Requires live OEM driver endpoints + an LTSC build | Run an LTSC (2021/2024) build with Make/Model; confirm drivers download without a release-year failure |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
