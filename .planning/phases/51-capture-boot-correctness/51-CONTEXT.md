# Phase 51: Capture/Boot Correctness - Context

**Gathered:** 2026-06-26
**Status:** Ready for planning

> Decisions in this phase were selected via a three-agent **adversarial review**
> (Advocate → Adversary → Referee) at the user's request. Each competing
> implementation option was argued for, attacked, and ruled on against the live
> fork code and external facts. The full reasoning — including the D3 reversal
> where the Referee found upstream changelog evidence overturning the
> Adversary — is preserved in `51-DISCUSSION-LOG.md`.

<domain>
## Phase Boundary

Builds never produce a wrong-edition, unbootable, or LTSC-failing artifact. Four targeted correctness ports from upstream `rbalsleyMSFT/FFU` branch `UI` into the fork's modular code:

- **CORRECT-01** (`5aaa1ad`): after a fallback edition is chosen because the exact SKU isn't on the media, the FFU is named/cached/serviced as the *selected* edition, not the originally-requested one.
- **CORRECT-02** (`04dfb5f`): OEM driver downloads for LTSC builds (2019/2021/2024) no longer fail on a release-year validation error.
- **CORRECT-03** (`6c0ee8a`): boot files are written with the **ADK's** BCDBoot (not the host's) so captured images boot on Secure Boot 2023-cert devices.
- **CORRECT-04** (`b2a7ef5`): the correct edition is captured from non-English/multi-edition media by selecting the image index via EditionId/InstallationType, not a localized name substring.

**In scope:** the four ports above, adapted to the fork's modular + ThreadJob/WPF reality. **Out of scope:** any new capability beyond these four fixes (later v1.12.0 phases own driver-grid, cache-naming, device-naming, UI, and hygiene work).

</domain>

<decisions>
## Implementation Decisions

These four decisions were locked via adversarial review. Each is the Referee's final ruling.

### D1 — Fallback selection UX (CORRECT-01) — ruling: **1A-conditional** (Adversary WEAKEN upheld)
- **D-01:** When `Get-Index` finds no exact edition match, **delete the interactive `Read-Host` / `while($true)` loop entirely** (`FFU.Imaging.psm1:562-585`). It is the real bug — it *hangs* under ThreadJob, it does not throw cleanly.
- **D-02:** If **exactly one** relevant candidate index exists (the `ImageName -match "(10|11|2016|2019|202\d)"` set, line 560), **auto-select it non-interactively AND propagate the actually-selected edition downstream** so naming, caching, and servicing use the selected edition — this propagation *is* the upstream `5aaa1ad` fix.
- **D-03:** If **two or more** candidates exist (genuinely ambiguous), **`WriteLog` the full available-editions list, then `throw`**. Do NOT rely on the throw message alone — the ThreadJob error stream is unreliable, so the editions list must land in the build log.
- **D-04:** `Get-Index` returns only an `[int]` index today and `$WindowsSKU` is never reassigned (`BuildFFUVM.ps1:4403-4404`). The propagation in D-02 must update the edition value consumed by: FFU naming (`Get-ShortenedWindowsSKU` → `New-FFUFileName`, ~5340), VHDX cache key (`$cachedVHDXInfo.WindowsSKU` write ~4643 / match ~4087), and the servicing/build-context hashes (`WindowsSKU = $WindowsSKU` at ~4339, 4698, 5192, 5301, 5636, 5696). **Trace all three consumer families** (research flag from STATE.md).
- **Rejected:** pure-1B (always hard-fail) — the SKU validation at `BuildFFUVM.ps1:965` only checks edition *legality for the release*, NOT media *presence*, so a legitimate single-edition ISO would be hard-failed when it should be salvaged. 1C (WPF round-trip mid-build) — needs `FFU.Messaging` request/response plumbing and still needs a headless fallback; collapses back to 1A/1B.

