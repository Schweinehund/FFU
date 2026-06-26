# Phase 51: Capture/Boot Correctness - Pattern Map

**Mapped:** 2026-06-26
**Files analyzed:** 9 new/modified files
**Analogs found:** 9 / 9

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` (Get-WindowsImageSelection rewrite) | service | request-response (DISM query) | `FFU.Imaging.psm1:490-587` (`Get-Index`) + `FFU.ArtifactScanner.psm1:205-208` | exact (same function being rewritten) + exact (EditionId pattern) |
| `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` (Add-BootFiles extension) | service | request-response (external tool) | `FFU.Imaging.psm1:1874-1886` (`Add-BootFiles`) | exact (same function to extend) |
| `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1` | config | n/a | `FFU.Imaging.psd1` current (lines 1-273) | exact |
| `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` (Test-FFUADK extension) | middleware | request-response (preflight) | `FFU.Preflight.psm1:1082-1112` (sequential file checks) | exact (same check pattern) |
| `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1` | config | n/a | `FFU.Preflight.psd1` current | exact |
| `FFUDevelopment/BuildFFUVM.ps1` (Get-EffectiveDriverWindowsRelease new function) | utility | transform | `BuildFFUVM.ps1:2400-2408` (`$isLTSC` derivation block) | role-match (same SKU-gated transform logic) |
| `FFUDevelopment/BuildFFUVM.ps1` (Get-WindowsTargetRuntimeState new function) | utility | transform | `BuildFFUVM.ps1:2388-2408` (`installationType` + `isLTSC` derivation) | exact (same logic factored into a function) |
| `FFUDevelopment/BuildFFUVM.ps1` (caller update sites) | controller | request-response | `BuildFFUVM.ps1:4403-4404` (current `Get-Index` call) + `BuildFFUVM.ps1:3163-3193` (driver dispatch block) | exact |
| `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` | test | n/a | `FFUDevelopment/Tests/Test-OSPartitionLookup.ps1` + `Test-ErrorHandling.ps1` | role-match (same custom Write-TestResult framework) |

---

## Pattern Assignments

### `FFU.Imaging.psm1` — Get-WindowsImageSelection rewrite (D1 + D2)

**Analog 1 (function being replaced):** `FFU.Imaging.psm1:490-587` (`Get-Index`)

**Analog 2 (EditionId pattern):** `FFU.ArtifactScanner.psm1:201-215` (`Get-WindowsImage -Index 1` → `.EditionId`)

#### Current signature to replace (lines 516-526):
```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsImagePath,

    [Parameter(Mandatory = $true)]
    [string]$WindowsSKU,

    [Parameter(Mandatory = $false)]
    [string]$ISOPath          # REMOVE: no longer needed, was for Substring start-index logic
)
```

#### Substring derivation to DELETE (lines 532-545) — the logic to remove:
```powershell
# THIS ENTIRE BLOCK IS DELETED:
if ($ISOPath) {
    if ($WindowsSKU -notmatch "Standard|Datacenter") {
        $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 1
        $WindowsImage = $imageIndex.ImageName.Substring(0, 10)   # line 535 — DELETE
    }
    else {
        $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 1
        $WindowsImage = $imageIndex.ImageName.Substring(0, 19)   # line 539 — DELETE
    }
}
else {
    $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 4
    $WindowsImage = $imageIndex.ImageName.Substring(0, 10)       # line 544 — DELETE
}
```

#### Read-Host/while($true) loop to DELETE (lines 562-585) — the loop to remove:
```powershell
# THIS ENTIRE WHILE LOOP IS DELETED (ThreadJob deadlock):
while ($true) {
    Write-Host "No matching ImageIndex found..."
    $inputValue = Read-Host "Enter the number of the ImageName you want to use"  # HANGS THREADJOB
    ...
}
```

#### Safe fallback tier to KEEP (line 551 — exact -eq match, safe per D-08):
```powershell
$matchingImageIndex = $imageIndexes | Where-Object ImageName -eq $ImageNameToFind
if ($matchingImageIndex) {
    $matchingImageIndex.ImageIndex
    return
}
```

#### EditionId pattern from ArtifactScanner (analog, lines 201-215):
```powershell
# Source: FFU.ArtifactScanner.psm1:205-208 — proven in-repo pattern for EditionId
$imageInfo = Get-WindowsImage -ImagePath $FFUPath -Index 1 -ErrorAction Stop
$metadata.WindowsSKU = $imageInfo.EditionId    # <-- the EditionId property access pattern
```

#### New function signature (from RESEARCH.md Code Example, fork-adapted):
```powershell
function Get-WindowsImageSelection {
    # Source: upstream commits b2a7ef5 + 5aaa1ad, adapted for ThreadJob (no Read-Host per D-01)
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsImagePath,

        [Parameter(Mandatory = $true)]
        [string]$WindowsSKU,

        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease
        # NOTE: $ISOPath is REMOVED (pitfall 2 in RESEARCH.md)
    )
    ...
}
```

#### New companion function signature:
```powershell
function Get-ResolvedWindowsSKUFromImage {
    # Source: upstream commit 5aaa1ad — reverse EditionId→SKU map
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [string]$EditionId,
        [Parameter(Mandatory = $true)] [string]$InstallationType,
        [Parameter(Mandatory = $true)] [string]$ImageName,
        [Parameter(Mandatory = $true)] [int]$WindowsRelease
    )
    ...
    return $null   # returns $null for unknown EditionId — caller must guard with IsNullOrWhiteSpace
}
```

#### WriteLog+throw idiom (fork's ThreadJob-safe error reporting — D-03):
```powershell
# Established pattern: log the editions list FIRST, then throw
# (ThreadJob error stream is unreliable; WriteLog guarantees the list reaches the build log)
$editionList = ($imageMetadata | ForEach-Object {
    "  [$($_.ImageIndex)] $($_.ImageName) (EditionId=$($_.EditionId))"
}) -join [System.Environment]::NewLine
WriteLog "No exact EditionId or ImageName match found for SKU '$WindowsSKU'. Available editions:$([System.Environment]::NewLine)$editionList"

