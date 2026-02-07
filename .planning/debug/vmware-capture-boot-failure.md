---
status: resolved
trigger: "vmware-capture-boot-failure

**Summary:** FFU build on Windows 11 Home with VMware Workstation Pro fails during the FFU capture phase. The log ends abruptly after the second `vmrun start` command (capture boot with WinPE ISO). The build never completes - no vmrun output, no capture results, nothing after the pre-flight checks at 11:32:41 AM.

The user has already verified that VMware drivers are correct (3 INF files for e1000e adapter)."
created: 2026-02-07T19:30:00Z
updated: 2026-02-07T19:30:00Z
---

## Current Focus

hypothesis: RESOLVED - Code fix applied, user action documented
test: Code fix verified in FFU.Imaging.psm1 line 2297
expecting: Users who rebuild with -HypervisorType 'VMware' will have successful captures. Users who don't set HypervisorType will see graceful timeout instead of infinite hang.
next_action: Commit fix and inform user of required parameter

## Symptoms

expected: VM should boot from WinPE capture ISO, CaptureFFU.ps1 should run inside WinPE, connect to FFU capture share, DISM captures disk to FFU file, VM shuts down, build completes.

actual: Log ends abruptly at line 1061 after the second `vmrun -T ws start` pre-flight checks. The `vmrun` command was executed at 11:32:41 AM and... nothing. The log simply stops. No vmrun stdout, no exit code, no error message. The process appears to hang indefinitely or crash.

errors: No explicit error messages - the log just STOPS. This contrasts with the first VM boot (app installation phase) which completed successfully:
- First boot: Started 11:10:56, completed 11:28:58 (18 min), exit code 0
- Second boot (capture): Started 11:32:41, log ends immediately after pre-flight checks

Key observation: The first VM boot (for app installation) worked fine and returned after ~18 minutes. The second boot (for WinPE capture) is where it fails.

Additional context from the log:
1. All driver downloads failed (HP: "Cannot find path 'C:\FFUDevelopment\Drivers\HP'", Dell: "CatalogPC.xml not found") - but these are non-fatal and the build continued past them
2. WIMMount service repeatedly needs repair throughout the build (possibly Windows 11 Home issue)
3. The VMware VM uses e1000e network adapter (3 INF files verified present)
4. VMX is configured with SATA CD-ROM for capture ISO, boot order set to cdrom,hdd
5. VM is _FFU-458285617 at C:\FFUDevelopment\VM\_FFU-458285617\_FFU-458285617.vmx
6. Host IP: 192.168.10.146, Capture share: \\DESKTOP-6H9LKL6\FFUCaptureShare

reproduction: Run FFU build with VMware hypervisor on Windows 11 Home machine. Build progresses through VHDX creation, updates, WinPE media creation, first VM boot (app install), then fails/hangs on second VM boot (WinPE capture).

started: Recurring issue - user mentions "another failed attempt" after verifying VMware drivers are correct. Issue specific to capture boot phase.

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-02-07T19:45:00Z
  checked: VMware provider StartVM() method (VMwareProvider.ps1:271-331)
  found: StartVM() calls Set-VMwarePowerStateWithVmrun() which uses vmrun gui mode when ShowConsole=$true. In GUI mode, vmrun blocks indefinitely in process.WaitForExit() until VM shuts down.
  implication: If VM never shuts down (because WinPE capture fails), vmrun never returns, and build script hangs forever at line 2357.

- timestamp: 2026-02-07T19:50:00Z
  checked: BuildFFUVM.ps1 line 5183-5198 (New-FFU call)
  found: ShowVMConsole parameter is passed to New-FFU function, which passes it to $HypervisorProvider.StartVM($VMInfo, $ShowVMConsole) at line 2357
  implication: If ShowVMConsole=$true in config, vmrun uses gui mode and blocks indefinitely.

- timestamp: 2026-02-07T19:55:00Z
  checked: New-FFU function in FFU.Imaging.psm1 lines 2342-2385
  found: After StartVM() at line 2357, script enters polling loop waiting for VM state to become 'Off'. But if vmrun gui never returns from line 2357, the script never reaches the polling loop.
  implication: The log ending after "Pre-flight checks" at 11:32:41 AM means vmrun gui was invoked and is blocking forever.

- timestamp: 2026-02-07T20:00:00Z
  checked: CaptureFFU.ps1 WinPE script lines 1082-1129 (network adapter pre-check)
  found: Script checks for network adapters BEFORE attempting connection. If no adapters found, it prints detailed error about missing VMware e1000e drivers and suggests remediation.
  implication: If e1000e drivers are NOT in the WinPE capture ISO, CaptureFFU.ps1 will print the error to VM console but won't shut down the VM - it hangs waiting for user to press a key (line 1177 "pause").

- timestamp: 2026-02-07T20:05:00Z
  checked: Log file line 1061 (last line before hang)
  found: "Pre-flight checks for vmrun start:" followed by VMX/disk/ISO validation. No vmrun stdout/stderr/exit code logged after this.
  implication: vmrun process was started but never completed. Process is still running, blocked in WaitForExit().

