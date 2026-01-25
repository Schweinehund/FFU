# KB Article: Troubleshooting Windows Package Manager (Winget) Issues

**Article ID:** KB-WINGET-001
**Last Updated:** 2026-01-24
**Applies To:** Windows 10 (1809+), Windows 11, Windows Server 2019+
**Keywords:** winget, Windows Package Manager, App Installer, elevated, admin, registration, search fails

---

## Summary

This article provides troubleshooting guidance for Windows Package Manager (Winget) issues, particularly when Winget commands fail in elevated (Run as Administrator) contexts or for admin accounts different from the primary logged-in user.

---

## Table of Contents

1. [Common Symptoms](#common-symptoms)
2. [Understanding the Problem](#understanding-the-problem)
3. [Quick Diagnostic Commands](#quick-diagnostic-commands)
4. [Resolution Procedures](#resolution-procedures)
5. [Automated Remediation](#automated-remediation)
6. [Verification Steps](#verification-steps)
7. [Prevention](#prevention)
8. [Error Code Reference](#error-code-reference)
9. [Frequently Asked Questions](#frequently-asked-questions)

---

## Common Symptoms

### Symptom 1: Winget Not Recognized
```
'winget' is not recognized as an internal or external command,
operable program or batch file.
```

**Cause:** The Microsoft.DesktopAppInstaller package is not registered for the current user account.

### Symptom 2: Search Returns No Results
```
Failed when searching source; results will not be included: winget
No package found matching input criteria.
```

**Cause:** The Microsoft.Winget.Source package (repository index) is not registered for the current user account.

### Symptom 3: Source Data Missing Error
```
Failed when opening source(s); try the 'source reset' command if the problem persists.
An unexpected error occurred while executing the command:
0x8a15000f : Data required by the source is missing
```

**Cause:** The winget source index database is not available for the current user context.

### Symptom 4: Source Agreement Required
```
The `msstore` source requires that you view the following agreements before using.
Terms of Transaction: https://aka.ms/microsoft-store-terms-of-transaction
Do you agree to all the source agreements terms?
[Y] Yes  [N] No:
```

**Cause:** Source agreements have not been accepted for the current user account.

### Symptom 5: Winget Works in Normal Prompt but Not Elevated
- `winget --version` works in a standard PowerShell/CMD window
- `winget --version` fails in an elevated (Run as Administrator) window

**Cause:** The elevated prompt runs under a different user account (e.g., a separate admin account) that doesn't have Winget registered.

---

## Understanding the Problem

### How Winget Installation Works

Windows Package Manager (Winget) consists of multiple components:

| Package | Purpose | Family Name |
|---------|---------|-------------|
| Microsoft.DesktopAppInstaller | Winget CLI (`winget.exe`) | `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe` |
| Microsoft.Winget.Source | Repository index database | `Microsoft.Winget.Source_8wekyb3d8bbwe` |
| Microsoft.VCLibs | Visual C++ runtime dependency | `Microsoft.VCLibs.140.00.UWPDesktop_8wekyb3d8bbwe` |
| Microsoft.UI.Xaml | UI framework dependency | `Microsoft.UI.Xaml.2.8_8wekyb3d8bbwe` |

### Provisioned vs. Registered

- **Provisioned:** Package is available system-wide for new user accounts
- **Registered:** Package is installed and usable for a specific user account

A package can be provisioned but NOT registered for a particular user. This commonly occurs when:
- An admin uses a separate elevated account (e.g., `admin-username`)
- The normal user account has Winget registered
- The elevated admin account does NOT have Winget registered

### Why This Happens

When you "Run as Administrator" using a different admin account:
1. Windows switches to that admin account's user context
2. AppX packages are user-specific
3. Even if Winget is provisioned, it's not automatically registered for all existing users
4. The admin account sees no Winget installation

---

## Quick Diagnostic Commands

Run these commands in the affected context (e.g., elevated prompt) to diagnose the issue:

### Check 1: Is Winget CLI Available?
```powershell
winget --version
```
- **Success:** Shows version (e.g., `v1.12.460`)
- **Failure:** `'winget' is not recognized...`

### Check 2: Is DesktopAppInstaller Registered?
```powershell
Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' | Select-Object Name, Version, Status
```
- **Success:** Shows package details
- **Failure:** No output (empty)

### Check 3: Is Winget.Source Registered?
```powershell
Get-AppxPackage -Name 'Microsoft.Winget.Source' | Select-Object Name, Version, Status
```
- **Success:** Shows package details
- **Failure:** No output (empty)

### Check 4: Are Packages Provisioned?
```powershell
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like '*Winget*' -or $_.DisplayName -like '*DesktopAppInstaller*' } | Select-Object DisplayName, Version
```
- **Success:** Shows provisioned packages available for registration

### Check 5: Are Sources Configured?
```powershell
winget source list
```
Expected output:
```
Name        Argument                                      Explicit
------------------------------------------------------------------
msstore     https://storeedgefd.dsx.mp.microsoft.com/v9.0 false
winget      https://cdn.winget.microsoft.com/cache        false
```

### Check 6: Does Search Work?
```powershell
winget search "PowerShell" --source winget
```
- **Success:** Returns search results
- **Failure:** Error messages or "No package found"

---

## Resolution Procedures

### Procedure 1: Register Winget CLI from Provisioned Package

**Use when:** `winget --version` fails but packages are provisioned

```powershell
# Run in elevated PowerShell
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
```

**Verify:**
```powershell
winget --version
```

### Procedure 2: Register Winget Source from Provisioned Package

**Use when:** Winget CLI works but search fails with "Data required by the source is missing"

```powershell
# Run in elevated PowerShell
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.Winget.Source_8wekyb3d8bbwe
```

### Procedure 3: Reset and Update Sources

**Use when:** Sources are missing or corrupted

```powershell
# Reset all sources (accepts agreements, reinitializes)
winget source reset --force

# Update source indexes
winget source update

# Verify
winget source list
```

### Procedure 4: Full Manual Installation (When Not Provisioned)

**Use when:** Packages are not provisioned on the system

```powershell
# Download dependencies and Winget
$vcLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
$uiXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
$wingetUrl = "https://aka.ms/getwinget"

$tempDir = $env:TEMP

# Download files
Invoke-WebRequest -Uri $vcLibsUrl -OutFile "$tempDir\VCLibs.appx"
Invoke-WebRequest -Uri $uiXamlUrl -OutFile "$tempDir\UIXaml.appx"
Invoke-WebRequest -Uri $wingetUrl -OutFile "$tempDir\Winget.msixbundle"

# Install packages
Add-AppxPackage -Path "$tempDir\VCLibs.appx"
Add-AppxPackage -Path "$tempDir\UIXaml.appx"
Add-AppxPackage -Path "$tempDir\Winget.msixbundle"

# Cleanup
Remove-Item "$tempDir\VCLibs.appx", "$tempDir\UIXaml.appx", "$tempDir\Winget.msixbundle" -Force

# Initialize sources
winget source reset --force
winget source update
```

### Procedure 5: Complete Reset (Nuclear Option)

**Use when:** All other procedures fail

```powershell
# Remove existing Winget packages
Get-AppxPackage *DesktopAppInstaller* | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage *Winget.Source* | Remove-AppxPackage -ErrorAction SilentlyContinue

# Re-register from provisioned packages
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.Winget.Source_8wekyb3d8bbwe

# Reset sources
winget source reset --force
winget source update

# Verify
winget --version
winget search "PowerShell"
```

---

## Automated Remediation

### Option 1: Intune Proactive Remediation

Deploy the detection and remediation scripts via Microsoft Intune:

1. Navigate to **Intune** > **Devices** > **Remediations**
2. Create a new script package
3. Upload:
   - Detection: `Detect-WingetRegistration.ps1`
   - Remediation: `Remediate-WingetRegistration.ps1`
4. Configure to run as **logged-on user** (not SYSTEM)
5. Schedule to run daily

### Option 2: PowerShell One-Liner Fix

For quick manual remediation:

```powershell
# One-liner: Register both packages and reset sources
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue; Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.Winget.Source_8wekyb3d8bbwe -ErrorAction SilentlyContinue; winget source reset --force; winget source update
```

### Option 3: Login Script / Group Policy

Add to user login script:

```powershell
# Check if Winget needs registration
$wingetInstalled = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue
if (-not $wingetInstalled) {
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.Winget.Source_8wekyb3d8bbwe -ErrorAction SilentlyContinue
}
```

---

## Verification Steps

After remediation, verify the fix:

### Step 1: Check Winget Version
```powershell
winget --version
```
Expected: `v1.x.xxx` (version number)

### Step 2: Check Package Registration
```powershell
Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' | Select-Object Name, Version
Get-AppxPackage -Name 'Microsoft.Winget.Source' | Select-Object Name, Version
```
Expected: Both packages listed with versions

### Step 3: Check Source Configuration
```powershell
winget source list
```
Expected: Both `winget` and `msstore` sources listed

### Step 4: Test Search Functionality
```powershell
winget search "7zip"
```
Expected: Search results for 7-Zip applications

### Step 5: Test Installation (Optional)
```powershell
winget install --id 7zip.7zip --accept-package-agreements --accept-source-agreements
```
Expected: Successful installation

---

## Prevention

### For IT Administrators

1. **Provision Winget in OS Image**
   - Include Microsoft.DesktopAppInstaller in your Windows deployment image
   - Use DISM to add AppX packages to offline images

2. **Deploy via Intune**
   - Deploy Winget as a required app
   - Use proactive remediation to ensure registration

3. **Login Script**
   - Add registration check to login scripts for admin accounts

4. **Document Admin Account Setup**
   - Include Winget registration in new admin account setup procedures

### For End Users

1. **Use Microsoft Store**
   - Open Microsoft Store and update "App Installer"

2. **Run Winget Once as Each Account**
   - After setting up a new admin account, run `winget list` once to initialize

---

## Error Code Reference

| Error Code | Description | Resolution |
|------------|-------------|------------|
| `0x8a15000f` | Data required by the source is missing | Register Winget.Source package, reset sources |
| `0x80511001` | Unknown error during source add | Reset sources with `--force` |
| `0x80070005` | Access denied | Run as administrator, ensure not running as SYSTEM |
| `0x80073D05` | Package not found | Package not provisioned, use manual installation |
| `0x80070002` | File not found | Winget.exe not in PATH, register DesktopAppInstaller |

---

## Frequently Asked Questions

### Q: Why does Winget work for my normal account but not when I Run as Administrator?

**A:** When you "Run as Administrator" with a different admin account, you're switching to that account's user context. AppX packages like Winget are registered per-user. If your admin account never had Winget registered, it won't be available.

### Q: Why did my admin account lose Winget after a Windows Update?

**A:** Windows Updates can reset or re-provision AppX packages. While the package remains provisioned, individual user registrations may be affected. Re-register using the procedures above.

### Q: Can I install Winget system-wide for all users?

**A:** Winget can be **provisioned** system-wide (available for new users) but each existing user must have it **registered** to their profile. Use `Add-AppxProvisionedPackage` to provision for new users:

```powershell
Add-AppxProvisionedPackage -Online -PackagePath "path\to\Microsoft.DesktopAppInstaller.msixbundle" -SkipLicense
```

### Q: Does this affect SYSTEM account / Intune scripts?

**A:** Scripts running as SYSTEM cannot use Winget because AppX packages are user-specific. For Intune scripts that need Winget, configure them to run as the logged-on user.

### Q: How do I check which user context I'm running in?

```powershell
whoami
$env:USERNAME
```

### Q: The winget source keeps disappearing after reset. Why?

**A:** The Microsoft.Winget.Source package may not be registered. Register it first, then reset sources:

```powershell
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.Winget.Source_8wekyb3d8bbwe
winget source reset --force
```

---

## Related Articles

- [Microsoft Docs: Windows Package Manager](https://docs.microsoft.com/windows/package-manager/)
- [Winget GitHub Repository](https://github.com/microsoft/winget-cli)
- [App Installer Troubleshooting](https://docs.microsoft.com/windows/package-manager/winget/troubleshooting)

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-24 | FFU Builder Team | Initial release |

---

*For additional support, contact your IT Help Desk or submit a ticket.*
