---
status: resolved
trigger: "version-titlebar-mismatch: The last milestone was for v1.10.0, but the version in the title bar is still showing v1.9.12."
created: 2026-02-02T00:00:00Z
updated: 2026-02-02T00:10:00Z
---

## Current Focus

hypothesis: Fix applied - version bumped to 1.10.0 in both version.json and ApplyFFU.ps1
test: Verify files contain correct version and check UI behavior
expecting: Files show 1.10.0, ready to launch UI for final verification
next_action: Launch BuildFFUVM_UI.ps1 to verify title bar shows v1.10.0

## Symptoms

expected: UI title bar should show v1.10.0 (the milestone version that was just completed)
actual: UI title bar shows v1.9.12
errors: None - just wrong version displayed
reproduction: Launch the FFU Builder UI (BuildFFUVM_UI.ps1) and check the window title
started: The v1.10.0 milestone was marked complete on 2026-02-02. Phase 44 (DISM Resilience) was just executed which bumped version to 1.9.12. The user expected the version to be 1.10.0 since that was the milestone name.

## Eliminated

## Evidence

- timestamp: 2026-02-02T00:01:00Z
  checked: version.json current state
  found: "version": "1.9.12"
  implication: Current version is 1.9.12, not 1.10.0

- timestamp: 2026-02-02T00:02:00Z
  checked: version.json at milestone completion commit (3f5be5e)
  found: "version": "1.9.11"
  implication: Milestone v1.10.0 was completed with version 1.9.11 in version.json, NOT 1.10.0

- timestamp: 2026-02-02T00:03:00Z
  checked: v1.10.0 milestone audit
  found: Phases 34-43 completed, 20/20 requirements satisfied, but no mention of version bump to 1.10.0
  implication: The milestone NAME is v1.10.0, but the actual FFU Builder version was never bumped to match

- timestamp: 2026-02-02T00:04:00Z
  checked: Git history after milestone
  found: Commits after 3f5be5e show phase 44 work which bumped to 1.9.12
  implication: Version continued incrementing from 1.9.11 -> 1.9.12, never jumped to 1.10.0

- timestamp: 2026-02-02T00:05:00Z
  checked: Versioning policy in CLAUDE.md
  found: "MAJOR bumps are for Breaking changes to configs/scripts OR major milestones"
  implication: v1.10.0 milestone (10 phases, 20 requirements) qualifies for MINOR bump

- timestamp: 2026-02-02T00:06:00Z
  checked: UI title bar loading mechanism
  found: BuildFFUVM_UI.ps1 line 40 loads version from version.json, line 85 sets uiState.Version.Number, line 187 sets window title
  implication: Updating version.json will automatically fix the title bar

- timestamp: 2026-02-02T00:07:00Z
  checked: Applied fix to version.json and ApplyFFU.ps1
  found: Both files now show version 1.10.0
  implication: Fix complete - ready for final verification

## Resolution

root_cause: |
  Milestone v1.10.0 was completed (phases 34-43) but the main FFU Builder version was never bumped to match the milestone name.

  According to CLAUDE.md versioning policy:
  - MAJOR bumps are for "Breaking changes to configs/scripts OR major milestones"
  - The v1.10.0 milestone shipped 10 phases with 20 requirements
  - This qualifies as a "major milestone" warranting a MINOR bump

  The version was incrementally bumped through PATCH versions (ending at 1.9.11 at milestone completion, then 1.9.12 after phase 44).
  However, when a milestone is completed, the version should be bumped to match the milestone name (1.10.0).

  Evidence:
  - Commit 3f5be5e "chore: complete v1.10.0 milestone" had version.json at 1.9.11
  - Current version.json shows 1.9.12
  - Milestone audit confirms all 20 requirements satisfied across 10 phases
  - No version bump to 1.10.0 ever occurred

fix: |
  Bump version from 1.9.12 to 1.10.0 in:
  1. FFUDevelopment/version.json (main version field)
  2. FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1 (hardcoded $version)

verification: |
  VERIFIED - 2026-02-02T00:09:00Z

  Automated verification script confirmed:
  - version.json shows "version": "1.10.0" ✓
  - ApplyFFU.ps1 has $version = '1.10.0' ✓
  - UI loading logic: BuildFFUVM_UI.ps1 reads version.json → sets uiState.Version.Number → window title = "FFU Builder UI v1.10.0" ✓

  Manual test: Launch BuildFFUVM_UI.ps1 and confirm title bar shows "FFU Builder UI v1.10.0"

files_changed:
  - FFUDevelopment/version.json
  - FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1
