# Phase 51: Capture/Boot Correctness - Research

**Researched:** 2026-06-26
**Domain:** PowerShell / DISM image index selection, ADK toolchain, OEM driver dispatch, Windows edition metadata
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D1 — Fallback selection UX (CORRECT-01) — ruling: 1A-conditional**
- D-01: Delete the `Read-Host` / `while($true)` loop in `Get-Index` (FFU.Imaging.psm1:562-585) entirely — it hangs under ThreadJob.
- D-02: Exactly one relevant candidate (filter `(10|11|2016|2019|202\d)`) → auto-select non-interactively AND propagate the selected edition downstream.
- D-03: Two or more candidates → `WriteLog` full available-editions list, then `throw`. Editions list must land in the build log (ThreadJob error stream is unreliable).
- D-04: `Get-Index` returns only `[int]` today. Propagation must update the value consumed by: FFU naming (`Get-ShortenedWindowsSKU` → `New-FFUFileName`, ~5340), VHDX cache key writes (~4643) and reads (~4087), and the servicing/build-context hashes (~4339, 4698, 5192, 5301, 5636, 5696).

**D2 — Image index selection (CORRECT-04) — ruling: 2B**
- D-05: Select index by `EditionId` (primary) → exact `ImageName -eq` (fallback) → fail. Replace all `Substring(0,10)/(0,19)` localized derivation.
- D-06: SKU→EditionId map is MANDATORY and must cover every entry in `$clientSKUs`, `$LTSCSKUs`, `$ServerSKUs`. Map completeness is a test gate.
- D-07: Use `InstallationType` (Client/Server) to prevent client edition matching on server media.
- D-08: Exact `ImageName -eq` fallback is safe and must be retained as a zero-cost salvage path for map gaps.

**D3 — BCDBoot source (CORRECT-03) — ruling: 3A**
- D-09: `Add-BootFiles` must invoke the ADK's `bcdboot.exe`. Hard-fail if not found — never fall back to host bcdboot.
- D-10: Why: post early-2025 CU, build hosts carry the Windows UEFI CA 2023 cert; bcdboot binary version determines which cert variant lands on the ESP. ADK's Dec 2024 build (`10.1.26100.2454`) stages 2011 certs; host bcdboot can silently produce FFUs that boot in Hyper-V but fail on fleet hardware.
- D-11: Resolve ADK bcdboot via existing FFU.ADK path discovery. Expected path: `{ADKPath}Assessment and Deployment Kit\Deployment Tools\<amd64|arm64>\BCDBoot\bcdboot.exe`. Verify leaf folder name before wiring.
- D-12: Add ADK bcdboot existence to `FFU.Preflight` ADK checks (early fail with remediation guidance).
- D-13: ADK version caveat: Dec 2024 ADK `10.1.26100.2454` stages 2011 certs; Nov 2025+ ADK defaults to 2023 certs. Pinning to ADK bcdboot is upstream-blessed, but determinism depends on installed ADK version.

**D4 — LTSC year→release normalization (CORRECT-02) — ruling: mapping + central dedicated var**
- D-14: Mapping (gate on `$isLTSC`): 2016→10, 2019→10 (LTSC only), 2021→10, 2024→11. Server years stay as-is.
- D-15: 2019 collision disambiguated by `$isLTSC`, never by year. Server 2019 never remapped. Mutually exclusive: no SKU is both Server and LTSC.
- D-16: Normalize once at the single driver-dispatch choke point (BuildFFUVM.ps1 ~3165-3193) into a dedicated `$driverWindowsRelease`. Do NOT clobber global `$WindowsRelease`.
- D-17: Bug is real: `[int]$WindowsRelease = 2021`/`2024` yields `Win2021`/`Win2024` (HP, Lenovo) and Dell `else → W22` — all wrong.

### Claude's Discretion
- Exact shape of SKU→EditionId map (hashtable vs switch) and where it lives.
- Mechanism for propagating selected edition back through `Get-Index` caller (return richer object vs out-param vs call-site reassignment).
- Whether ADK bcdboot resolution gets a small wrapper in FFU.ADK or is resolved inline in `Add-BootFiles`.
- Unit-test surface: what is unit-testable vs human-UAT only.

### Deferred Ideas (OUT OF SCOPE)
- Normalizing global `$WindowsRelease` for LTSC artifact naming/caching.
- LTSC 2016 exercise confirmation.
- T1-7 (`42b0b0c`) Win10 LTSC in-VM cumulative update.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORRECT-01 | When exact SKU not present and fallback image selected, FFU is named/cached/serviced as the *selected* edition | Propagation via `Get-WindowsImageSelection` rich return + caller update at BuildFFUVM.ps1:4404 |
| CORRECT-02 | LTSC builds (2019/2021/2024) can download OEM drivers without release-year validation error | `Get-EffectiveDriverWindowsRelease` at both driver dispatch sites |
| CORRECT-03 | Captured images boot on Secure Boot 2023-cert devices via ADK BCDBoot | `Add-BootFiles` ADK path fix + preflight check in `Test-FFUADK` |
| CORRECT-04 | Correct edition captured from non-English/multi-edition media via EditionId/InstallationType | `Get-WindowsImageSelection` SKU→EditionId switch + per-index `Get-WindowsImage -Index N` |

</phase_requirements>

---

## Summary

This phase ports four correctness fixes from upstream `rbalsleyMSFT/FFU` branch `UI` into the fork's modular/ThreadJob architecture. All four fixes have been verified against the upstream commit diffs (fetched live via GitHub API) and cross-checked against the fork's current code. Implementation decisions are locked via adversarial review in CONTEXT.md; research confirms the HOW.

**CORRECT-01 and CORRECT-04 are one implementation unit.** Both rewrite `Get-Index` in `FFU.Imaging.psm1`: CORRECT-04 changes how the correct index is found (EditionId-based), and CORRECT-01 propagates the resulting edition back into the build context. The SKU→EditionId map (D-06) is what enables both. The upstream commit `5aaa1ad` renames `Get-Index` to `Get-WindowsImageSelection` and adds two companion functions (`Get-ResolvedWindowsSKUFromImage`, `Get-WindowsTargetRuntimeState`); this research confirms the exact signatures and how the fork adapts them for ThreadJob (deleting the Read-Host prompt entirely per D-01).

**CORRECT-03** requires the exact ADK bcdboot.exe path: `{ADKRoot}Assessment and Deployment Kit\Deployment Tools\{amd64|arm64}\BCDBoot\bcdboot.exe`. The leaf folder is `BCDBoot` (PascalCase) — confirmed from the upstream commit `6c0ee8a` diff and cross-checked against Microsoft documentation. The fork already has `$adkPath` in scope at the `Add-BootFiles` call site; the fix is adding two mandatory params and a pre-check.

**CORRECT-02** is a standalone function `Get-EffectiveDriverWindowsRelease` injected at both driver dispatch sites in BuildFFUVM.ps1. The upstream commit `04dfb5f` provides the exact function and injection pattern. Server SKUs (Standard/Datacenter) are correctly unaffected because their friendly name does not contain `*LTS*`.

