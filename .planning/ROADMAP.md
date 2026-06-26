# Roadmap: FFU Builder

## Milestones

- ✅ **v1.8.0 Codebase Health** - Phases 1-10 (shipped 2026-01-20)
- ✅ **v1.8.1 Bug Fixes** - Phases 11-13 (shipped 2026-01-20)
- ✅ **v1.8.3 VMware UI Settings** - Phase 14 (shipped 2026-01-21)
- ✅ **v1.9.0 Reliability Hardening** - Phases 15-25 (shipped 2026-01-24)
- ✅ **v1.9.1 Build Phase Integration** - Phase 26 (shipped 2026-01-24)
- ✅ **v1.9.2 Smart Configuration & Bug Fixes** - Phases 27-30 (shipped 2026-01-25)
- ✅ **v1.9.3 OEM Driver Bug Fixes** - Phases 31-33 (shipped 2026-01-27)
- ✅ **v1.10.0 Upstream Cherry-Pick** - Phases 34-43 (shipped 2026-02-02)
- ✅ **Phase 44: DISM Resilience Updates** - (shipped 2026-03-12, ad-hoc)
- ✅ **v1.11.0 USB from Existing Components** - Phases 45-50 (shipped 2026-06-26)

## Phases

<details>
<summary>✅ v1.8.0 through v1.10.0 + Phase 44 (Phases 1-44) - SHIPPED</summary>

Phases 1-44 complete. See MILESTONES.md for details.

</details>

<details>
<summary>✅ v1.11.0 USB from Existing Components (Phases 45-50) — SHIPPED 2026-06-26</summary>

**Milestone Goal:** Enable USB deployment media creation from pre-existing build artifacts without running the full 40+ minute build pipeline.

- [x] Phase 45: Config Schema Extension (2/2 plans) — completed 2026-03-20
- [x] Phase 46: FFU.ArtifactScanner Module (2/2 plans) — completed 2026-03-14
- [x] Phase 47: USB Mode Pipeline Entry (1/1 plan) — completed 2026-03-20
- [x] Phase 48: XAML Mode Toggle and USB Tab (2/2 plans) — completed 2026-03-24
- [x] Phase 49: UI Event Wiring and Artifact Integration (5/5 plans) — completed 2026-03-25
- [x] Phase 50: Selective Rebuild Pipeline (6/6 plans) — completed 2026-06-22

Full phase details archived in `.planning/milestones/v1.11.0-ROADMAP.md`.
Requirements archived in `.planning/milestones/v1.11.0-REQUIREMENTS.md`.

**Known gaps at close (deferred):** DISC-01 and VALID-01→04 (Phase 46 artifact discovery/validation) implemented but their GUI verification is the deferred USB Mode UAT. See MILESTONES.md and STATE.md "Deferred Items".

</details>

### 📋 v1.12.0 (Next — not yet defined)

Run `/gsd-new-milestone` to define scope, requirements, and phases.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-44. Previous Milestones | v1.8.0-v1.10.0 | 133/133 | Complete | 2026-03-12 |
| 45-50. USB from Existing Components | v1.11.0 | 18/18 | Complete | 2026-06-26 |

---
*Roadmap created: 2026-03-12 for v1.11.0 USB from Existing Components*
*Last updated: 2026-06-26 — v1.11.0 milestone shipped and archived*
