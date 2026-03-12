# Pitfalls Research

**Domain:** Adding USB-from-existing-components mode to an existing WPF/PowerShell deployment tool
**Researched:** 2026-03-12
**Confidence:** HIGH — derived from direct codebase inspection of 90,000+ lines across 13 modules, UI layer, and documented history of prior bugs

---

## Critical Pitfalls

### Pitfall 1: Mode State Not Propagated to isBuilding/Cancel Flow

**What goes wrong:**
The `btnRun` click handler has a dual-role: it starts a build AND acts as a cancel button. The cancel path checks `$script:uiState.Flags.isBuilding`. If USB Mode launches a ThreadJob but doesn't set `isBuilding = $true` through the same code path, the Cancel button will not cancel the USB job — it will attempt to start a second build instead. On completion, the job result handler may also reset `btnRun.Content = "Build FFU"` instead of "Create USB", leaving the button label wrong after the operation finishes.

**Why it happens:**
Developers adding a new mode often wire a new button or reuse `btnRun` with conditional logic, but they copy the "start" path without making the entire cancel/cleanup/reset/timer lifecycle mode-aware. The existing state recovery path in `Reset-FFUUIToIdle` and `FFUUI.Core.StateRecovery.psm1` hardcodes the string `"Build FFU"` as the idle button label.

**How to avoid:**
- Introduce a `currentMode` flag in `$script:uiState.Flags` (`'FullBuild'` or `'USBMode'`) set before marking `isBuilding = $true`.
- Make `Reset-FFUUIToIdle` and any code that sets `btnRun.Content` read from `currentMode` to determine the correct idle label (`"Build FFU"` vs `"Create USB"`).
- Audit every location where `btnRun.Content = "Build FFU"` is hardcoded (BuildFFUVM_UI.ps1 lines 332, 413, 827 and StateRecovery.psm1 line 35) before shipping.

**Warning signs:**
- Cancel button does nothing or launches a second job when clicked in USB Mode.
- Button label shows "Build FFU" after a USB-only operation completes.
- Two concurrent `$script:uiState.Data.currentBuildJob` references exist simultaneously.

**Phase to address:**
Phase that introduces the mode toggle UI and wires `btnRun` to the USB path — must be the first phase that touches button click handling.

---

### Pitfall 2: Artifact Scanner Runs File I/O on the WPF Dispatcher Thread

**What goes wrong:**
Scanning for FFU files, ISOs, driver folders, and PPKG packages involves `Get-ChildItem`, `Get-Item`, and potentially DISM metadata queries across large directories. If this runs on the WPF STA thread (inside a button click handler or `Window.Loaded`), the UI freezes until scanning finishes — which can take 10-30 seconds on a machine with large driver sets or slow storage.

**Why it happens:**
The existing UI codebase reads small JSON files and populates dropdowns synchronously during `Initialize-UIControls` and `Initialize-UIDefaults`. Developers familiar with that pattern apply it to artifact scanning without recognizing the difference in I/O cost.

**How to avoid:**
- Run artifact scanning in a `Start-ThreadJob` or `[System.Threading.Tasks.Task]` and update the UI by dispatching back to the STA thread via `$window.Dispatcher.Invoke()`.
- Show a progress indicator (spinner or indeterminate progress bar) during scan.
- Do not use `Get-Command` inside the background work — use `$function:FuncName` or try/catch around actual calls per the documented ThreadJob compatibility table.

**Warning signs:**
- UI freezes for several seconds when the user switches to USB Mode or clicks "Scan".
- WPF "not responding" in Task Manager during scan.
- Any synchronous file system enumeration inside a `$window.Add_Loaded` or button click handler.

**Phase to address:**
The artifact scanner implementation phase — must include a dispatcher-based callback pattern from day one, not retrofitted later.

---

### Pitfall 3: Selective Pipeline Execution Bypasses Preflight Checks That Guard It

