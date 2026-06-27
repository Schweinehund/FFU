---
phase: 51-capture-boot-correctness
verified: 2026-06-26T00:00:00Z
status: human_needed
score: 13/13 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Provide a non-English or multi-edition Windows ISO (e.g. French, Spanish, or a media containing both Pro and Home). Run a build targeting 'Pro'. Confirm the captured FFU is a Pro image, not a wrong edition."
    expected: "Build completes; FFU file is named and indexed as the Pro edition. The WriteLog output shows 'Selected image index N (SKU=Pro, EditionId=Professional)' — not a Tier 3 auto-select."
    why_human: "Real DISM media required; cannot mock Get-WindowsImage with live locale variation in content-match tests."
  - test: "Provide an ISO with exactly one edition (e.g. a Windows 10 LTSC 2021 media containing only 'Enterprise LTSC'). Request a build for 'Enterprise LTSC'. Confirm naming/caching."
    expected: "Build succeeds. FFU is named 'Enterprise LTSC'. No fallback WriteLog or throw. $WindowsSKU propagates correctly through naming/cache/checkpoint sites."
    why_human: "Single-edition ISO salvage path (Tier 3 → auto-select) requires actual WIM media."
  - test: "Provide an ISO where the exact requested SKU is not present but a single relevant candidate is (e.g. request 'Enterprise' but ISO only has 'Enterprise N'). Confirm auto-select and name propagation."
    expected: "Tier 3 fires, auto-selects 'Enterprise N'; $WindowsSKU is reassigned; FFU is named 'Enterprise N'; WriteLog shows the resolved SKU change."
    why_human: "Fallback edition propagation requires live WIM media for the edition-mismatch scenario."
  - test: "On a machine with Windows ADK installed, build an FFU and boot it on a device with a Secure Boot 2023 certificate (e.g. Pluton or post-2023 OEM device). Verify the image boots successfully."
    expected: "Device boots the deployed FFU without a Secure Boot violation. The ADK bcdboot used is at {ADKPath}\\Assessment and Deployment Kit\\Deployment Tools\\amd64\\BCDBoot\\bcdboot.exe."
    why_human: "Requires physical Secure Boot 2023-cert hardware; cannot simulate cert-variant differences in software."
  - test: "Run a full build targeting 'Enterprise LTSC 2021' or 'Enterprise LTSC 2024' with an OEM (HP, Lenovo, or Dell) driver download enabled. Confirm drivers are downloaded without a release-year error."
    expected: "OEM driver download completes. WriteLog shows 'Normalized WindowsRelease for single-model driver processing from 2021 to 10' (or 2024 to 11). No 'Win2021'/'Win2024' validation error from the OEM provider."
    why_human: "Requires live OEM driver catalog connectivity and an actual LTSC build run."
---

# Phase 51: Capture/Boot Correctness — Verification Report