if ($relevantCandidates.Count -eq 1) {
    WriteLog "Auto-selecting single relevant candidate: $($relevantCandidates[0].ImageName)"
    return $relevantCandidates[0]
}
throw "No matching Windows image found for SKU '$WindowsSKU' and $($relevantCandidates.Count) candidate(s) exist — cannot auto-select. Available editions logged above."
```

#### Rich return object shape (not just [int] — per D-04):
```powershell
# New: return PSCustomObject, not just ImageIndex int
[PSCustomObject]@{
    ImageIndex         = $details.ImageIndex
    ImageName          = $details.ImageName
    ImageSize          = $details.ImageSize
    EditionId          = $details.EditionId
    InstallationType   = $details.InstallationType
    ResolvedWindowsSKU = Get-ResolvedWindowsSKUFromImage -EditionId $details.EditionId `
                         -InstallationType $details.InstallationType `
                         -ImageName $details.ImageName -WindowsRelease $WindowsRelease
}
```

#### Per-index DISM call pattern (inside `foreach ($imageIndex in $imageIndexes)` loop):
```powershell
try {
    $details = Get-WindowsImage -ImagePath $WindowsImagePath -Index $imageIndex.ImageIndex
    # $details.EditionId and $details.InstallationType are available here
}
catch { $null }   # null filtered out by Where-Object after loop
```

---

### `FFU.Imaging.psm1` — Add-BootFiles extension (D3)

**Analog:** `FFU.Imaging.psm1:1874-1886` (current `Add-BootFiles`) + `FFU.Preflight.psm1:1082-1083` (arch path computation) + `FFU.ADK.psm1:408-409` (ADK tool path construction)

#### Current function to extend (lines 1874-1886):
```powershell
function Add-BootFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OsPartitionDriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$SystemPartitionDriveLetter,
        [string]$FirmwareType = 'UEFI'
    )

    WriteLog "Adding boot files for `"$($OsPartitionDriveLetter):\Windows`" to System partition `"$($SystemPartitionDriveLetter):`"..."
    Invoke-Process bcdboot "$($OsPartitionDriveLetter):\Windows /S $($SystemPartitionDriveLetter): /F $FirmwareType" | Out-Null
    WriteLog "Done."
}
```

#### ADK arch path pattern from FFU.Preflight.psm1:1082-1083 (exact pattern to copy):
```powershell
$archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }
$oscdimgPath = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg"
```

#### ADK tool path pattern from FFU.ADK.psm1:408-409 (same structure, different leaf folder):
```powershell
# oscdimg: ...\Oscdimg\oscdimg.exe    (existing, confirmed)
# bcdboot: ...\BCDBoot\bcdboot.exe    (new, same arch root — BCDBoot is PascalCase)
$archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }
$oscdimgPath = "$($result.ADKPath)Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg"
```

#### New Add-BootFiles signature and body (from upstream commit 6c0ee8a, fork-adapted):
```powershell
function Add-BootFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OsPartitionDriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$SystemPartitionDriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$AdkPath,                    # NEW: required — path from $adkPath (set at BuildFFUVM.ps1:3217)
        [Parameter(Mandatory = $true)]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$WindowsArch,                # NEW: required — arch-aware bcdboot selection
        [string]$FirmwareType = 'UEFI'
    )

    $bcdBootArchitecture = if ($WindowsArch -ieq 'arm64') { 'arm64' } else { 'amd64' }
    $bcdBootPath = Join-Path $AdkPath "Assessment and Deployment Kit\Deployment Tools\$bcdBootArchitecture\BCDBoot\bcdboot.exe"

    if (-not (Test-Path -Path $bcdBootPath)) {
        throw "ADK BCDBoot was not found at '$bcdBootPath'. Install Windows ADK with Deployment Tools or run with -UpdateADK `$true."
    }

    WriteLog "Adding boot files using ADK bcdboot: $bcdBootPath"
    WriteLog "Adding boot files for `"$($OsPartitionDriveLetter):\Windows`" to System partition `"$($SystemPartitionDriveLetter):`"..."
    Invoke-Process $bcdBootPath "$($OsPartitionDriveLetter):\Windows /S $($SystemPartitionDriveLetter): /F $FirmwareType" | Out-Null
    WriteLog "Done."
}
```

#### Updated call site in BuildFFUVM.ps1 (currently at ~line 4444 — add two new params):
```powershell
# Before (current):
# Add-BootFiles -OsPartitionDriveLetter $osPartitionDriveLetter -SystemPartitionDriveLetter $systemPartitionDriveLetter[1]

