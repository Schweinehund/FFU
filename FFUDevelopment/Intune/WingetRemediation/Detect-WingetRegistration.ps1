<#
.SYNOPSIS
    Intune Proactive Remediation - Detection Script for Winget Registration Issues

.DESCRIPTION
    Detects whether the Windows Package Manager (Winget) components are properly
    registered for the current user context. This is particularly important for
    elevated admin accounts that may have Winget provisioned but not registered.

    Checks performed:
    1. Microsoft.DesktopAppInstaller package registration (Winget CLI)
    2. Microsoft.Winget.Source package registration (Repository index)
    3. Winget CLI accessibility (winget.exe in PATH)
    4. Winget source configuration (winget source list)

.NOTES
    Script Name: Detect-WingetRegistration.ps1
    Version: 1.0.0
    Author: FFU Builder Team

    Exit Codes:
    - 0: Compliant - Winget is properly configured
    - 1: Non-Compliant - Winget needs remediation

.LINK
    Related fix: BUG-WINGET-01, BUG-WINGET-02
    https://github.com/yourusername/FFUBuilder
#>

#Requires -Version 5.1

$ErrorActionPreference = 'SilentlyContinue'

# Initialize compliance tracking
$issues = @()

# =============================================================================
# Check 1: Microsoft.DesktopAppInstaller (Winget CLI)
# =============================================================================
Write-Output "Checking Microsoft.DesktopAppInstaller registration..."

$desktopAppInstaller = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller'
if (-not $desktopAppInstaller) {
    $issues += "Microsoft.DesktopAppInstaller not registered for current user"
    Write-Output "  [FAIL] Not registered"
}
else {
    Write-Output "  [OK] Registered (v$($desktopAppInstaller.Version))"
}

# =============================================================================
# Check 2: Microsoft.Winget.Source (Repository Index)
# =============================================================================
Write-Output "Checking Microsoft.Winget.Source registration..."

$wingetSource = Get-AppxPackage -Name 'Microsoft.Winget.Source'
if (-not $wingetSource) {
    $issues += "Microsoft.Winget.Source not registered for current user"
    Write-Output "  [FAIL] Not registered"
}
else {
    Write-Output "  [OK] Registered (v$($wingetSource.Version))"
}

# =============================================================================
# Check 3: Winget CLI Accessibility
# =============================================================================
Write-Output "Checking winget.exe accessibility..."

$wingetCmd = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
if (-not $wingetCmd) {
    $issues += "winget.exe not found in PATH"
    Write-Output "  [FAIL] Not found in PATH"
}
else {
    # Try to get version
    try {
        $wingetVersion = & winget.exe --version 2>&1
        if ($wingetVersion -match 'v?[\d\.]+') {
            Write-Output "  [OK] Found ($wingetVersion)"
        }
        else {
            $issues += "winget.exe found but version check failed"
            Write-Output "  [WARN] Found but version check failed: $wingetVersion"
        }
    }
    catch {
        $issues += "winget.exe found but execution failed"
        Write-Output "  [FAIL] Execution failed: $($_.Exception.Message)"
    }
}

# =============================================================================
# Check 4: Winget Source Configuration
# =============================================================================
Write-Output "Checking winget source configuration..."

if ($wingetCmd) {
    try {
        $sourceList = & winget.exe source list 2>&1
        $sourceListString = $sourceList -join "`n"

        # Check for the main 'winget' source
        if ($sourceListString -match 'winget\s+https://cdn\.winget\.microsoft\.com') {
            Write-Output "  [OK] Winget community source configured"
        }
        else {
            $issues += "Winget community source not configured"
            Write-Output "  [FAIL] Winget community source not found"
        }

        # Check for msstore source
        if ($sourceListString -match 'msstore\s+https://storeedgefd\.dsx\.mp\.microsoft\.com') {
            Write-Output "  [OK] Microsoft Store source configured"
        }
        else {
            Write-Output "  [WARN] Microsoft Store source not found (optional)"
        }
    }
    catch {
        $issues += "Failed to query winget sources"
        Write-Output "  [FAIL] Source query failed: $($_.Exception.Message)"
    }
}
else {
    Write-Output "  [SKIP] Cannot check sources - winget.exe not available"
}

# =============================================================================
# Check 5: Test Search Functionality (Optional but thorough)
# =============================================================================
Write-Output "Testing winget search functionality..."

if ($wingetCmd -and $desktopAppInstaller -and $wingetSource) {
    try {
        # Quick search test with timeout
        $searchJob = Start-Job -ScriptBlock {
            & winget.exe search "Microsoft.PowerShell" --source winget 2>&1
        }
        $searchResult = Wait-Job $searchJob -Timeout 30 | Receive-Job
        Remove-Job $searchJob -Force -ErrorAction SilentlyContinue

        $searchResultString = $searchResult -join "`n"

        if ($searchResultString -match 'Microsoft\.PowerShell' -or $searchResultString -match 'PowerShell') {
            Write-Output "  [OK] Search functionality working"
        }
        elseif ($searchResultString -match 'Failed when searching source|error|missing') {
            $issues += "Winget search failing - source index may be corrupted"
            Write-Output "  [FAIL] Search returned error: $searchResultString"
        }
        else {
            Write-Output "  [WARN] Search completed but no expected results (may be OK)"
        }
    }
    catch {
        Write-Output "  [WARN] Search test inconclusive: $($_.Exception.Message)"
    }
}
else {
    Write-Output "  [SKIP] Cannot test search - prerequisites not met"
}

# =============================================================================
# Final Result
# =============================================================================
Write-Output ""
Write-Output "=========================================="

if ($issues.Count -eq 0) {
    Write-Output "RESULT: COMPLIANT"
    Write-Output "Winget is properly configured for this user."
    Write-Output "=========================================="
    exit 0
}
else {
    Write-Output "RESULT: NON-COMPLIANT"
    Write-Output "Issues detected ($($issues.Count)):"
    foreach ($issue in $issues) {
        Write-Output "  - $issue"
    }
    Write-Output "=========================================="
    Write-Output "Remediation required."
    exit 1
}
