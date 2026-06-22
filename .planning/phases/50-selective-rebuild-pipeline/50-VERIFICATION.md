---
phase: 50-selective-rebuild-pipeline
verified: 2026-06-22T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Launch BuildFFUVM_UI.ps1 in USB Mode and inspect all 7 artifact cards"
    expected: "FFU card shows single disabled Reuse ComboBox + italic helper text 'To rebuild the OS image, switch to Full Build'; WinPE Deploy ISO shows enabled 2-item Reuse/Rebuild ComboBox (no Skip); Drivers and Applications ISO show 3-item Reuse/Rebuild/Skip; PPKG/Unattend.xml/Autopilot Profile show 2-item Reuse/Skip"
    why_human: "ComboBox tier enforcement and XAML rendering require a live WPF runtime; Pester tests are source-text assertions only and cannot validate rendered UI state"
  - test: "Save config with Drivers=Rebuild, restart UI, reload config and check ComboBox state"
    expected: "WinPE Deploy ISO and Drivers ComboBoxes restore their saved Disposition values (Rebuild); other artifacts restore their selections; no Include field in saved config JSON"
    why_human: "Config round-trip persistence across sessions requires a live WPF runtime with file I/O; functional test cannot be run in the Pester environment"
  - test: "Simulate a degraded artifact (zero-byte FFU or Drivers folder with suspect content) and run the USB Mode scanner"
    expected: "Affected card shows 'Found (degraded)' in DarkOrange, the warning TextBlock below the card becomes visible with scanner error/warning text, ComboBox remains enabled (not disabled)"
    why_human: "4-status rendering and warning TextBlock visibility toggling require the live WPF dispatcher and a scanner that returns ArtifactStatus::Degraded; cannot be reproduced in headless Pester"
  - test: "(Real env, if available) Mark Drivers=Rebuild + FFU=Reuse, click Create USB, and monitor the build log"
    expected: "Only the driver download phase runs before USB assembly; the Monitor tab log shows 'Rebuilding Drivers' message followed directly by USB copy operations; the final USB drive contains the freshly downloaded drivers alongside the reused FFU; no VM/VHDX/OS build phases fire"
    why_human: "End-to-end selective rebuild execution requires an ADK installation, a valid driversJsonPath, and a physical or virtual USB drive; not available in the sandbox CI environment"
---

# Phase 50: Selective Rebuild Pipeline Verification Report

