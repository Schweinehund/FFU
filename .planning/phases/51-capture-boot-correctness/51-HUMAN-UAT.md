---
status: partial
phase: 51-capture-boot-correctness
source: [51-VERIFICATION.md]
started: 2026-06-26
updated: 2026-06-26
---

## Current Test

[awaiting human testing — requires real media / hardware / live network not available in CI]

## Tests

### 1. Non-English / multi-edition ISO capture (CORRECT-04)
expected: Building from a non-English (e.g. de-DE) multi-edition ISO captures the *requested* edition via the EditionId/InstallationType Tier-1 path (not a localized name-substring match).
result: [pending]

### 2. Single-edition ISO salvage + naming (CORRECT-01)
expected: Building with a SKU absent from a single-edition ISO auto-selects the one present edition (Tier-3) and the resulting FFU is named/cached for the edition actually captured.
result: [pending]

### 3. Mismatched-SKU ISO salvage propagation (CORRECT-01)
expected: When a fallback edition is selected, `ResolvedWindowsSKU` propagation renames the FFU to the actually-captured edition (naming, VHDX cache, servicing all use the selected edition).
result: [pending]

### 4. Secure Boot 2023 hardware boot (CORRECT-03)
expected: An FFU captured with ADK bcdboot boots on a device carrying the Windows UEFI CA 2023 Secure Boot certificate (no Secure Boot violation at first boot).
result: [pending]

### 5. LTSC 2021/2024 OEM driver download (CORRECT-02)
expected: An LTSC (2021/2024) build with Make/Model downloads OEM drivers end-to-end without a release-year validation failure (normalized `$driverWindowsRelease` resolves the catalog lookup).
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps

None — all 5 items are inherently human-UAT (real media / Secure-Boot-2023 hardware / live driver endpoints), not code gaps. All 13 automated must-haves are VERIFIED (51-VERIFICATION.md). Re-run via `/gsd-verify-work 51` when a test environment is available.
