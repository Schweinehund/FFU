<#
.SYNOPSIS
    Orchestration script for FFU VM deployment tasks

.DESCRIPTION
    This script orchestrates the following deployment tasks:
    - Install-Office.ps1
    - Update-Defender.ps1
    - Update-MSRT.ps1
    - Update-OneDrive.ps1
    - Update-Edge.ps1
    - Install-Win32Apps.ps1
    - Invoke-AppsScript.ps1
    - Install-UserApps.ps1
    - Install-StoreApps.ps1
    - Run-DiskCleanup.ps1
    - Run-Sysprep.ps1

    The script will check for the presence of each of these files and if they exist, will run the script
#>

# Header

Write-Host "---------------------------------------------------" -ForegroundColor Yellow
Write-Host "             FFU Builder Orchestrator              " -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor Yellow

# Define the path to the scripts
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ============================================================================
# Execution Tracking (REL-WINPE-02)
# Tracks script execution status for summary reporting
# ============================================================================
$script:executionSummary = @{
    Executed = [System.Collections.ArrayList]@()
    Skipped = [System.Collections.ArrayList]@()
    Failed = [System.Collections.ArrayList]@()
}

# ============================================================================
# Script Integrity Verification (SEC-03)
# Verifies scripts against hash manifest before execution to detect tampering
# ============================================================================

$verifyIntegrity = $true  # Set to $false to disable verification

# Initialize verification variables
$manifest = $null
$manifestPath = $null

if ($verifyIntegrity) {
    # Derive paths - go up from Orchestration to Apps to FFUDevelopment
    $ffuDevelopmentPath = Split-Path -Path (Split-Path -Path $scriptPath -Parent) -Parent
    $manifestPath = Join-Path $ffuDevelopmentPath ".security\orchestration-hashes.json"

    # Check if manifest exists
    if (Test-Path $manifestPath) {
        Write-Host "SECURITY: Verifying script integrity..." -ForegroundColor Cyan

        # Load manifest once for all verifications
        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-Host "SECURITY WARNING: Failed to read hash manifest: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        if ($null -ne $manifest) {
            # Self-verify Orchestrator.ps1 first
            $selfPath = $MyInvocation.MyCommand.Definition
            $selfHash = (Get-FileHash -Path $selfPath -Algorithm SHA256).Hash
            $expectedSelfHash = $manifest.scripts.'Orchestrator.ps1'

            if (-not [string]::IsNullOrEmpty($expectedSelfHash) -and $selfHash -ne $expectedSelfHash) {
                Write-Host "SECURITY ERROR: Orchestrator.ps1 integrity check failed!" -ForegroundColor Red
                Write-Host "  Expected: $expectedSelfHash" -ForegroundColor Red
                Write-Host "  Actual:   $selfHash" -ForegroundColor Red
                Write-Host "Script execution halted. This may indicate tampering." -ForegroundColor Red
                exit 1
            }
            Write-Host "SECURITY: Orchestrator.ps1 verified" -ForegroundColor Green
        }
    }
    else {
        Write-Host "SECURITY WARNING: Hash manifest not found at $manifestPath" -ForegroundColor Yellow
        Write-Host "Proceeding without integrity verification" -ForegroundColor Yellow
    }
}