**What goes wrong:**
`Invoke-FFUPreflight` (FFU.Preflight module) runs tiered checks: ADK availability, disk space estimation with component breakdown, Hyper-V/VMware validation, WIMMount service state. When selective rebuild skips phases (e.g., "reuse FFU, only rebuild Deploy ISO"), developers may skip the entire preflight call — but some preflight checks are necessary even for USB-only paths (disk space for ISO extraction, ADK path for WinPE creation). Skipping them causes cryptic failures mid-operation instead of clear upfront errors.

**Why it happens:**
Preflight is associated mentally with "full build" because it validates VM requirements. Developers building the "skip most phases" code path omit preflight entirely to avoid the Hyper-V/VMware checks that are irrelevant to USB assembly.

**How to avoid:**
- Restructure preflight into explicitly labeled tier sets so USB Mode can call only the relevant tiers (e.g., Tier 1 admin/PS7 check + disk space check + ADK check, but not Tier 2 VM switch check).
- Expose a `-SkipTiers` or `-RequiredTiers` parameter on `Invoke-FFUPreflight` so USB Mode passes only the checks it needs.
- Document which preflight checks are required for USB-only operation before implementation begins.

**Warning signs:**
- USB Mode proceeds past a missing ADK installation and fails during `New-PEMedia`.
- Disk space failures occur mid-operation rather than at startup.
- WIMMount service is not checked before any ISO or image mounting step that USB Mode performs.

**Phase to address:**
The selective pipeline execution design phase — the preflight tiering refactor must precede any phase that actually runs selective builds.

---

### Pitfall 4: Cross-Architecture FFU/ISO Compatibility Silently Mismatches

**What goes wrong:**
The artifact scanner finds an x86 FFU and an ARM64 Deploy ISO. The user marks both as "reuse." The USB assembly copies them to the same drive without rejecting the combination. At deployment time, WinPE boots (correct architecture for the hardware) but the FFU fails to apply because it was built for a different architecture. The failure message from `ApplyFFU.ps1` at that point is cryptic.

**Why it happens:**
Architecture metadata is embedded in FFU files (accessible via `Get-WindowsImage -ImagePath`) and in ISO/WIM boot records, but the scan-and-validate step is complex enough that developers defer it to "phase 2." The path of least resistance is to display architecture info in the UI without enforcing cross-artifact compatibility.

**How to avoid:**
- During artifact scan, extract and store architecture from each artifact (FFU via `Get-WindowsImage`, ISO via examining `\sources\boot.wim` or `\efi\boot` directory structure).
- Before USB assembly begins, validate that all reused artifacts share the same architecture. Block assembly if they don't — show a clear dialog naming the conflicting artifacts.
- Store architecture as a required field in the artifact metadata object, not an optional display-only field.

**Warning signs:**
- Architecture column in the artifact list UI is empty or shows "Unknown" for any artifact.
- No validation gating step between "user confirms selections" and "USB assembly starts."
- `Get-WindowsImage` is not called during scan (it can be slow but is the authoritative source).

**Phase to address:**
The metadata extraction and cross-validation phase — must be complete before the USB assembly phase begins.

---

### Pitfall 5: ThreadJob Context Breaks Get-WindowsImage / DISM Cmdlets During Artifact Scan

**What goes wrong:**
The documented ThreadJob compatibility issue (cmdlets in `Microsoft.PowerShell.Core` and `Microsoft.PowerShell.Utility` becoming temporarily unavailable during heavy operations) also affects DISM-related cmdlets like `Get-WindowsImage`. If artifact scanning runs in a ThreadJob alongside other active operations, DISM metadata extraction intermittently fails with `The term 'Get-WindowsImage' is not recognized` rather than a file-not-found error, making the scan appear to succeed with empty results.

**Why it happens:**
`Get-WindowsImage` belongs to the DISM module, not a built-in module. The DISM module requires the `dism.exe` binary and WIMMount filter driver to be active. In a ThreadJob context, if the DISM module is not explicitly imported inside the job scriptblock, it may not be available. The WIMMount service dependency (documented bug causing 0x800704DB errors, fixed in v1.3.5-v1.3.9) can surface here too.

