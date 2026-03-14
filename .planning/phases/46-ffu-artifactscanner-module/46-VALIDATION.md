---
phase: 46
slug: ffu-artifactscanner-module
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-14
---

# Phase 46 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 5.x |
| **Config file** | None — runner is `Tests/Unit/Invoke-PesterTests.ps1` |
| **Quick run command** | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ArtifactScanner'` |
| **Full suite command** | `.\Tests\Unit\Invoke-PesterTests.ps1` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ArtifactScanner'`
- **After every plan wave:** Run `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 46-01-01 | 01 | 0 | DISC-01 | unit | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ArtifactScanner'` | ❌ W0 | ⬜ pending |
| 46-01-02 | 01 | 0 | VALID-01 | unit | same | ❌ W0 | ⬜ pending |
| 46-01-03 | 01 | 0 | VALID-04 | unit | same | ❌ W0 | ⬜ pending |
| 46-02-01 | 02 | 1 | DISC-01 | unit | same | ❌ W0 | ⬜ pending |
| 46-02-02 | 02 | 1 | VALID-01 | unit | same | ❌ W0 | ⬜ pending |
| 46-03-01 | 03 | 1 | VALID-02 | unit | same | ❌ W0 | ⬜ pending |
| 46-03-02 | 03 | 1 | VALID-02 | unit | same | ❌ W0 | ⬜ pending |
| 46-04-01 | 04 | 2 | VALID-03 | unit | same | ❌ W0 | ⬜ pending |
| 46-04-02 | 04 | 2 | VALID-03 | unit | same | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/Unit/FFU.ArtifactScanner.Tests.ps1` — stubs for DISC-01, VALID-01, VALID-02, VALID-03, VALID-04
- [ ] `FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1` — enums + data classes
- [ ] `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1` — module root
- [ ] `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psd1` — manifest

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| DISM extracts real FFU metadata | VALID-02 | Requires actual FFU file and DISM service | Run `Get-ArtifactMetadata -FFUPath <real.ffu>` on a test machine with an FFU file |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
