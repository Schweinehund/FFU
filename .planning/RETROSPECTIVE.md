# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.11.0 — USB from Existing Components

**Shipped:** 2026-06-26
**Phases:** 6 (45-50) | **Plans:** 18 | **Tasks:** 20

### What Was Built
- Config schema v1.3 with additive migration (ActiveMode + USBMode.Artifacts, 7 artifact types) — no data loss for existing configs.
- FFU.ArtifactScanner module — typed data contracts, Find-FFUArtifacts (7 types, graceful degradation), Get-ArtifactMetadata via DISM with filename fallback, Test-ArtifactCompatibility arch-mismatch detection.
- `-USBOnlyMode` pipeline entry short-circuiting the build to assemble a USB directly (14 `$using:` variables populated from manifest).
- UI mode toggle (Full Build / USB Mode) with USB tab, 7 artifact cards, browse dialogs, USB drive selection, mode-aware cancel/reset.
- Selective rebuild pipeline — per-artifact Reuse/Rebuild/Skip disposition drives selective per-phase rebuild; legacy Include field removed for schema-native Disposition enum.

### What Worked
- **Schema-first sequencing** (Phase 45 before everything): defining the config contract up front avoided expensive retrofits in UI/pipeline consumers.
- **Isolated data-contract module** (Phase 46) before any UI/pipeline work — consumers built against a stable, tested interface.
- **Wave-based TDD in Phase 50**: Wave-0 RED scaffolds (43 failing behavioral Its) defined the spec before implementation; finished 275/275 green.
- Deferring the highest-complexity phase (selective rebuild) to last, once the full USB Mode end-to-end already worked.

### What Was Inefficient
- **Long calendar span** (2026-03-20 → 2026-06-26) with the milestone sitting at "code-complete" while GUI UAT went unrun — verification debt accumulated rather than closing per-phase.
- Phase 49 needed a 5th gap-closure plan (49-05) for a cancel/cleanup label fix that an earlier cancel-flow audit should have caught (it was flagged as a research item but not fully resolved in-phase).
- SUMMARY one-liner extraction produced noisy MILESTONES.md accomplishments (stray "BuildFFUVM_UI.xaml", a raw review-rule line) requiring manual curation at close.

### Patterns Established
- Per-artifact **Disposition enum** (Reuse/Rebuild/Skip) as the schema-native control surface, replacing boolean Include flags.
- USB Mode control naming convention `usb{ArtifactType}{Property}` across 46 named controls.
- Typed WPF Brushes/FontStyles only (no bare strings) in UI scan rendering to avoid WPF type-conversion failures.
- `isLoadingConfig` flag to guard scans from firing during config load (load order: artifact paths before ActiveMode RadioButton).

### Key Lessons
1. **Mark deferred UAT explicitly, carry it forward at project level.** When GUI testing is deferred (here: upcoming changes would invalidate it), record it in STATE.md "Deferred Items" + MILESTONES.md known gaps, not just the phase folder — otherwise it disappears at milestone close.
2. **Resolve flagged research items in-phase.** Phase 49's cancel-flow audit item became a 5th plan; flagged-but-unclosed audits tend to resurface as gap-closure work.
3. **Curate auto-extracted accomplishments.** The milestone SDK pulls SUMMARY one-liners verbatim — review for stray fragments before the entry is committed.

### Cost Observations
- Model mix: predominantly Opus for planning/execution (not separately instrumented this milestone).
- Notable: the milestone's wall-clock was dominated by the gap between Phase 49 (late March) and Phase 50 (June), not by active execution time.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.11.0 | 6 (45-50) | 18 | Schema-first + isolated data-contract module before UI; wave-based TDD; first milestone to defer GUI UAT as explicit carry-forward |

### Cumulative Quality

| Milestone | Tests at close | Zero-Dep Additions |
|-----------|----------------|-------------------|
| v1.11.0 | 275/275 Pester green | FFU.ArtifactScanner (new module) |

### Top Lessons (Verified Across Milestones)

1. Schema/contract-first sequencing prevents expensive downstream retrofits.
2. Verification deferred is verification at risk — make it an explicit, tracked carry-forward, never an implicit gap.
