---
status: partial
phase: 50-selective-rebuild-pipeline
source: [50-VERIFICATION.md, 50-REVIEW.md]
started: 2026-06-22
updated: 2026-06-22
---

## Current Test

[awaiting human testing]

## Tests

### 1. ComboBox tier rendering (visual)
expected: Launch `BuildFFUVM_UI.ps1`, switch to USB Mode. Each artifact card shows a disposition ComboBox with the correct items: FFU = single disabled "Reuse" + helper text "To rebuild the OS image, switch to Full Build"; DeployISO = enabled Reuse/Rebuild (no Skip); Drivers/AppsISO = Reuse/Rebuild/Skip; PPKG/Unattend/Autopilot = Reuse/Skip.
result: [pending]

### 2. Config persistence round-trip (functional UI)
expected: Set Drivers = Rebuild, save config, restart the UI, reload the config. The Drivers ComboBox restores to "Rebuild" and the saved config JSON contains `Disposition` (no legacy `Include` key) for USB artifacts.
result: [pending]

### 3. Degraded artifact rendering (visual)
expected: Create a zero-byte / corrupt artifact file, trigger a USB-Mode scan. The card shows DarkOrange "Found (degraded)" status text and a visible warning TextBlock; disposition still defaults to Reuse.
result: [pending]

### 4. End-to-end selective rebuild (real build environment)
expected: With a real FFU + DeployISO present, mark Drivers = Rebuild and FFU = Reuse, click Create USB. The Monitor log shows ONLY the driver rebuild phase firing (no VM/OS build, no AppsISO/DeployISO rebuild), and the finished USB contains the freshly rebuilt drivers combined with the reused FFU. Also spot-check an AppsISO = Rebuild run to confirm the rebuilt Apps.iso lands on the USB (regression guard for the CR-01/CR-02 clobber bug fixed during this phase).

result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps

(none recorded yet — pending human testing)

## Known Limitations (from code review)

- **WR-01 (minor):** DeployISO `disposition = Rebuild` only takes effect when a DeployISO is already present. If DeployISO is Missing, the `IsReady` required-artifact gate aborts USB-Mode before the rebuild block runs, so a Missing DeployISO cannot be regenerated from USB Mode (use a full build). FFU + DeployISO remain mandatory inputs. Considered acceptable for this milestone; revisit if rebuild-from-missing for DeployISO is desired.