### D2 — Image index selection (CORRECT-04) — ruling: **2B** (Adversary OVERTURN upheld)
- **D-05:** Select the image index by **`EditionId` (primary) → exact `ImageName -eq` (fallback) → fail**. Replace the localized-substring derivation (`ImageName.Substring(0,10)/(0,19)` at lines 535/539/544) — it hard-assumes English string lengths and breaks on non-English/LTSC/multi-edition media.
- **D-06:** A **SKU→EditionId map is MANDATORY** (true for 2A *or* 2B): user `$WindowsSKU` values are friendly names (`'Pro'`, `'Home'`, `'Enterprise LTSC'`, …, `BuildFFUVM.ps1:926-963`) and DISM `EditionId` returns canonical tokens (`Professional`, `Core`, `EnterpriseS`, …). `'Pro' ≠ 'Professional'` — a direct match fails. The map must cover **every** entry in `$clientSKUs`, `$LTSCSKUs`, `$ServerSKUs`, including the hard ones: Home→`Core`, Pro→`Professional`, N variants→`*N`, "Enterprise LTSC"→`EnterpriseS`, "IoT Enterprise LTSC"→`IoTEnterpriseS`, Server desktop-vs-core. **Map completeness is a test gate** — an incomplete map silently mis-selects.
- **D-07:** Use `InstallationType` (Client/Server — already computed as `$installationType` at `BuildFFUVM.ps1:2388`, passed into imaging at `FFU.Imaging.psm1:2588`) to prevent matching a client edition on server media and vice-versa.
- **D-08:** The exact-`ImageName -eq` fallback is safe — the existing match at line 551 is exact `-eq` (NOT substring/`-match`), so `"Windows 11 Pro" -ne "Windows 11 Pro N"`; it cannot manufacture a false positive. It runs only *after* EditionId already missed, covering map gaps on English media.
- **Rejected:** 2A (replace entirely, no name fallback) — discards a zero-cost salvage path for SKU→EditionId map omissions; strictly less safe than 2B for no benefit. **`EditionId` precedent already in fork:** `FFU.ArtifactScanner.psm1:205-208` reads `.EditionId` via `Get-WindowsImage -Index 1`.

### D3 — BCDBoot source (CORRECT-03) — ruling: **3A** (Adversary OVERTURN **REVERSED** by Referee)
- **D-09:** `Add-BootFiles` (`FFU.Imaging.psm1:1884`) must invoke the **ADK's** `bcdboot.exe`, not the bare host `bcdboot`. **Hard-fail the build if the ADK bcdboot cannot be located** — never silently fall back to the host binary.
- **D-10:** **Why (the decisive evidence):** upstream `6c0ee8a` / FFU ChangeLog v2603.2 states the ADK bcdboot is required because, post early-2025 cumulative updates, a build host carrying the **Windows UEFI CA 2023** cert stages **2023-signed** boot files that fail Secure Boot on target hardware lacking the 2023 cert. **The bcdboot binary's version determines which cert variant lands on the ESP** — this directly refutes the "bcdboot just copies from the applied image" model. Host bcdboot can silently ship FFUs that boot in the Hyper-V VM but fail on real fleet hardware.
- **D-11:** Resolve ADK bcdboot via the existing **FFU.ADK** path discovery (same ADK root used for DISM/Oscdimg; expected `…\Assessment and Deployment Kit\Deployment Tools\<arch>\BCDBoot\bcdboot.exe`, `<arch>` = `amd64`/`arm64` mirroring `FFU.ADK.psm1:~408`). **Verify the exact `BCDBoot` leaf folder name against a real ADK install before wiring** — a wrong subpath would hard-fail *every* build.
- **D-12:** **Add ADK bcdboot existence to `FFU.Preflight` ADK checks** so a missing/incorrect ADK fails *early* with actionable remediation (point to `-UpdateADK $true` / ADK install), not deep in imaging. The runtime hard-fail (D-09) remains the backstop.
- **D-13:** ⚠️ **ADK-version caveat (record + honor):** the 2011-cert benefit is tied to ADK *version* — Dec 2024 ADK `10.1.26100.2454` stages 2011 certs; a Nov 2025+ ADK defaults to 2023 certs. Pinning to "ADK bcdboot" is the upstream-blessed behavior, but the determinism depends on the installed ADK version. A future ADK bump must be a conscious decision, not a silent regression.
- **Rejected:** 3B (host fallback + warning) — re-introduces the exact bug being fixed; a `WriteLog` warning cannot save an unattended ThreadJob build from producing an unbootable artifact. The ADK is already a hard, pre-flight-validated dependency, so requiring ADK bcdboot adds no new dependency burden.

### D4 — LTSC year→release normalization (CORRECT-02) — ruling: **mapping + central, dedicated var** (Adversary UPHOLD confirmed)
- **D-14:** Normalization mapping (gate on `$isLTSC`):

  | Input year | LTSC fact | Normalize → |
  |---|---|---|
  | 2016 | Win10 LTSB 1607 | 10 |
  | 2019 | Win10 LTSC 1809 | 10 *(LTSC only)* |
  | 2021 | Win10 LTSC 21H2 | 10 |
  | 2024 | Win11 LTSC 24H2 | 11 |
  | 2016/2019/2022/2025 when `installationType='Server'` | Server year | **keep as-is** (Dell maps `W14/W19/W22/W25`, `FFU.Drivers.psm1:~2552-2562`) |

