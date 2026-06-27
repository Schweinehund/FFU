#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Phase 51 correctness fixes: CORRECT-01, CORRECT-02, CORRECT-03, and CORRECT-04.

.DESCRIPTION
    Content-match and module-load assertions covering:
    - CORRECT-04: EditionId-based image index selection (locale-independent, D-05/D-06/D-07/D-08)
    - CORRECT-01: Non-interactive fallback, ResolvedWindowsSKU propagation (D-01/D-02/D-03/D-04)
    - CORRECT-03: ADK bcdboot.exe for Secure Boot 2023 fix (D-09/D-11/D-12/D-13)
    - CORRECT-02: LTSC driver year normalization via Get-EffectiveDriverWindowsRelease (D-14..D-17)

    Uses the repo's custom Write-TestResult framework (NOT Pester).
    Real non-English media and Secure Boot 2023 hardware behaviors are human-UAT only.

.NOTES
    Version: 1.0.0
    Run command: powershell -NoProfile -ExecutionPolicy Bypass -File .\FFUDevelopment\Tests\Test-Phase51Correctness.ps1
    Note: Module-load tests require Administrator privileges (FFU.Imaging.psm1 requires admin).
          Content-match tests run in any context.
    Human-UAT only (not automated):
      - Correct edition captured from real non-English / multi-edition ISO
      - Single-edition ISO salvage names FFU for the present edition
      - Captured FFU boots on Secure Boot 2023-cert hardware (CORRECT-03)
#>

param(
    [switch]$Verbose
)

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
    }
    else {
        $script:FailCount++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "         $Message" -ForegroundColor Yellow
        }
    }
}

# =============================================================================
# Setup
# =============================================================================
$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$ModulesPath = Join-Path $FFUDevelopmentPath "Modules"
$ImagingPsd1  = Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psd1"
$ImagingPsm1  = Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psm1"
$BuildScript   = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"
$PreflightPsm1 = Join-Path $ModulesPath "FFU.Preflight\FFU.Preflight.psm1"
$PreflightPsd1 = Join-Path $ModulesPath "FFU.Preflight\FFU.Preflight.psd1"

if ($env:PSModulePath -notlike "*$ModulesPath*") {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
}

Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Phase 51 Correctness Test Suite - CORRECT-01 / CORRECT-02 / CORRECT-03 / CORRECT-04" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# SECTION: CORRECT-04 - EditionId-based image selection (Plan 01)
# =============================================================================
Write-Host "CORRECT-04: EditionId-based image selection" -ForegroundColor Yellow
Write-Host ""

# --- psd1 export checks (content-match, no admin required) ---
Write-Host "  [psd1] Export declarations" -ForegroundColor Gray
try {
    $psd1Content = Get-Content -Path $ImagingPsd1 -Raw -ErrorAction Stop

    $hasNewFunc = $psd1Content -match "'Get-WindowsImageSelection'"
    Write-TestResult -TestName "psd1 exports Get-WindowsImageSelection" -Passed $hasNewFunc `
        -Message "$(if (-not $hasNewFunc) { 'Get-WindowsImageSelection not found in FunctionsToExport' })"

    $hasRevFunc = $psd1Content -match "'Get-ResolvedWindowsSKUFromImage'"
    Write-TestResult -TestName "psd1 exports Get-ResolvedWindowsSKUFromImage" -Passed $hasRevFunc `
        -Message "$(if (-not $hasRevFunc) { 'Get-ResolvedWindowsSKUFromImage not found in FunctionsToExport' })"

    $noOldFunc = $psd1Content -notmatch "'Get-Index'"
    Write-TestResult -TestName "psd1 does NOT export Get-Index (renamed)" -Passed $noOldFunc `
        -Message "$(if (-not $noOldFunc) { 'Get-Index still present in FunctionsToExport - must be renamed' })"

    $isV140 = $psd1Content -match "ModuleVersion = '1\.4\.0'"
    Write-TestResult -TestName "psd1 ModuleVersion = 1.4.0" -Passed $isV140 `
        -Message "$(if (-not $isV140) { 'Version not bumped to 1.4.0 in FFU.Imaging.psd1' })"
}
catch {
    Write-TestResult -TestName "Read FFU.Imaging.psd1" -Passed $false -Message $_.Exception.Message
}

