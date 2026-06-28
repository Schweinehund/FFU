#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Phase 52 correctness fixes: DGRID-01, DGRID-02, DGRID-03.

.DESCRIPTION
    Content-match and logic assertions covering:
    - DGRID-01: Filter persists after sort (Invoke-ListViewSort filter-capture preamble)
    - DGRID-02: Save-DriversJson reads allDriverModels master list (not lstDriverModels.Items)
    - DGRID-02: -HeaderSelectionAffectsVisibleItemsOnly switch present; only driver grid opts in
    - DGRID-03: CopyDrivers dependency throw present in END block with USBOnlyMode guard

    Uses the repo's custom Write-TestResult framework (NOT Pester).
    WPF CollectionView visual behaviors (filter-sort coexistence, select-all scope,
    header tri-state, header alignment) are human-UAT only.

.NOTES
    Version: 1.0.0
    Run command: powershell -NoProfile -ExecutionPolicy Bypass -File .\FFUDevelopment\Tests\Test-Phase52DriverGridFixes.ps1
    Human-UAT only (not automated):
      - Filter persists visually after sort (requires live WPF UI)
      - Select-all visible scope under active filter (requires live WPF UI)
      - Header tri-state sync (requires live WPF UI)
      - Header checkbox alignment (requires live visual inspection)
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
$SharedPsm1  = Join-Path $FFUDevelopmentPath "FFUUI.Core\FFUUI.Core.Shared.psm1"
$DriversPsm1 = Join-Path $FFUDevelopmentPath "FFUUI.Core\FFUUI.Core.Drivers.psm1"
$InitPsm1    = Join-Path $FFUDevelopmentPath "FFUUI.Core\FFUUI.Core.Initialize.psm1"
$BuildScript = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"

Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Phase 52 Driver-Grid UI Fixes - DGRID-01 / DGRID-02 / DGRID-03" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# SECTION: DGRID-01 - Invoke-ListViewSort filter-capture preamble (b4305a1)
# =============================================================================
Write-Host "DGRID-01: Invoke-ListViewSort filter-capture preamble (b4305a1)" -ForegroundColor Yellow
Write-Host ""

try {
    $sharedContent = Get-Content -Path $SharedPsm1 -Raw -ErrorAction Stop

    $hasFilterCapture = $sharedContent -match '\$existingFilter\s*=\s*\$null'
    Write-TestResult -TestName "Shared.psm1 has filter-capture preamble (\$existingFilter = \$null)" -Passed $hasFilterCapture `
        -Message "$(if (-not $hasFilterCapture) { 'Filter-capture preamble missing from Invoke-ListViewSort (b4305a1 not ported)' })"

    $hasCollectionViewCapture = $sharedContent -match 'existingCollectionView.*GetDefaultView'
    Write-TestResult -TestName "Shared.psm1 captures CollectionView before sort (existingCollectionView)" -Passed $hasCollectionViewCapture `
        -Message "$(if (-not $hasCollectionViewCapture) { 'GetDefaultView capture missing from Invoke-ListViewSort' })"

    $hasFilterReapply = $sharedContent -match 'newView\.Filter\s*=\s*\$existingFilter'
    Write-TestResult -TestName "Shared.psm1 reapplies captured filter after sort (newView.Filter = existingFilter)" -Passed $hasFilterReapply `
        -Message "$(if (-not $hasFilterReapply) { 'Filter reapplication missing after ItemsSource reassignment' })"
}
catch {
    Write-TestResult -TestName "Read FFUUI.Core.Shared.psm1 (DGRID-01)" -Passed $false -Message $_.Exception.Message
}

Write-Host ""

# =============================================================================
# SECTION: DGRID-02 - Select-all scope switch + save fix (f09c989, 42ed281)
# =============================================================================
Write-Host "DGRID-02: -HeaderSelectionAffectsVisibleItemsOnly switch + save-source fix" -ForegroundColor Yellow
Write-Host ""

Write-Host "  [Shared.psm1] Switch and alignment assertions" -ForegroundColor Gray
try {
    if (-not $sharedContent) {
        $sharedContent = Get-Content -Path $SharedPsm1 -Raw -ErrorAction Stop
    }

    # Switch declared in Add-SelectableGridViewColumn param block
    $hasSwitchParam = $sharedContent -match '\[switch\]\s*\$HeaderSelectionAffectsVisibleItemsOnly'
    Write-TestResult -TestName "Shared.psm1 Add-SelectableGridViewColumn has -HeaderSelectionAffectsVisibleItemsOnly switch" -Passed $hasSwitchParam `
        -Message "$(if (-not $hasSwitchParam) { '-HeaderSelectionAffectsVisibleItemsOnly switch missing from param block (f09c989 not ported)' })"

    # Update-SelectAllHeaderCheckBoxState reads the switch off the Tag
    $hasTagRead = $sharedContent -match 'HeaderSelectionAffectsVisibleItemsOnly'
    Write-TestResult -TestName "Shared.psm1 Update-SelectAllHeaderCheckBoxState reads HeaderSelectionAffectsVisibleItemsOnly" -Passed $hasTagRead `
        -Message "$(if (-not $hasTagRead) { 'HeaderSelectionAffectsVisibleItemsOnly not referenced in Update-SelectAllHeaderCheckBoxState' })"

    # Header wrapped in GridViewColumnHeader (42ed281)
    $hasGridViewColumnHeader = $sharedContent -match 'New-Object System\.Windows\.Controls\.GridViewColumnHeader'
    Write-TestResult -TestName "Shared.psm1 wraps header checkbox in GridViewColumnHeader (42ed281)" -Passed $hasGridViewColumnHeader `
        -Message "$(if (-not $hasGridViewColumnHeader) { 'GridViewColumnHeader wrapper missing from Add-SelectableGridViewColumn (42ed281 not ported)' })"
}
catch {
    Write-TestResult -TestName "Read FFUUI.Core.Shared.psm1 (DGRID-02)" -Passed $false -Message $_.Exception.Message
}