- **D-15:** **The 2019 collision is disambiguated by `$isLTSC`, never by the year.** `$installationType='Server'` (SKU `Standard*`/`Datacenter*`, `BuildFFUVM.ps1:2388`) and `$isLTSC` (SKU `*LTS*`, ~2400-2407) are **mutually exclusive** — no SKU is both — so gating the `2019→10` remap on `$isLTSC` leaves Server 2019 (→1809, Dell `W19`) untouched. **Never remap when `installationType -eq 'Server'`.**
- **D-16:** Normalize **once at the single driver-dispatch choke point** (`BuildFFUVM.ps1:~3165-3193`, where `-WindowsRelease` fans out to all 9 OEM providers), placed *after* `$isLTSC` is established (~2407), into a **dedicated `$driverWindowsRelease`**. **Do NOT clobber the global `$WindowsRelease`** — it is load-bearing for FFU naming (`{WindowsRelease}` placeholder ~85), the release→SKU validation map (~955-966), MSRT naming (~3587), VHDX cache keys, and the Server `$WindowsVersion` switch (~2391-2396).
- **D-17:** The bug is real and reachable: `[int]$WindowsRelease = 11` has **no `[ValidateSet]`** (`BuildFFUVM.ps1:415`); `2021`/`2024` are valid `$releaseToSKUMapping` keys (~960/962); the dispatch passes the value straight through, yielding `Win2021`/`Win2024` (HP `"Win$WindowsRelease"` ~1483; Lenovo `"_Win$WindowsRelease"` ~2113) and Dell's `else → W22` default — all wrong.
- **Rejected:** 4-PerProvider (normalize inside each OEM provider) — duplicates the gated mapping across 9+ `[int]$WindowsRelease` providers, drift-prone, each must independently re-derive the 2019 collision rule.

### Claude's Discretion (for researcher/planner)
- Exact shape of the SKU→EditionId map (hashtable vs lookup function) and where it lives (FFU.Imaging vs a shared FFU.Core helper) — but completeness is non-negotiable (D-06).
- The precise mechanism for propagating the selected edition back through the `Get-Index` caller in D-04 (return a richer object vs an out-param vs reassigning `$WindowsSKU` at the call site) — research the cleanest fit.
- Whether the ADK bcdboot resolution gets a small wrapper in FFU.ADK or is resolved inline in `Add-BootFiles` (it needs an arch-aware ADK path either way).
- Unit-test surface: `Get-Index` with mocked `Get-WindowsImage` (EditionId/InstallationType paths + ambiguous-vs-single fallback), the year-normalization as a pure function (LTSC vs Server 2019), and SKU→EditionId map coverage. Real-media / Secure-Boot-2023-hardware paths are human-UAT only.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scoping basis (milestone)
- `.planning/reports/upstream-sync-verdict-2026-06-25.md` — adversarial PORT/ADAPT verdict; Phase 51 = P1 Correctness bucket: T1-1/`5aaa1ad`, T1-3/`04dfb5f`, T1-4/`6c0ee8a`, T2-1/`b2a7ef5`.
- `.planning/REQUIREMENTS.md` — CORRECT-01..04 definitions with upstream commit IDs.
- `.planning/ROADMAP.md` §"Phase 51: Capture/Boot Correctness" — goal + 4 success criteria.

### Image index selection (D1 + D2) — the Get-Index rewrite
- `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` — `Get-Index` (~490-587): substring derivation (535/539/544), exact-`-eq` match (551), the relevant-index filter (560), the `Read-Host`/`while($true)` loop to DELETE (562-585). `$installationType` already reaches imaging at ~2588.
- `FFUDevelopment/BuildFFUVM.ps1` — `Get-Index` caller (~4403-4404, returns `[int]` only, `$WindowsSKU` never reassigned); SKU validation (legality-only, ~960-966); `$clientSKUs`/`$LTSCSKUs`/`$ServerSKUs` friendly-name lists (~926-963); the `$WindowsSKU` downstream consumers to propagate into (~4087, 4339, 4643, 4698, 5192, 5301, 5340, 5636, 5696).
- `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1` (~205-208) — existing `Get-WindowsImage -Index 1` / `.EditionId` precedent to reuse.

### Boot files (D3)
- `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` — `Add-BootFiles` (~1874-1886, the bare `bcdboot` call at 1884).
- `FFUDevelopment/Modules/FFU.ADK/FFU.ADK.psm1` — ADK path resolution + arch-tool validation (`Deployment Tools\<arch>\…`, ~408); add bcdboot resolution here or reuse the root.
- `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` — ADK pre-flight checks; add ADK-bcdboot existence (D-12).