# Define the list of scripts to run, order doesn't matter - if you have a custom script, add it here
$scriptList = @(
    "Update-Defender.ps1",
    "Install-Office.ps1",
    "Update-MSRT.ps1",
    "Update-OneDrive.ps1",
    "Update-Edge.ps1",
    "Install-Win32Apps.ps1",
    "Install-StoreApps.ps1",
    "Install-UserApps.ps1"    
)
# Check if each script exists and has content to process, then run it
foreach ($script in $scriptList) {
    $scriptFile = Join-Path -Path $scriptPath -ChildPath $script
    if (-not (Test-Path -Path $scriptFile)) {
        # REL-WINPE-02: Log warning for missing scripts instead of silent skip
        Write-Host "[SKIP] Script not found: $script" -ForegroundColor Yellow
        Write-Host "       Expected at: $scriptFile" -ForegroundColor Gray
        [void]$script:executionSummary.Skipped.Add(@{
            Script = $script
            Reason = "File not found"
            Path = $scriptFile
        })
        continue
    }

    $shouldRun = $true # Default to run if script exists
    $skipReason = $null
    switch ($script) {
        "Install-Win32Apps.ps1" {
            $wingetAppsJsonFile = Join-Path -Path $scriptPath -ChildPath "WinGetWin32Apps.json"
            $userAppsJsonFile = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "UserAppList.json"
            if (-not (Test-Path -Path $wingetAppsJsonFile) -and -not (Test-Path -Path $userAppsJsonFile)) {
                $shouldRun = $false
                $skipReason = "No WinGetWin32Apps.json or UserAppList.json found"
            }
        }
        "Install-StoreApps.ps1" {
            $msStorePath = "D:\MSStore"
            if (-not (Test-Path -Path $msStorePath) -or -not (Get-ChildItem -Path $msStorePath)) {
                $shouldRun = $false
                $skipReason = "MSStore folder empty or not found at $msStorePath"
            }
        }
    }

    if (-not $shouldRun) {
        # REL-WINPE-02: Log warning for skipped scripts due to missing dependencies
        Write-Host "[SKIP] Script skipped: $script" -ForegroundColor Yellow
        Write-Host "       Reason: $skipReason" -ForegroundColor Gray
        [void]$script:executionSummary.Skipped.Add(@{
            Script = $script
            Reason = $skipReason
            Path = $scriptFile
        })
        continue
    }

    # Verify script integrity before execution (SEC-03)
    if ($verifyIntegrity -and $null -ne $manifest) {
        $scriptHash = (Get-FileHash -Path $scriptFile -Algorithm SHA256).Hash
        $expectedHash = $manifest.scripts.$script

        if (-not [string]::IsNullOrEmpty($expectedHash) -and $scriptHash -ne $expectedHash) {
            Write-Host "SECURITY ERROR: $script integrity check failed!" -ForegroundColor Red
            Write-Host "  Expected: $expectedHash" -ForegroundColor Red
            Write-Host "  Actual:   $scriptHash" -ForegroundColor Red
            Write-Host "Skipping execution of $script" -ForegroundColor Red
            [void]$script:executionSummary.Failed.Add(@{
                Script = $script
                Error = "Integrity check failed"
            })
            continue  # Skip this script but continue with others
        }
        elseif (-not [string]::IsNullOrEmpty($expectedHash)) {
            Write-Host "SECURITY: $script verified" -ForegroundColor Green
        }
    }

    Write-Host "`n" # Add a newline for spacing
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host " Running script: $script                           " -ForegroundColor Yellow
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow

    # REL-WINPE-02: Track execution with error handling
    try {
        & $scriptFile
        [void]$script:executionSummary.Executed.Add($script)
    }
    catch {
        Write-Host "[ERROR] Script failed: $script" -ForegroundColor Red
        Write-Host "        Error: $_" -ForegroundColor Red
        [void]$script:executionSummary.Failed.Add(@{
            Script = $script
            Error = $_.Exception.Message
        })
    }
}

# Invoke-AppsScript.ps1 if it exists and AppsScriptVariables.json is present
$appsScriptFile = Join-Path -Path $scriptPath -ChildPath "Invoke-AppsScript.ps1"
$appsScriptVarsJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "AppsScriptVariables.json"
if ((Test-Path -Path $appsScriptFile) -and (Test-Path -Path $appsScriptVarsJsonPath)) {
    # Verify script integrity before execution (SEC-03)
    $skipAppsScript = $false
    if ($verifyIntegrity -and $null -ne $manifest) {
        $appsScriptHash = (Get-FileHash -Path $appsScriptFile -Algorithm SHA256).Hash
        $expectedAppsScriptHash = $manifest.scripts.'Invoke-AppsScript.ps1'

        if (-not [string]::IsNullOrEmpty($expectedAppsScriptHash) -and $appsScriptHash -ne $expectedAppsScriptHash) {
            Write-Host "SECURITY ERROR: Invoke-AppsScript.ps1 integrity check failed!" -ForegroundColor Red
            Write-Host "  Expected: $expectedAppsScriptHash" -ForegroundColor Red
            Write-Host "  Actual:   $appsScriptHash" -ForegroundColor Red
            Write-Host "Skipping execution of Invoke-AppsScript.ps1" -ForegroundColor Red
            [void]$script:executionSummary.Failed.Add(@{
                Script = "Invoke-AppsScript.ps1"
                Error = "Integrity check failed"
            })
            $skipAppsScript = $true
        }
        elseif (-not [string]::IsNullOrEmpty($expectedAppsScriptHash)) {
            Write-Host "SECURITY: Invoke-AppsScript.ps1 verified" -ForegroundColor Green
        }
    }

    if (-not $skipAppsScript) {
        Write-Host "`n" # Add a newline for spacing
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Running script: Invoke-AppsScript.ps1             " -ForegroundColor Yellow
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow

        Write-Host "Using AppsScriptVariables from JSON file: $appsScriptVarsJsonPath"
        # REL-WINPE-02: Track execution with error handling
        try {
            & $appsScriptFile
            [void]$script:executionSummary.Executed.Add("Invoke-AppsScript.ps1")
        }
        catch {
            Write-Host "[ERROR] Script failed: Invoke-AppsScript.ps1" -ForegroundColor Red
            Write-Host "        Error: $_" -ForegroundColor Red
            [void]$script:executionSummary.Failed.Add(@{
                Script = "Invoke-AppsScript.ps1"
                Error = $_.Exception.Message
            })
        }
    }
}
elseif (-not (Test-Path -Path $appsScriptFile)) {
    # REL-WINPE-02: Log if script doesn't exist (optional script)
    Write-Host "[SKIP] Script not found: Invoke-AppsScript.ps1" -ForegroundColor Yellow
    Write-Host "       Expected at: $appsScriptFile" -ForegroundColor Gray
    [void]$script:executionSummary.Skipped.Add(@{
        Script = "Invoke-AppsScript.ps1"
        Reason = "File not found"
        Path = $appsScriptFile
    })
}
elseif (-not (Test-Path -Path $appsScriptVarsJsonPath)) {
    # REL-WINPE-02: Log if config doesn't exist
    Write-Host "[SKIP] Script skipped: Invoke-AppsScript.ps1" -ForegroundColor Yellow
    Write-Host "       Reason: AppsScriptVariables.json not found at $appsScriptVarsJsonPath" -ForegroundColor Gray
    [void]$script:executionSummary.Skipped.Add(@{
        Script = "Invoke-AppsScript.ps1"
        Reason = "AppsScriptVariables.json not found"
        Path = $appsScriptFile
    })
}

