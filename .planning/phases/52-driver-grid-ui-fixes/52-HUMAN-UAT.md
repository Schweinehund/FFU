---
status: partial
phase: 52-driver-grid-ui-fixes
source: [52-VERIFICATION.md]
started: 2026-06-28
updated: 2026-06-28
---

## Current Test

[awaiting human testing — launch the FFU Builder UI: `cd C:\FFUDevelopment; .\BuildFFUVM_UI.ps1`, open the Drivers tab]

## Tests

### 1. DGRID-01 — Filter persists after sort
expected: With a search filter active on the Drivers grid (e.g. type "Latitude"), clicking a column header to sort keeps the filter applied and sorts only the filtered rows — the list does NOT reset to all rows.
result: [pending]

### 2. DGRID-02 — Select-all scoped to visible rows
expected: With a filter active, clicking the header select-all checkbox selects/deselects ONLY the visible (filtered) rows; hidden rows retain their previous selection state.
result: [pending]

### 3. DGRID-02 — Header tri-state correctness
expected: With 3 rows visible (1 selected, 2 unselected), clicking the header selects all 3; clicking again clears all 3; deselecting one visible row drives the header to the indeterminate (tri-state) state.
result: [pending]

### 4. DGRID-02 — Save preserves hidden selections
expected: Select 2 drivers in the full (unfiltered) list, apply a filter that hides one of the selected rows, click Save — the saved Drivers.json includes BOTH selected drivers (the hidden one is not dropped).
result: [pending]

### 5. DGRID-02 — Header checkbox alignment
expected: On the Drivers tab the header select-all checkbox is horizontally centered and vertically aligned with the row checkboxes (no visual offset).
result: [pending]

### 6. DGRID-03 — Invalid CopyDrivers config blocked
expected: Set CopyDrivers = true and BuildUSBDrive = false (non-USB-only build) and start a build — the build stops with a clear error stating BuildUSBDrive must be true when CopyDrivers is set. A USB-only build with the same flags is NOT blocked.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
