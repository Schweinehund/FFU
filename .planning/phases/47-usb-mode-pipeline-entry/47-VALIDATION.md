---
phase: 47
slug: usb-mode-pipeline-entry
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 47 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 5.x |
| **Config file** | `Tests/Unit/Invoke-PesterTests.ps1` |
| **Quick run command** | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.Core'` |
| **Full suite command** | `.\Tests\Unit\Invoke-PesterTests.ps1` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.Core'`
- **After every plan wave:** Run `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 47-01-01 | 01 | 1 | USB-01 | unit | `Invoke-Pester -Path Tests/Unit/USBOnlyMode.Tests.ps1` | ❌ W0 | ⬜ pending |
| 47-01-02 | 01 | 1 | USB-04 | unit | `Invoke-Pester -Path Tests/Unit/USBOnlyMode.Tests.ps1` | ❌ W0 | ⬜ pending |
| 47-02-01 | 02 | 1 | USB-01 | integration | `Invoke-Pester -Path Tests/Unit/USBOnlyMode.Tests.ps1 -Tag 'ThreadJob'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/Unit/USBOnlyMode.Tests.ps1` — stubs for USB-01, USB-04 (param parsing, manifest validation, variable population, ThreadJob compatibility)
- [ ] Pester mocks for `Find-FFUArtifacts`, `Mount-DiskImage`, `Dismount-DiskImage`, `New-DeploymentUSB`

*Existing Pester infrastructure covers framework setup.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| USB drive assembly with real hardware | USB-01 | Requires physical USB drives | Attach USB drive, run `BuildFFUVM.ps1 -USBOnlyMode`, verify files copied |
| ISO mount on real filesystem | USB-01 | Mount-DiskImage requires admin + real ISO | Run with valid DeployISO path, verify mount succeeds |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
