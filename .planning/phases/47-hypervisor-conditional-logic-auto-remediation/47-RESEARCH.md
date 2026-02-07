# Phase 47: Hypervisor Conditional Logic & Auto-Remediation - Research

**Research Date:** 2026-02-06
**Phase:** 47 of 48 (v1.11.0 milestone)
**Dependencies:** Phase 46 (Dashboard Foundation)

## Executive Summary

This phase adds two major capabilities to the dashboard: (1) conditional hypervisor check execution based on VM Settings selection, and (2) one-click auto-remediation for safe pre-flight failures. Research reveals existing infrastructure provides strong foundations for both features.

### Key Findings

1. **Hypervisor selection already captured**: UI reads `cmbHypervisorType.SelectedIndex` and passes to `Invoke-FFUPreflight` as `HypervisorType` parameter
2. **Conditional check logic exists**: `Invoke-FFUPreflight` already skips Hyper-V when `HypervisorType='VMware'` (line 3629-3633)
3. **Category map covers all hypervisor checks**: 5 checks mapped in FFUUI.Core.Dashboard.psm1 (HyperV, VmxToolkit, VMwareDrivers, VMwareBridgeConfig, HyperVSwitchConflict)
4. **WIMMount has auto-repair logic**: `Test-FFUWimMount` contains 6-step registry/service remediation (lines 1954-1959)
5. **Safe vs unsafe distinction clear**: Hyper-V enablement requires `Enable-WindowsOptionalFeature` + reboot (unsafe), WIMMount repair uses service/registry operations (safe)

### Planning Confidence: HIGH

- ✅ Existing code patterns for conditional execution
- ✅ All check remediations documented in `New-FFURemediationBlock` calls
- ✅ WPF dashboard infrastructure from Phase 46
- ✅ Clear separation between check execution (FFU.Preflight) and display (FFUUI.Core.Dashboard)

---

## 1. Current State Analysis

### 1.1 Hypervisor Selection Flow

**UI Component:**
```powershell
# BuildFFUVM_UI.ps1 line 1036
$hypervisorType = switch ($script:uiState.Controls.cmbHypervisorType.SelectedIndex) {
    0 { 'HyperV' }
    1 { 'VMware' }
    2 { 'Auto' }
}
```

**Dashboard Execution:**
```powershell
# BuildFFUVM_UI.ps1 line 1061
$preflightResult = Invoke-FFUPreflight `
    -Features $features `
    -FFUDevelopmentPath $ffuPath `
    -HypervisorType $hypervisorType `
    # ...
```

**Conditional Logic (Invoke-FFUPreflight):**
```powershell
# FFU.Preflight.psm1 lines 3615-3638
if ($requirements.NeedsHyperV) {
    $hvResult = Test-FFUHyperV
    # ... execute Hyper-V check
}
elseif ($HypervisorType -eq 'VMware') {
    Write-Information "  Checking Hyper-V feature... SKIPPED (using VMware)"
    $result.Tier1Results['HyperV'] = New-FFUCheckResult -CheckName 'HyperV' -Status 'Skipped' `
        -Message 'Hyper-V check skipped (VMware hypervisor selected)'
}
```

**Key Insight:** The backend already skips Hyper-V when VMware is selected. The dashboard just needs to **hide the Hypervisor category Expander** when no hypervisor checks are relevant.

### 1.2 Hypervisor Check Inventory

**From FFUUI.Core.Dashboard.psm1 (lines 32-38):**

| Check Name | Category | Purpose |
|------------|----------|---------|
| `HyperV` | Hypervisor | Hyper-V feature installed and enabled |
| `VmxToolkit` | Hypervisor | vmxtoolkit PowerShell module (VMware, optional warning) |
| `VMwareDrivers` | Hypervisor | Intel e1000e drivers for WinPE capture (VMware) |
| `VMwareBridgeConfig` | Hypervisor | Network adapter configuration guidance (VMware, warning) |
| `HyperVSwitchConflict` | Hypervisor | Detects External Hyper-V switches (VMware, blocking) |

**Conditional Execution Status:**
- ✅ `HyperV`: Already skips when `HypervisorType='VMware'` (line 3629)
- ✅ `VmxToolkit`: Only runs when `HypervisorType='VMware'` (FFU.Preflight.psm1 line 2463)
- ✅ `VMwareDrivers`: Only runs when `HypervisorType='VMware'` (line 4131)
- ✅ `VMwareBridgeConfig`: Only runs when `HypervisorType='VMware'` (line 2679)
- ✅ `HyperVSwitchConflict`: Only runs when `HypervisorType='VMware'` (line 2572)

**Result:** All hypervisor checks already have conditional execution logic in `Invoke-FFUPreflight`. Dashboard visibility is the missing piece.

### 1.3 Dashboard Category Structure

**Home Tab XAML (BuildFFUVM_UI.xaml lines 107-117):**
```xml
<!-- Category: Hypervisor -->
<Expander x:Name="expHypervisor" Style="{StaticResource MinimalExpanderNoHighlightStyle}" IsExpanded="False" Margin="0,2">
    <Expander.Header>
        <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="txtHypervisorIcon" Text="&#9675;" FontSize="14" Foreground="Gray" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <TextBlock Text="Hypervisor" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBlock x:Name="txtHypervisorSummary" Text="(checking...)" Foreground="Gray" FontStyle="Italic" VerticalAlignment="Center"/>
        </StackPanel>
    </Expander.Header>
    <StackPanel x:Name="pnlHypervisorChecks" Margin="20,5,0,5"/>