**Primary recommendation:** Port as four sequential tasks sharing a single implementation wave for CORRECT-01+04, then CORRECT-03, then CORRECT-02. Sequence: (a) Get-WindowsImageSelection rewrite, (b) caller propagation, (c) bcdboot fix + preflight, (d) LTSC normalization, (e) tests + version bumps.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Image index selection (CORRECT-04) | Module Layer (FFU.Imaging) | Build Orchestration (BuildFFUVM.ps1 caller) | DISM image inspection is an imaging concern; caller owns build-context propagation |
| Edition propagation after fallback (CORRECT-01) | Build Orchestration (BuildFFUVM.ps1) | Module Layer (FFU.Imaging returns rich object) | `$WindowsSKU` and dependent vars are orchestrator state, not module state |
| ADK bcdboot path resolution (CORRECT-03) | Module Layer (FFU.Imaging.Add-BootFiles) | Module Layer (FFU.Preflight.Test-FFUADK) | Boot file writing is imaging; early validation belongs in preflight |
| LTSC year normalization (CORRECT-02) | Build Orchestration (BuildFFUVM.ps1 dispatch site) | — | Normalization touches build orchestration variables (`$WindowsRelease`) not OEM provider internals |
| ADK root discovery | Module Layer (FFU.ADK) | — | Already resolved via `Test-ADKPrerequisites` returning `ADKPath`; fork reuses `$adkPath` |

---

## Standard Stack

No new external packages for this phase. All changes are in-repo PowerShell and use existing in-box cmdlets.

### Core Tools / Cmdlets Used

| Tool | Source | Purpose | Status |
|------|--------|---------|--------|
| `Get-WindowsImage` (DISM) | Windows DISM module | Returns `EditionId`, `InstallationType`, `ImageName`, `ImageSize` per index | Already used in ArtifactScanner (`FFU.ArtifactScanner.psm1:205`) [VERIFIED: codebase grep] |
| `Get-WindowsImage -Index N` | Windows DISM module | Fetches per-image metadata (EditionId, InstallationType) | Required per `b2a7ef5` diff pattern [VERIFIED: codebase grep - ArtifactScanner precedent] |
| `Test-Path -PathType Leaf` | PowerShell | Validates bcdboot.exe existence | Existing pattern in FFU.ADK and FFU.Preflight [VERIFIED: codebase grep] |
| `Join-Path` | PowerShell | Build ADK bcdboot path | Used already throughout for ADK path construction [VERIFIED: codebase grep] |

### Package Legitimacy Audit

This phase installs no external packages. Section not applicable.

---

## Architecture Patterns

### System Architecture Diagram

```
CORRECT-01+04 (Get-WindowsImageSelection in FFU.Imaging):
 BuildFFUVM.ps1
    │
    ├─ $WindowsSKU, $WindowsRelease ──► Get-WindowsImageSelection (FFU.Imaging.psm1)
    │                                        │
    │                                        ├─ SKU→EditionId map (switch)
    │                                        ├─ Get-WindowsImage (no -Index) → list
    │                                        ├─ Get-WindowsImage -Index N → EditionId/InstallationType per image
    │                                        ├─ Match by EditionId + InstallationType
    │                                        ├─ Fallback: exact ImageName -eq
    │                                        ├─ Fallback-of-last-resort: 1 candidate→auto-select, ≥2→throw
    │                                        └─ Returns PSCustomObject {ImageIndex, EditionId, ResolvedWindowsSKU, ...}
    │
    ├─ $WindowsSKU ← $selection.ResolvedWindowsSKU
    ├─ Recalculate installationType / WindowsVersion / isLTSC via Get-WindowsTargetRuntimeState
    └─ $WindowsSKU propagates into: naming (~5340), VHDX cache write (~4643) / read (~4087), checkpoints (~4339, 4698, 5192, 5301, 5636, 5696)

CORRECT-03 (ADK bcdboot in FFU.Imaging):
 BuildFFUVM.ps1
    ├─ $adkPath (from Test-ADKPrerequisites ~3217) ──────────────────────────────────────┐
    ├─ $WindowsArch ──────────────────────────────────────────────────────────────────────┤
    │                                                                                      ▼
    └─ Add-BootFiles (FFU.Imaging.psm1:1884)
          ├─ Resolves bcdboot path: {ADKPath}\...\{amd64|arm64}\BCDBoot\bcdboot.exe
          ├─ Hard-fails if not found
          └─ Invokes via Invoke-Process

 FFU.Preflight (Test-FFUADK):
    ├─ Existing: checks DandISetEnv.bat, oscdimg.exe, boot files
    └─ New: check {ADKPath}\...\BCDBoot\bcdboot.exe → New-FFUCheckResult 'Failed' if missing

CORRECT-02 (LTSC normalization in BuildFFUVM.ps1):
 $WindowsRelease (2016/2019/2021/2024) ──► Get-EffectiveDriverWindowsRelease
 $WindowsSKU (*LTS* guard)                       │
                                                  ├─ LTSC client: 2016/2019/2021→10, 2024→11
                                                  └─ All other: pass-through
 ↓
 $driverWindowsRelease → driver dispatch (HP, Microsoft, Lenovo, Dell, and driversJsonPath path)
```

### Recommended Project Structure (changes only)

