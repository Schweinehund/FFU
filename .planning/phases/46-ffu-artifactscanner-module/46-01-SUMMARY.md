---
phase: 46-ffu-artifactscanner-module
plan: "01"
subsystem: FFU.ArtifactScanner
tags:
  - new-module
  - data-contract
  - powershell-classes
  - dism
  - usb-mode
dependency_graph:
  requires:
    - FFU.Core (RequiredModules)
    - FFU.Preflight (RequiredModules, Test-FFUWimMount)
  provides:
    - FFU.ArtifactScanner module at FFUDevelopment/Modules/FFU.ArtifactScanner/
    - ArtifactManifest, ArtifactResult, FFUMetadata, CompatibilityWarning, ArtifactFileEntry classes
    - ArtifactStatus, ArtifactType enums
    - Get-ArtifactMetadata public function
    - New-ArtifactManifest, New-ArtifactResult factory functions
  affects:
    - Phase 47 (pipeline reads ArtifactManifest)
    - Phase 48 (UI columns bind to ArtifactResult properties)
    - Phase 49 (controls use per-artifact ArtifactResult)
tech_stack:
  added:
    - FFU.ArtifactScanner module (new)
  patterns:
    - Classes/ subfolder with dot-sourced ps1 (FFU.Hypervisor pattern)
    - InModuleScope Pester tests for PowerShell class assertions (Pitfall 4 mitigation)
    - Factory functions for cross-scope class instantiation (New-ArtifactManifest, New-ArtifactResult)
    - DISM Get-WindowsImage on FFU files (no mount required) with WIMMount gate
    - Architecture integer-to-string mapping (DISM encoding: 0=x86, 9=x64, 12=arm64)
key_files:
  created:
    - FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1
    - FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1
    - FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psd1
    - Tests/Unit/FFU.ArtifactScanner.Tests.ps1
  modified:
    - Tests/Unit/Invoke-PesterTests.ps1 (added FFU.ArtifactScanner to ValidateSet)
    - FFUDevelopment/version.json (added module entry, bumped 1.10.0->1.10.1)
    - CHANGELOG_FORK.md (added Phase 46-01 entry)
    - CLAUDE.md (added module to component structure and module summary table)
decisions:
  - "InModuleScope required for all PowerShell class/enum assertions in Pester — types not exported to caller scope (Pitfall 4)"
  - "Regex word boundary \\b fails with underscore delimiters; used (?:^|[^a-z]) anchors for architecture filename parsing"
  - "ArtifactResult.Files initialization tested via .Count property not BeOfType — generic type identity differs between Pester re-import contexts"
  - "Get-ArtifactMetadata and factory functions must be tested InModuleScope — function class instantiation fails in caller scope at runtime"
metrics:
  duration: "~14 minutes"
  completed_date: "2026-03-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 4
  tests_written: 79
  tests_passing: 79
---

# Phase 46 Plan 01: FFU.ArtifactScanner Module Scaffold Summary

**One-liner:** PowerShell module with typed data contract classes (ArtifactManifest, ArtifactResult, FFUMetadata) and Get-ArtifactMetadata using DISM Get-WindowsImage with filename-parsing fallback.

## What Was Built

### Module Structure
```
FFUDevelopment/Modules/FFU.ArtifactScanner/
├── Classes/
│   └── ArtifactScanner.Classes.ps1     # Enums + data classes (dot-sourced)
├── FFU.ArtifactScanner.psm1            # Module root: loads classes + public functions
└── FFU.ArtifactScanner.psd1            # Manifest: RequiredModules, FunctionsToExport, GUID
```

### Data Contract
- **Enums:** `ArtifactStatus` (Found/Missing/Error/Degraded), `ArtifactType` (FFU/DeployISO/Drivers/PPKG/Unattend/Autopilot/AppsISO)
- **Classes:**
  - `ArtifactFileEntry` — FilePath, FileSizeBytes, LastWriteTime
  - `FFUMetadata` — WindowsVersion, WindowsSKU, Architecture, ImageName, BuildDate, MetadataSource, ErrorMessage
  - `ArtifactResult` — all ArtifactFileEntry properties + ArtifactType, Status, AgeDays, IsPrimary, Metadata, Files (List[ArtifactFileEntry]), FileCount, TotalSizeBytes
  - `CompatibilityWarning` — Severity, Message, AffectedArtifacts
  - `ArtifactManifest` — BasePath, ScanTimestamp, FFUFiles[], DeployISO, Drivers, PPKGFiles[], UnattendFiles[], AutopilotFiles[], AppsISO, Warnings[], FoundCount, MissingCount, ErrorCount, IsReady