### Driver year normalization (D4)
- `FFUDevelopment/BuildFFUVM.ps1` — `[int]$WindowsRelease` param (no ValidateSet, 415); `$releaseToSKUMapping` (~955-964, incl. 2021/2024 LTSC keys); `$installationType` (2388) and `$isLTSC` (~2400-2407) derivation; driver dispatch choke point (~3165-3193); Dell client/server split (`-le 11` ~2405/2549; server osCodes `W14/W19/W22/W25` ~2552-2562).
- `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` — all 9 OEM providers' `[int]$WindowsRelease` params; HP `"Win$WindowsRelease"` (~1483), Lenovo `"_Win$WindowsRelease"` (~2113), Samsung/Acer release strings.

### Prior context (decisions carried forward)
- `.planning/STATE.md` §"Research Flags for Planning" — the CORRECT-01 three-consumer trace flag.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FFU.ArtifactScanner` `.EditionId` read (`Get-WindowsImage -Index 1` → `.EditionId`) — proves the EditionId approach is feasible in-repo; reuse the pattern in `Get-Index` (D-05).
- `$installationType` (Client/Server) and `$isLTSC` are already computed in `BuildFFUVM.ps1` (~2388/2407) — reuse them as the disambiguators for D-07 (InstallationType) and D-15 (LTSC-vs-Server 2019).
- `FFU.ADK` path discovery — the existing ADK root resolution for Oscdimg/DISM is the model for locating ADK bcdboot (D-11).
- The single driver-dispatch choke point (~3165-3193) — one place to inject `$driverWindowsRelease` for D-16.

### Established Patterns
- ThreadJob-safe idioms are mandatory for all build-time code: `WriteLog` (not `Write-Host`), `[DateTime]::Now`, **no `Read-Host`** — this is *why* the D1 fallback loop is broken and must be deleted.
- Exact `Where-Object ... -eq` matching (FFU.Imaging.psm1:551) — the safe fallback tier for D-08.
- Dedicated/scoped variables over global mutation (D-16): `$WindowsRelease` is load-bearing across naming/cache/servicing; introduce `$driverWindowsRelease` rather than overwrite.

### Integration Points
- `Get-Index` ↔ its `BuildFFUVM.ps1` caller (~4404): the propagation seam for D-04 — the selected edition must flow from `Get-Index` back into the `$WindowsSKU` consumers.
- `Add-BootFiles` ↔ FFU.ADK: arch-aware ADK bcdboot path (D-11).
- `Add-BootFiles` ↔ FFU.Preflight: early ADK-bcdboot validation (D-12).
- Driver dispatch ↔ all 9 OEM providers: normalized `$driverWindowsRelease` (D-16).

</code_context>

<specifics>
## Specific Ideas

- **D1 and D2 are ONE implementation unit** — both rewrite `Get-Index`, share the "WriteLog available editions" requirement, and the SKU→EditionId map (D-06) is what makes D2 work and reduces how often the D1 fallback fires. Plan them together; D2 lands first (or together) so the D1 hard-fail only triggers on genuine media/SKU mismatches, never on the locale false-negatives D2 eliminates.
- **D3 is the one to get exactly right** — it's a silent, deploy-time, high-blast-radius failure (boots in VM, fails on fleet). The verification surface is mostly human-UAT (real Secure-Boot-2023 hardware), so the code must be conservative: hard-fail loudly rather than ship a maybe-unbootable image.
- The whole phase is the P1 must-ship core of v1.12.0 — every later phase (52-58) depends on it.

</specifics>

<deferred>
## Deferred Ideas

- Normalizing the **global** `$WindowsRelease` (so LTSC artifacts are also *named*/*cached* by their base 10/11) — deliberately NOT done in Phase 51 (D-16 scopes to `$driverWindowsRelease` only); broader blast radius, a separate deliberate decision if ever wanted.
- LTSC 2016 exercise confirmation — verify the fork actually drives WindowsRelease=2016 LTSC before relying on that mapping row; harmless but unverified.
- T1-7 (`42b0b0c`) Win10 LTSC in-VM cumulative update — DEFERRED at milestone scoping (verify-first; only if the fork's offline LTSC servicing is proven to fail on 1607/1809). Not Phase 51 scope.

None beyond the above — discussion stayed within phase scope.

</deferred>

---

*Phase: 51-capture-boot-correctness*
*Context gathered: 2026-06-26*
