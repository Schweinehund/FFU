# Winget Registration Remediation for Intune

## Overview

These scripts are designed to be deployed as an **Intune Proactive Remediation** (formerly known as "Scripts and Remediations") to detect and fix Windows Package Manager (Winget) registration issues on managed devices.

## The Problem

When administrators use elevated accounts (e.g., `admin-username`) that are different from their normal login accounts, Winget may be:
- **Provisioned** system-wide (available for new users)
- **Registered** for the normal user account
- **NOT registered** for the elevated admin account

This causes `winget` commands to fail with errors like:
- `'winget' is not recognized as an internal or external command`
- `Failed when searching source; results will not be included: winget`
- `0x8a15000f : Data required by the source is missing`

## Scripts Included

| Script | Purpose |
|--------|---------|
| `Detect-WingetRegistration.ps1` | Checks if Winget is properly configured |
| `Remediate-WingetRegistration.ps1` | Fixes Winget registration issues |

## What Gets Checked/Fixed

1. **Microsoft.DesktopAppInstaller** - The Winget CLI package
2. **Microsoft.Winget.Source** - The repository index package
3. **Winget source configuration** - Community repository and MS Store sources
4. **Source agreements** - Automatically accepted during remediation

## Intune Deployment Instructions

### Step 1: Create Proactive Remediation

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com)
2. Navigate to **Devices** > **Remediations** (under "Manage devices")
3. Click **+ Create script package**

### Step 2: Configure Basics

| Setting | Value |
|---------|-------|
| Name | `Winget Registration Remediation` |
| Description | `Detects and fixes Winget package registration issues for elevated admin accounts. Ensures Microsoft.DesktopAppInstaller and Microsoft.Winget.Source packages are registered for the current user.` |
| Publisher | `IT Department` |

### Step 3: Upload Scripts

**Detection Script:**
- Upload: `Detect-WingetRegistration.ps1`
- Run this script using the logged-on credentials: **Yes**
- Enforce script signature check: **No** (or Yes if you sign scripts)
- Run script in 64-bit PowerShell: **Yes**

**Remediation Script:**
- Upload: `Remediate-WingetRegistration.ps1`
- Run this script using the logged-on credentials: **Yes**
- Enforce script signature check: **No** (or Yes if you sign scripts)
- Run script in 64-bit PowerShell: **Yes**

> **Important:** These scripts MUST run as the logged-on user (not SYSTEM) because AppX package registration is user-specific.

### Step 4: Scope Tags

Add appropriate scope tags for your organization.

### Step 5: Assignments

| Setting | Recommendation |
|---------|----------------|
| Included groups | Target groups containing admin workstations or devices where elevated accounts are used |
| Excluded groups | (Optional) Exclude kiosks or shared devices |
| Schedule | Daily or every 8 hours for proactive fix |

### Step 6: Review + Create

Review settings and click **Create**.

## Manual Testing

Before deploying via Intune, test the scripts manually:

```powershell
# Run detection (as the target user)
.\Detect-WingetRegistration.ps1

# If non-compliant (exit code 1), run remediation
.\Remediate-WingetRegistration.ps1

# Verify fix
winget --version
winget search "PowerShell"
```

## Expected Output

### Detection Script (Compliant)
```
Checking Microsoft.DesktopAppInstaller registration...
  [OK] Registered (v1.27.460.0)
Checking Microsoft.Winget.Source registration...
  [OK] Registered (v2026.125.158.48)
Checking winget.exe accessibility...
  [OK] Found (v1.12.460)
...
RESULT: COMPLIANT
```

### Remediation Script (Success)
```
Step 1: Checking/Registering Microsoft.DesktopAppInstaller...
  Found provisioned package. Registering...
  [OK] Successfully registered
Step 2: Checking/Registering Microsoft.Winget.Source...
  Found provisioned package. Registering...
  [OK] Successfully registered
Step 3: Resetting Winget sources...
  [OK] Completed
Step 4: Updating Winget sources...
  [OK] Completed
...
RESULT: SUCCESS
```

## Troubleshooting

### Script fails with "Access Denied"
- Ensure the script runs as the logged-on user, not SYSTEM
- Check that the user has permissions to install AppX packages

### Packages not provisioned
- The remediation script will attempt to download packages from Microsoft
- Ensure devices have internet access to:
  - `https://aka.ms/getwinget`
  - `https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx`
  - `https://github.com/microsoft/microsoft-ui-xaml/releases/`
  - `https://cdn.winget.microsoft.com/`

### Source update fails
- May require accepting source agreements manually first time
- Network/proxy issues may block access to winget CDN

## Related Issues

- **BUG-WINGET-01**: Winget CLI not available in elevated context
- **BUG-WINGET-02**: Winget Source package not registered for admin

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-24 | Initial release |
