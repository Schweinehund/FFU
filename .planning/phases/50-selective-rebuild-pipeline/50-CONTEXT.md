# Phase 50: Selective Rebuild Pipeline - Context

**Gathered:** 2026-06-22
**Status:** Ready for planning

> Decisions in this phase were selected via a three-agent adversarial review
> (Finder → Adversary → Referee). Each option was scored for flaws, challenged,
> and ruled on. The reasoning behind every locked decision is preserved in
> `50-DISCUSSION-LOG.md`.

<domain>
## Phase Boundary

Users can mark each USB-Mode artifact as **Reuse / Rebuild / Skip**. The pipeline runs **only** the build phase(s) needed to regenerate artifacts marked Rebuild, takes Reuse artifacts from their existing paths with no build execution, excludes Skip artifacts from USB assembly, and combines rebuilt + reused artifacts into the final USB drive.

**Requirements:** REBUILD-01, REBUILD-02, REBUILD-03.

**In scope (full machinery):** disposition control UI, config wiring of `Disposition` into the build gate, the AppsISO USB copy path, a 4-status scanner UI, AND new selective per-phase execution machinery so individual buildable phases (Drivers, AppsISO, DeployISO) can run in isolation from a cold USB-Mode start — including collecting the inputs those phases require.

**Out of scope:** FFU rebuild inside USB Mode (OS rebuild is routed to Full Build mode — see D-09); auto-rebuild of stale/missing artifacts (REQUIREMENTS.md out-of-scope); saved USB profiles (REBUILD-04); version history/rollback (REBUILD-05).

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Disposition control UI (winner: 1A, single ComboBox)
- **D-01:** Each artifact card uses a **single ComboBox** (`Reuse` / `Rebuild` / `Skip`) that **replaces** the Phase-49 include checkbox. One control binds 1:1 to the schema `Disposition` enum — no illegal multi-control state combinations.
- **D-02:** The ComboBox `ItemsSource` is **per-card, driven by the Area-2 scope tier** (3 items for buildable, 2 items `Reuse`/`Skip` for user-authored, 1 disabled `Reuse` item for required). Control *type* stays uniform across all cards; only the item set varies.
- **D-03:** **Required artifacts (FFU, DeployISO)** render as a ComboBox containing only `Reuse`, `IsEnabled=False`, default-selected — preserving the existing XAML hard-lock (`usbFFUInclude`/`usbDeployISOInclude` are `IsEnabled=False IsChecked=True`, XAML 959/1012) and the BLOCKING `IsReady` throw (BuildFFUVM.ps1 1776-1782). They never offer Skip or Rebuild.
- **Rejected:** 1B (3 radios) and 1D (segmented toggle) hardwire a fixed cardinality and need per-card show/hide surgery for the 2-item and 1-item tiers. 1C (checkbox + separate Rebuild toggle) creates a 4-state space over a 3-value enum, including the incoherent "excluded + rebuild" state.

### Area 2 — Rebuildable scope (winner: 2C, tiered by what the pipeline can produce)
- **D-04:** **Buildable artifacts** — Drivers, AppsISO, DeployISO — offer the full `Reuse` / `Rebuild` / `Skip` set.
- **D-05:** **User-authored artifacts** — PPKG, Unattend, Autopilot — offer only `Reuse` / `Skip`. The pipeline only ever *copies* these (it never authored them); offering Rebuild would be a no-op/misleading affordance (the 2A trap).
- **D-06:** **FFU is special-cased** — `Reuse` only (see Area 3 / D-09). This special case is the reason 2C is chosen over 2B.
- **D-07:** Drivers' `Rebuild` item is **gated on input availability** (F6): driver rebuild requires `$driversJsonPath` + Make/Model, which the USB tab does not currently collect. Because full-machinery scope was chosen (see D-12), Phase 50 **adds those inputs** to the Drivers card / sources them from config so Drivers Rebuild is genuinely offerable. If at plan time those inputs cannot be sourced, Drivers degrades to `Reuse`/`Skip` for this phase.