**Phase Goal:** Builds never produce a wrong-edition, unbootable, or LTSC-failing artifact — the captured FFU always matches the edition the user actually built, boots on modern Secure Boot devices, and supports LTSC driver downloads.
**Verified:** 2026-06-26T00:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Image index selected via EditionId (primary) then exact ImageName -eq (fallback), never via localized name substring (CORRECT-04, D-05) | VERIFIED | `Get-WindowsImageSelection` (FFU.Imaging.psm1:571) implements Tier 1 EditionId match, Tier 2 exact `-eq`, Tier 3 single-candidate auto-select. No `.Substring(0,10)` or `.Substring(0,19)` in file. Test 68/68 passes. |
| 2 | Complete SKU→EditionId map covers every `$clientSKUs`/`$LTSCSKUs`/`$ServerSKUs` friendly name; map completeness enforced by test gate (CORRECT-04, D-06) | VERIFIED | 24-entry switch at psm1:622–646 includes Core, CoreN, CoreSingleLanguage, Education, EducationN, Professional, ProfessionalN, ProfessionalEducation, ProfessionalEducationN, ProfessionalWorkstation, ProfessionalWorkstationN, Enterprise, EnterpriseN, EnterpriseS, EnterpriseSN, IoTEnterpriseS, IoTEnterpriseSN, ServerStandard, ServerDatacenter. All 19 mandatory tokens pass the map-completeness gate in test suite. |
| 3 | Server Desktop Experience vs Server Core disambiguated by InstallationType (CORRECT-04, D-07) | VERIFIED | psm1:649–652: `$preferredInstallationType = if ($isDesktopExperienceRequested) { 'Server' } else { 'Server Core' }` applied when SKU is Standard/Datacenter. |
| 4 | Read-Host / while($true) fallback loop deleted; single relevant candidate auto-selects non-interactively; >=2 candidates WriteLog editions list then throw (CORRECT-01, D-01/D-02/D-03) | VERIFIED | No `Read-Host` or `while ($true)` in FFU.Imaging.psm1. Tier 3 at psm1:710–721 uses auto-select for 1 candidate, throw for ambiguity with editions list in build log. |
| 5 | After fallback edition chosen, `$WindowsSKU` reassigned to selected edition and runtime state recomputed, so naming/caching/servicing use the selected edition (CORRECT-01, D-04) | VERIFIED | BuildFFUVM.ps1:4563–4578: `$WindowsSKU = $windowsImageSelection.ResolvedWindowsSKU` guarded by `IsNullOrWhiteSpace`; `Get-WindowsTargetRuntimeState` recomputes `$installationType`, `$WindowsVersion`, `$isLTSC`, `$isWindows10LtscClient`, `$installLatestCuInVm`. |
| 6 | Add-BootFiles invokes ADK bcdboot.exe at `{AdkPath}\Assessment and Deployment Kit\Deployment Tools\<amd64|arm64>\BCDBoot\bcdboot.exe`, never the bare host bcdboot (CORRECT-03, D-09/D-11) | VERIFIED | psm1:2027–2040: `$bcdBootPath = Join-Path $AdkPath "Assessment and Deployment Kit\Deployment Tools\$bcdBootArchitecture\BCDBoot\bcdboot.exe"`. `Invoke-Process $bcdBootPath` replaces bare `bcdboot`. No host bcdboot fallback path. |
| 7 | If ADK bcdboot not found, Add-BootFiles hard-fails (throw) with actionable remediation rather than silently falling back (CORRECT-03, D-09) | VERIFIED | psm1:2030–2032: `if (-not (Test-Path -Path $bcdBootPath)) { throw "ADK BCDBoot was not found at '$bcdBootPath'. Install Windows ADK with Deployment Tools or run with -UpdateADK \`$true." }` |
| 8 | Test-FFUADK fails early with remediation when ADK bcdboot.exe is missing (CORRECT-03, D-12) | VERIFIED | FFU.Preflight.psm1:1114–1126: CHECK 5 uses dedicated `$bcdbootArchPath` (matching Add-BootFiles arch mapping), validates `BCDBoot\bcdboot.exe` existence, appends to `$errors`/`$missingFiles` for the existing pass/fail block. |
| 9 | ADK version logged at Add-BootFiles time as diagnostic (CORRECT-03, D-10/D-13) | VERIFIED | psm1:2033–2038: `WriteLog "Adding boot files using ADK bcdboot: $bcdBootPath"` plus comment citing `ADK 10.1.26100.2454` cert-variant caveat (D-13). |
| 10 | LTSC client builds normalize OEM driver release year: 2016/2019/2021→10, 2024→11 (CORRECT-02, D-14) | VERIFIED | `Get-EffectiveDriverWindowsRelease` (BuildFFUVM.ps1:1248): `if ($WindowsSKU -like '*LTS*') { if ($WindowsRelease -in 2016,2019,2021) { return 10 }; if ($WindowsRelease -eq 2024) { return 11 } }`. 12 pure-function table tests all pass. |
| 11 | 2019 collision disambiguated by `$isLTSC`; Server 2019 ('Standard'/'Datacenter' SKUs) never remapped (CORRECT-02, D-15) | VERIFIED | `*LTS*` gate: 'Standard' and 'Datacenter' SKUs never contain 'LTS', so they pass through unchanged. Server 2019 → 2019 test passes. |
| 12 | Normalization into dedicated `$driverWindowsRelease` at both driver-dispatch sites; global `$WindowsRelease` never clobbered (CORRECT-02, D-16) | VERIFIED | BuildFFUVM.ps1:3132 (driversJsonPath site) and 3308 (single-model site) both assign `$driverWindowsRelease = Get-EffectiveDriverWindowsRelease`. No bare reassignment of `$WindowsRelease` exists. |
| 13 | OEM provider calls (HP/Microsoft/Lenovo/Dell) receive `$driverWindowsRelease`; no Win2021/Win2024/Dell-W22 (CORRECT-02, D-17) | VERIFIED | BuildFFUVM.ps1:3317/3324/3331/3339: all four providers pass `-WindowsRelease $driverWindowsRelease`. Test asserts ≥4 occurrences of `driverWindowsRelease` in provider calls. |