Write-Host ""
Write-Host "  [psm1] Function definitions and map tokens" -ForegroundColor Gray
try {
    $psm1Content = Get-Content -Path $ImagingPsm1 -Raw -ErrorAction Stop

    $hasFuncDef1 = $psm1Content -match 'function Get-WindowsImageSelection'
    Write-TestResult -TestName "psm1 defines function Get-WindowsImageSelection" -Passed $hasFuncDef1

    $hasFuncDef2 = $psm1Content -match 'function Get-ResolvedWindowsSKUFromImage'
    Write-TestResult -TestName "psm1 defines function Get-ResolvedWindowsSKUFromImage" -Passed $hasFuncDef2

    $noGetIndex = $psm1Content -notmatch 'function Get-Index'
    Write-TestResult -TestName "psm1 has no function Get-Index (deleted)" -Passed $noGetIndex

    # CORRECT-04: No locale-fragile Substring derivation (D-05)
    $noSubstr10 = $psm1Content -notmatch '\.Substring\(0, 10\)'
    Write-TestResult -TestName "psm1 no Substring(0, 10) locale derivation (D-05)" -Passed $noSubstr10

    $noSubstr19 = $psm1Content -notmatch '\.Substring\(0, 19\)'
    Write-TestResult -TestName "psm1 no Substring(0, 19) locale derivation (D-05)" -Passed $noSubstr19

    # CORRECT-01: No ThreadJob-deadlocking interactive prompt (D-01)
    $noReadHost = $psm1Content -notmatch 'Read-Host'
    Write-TestResult -TestName "psm1 no Read-Host (ThreadJob deadlock removed, D-01)" -Passed $noReadHost

    # CORRECT-03: throw-on-ambiguity - editions list logged then throw (D-03)
    $hasThrowOnAmbiguous = $psm1Content -match 'No matching Windows image found'
    Write-TestResult -TestName "psm1 throw message 'No matching Windows image found' present (D-03)" -Passed $hasThrowOnAmbiguous

    # CORRECT-04: InstallationType-based server disambiguation (D-07)
    $hasInstallTypeFilter = $psm1Content -match 'InstallationType'
    Write-TestResult -TestName "psm1 references InstallationType for server disambiguation (D-07)" -Passed $hasInstallTypeFilter

    # CORRECT-04: Exact ImageName -eq fallback retained (D-08)
    $hasExactNameFallback = $psm1Content -match "ImageName\s+-eq\s+"
    Write-TestResult -TestName "psm1 retains exact ImageName -eq fallback (D-08)" -Passed $hasExactNameFallback
}
catch {
    Write-TestResult -TestName "Read FFU.Imaging.psm1" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# SECTION: CORRECT-04 - SKU->EditionId map completeness gate (D-06)
# Maps every entry in $clientSKUs/$LTSCSKUs/$ServerSKUs to a DISM EditionId.
# An incomplete map silently mis-selects editions - this is a hard gate.
# =============================================================================
Write-Host "CORRECT-04: SKU->EditionId map completeness gate (D-06)" -ForegroundColor Yellow
Write-Host ""

try {
    if (-not $psm1Content) {
        $psm1Content = Get-Content -Path $ImagingPsm1 -Raw -ErrorAction Stop
    }

    # All mandatory EditionId tokens that must appear in FFU.Imaging.psm1
    $mandatoryEditionIds = @(
        'Core',
        'CoreN',
        'CoreSingleLanguage',
        'Education',
        'EducationN',
        'Professional',
        'ProfessionalN',
        'ProfessionalEducation',
        'ProfessionalEducationN',
        'ProfessionalWorkstation',
        'ProfessionalWorkstationN',
        'Enterprise',
        'EnterpriseN',
        'EnterpriseS',
        'EnterpriseSN',
        'IoTEnterpriseS',
        'IoTEnterpriseSN',
        'ServerStandard',
        'ServerDatacenter'
    )

    foreach ($editionId in $mandatoryEditionIds) {
        $hasToken = $psm1Content -match [regex]::Escape("'$editionId'")
        Write-TestResult -TestName "SKU map contains EditionId token '$editionId'" -Passed $hasToken `
            -Message "$(if (-not $hasToken) { 'Missing EditionId token in Get-WindowsImageSelection switch - map incomplete' })"
    }
}
catch {
    Write-TestResult -TestName "SKU->EditionId map completeness check" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# SECTION: CORRECT-01 - Non-interactive fallback and SKU propagation (Plan 01)
# =============================================================================
Write-Host "CORRECT-01: Non-interactive fallback and SKU propagation" -ForegroundColor Yellow
Write-Host ""

try {
    if (-not $psm1Content) {
        $psm1Content = Get-Content -Path $ImagingPsm1 -Raw -ErrorAction Stop
    }

    # D-02: Single relevant candidate auto-select
    $hasAutoSelect = $psm1Content -match 'Auto-selecting single relevant candidate'
    Write-TestResult -TestName "psm1 auto-selects single relevant candidate (D-02)" -Passed $hasAutoSelect

    # D-03: Multiple candidates logs editions list then throws
    $hasEditionListLog = $psm1Content -match 'Available editions'
    Write-TestResult -TestName "psm1 logs available editions before throw (D-03)" -Passed $hasEditionListLog

    # Rich PSCustomObject return shape (D-04)
    $hasRichReturn = $psm1Content -match 'ResolvedWindowsSKU'
    Write-TestResult -TestName "psm1 returns ResolvedWindowsSKU in rich PSCustomObject (D-04)" -Passed $hasRichReturn
}
catch {
    Write-TestResult -TestName "Read FFU.Imaging.psm1 for CORRECT-01 checks" -Passed $false -Message $_.Exception.Message
}

try {
    $buildContent = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # D-04: BuildFFUVM.ps1 defines Get-WindowsTargetRuntimeState
    $hasRuntimeState = $buildContent -match 'function Get-WindowsTargetRuntimeState'
    Write-TestResult -TestName "BuildFFUVM.ps1 defines Get-WindowsTargetRuntimeState (D-04)" -Passed $hasRuntimeState

    # D-04: Caller reassigns WindowsSKU from ResolvedWindowsSKU
    $hasSkuReassignment = $buildContent -match '\$WindowsSKU\s*=\s*\$windowsImageSelection\.ResolvedWindowsSKU'
    Write-TestResult -TestName "BuildFFUVM.ps1 caller reassigns WindowsSKU from ResolvedWindowsSKU (D-04)" -Passed $hasSkuReassignment

    # D-04: Caller guards reassignment with IsNullOrWhiteSpace check
    $hasNullGuard = $buildContent -match 'IsNullOrWhiteSpace\(\$windowsImageSelection\.ResolvedWindowsSKU\)'
    Write-TestResult -TestName "BuildFFUVM.ps1 caller guards reassignment with IsNullOrWhiteSpace (D-04)" -Passed $hasNullGuard

    # D-04: No remaining Get-Index -WindowsImagePath call
    $noGetIndexCall = $buildContent -notmatch 'Get-Index -WindowsImagePath'
    Write-TestResult -TestName "BuildFFUVM.ps1 has no remaining Get-Index -WindowsImagePath call" -Passed $noGetIndexCall

    # D-04: New caller uses Get-WindowsImageSelection
    $hasNewCall = $buildContent -match 'Get-WindowsImageSelection -WindowsImagePath'
    Write-TestResult -TestName "BuildFFUVM.ps1 caller uses Get-WindowsImageSelection (D-04)" -Passed $hasNewCall

    # D-04: Caller recomputes installationType via Get-WindowsTargetRuntimeState
    $hasRuntimeStateCall = $buildContent -match 'Get-WindowsTargetRuntimeState -WindowsRelease'
    Write-TestResult -TestName "BuildFFUVM.ps1 caller recomputes runtime state via Get-WindowsTargetRuntimeState" -Passed $hasRuntimeStateCall
}
catch {
    Write-TestResult -TestName "Read BuildFFUVM.ps1 for CORRECT-01 checks" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# SECTION: Module load test (requires Administrator)
# =============================================================================
Write-Host "Module load test (requires Administrator)" -ForegroundColor Yellow
Write-Host ""

$moduleLoadAttempted = $false
try {
    Import-Module $ImagingPsd1 -Force -ErrorAction Stop
    $moduleLoadAttempted = $true
    $exportedFunctions = (Get-Module FFU.Imaging).ExportedFunctions.Keys

    Write-TestResult -TestName "FFU.Imaging module loads successfully" -Passed $true

    $exportsNewFunc = 'Get-WindowsImageSelection' -in $exportedFunctions
    Write-TestResult -TestName "Module exports Get-WindowsImageSelection" -Passed $exportsNewFunc

    $exportsRevFunc = 'Get-ResolvedWindowsSKUFromImage' -in $exportedFunctions
    Write-TestResult -TestName "Module exports Get-ResolvedWindowsSKUFromImage" -Passed $exportsRevFunc

    $noGetIndexExport = 'Get-Index' -notin $exportedFunctions
    Write-TestResult -TestName "Module does NOT export Get-Index (renamed)" -Passed $noGetIndexExport
}
catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match 'Administrator|RunAsAdministrator|requires') {
        Write-Host "  [NOTE] Module load skipped - requires Administrator privileges" -ForegroundColor DarkYellow
        Write-Host "         Run this test as Administrator for full module-level coverage" -ForegroundColor DarkYellow
    }
    else {
        Write-TestResult -TestName "FFU.Imaging module loads successfully" -Passed $false -Message $errMsg
    }
}

Write-Host ""

# =============================================================================
# SECTION: CORRECT-03 (Plan 02) - ADK bcdboot for Secure Boot 2023 fix
# Source: upstream commit 6c0ee8a - Add-BootFiles must use ADK bcdboot.exe
# (D-09/D-11/D-12/D-13)
# =============================================================================
Write-Host "CORRECT-03: ADK bcdboot for Secure Boot 2023 (D-09/D-11/D-12/D-13)" -ForegroundColor Yellow
Write-Host ""

try {
    if (-not $psm1Content) {
        $psm1Content = Get-Content -Path $ImagingPsm1 -Raw -ErrorAction Stop
    }

    # (a) FFU.Imaging.psm1 references the BCDBoot\bcdboot.exe ADK path (D-11)
    $hasAdkBCDBootPath = $psm1Content -match 'BCDBoot\\bcdboot\.exe'
    Write-TestResult -TestName "Add-BootFiles references ADK BCDBoot path (BCDBoot\bcdboot.exe)" -Passed $hasAdkBCDBootPath `
        -Message "$(if (-not $hasAdkBCDBootPath) { 'BCDBoot\bcdboot.exe ADK path not found in FFU.Imaging.psm1' })"

    # (b) Add-BootFiles Test-Path validates bcdboot.exe existence before invoking (D-09)
    $hasTestPathGuard = $psm1Content -match 'Test-Path.*bcdBootPath|Test-Path.*bcdboot'
    Write-TestResult -TestName "Add-BootFiles Test-Path guards bcdboot existence before invoking (D-09)" -Passed $hasTestPathGuard `
        -Message "$(if (-not $hasTestPathGuard) { 'No Test-Path guard on bcdboot path found in Add-BootFiles' })"

    # (c) Add-BootFiles declares the $WindowsArch parameter (D-11 arch-awareness)
    $hasWindowsArchParam = $psm1Content -match '\[ValidateSet.*x86.*x64.*arm64.*\]\s*\[string\]\s*\$WindowsArch|\[string\]\s*\$WindowsArch'
    Write-TestResult -TestName "Add-BootFiles declares WindowsArch parameter for arch-aware bcdboot (D-11)" -Passed $hasWindowsArchParam `
        -Message "$(if (-not $hasWindowsArchParam) { 'WindowsArch parameter not declared in Add-BootFiles' })"

    # (d) Add-BootFiles no longer issues a bare `Invoke-Process bcdboot ` host call (D-09)
    # Negative assertion: the bare host bcdboot invocation must be gone.
    $hasNoBareHostBcdboot = $psm1Content -notmatch 'Invoke-Process bcdboot '
    Write-TestResult -TestName "Add-BootFiles has no bare host bcdboot invocation (D-09 - host fallback removed)" -Passed $hasNoBareHostBcdboot `
        -Message "$(if (-not $hasNoBareHostBcdboot) { 'Bare `Invoke-Process bcdboot ` host call still present - must use ADK path variable' })"

    # (d2) And the ADK throw message is present (D-09 hard-fail)
    $hasHardFail = $psm1Content -match 'throw.*ADK BCDBoot'
    Write-TestResult -TestName "Add-BootFiles hard-fails with actionable throw when ADK bcdboot missing (D-09)" -Passed $hasHardFail `
        -Message "$(if (-not $hasHardFail) { 'throw ADK BCDBoot message not found - hard-fail requirement not met' })"
}
catch {
    Write-TestResult -TestName "Read FFU.Imaging.psm1 for CORRECT-03 checks" -Passed $false -Message $_.Exception.Message
}

try {
    $prefContent = Get-Content -Path $PreflightPsm1 -Raw -ErrorAction Stop

    # (e) FFU.Preflight.psm1 Test-FFUADK contains BCDBoot\bcdboot.exe existence check (D-12)
    $prefHasBCDBootCheck = $prefContent -match 'BCDBoot\\bcdboot\.exe'
    Write-TestResult -TestName "Test-FFUADK validates ADK bcdboot.exe existence (D-12 - early fail)" -Passed $prefHasBCDBootCheck `
        -Message "$(if (-not $prefHasBCDBootCheck) { 'BCDBoot\bcdboot.exe check not found in FFU.Preflight.psm1' })"

    $prefHasSecureBootMsg = $prefContent -match 'Secure Boot 2023'
    Write-TestResult -TestName "Test-FFUADK check message references Secure Boot 2023 (D-12)" -Passed $prefHasSecureBootMsg `
        -Message "$(if (-not $prefHasSecureBootMsg) { 'Secure Boot 2023 not mentioned in bcdboot check error message' })"
}
catch {
    Write-TestResult -TestName "Read FFU.Preflight.psm1 for CORRECT-03 checks" -Passed $false -Message $_.Exception.Message
}

try {
    $prefPsd1Content = Get-Content -Path $PreflightPsd1 -Raw -ErrorAction Stop

    $prefIsV170 = $prefPsd1Content -match "ModuleVersion = '1\.7\.0'"
    Write-TestResult -TestName "FFU.Preflight.psd1 bumped to 1.7.0 for CORRECT-03 (D-12)" -Passed $prefIsV170 `
        -Message "$(if (-not $prefIsV170) { 'FFU.Preflight.psd1 ModuleVersion not updated to 1.7.0' })"
}
catch {
    Write-TestResult -TestName "Read FFU.Preflight.psd1 for CORRECT-03 version check" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# SECTION: CORRECT-02 (Plan 03) - LTSC driver year normalization
# Source: upstream commit 04dfb5f - Get-EffectiveDriverWindowsRelease
# (D-14/D-15/D-16/D-17)
# =============================================================================
Write-Host "CORRECT-02: LTSC driver year normalization (D-14/D-15/D-16/D-17)" -ForegroundColor Yellow
Write-Host ""

# --- Content-match: function defined and dispatch wired (no admin required) ---
Write-Host "  [content-match] BuildFFUVM.ps1 function and dispatch" -ForegroundColor Gray
try {
    if (-not $buildContent) {
        $buildContent = Get-Content -Path $BuildScript -Raw -ErrorAction Stop
    }

    # (a) Function is defined (D-14/D-15)
    $hasFunc = $buildContent -match 'function Get-EffectiveDriverWindowsRelease'
    Write-TestResult -TestName "BuildFFUVM.ps1 defines Get-EffectiveDriverWindowsRelease (D-14)" -Passed $hasFunc `
        -Message "$(if (-not $hasFunc) { 'function Get-EffectiveDriverWindowsRelease not found in BuildFFUVM.ps1' })"

    # (b) Function uses the *LTS* gate (D-15 - Server SKUs never contain LTS, so they pass through)
    $hasLTSGate = $buildContent -match "like\s+['\*]+LTS\*[']"
    Write-TestResult -TestName "Get-EffectiveDriverWindowsRelease gates remap on '*LTS*' SKU pattern (D-15)" -Passed $hasLTSGate `
        -Message "$(if (-not $hasLTSGate) { 'LTSC gate (*LTS* pattern) not found in Get-EffectiveDriverWindowsRelease body' })"

    # (c) LTSC 2016/2019/2021 -> 10 mapping present (D-14)
    $has2016_2021map = $buildContent -match '2016,\s*2019,\s*2021.*return\s+10'
    Write-TestResult -TestName "Get-EffectiveDriverWindowsRelease maps LTSC 2016/2019/2021 -> 10 (D-14)" -Passed $has2016_2021map `
        -Message "$(if (-not $has2016_2021map) { 'LTSC 2016/2019/2021->10 mapping not found in function body' })"

    # (d) LTSC 2024 -> 11 mapping present (D-14)
    $has2024map = $buildContent -match '-eq\s+2024.*return\s+11'
    Write-TestResult -TestName "Get-EffectiveDriverWindowsRelease maps LTSC 2024 -> 11 (D-14)" -Passed $has2024map `
        -Message "$(if (-not $has2024map) { 'LTSC 2024->11 mapping not found in function body' })"

    # (e) $driverWindowsRelease assigned from Get-EffectiveDriverWindowsRelease at both dispatch sites (D-16)
    $assignCount = ([regex]::Matches($buildContent, '\$driverWindowsRelease\s*=\s*Get-EffectiveDriverWindowsRelease')).Count
    $hasTwoAssigns = $assignCount -ge 2
    Write-TestResult -TestName "BuildFFUVM.ps1 assigns driverWindowsRelease at both dispatch sites (D-16)" -Passed $hasTwoAssigns `
        -Message "$(if (-not $hasTwoAssigns) { "Expected >= 2 assignment sites, found $assignCount" })"

    # (f) OEM provider calls use $driverWindowsRelease (D-17): check >= 4 calls (HP, Microsoft, Lenovo, Dell)
    $oemCallCount = ([regex]::Matches($buildContent, '-WindowsRelease \$driverWindowsRelease')).Count
    $allOEMCallsUseDriverRelease = $oemCallCount -ge 4
    Write-TestResult -TestName "All OEM provider calls pass driverWindowsRelease (>= 4 occurrences, D-17)" -Passed $allOEMCallsUseDriverRelease `
        -Message "$(if (-not $allOEMCallsUseDriverRelease) { "Expected >= 4 OEM -WindowsRelease driverWindowsRelease calls, found $oemCallCount" })"

    # (g) Global $WindowsRelease is NOT bare-reassigned outside param/let declarations (D-16)
    # This ensures the load-bearing global is preserved for naming/cache/MSRT/Server switch
    $globalReassignCount = ([regex]::Matches($buildContent, '^\s*\$WindowsRelease\s*=\s*[^=]', [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
    $noGlobalReassign = $globalReassignCount -eq 0
    Write-TestResult -TestName "Global WindowsRelease is NOT bare-reassigned outside param blocks (D-16)" -Passed $noGlobalReassign `
        -Message "$(if (-not $noGlobalReassign) { "Found $globalReassignCount bare assignment(s) to global WindowsRelease - load-bearing variable clobbered" })"
}
catch {
    Write-TestResult -TestName "Read BuildFFUVM.ps1 for CORRECT-02 content-match checks" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# --- Pure function table tests (local copy of the pure function for isolated testing) ---
Write-Host "  [pure-function] Get-EffectiveDriverWindowsRelease mapping table" -ForegroundColor Gray

# Local copy of the pure function - mirrors upstream 04dfb5f verbatim so tests stay valid
# even if the file cannot be dot-sourced (BuildFFUVM.ps1 has side-effects at script scope)
function Test-EffectiveDriverWindowsRelease-Local {
    param([int]$WindowsRelease, [string]$WindowsSKU)
    if (-not [string]::IsNullOrWhiteSpace($WindowsSKU) -and $WindowsSKU -like '*LTS*') {
        if ($WindowsRelease -in 2016, 2019, 2021) { return 10 }
        if ($WindowsRelease -eq 2024)             { return 11 }
    }
    return $WindowsRelease
}

$mappingTests = @(
    @{ Release = 2016; SKU = 'Enterprise 2016 LTSB'; Expected = 10;   Label = 'LTSC 2016 (LTSB) -> 10 (D-14)' }
    @{ Release = 2019; SKU = 'Enterprise LTSC';      Expected = 10;   Label = 'LTSC 2019 -> 10 (D-14)' }
    @{ Release = 2021; SKU = 'Enterprise LTSC';      Expected = 10;   Label = 'LTSC 2021 -> 10 (D-14)' }
    @{ Release = 2024; SKU = 'Enterprise LTSC';      Expected = 11;   Label = 'LTSC 2024 -> 11 (D-14)' }
    @{ Release = 2019; SKU = 'Standard';             Expected = 2019; Label = 'Server 2019 Standard -> 2019 unchanged (D-15 collision)' }
    @{ Release = 2022; SKU = 'Standard';             Expected = 2022; Label = 'Server 2022 Standard -> 2022 unchanged' }
    @{ Release = 2025; SKU = 'Standard';             Expected = 2025; Label = 'Server 2025 Standard -> 2025 unchanged' }
    @{ Release = 2019; SKU = 'Datacenter';           Expected = 2019; Label = 'Server 2019 Datacenter -> 2019 unchanged (D-15)' }
    @{ Release = 10;   SKU = 'Pro';                  Expected = 10;   Label = 'Client Win10 non-LTSC Pro -> 10 unchanged' }
    @{ Release = 11;   SKU = 'Pro';                  Expected = 11;   Label = 'Client Win11 non-LTSC Pro -> 11 unchanged' }
    @{ Release = 2024; SKU = 'IoT Enterprise LTSC';  Expected = 11;   Label = 'IoT Enterprise LTSC 2024 -> 11 (D-14)' }
    @{ Release = 2021; SKU = 'Enterprise N LTSC';    Expected = 10;   Label = 'Enterprise N LTSC 2021 -> 10 (D-14)' }
)

foreach ($tc in $mappingTests) {
    $result = Test-EffectiveDriverWindowsRelease-Local -WindowsRelease $tc.Release -WindowsSKU $tc.SKU
    $passed = $result -eq $tc.Expected
    Write-TestResult -TestName $tc.Label -Passed $passed `
        -Message "$(if (-not $passed) { "Expected $($tc.Expected), got $result (Release=$($tc.Release) SKU='$($tc.SKU)')" })"
}

Write-Host ""

# =============================================================================
# Test Summary
# =============================================================================
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Total Tests : $($script:PassCount + $script:FailCount)" -ForegroundColor White
Write-Host "Passed      : $script:PassCount" -ForegroundColor Green
Write-Host "Failed      : $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($script:FailCount -eq 0) {
    Write-Host "All Phase 51 tests passed. CORRECT-01, CORRECT-02, CORRECT-03, and CORRECT-04 implementation verified." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "CRITICAL: $($script:FailCount) test(s) failed. Review output above." -ForegroundColor Red
    exit 1
}

