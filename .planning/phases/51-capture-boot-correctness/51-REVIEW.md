---
phase: 51-capture-boot-correctness
reviewed: 2026-06-26T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1
  - FFUDevelopment/BuildFFUVM.ps1
  - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1
  - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1
  - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1
  - FFUDevelopment/Tests/Test-Phase51Correctness.ps1
  - FFUDevelopment/version.json
  - CHANGELOG_FORK.md
  - FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 51: Code Review Report

**Reviewed:** 2026-06-26
**Depth:** standard
**Files Reviewed:** 9 (Phase 51 diff only — CORRECT-01 through CORRECT-04)
**Status:** issues_found

## Summary

Phase 51 ports four upstream correctness fixes (commits 5aaa1ad, b2a7ef5, 04dfb5f, 6c0ee8a) into the modular fork:

- **CORRECT-04**: `Get-WindowsImageSelection` replaces the fragile Substring-based `Get-Index` with a complete 24-entry SKU→EditionId switch map, InstallationType-based server disambiguation, and an exact-name fallback.
- **CORRECT-01**: `ResolvedWindowsSKU` propagates back to `$WindowsSKU` at the call site; `Get-WindowsTargetRuntimeState` recomputes dependent runtime state; the `Read-Host` loop that deadlocked ThreadJob builds is deleted.
- **CORRECT-02**: `Get-EffectiveDriverWindowsRelease` normalizes LTSC year-based release numbers to base Windows releases (2016/2019/2021→10, 2024→11) scoped to `$driverWindowsRelease` without mutating the load-bearing global.
- **CORRECT-03**: `Add-BootFiles` mandates ADK bcdboot.exe via new `-AdkPath`/`-WindowsArch` parameters; `Test-FFUADK` adds CHECK 5 for early detection.

The core logic is sound across all four fixes. The SKU↔EditionId round-trip is internally consistent. ThreadJob safety is maintained throughout — no `Read-Host`, `Write-Host`, or `Get-Date` in the build path. The `throw` in `Add-BootFiles` is a native PowerShell statement and is safe in ThreadJob contexts. Versioning (FFU.Imaging 1.4.0, FFU.Preflight 1.7.0, main 1.12.0, ApplyFFU.ps1 `$version = '1.12.0'`) is consistent across all files.

Three warnings are present: a silent exception swallow that would mask per-index WIM read failures, a missing `[CmdletBinding()]` on the modified `Add-BootFiles`, and a cross-file arch path inconsistency for x86 builds introduced when CHECK 5 reuses the pre-existing CHECK 4 arch mapping that maps x86 to `arm64` rather than `amd64`.

## Warnings

### WR-01: Silent `catch { $null }` in image-metadata enumeration masks per-index WIM failures

**File:** `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1:669-671`

**Issue:** The inner `catch` block that guards `Get-WindowsImage -Index N` calls discards exceptions without any log entry:

```powershell
$imageMetadata = @(foreach ($imageIndex in $imageIndexes) {
    try {
        $details = Get-WindowsImage -ImagePath $WindowsImagePath -Index $imageIndex.ImageIndex
        [PSCustomObject]@{ ... }
    }
    catch { $null }    # <-- silently discarded
}) | Where-Object { $null -ne $_ }
```

If one index fails to enumerate (e.g., an ESD with a partially-read index, or a race with another process holding the file), `$imageMetadata` is silently smaller than expected. Tier 1 EditionId matching then misses the skipped index, and the function may fall through to Tier 3 (auto-select-or-throw). In the worst case — the target edition's index is the one that failed — Tier 3 auto-selects a different edition with no diagnostic log explaining why the EditionId path was bypassed. The captured FFU would contain the wrong Windows edition.

**Fix:** Log the failure at a minimum before returning `$null`, so the build log captures the partial-enumeration event:

```powershell
catch {
    WriteLog "WARNING: Failed to enumerate metadata for image index $($imageIndex.ImageIndex): $($_.Exception.Message). Skipping."
    $null
}
```

---

### WR-02: `Add-BootFiles` lacks `[CmdletBinding()]` and `[OutputType()]`

**File:** `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1:2004-2018`

**Issue:** Phase 51 adds mandatory parameters `-AdkPath` and `-WindowsArch` to `Add-BootFiles`, but the function still lacks `[CmdletBinding()]` and `[OutputType()]`. Every other function added or significantly modified in this phase (`Get-WindowsImageSelection`, `Get-ResolvedWindowsSKUFromImage`) carries both attributes. The project's PowerShell Style Standard (CLAUDE.md) requires `[CmdletBinding()]` and `[OutputType()]` on all functions. The absence means the function cannot use `-Verbose`, `-ErrorAction`, or other common parameters, and PSScriptAnalyzer will flag it.