</Expander>
```

**State Management:** All dashboard controls registered in `$script:uiState.Controls` hashtable during UI initialization.

---

## 2. Auto-Remediation Analysis

### 2.1 Safe vs Unsafe Remediation Classification

**Safe Remediations (one-click, no reboot):**

| Check | Issue | PowerShell Fix | Implementation Reference |
|-------|-------|----------------|--------------------------|
| **WimMount** | Filter not loaded | `fltmc load WimMount` + registry repair | FFU.Preflight.psm1 lines 1944-2407 |
| **DISMState** | Service degraded | `DISM /Online /Cleanup-Image /RestoreHealth` | FFU.Preflight.psm1 lines 4467-4606 |
| **DISMCleanup** | Component store bloat | `Invoke-FFUDISMCleanup` (pre-remediation tier) | FFU.Preflight.psm1 lines 4649-4876 |
| **Network** | DNS resolution | `Clear-DnsClientCache; Test-NetConnection` | FFU.Preflight.psm1 lines 1317-1475 |

**Unsafe Remediations (reboot required, confirmation dialog):**

| Check | Issue | PowerShell Fix | Reboot Required |
|-------|-------|----------------|-----------------|
| **HyperV** | Feature not enabled | `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart` | YES |
| **PowerShellVersion** | PS 5.1 installed | Manual install from https://aka.ms/powershell | YES |
| **Administrator** | Not running elevated | `Start-Process powershell -Verb RunAs` (app restart) | NO, but restarts app |

**ADK Remediation Decision:**

The ADK check (`Test-FFUADK`, lines 988-1191) fails when:
1. **Registry key missing** → ADK not installed → Manual install required (NOT auto-fixable)
2. **Deployment Tools missing** → Component not selected during install → Manual reinstall required (NOT auto-fixable)
3. **WinPE add-on missing** → Separate installer required → Manual install required (NOT auto-fixable)
4. **Architecture files missing** → Corrupted install → Manual reinstall required (NOT auto-fixable)

**Recommendation:** ADK check should **NOT** have an auto-fix button. All ADK failures require manual installer execution (can't be scripted reliably).

### 2.2 WIMMount Auto-Repair Deep Dive

**Existing Auto-Repair Logic (Test-FFUWimMount, lines 1954-2132):**

```powershell
# PRIMARY CHECK: Runs 'fltmc filters' and looks for "WimMount" in output
$fltmcOutput = & fltmc.exe filters 2>&1
$wimMountFound = $fltmcOutput -match 'WimMount'

