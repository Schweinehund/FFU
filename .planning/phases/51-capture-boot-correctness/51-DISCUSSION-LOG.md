# Phase 51: Capture/Boot Correctness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-26
**Phase:** 51-capture-boot-correctness
**Areas discussed:** Fallback selection UX, EditionId vs name match, BCDBoot not-found behavior, LTSC year mapping
**Method:** User delegated decisions to a three-agent **adversarial review** (Advocate → Adversary → Referee) via `/adversarial-review`. Each option was argued for, attacked, and ruled on against live fork code + external facts. Final rulings = the Referee's calibrated verdicts.

---

## Fallback selection UX (CORRECT-01 / 5aaa1ad)

| Option | Description | Selected |
|--------|-------------|----------|
| 1A auto-select + propagate | Pick a fallback non-interactively, propagate selected edition downstream | partial ✓ |
| 1B hard-fail with editions list | List available editions, throw — no silent substitution | partial ✓ |
| 1C WPF UI pick | Surface the choice to the operator via the UI | |

**Ruling: 1A-conditional** — auto-select + propagate when exactly ONE relevant candidate exists; WriteLog editions list + hard-fail when ambiguous. Delete the `Read-Host`/`while($true)` loop (it hangs under ThreadJob).
**Debate:** Advocate=1B (contingent on D2). Adversary WEAKEN: the SKU validation (`BuildFFUVM.ps1:965`) checks edition *legality*, not media *presence*, so pure-1B hard-fails legitimate single-edition ISOs that 1A would salvage; also the Get-Index call is outside any `Invoke-BuildPhase` wrapper so editions must be `WriteLog`'d, not just thrown. Referee upheld WEAKEN — upstream `5aaa1ad`'s actual purpose is *propagating the selected edition*, favoring auto-select-single-candidate. 1C rejected: needs FFU.Messaging plumbing + still needs a headless fallback.

---

## EditionId vs name match (CORRECT-04 / b2a7ef5)

| Option | Description | Selected |
|--------|-------------|----------|
| 2A replace entirely | Substitute substring/name match with EditionId/InstallationType only | |
| 2B EditionId primary + name fallback | EditionId → exact `ImageName -eq` fallback → fail | ✓ |

**Ruling: 2B.**
**Debate:** Advocate=2A (cleaner, matches upstream). Adversary OVERTURN: user `$WindowsSKU` values are friendly names (`'Pro'`) ≠ DISM `EditionId` (`Professional`), so 2A *requires* a large error-prone SKU→EditionId map anyway; and the existing name match is exact `-eq` (not substring), so a name fallback cannot manufacture false positives — 2B is strictly safer. Referee upheld (High confidence): `'Pro' -ne 'Professional'` is a pure code fact; map is mandatory either way; exact-`-eq` fallback covers map gaps on English media. Map completeness flagged as a test gate.

---

## BCDBoot not-found behavior (CORRECT-03 / 6c0ee8a)

| Option | Description | Selected |
|--------|-------------|----------|
| 3A hard-fail if ADK bcdboot missing | Guarantee Secure-Boot-2023-correct artifact; never silently substitute | ✓ |
| 3B host fallback + warning | Fall back to host bcdboot with a logged warning | |

**Ruling: 3A** — *Adversary's overturn was REVERSED by the Referee.*
**Debate:** Advocate=3A. Adversary OVERTURN=3B, claiming the 2023 cert ships in the applied image and bcdboot just copies from `$Os:\Windows`, so host vs ADK bcdboot doesn't change the cert (flagging it couldn't read upstream 6c0ee8a). Referee verified upstream changelog (v2603.2): the ADK bcdboot is required *because* a host carrying the Windows UEFI CA 2023 cert stages 2023-signed boot files that fail Secure Boot on target hardware — **the bcdboot binary's version determines the staged cert**, refuting the Adversary's model. 3B re-introduces the exact bug. Referee ruled 3A (High confidence) + add a pre-flight ADK-bcdboot check + record an ADK-version caveat (Dec 2024 ADK stages 2011 certs; Nov 2025+ ADK defaults to 2023).

---

## LTSC year mapping (CORRECT-02 / 04dfb5f)

| Option | Description | Selected |
|--------|-------------|----------|
| Mapping {2016→10, 2019→10/Server-keep, 2021→10, 2024→11} | Year→release normalization gated on $isLTSC | ✓ |
| 4-Central (dedicated $driverWindowsRelease) | Normalize once at driver dispatch, don't clobber global | ✓ |
| 4-PerProvider | Normalize inside each OEM provider | |

**Ruling: mapping above + central, dedicated `$driverWindowsRelease` gated on `$isLTSC`, never clobber global `$WindowsRelease`.**
**Debate:** Advocate proposed it; Adversary UPHELD (declined to attack to avoid the 2x wrong-call penalty). Referee confirmed (High confidence): `$WindowsRelease` has no `[ValidateSet]` so 2021/2024 reach the driver step and fail today (bug is real); LTSC-2019 vs Server-2019 are mutually exclusive via `$isLTSC`/`$installationType` so gating is clean; central normalization keeps the LTSC-vs-Server logic in one audited spot; a dedicated var avoids clobbering naming/cache/MSRT/Server-version consumers of the global.

---

## Claude's Discretion

- Shape/location of the SKU→EditionId map (completeness non-negotiable).
- Mechanism for propagating the selected edition through the Get-Index caller (richer return object vs out-param vs call-site reassignment).
- Whether ADK bcdboot resolution is a FFU.ADK wrapper or inline in Add-BootFiles.
- Unit-test surface (mocked Get-WindowsImage; pure year-normalization function; map coverage). Real-media / Secure-Boot-2023-hardware paths are human-UAT only.

## Deferred Ideas

- Normalizing the *global* `$WindowsRelease` (name/cache LTSC by base 10/11) — out of scope; broader blast radius.
- Confirm the fork actually drives WindowsRelease=2016 LTSC before relying on that mapping row.
- T1-7 (`42b0b0c`) Win10 LTSC in-VM cumulative update — deferred at milestone scoping (verify-first).
