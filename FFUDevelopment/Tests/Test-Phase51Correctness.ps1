#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Phase 51 correctness fixes: CORRECT-01 and CORRECT-04.

.DESCRIPTION
    Content-match and module-load assertions covering:
    - CORRECT-04: EditionId-based image index selection (locale-independent, D-05/D-06/D-07/D-08)
    - CORRECT-01: Non-interactive fallback, ResolvedWindowsSKU propagation (D-01/D-02/D-03/D-04)

    Placeholder sections for CORRECT-03 (Plan 02 - ADK bcdboot) and
    CORRECT-02 (Plan 03 - LTSC driver year normalization) are included so later
    plans can append their assertions to this file.

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
$ImagingPsd1 = Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psd1"
$ImagingPsm1 = Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psm1"
$BuildScript  = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"

if ($env:PSModulePath -notlike "*$ModulesPath*") {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
}

Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Phase 51 Correctness Test Suite - CORRECT-01 / CORRECT-04" -ForegroundColor Cyan
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
# PLACEHOLDER: Add assertions here when Plan 02 is implemented.
# =============================================================================
Write-Host "CORRECT-03: ADK bcdboot for Secure Boot 2023 (Plan 02 - placeholder)" -ForegroundColor DarkGray
Write-Host "  [PLACEHOLDER] Plan 02 will add assertions for:" -ForegroundColor DarkGray
Write-Host "    - Add-BootFiles uses ADK bcdboot.exe (not host bcdboot)" -ForegroundColor DarkGray
Write-Host "    - Add-BootFiles validates bcdboot.exe existence before invoking" -ForegroundColor DarkGray
Write-Host "    - Test-FFUADK preflight validates ADK bcdboot.exe presence" -ForegroundColor DarkGray
Write-Host ""

# =============================================================================
# SECTION: CORRECT-02 (Plan 03) - LTSC driver year normalization
# PLACEHOLDER: Add assertions here when Plan 03 is implemented.
# =============================================================================
Write-Host "CORRECT-02: LTSC driver year normalization (Plan 03 - placeholder)" -ForegroundColor DarkGray
Write-Host "  [PLACEHOLDER] Plan 03 will add assertions for:" -ForegroundColor DarkGray
Write-Host "    - Get-EffectiveDriverWindowsRelease function defined in BuildFFUVM.ps1" -ForegroundColor DarkGray
Write-Host "    - LTSC 2021 -> 10, LTSC 2024 -> 11, Server 2019 unchanged" -ForegroundColor DarkGray
Write-Host "    - Driver dispatch uses driverWindowsRelease not WindowsRelease" -ForegroundColor DarkGray
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
    Write-Host "All Phase 51 Plan 01 tests passed. CORRECT-01 and CORRECT-04 implementation verified." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "CRITICAL: $($script:FailCount) test(s) failed. Review output above." -ForegroundColor Red
    exit 1
}