# Run-DiskCleanup.ps1 must run before Run-Sysprep.ps1
$diskCleanupScript = Join-Path -Path $scriptPath -ChildPath "Run-DiskCleanup.ps1"
if (Test-Path -Path $diskCleanupScript) {
    # Verify script integrity before execution (SEC-03)
    $skipDiskCleanup = $false
    if ($verifyIntegrity -and $null -ne $manifest) {
        $diskCleanupHash = (Get-FileHash -Path $diskCleanupScript -Algorithm SHA256).Hash
        $expectedDiskCleanupHash = $manifest.scripts.'Run-DiskCleanup.ps1'

        if (-not [string]::IsNullOrEmpty($expectedDiskCleanupHash) -and $diskCleanupHash -ne $expectedDiskCleanupHash) {
            Write-Host "SECURITY ERROR: Run-DiskCleanup.ps1 integrity check failed!" -ForegroundColor Red
            Write-Host "  Expected: $expectedDiskCleanupHash" -ForegroundColor Red
            Write-Host "  Actual:   $diskCleanupHash" -ForegroundColor Red
            Write-Host "Skipping execution of Run-DiskCleanup.ps1" -ForegroundColor Red
            [void]$script:executionSummary.Failed.Add(@{
                Script = "Run-DiskCleanup.ps1"
                Error = "Integrity check failed"
            })
            $skipDiskCleanup = $true
        }
        elseif (-not [string]::IsNullOrEmpty($expectedDiskCleanupHash)) {
            Write-Host "SECURITY: Run-DiskCleanup.ps1 verified" -ForegroundColor Green
        }
    }

    if (-not $skipDiskCleanup) {
        Write-Host "`n" # Add a newline for spacing
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Running script: Run-DiskCleanup.ps1               " -ForegroundColor Yellow
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        # REL-WINPE-02: Track execution with error handling
        try {
            & $diskCleanupScript
            [void]$script:executionSummary.Executed.Add("Run-DiskCleanup.ps1")
        }
        catch {
            Write-Host "[ERROR] Script failed: Run-DiskCleanup.ps1" -ForegroundColor Red
            Write-Host "        Error: $_" -ForegroundColor Red
            [void]$script:executionSummary.Failed.Add(@{
                Script = "Run-DiskCleanup.ps1"
                Error = $_.Exception.Message
            })
        }
    }
} else {
    # REL-WINPE-02: Log warning for missing disk cleanup script
    Write-Host "[SKIP] Script not found: Run-DiskCleanup.ps1" -ForegroundColor Yellow
    Write-Host "       Expected at: $diskCleanupScript" -ForegroundColor Gray
    [void]$script:executionSummary.Skipped.Add(@{
        Script = "Run-DiskCleanup.ps1"
        Reason = "File not found"
        Path = $diskCleanupScript
    })
}