if (-not $wimMountFound) {
    # AUTO-REPAIR SEQUENCE:
    # 1. Verify wimmount.sys driver file exists
    # 2. Create/recreate WimMount service registry entries
    # 3. Create filter instance configuration
    # 4. Start the service via 'sc start wimmount'
    # 5. Load filter via 'fltmc load WimMount'
    # 6. Re-verify filter is now loaded
}
```

**Key Detail:** This repair logic is **already implemented** in `Test-FFUWimMount`. The check function itself performs remediation and returns success if repair works. The dashboard just needs to **extract the remediation logic into a separate callable function**.

**Recommendation:** Create `Repair-FFUWimMount` function that:
1. Extracts lines 2064-2132 from `Test-FFUWimMount`
2. Returns PSCustomObject with `{ Succeeded = $bool; Message = $string; DurationMs = $int }`
3. Gets called by dashboard "Fix" button click handler

### 2.3 Check Duration Measurement

**All checks already track duration:**

```powershell
# Pattern used in every Test-FFU* function
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
# ... check logic ...
$stopwatch.Stop()

return New-FFUCheckResult -CheckName 'CheckName' `
    -Status 'Passed' `
    -Message 'Check passed' `
    -DurationMs $stopwatch.ElapsedMilliseconds
```

**Check result objects already contain `DurationMs` property.** Dashboard just needs to display it in the UI.

### 2.4 PowerShell Commands for Manual Remediation

**All checks already provide structured remediation:**

```powershell
# Example from Test-FFUHyperV (line 939)
New-FFURemediationBlock -Issue "Hyper-V feature is not installed (State: $featureState)" `
    -Impact "Build cannot proceed without virtualization" `
    -PowerShellCommands @(
        '# Enable Hyper-V (requires restart)',
        'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart',
        '',
        '# Or use DISM',
        'dism /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V-All /All'
    ) `
    -ManualSteps @(
        "Press Win+R, type 'optionalfeatures', press Enter",
        "Check 'Hyper-V' (all sub-features)",
        "Click OK and restart computer"
    ) `
    -VerifyCommand 'Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All | Select-Object State'
```

**The `Remediation` string in check results contains formatted multi-line text with PowerShell commands.** Dashboard needs to:
1. Parse the remediation text for the `PowerShellCommands` section
2. Extract command lines (skip comments and blank lines)
3. Display in a selectable TextBox with monospace font
4. Provide a "Copy" button that copies to clipboard

---

## 3. Implementation Requirements

### 3.1 Hypervisor Conditional Logic (HYP-01 through HYP-05)

**HYP-01, HYP-02:** Pre-flight check execution conditional on hypervisor
**Status:** ✅ Already implemented in `Invoke-FFUPreflight` (lines 3615-3638, 2463, 2572, 2679, 4131)
**No code changes needed** — checks already skip when hypervisor doesn't match.

**HYP-03:** Build not blocked by missing Hyper-V when VMware selected
**Status:** ✅ Already implemented — `Get-FFURequirements` (line 264) sets `NeedsHyperV = $false` when `HypervisorType='VMware'`
**No code changes needed** — logic already exists.

**HYP-04:** Dashboard visually hides irrelevant hypervisor checks
**Implementation:** Add function `Update-HypervisorCategoryVisibility` to FFUUI.Core.Dashboard.psm1:
```powershell
function Update-HypervisorCategoryVisibility {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State,

        [Parameter(Mandatory)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType
    )

    $expander = $State.Controls.expHypervisor

    # Determine if any hypervisor checks will run
    $hasRelevantChecks = switch ($HypervisorType) {
        'HyperV' { $true }  # HyperV check runs
        'VMware' { $true }  # VmxToolkit, VMwareDrivers, etc. run
        'Auto'   { $true }  # Auto-detect runs checks for detected hypervisor
    }

    if ($hasRelevantChecks) {
        $expander.Visibility = [System.Windows.Visibility]::Visible
    }
    else {
        $expander.Visibility = [System.Windows.Visibility]::Collapsed
    }
}
```

**HYP-05:** Dashboard displays skip message for non-selected hypervisor
**Implementation:** Add inline info banner after summary status banner in XAML:
```xml
<!-- After borderSummaryStatus, before pnlDashboardProgress -->
<Border x:Name="borderHypervisorInfo" Background="#E3F2FD" Padding="8" CornerRadius="3" Margin="0,4,0,4" Visibility="Collapsed">
    <StackPanel Orientation="Horizontal">
        <TextBlock Text="ℹ" FontSize="14" Foreground="#1976D2" Margin="0,0,6,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="txtHypervisorInfo" Text="" Foreground="#1565C0" FontSize="12"/>
    </StackPanel>
</Border>
```

