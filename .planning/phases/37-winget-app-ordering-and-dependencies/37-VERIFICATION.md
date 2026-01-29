---
phase: 37-winget-app-ordering-and-dependencies
verified: 2026-01-29T02:15:00Z
status: passed
score: 4/4 must-haves verified
gaps: []
---

# Phase 37: Winget App Ordering and Dependencies Verification Report

**Phase Goal:** Enforce AppList.json installation order and resolve Win32 app dependencies with deduplication
**Verified:** 2026-01-29T02:15:00Z
**Status:** PASSED
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Apps install in the exact order specified in AppList.json | VERIFIED | Get-Apps post-download reorder section (lines 617-746): desiredOrderMap, 3-key stable sort, atomic write |
| 2 | Win32 app dependencies resolved and deduplicated | VERIFIED | Add-Win32DependencySilentInstallCommands (line 1109): Dependencies YAML discovery, PackageIdentifier dedup, DependencyFor metadata |
| 3 | Build log shows installation order and dependency insertions | VERIFIED | Per-app priority logging (line 708), Install Manifest (lines 720-729), dependency log (line 1163) |
| 4 | Pester tests verify ordering and dependency resolution | VERIFIED | 35 new Phase37 tests in 9 Describe blocks; 51 total (16 existing + 35 new) |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1 | Helper functions + upgraded functions + reorder logic | VERIFIED | 1196 lines, 5 new functions, all key links wired |
| Tests/Unit/FFU.Common.Winget.Tests.ps1 | Pester tests for Phase 37 | VERIFIED | 1266 lines, 51 total tests, all tagged |

### Artifact Detail: FFU.Common.Winget.psm1

**Level 1 (Existence):** EXISTS (1196 lines)
**Level 2 (Substantive):**
- 4 helper functions: Get-WinGetWin32AppsJsonMutexName (line 17), Invoke-WithNamedMutex (line 30), Set-FileContentAtomic (line 57), Get-WinGetYamlScalarValue (line 79)
- Add-Win32SilentInstallCommand (line 823): 6 new params (YamlFilePath, BasePathOverride, PackageIdentifier, DependencyFor, SkipRemoveOnFailure)
- Add-Win32DependencySilentInstallCommands (line 1109): 82 lines, Dependencies/ discovery, YAML processing
- Post-download reorder (lines 617-746): 130 lines, order map, 3-key sort, priority reassignment, manifest logging
- No stub patterns (zero TODO/FIXME/placeholder)

**Level 3 (Wired):**
- Invoke-WithNamedMutex: 3 call sites (lines 569, 636, 1019)
- Set-FileContentAtomic: 3 call sites (lines 600, 712, 1090)
- Add-Win32DependencySilentInstallCommands: 3 call sites (lines 156, 167, 340)
- Export-ModuleMember includes Add-Win32DependencySilentInstallCommands (line 1197)

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Add-Win32SilentInstallCommand | Invoke-WithNamedMutex | mutex wrapper (line 1019) | WIRED | Replaces raw Mutex |
| Add-Win32SilentInstallCommand | Set-FileContentAtomic | atomic write (line 1090) | WIRED | Replaces Set-Content |
| Add-Win32SilentInstallCommand | PackageIdentifier dedup | three-tier (lines 1030-1063) | WIRED | ID + Name + Command |
| Get-Application | Add-Win32DependencySilentInstallCommands | fresh hook (line 340) | WIRED | Warns on failure |
| Get-Application | Add-Win32DependencySilentInstallCommands | pre-downloaded (lines 156, 167) | WIRED | Both arch variants |
| Get-Apps | desiredOrderMap | reorder (lines 624-665) | WIRED | AppList.json order map |
| Get-Apps override | Invoke-WithNamedMutex | mutex wrapper (line 569) | WIRED | Upgraded from raw mutex |
| Get-Apps override | Set-FileContentAtomic | atomic write (line 600) | WIRED | Upgraded from Set-Content |
| Add-Win32DependencySilentInstallCommands | Add-Win32SilentInstallCommand | DependencyFor (lines 1152-1161) | WIRED | All 5 dependency params |
| Tests | FFU.Common.Winget module | Import-Module (line 34) | WIRED | Module imported and tested |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| WINGET-01: Apps install in exact order specified in AppList.json | SATISFIED | None |
| WINGET-02: Win32 app dependencies automatically resolved and deduplicated | SATISFIED | None |

### Anti-Patterns Found

No blocker or warning anti-patterns found. Two info-level matches (legitimate code, not stubs).

### Human Verification Required

#### 1. End-to-End AppList.json Ordering
**Test:** Configure AppList.json with 3+ winget apps. Run build. Check WinGetWin32Apps.json.
**Expected:** JSON entries match AppList.json order with sequential priorities.
**Why human:** Requires real WinGet downloads.

#### 2. Dependency Discovery with Real App
**Test:** Download winget app with Dependencies subfolder. Check WinGetWin32Apps.json.
**Expected:** Dependency entries with DependencyFor metadata sort before parent.
**Why human:** Requires actual WinGet package with dependency manifests.

#### 3. Build Log Output
**Test:** Run build with multiple winget apps. Check build log.
**Expected:** Log shows Install Manifest with numbered entries and dependency markers.
**Why human:** Requires full build execution.

### Gaps Summary

No gaps found. All four observable truths verified through three-level artifact inspection.

---

_Verified: 2026-01-29T02:15:00Z_
_Verifier: Claude (gsd-verifier)_