### Area 3 — FFU rebuild semantics (winner: 3C, disallow in USB Mode)
- **D-08:** FFU **cannot be rebuilt inside USB Mode.** FFU rebuild *is* the full 30-90 min heavy build (VM, OS, updates, sysprep, capture) that the Phase-47 short-circuit deliberately skips (it bypasses pre-flight and all build phases and ends in a hard `return`, with a hardcoded progress model 5/10/15/100 that collides with the full-build scale).
- **D-09:** Where a user might expect an FFU rebuild, show **inline helper text** — "To rebuild the OS image, switch to Full Build" — pointing at the existing `ActiveMode` toggle (XAML line 78). This is an honest, visible redirect, NOT a silent mode-switch (3B's flaw: it breaks persisted `ActiveMode`, Full Build ignores per-artifact dispositions, and it needs unconfigured 7-tab inputs).
- **Rejected:** 3A inline and 3D inline+dialog are architecturally infeasible (a dialog cannot fix an infeasible execution path). 3B redirect-to-Full-Build silently breaks the mode contract and drops per-artifact reuse/skip semantics.

### Area 4 — Defaults & missing-artifact disposition (winner: 4A, two-tier)
- **D-10:** **Found → `Reuse`** (matches the schema default). **Missing REQUIRED** (FFU, DeployISO) → **block** (reuse the existing `IsReady` throw, 1776-1782). **Missing OPTIONAL** (Drivers, PPKG, Unattend, Autopilot, AppsISO) → **`Skip`**.
- **D-11:** Extend the default mapping to the **real 4-status scanner** (F7): `Degraded` → default `Reuse` **with a visible warning** (file present but suspect — let the user decide, don't silently drop); `Error` → treat like `Missing` per its required/optional tier. The current binary Found/else UI logic must be widened end-to-end.
- **Rejected:** 4B (Missing→Skip uniformly) would silently skip a missing required FFU/DeployISO, contradicting the BLOCKING gate. 4C (Missing→Rebuild) auto-launches the heavy build on an empty FFU folder and is impossible for user-authored artifacts.

### Scope decision — full selective-execution machinery
- **D-12:** Phase 50 **builds the selective per-phase execution machinery** (the F3 gap). Today every skip flag (`$skipPreflightValidation`, `$skipDriverDownload`, `$skipDeploymentMedia`, `$skipUSBCreation`) is **resume-forward only** (guarded by `$script:IsResuming` + `Test-PhaseAlreadyComplete`); there is no "run ONLY phase X" gate, and phases share VM/VHDX/ADK state. Phase 50 implements the inverse capability so Drivers / AppsISO / DeployISO can each run in isolation from a cold USB-Mode start, then hand off to USB assembly. **This is the largest single cost in the phase and must be scoped explicitly in planning.**

### Claude's Discretion (for researcher/planner)
- Exact ComboBox styling, item rendering, and how `Degraded`/`Error` warnings surface on the card.
- The mechanism/shape of the selective per-phase execution gate (a new `$rebuild<Phase>` gate set, a phase-dispatch table, refactoring the existing skip-flag conditions, etc.) — research the cleanest fit with the existing resume/skip pattern.
- How rebuilt artifact outputs are reconciled into the `New-DeploymentUSB` script-scoped globals (`$DriversFolder`, `$DeployISO`, etc.) before assembly.
- Whether Drivers Make/Model inputs live on the Drivers card vs. are read from the active config.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Config schema (Phase 45) — disposition model + the F2 gap
- `FFUDevelopment/config/ffubuilder-config.schema.json` — `ActiveMode` field (~653-657); `USBMode.Artifacts` section; `ArtifactEntry` definition (~681-700) with `Path` + `Disposition` enum (Reuse/Rebuild/Skip, default Reuse, ~692-697). **Note: schema has NO `Include` property.**

### Pipeline / build gate (Phase 47) — the F1/F2/F3 work lives here
- `FFUDevelopment/BuildFFUVM.ps1` — `-USBOnlyMode` short-circuit block (~1723-1925); `IsReady` BLOCKING throw (1776-1782); the gate that currently reads `cfgArt.<Type>.Include` and **must be rewritten to read `.Disposition`** (~1895-1909); hardcoded short-circuit progress `Set-Progress 5/10/15/100`.
- `FFUDevelopment/BuildFFUVM.ps1` — `New-DeploymentUSB` (~1315-1562); copies FFU/Drivers/PPKG/Unattend/Autopilot but **has no AppsISO copy path** (comment ~1894, "no `$CopyAppsISO` ... handled via path only") — F1 must add it.
- `FFUDevelopment/BuildFFUVM.ps1` — resume-forward skip-flag pattern: `$skipPreflightValidation` (~1933), `$skipDriverDownload` (~2653), `$skipDeploymentMedia` (~5318), `$skipUSBCreation` (~5378); Driver Download phase (~2651-2666, needs `$driversJsonPath`/Make/Model); Deployment Media phase / `New-PEMedia` (~5316-5374, depends on `$adkPath`/`$WindowsArch`/`$DriversFolder`).

### Artifact scanner (Phase 46) — F7 status model
- `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1` — `Find-FFUArtifacts`, `Get-ArtifactMetadata`, `New-ArtifactManifest`.
- `FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1` — `ArtifactType` enum, `ArtifactStatus` enum (`Found`/`Missing`/`Error`/`Degraded`), `ArtifactManifest`, `ArtifactResult`, `FFUMetadata`.

### USB Mode UI (Phases 48/49)
- `FFUDevelopment/BuildFFUVM_UI.xaml` — `usbModeTab` artifact cards (~932-1243); required-artifact hard-locks `usbFFUInclude` (line 959) and `usbDeployISOInclude` (line 1012) `IsEnabled=False IsChecked=True`; `rbFullBuild`/`rbUSBMode` RadioButtons (~78-79) for `ActiveMode`.
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` — `Register-EventHandlers`; `$artifactMap` keyed on `includeCtrl` (~26-33) — must be reworked from a single checkbox per type to a ComboBox; Add_Checked/Add_Click idioms (a new SelectionChanged idiom is introduced by D-01).
- `FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1` — `Build-UIConfiguration` / `Update-UIFromConfig` USBMode save/load (per 49-CONTEXT D-22/D-24) — must serialize/restore `Disposition` per artifact.

### Prior phase contexts (decisions carried forward)
- `.planning/phases/45-config-schema-extension/45-CONTEXT.md` — ActiveMode + USBMode schema decisions.
- `.planning/phases/46-ffu-artifactscanner-module/46-CONTEXT.md` — artifact types, status model.
- `.planning/phases/47-usb-mode-pipeline-entry/47-CONTEXT.md` — short-circuit architecture, copy gates, `$using:` inventory (the boundary Area 3 protects).
- `.planning/phases/49-ui-event-wiring-and-artifact-integration/49-CONTEXT.md` — card layout, include checkbox, mode-switch handler, config persistence, ThreadJob launch pattern.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Find-FFUArtifacts` / `ArtifactManifest`: per-artifact `Status` (4-state), `FilePath`, `IsReady`, `Warnings` — the source of truth that drives both the ComboBox item set (D-02) and the missing-artifact defaults (D-10/D-11).
- `New-DeploymentUSB`: existing assembly function — extend it (F1: AppsISO copy path) and feed it the reconciled mix of rebuilt + reused artifact paths (Criterion 5).
- Resume/skip-flag pattern (`$skip<Phase>` + `Test-PhaseAlreadyComplete`): the closest existing analog for D-12's selective execution; research whether to invert/extend it or add a parallel `$rebuild<Phase>` gate set.
- `Register-EventHandlers` / `$artifactMap`: central wiring point for the new ComboBox controls.

### Established Patterns
- Schema `Disposition` enum is the canonical disposition representation — D-01's ComboBox binds directly to it; the pipeline gate must read it (F2).
- Param-block coupling rule: no `[FFUConstants]::` in param defaults (ThreadJob parse-time constraint).
- All build-time code must run inside `Start-ThreadJob`; use `WriteLog` and the ThreadJob-safe idioms (`[DateTime]::Now`, etc.).

### Integration Points
- Build gate (~1895-1909): switch from `.Include` to `.Disposition`.
- `New-DeploymentUSB` (~1328-1562): add AppsISO copy; consume disposition-driven path set.
- USB-Mode short-circuit (~1723-1925): insert selective per-phase execution (D-12) between scan/validate and USB assembly; preserve the `return`-terminated boundary that keeps the full build out.
- USB Mode tab cards: checkbox → ComboBox; add Drivers Make/Model inputs (D-07) if sourced there.

</code_context>

<specifics>
## Specific Ideas

- The disposition control, scope tiering, FFU policy, and defaults are deliberately interlocked: 1A's ComboBox item set is *supplied by* 2C's tier; 2C *assumes* 3C (FFU = Reuse-only); 4A's defaults always resolve to a legal item within 2C's allowed set, so the UI state machine is closed (no default ever selects an item a card doesn't offer).
- "Rebuild means the pipeline can regenerate this artifact from inputs" is the governing principle — it is why user-authored artifacts get no Rebuild and why FFU (regenerable only via the heavy build) is routed out to Full Build mode rather than rebuilt in place.

</specifics>

<deferred>
## Deferred Ideas

- Inline FFU rebuild inside USB Mode — intentionally rejected (3C); OS rebuild routes to Full Build mode.
- Auto-rebuild of stale or missing artifacts — Out of scope per REQUIREMENTS.md (and 49-CONTEXT line 156).
- Saved USB Mode profiles (named configurations) — Future (REBUILD-04).
- Artifact version history / rollback selection — Future (REBUILD-05).
- Network/cloud artifact sources — Out of scope per REQUIREMENTS.md.

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 50-selective-rebuild-pipeline*
*Context gathered: 2026-06-22*
