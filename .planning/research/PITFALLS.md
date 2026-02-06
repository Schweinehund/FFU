# Pitfalls Research

**Domain:** WPF PowerShell Application - Readiness Dashboard & Optional Prerequisites
**Researched:** 2026-02-05
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Dispatcher.Invoke Blocking UI Thread from Background Jobs

**What goes wrong:**
Using `Dispatcher.Invoke` synchronously from background jobs causes the UI to freeze while waiting for the dispatcher operation to complete. In FFUBuilder's case, with 50ms DispatcherTimer polling, multiple synchronous dispatcher calls can create cumulative delays that make the UI feel sluggish or unresponsive during readiness checks.

**Why it happens:**
Developers familiar with C# WPF naturally reach for `Dispatcher.Invoke` when updating UI from background threads. PowerShell's ThreadJob pattern inherited the UI window object (`$Window.Dispatcher.Invoke`), making it easy to block the UI thread without realizing the performance impact.

**How to avoid:**
1. **Always use Dispatcher.BeginInvoke** for non-critical UI updates (status messages, progress indicators)
2. **Reserve Dispatcher.Invoke only for** scenarios requiring immediate UI state synchronization
3. **Use FFU.Messaging ConcurrentQueue pattern** that FFUBuilder already has - it's 20x faster than file polling
4. **Batch updates** - don't dispatch every single check result individually, collect them and update in batches

```powershell
# BAD: Synchronous blocking call
$Window.Dispatcher.Invoke([Action] {
    $StatusTextBlock.Text = "Checking Hyper-V..."
})

# GOOD: Asynchronous non-blocking call
$Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] {
    $StatusTextBlock.Text = "Checking Hyper-V..."
})

# BEST: Use FFU.Messaging queue
Send-FFUMessage -Level Info -Message "Checking Hyper-V..." -Source "PreFlight"
```

**Warning signs:**
- UI feels sluggish when readiness dashboard refreshes
- Mouse cursor shows "busy" spinner during checks
- DispatcherTimer callbacks take >100ms to complete
- Multiple consecutive "Not Responding" warnings in Task Manager

**Phase to address:**
Phase 1 (Dashboard Foundation) - Establish the dispatcher pattern before adding check implementations

---

### Pitfall 2: ThreadJob Cmdlet Availability Issues During Readiness Checks

**What goes wrong:**
PowerShell cmdlets like `Get-Date`, `Write-Host`, `Get-Command`, and `Write-Warning` become unavailable or throw errors during heavy ThreadJob operations. Readiness checks that use these cmdlets fail intermittently with "The term 'Get-Date' is not recognized" errors.

**Why it happens:**
ThreadJob runspaces have limited cmdlet availability - only `Microsoft.PowerShell.Core` and `Microsoft.PowerShell.Utility` cmdlets are guaranteed. During heavy operations (like running multiple pre-flight checks), even these can become temporarily unavailable due to runspace resource contention.

**How to avoid:**
FFUBuilder already has established patterns (from v0.0.9-v0.0.12 fixes):

| Cmdlet | Safe Alternative |
|--------|-----------------|
| `Get-Date` | `[DateTime]::Now` or `[DateTime]::UtcNow` |
| `Write-Host` | `[Console]::WriteLine()` or WriteLog function |
| `Write-Warning` | Safe logging pattern with `$function:WriteLog` check |
| `Get-Command FuncName` | `$function:FuncName` (for functions) |
| `Get-Command CmdletName` | try/catch around actual cmdlet call |
| `Get-Command exe.exe` | `Find-ExecutableInPath 'exe.exe'` (FFU.Common.Core) |

**Safe logging pattern for warnings:**
```powershell
# Uses $function: drive instead of Get-Command (v0.0.12 pattern)
$warningMsg = "Hyper-V not enabled but VMware detected"
if ($function:WriteLog) {
    WriteLog "WARNING: $warningMsg"
}
else {
    Write-Verbose "WARNING: $warningMsg"
}
```

**Warning signs:**
- Intermittent "cmdlet not recognized" errors in logs
- Pre-flight checks fail randomly on second/third run
- Errors disappear when running checks outside ThreadJob context
- Stack traces showing runspace initialization failures

**Phase to address:**
Phase 1 (Dashboard Foundation) - Audit ALL pre-flight check code for cmdlet usage before implementing dashboard UI