Update text when checks complete:
```powershell
if ($hypervisorType -eq 'VMware') {
    $State.Controls.borderHypervisorInfo.Visibility = [System.Windows.Visibility]::Visible
    $State.Controls.txtHypervisorInfo.Text = "Validating for: VMware Workstation — Hyper-V checks skipped"
}
elseif ($hypervisorType -eq 'HyperV') {
    $State.Controls.borderHypervisorInfo.Visibility = [System.Windows.Visibility]::Visible
    $State.Controls.txtHypervisorInfo.Text = "Validating for: Hyper-V — VMware checks skipped"
}
```

### 3.2 Auto-Remediation UX (REM-01 through REM-04)

**REM-01:** One-click fix button for safe issues
**Safe remediations identified:**
- WIMMount service repair (extract from `Test-FFUWimMount`)
- DISM cleanup (`Invoke-FFUDISMCleanup` already exists)
- DISM restore health (`DISM /Online /Cleanup-Image /RestoreHealth`)
- DNS cache clear (`Clear-DnsClientCache`)

**Implementation approach:**
1. Create `Repair-FFUWimMount` function in FFU.Preflight.psm1
2. Create `Repair-FFUNetwork` function in FFU.Preflight.psm1
3. Map check names to repair functions:
```powershell
$script:RepairFunctions = @{
    'WimMount' = { Repair-FFUWimMount }
    'DISMCleanup' = { Invoke-FFUDISMCleanup -FFUDevelopmentPath $args[0] }
    'DISMState' = { Repair-FFUDismState }
    'Network' = { Repair-FFUNetwork }
}
```

**Button placement:** Inline next to check status (per CONTEXT.md decision):
```powershell
# In Update-DashboardCheckUI, after status icon + name + message
if ($Status -eq 'Failed' -and $script:RepairFunctions.ContainsKey($CheckName)) {
    $btnFix = [System.Windows.Controls.Button]::new()
    $btnFix.Content = 'Fix'
    $btnFix.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
    $btnFix.Padding = [System.Windows.Thickness]::new(8, 2)
    $btnFix.Background = [System.Windows.Media.Brushes]::LightGreen

    # Click handler executes repair function
    $btnFix.Add_Click({
        # Transform button to spinner
        $this.Content = 'Fixing...'
        $this.IsEnabled = $false

        # Execute repair in background
        # Re-run check after repair
        # Update UI with new status
    })

    [void]$innerPanel.Children.Add($btnFix)
}
```

**REM-02:** Unsafe remediations show reboot confirmation dialog
**Unsafe checks identified:**
- HyperV (`Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart`)
- PowerShellVersion (manual install, not auto-fixable)

**Implementation:**
```powershell
$script:UnsafeRemediations = @{
    'HyperV' = @{
        Command = 'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart'
        RequiresReboot = $true
        ConfirmationMessage = @"
This will enable Hyper-V on your system.

Command to run:
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart

A system reboot is required to complete the installation.
The build cannot proceed until the system is restarted.

Continue?
"@
    }
}

# In Fix button click handler for unsafe remediations
$result = [System.Windows.MessageBox]::Show(
    $confirmationMessage,
    'Confirm System Change',
    [System.Windows.MessageBoxButton]::YesNo,
    [System.Windows.MessageBoxImage]::Warning
)

if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
    # Execute command
    Invoke-Expression $command

    [System.Windows.MessageBox]::Show(
        "Hyper-V has been enabled. Please reboot your system to complete the installation.",
        'Reboot Required',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    )
}
```