**Phase Goal:** Users can mark each artifact as reuse, rebuild, or skip, and the pipeline executes only the build phases needed for marked-rebuild artifacts, then combines rebuilt + reused artifacts into the final USB.
**Verified:** 2026-06-22
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | USB Mode artifact display shows a per-artifact disposition control (reuse / rebuild / skip) | VERIFIED | BuildFFUVM_UI.xaml contains 7 ComboBoxes named usb{Type}Disposition; FFU=1-item disabled Reuse; DeployISO=2-item enabled Reuse/Rebuild; Drivers/AppsISO=3-item Reuse/Rebuild/Skip; PPKG/Unattend/Autopilot=2-item Reuse/Skip; no usb{Type}Include CheckBoxes remain |
| 2 | Marking an artifact as rebuild causes only the corresponding build phase(s) to run before USB assembly | VERIFIED | BuildFFUVM.ps1 contains $rebuildDrivers/$rebuildAppsISO/$rebuildDeployISO gates set exclusively from Disposition=='Rebuild' (not from $script:IsResuming); selective execution block at index 95354 precedes dispositionCheckTypes gate at index 97992 (BLOCKER-1 verified); Pester ordering assertion passes |
| 3 | Artifacts marked reuse are taken from their current paths with no build phase execution | VERIFIED | Disposition gate switch default case (line 2147) is empty for 'Reuse' — copy flags already set from scanner/manifest, no build invocation; only 'Rebuild' triggers New-AppsISO / New-PEMedia / Invoke-ParallelProcessing |
| 4 | Artifacts marked skip are excluded from USB assembly | VERIFIED | dispositionCheckTypes foreach+switch 'Skip' case (lines 2132-2141) sets $CopyDrivers/$CopyAppsISO/$CopyPPKG/$CopyUnattend/$CopyAutopilot to $false; FFU and DeployISO are excluded from the Skip branch with an explicit comment (D-03/D-10); no PSObject.Properties.Match('Include') references remain |
| 5 | Rebuilt artifacts are combined with reused artifacts and assembled into the final USB drive | VERIFIED | After each rebuild block: AppsISO sets $AppsISOPath=$AppsISO + $CopyAppsISO=$true; Drivers sets $CopyDrivers=$true; DeployISO path reconciled before mount pre-check; New-DeploymentUSB parallel block copies all flags via $using:CopyAppsISO/$using:AppsISOPath |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `FFUDevelopment/BuildFFUVM_UI.xaml` | 7 disposition ComboBoxes + 7 warning TextBlocks + FFU helper text | VERIFIED | All 7 usb{Type}Disposition ComboBoxes present; all 7 usb{Type}Warning TextBlocks with Foreground=DarkOrange/Visibility=Collapsed; FFU helper text "To rebuild the OS image, switch to Full Build" at XAML line 970 |
| `FFUDevelopment/BuildFFUVM_UI.ps1` | usbArtifactState init with disposition='Reuse' on all 7 entries | VERIFIED | Lines 73-79 show all 7 entries with `disposition = 'Reuse'` property |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` | $artifactMap with dispCtrl/tier/warnCtrl; 4-status switch; 7 SelectionChanged handlers | VERIFIED | $artifactMap at lines 26-61 has dispCtrl/tier/warnCtrl for all 7 artifacts; DeployISO tier='required-buildable'; switch($result.Status.ToString()) with Found/Degraded/Error/default(Missing) cases; DarkOrange foreground for Degraded; 7 Add_SelectionChanged registrations confirmed |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` | Build-UIConfiguration writes Disposition from ComboBox Tag; Update-UIFromConfig restores by Tag match under isLoadingConfig | VERIFIED | SelectedItem.Tag read for Disposition (lines 181-183); no Include=... write; Update-UIFromConfig restores via Tag -eq targetDisp loop (lines 665-674); isLoadingConfig guard wraps the restore |
| `FFUDevelopment/BuildFFUVM.ps1` | AppsISO copy path (F1); Disposition gate (F2); mini path-init + rebuild flags + selective execution (F3); F6 config sourcing | VERIFIED | $CopyAppsISO/$AppsISOPath declared and populated from manifest; $using:CopyAppsISO/$using:AppsISOPath in parallel block with robocopy+Test-RobocopySuccess; dispositionCheckTypes foreach+switch; no PSObject.Properties.Match('Include') references; mini path-init at lines 1802-1814; rebuild flags at 1822-1843; driversJsonPath/Make/Model sourced from $configData at 1851-1869 |
| `Tests/Unit/SelectiveRebuild.Tests.ps1` | Wave-0 test scaffold + ArtifactStatus enum + Disposition round-trip assertions | VERIFIED | File exists at Tests/Unit/SelectiveRebuild.Tests.ps1; InModuleScope FFU.ArtifactScanner assertions for Degraded/Error; Build-UIConfiguration round-trip assertions; 30 tests, 30 passed |
| `Tests/Unit/USBOnlyMode.Tests.ps1` | F1/F2/F3 structural assertions + BLOCKER-1 ordering assertion | VERIFIED | F1 AppsISO Context, F2 Disposition Gate Context, F3 Selective Rebuild Flags Context all present; BLOCKER-1 ordering assertion (IndexOf rebuildDrivers < IndexOf dispositionCheckTypes) present and passing |
| `FFUDevelopment/version.json` | MINOR bump to 1.11.0; buildDate 2026-06-22; FFUUI.Core module version 0.0.21 | VERIFIED | version=1.11.0, buildDate=2026-06-22, modules.FFUUI.Core.version=0.0.21 |
| `FFUDevelopment/FFUUI.Core/FFUUI.Core.psd1` | ModuleVersion=0.0.21 with Phase 50 ReleaseNotes | VERIFIED | ModuleVersion='0.0.21'; ReleaseNotes contains Phase 50 Selective Rebuild entry |
| `CHANGELOG_FORK.md` | v1.11.0 entry documenting Selective Rebuild Pipeline (REBUILD-01/02/03) | VERIFIED | [1.11.0] - 2026-06-22 entry present with "Selective Rebuild" and REBUILD-01/02/03 references |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| BuildFFUVM_UI.xaml usbDriversDisposition ComboBox | FFUUI.Core.Handlers $artifactMap dispCtrl | x:Name matches dispCtrl value | VERIFIED | All 7 XAML ComboBox x:Name values match corresponding $artifactMap dispCtrl strings |
| FFUUI.Core.Handlers SelectionChanged handler | usbArtifactState[Type].disposition | Window.Tag retrieval + isLoadingConfig guard | VERIFIED | 7 Add_SelectionChanged registrations found; isLoadingConfig guard present in each; writes to usbArtifactState[Type].disposition |
| Build-UIConfiguration | config.USBMode.Artifacts[Type].Disposition | SelectedItem.Tag read | VERIFIED | dispCtrlName = "usb${artifactType}Disposition"; Tag read; Disposition key written; no Include key written |
| Update-UIFromConfig | usb{Type}Disposition.SelectedItem | ComboBoxItem.Tag match within isLoadingConfig window | VERIFIED | PSObject.Properties.Match('Disposition') existence check; foreach loop matching .Tag -eq targetDisp; within isLoadingConfig=$true |
| config Disposition=='Rebuild' | $rebuildDrivers/$rebuildAppsISO/$rebuildDeployISO gates | PSObject.Properties.Match('Disposition') check, not $script:IsResuming | VERIFIED | Each flag set via cfgArtEarly.{Type}.PSObject.Properties.Match('Disposition').Count -gt 0 and .Disposition -eq 'Rebuild'; no IsResuming dependency |
| $rebuildAppsISO block | New-AppsISO | isolated phase call after mini-init | VERIFIED | New-AppsISO called with adkPath/AppsPath/AppsISO; reconciles $AppsISOPath=$AppsISO and $CopyAppsISO=$true |
| $rebuildDeployISO block | New-PEMedia | isolated phase call before ISO mount pre-check | VERIFIED | New-PEMedia called with full param set; appears at file index 95418 vs mount pre-check at 104668 (Pitfall 6 respected) |
| USBOnlyMode block | New-DeploymentUSB parallel copy | script-scope $CopyAppsISO/$AppsISOPath captured by $using: | VERIFIED | $using:CopyAppsISO and $using:AppsISOPath present in ForEach-Object -Parallel block; Test-RobocopySuccess for AppsISO |
| FFUUI.Core.psd1 ModuleVersion | version.json modules.FFUUI.Core.version | matching version strings | VERIFIED | Both are '0.0.21' |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| BuildFFUVM.ps1 disposition gate | $disp | $dEntry.Disposition from config JSON / PSObject.Properties.Match check | Yes — reads from persisted config file populated by Build-UIConfiguration from ComboBox Tag | FLOWING |
| BuildFFUVM.ps1 rebuild flags | $rebuildDrivers/$rebuildAppsISO/$rebuildDeployISO | $cfgArtEarly.{Type}.Disposition -eq 'Rebuild' | Yes — driven from config file Disposition value | FLOWING |
| New-DeploymentUSB parallel block | $using:CopyAppsISO/$using:AppsISOPath | script-scope variables populated from manifest.AppsISO.Status + config override + rebuild reconciliation | Yes — real artifact path from scanner or rebuild output | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Targeted Phase-50 Pester suite (SelectiveRebuild, USBOnlyMode, FFUUI.Core.Handlers, FFUUI.Core.ConfigValidation) | `Invoke-Pester -Path ... -PassThru` | 154 passed / 0 failed / 0 skipped | PASS |
| FFU.ArtifactScanner tests | `Invoke-Pester -Path Tests/Unit/FFU.ArtifactScanner.Tests.ps1 -PassThru` | 121 passed / 0 failed / 0 skipped | PASS |
| BLOCKER-1 rebuild-before-gate ordering | `$content.IndexOf('$rebuildDrivers') -lt $content.IndexOf('$dispositionCheckTypes')` | 95354 < 97992 = True | PASS |
| DeployISO rebuild before ISO mount pre-check ordering | `$content.IndexOf('$rebuildDeployISO') -lt $content.IndexOf('Step 4: ISO mountability')` | 95418 < 104668 = True | PASS |
| version.json / psd1 version sync | `$v.modules.'FFUUI.Core'.version -eq $psd.ModuleVersion` | Both '0.0.21' = True | PASS |
| FFU never rebuildable (no rebuildFFU flag) | Grep `\$rebuildFFU` in BuildFFUVM.ps1 | No matches | PASS |
| No PSObject.Properties.Match('Include') in BuildFFUVM.ps1 | Grep for Include-flag gate | No matches | PASS |