**How to avoid:**
- Explicitly call `Import-Module DISM` inside any ThreadJob scriptblock that calls `Get-WindowsImage`.
- Wrap all `Get-WindowsImage` calls with try/catch and return a structured "scan failed" result rather than silently returning $null.
- Validate WIMMount filter service is active before any scan operation that uses DISM image inspection (`fltmc filters` check, same as v1.3.12 WimMount auto-repair pattern).
- Use `$env:PSModulePath` setup inside the ThreadJob (follow the documented pattern from `BuildFFUVM.ps1` lines 748-759).

**Warning signs:**
- Artifact scan returns empty metadata for valid FFU or WIM files.
- `Get-WindowsImage` calls succeed in interactive testing but fail when triggered from the UI.
- No `Import-Module DISM` visible inside the scan ThreadJob scriptblock.

**Phase to address:**
The artifact scanner implementation phase — the DISM import and WIMMount pre-check must be in the scanner from the first iteration.

---

### Pitfall 6: Config Schema Not Extended for USB Mode Artifact Paths

**What goes wrong:**
USB Mode introduces new configuration concepts: paths to pre-existing FFU, Deploy ISO, driver folder, PPKG, unattend, Autopilot, and Apps.iso artifacts, plus per-artifact disposition flags (`reuse`/`rebuild`/`skip`). If these are not added to the JSON config schema and covered by `FFU.ConfigMigration`, loading a USB Mode config in a future release (or loading it in Full Build mode) silently ignores the new fields. More dangerously, `Get-UIConfig` in `FFUUI.Core.Config.psm1` will not serialize them when the user saves, losing their artifact selections.

**Why it happens:**
Developers treat USB Mode state as transient UI state (not persisted) to avoid schema work. This is fine for a prototype but becomes a problem when users want to re-run USB Mode with the same artifact set without manually re-browsing.

**How to avoid:**
- Define USB Mode fields in the config schema with a version bump (`configSchemaVersion` from `1.2` to `1.3` or similar) before writing any UI code that reads them.
- Add migration rule in `FFU.ConfigMigration` that sets default values for the new fields when loading a pre-v1.11.0 config.
- Add the new fields to `Get-UIConfig` and `Set-UIConfig` in the same phase they are defined.
- Write a Pester test that loads a v1.10.0 config and confirms migration adds the expected defaults.

**Warning signs:**
- Artifact paths are stored only in `$script:uiState` but not written to `$config` in `Get-UIConfig`.
- No `configSchemaVersion` bump in the PR that adds USB Mode config fields.
- No migration test for the new schema version.

**Phase to address:**
The configuration schema extension phase — must be the first completed phase before any UI wiring that reads artifact state from config.

---

### Pitfall 7: Param Block Coupling Repeated for USB Mode Parameters

**What goes wrong:**
`BuildFFUVM.ps1` already documents (lines 7-18) that param block defaults must be hardcoded values matching `FFU.Constants` because `using module` fails in ThreadJob contexts with different working directories. If USB Mode adds new parameters with defaults derived from constants (e.g., a minimum artifact age threshold or a default scan path), the developer may use `[FFUConstants]::CONSTANT` in the default expression. This causes a parse-time failure when the script is launched as a ThreadJob from the UI.

**Why it happens:**
The existing workaround is documented but easy to overlook when adding parameters. The error message ("The type [FFUConstants] could not be found") appears at job launch, not at test time, because interactive testing typically runs the script directly rather than through `Start-ThreadJob`.

**How to avoid:**
- Hardcode any new parameter defaults numerically or as string literals, matching their corresponding `FFU.Constants` values.
- Add an inline comment at each new parameter default pointing to the corresponding constant, following the existing pattern at lines 7-18.
- Add a test in `Tests/Unit` that launches `BuildFFUVM.ps1` with USB Mode parameters via `Start-ThreadJob` to catch parse failures early.

**Warning signs:**
- New parameter defaults reference `[FFUConstants]::` anywhere in the param block.
- Build job silently fails immediately after launch with no log output created.
- The error only reproduces when launched via the UI, not when run interactively.