# After (add AdkPath and WindowsArch):
Add-BootFiles -OsPartitionDriveLetter $osPartitionDriveLetter `
              -SystemPartitionDriveLetter $systemPartitionDriveLetter[1] `
              -AdkPath $adkPath `
              -WindowsArch $WindowsArch
# $adkPath is set at BuildFFUVM.ps1:3217 from $adkValidation.ADKPath (already in scope)
```

---

### `FFU.Preflight.psm1` — Test-FFUADK bcdboot check (D-12)

**Analog:** `FFU.Preflight.psm1:1082-1112` (existing sequential ADK file checks)

#### Existing check pattern to copy (lines 1082-1112):
```powershell
# CHECK 4: Architecture-specific executables
$archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }   # line 1082
$oscdimgPath = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg"   # line 1083

# oscdimg.exe
$oscdimgExe = Join-Path $oscdimgPath 'oscdimg.exe'
if (-not (Test-Path -Path $oscdimgExe -PathType Leaf)) {
    $errors += 'oscdimg.exe not found'
    $missingFiles += $oscdimgExe
}
```

#### New bcdboot check to INSERT (after the `$efisysNoprompt` check at line ~1112):
```powershell
# CHECK 5: ADK BCDBoot executable (required for Add-BootFiles Secure Boot 2023 fix)
# $archPath already computed at line 1082 — reuse it here
$bcdbootExe = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$archPath\BCDBoot\bcdboot.exe"
if (-not (Test-Path -Path $bcdbootExe -PathType Leaf)) {
    $errors += "ADK bcdboot.exe not found (required for Secure Boot 2023 compatibility)"
    $missingFiles += $bcdbootExe
}
```

