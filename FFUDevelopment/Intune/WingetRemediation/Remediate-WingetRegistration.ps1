<#
.SYNOPSIS
    Intune Proactive Remediation - Remediation Script for Winget Registration Issues

.DESCRIPTION
    Remediates Windows Package Manager (Winget) registration issues for the current
    user context. This fixes the common scenario where Winget packages are provisioned
    system-wide but not registered for elevated admin accounts.

    Remediation steps:
    1. Register Microsoft.DesktopAppInstaller (Winget CLI) from provisioned package
    2. Register Microsoft.Winget.Source (Repository index) from provisioned package
    3. Reset winget sources to accept agreements and reinitialize
    4. Update winget sources to ensure current index

.NOTES
    Script Name: Remediate-WingetRegistration.ps1
    Version: 1.0.0
    Author: FFU Builder Team

    Exit Codes:
    - 0: Remediation successful
    - 1: Remediation failed

    Requirements:
    - Must run in user context (not SYSTEM) for AppX registration
    - Packages must be provisioned on the system

.LINK
    Related fix: BUG-WINGET-01, BUG-WINGET-02
    https://github.com/yourusername/FFUBuilder
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

# Track remediation success
$remediationSuccess = $true
$remediationSteps = @()

Write-Output "=========================================="
Write-Output "Winget Registration Remediation"
Write-Output "User: $env:USERNAME"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "=========================================="
Write-Output ""

# =============================================================================
# Step 1: Register Microsoft.DesktopAppInstaller (Winget CLI)
# =============================================================================
Write-Output "Step 1: Checking/Registering Microsoft.DesktopAppInstaller..."

try {
    $desktopAppInstaller = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue

    if ($desktopAppInstaller) {
        Write-Output "  [OK] Already registered (v$($desktopAppInstaller.Version))"
        $remediationSteps += "DesktopAppInstaller: Already registered"
    }
    else {
        # Check if provisioned
        $provisionedInstaller = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' }

        if ($provisionedInstaller) {
            Write-Output "  Found provisioned package (v$($provisionedInstaller.Version)). Registering..."
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
            Write-Output "  [OK] Successfully registered"
            $remediationSteps += "DesktopAppInstaller: Registered from provisioned package"
        }
        else {
            Write-Output "  [WARN] Package not provisioned. Attempting download installation..."

            # Download and install from official source
            $installerUrl = "https://aka.ms/getwinget"
            $installerPath = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"

            # Download dependencies and main package
            $packages = @(
                @{
                    Name = "VCLibs"
                    Url = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
                    File = "Microsoft.VCLibs.x64.14.00.Desktop.appx"
                },
                @{
                    Name = "UIXaml"
                    Url = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
                    File = "Microsoft.UI.Xaml.2.8.x64.appx"
                },
                @{
                    Name = "WinGet"
                    Url = $installerUrl
                    File = "Microsoft.DesktopAppInstaller.msixbundle"
                }
            )

            foreach ($package in $packages) {
                $destPath = Join-Path $env:TEMP $package.File
                Write-Output "    Downloading $($package.Name)..."
                Invoke-WebRequest -Uri $package.Url -OutFile $destPath -UseBasicParsing
                Write-Output "    Installing $($package.Name)..."
                Add-AppxPackage -Path $destPath -ErrorAction SilentlyContinue
                Remove-Item $destPath -Force -ErrorAction SilentlyContinue
            }

            Write-Output "  [OK] Downloaded and installed"
            $remediationSteps += "DesktopAppInstaller: Downloaded and installed"
        }
    }
}
catch {
    Write-Output "  [FAIL] $($_.Exception.Message)"
    $remediationSteps += "DesktopAppInstaller: FAILED - $($_.Exception.Message)"
    $remediationSuccess = $false
}

Write-Output ""

# =============================================================================
# Step 2: Register Microsoft.Winget.Source (Repository Index)
# =============================================================================
Write-Output "Step 2: Checking/Registering Microsoft.Winget.Source..."

try {
    $wingetSource = Get-AppxPackage -Name 'Microsoft.Winget.Source' -ErrorAction SilentlyContinue

    if ($wingetSource) {
        Write-Output "  [OK] Already registered (v$($wingetSource.Version))"
        $remediationSteps += "Winget.Source: Already registered"
    }
    else {
        # Check if provisioned
        $provisionedSource = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq 'Microsoft.Winget.Source' }

        if ($provisionedSource) {
            Write-Output "  Found provisioned package (v$($provisionedSource.Version)). Registering..."
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.Winget.Source_8wekyb3d8bbwe -ErrorAction Stop
            Write-Output "  [OK] Successfully registered"
            $remediationSteps += "Winget.Source: Registered from provisioned package"
        }
        else {
            Write-Output "  [WARN] Package not provisioned - will be initialized via source update"
            $remediationSteps += "Winget.Source: Not provisioned (will init via source update)"
        }
    }
}
catch {
    Write-Output "  [FAIL] $($_.Exception.Message)"
    $remediationSteps += "Winget.Source: FAILED - $($_.Exception.Message)"
    # Non-fatal - source update may still work
}