### Probe Execution

No probe scripts declared for Phase 50. Step 7c: SKIPPED (no probe-*.sh files for this phase).

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| REBUILD-01 | 50-01, 50-02, 50-03, 50-06 | User can mark each artifact as reuse, rebuild, or skip | SATISFIED | 7 disposition ComboBoxes in XAML; dispCtrl/$artifactMap in Handlers; Build-UIConfiguration writes Disposition from Tag; Update-UIFromConfig restores by Tag; no Include field in USB save/restore path |
| REBUILD-02 | 50-01, 50-04, 50-05, 50-06 | Pipeline executes only the build phases needed for rebuild artifacts | SATISFIED | $rebuildDrivers/$rebuildAppsISO/$rebuildDeployISO flags driven by Disposition=='Rebuild' only; selective execution block runs Invoke-ParallelProcessing / New-AppsISO / New-PEMedia in isolation; block precedes dispositionCheckTypes gate (BLOCKER-1 verified) |
| REBUILD-03 | 50-01, 50-04, 50-05, 50-06 | Rebuilt artifacts combined with reused artifacts for final USB assembly | SATISFIED | After rebuild: $CopyAppsISO/$AppsISOPath reconciled; $CopyDrivers=$true + $DriversFolder preserved; DeployISO path reconciled before mount pre-check; New-DeploymentUSB receives all flags and copies rebuilt+reused artifacts together; $using:CopyAppsISO/$using:AppsISOPath wired to parallel block |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found in Phase 50 files | — | No TBD/FIXME/XXX markers; no stub returns; no empty handlers | — | Clean |