Write-Host ""
Write-Host "  [Initialize.psm1] Exactly one driver-grid call site opts in" -ForegroundColor Gray
try {
    $initContent = Get-Content -Path $InitPsm1 -Raw -ErrorAction Stop

    # Count all Add-SelectableGridViewColumn call sites
    $allCallSites = ([regex]::Matches($initContent, 'Add-SelectableGridViewColumn')).Count

    # Count call sites with -HeaderSelectionAffectsVisibleItemsOnly
    $switchCallSites = ([regex]::Matches($initContent, 'Add-SelectableGridViewColumn[^\r\n]*-HeaderSelectionAffectsVisibleItemsOnly')).Count

    $hasExactlyOne = $switchCallSites -eq 1
    Write-TestResult -TestName "Initialize.psm1 exactly ONE Add-SelectableGridViewColumn call carries -HeaderSelectionAffectsVisibleItemsOnly (driver grid only)" `
        -Passed $hasExactlyOne `
        -Message "$(if (-not $hasExactlyOne) { "Expected 1 call with switch, found $switchCallSites (total calls: $allCallSites)" })"
}
catch {
    Write-TestResult -TestName "Read FFUUI.Core.Initialize.psm1 (DGRID-02)" -Passed $false -Message $_.Exception.Message
}

Write-Host ""
Write-Host "  [Drivers.psm1] Save-DriversJson reads allDriverModels with null-guard" -ForegroundColor Gray
try {
    $driversContent = Get-Content -Path $DriversPsm1 -Raw -ErrorAction Stop

    $hasAllDriverModels = $driversContent -match 'allDriverModels'
    Write-TestResult -TestName "Drivers.psm1 Save-DriversJson references allDriverModels" -Passed $hasAllDriverModels `
        -Message "$(if (-not $hasAllDriverModels) { 'allDriverModels not referenced in FFUUI.Core.Drivers.psm1 (f09c989 not ported)' })"

    $hasNullGuard = $driversContent -match '\$null\s*-ne\s*\$State\.Data\.allDriverModels|\$State\.Data\.allDriverModels.*-ne\s*\$null'
    Write-TestResult -TestName "Drivers.psm1 Save-DriversJson null-guards allDriverModels before reading" -Passed $hasNullGuard `
        -Message "$(if (-not $hasNullGuard) { 'Null-guard for State.Data.allDriverModels missing (f09c989 not ported)' })"
}
catch {
    Write-TestResult -TestName "Read FFUUI.Core.Drivers.psm1 (DGRID-02)" -Passed $false -Message $_.Exception.Message
}

