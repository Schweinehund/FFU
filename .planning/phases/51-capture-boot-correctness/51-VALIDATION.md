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

> **Framework reconciliation (PATTERNS.md finding #4, confirmed by plan-checker):** the
> fork's `FFUDevelopment/Tests/*.ps1` do NOT use Pester 5.x — they use a custom
> `Write-TestResult` helper that `exit`s 0/1 (analog: `Test-OSPartitionLookup.ps1`).
> The Pester references elsewhere are aspirational. Phase 51 tests therefore live in a
> single new suite, `FFUDevelopment/Tests/Test-Phase51Correctness.ps1`, created in
> Plan 51-01 and appended by Plans 02/03.

| Property | Value |
|----------|-------|
| **Framework** | Custom `Write-TestResult` content-match harness (exit 0/1) — NOT Pester |
| **Config file** | none — single suite `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` |
| **Quick run command** | `pwsh -File .\FFUDevelopment\Tests\Test-Phase51Correctness.ps1` |
| **Full suite command** | `pwsh -File .\FFUDevelopment\Tests\Test-Phase51Correctness.ps1` + module-import + PSScriptAnalyzer (no new errors) |
| **Estimated runtime** | < 30 seconds (content-match assertions, no real WIM/DISM) |

> Verification is primarily content-match (`-match`) against module source plus module-import and PSScriptAnalyzer gates — the non-interactive correctness ports are asserted structurally; real-media / Secure-Boot-2023 behaviors are manual-only (see below).

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

Single new suite `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` (created Plan 51-01-T3, appended by 02-T3 / 03-T2), with sections:

- [ ] CORRECT-04 / Get-WindowsImageSelection — EditionId/InstallationType selection + exact-name fallback (content-match assertions on the rewritten function).
- [ ] CORRECT-06 map completeness — every friendly SKU value has a SKU→EditionId mapping (test gate per CONTEXT D-06; ~19/24 EditionId tokens asserted present).
- [ ] CORRECT-01 fallback — Read-Host/`while ($true)` absent; single-candidate auto-select returns `ResolvedWindowsSKU`; ≥2-candidate throw message present; caller propagation reassignment present.
- [ ] CORRECT-03 — `Add-BootFiles` ADK bcdboot path + hard-fail string; `Test-FFUADK` bcdboot existence check.
- [ ] CORRECT-02 — `Get-EffectiveDriverWindowsRelease` mapping (2016/2019/2021→10, 2024→11; Server 2019 stays 2019); global `$WindowsRelease` not reassigned.

*No new harness needed — the `Write-TestResult` helper already exists in the Tests folder.*

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
