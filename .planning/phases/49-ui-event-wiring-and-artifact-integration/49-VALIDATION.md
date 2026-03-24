---
phase: 49
slug: ui-event-wiring-and-artifact-integration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 49 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 5.x |
| **Config file** | Tests/Unit/Invoke-PesterTests.ps1 |
| **Quick run command** | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFUUI.Core'` |
| **Full suite command** | `.\Tests\Unit\Invoke-PesterTests.ps1` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFUUI.Core'`
- **After every plan wave:** Run `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 49-01-01 | 01 | 1 | DISC-02 | unit | `Invoke-Pester -Path Tests\Unit\Phase49.Tests.ps1 -Tag BrowseHandler` | ❌ W0 | ⬜ pending |
| 49-01-02 | 01 | 1 | DISC-03 | unit | `Invoke-Pester -Path Tests\Unit\Phase49.Tests.ps1 -Tag ConfigPersistence` | ❌ W0 | ⬜ pending |
| 49-01-03 | 01 | 1 | USB-02 | unit (mock) | `Invoke-Pester -Path Tests\Unit\Phase49.Tests.ps1 -Tag USBDriveDetection` | ❌ W0 | ⬜ pending |
| 49-01-04 | 01 | 1 | USB-03 | unit | `Invoke-Pester -Path Tests\Unit\Phase49.Tests.ps1 -Tag IncludeFlags` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/Unit/Phase49.Tests.ps1` — stubs for DISC-02, DISC-03, USB-02, USB-03
- [ ] Mock patterns for `Find-FFUArtifacts`, `Get-USBDrives`, `Invoke-BrowseAction` (WPF-free unit tests)

*Existing infrastructure covers test runner and module import tests.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Mode switch hides/shows correct tabs | DISC-02 | Requires WPF DispatcherTimer and visual verification | 1. Launch UI 2. Click USB Mode radio 3. Verify 7 Build tabs hidden, USB tab visible 4. Click Full Build radio 5. Verify tabs restored |
| Browse dialog opens correct filter | DISC-02 | WPF file dialog cannot be automated in Pester | 1. Click each Browse button 2. Verify correct file filter (.ffu, .iso, .xml, .ppkg) 3. Verify selected path updates TextBlock |
| Config survives restart | DISC-03 | Requires full app restart cycle | 1. Set USB Mode 2. Browse to custom paths 3. Close/reopen UI 4. Verify USB Mode active and paths restored |
| USB drive list populates | USB-02 | Requires physical USB drive | 1. Insert USB drive 2. Click Check USB Drives 3. Verify drive appears in list |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