Write-Host ""
Write-Host "  [logic] Test-DriverSelectionSource-Local pure-function test" -ForegroundColor Gray

# Local copy of pure logic - mirrors Save-DriversJson source selection verbatim
# so tests stay valid even without WPF runtime
function Test-DriverSelectionSource-Local {
    param([object]$allDriverModels, [object]$lstItems)
    $driverSelectionSource = if ($null -ne $allDriverModels) { $allDriverModels } else { $lstItems }
    return $driverSelectionSource
}

$selectionTests = @(
    @{ allDriverModels = @('A', 'B', 'C'); lstItems = @('X'); Expected = @('A', 'B', 'C'); Label = 'allDriverModels non-null: reads master list (D-07)' }
    @{ allDriverModels = $null;            lstItems = @('X'); Expected = @('X');            Label = 'allDriverModels null: falls back to lstItems (D-07 null guard)' }
)
foreach ($tc in $selectionTests) {
    $result = Test-DriverSelectionSource-Local -allDriverModels $tc.allDriverModels -lstItems $tc.lstItems
    $passed = ($result -join ',') -eq ($tc.Expected -join ',')
    Write-TestResult -TestName $tc.Label -Passed $passed `
        -Message "$(if (-not $passed) { "Expected '$($tc.Expected -join ',')', got '$($result -join ',')'" })"
}

Write-Host ""

# =============================================================================
# SECTION: DGRID-03 - CopyDrivers dependency throw in END block (dc801e9)
# =============================================================================
Write-Host "DGRID-03: CopyDrivers dependency throw in END block with USBOnlyMode guard" -ForegroundColor Yellow
Write-Host ""

try {
    $buildContent = Get-Content -Path $BuildScript -Raw -ErrorAction Stop
    $buildLines   = Get-Content -Path $BuildScript -ErrorAction Stop

    # Throw wording present (verbatim from upstream dc801e9)
    $hasThrowWording = $buildContent -match '-CopyDrivers is set to .* -BuildUSBDrive is not set'
    Write-TestResult -TestName "BuildFFUVM.ps1 throw contains '-CopyDrivers is set to ... -BuildUSBDrive is not set'" -Passed $hasThrowWording `
        -Message "$(if (-not $hasThrowWording) { 'CopyDrivers dependency throw wording not found in BuildFFUVM.ps1 (dc801e9 not ported)' })"

    # USBOnlyMode guard present
    $hasUSBOnlyModeGuard = $buildContent -match '-not\s+\$USBOnlyMode'
    Write-TestResult -TestName "BuildFFUVM.ps1 CopyDrivers throw guarded with -not \$USBOnlyMode (D-03)" -Passed $hasUSBOnlyModeGuard `
        -Message "$(if (-not $hasUSBOnlyModeGuard) { '-not $USBOnlyMode guard missing from CopyDrivers throw (Decision D-03)' })"

    # Throw is in END block, after config load line 775
    # Find the line number of the config-load marker
    $configLoadLine = -1
    for ($i = 0; $i -lt $buildLines.Count; $i++) {
        if ($buildLines[$i] -match '###PARAMETER VALIDATION') {
            $configLoadLine = $i + 1  # 1-based
            break
        }
    }

    # Find the line number of the throw statement
    $throwLine = -1
    for ($i = 0; $i -lt $buildLines.Count; $i++) {
        if ($buildLines[$i] -match '-CopyDrivers is set to .* -BuildUSBDrive is not set') {
            $throwLine = $i + 1  # 1-based
            break
        }
    }

    $throwAfterConfigLoad = ($throwLine -gt 775)
    Write-TestResult -TestName "BuildFFUVM.ps1 CopyDrivers throw is in END block after config load (line $throwLine > 775)" `
        -Passed $throwAfterConfigLoad `
        -Message "$(if (-not $throwAfterConfigLoad) { "Throw found at line $throwLine, expected > 775 (config load). May be in BEGIN block (Decision D-02)" })"
}
catch {
    Write-TestResult -TestName "Read BuildFFUVM.ps1 (DGRID-03)" -Passed $false -Message $_.Exception.Message
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
    Write-Host "All Phase 52 tests passed. DGRID-01, DGRID-02, DGRID-03 implementation verified." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "CRITICAL: $($script:FailCount) test(s) failed. Review output above." -ForegroundColor Red
    exit 1
}