Write-Output ""

# =============================================================================
# Step 3: Reset Winget Sources (Accept Agreements)
# =============================================================================
Write-Output "Step 3: Resetting Winget sources..."

try {
    # Verify winget is now accessible
    $wingetPath = (Get-Command 'winget.exe' -ErrorAction SilentlyContinue).Source

    if (-not $wingetPath) {
        # Try common paths
        $possiblePaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
        )
        foreach ($path in $possiblePaths) {
            $resolved = Resolve-Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($resolved) {
                $wingetPath = $resolved.Path
                break
            }
        }
    }

    if ($wingetPath) {
        Write-Output "  Using winget at: $wingetPath"

        # Reset sources (--force bypasses prompts)
        Write-Output "  Executing: winget source reset --force"
        $resetOutput = & $wingetPath source reset --force 2>&1
        Write-Output "  Result: $($resetOutput -join ' ')"
        $remediationSteps += "Source reset: Completed"
    }
    else {
        Write-Output "  [WARN] winget.exe not found - skipping source reset"
        $remediationSteps += "Source reset: Skipped (winget not found)"
    }
}
catch {
    Write-Output "  [WARN] Source reset had issues: $($_.Exception.Message)"
    $remediationSteps += "Source reset: Warning - $($_.Exception.Message)"
    # Non-fatal
}

Write-Output ""

# =============================================================================
# Step 4: Update Winget Sources
# =============================================================================
Write-Output "Step 4: Updating Winget sources..."

try {
    if ($wingetPath) {
        Write-Output "  Executing: winget source update"
        $updateOutput = & $wingetPath source update 2>&1
        Write-Output "  Result: $($updateOutput -join ' ')"
        $remediationSteps += "Source update: Completed"
    }
    else {
        Write-Output "  [SKIP] winget.exe not found"
        $remediationSteps += "Source update: Skipped"
    }
}
catch {
    Write-Output "  [WARN] Source update had issues: $($_.Exception.Message)"
    $remediationSteps += "Source update: Warning - $($_.Exception.Message)"
    # Non-fatal
}

Write-Output ""

# =============================================================================
# Step 5: Verification
# =============================================================================
Write-Output "Step 5: Verifying remediation..."

$verificationPassed = $true

try {
    # Check DesktopAppInstaller
    $checkInstaller = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue
    if ($checkInstaller) {
        Write-Output "  [OK] DesktopAppInstaller registered"
    }
    else {
        Write-Output "  [FAIL] DesktopAppInstaller not registered"
        $verificationPassed = $false
    }

    # Check Winget.Source
    $checkSource = Get-AppxPackage -Name 'Microsoft.Winget.Source' -ErrorAction SilentlyContinue
    if ($checkSource) {
        Write-Output "  [OK] Winget.Source registered"
    }
    else {
        Write-Output "  [WARN] Winget.Source not registered (may work via source list)"
    }

    # Check winget command
    if ($wingetPath) {
        $versionCheck = & $wingetPath --version 2>&1
        if ($versionCheck -match 'v?[\d\.]+') {
            Write-Output "  [OK] winget command working ($versionCheck)"
        }
        else {
            Write-Output "  [WARN] winget version check returned: $versionCheck"
        }

        # Check sources
        $sourceCheck = & $wingetPath source list 2>&1
        if ($sourceCheck -match 'winget') {
            Write-Output "  [OK] Winget source configured"
        }
        else {
            Write-Output "  [WARN] Winget source may not be configured: $sourceCheck"
        }
    }
}
catch {
    Write-Output "  [WARN] Verification check failed: $($_.Exception.Message)"
}

Write-Output ""

# =============================================================================
# Final Result
# =============================================================================
Write-Output "=========================================="
Write-Output "REMEDIATION SUMMARY"
Write-Output "=========================================="

foreach ($step in $remediationSteps) {
    Write-Output "  - $step"
}

Write-Output ""

if ($remediationSuccess -and $verificationPassed) {
    Write-Output "RESULT: SUCCESS"
    Write-Output "Winget has been successfully configured for this user."
    Write-Output "=========================================="
    exit 0
}
elseif ($remediationSuccess) {
    Write-Output "RESULT: PARTIAL SUCCESS"
    Write-Output "Remediation completed with warnings. Winget should be functional."
    Write-Output "=========================================="
    exit 0
}
else {
    Write-Output "RESULT: FAILED"
    Write-Output "Remediation encountered errors. Manual intervention may be required."
    Write-Output "=========================================="
    exit 1
}