```
FFUDevelopment/
├── Modules/
│   ├── FFU.Imaging/
│   │   └── FFU.Imaging.psm1          # Get-WindowsImageSelection (replaces Get-Index)
│   │                                  # Get-ResolvedWindowsSKUFromImage (new)
│   │                                  # Add-BootFiles (add AdkPath + WindowsArch params)
│   └── FFU.Preflight/
│       └── FFU.Preflight.psm1        # Test-FFUADK: add bcdboot existence check
├── BuildFFUVM.ps1                     # Get-WindowsTargetRuntimeState (new script function)
│                                      # Get-EffectiveDriverWindowsRelease (new script function)
│                                      # Caller update at line 4404 (SKU propagation)
│                                      # Add-BootFiles call update at line 4444 (pass ADK path)
│                                      # Driver dispatch: inject $driverWindowsRelease
└── Tests/
    └── Test-Phase51Correctness.ps1   # New test file for unit-testable surfaces
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| EditionId lookup per image | Custom WIM reader or INF parser | `Get-WindowsImage -Index N` (DISM) | DISM is the authoritative source; ArtifactScanner.psm1:205 confirms the pattern works |
| ADK root discovery | Re-read registry in `Add-BootFiles` | `$adkPath` already in BuildFFUVM.ps1 scope from `Test-ADKPrerequisites` (~3217) | Single source of truth already established; no need for a second registry read |
| InstallationType derivation | Parse `$WindowsSKU` manually again | `Get-WindowsTargetRuntimeState` (new helper function) | The upstream already solved this; reuse the same function for both initial setup and post-selection recalculation |

**Key insight:** All four fixes are small, targeted changes to existing logic flows. The upstream commit diffs are short and focused; resist scope creep.

---

## Upstream Commit Evidence (Verified)

All four commits were fetched live from `rbalsleyMSFT/FFU` via `gh api`. [VERIFIED: live GitHub API call]

### Commit `b2a7ef5` — CORRECT-04 (EditionId index selection)
**In upstream, this is still in the monolith `BuildFFUVM.ps1`.** In the fork, `Get-Index` lives in `FFU.Imaging.psm1`, so the port goes there.

Key diff from upstream (verbatim — confirmed):
```powershell
# SKU→EditionId map (switch statement inside Get-WindowsImageSelection / Get-Index rewrite):
$editionIdCandidates = switch ($normalizedWindowsSKU) {
    'Home'                       { @('Core') }
    'Home N'                     { @('CoreN') }
    'Home Single Language'       { @('CoreSingleLanguage') }
    'Education'                  { @('Education') }
    'Education N'                { @('EducationN') }
    'Pro'                        { @('Professional') }
    'Pro N'                      { @('ProfessionalN') }
    'Pro Education'              { @('ProfessionalEducation') }
    'Pro Education N'            { @('ProfessionalEducationN') }
    'Pro for Workstations'       { @('ProfessionalWorkstation') }
    'Pro N for Workstations'     { @('ProfessionalWorkstationN') }
    'Enterprise'                 { @('Enterprise') }
    'Enterprise N'               { @('EnterpriseN') }
    'Enterprise LTSC'            { @('EnterpriseS') }
    'Enterprise 2016 LTSB'       { @('EnterpriseS') }
    'Enterprise N LTSC'          { @('EnterpriseSN') }
    'Enterprise N 2016 LTSB'     { @('EnterpriseSN') }
    'IoT Enterprise LTSC'        { @('IoTEnterpriseS') }
    'IoT Enterprise N LTSC'      { @('IoTEnterpriseSN') }
    'Standard'                   { @('ServerStandard') }
    'Standard (Desktop Experience)' { @('ServerStandard') }
    'Datacenter'                 { @('ServerDatacenter') }
    'Datacenter (Desktop Experience)' { @('ServerDatacenter') }
    default                      { @() }
}
# InstallationType disambiguation for Server Desktop Experience vs Core:
$preferredInstallationType = $null
if ($normalizedWindowsSKU -in @('Standard', 'Standard (Desktop Experience)', 'Datacenter', 'Datacenter (Desktop Experience)')) {
    $preferredInstallationType = if ($isDesktopExperienceRequested) { 'Server' } else { 'Server Core' }
}
```
[VERIFIED: upstream commit b2a7ef5 diff via GitHub API]

**Fork caveat:** `'CoreSingleLanguage'`, `'EducationN'`, `'ProfessionalN'`, etc. are EditionId aliases also present in the switch. The fork's `$clientSKUs` does NOT include `'CoreSingleLanguage'` — it uses `'Home Single Language'`. The switch covers BOTH forms, ensuring map completeness.

**FORK DEVIATION FROM UPSTREAM (b2a7ef5):** Upstream still retains the `Read-Host`/`while($true)` loop as a last resort. **The fork MUST delete this** (D-01) — it hangs in ThreadJob. Replace with: 1 candidate → auto-select, ≥2 → throw.

### Commit `5aaa1ad` — CORRECT-01 (SKU refresh after fallback)
Key diff from upstream (verbatim — confirmed):

```powershell
# 1. Get-WindowsImageSelection now returns rich PSCustomObject (not just int):
return $bestMatch   # was: return $bestMatch.ImageIndex

# 2. ResolvedWindowsSKU is computed per-image via Get-ResolvedWindowsSKUFromImage:
[pscustomobject]@{
    ImageIndex        = $details.ImageIndex
    ImageName         = $details.ImageName
    ImageSize         = $details.ImageSize
    EditionId         = $details.EditionId
    InstallationType  = $details.InstallationType
    ResolvedWindowsSKU = Get-ResolvedWindowsSKUFromImage -EditionId $details.EditionId `
                         -InstallationType $details.InstallationType -ImageName $details.ImageName `
                         -WindowsRelease $WindowsRelease
}