**REM-03:** Failed checks display copy-paste PowerShell commands
**Implementation:** Add Details expander to failed checks in `Update-DashboardCheckUI`:
```powershell
# After remediation Expander
if ($Status -eq 'Failed' -and -not [string]::IsNullOrWhiteSpace($Remediation)) {
    $detailsExpander = [System.Windows.Controls.Expander]::new()
    $detailsExpander.Header = 'Details'
    $detailsExpander.IsExpanded = $false
    $detailsExpander.Margin = [System.Windows.Thickness]::new(22, 2, 0, 4)

    # Extract PowerShell commands from remediation text
    $commands = Extract-PowerShellCommands -RemediationText $Remediation

    # Create monospace TextBox
    $txtCommands = [System.Windows.Controls.TextBox]::new()
    $txtCommands.Text = $commands -join "`n"
    $txtCommands.IsReadOnly = $true
    $txtCommands.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $txtCommands.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $txtCommands.Background = [System.Windows.Media.Brushes]::WhiteSmoke

    # Copy button
    $btnCopy = [System.Windows.Controls.Button]::new()
    $btnCopy.Content = 'Copy'
    $btnCopy.Width = 60
    $btnCopy.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)

    $btnCopy.Add_Click({
        [System.Windows.Clipboard]::SetText($txtCommands.Text)
        $originalContent = $this.Content
        $this.Content = 'Copied!'

        # Reset after 2 seconds
        Start-Sleep -Milliseconds 2000
        $this.Content = $originalContent
    })

    $contentPanel = [System.Windows.Controls.StackPanel]::new()
    [void]$contentPanel.Children.Add($txtCommands)
    [void]$contentPanel.Children.Add($btnCopy)

    $detailsExpander.Content = $contentPanel
    [void]$outerPanel.Children.Add($detailsExpander)
}
```

**REM-04:** Each completed check displays duration
**Implementation:** Append duration to message text in `Update-DashboardCheckUI`:
```powershell
# After status icon, check name, modify message TextBlock
if (-not [string]::IsNullOrWhiteSpace($Message)) {
    $durationText = if ($DurationMs -gt 0) {
        $seconds = [Math]::Round($DurationMs / 1000.0, 1)
        " (${seconds}s)"
    } else { '' }

    $messageBlock.Text = "$Message$durationText"
}
```

Add `DurationMs` parameter to `Update-DashboardCheckUI`:
```powershell
[Parameter()]
[int]$DurationMs = 0
```

Update call sites in `Start-DashboardChecks` (BuildFFUVM_UI.ps1):
```powershell
Update-DashboardCheckUI -State $state `
    -CheckName $check.CheckName `
    -Status $check.Status `
    -Severity $check.Severity `
    -Message $check.Message `
    -Remediation $check.Remediation `
    -DurationMs $check.DurationMs
```

---

## 4. Technical Considerations

### 4.1 WPF Threading and Background Execution

**Problem:** Repair functions may take 5-30 seconds. Must not block UI thread.

**Solution:** Use `Start-Job` to execute repair, poll for completion:
```powershell
$btnFix.Add_Click({
    $checkName = $CheckName  # Capture in closure

    # Transform button
    $this.Content = 'Fixing...'
    $this.IsEnabled = $false

    # Start repair job
    $repairJob = Start-Job -ScriptBlock {
        param($CheckName)

        # Import modules (jobs start in clean runspace)
        Import-Module FFU.Preflight -Force

        $repairFunc = $using:RepairFunctions[$CheckName]
        & $repairFunc
    } -ArgumentList $checkName

    # Poll for completion (use DispatcherTimer)
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($repairJob.State -eq 'Completed') {
            $this.Stop()

            $repairResult = Receive-Job -Job $repairJob
            Remove-Job -Job $repairJob

            # Re-run check to verify fix
            $checkResult = & "Test-FFU$checkName"

            # Update UI with new status
            Update-DashboardCheckUI -State $state `
                -CheckName $checkName `
                -Status $checkResult.Status `
                -Severity $checkResult.Severity `
                -Message $checkResult.Message `
                -Remediation $checkResult.Remediation `
                -DurationMs $checkResult.DurationMs
        }
    })
    $timer.Start()
})
```

**Alternative (simpler):** Use `Invoke-Command` with `-AsJob` for module visibility:
```powershell
$repairJob = Start-ThreadJob -ScriptBlock {
    param($CheckName, $FFUPath)

    # Modules already loaded in current session
    & $using:RepairFunctions[$CheckName] -FFUDevelopmentPath $FFUPath
} -ArgumentList $checkName, $FFUDevelopmentPath
```

### 4.2 Spinner Implementation

**Requirement:** Button transforms to "Fixing..." text with spinner during execution.

**Options:**
1. **Text-only** (simplest): `$btnFix.Content = 'Fixing...'` (no animation)
2. **ProgressBar overlay** (medium): Replace button content with horizontal ProgressBar (indeterminate)
3. **Custom animation** (complex): Create rotating Unicode spinner using DispatcherTimer

**Recommendation:** Text-only for MVP. Users understand "Fixing..." implies in-progress work. Animation can be added in Phase 48 polish if desired.

### 4.3 Parsing PowerShell Commands from Remediation Text

**Remediation format (from `New-FFURemediationBlock`):**
```
=== ISSUE ===
Hyper-V feature is not installed