---

### Pitfall 3: Auto-Remediation Without Reboot Safety Gates

**What goes wrong:**
Auto-remediation enables Hyper-V or other Windows features that require reboot, but doesn't block further operations. User clicks "Start Build" after auto-remediation completes, build proceeds to VM creation, and fails catastrophically because Hyper-V isn't actually available until reboot. Worse: auto-remediation runs silently on startup, system needs reboot, user doesn't know.

**Why it happens:**
Windows Optional Features API (`Enable-WindowsOptionalFeature`) returns success immediately, but the feature isn't active until reboot. Developers assume "success = ready to use" and don't check for pending reboot state.

**How to avoid:**
1. **Detect pending reboots** before and after remediation:
   ```powershell
   function Test-PendingReboot {
       $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
       $wuau = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
       $hyperv = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Serviring\PackagesPending'
       return ($cbs -or $wuau -or $hyperv)
   }
   ```

2. **Block build operations if reboot pending:**
   ```powershell
   if ($remediationResult.RequiresReboot -or (Test-PendingReboot)) {
       $buildButton.IsEnabled = $false
       $statusMessage = "System reboot required before build can proceed"
       # Show prominent warning banner in dashboard
   }
   ```

3. **Never auto-reboot without explicit consent:**
   - Show modal dialog: "Hyper-V enabled. Reboot now or later?"
   - Provide "Reboot Now" and "Reboot Later" buttons
   - If "Later": disable build until manual reboot occurs
   - Log warning: "User chose to reboot later - build disabled until reboot"

4. **Whitelist safe remediations:**
   ```powershell
   # Safe: doesn't require reboot
   $safeRemediations = @(
       'EnableLongPathSupport',      # Registry change, instant
       'DisableAntivirusRealtime',    # Service change, instant
       'CreateVMSwitch'               # Hyper-V cmdlet, instant (if HV already enabled)
   )

   # Unsafe: requires reboot
   $unsafeRemediations = @(
       'EnableHyperV',                # Windows feature, reboot required
       'EnableVirtualizationExtensions', # BIOS/UEFI, reboot required
       'InstallWindowsADK'            # Installer, may require reboot
   )
   ```

**Warning signs:**
- User reports "build starts then immediately fails"
- Logs show "Hyper-V enabled successfully" followed by "VM creation failed: Hyper-V not available"
- Dashboard shows green checkmark for Hyper-V but `Get-WindowsOptionalFeature` shows State=EnablePending
- Registry shows `Component Based Servicing\RebootPending` key exists

**Phase to address:**
Phase 2 (Auto-Remediation) - MUST implement reboot detection and gating before ANY auto-remediation features ship

---

### Pitfall 4: Tightly Coupled Pre-flight Checks Prevent Optional Hyper-V

**What goes wrong:**
Existing pre-flight code (`FFU.Preflight` module) hardcodes Hyper-V as Tier 1 CRITICAL check that always runs and blocks builds. When making Hyper-V optional, developers modify the check to "always pass" or "skip if VMware selected", creating a configuration state where:
- Hyper-V check shows "Passed" (green) even though Hyper-V is disabled
- User selects Hyper-V as hypervisor later, build fails because they trusted the green checkmark
- OR: Hyper-V check doesn't run at all, user doesn't realize they need to enable it