**Fix:**

```powershell
function Add-BootFiles {
    # Source: upstream commit 6c0ee8a ...
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OsPartitionDriveLetter,
        ...
    )
```

---

### WR-03: `Test-FFUADK` CHECK 5 validates the wrong bcdboot path for x86 builds

**File:** `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1:1082,1114-1122`

**Issue:** Phase 51 adds CHECK 5 which reuses `$archPath` computed by the pre-existing CHECK 4 at line 1082:

```powershell
# CHECK 4 (pre-existing):
$archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }

# CHECK 5 (Phase 51, added):
$bcdbootExe = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$archPath\BCDBoot\bcdboot.exe"
```

For `$WindowsArch = 'x86'`, `$archPath` evaluates to `'arm64'`, so CHECK 5 validates `arm64\BCDBoot\bcdboot.exe`.

However, `Add-BootFiles` (FFU.Imaging.psm1:2020) computes its own arch mapping:

```powershell
$bcdBootArchitecture = if ($WindowsArch -ieq 'arm64') { 'arm64' } else { 'amd64' }
```

For `x86`, this yields `'amd64'`, so `Add-BootFiles` would resolve `amd64\BCDBoot\bcdboot.exe`.

The preflight validates a different bcdboot binary than the one `Add-BootFiles` actually invokes. On a system where `amd64\BCDBoot\bcdboot.exe` exists but `arm64\BCDBoot\bcdboot.exe` does not: CHECK 5 reports failure, blocking the build even though `Add-BootFiles` would succeed. On a system where `arm64\BCDBoot\bcdboot.exe` exists but `amd64\BCDBoot\bcdboot.exe` does not: CHECK 5 passes, then `Add-BootFiles` hard-fails mid-build.

x86 is deprecated for Windows 11 enterprise builds, limiting blast radius to rare x86 images. Nevertheless, Phase 51 introduces this specific mismatch at the call site where CHECK 5 was authored. The fix is to use a standalone arch computation in CHECK 5 rather than inheriting CHECK 4's result:

```powershell
# CHECK 5: ADK BCDBoot executable (CORRECT-03)
# Use the same arch mapping as Add-BootFiles: x86+x64 -> amd64, arm64 -> arm64
$bcdbootArch = if ($WindowsArch -ieq 'arm64') { 'arm64' } else { 'amd64' }
$bcdbootExe = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$bcdbootArch\BCDBoot\bcdboot.exe"
if (-not (Test-Path -Path $bcdbootExe -PathType Leaf)) {
    $errors += "ADK bcdboot.exe not found (required for Secure Boot 2023 compatibility)"
    $missingFiles += $bcdbootExe
}
```

## Info

### IN-01: Phantom `'CoreSingleLanguage'` key in the SKU→EditionId forward switch

**File:** `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1:626`

**Issue:** The forward switch in `Get-WindowsImageSelection` contains:

```powershell
'Home Single Language' { @('CoreSingleLanguage') }
'CoreSingleLanguage'   { @('CoreSingleLanguage') }   # phantom entry
```

`CoreSingleLanguage` is a DISM EditionId token, not a user-facing SKU name. No caller would pass `"CoreSingleLanguage"` as `$WindowsSKU` — the valid input is `"Home Single Language"`. The phantom key is dead code and creates a misleading impression that EditionId tokens are accepted as `$WindowsSKU` input. It is harmless but should be removed for clarity.

**Fix:** Remove the `'CoreSingleLanguage'` key from the forward switch. The `'Home Single Language'` entry already covers the correct mapping.

---

### IN-02: Tier 3 fallback logs no per-tier trace before auto-selecting

**File:** `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1:703-716`

**Issue:** When Tier 1 (EditionId) and Tier 2 (exact name) both fail, the code logs the available editions list and then enters Tier 3 (version-number regex filter + auto-select). However, there is no explicit log entry stating "Falling through to Tier 3 auto-select" at the decision point. If a build reaches auto-select, the log shows the editions list but not the reason Tiers 1 and 2 were bypassed (e.g., whether the EditionId candidates list was empty or the EditionId simply wasn't found). This complicates post-mortem diagnosis for the case where the SKU map has a gap and the image name fallback also misses.

**Fix:** Add a trace log before Tier 3:

```powershell
WriteLog "Tier 1 (EditionId) and Tier 2 (exact name) produced no match. Attempting Tier 3 fallback..."
$relevantCandidates = @($imageMetadata | Where-Object { $_.ImageName -match '(10|11|2016|2019|202\d)' })
```

---

_Reviewed: 2026-06-26_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