#### How errors reach the result (lines 1154-1174 pattern — no change needed):
```powershell
# Errors accumulate in $errors array; the existing pass/fail block at 1143-1174 picks them up:
$isValid = $adkInstalled -and $deploymentToolsInstalled -and ($errors.Count -eq 0)
# ...
New-FFUCheckResult -CheckName 'ADK' -Status 'Failed' `
    -Message "ADK validation failed: $($errors -join '; ')" `
    -Severity 'Critical' `
    -Remediation (New-FFURemediationBlock -Issue "..." -PowerShellCommands @('.\BuildFFUVM.ps1 -UpdateADK $true') ...)
```

---

### `BuildFFUVM.ps1` — Get-EffectiveDriverWindowsRelease new function (D4)

**Analog:** `BuildFFUVM.ps1:2400-2408` (existing `$isLTSC` derivation with `$WindowsSKU -like "*LTS*"` gate)

#### Existing pattern the new function mirrors (lines 2400-2408):
```powershell
# Existing: $isLTSC derivation (the same *LTS* guard and $WindowsRelease switch)
if ($WindowsSKU -like "*LTS*") {
    switch ($WindowsRelease) {
        2016 { $WindowsVersion = '1607' }
        2019 { $WindowsVersion = '1809' }
        2021 { $WindowsVersion = '21H2' }
        2024 { $WindowsVersion = '24H2' }
    }
    $isLTSC = $true
}
```

#### New function (from upstream commit 04dfb5f — verbatim, verified):
```powershell
function Get-EffectiveDriverWindowsRelease {
    # Source: upstream commit 04dfb5f (verbatim)
    # Purpose: normalize LTSC years (2016/2019/2021/2024) to their base Windows release (10/11)
    #          so OEM driver providers receive correct release numbers
    # Place: BEFORE driver dispatch (~line 3155 elseif block), as a script-level function
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

#### Injection at driversJsonPath site (~line 2999) — before `$taskArguments` hashtable:
```powershell
# INJECT BEFORE $taskArguments = @{...}:
$driverWindowsRelease = Get-EffectiveDriverWindowsRelease -WindowsRelease $WindowsRelease -WindowsSKU $WindowsSKU
if ($driverWindowsRelease -ne $WindowsRelease) {
    WriteLog "Normalized WindowsRelease for drivers JSON processing from $WindowsRelease to $driverWindowsRelease (SKU='$WindowsSKU')."
}

$taskArguments = @{
    DriversFolder            = $DriversFolder
    WindowsRelease           = $driverWindowsRelease   # was: $WindowsRelease
    WindowsArch              = $WindowsArch
    ...
}
```

#### Injection at single-model driver dispatch site (~lines 3163-3193) — before `Invoke-BuildPhase`:
```powershell
# INJECT BEFORE the Invoke-BuildPhase -Action {} block:
$driverWindowsRelease = Get-EffectiveDriverWindowsRelease -WindowsRelease $WindowsRelease -WindowsSKU $WindowsSKU
if ($driverWindowsRelease -ne $WindowsRelease) {
    WriteLog "Normalized WindowsRelease for single-model driver processing from $WindowsRelease to $driverWindowsRelease (SKU='$WindowsSKU')."
}

# INSIDE the Invoke-BuildPhase -Action {} block, replace $WindowsRelease → $driverWindowsRelease
# for ALL OEM provider calls (HP, Microsoft, Lenovo, Dell at lines 3167/3174/3181/3189):
Get-HPDrivers ... -WindowsRelease $driverWindowsRelease ...
Get-MicrosoftDrivers ... -WindowsRelease $driverWindowsRelease ...
Get-LenovoDrivers ... -WindowsRelease $driverWindowsRelease ...
Get-DellDrivers ... -WindowsRelease $driverWindowsRelease ...
```

---

### `BuildFFUVM.ps1` — Get-WindowsTargetRuntimeState new function (D-04 propagation)

**Analog:** `BuildFFUVM.ps1:2388-2408` (the existing `installationType` + `isLTSC` + `WindowsVersion` derivation)

#### Existing derivation the function encapsulates (lines 2388-2408):
```powershell
# Existing inline logic at 2388-2408 — Get-WindowsTargetRuntimeState wraps this same logic
if (-not $installationType) {
    $installationType = if ($WindowsSKU -like "Standard*" -or $WindowsSKU -like "Datacenter*") { 'Server' } else { 'Client' }
}
if ($installationType -eq 'Server') {
    switch ($WindowsRelease) {
        2016 { $WindowsVersion = '1607' }
        2019 { $WindowsVersion = '1809' }
        2022 { $WindowsVersion = '21H2' }
        2025 { $WindowsVersion = '24H2' }
    }
}
if ($WindowsSKU -like "*LTS*") {
    switch ($WindowsRelease) { ... }
    $isLTSC = $true
}
```

#### New function (from upstream commit 5aaa1ad, fork-adapted):
```powershell
function Get-WindowsTargetRuntimeState {
    # Source: upstream commit 5aaa1ad
    # Called ONLY at post-selection update site (~4404) — NOT replacing the initial derivation at 2388-2408
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

#### Caller update at Get-Index call site (lines 4403-4404 → rewrite):
```powershell
# Current (line 4404):
$index = Get-Index -WindowsImagePath $wimPath -WindowsSKU $WindowsSKU -ISOPath $ISOPath

# Replace with:
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

### `FFU.Imaging.psd1` — version bump + FunctionsToExport update

**Analog:** `FFU.Imaging.psd1` current (lines 1-273)

#### Fields that change:
```powershell
# Line 6: bump version
ModuleVersion = '1.4.0'   # was '1.3.3' — MINOR bump for correctness fixes

# Lines 35-71: FunctionsToExport — replace 'Get-Index' with 'Get-WindowsImageSelection'
#   and add the two new companion functions:
FunctionsToExport = @(
    'Initialize-DISMService',
    'Test-WimSourceAccessibility',
    'Invoke-ExpandWindowsImageWithRetry',
    'Get-WimFromISO',
    'Get-WindowsImageSelection',     # was 'Get-Index' — RENAMED
    'Get-ResolvedWindowsSKUFromImage', # NEW companion function
    # ... (all other existing exports unchanged)
    'Add-BootFiles',                 # existing export, function signature changes
    ...
)
```

#### ReleaseNotes block pattern (copy existing PSData/ReleaseNotes structure):
```powershell
ReleaseNotes = @'
v1.4.0 - Phase 51 CORRECT-01/03/04: Capture/Boot Correctness
- Get-WindowsImageSelection: replaces Get-Index with EditionId-based matching (locale-independent)
- Get-ResolvedWindowsSKUFromImage: new companion for reverse EditionId→SKU resolution
- Add-BootFiles: now requires AdkPath + WindowsArch params; uses ADK bcdboot.exe (Secure Boot 2023 fix)
- Deleted Read-Host/while($true) fallback (ThreadJob deadlock fix)
- Auto-selects on single relevant candidate; throws with full edition log on ambiguity

v1.3.3 - ...
'@
```

---

### `FFU.Preflight.psd1` — version bump

**Analog:** `FFU.Preflight.psd1` current (lines 1-40+)

#### Fields that change:
```powershell
ModuleVersion = '1.7.0'   # was '1.6.0' — MINOR bump for new preflight check

# ReleaseNotes (in PSData section) — add:
# v1.7.0 - Phase 51 CORRECT-03: Add ADK bcdboot.exe existence check to Test-FFUADK
# - Validates ADK BCDBoot\bcdboot.exe presence during ADK preflight
# - Hard-fails early with remediation (-UpdateADK $true) if missing
# - Prevents silent Secure Boot 2023 failures that only surface at Add-BootFiles time
```

---

### `FFUDevelopment/Tests/Test-Phase51Correctness.ps1` — new test file

**Analog:** `FFUDevelopment/Tests/Test-OSPartitionLookup.ps1` (content-match tests) + `FFUDevelopment/Tests/Test-ErrorHandling.ps1` (module-load + function-call tests)

#### File header pattern (lines 1-17 from Test-OSPartitionLookup.ps1):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Phase 51 correctness fixes: CORRECT-01, CORRECT-02, CORRECT-03, CORRECT-04.

.DESCRIPTION
    Unit tests for Get-WindowsImageSelection, Get-ResolvedWindowsSKUFromImage,
    Add-BootFiles (bcdboot path), Test-FFUADK (bcdboot check), and
    Get-EffectiveDriverWindowsRelease. Uses content-match patterns for
    pure-function coverage and module-load patterns for behavioral coverage.

.NOTES
    Version: 1.0.0
    Run: Invoke-Pester -Path "D:\claude\FFUBuilder\FFUDevelopment\Tests\Test-Phase51Correctness.ps1" -Output Detailed
#>

param([switch]$Verbose)
```

#### Write-TestResult pattern (standard across all test files):
```powershell
$script:PassCount = 0
$script:FailCount = 0
$script:TestResults = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )
    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Passed   = $Passed
        Message  = $Message
    }
    if ($Passed) {
        $script:PassCount++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "         $Message" -ForegroundColor Yellow }
    }
}
```

#### Module path setup pattern (lines 49-54 from Test-ErrorHandling.ps1):
```powershell
$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$ModulesPath = Join-Path $FFUDevelopmentPath "Modules"

