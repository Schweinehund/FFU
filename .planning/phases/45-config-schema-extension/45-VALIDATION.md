---
phase: 45
slug: config-schema-extension
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-20
---

# Phase 45 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 5.x |
| **Config file** | Tests/Unit/Invoke-PesterTests.ps1 |
| **Quick run command** | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ConfigMigration'` |
| **Full suite command** | `.\Tests\Unit\Invoke-PesterTests.ps1` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ConfigMigration'`
- **After every plan wave:** Run `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 45-01-01 | 01 | 1 | CONFIG-02 | unit | `Invoke-Pester -Path Tests/Unit/FFU.ConfigMigration.Tests.ps1 -Tag 'SchemaVersion'` | Yes | pending |
| 45-01-02 | 01 | 1 | CONFIG-02 | unit | `Invoke-Pester -Path Tests/Unit/FFU.ConfigMigration.Tests.ps1 -Tag 'Migration'` | Yes | pending |
| 45-01-03 | 01 | 1 | CONFIG-02 | unit | `Invoke-Pester -Path Tests/Unit/FFU.ConfigMigration.Tests.ps1` (backup test per D-16) | Yes | pending |
| 45-02-01 | 02 | 2 | CONFIG-01 | schema | `powershell -Command "Get-Content 'FFUDevelopment/config/ffubuilder-config.schema.json' -Raw \| ConvertFrom-Json \| Out-Null"` | Yes | pending |
| 45-02-02 | 02 | 2 | CONFIG-01 | source | `powershell -Command "Import-Module .\FFUDevelopment\FFUUI.Core -Force -ErrorAction Stop"` + source grep for ActiveMode/USBMode keys | Yes | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `Tests/Unit/FFU.ConfigMigration.Tests.ps1` — update existing version assertions (1.2 to 1.3), add v1.3 migration tests + backup test

*No fixture files needed — tests use in-memory hashtables per RESEARCH.md recommendation.*

*Existing Pester infrastructure covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Config round-trip through UI save/load | CONFIG-02 | Requires WPF UI context | Load UI, save config, verify USBMode section in JSON |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