# 3. Caller at ~4404 propagates the selection:
$windowsImageSelection = Get-WindowsImageSelection -WindowsImagePath $wimPath -WindowsSKU $WindowsSKU -WindowsRelease $WindowsRelease
$index = $windowsImageSelection.ImageIndex
if (-not [string]::IsNullOrWhiteSpace($windowsImageSelection.ResolvedWindowsSKU)) {
    $WindowsSKU = $windowsImageSelection.ResolvedWindowsSKU
    $windowsTargetRuntimeState = Get-WindowsTargetRuntimeState -WindowsRelease $WindowsRelease `
        -WindowsSKU $WindowsSKU -CurrentWindowsVersion $WindowsVersion -UpdateLatestCU:$UpdateLatestCU
    $installationType = $windowsTargetRuntimeState.InstallationType
    $WindowsVersion   = $windowsTargetRuntimeState.WindowsVersion
    $isLTSC           = $windowsTargetRuntimeState.IsLTSC
    $isWindows10LtscClient = $windowsTargetRuntimeState.IsWindows10LtscClient
    $installLatestCuInVm   = $windowsTargetRuntimeState.InstallLatestCuInVm
}
```
[VERIFIED: upstream commit 5aaa1ad diff via GitHub API]

**Fork-specific adaptation:** `Get-WindowsTargetRuntimeState` in the fork is added as a script-level function in BuildFFUVM.ps1. It does NOT replace the existing initial installationType/isLTSC computation (lines 2388-2408); it is called ONLY at the post-selection update site (~4404). This minimizes blast radius.

**Reverse EditionId→SKU map** (`Get-ResolvedWindowsSKUFromImage`) from upstream (verbatim):
```powershell
switch ($EditionId) {
    'Core'                  { return 'Home' }
    'CoreN'                 { return 'Home N' }
    'CoreSingleLanguage'    { return 'Home Single Language' }
    'Education'             { return 'Education' }
    'EducationN'            { return 'Education N' }
    'Professional'          { return 'Pro' }
    'ProfessionalN'         { return 'Pro N' }
    'ProfessionalEducation' { return 'Pro Education' }
    'ProfessionalEducationN' { return 'Pro Education N' }
    'ProfessionalWorkstation'  { return 'Pro for Workstations' }
    'ProfessionalWorkstationN' { return 'Pro N for Workstations' }
    'Enterprise'            { return 'Enterprise' }
    'EnterpriseN'           { return 'Enterprise N' }
    'EnterpriseS'           {
        if ($WindowsRelease -eq 2016 -or $ImageName -match 'LTSB') { return 'Enterprise 2016 LTSB' }
        return 'Enterprise LTSC'
    }
    'EnterpriseSN'          {
        if ($WindowsRelease -eq 2016 -or $ImageName -match 'LTSB') { return 'Enterprise N 2016 LTSB' }
        return 'Enterprise N LTSC'
    }
    'IoTEnterpriseS'        { return 'IoT Enterprise LTSC' }
    'IoTEnterpriseSN'       { return 'IoT Enterprise N LTSC' }
    'ServerStandard'        {
        if ($normalizedInstallationType -eq 'Server') { return 'Standard (Desktop Experience)' }
        return 'Standard'
    }
    'ServerDatacenter'      {
        if ($normalizedInstallationType -eq 'Server') { return 'Datacenter (Desktop Experience)' }
        return 'Datacenter'
    }
}
return $null
```
[VERIFIED: upstream commit 5aaa1ad diff via GitHub API]

### Commit `6c0ee8a` — CORRECT-03 (ADK bcdboot)
```powershell
# Add-BootFiles new params and body (from upstream diff):
param(
    [Parameter(Mandatory = $true)] [string]$OsPartitionDriveLetter,
    [Parameter(Mandatory = $true)] [string]$SystemPartitionDriveLetter,
    [Parameter(Mandatory = $true)] [string]$AdkPath,
    [Parameter(Mandatory = $true)]
    [ValidateSet('x86', 'x64', 'arm64')]
    [string]$WindowsArch,
    [string]$FirmwareType = 'UEFI'
)

$bcdBootArchitecture = if ($WindowsArch -ieq 'arm64') { 'arm64' } else { 'amd64' }
$bcdBootPath = Join-Path $AdkPath "Assessment and Deployment Kit\Deployment Tools\$bcdBootArchitecture\BCDBoot\bcdboot.exe"

if (-not (Test-Path -Path $bcdBootPath)) {
    throw "ADK BCDBoot was not found at $bcdBootPath"
}

Invoke-Process $bcdBootPath "$($OsPartitionDriveLetter):\Windows /S $($SystemPartitionDriveLetter): /F $FirmwareType" | Out-Null
```
[VERIFIED: upstream commit 6c0ee8a diff via GitHub API]

**ADK leaf folder name confirmed: `BCDBoot` (PascalCase).** [VERIFIED: upstream diff + Microsoft documentation cross-reference]

**Fork call site** (BuildFFUVM.ps1:4444 → new):
```powershell
Add-BootFiles -OsPartitionDriveLetter $osPartitionDriveLetter `
              -SystemPartitionDriveLetter $systemPartitionDriveLetter[1] `
              -AdkPath $adkPath `
              -WindowsArch $WindowsArch
```
`$adkPath` is already in scope at line 4444 — it is set at line 3217 (`$adkPath = $adkValidation.ADKPath`). No new ADK lookup needed. [VERIFIED: BuildFFUVM.ps1 grep - `$adkPath` established at line 3217]

**ADK version detection:** The `Test-FFUADK` already reads ADK version from Uninstall registry at lines 1116-1126 and stores it in `$adkVersion`. No new code needed. The version is surfaced in the check result details. Per D-13, the planner should add a `WriteLog "ADK version: $($adkResult.Details.ADKVersion)"` message during `Add-BootFiles` as a diagnostic log.

### Commit `04dfb5f` — CORRECT-02 (LTSC normalization)
```powershell
# New function in BuildFFUVM.ps1 (from upstream diff):
function Get-EffectiveDriverWindowsRelease {
    param(
        [Parameter(Mandatory = $true)] [int]$WindowsRelease,
        [string]$WindowsSKU
    )
    if (-not [string]::IsNullOrWhiteSpace($WindowsSKU) -and $WindowsSKU -like '*LTS*') {
        if ($WindowsRelease -in 2016, 2019, 2021) { return 10 }
        if ($WindowsRelease -eq 2024)             { return 11 }
    }
    return $WindowsRelease
}
```
[VERIFIED: upstream commit 04dfb5f diff via GitHub API]

**Two injection sites in the fork (both need `$driverWindowsRelease`):**

1. **driversJsonPath path (~2999):**
```powershell
# Before: WindowsRelease = $WindowsRelease
# After:
$driverWindowsRelease = Get-EffectiveDriverWindowsRelease -WindowsRelease $WindowsRelease -WindowsSKU $WindowsSKU
if ($driverWindowsRelease -ne $WindowsRelease) {
    WriteLog "Normalized WindowsRelease for drivers JSON processing from $WindowsRelease to $driverWindowsRelease (SKU='$WindowsSKU')."
}
$taskArguments = @{
    DriversFolder  = $DriversFolder
    WindowsRelease = $driverWindowsRelease   # was $WindowsRelease
    ...
}
```

2. **Single-model path (~3165-3193):**
```powershell
# Before Invoke-BuildPhase block:
$driverWindowsRelease = Get-EffectiveDriverWindowsRelease -WindowsRelease $WindowsRelease -WindowsSKU $WindowsSKU
if ($driverWindowsRelease -ne $WindowsRelease) {
    WriteLog "Normalized WindowsRelease for single-model driver processing from $WindowsRelease to $driverWindowsRelease (SKU='$WindowsSKU')."
}
# Inside Invoke-BuildPhase block, replace $WindowsRelease → $driverWindowsRelease for driver calls:
Get-HPDrivers ... -WindowsRelease $driverWindowsRelease ...
Get-MicrosoftDrivers ... -WindowsRelease $driverWindowsRelease ...
Get-LenovoDrivers ... -WindowsRelease $driverWindowsRelease ...
Get-DellDrivers ... -WindowsRelease $driverWindowsRelease ...
```

**Scope note:** `$driverWindowsRelease` defined before the `Invoke-BuildPhase -Action {}` scriptblock will be accessible inside the scriptblock. Confirmed: `Invoke-BuildPhase` calls `& $Action` from `FFU.Core.psm1:3882`, and existing code inside these scriptblocks already accesses BuildFFUVM.ps1 variables (`$Make`, `$Model`, `$WindowsRelease`, etc.). PowerShell scriptblock closures capture the creating scope. [VERIFIED: FFU.Core.psm1:3882 grep]

---

## Complete SKU → EditionId Map (D-06)

Covering all entries in `$clientSKUs` (BuildFFUVM.ps1:926-940), `$LTSCSKUs` (941-948), `$ServerSKUs` (949-953):

| User `$WindowsSKU` | DISM `EditionId` | `InstallationType` filter |
|---|---|---|
| Home | Core | — |
| Home N | CoreN | — |
| Home Single Language | CoreSingleLanguage | — |
| Education | Education | — |
| Education N | EducationN | — |
| Pro | Professional | — |
| Pro N | ProfessionalN | — |
| Pro Education | ProfessionalEducation | — |
| Pro Education N | ProfessionalEducationN | — |
| Pro for Workstations | ProfessionalWorkstation | — |
| Pro N for Workstations | ProfessionalWorkstationN | — |
| Enterprise | Enterprise | — |
| Enterprise N | EnterpriseN | — |
| Enterprise 2016 LTSB | EnterpriseS | — |
| Enterprise N 2016 LTSB | EnterpriseSN | — |
| Enterprise LTSC | EnterpriseS | — |
| Enterprise N LTSC | EnterpriseSN | — |
| IoT Enterprise LTSC | IoTEnterpriseS | — |
| IoT Enterprise N LTSC | IoTEnterpriseSN | — |
| Standard | ServerStandard | Server Core |
| Standard (Desktop Experience) | ServerStandard | Server |
| Datacenter | ServerDatacenter | Server Core |
| Datacenter (Desktop Experience) | ServerDatacenter | Server |

[VERIFIED: upstream commit b2a7ef5 diff — complete switch statement]

**Note on `'CoreSingleLanguage'` (EditionId alias):** The switch must include entries for both `'Home Single Language'` (the user-facing SKU from `$clientSKUs`) AND `'CoreSingleLanguage'` (the EditionId form, used as alias input). The upstream includes both. The fork switch must do the same.

---

## LTSC Year→Driver Release Normalization (D-14..D-17)

```
$WindowsRelease  $WindowsSKU contains '*LTS*'?  $driverWindowsRelease
2016             Yes (LTSB)                      10
2019             Yes (LTSC)                      10
2021             Yes (LTSC)                      10
2024             Yes (LTSC)                      11
2019             No  (Server 2019: 'Standard')   2019  ← UNCHANGED
2022             No  (Server 2022)               2022  ← UNCHANGED
2025             No  (Server 2025)               2025  ← UNCHANGED
10               No  (client)                    10    ← UNCHANGED
11               No  (client)                    11    ← UNCHANGED
```

**OEM provider verification (no regression):**

| Provider | Pattern | With LTSC 2021 (→10) | With LTSC 2024 (→11) | With Server 2019 (stays 2019) |
|---|---|---|---|---|
| HP | `"Win$WindowsRelease"` | `"Win10"` ✓ | `"Win11"` ✓ | Not LTSC, 2019 stays → `"Win2019"` (HP doesn't have Server drivers this way; acceptable) |
| Lenovo | `"_Win$WindowsRelease"` | `"_Win10"` ✓ | `"_Win11"` ✓ | Not LTSC, unchanged |
| Dell (client) | `$WindowsRelease -le 11` | `10 -le 11 = $true` → CatalogPC ✓ | `11 -le 11 = $true` → CatalogPC ✓ | Not LTSC, 2019 unchanged → falls to `elseif (2019)` → W19 ✓ |
| Dell (server) | `W14/W19/W22/W25` codes | N/A (not Server) | N/A (not Server) | `elseif (2019)` → W19 ✓ |
| Samsung | `$WindowsRelease -eq 11` | `10 -eq 11 = $false` → Win10 path ✓ | `11 -eq 11 = $true` → Win11 path ✓ | Not LTSC |
| Microsoft | Generic (no release filtering in Surface dispatch) | Pass-through | Pass-through | N/A |

[VERIFIED: FFU.Drivers.psm1 grep for WindowsRelease usage + Dell dispatch at lines 2405/2549-2562]

---

## $WindowsSKU Consumer Trace (CORRECT-01 Propagation)

All sites that read `$WindowsSKU` AFTER the `Get-Index` call site (~4404) must see the updated value. The updated `$WindowsSKU = $windowsImageSelection.ResolvedWindowsSKU` at ~4404 causes all downstream reads to be correct automatically (no per-site changes needed).

| Line | Consumer | Family | Notes |
|------|----------|--------|-------|
| ~4087 | `$vhdxCacheItem.WindowsSKU -ne $WindowsSKU` | VHDX cache read | Cache lookup — wrong SKU = cache miss (harmless but wastes time). Fix: correct SKU means correct cache hit. |
| ~4339 | `Save-FFUBuildCheckpoint ... WindowsSKU = $WindowsSKU` | Checkpoint persistence | Stores correct edition for resume |
| ~4643 | `$cachedVHDXInfo.WindowsSKU = $WindowsSKU` | VHDX cache write | Writes correct edition to cache JSON |
| ~4698 | `Save-FFUBuildCheckpoint ... WindowsSKU = $WindowsSKU` | Checkpoint persistence | |
| ~5192 | `Save-FFUBuildCheckpoint ... WindowsSKU = $WindowsSKU` | Checkpoint persistence | |
| ~5301 | `Save-FFUBuildCheckpoint ... WindowsSKU = $WindowsSKU` | Checkpoint persistence | |
| ~5340 | `Get-ShortenedWindowsSKU -WindowsSKU $WindowsSKU` | FFU naming | This is the D-04 naming fix |
| ~5636 | `Save-FFUBuildCheckpoint ... WindowsSKU = $WindowsSKU` | Checkpoint persistence | |
| ~5696 | `Save-FFUBuildCheckpoint ... WindowsSKU = $WindowsSKU` | Checkpoint persistence | |

**All 9 consumers are automatically fixed** by the single `$WindowsSKU =` reassignment at line ~4404. No per-site changes required. [VERIFIED: BuildFFUVM.ps1 reads at lines 4087, 4339, 4643, 4698, 5192, 5301, 5340, 5636, 5696]

**Secondary propagation:** `$installationType`, `$WindowsVersion`, `$isLTSC`, `$isWindows10LtscClient`, `$installLatestCuInVm` are recalculated via `Get-WindowsTargetRuntimeState`. These are needed for correct servicing behavior when a fallback edition changes the installation type (e.g., requesting a client SKU not on the media and falling back to a server SKU).

---

## ADK bcdboot Path Details

**Confirmed path structure:**
```
{ADKRoot}\Assessment and Deployment Kit\Deployment Tools\{archStr}\BCDBoot\bcdboot.exe

Where:
  {ADKRoot}  = value of HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots → KitsRoot10
               (typically: C:\Program Files (x86)\Windows Kits\10\)
  {archStr}  = 'amd64'  when $WindowsArch -ne 'arm64'
             = 'arm64'  when $WindowsArch -ieq 'arm64'
  BCDBoot    = leaf folder name, EXACTLY 'BCDBoot' (PascalCase — not 'bcdboot' or 'BcdBoot')
```

**Why leaf folder is `BCDBoot` (not `Oscdimg`):**
The existing FFU.ADK.psm1 and FFU.Preflight.psm1 show the arch-specific tool folder pattern:
```
...\Deployment Tools\amd64\Oscdimg\oscdimg.exe   ← existing (confirmed)
...\Deployment Tools\amd64\BCDBoot\bcdboot.exe   ← new (confirmed by upstream commit)
```
Both tools live under the same `amd64` subfolder, different leaf folders.

**Preflight check addition in `Test-FFUADK`** (after the `$efisysNoprompt` check at line ~1112):
```powershell
# CHECK 5: ADK BCDBoot executable (required for Add-BootFiles with Secure Boot 2023 fix)
$archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }  # already computed above
$bcdbootExe = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$archPath\BCDBoot\bcdboot.exe"
if (-not (Test-Path -Path $bcdbootExe -PathType Leaf)) {
    $errors += "ADK bcdboot.exe not found (required for Secure Boot 2023 compatibility)"
    $missingFiles += $bcdbootExe
}
```

Note: `$archPath` is already computed at line 1082 of `Test-FFUADK`. The new check reuses it.

---

## Common Pitfalls

### Pitfall 1: Performance of Per-Index `Get-WindowsImage -Index N`
**What goes wrong:** `Get-WindowsImage -Index N` is called once per image in the WIM/ESD. A multi-edition ISO may have 5-12 images. Each call reads from the file. This is acceptable (~1-2 seconds per image) but should be logged.
**Why it happens:** EditionId requires `Get-WindowsImage -Index N` — the no-index call only returns ImageName and ImageSize.
**How to avoid:** Call `Get-WindowsImage` (no `-Index`) first to get the count, then loop. Already the upstream pattern. Include a `WriteLog "Inspecting $($imageIndexes.Count) images for EditionId..."` before the loop.
**Warning signs:** Builds hanging at index selection on very slow storage.

### Pitfall 2: `$ISOPath` parameter in `Get-Index` must be removed
**What goes wrong:** The old `Get-Index` has `-ISOPath` which controlled whether to sample index 1 or 4 for the Substring derivation. With EditionId-based matching, this parameter is no longer needed or meaningful.
**Why it happens:** The parameter was the old architecture.
**How to avoid:** Remove `-ISOPath` from the new `Get-WindowsImageSelection` signature AND from the call at BuildFFUVM.ps1:4404 (which currently passes `-ISOPath $ISOPath`). Update `FunctionsToExport` in FFU.Imaging.psd1 if function is renamed.
**Warning signs:** PSScriptAnalyzer warns on unused parameter.

### Pitfall 3: Read-Host in ThreadJob hangs silently
**What goes wrong:** The current `Get-Index` fallback calls `Read-Host` which blocks the ThreadJob indefinitely with no error message, no timeout, and no way to cancel. The UI shows the build as "running" but it is deadlocked.
**Why it happens:** ThreadJob runspaces don't have an interactive console attached.
**How to avoid:** D-01 mandates deleting this. Replace with auto-select (1 candidate) or throw (2+ candidates). Never use `Read-Host` or `Write-Host` in module code that runs in the build path.

### Pitfall 4: Server Desktop Experience vs Server Core disambiguation
**What goes wrong:** Both `Standard` (Core) and `Standard (Desktop Experience)` have EditionId `ServerStandard`. Without `InstallationType` filtering, picking the wrong one will silently capture the wrong server variant.
**Why it happens:** `EditionId` alone is insufficient for server images.
**How to avoid:** After EditionId match, apply `$preferredInstallationType` filter (D-07). The upstream uses `Server` for Desktop Experience and `Server Core` for Core variant (confirmed in commit diff). Default to Core (no Desktop Experience) if the user-selected SKU has no `(Desktop Experience)` suffix.

### Pitfall 5: `$driverWindowsRelease` scope inside `Invoke-BuildPhase`
**What goes wrong:** If `$driverWindowsRelease` is computed inside the `Invoke-BuildPhase -Action {}` scriptblock, it may not be accessible after the block exits.
**Why it happens:** Scriptblock closure scope.
**How to avoid:** Compute `$driverWindowsRelease` in the OUTER scope BEFORE the `Invoke-BuildPhase` call (exactly as the upstream commit `04dfb5f` does). The variable is then captured by the scriptblock's closure when `& $Action` is called from `FFU.Core.psm1:3882`.

### Pitfall 6: Function rename requires psd1 export update
**What goes wrong:** If `Get-Index` is renamed to `Get-WindowsImageSelection`, the old name disappears from `FunctionsToExport` in `FFU.Imaging.psd1` and any callers break.
**Why it happens:** Explicit exports in psd1 manifests.
**How to avoid:** Either (a) rename in psd1 and update all callers (there is only ONE caller: BuildFFUVM.ps1:4404), or (b) add an alias `New-Alias -Name 'Get-Index' -Value 'Get-WindowsImageSelection'` for backward compat. Option (a) is cleaner; the function is only called from one place.

### Pitfall 7: InModuleScope required for Pester tests of module-internal functions
**What goes wrong:** `Get-WindowsImageSelection` and `Get-ResolvedWindowsSKUFromImage` are NOT exported from FFU.Imaging (only exported if added to psd1). Pester can't see them from the test file's scope.
**Why it happens:** PowerShell module exports — internal functions are private.
**How to avoid:** Use `InModuleScope 'FFU.Imaging' { ... }` for all tests of these functions. Reference: STATE.md Phase 46 note "InModuleScope required for all PowerShell class/enum assertions in Pester".

### Pitfall 8: `Get-ResolvedWindowsSKUFromImage` returns `$null` for unknown EditionId
**What goes wrong:** If DISM returns an EditionId not in the reverse map (e.g., an unusual OEM variant), `Get-ResolvedWindowsSKUFromImage` returns `$null`. The caller must handle this gracefully.
**Why it happens:** DISM may return EditionIds that are not in the known set.
**How to avoid:** Caller checks `if (-not [string]::IsNullOrWhiteSpace($windowsImageSelection.ResolvedWindowsSKU))` before reassigning `$WindowsSKU`. Already in the upstream pattern and in D-04.

---

## Code Examples

### Pattern 1: Get-WindowsImageSelection (fork adaptation, combining b2a7ef5 + 5aaa1ad + D-01 deviation)

```powershell
function Get-WindowsImageSelection {
    # Source: upstream commits b2a7ef5 + 5aaa1ad, adapted for ThreadJob (no Read-Host)
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsImagePath,

        [Parameter(Mandatory = $true)]
        [string]$WindowsSKU,

        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease
    )

    $imageIndexes = Get-WindowsImage -ImagePath $WindowsImagePath
    $normalizedWindowsSKU = $WindowsSKU.Trim()
    $isDesktopExperienceRequested = $normalizedWindowsSKU -match '\(Desktop Experience\)'
    $normalizedWindowsSKU = $normalizedWindowsSKU -replace '\s*\(Desktop Experience\)\s*', ''

    $editionIdCandidates = switch ($normalizedWindowsSKU) {
        'Home'                      { @('Core') }
        'Home N'                    { @('CoreN') }
        'Home Single Language'      { @('CoreSingleLanguage') }
        'CoreSingleLanguage'        { @('CoreSingleLanguage') }
        # ... (full map from research)
        default                     { @() }
    }

    $preferredInstallationType = $null
    if ($normalizedWindowsSKU -in @('Standard', 'Standard (Desktop Experience)', 'Datacenter', 'Datacenter (Desktop Experience)')) {
        $preferredInstallationType = if ($isDesktopExperienceRequested) { 'Server' } else { 'Server Core' }
    }

    WriteLog "Inspecting $($imageIndexes.Count) image(s) in '$WindowsImagePath' for EditionId matching SKU '$WindowsSKU'..."
    $imageMetadata = @(foreach ($imageIndex in $imageIndexes) {
        try {
            $details = Get-WindowsImage -ImagePath $WindowsImagePath -Index $imageIndex.ImageIndex
            [PSCustomObject]@{
                ImageIndex        = $details.ImageIndex
                ImageName         = $details.ImageName
                ImageSize         = $details.ImageSize
                EditionId         = $details.EditionId
                InstallationType  = $details.InstallationType
                ResolvedWindowsSKU = Get-ResolvedWindowsSKUFromImage -EditionId $details.EditionId `
                                     -InstallationType $details.InstallationType `
                                     -ImageName $details.ImageName -WindowsRelease $WindowsRelease
            }
        }
        catch { $null }
    }) | Where-Object { $null -ne $_ }

    if ($editionIdCandidates.Count -gt 0) {
        $imageMatches = $imageMetadata | Where-Object { $_.EditionId -in $editionIdCandidates }
        if ($null -ne $preferredInstallationType -and $imageMatches.Count -gt 0) {
            $preferredMatches = $imageMatches | Where-Object { $_.InstallationType -eq $preferredInstallationType }
            if ($preferredMatches.Count -gt 0) { $imageMatches = $preferredMatches }
        }
        if ($imageMatches.Count -gt 0) {
            $bestMatch = $imageMatches | Sort-Object -Property ImageSize -Descending | Select-Object -First 1
            WriteLog "Selected image index $($bestMatch.ImageIndex) (SKU='$WindowsSKU', EditionId='$($bestMatch.EditionId)', ResolvedSKU='$($bestMatch.ResolvedWindowsSKU)'): $($bestMatch.ImageName)"
            return $bestMatch
        }
    }

    # Fallback 1: exact ImageName -eq (D-08 — safe, no false positives)
    $exactNameMatch = $imageMetadata | Where-Object { $_.ImageName -eq "$($normalizedWindowsSKU)" }
    if ($exactNameMatch) {
        $bestMatch = @($exactNameMatch)[0]
        WriteLog "Selected image index $($bestMatch.ImageIndex) via exact ImageName match: $($bestMatch.ImageName)"
        return $bestMatch
    }

    # Fallback 2: single relevant candidate → auto-select (D-02) | multiple → throw (D-03)
    $relevantCandidates = @($imageMetadata | Where-Object { $_.ImageName -match '(10|11|2016|2019|202\d)' })
    if ($relevantCandidates.Count -eq 0) { $relevantCandidates = $imageMetadata }

    $editionList = ($imageMetadata | ForEach-Object { "  [$($_.ImageIndex)] $($_.ImageName) (EditionId=$($_.EditionId))" }) -join [System.Environment]::NewLine
    WriteLog "No exact EditionId or ImageName match found for SKU '$WindowsSKU'. Available editions:$([System.Environment]::NewLine)$editionList"

    if ($relevantCandidates.Count -eq 1) {
        WriteLog "Auto-selecting single relevant candidate: $($relevantCandidates[0].ImageName)"
        return $relevantCandidates[0]
    }

    throw "No matching Windows image found for SKU '$WindowsSKU' and $($relevantCandidates.Count) candidate(s) exist — cannot auto-select. Available editions logged above. Provide an ISO containing the exact requested SKU."
}
```

### Pattern 2: Get-WindowsTargetRuntimeState (BuildFFUVM.ps1 script-level function)

```powershell
function Get-WindowsTargetRuntimeState {
    # Source: upstream commit 5aaa1ad (verbatim from diff)
    param(
        [Parameter(Mandatory = $true)] [int]$WindowsRelease,
        [Parameter(Mandatory = $true)] [string]$WindowsSKU,
        [Parameter(Mandatory = $true)] [string]$CurrentWindowsVersion,
        [Parameter(Mandatory = $true)] [bool]$UpdateLatestCU
    )
    $localInstallationType = if ($WindowsSKU -like 'Standard*' -or $WindowsSKU -like 'Datacenter*') { 'Server' } else { 'Client' }
    $localWindowsVersion   = $CurrentWindowsVersion
    $localIsLTSC           = $false

    if ($localInstallationType -eq 'Server') {
        switch ($WindowsRelease) {
            2016 { $localWindowsVersion = '1607' }
            2019 { $localWindowsVersion = '1809' }
            2022 { $localWindowsVersion = '21H2' }
            2025 { $localWindowsVersion = '24H2' }
        }
    }
    if ($WindowsSKU -like '*LTS*') {
        switch ($WindowsRelease) {
            2016 { $localWindowsVersion = '1607' }
            2019 { $localWindowsVersion = '1809' }
            2021 { $localWindowsVersion = '21H2' }
            2024 { $localWindowsVersion = '24H2' }
        }
        $localIsLTSC = $true
    }
    $localIsWindows10LtscClient = ($localInstallationType -eq 'Client') -and ($WindowsRelease -in 2016, 2019, 2021) -and $localIsLTSC
    return [PSCustomObject]@{
        InstallationType      = $localInstallationType
        WindowsVersion        = $localWindowsVersion
        IsLTSC                = $localIsLTSC
        IsWindows10LtscClient = $localIsWindows10LtscClient
        InstallLatestCuInVm   = ($UpdateLatestCU -and $localIsWindows10LtscClient)
    }
}
```

### Pattern 3: Caller update at BuildFFUVM.ps1 ~4404

```powershell
if (-not($index) -and ($WindowsSKU)) {
    $requestedWindowsSKU = $WindowsSKU
    $windowsImageSelection = Get-WindowsImageSelection -WindowsImagePath $wimPath `
                                                       -WindowsSKU $WindowsSKU `
                                                       -WindowsRelease $WindowsRelease
    $index = $windowsImageSelection.ImageIndex

    if (-not [string]::IsNullOrWhiteSpace($windowsImageSelection.ResolvedWindowsSKU)) {
        $WindowsSKU = $windowsImageSelection.ResolvedWindowsSKU
        $windowsRuntimeState = Get-WindowsTargetRuntimeState -WindowsRelease $WindowsRelease `
                                   -WindowsSKU $WindowsSKU -CurrentWindowsVersion $WindowsVersion `
                                   -UpdateLatestCU:$UpdateLatestCU
        $installationType      = $windowsRuntimeState.InstallationType
        $WindowsVersion        = $windowsRuntimeState.WindowsVersion
        $isLTSC                = $windowsRuntimeState.IsLTSC
        $isWindows10LtscClient = $windowsRuntimeState.IsWindows10LtscClient
        $installLatestCuInVm   = $windowsRuntimeState.InstallLatestCuInVm

        if ($requestedWindowsSKU -ne $WindowsSKU) {
            WriteLog "Resolved WindowsSKU from '$requestedWindowsSKU' to '$WindowsSKU' based on image: '$($windowsImageSelection.ImageName)'."
        }
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|---|---|---|
| `Get-Index` with Substring derivation | `Get-WindowsImageSelection` with EditionId | Locale-independent; non-English media works |
| `Read-Host`/`while($true)` fallback | Auto-select 1 candidate; throw on ambiguity | ThreadJob safe; builds don't deadlock |
| Bare `bcdboot` (host binary) | ADK `bcdboot.exe` via full path | Correct cert variant for Secure Boot 2023 hardware |
| `$WindowsRelease` passed directly to OEM drivers | `$driverWindowsRelease` (normalized LTSC years) | LTSC 2021/2024 driver downloads succeed |
| `$WindowsSKU` never updated after fallback | `$WindowsSKU` reassigned after `Get-WindowsImageSelection` | FFU naming, cache, servicing use selected edition |

---

## Runtime State Inventory

This phase is NOT a rename/refactor/migration phase. No stored data, live service config, OS-registered state, secrets, or build artifacts reference any string being changed. Section not applicable.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows ADK (Deployment Tools) | CORRECT-03 (bcdboot.exe) | ✓ (pre-flight validated) | Read from registry at `Test-ADKPrerequisites` | None — hard dependency, already pre-flight validated |
| DISM PowerShell module | CORRECT-01+04 (`Get-WindowsImage -Index N`) | ✓ (existing FFU.Imaging usage) | In-box Windows | None — already used in `Get-Index` and ArtifactScanner |
| GitHub API (`gh`) | Research only | ✓ (used to fetch commit diffs) | — | — |

No missing dependencies identified that would block execution.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Pester 5.x |
| Config file | None (inline runner) |
| Quick run command | `Invoke-Pester -Path "D:\claude\FFUBuilder\FFUDevelopment\Tests\Test-Phase51Correctness.ps1" -Output Detailed` |
| Full suite command | `& "D:\claude\FFUBuilder\FFUDevelopment\Tests\Test-SyntaxCheck.ps1"` then Pester on Test-Phase51Correctness.ps1 |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| CORRECT-04 | Pro SKU → EditionId 'Professional' match | Unit | `Invoke-Pester ... -Tag 'CORRECT04'` | Mock `Get-WindowsImage -Index` |
| CORRECT-04 | EnterpriseS EditionId selected for 'Enterprise LTSC' | Unit | Same | Map completeness gate |
| CORRECT-04 | IoTEnterpriseS EditionId for 'IoT Enterprise LTSC' | Unit | Same | Map completeness gate |
| CORRECT-04 | Server Desktop Experience disambiguation via InstallationType | Unit | Same | Filter server vs server core |
| CORRECT-04 | All 24 SKU→EditionId mappings from the map table | Unit (ForEach) | Same | -ForEach parameterized |
| CORRECT-01 | Fallback: single relevant candidate → auto-select, ResolvedWindowsSKU set | Unit | Same | No Read-Host call |
| CORRECT-01 | Fallback: two candidates → throws | Unit | Same | Should -Throw |
| CORRECT-01 | `Get-ResolvedWindowsSKUFromImage` Core→Home, Professional→Pro, EnterpriseS→'Enterprise LTSC' | Unit (ForEach) | Same | Reverse map coverage |
| CORRECT-03 | `Add-BootFiles` throws when ADK bcdboot path not found | Unit | `Invoke-Pester ... -Tag 'CORRECT03'` | Mock Test-Path to return $false |
| CORRECT-03 | `Add-BootFiles` calls Invoke-Process with full ADK path when found | Unit | Same | Mock Test-Path $true + Should -Invoke |
| CORRECT-03 | `Test-FFUADK` returns Failed when bcdboot.exe missing | Unit | Same | InModuleScope FFU.Preflight |
| CORRECT-02 | 2021 LTSC → 10 | Unit (pure) | `Invoke-Pester ... -Tag 'CORRECT02'` | No mocks needed — pure function |
| CORRECT-02 | 2024 LTSC → 11 | Unit (pure) | Same | |
| CORRECT-02 | 2016 LTSB → 10 | Unit (pure) | Same | |
| CORRECT-02 | 2019 LTSC → 10 | Unit (pure) | Same | |
| CORRECT-02 | Server 2019 ('Standard' SKU) → 2019 unchanged | Unit (pure) | Same | 2019 collision test |
| CORRECT-02 | Non-LTSC Win10/11 → unchanged | Unit (pure) | Same | |
| CORRECT-01 | Real non-English ISO (e.g., German) selects correct Pro edition | Human UAT | Manual | Requires real media |
| CORRECT-03 | Captured FFU boots on Secure Boot 2023-cert hardware | Human UAT | Manual | Requires real hardware |

### Wave 0 Gaps

- [ ] `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` — covers all unit tests above (new file)
- [ ] InModuleScope setup for FFU.Imaging (needed for `Get-WindowsImageSelection`, `Get-ResolvedWindowsSKUFromImage`)
- [ ] InModuleScope setup for FFU.Preflight (needed for `Test-FFUADK`)

### Key Mocking Patterns

```powershell
# Mock Get-WindowsImage (list call — no -Index)
Mock Get-WindowsImage {
    @(
        [PSCustomObject]@{ ImageIndex = 1; ImageName = 'Windows 11 Pro'; ImageSize = 4000000000 }
        [PSCustomObject]@{ ImageIndex = 2; ImageName = 'Windows 11 Home'; ImageSize = 3800000000 }
    )
} -ParameterFilter { -not $PSBoundParameters.ContainsKey('Index') } -ModuleName 'FFU.Imaging'

# Mock Get-WindowsImage -Index N
Mock Get-WindowsImage {
    if ($Index -eq 1) {
        [PSCustomObject]@{ ImageIndex = 1; ImageName = 'Windows 11 Pro'; EditionId = 'Professional'; InstallationType = 'Client'; ImageSize = 4000000000 }
    }
    elseif ($Index -eq 2) {
        [PSCustomObject]@{ ImageIndex = 2; ImageName = 'Windows 11 Home'; EditionId = 'Core'; InstallationType = 'Client'; ImageSize = 3800000000 }
    }
} -ParameterFilter { $PSBoundParameters.ContainsKey('Index') } -ModuleName 'FFU.Imaging'
```

---

## Security Domain

`security_enforcement` not set in config.json — treated as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Partial | `$WindowsSKU` comes from user config — the SKU validation at BuildFFUVM.ps1:965 gates legality. No additional validation needed for the EditionId map (it returns `@()` for unknown SKUs, which fails gracefully). |
| V6 Cryptography | No | — |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Path traversal via `$AdkPath` | Tampering | `$adkPath` comes from registry (trusted source), validated by `Test-ADKPrerequisites` before use. Not user-controllable at runtime. |
| ADK binary substitution | Elevation of Privilege | ADK install path is system-protected (`C:\Program Files (x86)\Windows Kits\10\`). Hard-fail on path mismatch. |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | `$driverWindowsRelease` is accessible inside `Invoke-BuildPhase -Action {}` scriptblock via closure | CORRECT-02 code, Pitfall 5 | Driver normalization would silently not work; fix: declare in outer scope (which is already the plan) |

**Note:** A1 is LOW risk — the existing code already uses `$Make`, `$Model`, `$WindowsRelease` etc. inside identical `Invoke-BuildPhase -Action {}` blocks, proving outer-scope access works. The assumption was verified by checking `FFU.Core.psm1:3882` where `& $Action` is called. [VERIFIED: codebase grep confirms `& $Action` at FFU.Core.psm1:3882]

---

## Open Questions

1. **Should `Get-WindowsImageSelection` be exported from `FFU.Imaging.psd1`?**
   - What we know: `Get-Index` is currently exported (it's called from BuildFFUVM.ps1 which imports the module). The psd1 `FunctionsToExport` array must include the new name.
   - What's unclear: Whether any other callers outside the known set use `Get-Index` by name.
   - Recommendation: Rename to `Get-WindowsImageSelection` in psd1; search codebase for other `Get-Index` callers before final commit.

2. **LTSC 2016 (`Enterprise 2016 LTSB`) driver normalization — is it exercisable?**
   - What we know: `$releaseToSKUMapping` has `2016 = $LTSCSKUs + $ServerSKUs`; LTSB 2016 exists as a valid path.
   - What's unclear: Whether any user actually builds LTSC 2016 (very old, EOL).
   - Recommendation: Include in normalization anyway (D-14 explicitly lists it); mark as deferred verification per CONTEXT.md.

---

## Sources

### Primary (HIGH confidence)
- Upstream commit diffs fetched live via `gh api repos/rbalsleyMSFT/FFU/compare/{commit}~1...{commit}` — exact code for all 4 commits confirmed [VERIFIED: GitHub API]
- `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` — current `Get-Index` and `Add-BootFiles` code [VERIFIED: Read tool]
- `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` — `Test-FFUADK` function [VERIFIED: Read tool]
- `FFUDevelopment/Modules/FFU.ADK/FFU.ADK.psm1` — ADK path resolution pattern (oscdimg at `...\amd64\Oscdimg\...`) [VERIFIED: Read tool]
- `FFUDevelopment/BuildFFUVM.ps1` — `$clientSKUs`, `$LTSCSKUs`, `$ServerSKUs`, call sites, `$adkPath` variable scope [VERIFIED: Read tool + grep]
- `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1:205-208` — `Get-WindowsImage -Index 1 / .EditionId` precedent [VERIFIED: Read tool]
- `FFUDevelopment/version.json` — current module versions [VERIFIED: Read tool]

### Secondary (MEDIUM confidence)
- [BCDBOOT, from the latest Windows ADK — Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/5692303/bcdboot-from-the-latest-windows-adk-enforces-usage) — confirms ADK bcdboot Secure Boot cert behavior
- [Get-WindowsImage (DISM) — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/dism/get-windowsimage?view=windowsserver2025-ps) — confirms `-Index` parameter returns `EditionId` and `InstallationType`
- [bcdboot.exe — Strontic xcyclopedia](https://strontic.github.io/xcyclopedia/library/bcdboot.exe-1B79840301B3CC6D57EEB26CC2D05E5D.html) — confirms `C:\Program Files (x86)\Windows Kits\10\...\BCDBoot\bcdboot.exe` path format

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all tools already in use
- Architecture: HIGH — four targeted changes; upstream commits confirm exact implementation
- SKU→EditionId map: HIGH — verified from upstream commit diff b2a7ef5
- ADK bcdboot path: HIGH — confirmed from upstream diff + Microsoft Q&A cross-reference
- LTSC normalization: HIGH — verified from upstream commit diff 04dfb5f + Dell/HP/Lenovo OEM provider code
- $WindowsSKU consumer trace: HIGH — verified by reading all 9 sites in BuildFFUVM.ps1
- Pitfalls: HIGH — several confirmed from ThreadJob constraint history (STATE.md)

**Research date:** 2026-06-26
**Valid until:** 2026-07-26 (stable domain — PowerShell module patterns and ADK path structure are stable)