**Phase to address:**
Any phase that adds parameters to `BuildFFUVM.ps1` for USB Mode control — enforce the hardcoded-default rule as a checklist item in that phase's plan.

---

### Pitfall 8: WPF Tab Addition Breaks Existing XAML Validation at Load Time

**What goes wrong:**
The XAML file (`BuildFFUVM_UI.xaml`) is 1,004 lines and growing. Adding a new "USB Mode" tab or panel requires editing XAML. A malformed attribute (e.g., missing closing quote, unknown property name, wrong namespace) causes `[Windows.Markup.XamlReader]::Load()` to throw at startup, making the entire application fail to launch. Because the load error is a parse exception from .NET, the error message often points to a line number in the raw XAML that doesn't directly correlate to the editing mistake.

**Why it happens:**
XAML is XML-based but WPF adds a type system on top. Property names are validated against the WPF type system at parse time. Developers familiar with XML editing miss that `<TabItem Header="USB Mode">` is valid XML but a wrong property on a control (e.g., `IsChecked` on a `Button`) will fail silently or at load time depending on WPF version.

**How to avoid:**
- Use Visual Studio or VS Code with the XAML Language Server extension to validate XAML before committing — these tools surface type errors at edit time.
- Add a Pester test that calls `[Windows.Markup.XamlReader]::Load()` on the XAML file and asserts no exception — this is the cheapest possible regression guard.
- Make XAML changes in isolated commits so a bisect is fast if load fails.
- Name all new controls with `x:Name` attributes immediately — unbound controls in `Initialize-UIControls` fail with `FindName` returning null, causing NullReferenceExceptions at runtime rather than load time.

**Warning signs:**
- `[Windows.Markup.XamlReader]::Load()` throws at application startup after any XAML edit.
- `$window.FindName('newControlName')` returns `$null` in `Initialize-UIControls`.
- No Pester test covers XAML parse validity.