=== IMPACT ===
Build cannot proceed without virtualization

=== FIX ===
Run these PowerShell commands (as Administrator):

    # Enable Hyper-V (requires restart)
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart

    # Or use DISM
    dism /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V-All /All

Manual steps:
    1. Press Win+R, type 'optionalfeatures', press Enter
    2. Check 'Hyper-V' (all sub-features)
    3. Click OK and restart computer

=== VERIFY ===
Run this to confirm the fix worked:

    Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All | Select-Object State
```

**Extraction function:**
```powershell
function Extract-PowerShellCommands {
    param([string]$RemediationText)

    # Find FIX section
    if ($RemediationText -match '(?s)=== FIX ===\s+Run these PowerShell commands.*?\n\n(.*?)(?:Manual steps:|=== VERIFY ===|$)') {
        $commandBlock = $matches[1]

        # Split by newline, filter out comments and blank lines
        $commands = $commandBlock -split '\n' |
            Where-Object { $_ -match '^\s+' -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' } |
            ForEach-Object { $_.Trim() }

        return $commands
    }

    return @()
}
```

### 4.4 Duration Display Format

**Requirement:** Show duration as "Passed (1.2s)" or "Failed (0.8s)"

**Implementation:**
```powershell
$durationText = if ($check.DurationMs -gt 0) {
    $seconds = [Math]::Round($check.DurationMs / 1000.0, 1)
    " (${seconds}s)"
} else { '' }

$displayMessage = "$($check.Message)$durationText"
```

**Example outputs:**
- "Running with Administrator privileges (0.1s)"
- "Hyper-V feature is installed and enabled (1.5s)"
- "Windows ADK not installed (0.3s)"

---

## 5. Testing Strategy

### 5.1 Hypervisor Conditional Logic Tests

**Unit tests for FFUUI.Core.Dashboard:**
```powershell
Describe 'Update-HypervisorCategoryVisibility' {
    It 'shows Hypervisor category when HypervisorType is HyperV' {
        $state = New-MockState
        Update-HypervisorCategoryVisibility -State $state -HypervisorType 'HyperV'
        $state.Controls.expHypervisor.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
    }

    It 'shows Hypervisor category when HypervisorType is VMware' {
        $state = New-MockState
        Update-HypervisorCategoryVisibility -State $state -HypervisorType 'VMware'
        $state.Controls.expHypervisor.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
    }
}
```

**Integration tests (manual verification):**
1. Set hypervisor to Hyper-V → Run dashboard checks → Verify HyperV check runs, VMware checks skipped
2. Set hypervisor to VMware → Run dashboard checks → Verify VMware checks run, HyperV check skipped
3. Set hypervisor to Auto → Run dashboard checks → Verify auto-detection chooses correct checks

### 5.2 Auto-Remediation Tests

**Unit tests for repair functions:**
```powershell
Describe 'Repair-FFUWimMount' {
    It 'returns Succeeded=true when repair works' {
        $result = Repair-FFUWimMount
        $result.Succeeded | Should -Be $true
        $result.Message | Should -Match 'successfully'
        $result.DurationMs | Should -BeGreaterThan 0
    }

    It 'returns Succeeded=false when repair fails' {
        # Mock fltmc to fail
        Mock Invoke-Expression { throw 'Service unavailable' }

        $result = Repair-FFUWimMount
        $result.Succeeded | Should -Be $false
        $result.Message | Should -Match 'failed'
    }
}
```

**Manual UI tests:**
1. **WIMMount safe fix:**
   - Manually stop wimmount service: `net stop wimmount`
   - Run dashboard checks → WIMMount fails
   - Click "Fix" button → Verify button shows "Fixing..."
   - Wait for completion → Verify check re-runs and shows green pass
2. **Hyper-V unsafe fix:**
   - Disable Hyper-V in Windows Features
   - Run dashboard checks → HyperV fails
   - Click "Fix" button → Verify confirmation dialog appears
   - Click "Yes" → Verify command executes, reboot prompt appears
3. **Details expander:**
   - Click failed check → Verify Details expander appears
   - Expand Details → Verify PowerShell commands displayed
   - Click "Copy" → Verify clipboard contains commands
   - Verify "Copied!" tooltip appears for 2 seconds

### 5.3 Pester Test File Structure

**New test file:** `Tests/Unit/FFUUI.Core.Dashboard.AutoRemediation.Tests.ps1`
```powershell
BeforeAll {
    Import-Module FFU.Preflight -Force
    Import-Module FFUUI.Core.Dashboard -Force
}

Describe 'Repair Functions' {
    Context 'Repair-FFUWimMount' { }
    Context 'Repair-FFUNetwork' { }
    Context 'Extract-PowerShellCommands' { }
}

Describe 'Dashboard Remediation UI' {
    Context 'Update-DashboardCheckUI with Fix button' { }
    Context 'Unsafe remediation confirmation' { }
}
```

---

## 6. File Modifications Required

### 6.1 New Functions (FFU.Preflight)

**Create:**
1. `Repair-FFUWimMount` — Extract repair logic from `Test-FFUWimMount`
2. `Repair-FFUDismState` — Wrapper for `DISM /Online /Cleanup-Image /RestoreHealth`
3. `Repair-FFUNetwork` — DNS cache clear + connectivity test

**Export in FFU.Preflight.psd1:**
```powershell
FunctionsToExport = @(
    # ... existing exports
    'Repair-FFUWimMount',
    'Repair-FFUDismState',
    'Repair-FFUNetwork'
)
```

### 6.2 Enhanced Functions (FFUUI.Core.Dashboard)

**Modify:**
1. `Update-DashboardCheckUI` — Add Fix button, Details expander, duration display
2. Add `Update-HypervisorCategoryVisibility` — Control expHypervisor visibility
3. Add `Extract-PowerShellCommands` — Parse remediation text
4. Add `Invoke-SafeRemediation` — Execute repair function in background

**Export in FFUUI.Core.Dashboard.psm1:**
```powershell
Export-ModuleMember -Function @(
    'Get-CheckCategory',
    'Update-DashboardCheckUI',
    'Update-CategorySummary',
    'Update-SummaryStatus',
    'Update-BuildButtonState',
    'Clear-DashboardResults',
    'Update-HypervisorCategoryVisibility',
    'Invoke-SafeRemediation'
)
```

### 6.3 UI Modifications (BuildFFUVM_UI.xaml)

**Add:**
1. Inline hypervisor info banner (after `borderSummaryStatus`, before `pnlDashboardProgress`)

### 6.4 Event Handler Modifications (BuildFFUVM_UI.ps1)

**Modify:**
1. `Start-DashboardChecks` — Call `Update-HypervisorCategoryVisibility` before starting checks
2. Pass `DurationMs` when calling `Update-DashboardCheckUI`
3. Update hypervisor info banner text after checks complete

---

## 7. Dependencies and Risks

### 7.1 Dependencies

| Dependency | Status | Risk |
|------------|--------|------|
| Phase 46 dashboard infrastructure | ✅ Complete | None |
| FFU.Preflight check functions | ✅ Exists | None |
| WIMMount repair logic | ✅ Implemented in Test-FFUWimMount | Low — needs extraction |
| Hyper-V conditional execution | ✅ Implemented in Invoke-FFUPreflight | None |
| Check duration tracking | ✅ All checks track DurationMs | None |

### 7.2 Risks and Mitigations

**Risk 1:** Repair functions hang or fail silently
**Mitigation:** Execute in background job with timeout (30 seconds), show error message on failure

**Risk 2:** User clicks Fix button multiple times
**Mitigation:** Disable button immediately on click, prevent double-execution

**Risk 3:** Re-running check after repair doesn't detect fix
**Mitigation:** Add 2-second delay before re-running check to allow services to stabilize

**Risk 4:** PowerShell command extraction fails for unexpected format
**Mitigation:** Fallback to showing full remediation text if parsing fails

**Risk 5:** Clipboard operations fail (clipboard in use)
**Mitigation:** Wrap `SetText` in try/catch, show error message if copy fails

---

## 8. Open Questions for Planner

1. **Spinner approach:** Text-only "Fixing..." or implement ProgressBar overlay?
   - **Recommendation:** Text-only for MVP, animation can be Phase 48 polish
2. **Fix button retry logic:** Should users be able to click Fix multiple times if first attempt fails?
   - **Recommendation:** Yes, re-enable button after fix completes (success or failure)
3. **Hypervisor category ordering:** Should Hypervisor category move to top when relevant checks fail?
   - **Recommendation:** No, keep fixed category order (System, Hypervisor, BuildTools, Network, Optimization) for consistency
4. **Duration precision:** 1 decimal (1.2s) or 2 decimals (1.23s)?
   - **Recommendation:** 1 decimal — sufficient precision, cleaner display
5. **Copy button async behavior:** Should "Copied!" tooltip use async timer or block UI for 2 seconds?
   - **Recommendation:** Async with DispatcherTimer — don't block UI thread

---

## 9. Phase Boundary Validation

**In Scope (Phase 47):**
- ✅ Conditional hypervisor check execution (HYP-01, HYP-02, HYP-03)
- ✅ Hypervisor category visibility toggle (HYP-04)
- ✅ Hypervisor info banner (HYP-05)
- ✅ One-click safe fixes (REM-01)
- ✅ Unsafe remediation confirmation (REM-02)
- ✅ Copy-paste PowerShell commands (REM-03)
- ✅ Check duration display (REM-04)

**Out of Scope (Deferred to Phase 48):**
- ❌ Auto-refresh dashboard when hypervisor changes in VM Settings
- ❌ Staleness detection ("Last checked: 2 minutes ago")
- ❌ Export diagnostics to text file
- ❌ Animated spinner for Fix button (text-only sufficient for MVP)

---

## 10. Success Metrics

**Phase 47 Success Criteria (from ROADMAP.md):**
1. ✅ Hyper-V pre-flight checks only execute when Hyper-V is the selected hypervisor in VM Settings
2. ✅ VMware pre-flight checks only execute when VMware is the selected hypervisor in VM Settings
3. ✅ Build is not blocked by missing Hyper-V when VMware is selected as the hypervisor
4. ✅ Dashboard visually hides irrelevant hypervisor checks (shows only selected hypervisor's category)
5. ✅ Dashboard displays clear skip message for non-selected hypervisor ("Hyper-V checks skipped — using VMware")
6. ✅ User can click a one-click fix button for safe issues (WIMMount repair, DISM cleanup, service restart)
7. ✅ Unsafe remediations (e.g., Enable Hyper-V) show a reboot confirmation dialog before executing
8. ✅ Failed checks display copy-paste PowerShell commands in a selectable textbox for manual remediation
9. ✅ Each completed check displays its duration ("Completed in 1.2s") for transparency

**All requirements are feasible based on existing infrastructure.**

---

## Conclusion

Phase 47 implementation is **low-risk and high-confidence**. The codebase already contains:
- Conditional hypervisor check execution logic
- Auto-repair implementation (WIMMount)
- Structured remediation text with PowerShell commands
- Duration tracking in all checks
- Dashboard UI framework from Phase 46

**Primary work is integration, not invention:**
1. Extract WIMMount repair into callable function
2. Add Fix button to check display logic
3. Add Details expander with command parsing
4. Add hypervisor info banner to XAML
5. Call `Update-HypervisorCategoryVisibility` before checks run

**Estimated complexity: Medium.** Most logic exists, integration requires careful WPF threading and state management.

---

**Research Complete:** 2026-02-06
**Next Step:** Planning (47-01-PLAN.md, 47-02-PLAN.md, etc.)