**Why it happens:**
Original design (Tier 1-4 validation tiers) assumed all prerequisites are unconditional. The validation logic conflates "check execution" with "build blocking". Making something optional requires THREE states (not two):
1. Checked and required (current state)
2. Checked but not required (shows warning, doesn't block build)
3. Not checked at all (skipped entirely)

Current code pattern:
```powershell
# Tier 1: CRITICAL (Always Run, Blocking)
$checks = @(
    { Test-AdminPrivileges },      # Always required
    { Test-PowerShell7 },           # Always required
    { Test-HyperV }                 # WAS always required, NOW conditional!
)
```

**How to avoid:**
1. **Introduce "Conditional" check tier** between Tier 1 and Tier 2:
   ```powershell
   enum CheckTier {
       Critical_Always     = 1  # Admin, PowerShell - ALWAYS run, ALWAYS block
       Critical_Conditional = 2  # Hyper-V, VMware - ONLY run if selected, then block
       Feature_Dependent   = 3  # ADK, disk space - depends on features enabled
       Recommended         = 4  # Antivirus exclusions - warnings only
       Cleanup             = 5  # DISM cleanup - pre-remediation only
   }
   ```

2. **Pass configuration context to validator:**
   ```powershell
   # BAD: Validator doesn't know what user selected
   $validator = New-PreFlightValidator
   $validator.ValidateAll()  # How does it know if Hyper-V is needed?

   # GOOD: Validator knows configuration
   $validator = New-PreFlightValidator -Configuration $config
   $hypervisorType = $config.hypervisor.provider  # 'HyperV' or 'VMware'
   if ($hypervisorType -eq 'HyperV') {
       # Run Hyper-V checks as BLOCKING
   } else {
       # Skip Hyper-V checks entirely OR run as informational only
   }
   ```

3. **Distinguish check state in UI:**
   ```
   STATUS          ICON    MEANING
   ============================================
   Passed          ✓       Check ran and passed
   Failed          ✗       Check ran and failed (blocking)
   Warning         ⚠       Check ran, issue detected (non-blocking)
   Skipped         —       Check not applicable to current config
   Not Run         ?       Check applicable but hasn't run yet
   ```

4. **Make checks revalidate on config change:**
   ```powershell
   # User changes hypervisor dropdown: HyperV -> VMware
   $hypervisorComboBox.Add_SelectionChanged({
       # Re-run validation with new config
       $newConfig = Get-UIConfiguration -State $uiState
       $validationResult = $validator.ValidateAll($newConfig)
       Update-DashboardChecks -Result $validationResult

       # Example outcome:
       # - Hyper-V check: Passed -> Skipped (no longer needed)
       # - VMware check: Skipped -> Failed (now required, not installed)
   })
   ```

**Warning signs:**
- Dashboard shows all green checkmarks regardless of hypervisor selection
- User can start build with Hyper-V selected but Hyper-V not installed
- Changing hypervisor dropdown doesn't update dashboard status
- Tests hardcode `$config.hypervisor.provider = 'HyperV'` to make tests pass

**Phase to address:**
Phase 3 (Optional Hyper-V) - Restructure validation tiers and configuration context BEFORE making Hyper-V optional

---

### Pitfall 5: Dashboard Refresh During Active Build Corrupts Job State

**What goes wrong:**
User clicks "Refresh Dashboard" button while build is running in background ThreadJob. Refresh operation:
1. Re-runs pre-flight checks in NEW ThreadJob
2. Both jobs try to access DISM service simultaneously
3. DISM service locks (supports single client)
4. Build job hangs waiting for DISM lock
5. Refresh job times out
6. Neither completes, build is stuck, user must kill process

**Why it happens:**
Dashboard refresh logic doesn't check if build is active. Developers assume "refresh is read-only" but pre-flight checks aren't read-only:
- `Test-ADKPrerequisites` calls DISM.exe to check provisioning status
- `Test-FFUWimMount` calls `fltmc filters` and may restart WIMMount service
- `Test-DismReady` calls DISM cleanup operations
- Auto-remediation (if enabled) modifies system state

**How to avoid:**
1. **Disable refresh during build:**
   ```powershell
   function Start-FFUBuild {
       $uiState.Flags.isBuilding = $true
       $refreshButton.IsEnabled = $false
       $refreshButton.ToolTip = "Dashboard refresh disabled during build"
       # ... start build job
   }

   function Stop-FFUBuild {
       $uiState.Flags.isBuilding = $false
       $refreshButton.IsEnabled = $true
       $refreshButton.ToolTip = "Refresh readiness dashboard"
   }
   ```

2. **Make checks mutex-aware for DISM operations:**
   ```powershell
   # Global mutex for DISM operations
   $script:dismMutex = $null

   function Invoke-DismOperation {
       param([ScriptBlock]$Operation)

       try {
           $script:dismMutex = New-Object System.Threading.Mutex($false, "Global\FFUBuilder_DISM")
           if ($script:dismMutex.WaitOne(30000)) {  # 30 second timeout
               & $Operation
           } else {
               throw "DISM operation timed out waiting for lock (another operation in progress?)"
           }
       }
       finally {
           if ($script:dismMutex) { $script:dismMutex.ReleaseMutex() }
       }
   }
   ```

3. **Auto-refresh on build completion only:**
   ```powershell
   # In DispatcherTimer polling logic
   if ($job.State -eq 'Completed') {
       $uiState.Flags.isBuilding = $false
       # Auto-refresh dashboard to show post-build state
       Invoke-RefreshDashboard -State $uiState -Silent
   }
   ```

4. **Show "stale" indicator if build completed:**
   ```powershell
   # Visual indicator: "Dashboard shows pre-build state. Refresh to see current state."
   if ($uiState.Data.lastRefreshTime -lt $uiState.Data.lastBuildCompletionTime) {
       $staleWarningBanner.Visibility = 'Visible'
   }
   ```

**Warning signs:**
- Build hangs at "Initializing DISM" phase with no progress
- Logs show "Waiting for DISM service..." repeated indefinitely
- Task Manager shows multiple DISM.exe processes
- Restarting UI doesn't clear the hang (DISM lock persists until reboot)
- Event Viewer shows DISM errors: "Failed to acquire exclusive lock"

**Phase to address:**
Phase 1 (Dashboard Foundation) - Implement build-aware UI state management before adding refresh functionality

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip DISM mutex for "read-only" checks | Faster check execution, simpler code | DISM lock contention, random hangs, difficult to debug race conditions | Never - even read operations can conflict |
| Use Dispatcher.Invoke everywhere | Guaranteed synchronous UI updates, no race conditions | Sluggish UI, 50ms timer delays compound, user perceives app as slow | Only for critical state synchronization (e.g., disabling build button) |
| Hardcode "Hyper-V required=true" in checks | Easy to implement optional Hyper-V without refactoring | Config changes don't update dashboard, test suite becomes unreliable | Never - breaks core feature |
| Cache check results indefinitely | Dashboard shows instantly on tab switch | Shows stale data after config changes, users trust outdated status | Only with explicit TTL (60 seconds) and "Last checked: X ago" display |
| Auto-remediate without user confirmation | Smooth UX, no dialogs, "just works" | Unexpected system changes, reboot surprises, user loses trust | Only for provably safe operations (registry tweaks, exclusion lists) |
| Poll dashboard via DispatcherTimer | Consistent with existing UI pattern (log polling at 50ms) | Timer keeps firing even when hidden, wastes CPU, delays other UI operations | Only if check is instant (<10ms) - otherwise use manual refresh |
| Show all checks in one flat list | Simple to implement, easy to understand | Can't prioritize failures, can't group by severity, overwhelming when 15+ checks fail | Only for MVP with <8 checks total |

---

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| DISM Service | Assume DISM always available, call directly | Always call via `Test-DismReady` gate (FFU.Core pattern), retry with cleanup if fails |
| WIMMount Filter | Assume WIMMount works if installed | Use `Test-FFUWimMount` JIT validation before every mount operation (FFU.Preflight pattern) |
| Hyper-V Check | Use `Get-WindowsOptionalFeature` only | Check multiple signals: Optional Feature State=Enabled, `vmms` service running, `Get-VMHost` succeeds |
| VMware REST API | Assume localhost:8697 always works | Detect installation path from registry, verify service running, handle auth failure gracefully |
| Registry Reboot Detection | Check only `RebootPending` key | Check ALL keys: CBS RebootPending, WUAU RebootRequired, PackagesPending, PendingFileRenameOperations |
| Admin Privilege Check | Use `[Security.Principal.WindowsPrincipal]::IsInRole('Administrator')` | Correct BUT also verify UAC hasn't restricted privileges (`Test-Path 'HKLM:\SOFTWARE' -ErrorAction Stop`) |
| PowerShell Version Check | Check `$PSVersionTable.PSVersion.Major -ge 7` | Correct BUT also verify ThreadJob module available (`Get-Module -ListAvailable -Name ThreadJob`) |
| Long Path Support | Enable via registry, assume instant effect | Registry change is instant BUT running processes cached the old value - recommend app restart |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Synchronous Dispatcher.Invoke in loop | First 3 checks feel fine, check #4+ slow, total time 2-3 seconds for 10 checks | Use BeginInvoke for all non-critical updates, batch updates | When >5 checks run (each invoke adds 50-100ms overhead) |
| Running all checks on every config change | Responsive for first few changes, then UI freezes when user rapidly changes dropdowns | Debounce config change events (300ms delay), cancel in-flight validation, use optimistic UI updates | When user makes rapid config changes (5+ in 2 seconds) |
| File-based log polling at 50ms | Works fine for builds, acceptable CPU usage | For real-time dashboard updates use FFU.Messaging ConcurrentQueue (20x faster) | When 10+ status updates per second (log file I/O becomes bottleneck) |
| Recreating entire dashboard on each refresh | 8 checks refresh in <100ms, acceptable | Incremental updates: only modify changed check statuses, reuse existing UI elements | When >15 checks (full refresh takes >200ms, feels sluggish) |
| Running checks serially in ThreadJob | First run takes 5 seconds, acceptable | Run independent checks in parallel (use `Invoke-Parallel` from FFU.Common or PS7 ForEach-Object -Parallel) | When total serial time >3 seconds (user perceives as slow) |
| DispatcherTimer without IsEnabled check | Timer fires but finds nothing to do, wastes cycles | Disable timer when dashboard tab not visible, re-enable on tab switch | When user leaves dashboard tab open for hours (cumulative CPU waste) |
| Auto-refresh on 5-second timer | Background refresh feels "live" | Only auto-refresh on explicit triggers (build completion, config change), use manual refresh otherwise | When checks involve disk/network I/O (causes constant disk activity) |

---

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Auto-enabling Hyper-V without admin consent | Unexpected system changes, user loses control, enterprise policy violations | Always show confirmation dialog, log to event viewer, provide opt-out mechanism |
| Storing auto-remediation choices in user registry | Low-privilege user can modify, causes privilege escalation (auto-remediate runs as admin) | Store choices in HKLM (admin-only), validate on read, use ACLs to prevent tampering |
| Running auto-remediation scripts from temp folder | AV quarantine, MOTW blocks execution, user confusion | Run from module directory (already trusted), use signed scripts for enterprise deployment |
| Showing detailed error messages in dashboard | Exposes system paths, usernames, internal network structure | Show friendly message in UI, log detailed error to file, provide "copy diagnostics" button |
| Disabling antivirus without explicit consent | Security risk, enterprise policy violation, audit log flags | Never auto-disable AV - only show instructions, require manual action, verify enterprise policy allows |
| Clearing DISM logs during cleanup | Loses forensic evidence if build fails, can't diagnose issues | Archive old logs instead of deleting, rotate after 10MB or 30 days, compress before archiving |
| Running with unconstrained admin privileges | Build scripts can modify anything, malicious config could exploit | Use least privilege: elevate only specific operations (Hyper-V cmdlets, DISM), drop privileges after |

---

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Auto-refresh dashboard every 5 seconds | Distracting, feels like app is "doing work", interrupts user reading results | Manual refresh button + auto-refresh only on specific triggers (build complete, config change) |
| Showing "Checking..." spinner for >2 seconds | User thinks app is frozen, clicks multiple times, creates duplicate operations | Show individual check progress, estimated time remaining, allow cancel |
| Green checkmark even when Hyper-V "EnablePending" | User trusts green checkmark, starts build, fails, loses trust in dashboard | Use yellow warning icon with "Enabled, reboot required" message |
| All checks same visual weight | User can't prioritize what to fix first, overwhelming when 10 checks fail | Group by severity: Critical (red) first, Warnings (yellow) second, Info (blue) last |
| Remediation happens silently in background | System changes surprise user, no record of what changed, can't undo | Always show "Remediation in progress" modal, log all changes, provide "undo" where possible |
| No "last checked" timestamp | User doesn't know if dashboard is stale, re-runs checks unnecessarily | Show "Last checked: 2 minutes ago" with each check, highlight stale checks (>5 minutes old) |
| Cryptic error messages: "DISM error 0x800704db" | User has no idea what to do, searches Google, finds outdated solutions | Friendly message: "Windows imaging service needs repair. Click 'Fix' to repair automatically." |
| No progress indication during auto-remediation | User thinks app is frozen, task manager shows high CPU, user kills process | Show progress: "Enabling Hyper-V (step 1/3): Installing feature... 45%" |
| Refresh button clears all results | User loses context, has to remember what was wrong, frustrating | Preserve results, only update changed items, highlight what changed since last refresh |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Hyper-V Optional Check:** Dashboard shows green/red, but have you verified it REVALIDATES when user switches hypervisor dropdown? Test: Select HyperV (shows red), switch to VMware (should show "Skipped" or gray), switch back to HyperV (should show red again).

- [ ] **Auto-Remediation:** Remediation shows "Success", but have you checked for PENDING REBOOT state? Test: Auto-enable Hyper-V, verify dashboard detects pending reboot, verify build button disabled, verify reboot prompt shown.

- [ ] **Dashboard Refresh:** Refresh button works, but have you tested refresh DURING ACTIVE BUILD? Test: Start build, click refresh before build completes, verify build doesn't hang, verify refresh is blocked or queued.

- [ ] **Dispatcher Updates:** UI updates from ThreadJob, but are you using BEGINIVOKE for non-critical updates? Test: Run 20 checks, measure total time with Invoke vs BeginInvoke, verify BeginInvoke is ~2x faster.

- [ ] **DISM Operations:** DISM check works in isolation, but have you tested CONCURRENT DISM calls from multiple threads? Test: Start build (uses DISM), immediately refresh dashboard (also uses DISM), verify no hangs, verify mutex prevents conflicts.

- [ ] **Error Messages:** Error shows in UI, but is DETAILED ERROR LOGGED to file? Test: Force check to fail, verify UI shows friendly message, verify log file shows full stack trace and diagnostic data.

- [ ] **Cancellation:** Dashboard has cancel button, but does it STOP IN-FLIGHT CHECKS gracefully? Test: Start long-running check (simulate 30s delay), click cancel after 2s, verify check stops within 1s, verify no orphaned background jobs.

- [ ] **Config Change Validation:** Dashboard updates on config load, but does it REVALIDATE when user edits config in UI? Test: Load config (passes all checks), change config to invalid state (should fail checks), verify dashboard updates without explicit refresh.

- [ ] **Stale Data Indicator:** Dashboard shows results, but does it show WHEN RESULTS COLLECTED? Test: Run checks, wait 10 minutes, verify dashboard shows "Last checked: 10 minutes ago", verify visual indicator for stale data.

- [ ] **Check Dependencies:** Individual checks pass, but have you verified they run in CORRECT ORDER when dependencies exist? Test: ADK check should run before WinPE check (depends on ADK), verify order enforced, verify dependency failure skips dependent checks.

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| UI frozen from Dispatcher.Invoke blocking | MEDIUM | 1. Kill UI process 2. Restart UI 3. Reload last config 4. Re-run checks (audit code for Invoke->BeginInvoke migration) |
| Build hung from DISM lock contention | HIGH | 1. Kill all DISM.exe processes 2. Restart DISM service (`net stop TrustedInstaller; net start TrustedInstaller`) 3. Kill background job 4. Restart UI 5. Add DISM mutex to prevent recurrence |
| Auto-remediation enabled Hyper-V without reboot | LOW | 1. Show reboot prompt 2. Disable build button until reboot 3. Add pending reboot detection 4. Add reboot confirmation dialog |
| Dashboard shows stale data after config change | LOW | 1. Click manual refresh 2. Add config change listener to auto-refresh 3. Add "last checked" timestamp to make staleness visible |
| Hyper-V check shows green but EnablePending | MEDIUM | 1. Manually verify `Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All | select State` 2. Reboot if State=EnablePending 3. Fix check to detect EnablePending state |
| Multiple ThreadJobs hung (cmdlet availability issue) | HIGH | 1. Close UI (stops all ThreadJobs) 2. Wait 30s for cleanup 3. Restart UI 4. Audit code for cmdlet usage (replace with .NET APIs) 5. Run Tests/Unit/FFU.Core.ThreadJobCompatibility.Tests.ps1 |
| Pre-flight check modified system but failed | MEDIUM | 1. Check logs for what was changed 2. Manually revert (e.g., disable Hyper-V if that's what failed) 3. Add transactional pattern (checkpoint before remediation, rollback on failure) |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Dispatcher.Invoke blocking UI | Phase 1: Dashboard Foundation | Measure dashboard refresh time with 20 checks - must complete in <500ms, no UI freezes |
| ThreadJob cmdlet availability | Phase 1: Dashboard Foundation | Run Tests/Unit/FFU.Core.ThreadJobCompatibility.Tests.ps1 - all checks use safe patterns |
| Auto-remediation reboot safety | Phase 2: Auto-Remediation | Test: Enable Hyper-V via auto-remediation, verify build blocked until reboot, verify reboot prompt shown |
| Tightly coupled Hyper-V checks | Phase 3: Optional Hyper-V | Test: Change hypervisor dropdown HyperV->VMware, verify dashboard updates, verify Hyper-V check changes to "Skipped" |
| Dashboard refresh during build | Phase 1: Dashboard Foundation | Test: Start build, click refresh button, verify button disabled OR refresh queued until build completes, verify no hangs |
| DISM lock contention | Phase 1: Dashboard Foundation | Test: Start build (background DISM), run dashboard refresh (foreground DISM), verify mutex prevents hang |
| Stale dashboard data | Phase 1: Dashboard Foundation | Test: Run checks, change config, verify dashboard shows "stale" indicator OR auto-refreshes |
| No pending reboot detection | Phase 2: Auto-Remediation | Test: `Test-PendingReboot` function exists, checks all registry keys, returns true after Hyper-V enable |
| Error messages not actionable | Phase 1: Dashboard Foundation | Review all error messages - must have friendly text in UI AND detailed diagnostic in log file |
| Checks don't revalidate on config change | Phase 3: Optional Hyper-V | Test: Load config, change hypervisor setting, verify checks re-run automatically OR dashboard shows "refresh needed" |

---

## Sources

**WPF Threading and Dispatcher:**
- [PowerShell ProgressBar -- Part 2 – Tiberriver256](https://tiberriver256.github.io/powershell/PowerShellProgress-Pt2/)
- [Using Dispatcher to update values in GUI elements from a background thread - Koskila.net](https://www.koskila.net/using-dispatcher-to-update-values-in-gui-elements-from-a-background-thread/)
- [Threading Model - WPF | Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model)
- [Dispatcher.Invoke Method | Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.windows.threading.dispatcher.invoke?view=windowsdesktop-9.0)

**PowerShell Background Jobs:**
- [Background Jobs - PowerShell | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/background-jobs?view=powershell-7.5)
- [about_Thread_Jobs - PowerShell | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_thread_jobs?view=powershell-7.5)
- [Handling Progress with a Background Job in a GUI Application - SAPIEN](https://info.sapien.com/index.php/guis/gui-scripting/handling-progress-with-a-background-job-in-a-gui-application)
- [PowerShell background jobs unlock scripting performance | TechTarget](https://www.techtarget.com/searchwindowsserver/tutorial/Try-these-PowerShell-Start-Job-examples-for-more-efficiency)

**Auto-Remediation and Safety:**
- [Windows Autopatch: Auto-remediation with PowerShell scripts - Windows IT Pro Blog](https://techcommunity.microsoft.com/blog/windows-itpro-blog/windows-autopatch-auto-remediation-with-powershell-scripts/4228854)
- [Use Remediations to Detect and Fix Support Issues - Microsoft Intune](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/remediations)
- [Automating Reboot Maintenance Using Intune Proactive Remediations](https://azuretothemax.net/2025/04/06/automating-reboot-maintenance-using-intune-proactive-remediations/)
- [CSPM Auto-Remediation in CI/CD: Safe Patterns & Scorecard](https://www.cy5.io/blog/from-alerts-to-action-cspm-automated-remediation/)

**Hyper-V and Virtualization:**
- [System Requirements for Hyper-V on Windows | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/host-hardware-requirements)
- [Install Hyper-V in Windows and Windows Server | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/install-hyper-v)
- [Disable Hyper-V to run virtualization software | Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/windows-client/application-management/virtualization-apps-not-work-with-hyper-v)

**FFUBuilder Codebase (Internal):**
- `FFUDevelopment/BuildFFUVM_UI.ps1` - Existing DispatcherTimer polling pattern (50ms), ThreadJob usage
- `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` - Current pre-flight validation tiers
- `FFUDevelopment/Modules/FFU.Messaging/FFU.Messaging.psm1` - ConcurrentQueue-based messaging (20x faster than file polling)
- `FFUDevelopment/FFU.Common/FFU.Common.Parallel.psm1` - Dispatcher.Invoke usage patterns
- `docs/FIXED_ISSUES_ARCHIVE.md` - v0.0.9-v0.0.12 ThreadJob cmdlet availability fixes, v1.2.7-v1.2.9 module loading fixes

---
*Pitfalls research for: FFU Builder Readiness Dashboard and Optional Hyper-V*
*Researched: 2026-02-05*