**Phase to address:**
The mode toggle UI implementation phase — add the XAML parse test at the start of this phase before any UI controls are added.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Store artifact state only in `$script:uiState` (not config) | Avoids schema versioning work | Users must re-browse paths every session; config round-trips lose USB Mode data | Never for shipped feature |
| Use `Get-ChildItem -Recurse` synchronously on STA thread for artifact scan | Simple one-liner | UI freeze 5-30 seconds; user perception of broken app | Never — always background |
| Skip architecture cross-validation to ship faster | Faster to implement | Silent deployment failures in the field that are hard to diagnose | Never — validate at assembly time |
| Hardcode `"Build FFU"` as idle button label in reset functions | Simple | Button label wrong after USB Mode completes | Never — use mode flag |
| One monolithic USB ThreadJob that does scan + rebuild + assembly | Easier job lifecycle management | Cannot cancel mid-scan, cannot retry single phase, messaging granularity lost | MVP only if cancel is explicitly deferred |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `Invoke-FFUPreflight` | Call it in full or skip it entirely for USB Mode | Parameterize tier selection; USB Mode calls admin + disk + ADK tiers only |
| `New-DeploymentUSB` (existing USB phase) | Assume it handles all USB prep in USB Mode | It expects `$DeployISO` to already exist; USB Mode must ensure ISO is ready before calling it |
| `FFU.Messaging` queue | Create a new context for each job | Close and null the old context before creating a new one; leaking contexts fills the queue and degrades performance |
| `WriteLog` in scan background job | Call it directly | Log path must be set via `Set-CommonCoreLogPath` inside the ThreadJob before any `WriteLog` call |
| `Invoke-BuildPhase` wrapper | Use it only in Full Build path | USB Mode selective rebuilds should also use `Invoke-BuildPhase` for consistent cancellation and error aggregation |
| Config save (`Get-UIConfig`) | Add USB artifact paths as a separate "USB config" object | Integrate into existing config structure with schema version bump; two separate config files creates a sync problem |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `Get-WindowsImage` on every FFU during scan | Scan takes 30-60s for a folder with multiple FFUs | Cache results in scan; show progress per-file | Any folder with more than 2 FFU files |
| Enumerating driver folder recursively for metadata | 30+ second freeze or background job timeout | Show count only; defer deep inspection to on-demand detail view | Driver folders with 10,000+ files (common for Dell/HP catalogs) |
| Polling timer at 50ms during USB-only job | CPU usage spike from DOM updates with no new messages | Keep existing 50ms for progress; consider 200ms for USB scan phase where progress updates are infrequent | Always — but unnoticeable at normal job durations; harmful only for 5+ minute operations |
| XAML with 100+ artifact rows (one per detected FFU) | WPF ListView virtualization disabled by default in some panel types | Use `VirtualizingStackPanel` for any list that could have unbounded rows | More than ~50 artifact entries |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Accepting arbitrary `$ArtifactPath` without canonicalization | Path traversal if input comes from saved config edited by user | Resolve with `[System.IO.Path]::GetFullPath()` and assert path starts with expected root before any file operation |
| Copying Autopilot JSON from user-specified path without hash verification | Autopilot JSON could be tampered with if path points to a network share | If `CopyAutopilot` is enabled in USB Mode, apply the same SHA-256 integrity check pattern used for script verification |
| Logging artifact full paths including potential credential-bearing UNC paths | Log files readable by any admin on the machine | Existing `WriteLog` pattern is fine; ensure `ArtifactPath` values from UNC shares are not logged verbatim in progress messages shown in UI |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Mode toggle immediately clears all Full Build settings | User accidentally switches to USB Mode and loses configured paths | Store Full Build state separately in `$script:uiState`; switching modes should restore prior state for that mode |
| Artifact disposition shows three radio buttons (Reuse/Rebuild/Skip) per row in a ListView | 12+ rows × 3 controls = 36+ interactive elements; visually overwhelming | Use a ComboBox per row with the three options; keeps the list scannable |
| No visual distinction between "artifact found" and "artifact missing" | User doesn't know which artifacts need attention before starting | Color-code rows: green = found and valid, yellow = found but stale/mismatched, red = missing; use `Converter` or code-behind to drive color |
| "Create USB" starts immediately with no confirmation of artifact disposition | User realizes mid-operation they forgot to mark one artifact as "Rebuild" | Show a pre-flight summary dialog listing all dispositions before starting the job |
| Progress bar uses same 0-100 scale as Full Build | USB Mode has different phases; a 10% increment for "Scanning" then jump to 90% for "Copying" looks broken | Define USB Mode-specific progress milestones and document them before implementation |

---

## "Looks Done But Isn't" Checklist