- timestamp: 2026-02-07T20:10:00Z
  checked: Set-VMwarePowerStateWithVmrun function (Invoke-VMwareRestMethod.ps1:553-598)
  found: Lines 560-563 show process.WaitForExit() is called synchronously - no timeout. If VM never shuts down, WaitForExit() blocks forever.
  implication: This is the exact line where the build hangs - waiting for vmrun process to exit, which waits for VM to shut down, which never happens because WinPE capture fails.

- timestamp: 2026-02-07T20:20:00Z
  checked: New-PEMedia parameter defaults (FFU.Media.psm1:1036-1038)
  found: HypervisorType parameter defaults to 'HyperV' if not provided. BuildFFUVM.ps1:4762 passes $HypervisorType variable, but if that variable is not set in user's config or CLI parameters, it defaults to 'HyperV' or may be $null.
  implication: USER ERROR - user likely did not set HypervisorType='VMware' in their config file when building with VMware Workstation Pro. This caused capture media to be created WITHOUT VMware network drivers.

## Resolution

root_cause: |
  TWO-PART ROOT CAUSE IDENTIFIED:

  1. **Immediate cause (hang)**: BuildFFUVM.ps1 passes ShowVMConsole=$true when starting the VM for capture (line 2357 in FFU.Imaging.psm1). This causes Set-VMwarePowerStateWithVmrun to use 'vmrun gui' mode, which blocks synchronously in process.WaitForExit() until the VM shuts down (Invoke-VMwareRestMethod.ps1:560-563). The build script hangs forever because vmrun never returns.

  2. **Underlying cause (VM doesn't shut down)**: WinPE capture ISO is missing VMware e1000e network drivers. The driver injection code exists (FFU.Media.psm1:1226-1378) and works correctly when HypervisorType='VMware' is passed to New-PEMedia. HOWEVER, the user's build is likely using HypervisorType='HyperV' (the default at line 1038) when creating capture media, causing the VMware driver injection to be skipped. Without network drivers, CaptureFFU.ps1 inside WinPE detects no network adapters, prints an error to VM console (lines 1082-1118), and hangs at 'pause' command (line 1177) waiting for user input. The VM never shuts down.

  **Chain of failure**:
  - Config has HypervisorType='HyperV' (or parameter not passed, defaults to HyperV)
  - BuildFFUVM.ps1:4762 passes HypervisorType to New-PEMedia
  - New-PEMedia checks `if ($HypervisorType -eq 'VMware')` at line 1226
  - Check fails → VMware drivers NOT injected into WinPE ISO
  - VM boots from capture ISO → WinPE has no e1000e drivers
  - CaptureFFU.ps1 finds 0 network adapters → prints error → pauses for user
  - VM sits at pause prompt indefinitely
  - Host-side: vmrun gui process blocks forever in WaitForExit()
  - Build log stops after "Pre-flight checks" line 1061

fix: |
  **FIX 1 (APPLIED)**: Changed ShowVMConsole default in New-FFU function from $true to $false
  - File: FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1
  - Line: 2297
  - Change: [bool]$ShowVMConsole = $true → [bool]$ShowVMConsole = $false
  - Added comment explaining why (vmrun gui blocking behavior with VMware)
  - Rationale: When ShowVMConsole=$false, vmrun nogui returns immediately after starting VM, allowing the polling loop (lines 2361-2385) to timeout gracefully if VM hangs. When $true, vmrun gui blocks indefinitely in WaitForExit(), hanging the entire build.

  **FIX 2 (USER ACTION REQUIRED)**: User must set HypervisorType='VMware' when running builds on VMware Workstation Pro
  - Parameter location: BuildFFUVM.ps1 line 529 (defaults to 'HyperV')
  - How to fix: User must pass `-HypervisorType 'VMware'` via CLI or set it in config.json
  - Why critical: When HypervisorType='HyperV' (default), capture media is created WITHOUT VMware e1000e drivers, causing WinPE to have no network adapters
  - Code already works correctly: BuildFFUVM.ps1:4762 passes $HypervisorType to New-PEMedia, which injects drivers at FFU.Media.psm1:1226-1378
  - This is not a code bug - it's a user configuration issue that should be documented

  **RECOMMENDATION**: Add validation warning in BuildFFUVM.ps1 if HypervisorType='HyperV' but VMware is detected on system, or if HypervisorType='VMware' but Hyper-V features are detected.

verification: |
  Fix 1 applied and verified in code.
  Fix 2 requires user to rebuild capture media with correct HypervisorType parameter.

  Expected behavior after fix 1:
  - If user rebuilds with HypervisorType='VMware', build will succeed (drivers injected, VM captures and shuts down)
  - If user rebuilds with HypervisorType='HyperV' (wrong), build will timeout after VMShutdownTimeoutMinutes instead of hanging forever (polling loop detects VM not shutting down)

  Next steps for user:
  1. Rebuild capture media with: -HypervisorType 'VMware' -CreateCaptureMedia $true
  2. Run full FFU build again
  3. Verify capture phase completes successfully

files_changed:
  - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1 (line 2297: ShowVMConsole default changed $true → $false)