**Score:** 13/13 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` | `function Get-WindowsImageSelection` + EditionId map + ADK bcdboot in Add-BootFiles | VERIFIED | Lines 490–722 (Get-ResolvedWindowsSKUFromImage + Get-WindowsImageSelection); Lines 2009–2042 (Add-BootFiles with -AdkPath/-WindowsArch + BCDBoot path + hard-fail throw). [CmdletBinding()] + [OutputType] on all three functions (WR-02 fixed). |
| `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1` | v1.4.0; exports Get-WindowsImageSelection + Get-ResolvedWindowsSKUFromImage; no Get-Index | VERIFIED | `ModuleVersion = '1.4.0'`; FunctionsToExport lists both new functions; 'Get-Index' absent. |
| `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` | Test-FFUADK CHECK 5 for BCDBoot\bcdboot.exe | VERIFIED | Lines 1114–1126: CHECK 5 with dedicated arch mapping (WR-03 fixed), Test-Path -PathType Leaf, $errors/$missingFiles accumulation. |
| `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1` | v1.7.0 with CORRECT-03 release notes | VERIFIED | `ModuleVersion = '1.7.0'`. |
| `FFUDevelopment/BuildFFUVM.ps1` | `function Get-WindowsTargetRuntimeState` + SKU propagation + `function Get-EffectiveDriverWindowsRelease` + `$driverWindowsRelease` + Add-BootFiles call updated | VERIFIED | Lines 1168–1241 (Get-WindowsTargetRuntimeState); 1248–1295 (Get-EffectiveDriverWindowsRelease); 3132/3308 ($driverWindowsRelease at both sites); 4618–4621 (Add-BootFiles -AdkPath -WindowsArch). |
| `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` | 68-test suite; exits 0 | VERIFIED | 68/68 tests passed; exit 0 confirmed. Uses Write-TestResult framework (not Pester). |
| `FFUDevelopment/version.json` | main=1.12.0; FFU.Imaging=1.4.0; FFU.Preflight=1.7.0 | VERIFIED | All three version fields confirmed. |
| `FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1` | `$version = '1.12.0'` | VERIFIED | Line 560: `$version = '1.12.0'`. |
| `CHANGELOG_FORK.md` | [1.12.0] section covering CORRECT-01..04 | VERIFIED | Section present at head of file with all four CORRECT-xx entries and upstream commit IDs. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `BuildFFUVM.ps1` (~4555) | `Get-WindowsImageSelection` | `$windowsImageSelection = Get-WindowsImageSelection -WindowsImagePath $wimPath -WindowsSKU $WindowsSKU -WindowsRelease $WindowsRelease` | WIRED | Line 4555–4557. No `-ISOPath` argument (removed). |
| `BuildFFUVM.ps1` (~4563) | `$WindowsSKU` reassignment | `$WindowsSKU = $windowsImageSelection.ResolvedWindowsSKU` | WIRED | Line 4564. Guarded by `IsNullOrWhiteSpace`. |
| `BuildFFUVM.ps1` (~4565) | `Get-WindowsTargetRuntimeState` | Recomputes runtime state post-SKU-reassignment | WIRED | Lines 4565–4573. All five state fields ($installationType/$WindowsVersion/$isLTSC/$isWindows10LtscClient/$installLatestCuInVm) updated. |
| `FFU.Imaging.psd1` | `Get-WindowsImageSelection` / `Get-ResolvedWindowsSKUFromImage` | FunctionsToExport | WIRED | Both listed; 'Get-Index' absent. |
| `BuildFFUVM.ps1` (~4618) | `Add-BootFiles -AdkPath $adkPath -WindowsArch $WindowsArch` | Extended call site | WIRED | Lines 4618–4621. Both new mandatory params supplied. |
| `Test-FFUADK` (FFU.Preflight.psm1:1114) | `BCDBoot\bcdboot.exe` | Test-Path -PathType Leaf with dedicated `$bcdbootArchPath` (WR-03 fixed) | WIRED | Lines 1121–1126. Arch computation: `if ($WindowsArch -ieq 'arm64') { 'arm64' } else { 'amd64' }` — matches Add-BootFiles. |
| `BuildFFUVM.ps1` (~3132/3308) | `Get-EffectiveDriverWindowsRelease` | `$driverWindowsRelease = Get-EffectiveDriverWindowsRelease -WindowsRelease $WindowsRelease -WindowsSKU $WindowsSKU` | WIRED | Lines 3132 (driversJsonPath site) and 3308 (single-model site). Both in outer scope before Invoke-BuildPhase. |
| `BuildFFUVM.ps1` OEM calls | `$driverWindowsRelease` | HP/Microsoft/Lenovo/Dell all pass `-WindowsRelease $driverWindowsRelease` | WIRED | Lines 3317/3324/3331/3339. |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Test-Phase51Correctness.ps1 exits 0 | `pwsh -NoProfile -File FFUDevelopment/Tests/Test-Phase51Correctness.ps1` | Exit 0; 68/68 PASS | PASS |
| FFU.Imaging.psd1 exports correct functions | Content-match on FunctionsToExport | Get-WindowsImageSelection + Get-ResolvedWindowsSKUFromImage present; Get-Index absent | PASS |
| version.json module versions correct | Content-match | FFU.Imaging=1.4.0, FFU.Preflight=1.7.0, main=1.12.0 | PASS |
| ApplyFFU.ps1 hardcoded version | Content-match | `$version = '1.12.0'` at line 560 | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CORRECT-01 | 51-01, 51-04 | Selected-edition propagation after fallback; Read-Host loop removed | SATISFIED | Truths 4, 5 VERIFIED; call site at BuildFFUVM.ps1:4555–4578. |
| CORRECT-02 | 51-03, 51-04 | LTSC year normalization for OEM drivers | SATISFIED | Truths 10, 11, 12, 13 VERIFIED; Get-EffectiveDriverWindowsRelease + $driverWindowsRelease at both dispatch sites. |
| CORRECT-03 | 51-02, 51-04 | ADK bcdboot for Secure Boot 2023 | SATISFIED | Truths 6, 7, 8, 9 VERIFIED; Add-BootFiles hard-fails on missing bcdboot; TEST-FFUADK CHECK 5 added; WR-02/WR-03 fixes confirmed. |
| CORRECT-04 | 51-01, 51-04 | EditionId/InstallationType locale-independent image selection | SATISFIED | Truths 1, 2, 3 VERIFIED; 24-entry switch map; Tier 1/2/3 selection logic; 68-test map-completeness gate. |

---

### Code Review Follow-up (from 51-REVIEW.md)

The REVIEW.md (2026-06-26) identified 3 warnings and 2 info items. All 3 warnings were fixed in a follow-up commit. Verified:

| Finding | Severity | Status | Verification Evidence |
|---------|----------|--------|-----------------------|
| WR-01: Silent `catch { $null }` in metadata enumeration | Warning | FIXED | FFU.Imaging.psm1:671–674: `WriteLog "WARNING: Failed to read metadata for image index $(...): $($_.Exception.Message). This index is excluded from EditionId matching."` |
| WR-02: `Add-BootFiles` lacks `[CmdletBinding()]`/`[OutputType()]` | Warning | FIXED | FFU.Imaging.psm1:2012–2013: `[CmdletBinding()]` and `[OutputType([void])]` now present. |
| WR-03: CHECK 5 in Test-FFUADK validates wrong bcdboot path for x86 (reused CHECK 4's `$archPath` which maps x86→arm64) | Warning | FIXED | FFU.Preflight.psm1:1118–1122: Dedicated `$bcdbootArchPath = if ($WindowsArch -ieq 'arm64') { 'arm64' } else { 'amd64' }` matches Add-BootFiles mapping exactly. |
| IN-01: Phantom `'CoreSingleLanguage'` key in SKU→EditionId forward switch (dead code — DISM EditionId token is not a valid `$WindowsSKU` input) | Info | OPEN | psm1:626 still present. Harmless dead code; no correctness impact. |
| IN-02: No explicit "Falling through to Tier 3" WriteLog before auto-select | Info | OPEN | psm1:710: Tier 3 executes silently after the editions-list log. Low observability but not a correctness gap. |

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| `BuildFFUVM.ps1` | `Read-Host` at lines 824/1368/1525/1815/3055 | Info | All in interactive UI/USB-selection paths, NOT in the build-execution/ThreadJob path. The deadlocking `Read-Host` in the former `Get-Index` fallback is confirmed absent. Not a blocker. |
| `FFU.Imaging.psm1:626` | Phantom `'CoreSingleLanguage'` switch key (IN-01) | Info | Dead code — no valid `$WindowsSKU` is an EditionId token. Harmless. |

No `TBD`, `FIXME`, or `XXX` markers found in any Phase 51 modified files.

---

### Human Verification Required

#### 1. Non-English / Multi-Edition ISO — Correct Edition Captured (CORRECT-04 live path)

**Test:** Provide a non-English or multi-edition Windows ISO (French, Spanish, or media with both Pro and Home). Run a build targeting 'Pro'. Check the build log and the resulting FFU.
**Expected:** Build completes. WriteLog shows `Selected image index N (SKU='Pro', EditionId='Professional')` — no Tier 3 auto-select. FFU is a Pro image, not an incorrect edition.
**Why human:** Real DISM media required; cannot mock `Get-WindowsImage` with live locale variation in automated content-match tests.

#### 2. Single-Edition ISO Fallback Naming (CORRECT-01 Tier 3 single-candidate path)

**Test:** Provide an ISO containing only one edition (e.g. Windows 10 LTSC 2021 media with only 'Enterprise LTSC'). Request a build for that SKU. Verify naming and cache.
**Expected:** Build succeeds. FFU named as 'Enterprise LTSC'. `$WindowsSKU` propagates to naming/cache/checkpoint sites. WriteLog shows resolved SKU.
**Why human:** Single-edition ISO salvage (Tier 3 auto-select) requires actual WIM media.

#### 3. Mismatched-SKU ISO Salvage (CORRECT-01 Tier 3 auto-select + ResolvedWindowsSKU propagation)

**Test:** Provide an ISO where the exact requested SKU is absent but one relevant candidate exists (e.g. request 'Enterprise', ISO has only 'Enterprise N'). Confirm auto-select and name propagation.
**Expected:** Tier 3 fires. `$WindowsSKU` is reassigned to 'Enterprise N'. FFU is named 'Enterprise N'. WriteLog shows `Resolved WindowsSKU from 'Enterprise' to 'Enterprise N'`.
**Why human:** Fallback edition propagation requires live WIM media with the edition-mismatch scenario.

#### 4. Secure Boot 2023 Hardware Boot Test (CORRECT-03 hardware validation)

**Test:** On a machine with Windows ADK (Dec 2024 build `10.1.26100.2454` or earlier) installed, build an FFU for a target device with a Secure Boot 2023 certificate (Pluton or post-2023 OEM). Deploy and boot.
**Expected:** Device boots successfully. Build log shows `Adding boot files using ADK bcdboot: <ADKPath>\...\amd64\BCDBoot\bcdboot.exe`. No Secure Boot violation.
**Why human:** Requires physical Secure Boot 2023-cert hardware; cert-variant differences cannot be simulated.

#### 5. LTSC Build — OEM Driver Download End-to-End (CORRECT-02 live path)

**Test:** Run a full build targeting 'Enterprise LTSC 2021' or 'Enterprise LTSC 2024' with HP, Lenovo, or Dell driver download enabled and live internet access.
**Expected:** OEM driver download completes. WriteLog shows `Normalized WindowsRelease for single-model driver processing from 2021 to 10` (or 2024 to 11). No `Win2021`/`Win2024` validation error from OEM provider.
**Why human:** Requires live OEM driver catalog connectivity and an actual LTSC build run.

---

### Gaps Summary

No automated gaps found. All 13 must-have truths verified. All three REVIEW.md warnings (WR-01/02/03) were fixed. The 5 human-verification items above are inherent to the phase goal (real hardware, real media, live network) and are correctly classified as human-UAT per the phase boundary defined in 51-CONTEXT.md.

Status is `human_needed` — automated checks all pass; the human-UAT queue above must clear before the phase can be considered fully validated end-to-end.

---

_Verified: 2026-06-26T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