- [ ] **Mode toggle:** Button label resets correctly to mode-appropriate text after job completion — verify both "Build FFU" and "Create USB" idle states.
- [ ] **Cancel flow:** Pressing Cancel during a USB Mode job stops the ThreadJob — verify `isBuilding` was set, messaging context is cleaned up, and timer is stopped.
- [ ] **Artifact scan:** Architecture is extracted for every artifact type — verify FFU (via `Get-WindowsImage`), Deploy ISO (via WIM inspection), and driver folder (via INF `TargetOSVersion` sampling) all populate the Architecture column.
- [ ] **Cross-validation:** USB assembly is blocked when artifact architectures conflict — verify the block fires even when the user has manually typed paths (not just auto-detected ones).
- [ ] **Config persistence:** Saving config in USB Mode writes artifact paths and dispositions to JSON — verify by save → close → reopen → load config and assert all fields restored.
- [ ] **Config migration:** Loading a v1.10.0 config in v1.11.0 populates USB Mode fields with safe defaults — verify no exception and no missing keys.
- [ ] **Preflight scope:** USB Mode skips Hyper-V/VMware validation but still checks admin, ADK path, and disk space — verify by disabling Hyper-V on a test machine and confirming USB Mode still works.
- [ ] **DISM in ThreadJob:** `Import-Module DISM` and `Set-CommonCoreLogPath` are called inside scan job before any DISM or WriteLog call — inspect the ThreadJob scriptblock directly.
- [ ] **XAML parse test:** A Pester test calls `[Windows.Markup.XamlReader]::Load()` on the XAML and asserts no exception — confirm this test exists and passes.
- [ ] **WIMMount pre-check:** Scan phase checks WIMMount filter driver before calling `Get-WindowsImage` — verify using the same `fltmc filters` pattern from v1.3.12.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Mode state not propagated to cancel flow | MEDIUM | Audit all `btnRun.Content` and `isBuilding` assignments; add `currentMode` flag; update `Reset-FFUUIToIdle` |
| Artifact scanner on STA thread | LOW | Wrap scan in `Start-ThreadJob` with dispatcher callback; add spinner; ~2 hours work |
| Selective pipeline skips needed preflight | MEDIUM | Add `-RequiredTiers` parameter to `Invoke-FFUPreflight`; define USB-required tier set; ~4 hours work |
| Architecture cross-validation missing | HIGH | Requires re-scanning all artifacts and retrofitting validation gate before USB assembly; risk of schema changes if metadata not stored |
| ThreadJob breaks DISM cmdlets | LOW | Add `Import-Module DISM` inside scan scriptblock; ~30 minutes |
| Config schema not extended | HIGH | Schema change after users have saved configs; requires migration rule and testing; ~1 day work |
| Param block coupling repeated | LOW | Change param default to hardcoded value; ~30 minutes per parameter |
| XAML load failure | LOW-MEDIUM | Revert XAML edit, re-apply carefully with tooling; ~1-2 hours |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Mode state not propagated to cancel flow | Mode toggle UI + button wiring phase | Pester mock of cancel while USB job running; manual test clicking Cancel mid-USB |
| Artifact scanner on STA thread | Artifact scanner implementation phase | UI does not freeze during scan; spinner visible |
| Selective pipeline skips needed preflight | Selective pipeline execution design phase | Run USB Mode with ADK uninstalled — expect clear preflight failure, not mid-op crash |
| Cross-architecture mismatch not caught | Metadata extraction and cross-validation phase | Place x64 FFU + ARM64 ISO in scan folder; confirm UI blocks USB assembly |
| ThreadJob breaks DISM cmdlets | Artifact scanner implementation phase | Run scanner from UI (not interactive); confirm architecture fields populated |
| Config schema not extended | Config schema extension phase (first phase) | Save → reopen → confirm all USB fields restored; load v1.10.0 config → confirm migration |
| Param block coupling repeated | Any phase adding BuildFFUVM.ps1 parameters | Start-ThreadJob launch test in Pester; UI launch test |
| XAML load failure | Mode toggle UI implementation phase | Pester XAML parse test; must pass before any XAML PR merges |

---

## Sources

- Direct codebase inspection: `BuildFFUVM_UI.ps1` (state management, cancel flow, timer handler)
- Direct codebase inspection: `FFUUI.Core.StateRecovery.psm1` (hardcoded idle label)
- Direct codebase inspection: `FFUUI.Core.Config.psm1` (`Get-UIConfig` serialization pattern)
- Direct codebase inspection: `BuildFFUVM.ps1` param block comments (lines 7-18, documented coupling)
- Direct codebase inspection: `FFU.Preflight` module (tiered check structure)
- Direct codebase inspection: `FFU.Messaging` module (ConcurrentQueue context lifecycle)
- Direct codebase inspection: `BuildFFUVM.ps1` lines 748-759 (PSModulePath setup in ThreadJob)
- Project history: CLAUDE.md v1.3.5-v1.3.12 (WIMMount detection/repair progression)
- Project history: CLAUDE.md v1.2.7-v1.2.9 (module loading failures in ThreadJob)
- Project history: CLAUDE.md v0.0.9-v0.0.12 (ThreadJob cmdlet availability fixes)
- Project context: `.planning/PROJECT.md` (v1.11.0 milestone feature list)

---
*Pitfalls research for: USB-from-existing-components mode addition to FFU Builder WPF/PowerShell tool*
*Researched: 2026-03-12*
