# Phase 50: Selective Rebuild Pipeline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-22
**Phase:** 50-selective-rebuild-pipeline
**Areas discussed:** Disposition control UI, Rebuildable artifact scope, FFU rebuild semantics, Defaults & missing artifacts, Rebuild scope (machinery)

**Method:** The user requested a three-agent adversarial review (`/adversarial-review`) to score each option and recommend the best with reasoning. A Finder critiqued every option (368 weighted pts), an Adversary challenged the findings (0 wrong disproves; added the "phase-wide work vs. option discriminator" reframe), and a Referee delivered the final ruling. The user accepted all four recommendations and chose full-machinery scope.

---

## Area 1 — Disposition control UI

| Option | Description | Selected |
|--------|-------------|----------|
| 1A — ComboBox replacing checkbox | Single ComboBox (Reuse/Rebuild/Skip), per-card item set, binds 1:1 to the Disposition enum | ✓ |
| 1B — Three radio buttons | Fixed 3-radio group per card; needs show/hide surgery for 2-item and 1-item tiers | |
| 1C — Checkbox + separate Rebuild toggle | Two booleans → 4-state space over a 3-value enum; includes incoherent "excluded + rebuild" | |
| 1D — Segmented toggle group | Custom-built control; same fixed-cardinality problem as 1B, higher implementation cost | |

**User's choice:** 1A
**Notes:** Referee: ComboBox is the only control that adapts item count per scope tier without changing control type, and is the front half of the F2 Disposition→gate fix. Required artifacts render as a single disabled "Reuse" item (preserves XAML hard-lock + IsReady block).

---

## Area 2 — Rebuildable artifact scope

| Option | Description | Selected |
|--------|-------------|----------|
| 2A — All 7 types get 3-way | Rebuild offered on user-authored PPKG/Unattend/Autopilot (no build phase → no-op/mislead) | |
| 2B — Buildable get Rebuild incl. FFU | Honest except it implicitly endorses FFU rebuild, which is architecturally infeasible | |
| 2C — Tiered: buildable 3-way, user-authored Reuse/Skip, FFU special-cased | Models all three artifact tiers honestly | ✓ |

**User's choice:** 2C
**Notes:** Flagged as a genuine product judgment call (2B vs 2C). 2C wins because it forces an explicit answer to the FFU question (Area 3) rather than inheriting an unsafe default. Drivers Rebuild is gated on Make/Model + driversJson inputs (F6).

---

## Area 3 — FFU rebuild semantics

| Option | Description | Selected |
|--------|-------------|----------|
| 3A — Inline full build in USB Mode | Inlines a 30-90 min build into the short-circuit that skips pre-flight/phases; progress-model collision | |
| 3B — Redirect to Full Build mode | Breaks persisted ActiveMode; Full Build ignores per-artifact dispositions; needs unconfigured 7-tab inputs | |
| 3C — Disallow (FFU = Reuse only) | Only option with no architectural blocker; OS rebuild routes to Full Build via inline helper text | ✓ |
| 3D — Inline + confirmation dialog | A dialog cannot fix an infeasible execution path | |

**User's choice:** 3C
**Notes:** F4 is dispositive — FFU rebuild IS the heavy build the Phase-47 short-circuit deliberately avoids. 3C makes the existing FFU-is-required reality explicit and provides an honest, visible redirect (not a silent mode-switch).

---

## Area 4 — Defaults & missing-artifact disposition

| Option | Description | Selected |
|--------|-------------|----------|
| 4A — Found→Reuse; missing-required→block; missing-optional→Skip | Matches the existing two-tier IsReady reality | ✓ |
| 4B — Found→Reuse; Missing→Skip uniformly | Silently skips a missing required FFU/DeployISO, contradicting the BLOCKING gate | |
| 4C — Found→Reuse; Missing→Rebuild | Auto-launches the heavy build on an empty FFU folder; impossible for user-authored artifacts | |

**User's choice:** 4A
**Notes:** Extended to the real 4-status scanner (F7): Degraded → Reuse + warning; Error → treated like Missing per tier. The block path reuses the existing IsReady mechanism.

---

## Scope — what "Rebuild" covers in Phase 50

| Option | Description | Selected |
|--------|-------------|----------|
| Build the machinery (full scope) | Implement selective per-phase execution for Drivers/AppsISO/DeployISO + their inputs | ✓ |
| Narrow to what's feasible now | Rebuild only for cheaply-isolable artifacts; defer the rest | |
| Disposition UI only | Ship controls + config wiring + F1/F2, defer ALL rebuild execution | |
| Let me think about it | Discuss trade-offs first | |

**User's choice:** Build the machinery (full scope)
**Notes:** The review found NO selective-phase-execution machinery exists today (F3) — all skip flags are resume-forward only and phases share VM/VHDX/ADK state. The user chose to build the inverse "run only this phase" capability for the buildable artifacts. The Referee calls this the largest single cost in the phase; it must be scoped explicitly in planning.

## Claude's Discretion

- ComboBox styling, item rendering, and how Degraded/Error warnings surface on the card.
- The mechanism/shape of the selective per-phase execution gate (new `$rebuild<Phase>` gates vs. dispatch table vs. refactoring existing skip conditions).
- How rebuilt artifact outputs reconcile into the `New-DeploymentUSB` script-scoped globals before assembly.
- Whether Drivers Make/Model inputs live on the Drivers card vs. are read from active config.

## Deferred Ideas

- Inline FFU rebuild inside USB Mode — intentionally rejected (3C).
- Auto-rebuild of stale/missing artifacts — Out of scope per REQUIREMENTS.md.
- Saved USB Mode profiles (REBUILD-04) — future.
- Artifact version history / rollback (REBUILD-05) — future.
- Network/cloud artifact sources — Out of scope.