if ($env:PSModulePath -notlike "*$ModulesPath*") {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
}
```

#### Content-match test pattern (from Test-OSPartitionLookup.ps1:67-99 — for pure function coverage):
```powershell
# CORRECT-02: Pure function tests — no module load needed, inspect source content
$content = Get-Content -Path (Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1") -Raw -ErrorAction Stop

# Test: function exists
$hasFunction = $content -match 'function Get-EffectiveDriverWindowsRelease'
Write-TestResult -TestName "Get-EffectiveDriverWindowsRelease function defined in BuildFFUVM.ps1" -Passed $hasFunction

# Test: LTSC 2021 → 10 mapping is present
$has2021Map = $content -match '2021.*return\s+10|2019,\s*2021.*return\s+10'
Write-TestResult -TestName "LTSC 2021→10 normalization present" -Passed $has2021Map
```

#### Module-load + mock test pattern (for Get-WindowsImageSelection with DISM mock):
```powershell
# CORRECT-04/01: Module-load tests for Get-WindowsImageSelection
try {
    Import-Module (Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psd1") -Force -ErrorAction Stop
    Write-TestResult -TestName "FFU.Imaging module loads with Get-WindowsImageSelection" -Passed $true

    $exported = (Get-Module FFU.Imaging).ExportedFunctions.Keys
    Write-TestResult -TestName "Get-WindowsImageSelection exported" -Passed ('Get-WindowsImageSelection' -in $exported)
    Write-TestResult -TestName "Get-ResolvedWindowsSKUFromImage exported" -Passed ('Get-ResolvedWindowsSKUFromImage' -in $exported)
    Write-TestResult -TestName "Get-Index NOT exported (renamed)" -Passed ('Get-Index' -notin $exported)
    Write-TestResult -TestName "Add-BootFiles exported" -Passed ('Add-BootFiles' -in $exported)
}
catch {
    Write-TestResult -TestName "FFU.Imaging module loads successfully" -Passed $false -Message $_.Exception.Message
}
```

#### Should-Throw equivalent pattern (for ambiguous-candidate throw test):
```powershell
# Test that multiple candidates causes a throw (D-03)
try {
    # This test requires mocking Get-WindowsImage — content-match approach instead:
    $hasThrowOnMultiple = $content -match "throw.*No matching Windows image found"
    Write-TestResult -TestName "Get-WindowsImageSelection throws on multiple ambiguous candidates" -Passed $hasThrowOnMultiple
}
catch {
    Write-TestResult -TestName "Ambiguous-candidate throw check" -Passed $false -Message $_.Exception.Message
}
```

#### bcdboot path test pattern:
```powershell
# CORRECT-03: Add-BootFiles uses ADK bcdboot path
$imagingContent = Get-Content -Path (Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psm1") -Raw
$usesBCDBootPath = $imagingContent -match 'BCDBoot\\bcdboot\.exe'
Write-TestResult -TestName "Add-BootFiles references ADK BCDBoot path" -Passed $usesBCDBootPath

$hasTestPath = $imagingContent -match 'Test-Path.*bcdboot.*PathType Leaf|Test-Path.*bcdBootPath'
Write-TestResult -TestName "Add-BootFiles validates bcdboot.exe existence before invoking" -Passed $hasTestPath

$prefContent = Get-Content -Path (Join-Path $ModulesPath "FFU.Preflight\FFU.Preflight.psm1") -Raw
$prefHasBCDBootCheck = $prefContent -match 'BCDBoot\\bcdboot\.exe'
Write-TestResult -TestName "Test-FFUADK validates ADK bcdboot.exe existence" -Passed $prefHasBCDBootCheck
```

#### SKU→EditionId map coverage test:
```powershell
# CORRECT-04: Map completeness gate (D-06)
$imagingContent = Get-Content -Path (Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psm1") -Raw
$mandatoryMappings = @{
    "Home"              = 'Core'
    "Pro"               = 'Professional'
    "Enterprise LTSC"   = 'EnterpriseS'
    "IoT Enterprise LTSC" = 'IoTEnterpriseS'
    "Standard"          = 'ServerStandard'
    "Datacenter"        = 'ServerDatacenter'
}
foreach ($skuName in $mandatoryMappings.Keys) {
    $editionId = $mandatoryMappings[$skuName]
    $hasMapping = $imagingContent -match [regex]::Escape($editionId)
    Write-TestResult -TestName "SKU map contains EditionId '$editionId' (for '$skuName')" -Passed $hasMapping
}
```

---

### `version.json` — version bump

**Analog:** `FFUDevelopment/version.json` current (lines 1-30)

#### Fields to update:
```json
{
    "version": "1.12.0",
    "buildDate": "2026-06-26",
    "modules": {
        "FFU.Imaging": {
            "version": "1.4.0",
            "description": "Phase 51 CORRECT-01/03/04: Get-WindowsImageSelection (EditionId matching), Add-BootFiles ADK bcdboot"
        },
        "FFU.Preflight": {
            "version": "1.7.0",
            "description": "Phase 51 CORRECT-03: ADK bcdboot.exe preflight check in Test-FFUADK"
        }
    }
}
```

---

## Shared Patterns

### WriteLog (ThreadJob-safe logging) — apply to ALL new/modified code paths

**Source:** `CONVENTIONS.md:147-154` + throughout all module files

```powershell
# CORRECT pattern — WriteLog is always available in module code paths
WriteLog "Normalizing WindowsRelease from $WindowsRelease to $driverWindowsRelease for LTSC drivers."
WriteLog "WARNING: No exact EditionId match found for SKU '$WindowsSKU'."

# Safe fallback when WriteLog availability uncertain (ArtifactScanner pattern):
if ($function:WriteLog) { WriteLog $msg } else { Write-Verbose $msg }
```

**Never use:** `Write-Host`, `Read-Host`, `Write-Warning` (ThreadJob-incompatible)

### Test-Path + throw hard-fail pattern — for ADK bcdboot validation

**Source:** `FFU.Preflight.psm1:1086-1090` + `FFU.ADK.psm1:450-460`

```powershell
if (-not (Test-Path -Path $path -PathType Leaf)) {
    $errors += "Description of what's missing"
    $missingFiles += $path
}
```

For module-level (Add-BootFiles): use `throw` directly, not `$errors` accumulation.

### New-FFUCheckResult + errors array — for preflight result construction

**Source:** `FFU.Preflight.psm1:1154-1174`

```powershell
# Always accumulate to $errors, then pass to existing result builder — DO NOT bypass it:
$errors += "ADK bcdboot.exe not found (required for Secure Boot 2023 compatibility)"
$missingFiles += $bcdbootExe
# The existing if ($isValid) { New-FFUCheckResult 'Passed' } else { New-FFUCheckResult 'Failed' } block handles it
```

### Join-Path for ADK sub-paths — apply to all new ADK path construction

**Source:** `FFU.Preflight.psm1:1083`, `FFU.ADK.psm1:409`

```powershell
# Pattern: $archPath computed once, reused for all arch-specific tool paths
$archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }
$toolPath  = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$archPath\<LeafFolder>\<tool.exe>"
```

### [CmdletBinding()] + [OutputType()] on all new functions

**Source:** `CONVENTIONS.md:44-74`, `FFU.Preflight.psm1:1013-1014`

```powershell
[CmdletBinding()]
[OutputType([PSCustomObject])]   # or [string], [int], [void] as appropriate
param(...)
```

### Invoke-Process for external tool invocation

**Source:** `FFU.Imaging.psm1:1884` (current Add-BootFiles)

```powershell
# Use Invoke-Process (FFU.Core), not Start-Process or & operator, for external tools
Invoke-Process $bcdBootPath "$($OsPartitionDriveLetter):\Windows /S $($SystemPartitionDriveLetter): /F $FirmwareType" | Out-Null
```

---

## No Analog Found

All files in scope have strong analogs in the codebase. No entries in this section.

---

## Critical Implementation Notes for Planner

### Pitfall: No Pester in test files — use custom Write-TestResult framework

The existing `FFUDevelopment/Tests/*.ps1` files do NOT use Pester 5.x. They use a custom `Write-TestResult` helper function with `[PASS]`/`[FAIL]` output. `Test-Phase51Correctness.ps1` MUST follow this same framework.
RESEARCH.md's `Invoke-Pester` runner command is aspirational — the actual test structure in the repo uses the custom framework. Use content-match (`-match`) assertions instead of `Mock`/`Should -Invoke`.

### Pitfall: $ISOPath must be removed from both definition and call site

`Get-WindowsImageSelection` drops the `-ISOPath` parameter (Pitfall 2 in RESEARCH.md).
The call at `BuildFFUVM.ps1:4404` currently passes `-ISOPath $ISOPath` — this argument must also be removed.

### Pitfall: FunctionsToExport in psd1 must reflect rename

`FFU.Imaging.psd1:40` has `'Get-Index'`. This must become `'Get-WindowsImageSelection'`.
Add `'Get-ResolvedWindowsSKUFromImage'` if exported (only one external caller of Get-Index exists: `BuildFFUVM.ps1:4404`).

### Pitfall: $driverWindowsRelease must be declared in outer scope before Invoke-BuildPhase

Per RESEARCH.md Pitfall 5: declare `$driverWindowsRelease` in the outer scope BEFORE the `Invoke-BuildPhase -Action {}` scriptblock so it is captured by the closure. Do NOT declare it inside the scriptblock.

### Consumer propagation requires only one assignment

All 9 `$WindowsSKU` consumer sites (~4087, 4339, 4643, 4698, 5192, 5301, 5340, 5636, 5696) are automatically fixed by the single `$WindowsSKU = $windowsImageSelection.ResolvedWindowsSKU` at ~4404. No per-site changes required.

---

## Metadata

**Analog search scope:** `FFUDevelopment/Modules/FFU.Imaging/`, `FFUDevelopment/Modules/FFU.Preflight/`, `FFUDevelopment/Modules/FFU.ADK/`, `FFUDevelopment/Modules/FFU.ArtifactScanner/`, `FFUDevelopment/BuildFFUVM.ps1`, `FFUDevelopment/Tests/`
**Files scanned:** 9 source files read directly; 12 test files globbed
**Pattern extraction date:** 2026-06-26