# Run-Sysprep.ps1 must run last
$sysprepScript = Join-Path -Path $scriptPath -ChildPath "Run-Sysprep.ps1"
if (Test-Path -Path $sysprepScript) {
    # Verify script integrity before execution (SEC-03)
    $skipSysprep = $false
    if ($verifyIntegrity -and $null -ne $manifest) {
        $sysprepHash = (Get-FileHash -Path $sysprepScript -Algorithm SHA256).Hash
        $expectedSysprepHash = $manifest.scripts.'Run-Sysprep.ps1'

        if (-not [string]::IsNullOrEmpty($expectedSysprepHash) -and $sysprepHash -ne $expectedSysprepHash) {
            Write-Host "SECURITY ERROR: Run-Sysprep.ps1 integrity check failed!" -ForegroundColor Red
            Write-Host "  Expected: $expectedSysprepHash" -ForegroundColor Red
            Write-Host "  Actual:   $sysprepHash" -ForegroundColor Red
            Write-Host "Skipping execution of Run-Sysprep.ps1" -ForegroundColor Red
            [void]$script:executionSummary.Failed.Add(@{
                Script = "Run-Sysprep.ps1"
                Error = "Integrity check failed"
            })
            $skipSysprep = $true
        }
        elseif (-not [string]::IsNullOrEmpty($expectedSysprepHash)) {
            Write-Host "SECURITY: Run-Sysprep.ps1 verified" -ForegroundColor Green
        }
    }

    if (-not $skipSysprep) {
        Write-Host "`n" # Add a newline for spacing
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Running script: Run-Sysprep.ps1                   " -ForegroundColor Yellow
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        # REL-WINPE-02: Track execution with error handling
        try {
            & $sysprepScript
            [void]$script:executionSummary.Executed.Add("Run-Sysprep.ps1")
        }
        catch {
            Write-Host "[ERROR] Script failed: Run-Sysprep.ps1" -ForegroundColor Red
            Write-Host "        Error: $_" -ForegroundColor Red
            [void]$script:executionSummary.Failed.Add(@{
                Script = "Run-Sysprep.ps1"
                Error = $_.Exception.Message
            })
        }
    }
} else {
    # REL-WINPE-02: Run-Sysprep.ps1 is CRITICAL - cannot proceed without it
    Write-Host "" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host " CRITICAL ERROR: Run-Sysprep.ps1 not found! " -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run-Sysprep.ps1 is required to finalize the image." -ForegroundColor Yellow
    Write-Host "Without Sysprep, the FFU will not be properly generalized." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Expected location: $sysprepScript" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor White
    Write-Host "  1. Apps ISO was not created correctly" -ForegroundColor Gray
    Write-Host "  2. Orchestration folder is missing files" -ForegroundColor Gray
    Write-Host "  3. File was accidentally deleted" -ForegroundColor Gray
    Write-Host ""
    [void]$script:executionSummary.Failed.Add(@{
        Script = "Run-Sysprep.ps1"
        Error = "Critical script not found"
    })
    throw "CRITICAL: Run-Sysprep.ps1 not found at $sysprepScript - cannot proceed"
}

# ============================================================================
# Execution Summary (REL-WINPE-02)
# ============================================================================
Write-Host ""
Write-Host "---------------------------------------------------" -ForegroundColor Cyan
Write-Host "           Orchestrator Execution Summary           " -ForegroundColor Cyan
Write-Host "---------------------------------------------------" -ForegroundColor Cyan

Write-Host ""
Write-Host "Scripts Executed: $($script:executionSummary.Executed.Count)" -ForegroundColor Green
foreach ($executed in $script:executionSummary.Executed) {
    Write-Host "  [OK] $executed" -ForegroundColor Green
}

if ($script:executionSummary.Skipped.Count -gt 0) {
    Write-Host ""
    Write-Host "Scripts Skipped: $($script:executionSummary.Skipped.Count)" -ForegroundColor Yellow
    foreach ($skipped in $script:executionSummary.Skipped) {
        Write-Host "  [--] $($skipped.Script): $($skipped.Reason)" -ForegroundColor Yellow
    }
}

if ($script:executionSummary.Failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Scripts Failed: $($script:executionSummary.Failed.Count)" -ForegroundColor Red
    foreach ($failed in $script:executionSummary.Failed) {
        Write-Host "  [!!] $($failed.Script): $($failed.Error)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "---------------------------------------------------" -ForegroundColor Cyan
