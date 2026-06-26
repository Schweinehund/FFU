# Upstream-Sync Adversarial Review Verdict — 2026-06-25

**Method:** 4 parallel Porter agents (one per tier) argued FOR porting each candidate from
`upstream-sync-audit-2026-06-21.md`, verifying every claim against live fork code. A single
Skeptic adversary (2× wrong-dismissal penalty) challenged each PORT. A Referee issued final
verdicts, spot-checking contested items against fork source.

**Baseline:** `upstream/UI` unchanged since the 2026-06-21 audit (still 158 commits since fork
base `1130a83`). v1.10.x already ported T1-5, T1-6, T2-3, T2-2a, T2-2b.

**Contested rulings (Skeptic won, Referee upheld):**
- T1-2 8-OEM deploy detection: CRITICAL → **P2** (fork 3-tier deploy fallback already matches new OEMs; loses SystemID precision only, no failed artifact)
- T4-S3 select-all/save: data-loss CRITICAL → **P2** (build/download path filter-safe via `allDriverModels`; only `Save-DriversJson` leaks)
- T2-9 param capture naming: PORT → **ADAPT** (two `Start-Sleep 60` are documented CBS/CSI corruption guards; must preserve + replicate hive DisplayVersion logic)

## Final verdict

### PORT
| ID | Commit | Change | Priority | Effort |
|----|--------|--------|----------|--------|
| T1-1 | 5aaa1ad | SKU refresh after fallback image selection | P1 | M |
| T1-3 | 04dfb5f | LTSC driver year normalization (2019/2021/2024 → 10/11) | P1 | S |
| T1-4 | 6c0ee8a | ADK BCDBoot (Secure Boot 2023 cert) | P1 | S |
| T2-1 | b2a7ef5 | Image index by EditionId/InstallationType | P1 | S-M |
| T4-S2 | b4305a1 | Fix sort-after-filter breaking Drivers filter (live bug) | P2 | S-M |
| T4-S3 | f09c989 | Save-DriversJson scoped to visible (data-loss in save path) | P2 | S |
| T4-S1 | dc801e9 | CopyDrivers requires BuildUSBDrive validation | P2 | S |
| T2-5 | 866fa25 | Surface driver matching via System SKU | P2 | M |
| T2-6 | 554964f | Cached MS/Surface driver download links | P2 | S-M |
| T2-8 | 27eebeb+d349e5e | OS-scoped update cache + prune stale MSUs | P2 | M |
| T2-11 | a8fecd1 | Optimize-Volume -ReTrim on capture drive | P2 | S |
| T3-3 | f1f1957 | Auto-generate ComputerName in Unattend XML | P2 | M |
| T4-8 | 42ed281 | Header checkbox alignment (bundle w/ T4-S3) | P3 | S |
| T5-5 | 9bacac8 | dirty.txt relative-path creation fix | P3 | S |
| T5-7 | 24c81c2 | Remove redundant Images dir in USBImagingToolCreator | P3 | S |

### ADAPT
| ID | Commit | Change | Priority | Effort |
|----|--------|--------|----------|--------|
| T1-2 | d6688de | 8-OEM deploy-time SystemID precision tier (ApplyFFU) | P2 | M |
| T2-9 | f838ef3 | Param-driven capture naming (preserve sleep guards) | P2 | M |
| T3-1 | 4a2d8e6 | DeviceNamingMode framework (FOUNDATION; config migration) | P2 | L |
| T3-2 | 38323e6 | SerialComputerNames CSV mode + UI editor (dep T3-1) | P2 | M |
| T3-4 | 7bd5dec | Custom unattend path x64/arm64 (wire USB-copy + audit-mode) | P2 | M |
| T2-2c | 417be73 | USB SerialNumber → UniqueId (config-breaking, migration) | P2 | M-L |
| T4-7 | 80147ed | ESD vs ISO radios (backend ready, not shell-dependent) | P2 | S-M |
| T4-2 | b28344d | Expandable sections (adapt to fork XAML) | P2 | M |
| T4-5 | d6361da | ListView auto column resize | P3 | M |
| T4-9 | eac8be3 | BYO app-list path UI control (backend ready) | P3 | S |
| T3-5 | 1ea1ef6 | Read-MenuSelection + `*` fallback (SURGICAL — protect NICE-02) | P3 | M |
| T3-6 | 82bac17/24f10b8/6b76f6b | Prompt mode / state fix / label (fold into T3-1/2) | P3 | S |
| T5-2 | 5374163 | Malformed-JSON backup/rebuild fallback (catch only) | P3 | S |
| T5-11 | 3d1a586 | Driver-cleanup helper with path guard | P3 | M |
| T5-6 | 2d6f6e5/5580824 | Silence robocopy/Format-Volume output | P3 | S |
| T2-7 | 7f10811 | Retain ESD option | P3 | S |

### DEFER (verify-first / experimental)
| ID | Commit | Change | Note |
|----|--------|--------|------|
| T1-7 | 42b0b0c | Win10 LTSC in-VM CU | Only if fork offline LTSC path proven to fail on 1607/1809 |
| T5-4 | 78212f0 | -EnableVMNetworking | Experimental upstream |

### SKIP
| ID | Commit | Reason |
|----|--------|--------|
| T4-1/T4-3/T4-4/T4-6 | 7678f61/98c1644/db04455/aca968c | Fluent/sidebar shell — interlocking rewrite vs fork TabControl; separate future project (user-confirmed 2026-06-25) |
| T2-4 | 2273cff | Pure perf, no correctness gain |
| T2-10 | a8e2ab9/a8fecd1 | ADK detection already exe/path-based in fork |
| T5-1 | c135ad0 | WOULD-REGRESS fork's hardened VM-WinPE + VMware capture arch |
| T5-3 | 5ca5312 | Fork intentionally gates Office-on-ARM64 off |
| T5-8 | 422bc33 | Fork has .session/checkpoint equivalent |
| T5-9 | db22c18 | Fork's arch branch works; upstream change unverified |
| T5-10 | 9a59b9f/3cb4003 | Cosmetic |
| T5-12 | 11b3e12 | WOULD-REGRESS fork CatalogIndexPC (targets old CatalogPC.cab path) |

## Milestone scope (v1.12.0, user-confirmed buckets, shell skipped)
- **P1 Correctness:** T1-1, T1-3, T1-4, T2-1
- **P2 Driver/UI bugs:** T4-S2, T4-S3, T4-S1, T4-8, T2-5, T2-6, T2-11
- **P2 Cache + naming:** T2-8, T2-9, T1-2
- **Tier-3 Device-Naming family (atomic):** T3-1 → T3-2 → T3-3 → T3-4 → T3-6, T3-5 surgical, + T2-2c
- **Shell-independent UI:** T4-7, T4-2, T4-5, T4-9
- **Cleanup:** T5-2, T5-5, T5-6, T5-7, T5-11
- **Deferred:** T1-7, T5-4 · **Skipped:** Tier-4 shell + the SKIP table above