### Get-ArtifactMetadata
- **DISM path:** `Import-Module DISM` + `Get-WindowsImage -ImagePath $FFUPath -Index 1`
- **Architecture mapping:** 0→x86, 9→x64, 12→arm64 via `ConvertTo-ArchitectureString` private helper
- **Filename fallback:** regex extraction of arch (arm64, x64, x86) and version hint (23H2, etc.) from FFU filename
- **MetadataSource:** 'DISM' or 'Filename' to indicate which extraction path was used
- **WimMountAvailable parameter:** skip DISM entirely when WIMMount filter driver unavailable

### Factory Functions
- `New-ArtifactManifest` — returns `[ArtifactManifest]` with ScanTimestamp initialized
- `New-ArtifactResult` — returns `[ArtifactResult]` with ArtifactType set and Files list initialized

### Stub Functions (Plan 46-02)
- `Find-FFUArtifacts` — returns empty ArtifactManifest; full implementation in Plan 46-02
- `Test-ArtifactCompatibility` — returns empty array; full implementation in Plan 46-02

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PowerShell class cross-scope resolution in Pester tests**
- **Found during:** Task 1 test execution (GREEN phase)
- **Issue:** Direct type syntax `[ArtifactStatus]::Found` fails in Pester test scope; module classes not exported to caller's scope
- **Fix:** Wrapped all class/enum assertions in `InModuleScope FFU.ArtifactScanner { }` blocks; moved factory function tests to `InModuleScope` as well
- **Files modified:** `Tests/Unit/FFU.ArtifactScanner.Tests.ps1`
- **Research reference:** Pitfall 4 in 46-RESEARCH.md (already documented — fix applied as designed)

**2. [Rule 1 - Bug] Regex word boundary `\b` fails with underscore-delimited architecture tokens**
- **Found during:** Task 2 test execution (filename fallback path)
- **Issue:** `Windows11_23H2_x64_Pro.ffu` — `\b` before `x64` fails because `_` is a word character
- **Fix:** Replaced `\b(x64)\b` with `(?:^|[^a-z])(x64)(?:[^a-z]|$)` non-word-boundary anchors
- **Files modified:** `FFU.ArtifactScanner.psm1` (Get-MetadataFromFilename function)

**3. [Rule 1 - Bug] ArtifactResult.Files type assertion fails in Pester InModuleScope**
- **Found during:** Task 1 class tests
- **Issue:** `Should -BeOfType [System.Collections.Generic.List[ArtifactFileEntry]]` fails in Pester when module is re-imported during test run (class assembly identity changes)
- **Fix:** Changed assertion to `{ $result.Files.Count } | Should -Not -Throw` + `$result.Files.Count | Should -Be 0` — tests initialization without requiring exact type identity
- **Files modified:** `Tests/Unit/FFU.ArtifactScanner.Tests.ps1`

## Tests Written

79 tests across 10 Describe blocks:
- Module import (6 tests)
- ArtifactStatus enum (4 tests)
- ArtifactType enum (7 tests)
- ArtifactFileEntry class (4 tests)
- FFUMetadata class (8 tests)
- ArtifactResult class (11 tests)
- CompatibilityWarning class (4 tests)
- ArtifactManifest class (15 tests)
- Get-ArtifactMetadata — DISM/arch/fallback/WIMMount paths (15 tests)
- Factory functions (5 tests)

## Self-Check: PASSED

All created files verified present:
- FOUND: FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1
- FOUND: FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1
- FOUND: FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psd1
- FOUND: Tests/Unit/FFU.ArtifactScanner.Tests.ps1

Commits verified:
- 55d4c00: feat(46-01): create FFU.ArtifactScanner module with data contract classes and Get-ArtifactMetadata
- ef5033f: chore(46-01): update version.json and CHANGELOG for FFU.ArtifactScanner module

Tests: 79/79 passing