The SUMMARY notes 207 pre-existing PSScriptAnalyzer warnings in the changed files; all confirmed as pre-existing patterns via git history (PSReviewUnusedParameter on WPF event handler params is endemic to the project; PSAvoidUsingWriteHost for UI thread; $foreach/$error built-in variable name collisions). Zero new issues introduced by Phase 50.

### Human Verification Required

The following items cannot be verified programmatically and require a live WPF runtime and/or real build environment:

#### 1. Disposition ComboBox Tier Rendering

**Test:** Launch `.\BuildFFUVM_UI.ps1`, switch to USB from Existing mode, and inspect all 7 artifact cards.
**Expected:** FFU card shows a single disabled "Reuse" ComboBox (greyed out) with italic helper text "To rebuild the OS image, switch to Full Build"; WinPE Deploy ISO card shows an enabled 2-item ComboBox with "Reuse" and "Rebuild" only (no Skip item); Drivers and Applications ISO cards show a 3-item Reuse/Rebuild/Skip ComboBox; Provisioning Package, Unattend.xml, and Autopilot Profile cards show a 2-item Reuse/Skip ComboBox.
**Why human:** ComboBox tier enforcement and XAML rendering require a live WPF runtime; Pester tests use source-text assertions and cannot validate the rendered UI state or that disabled items are actually disabled.

#### 2. Disposition Config Persistence Round-Trip

**Test:** In USB Mode, set Drivers=Rebuild and DeployISO=Rebuild, save config (File > Save Config or equivalent), restart the UI, reload the same config.
**Expected:** Both Drivers and DeployISO ComboBoxes restore to "Rebuild" on reload; the saved config JSON contains `"Disposition": "Rebuild"` for those artifact entries and no `"Include"` key for any artifact.
**Why human:** Config file I/O round-trip across UI sessions requires a live WPF runtime; the functional Build-UIConfiguration Pester test uses a PSCustomObject mock but cannot validate the full WPF dispatcher path.

#### 3. Degraded Artifact 4-Status Rendering

**Test:** Create a zero-byte file at the expected FFU or Drivers scan path, then click Scan (or launch USB Mode), which triggers Invoke-USBArtifactScan.
**Expected:** The affected card renders "Found (degraded)" in DarkOrange text; the warning TextBlock below the card label becomes visible showing scanner error/warning text; the ComboBox remains enabled (not disabled as for Missing/Error).
**Why human:** The 4-status rendering path and warning TextBlock visibility toggling require the live WPF dispatcher and a scanner that returns ArtifactStatus::Degraded; cannot be replicated in a headless Pester run.

#### 4. End-to-End Selective Rebuild Execution (Real Environment)

**Test:** (Requires ADK + valid driversJsonPath in config + physical/virtual USB) Set Drivers=Rebuild and FFU=Reuse, click "Create USB", and watch the Monitor tab.
**Expected:** Only the driver download phase fires (Monitor log shows "USBOnlyMode: Rebuilding Drivers..."); no VM/VHDX/OS/Windows-ISO machinery starts; the final USB drive contains freshly downloaded drivers alongside the reused FFU; USB assembly completes successfully.
**Why human:** Requires an ADK installation, a valid driversJsonPath+Make+Model config, and a USB drive; not available in the sandbox CI environment. This is the D-12 selective-execution capability validated end-to-end.

### Gaps Summary

No gaps found. All 5 ROADMAP success criteria are VERIFIED in the codebase. All 3 requirement IDs (REBUILD-01/02/03) are satisfied. The 154 targeted Phase-50 Pester tests pass (0 failures). Versioning and changelog are complete.

The phase status is **human_needed** because plan 50-06 Task 3 is a `checkpoint:human-verify gate="blocking"` that requires manual UI launch and end-to-end confirmation. The SUMMARY records "auto-approved" but the plan's resume signal was never satisfied by a human typing "approved" after physical UI inspection. Four human verification items remain outstanding: ComboBox tier rendering, config round-trip, degraded artifact rendering, and (optionally) end-to-end selective rebuild in a real environment.

---

_Verified: 2026-06-22_
_Verifier: Claude (gsd-verifier)_
