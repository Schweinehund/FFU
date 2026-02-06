# Phase 47: Hypervisor Conditional Logic & Auto-Remediation - Context

**Gathered:** 2026-02-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Hyper-V becomes optional when VMware is selected as the hypervisor. Dashboard conditionally shows/hides hypervisor-specific check categories. Failed pre-flight checks get one-click auto-remediation for safe fixes, reboot confirmation for unsafe fixes, and copy-paste manual commands as fallback. Each check displays its execution duration.

Requirements: HYP-01 through HYP-05 (conditional hypervisor logic), REM-01 through REM-04 (auto-remediation UX).

</domain>

<decisions>
## Implementation Decisions

### Conditional check visibility
- Irrelevant hypervisor category is **fully hidden** (not collapsed or grayed out) — the expander disappears entirely when that hypervisor isn't selected
- An **inline info banner** below the summary shows which hypervisor is active: "Validating for: VMware Workstation" or "Validating for: Hyper-V"
- Hypervisor change detection deferred to Phase 48 — for now, dashboard reflects whatever hypervisor was selected at last check run; user clicks Refresh to update
- Category swap is **instant** — no fade or animation; WPF StackPanel Visibility.Collapsed is sufficient

### One-click fix UX
- Fix button appears **inline next to the failed check** status text — direct, obvious, no extra clicks
- During fix execution: button **transforms into spinner with "Fixing..." text**, button disabled to prevent double-clicks
- After fix completes: **re-runs just that single check** to show new status (not all checks)
- Safe auto-fix scope: **WIMMount service repair, DISM component cleanup, Windows service restarts**
- ADK repair included as safe fix **only if we can reliably detect the specific issue it resolves** — researcher should investigate what ADK failures are detectable

### Reboot confirmation flow
- **Standard WPF MessageBox** with warning icon for reboot-required remediations (e.g., Enable Hyper-V)
- Dialog shows **exact specifics** of what will be changed: "This will run: Enable-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All. A reboot is required to complete."
- App **does NOT auto-reboot** — runs the enable command, then prompts: "Hyper-V enabled. Please reboot to complete."
- If user **cancels** the confirmation dialog: check shows a **"Fix available" indicator** state to distinguish from checks with no fix option

### Manual remediation display
- Failed checks have an **expandable details section** (small "Details" expander) containing a read-only monospace TextBox with the PowerShell command
- Explicit **"Copy" button** next to the textbox — copies command to clipboard, shows brief "Copied!" tooltip
- Check duration shown **inline after status text**: "Passed (1.2s)" or "Failed (0.8s)"
- Checks with both auto-fix AND manual commands show **Fix button as primary** (inline), with manual command available inside the Details expander as fallback

### Claude's Discretion
- Exact WPF styling for Fix button, spinner, and Details expander
- How to detect ADK repair-eligible failures (researcher investigates)
- Spinner implementation approach (WPF animation or text-based)
- "Copied!" tooltip timing and fade behavior
- Duration format precision (1 decimal vs 2 decimals)

</decisions>

<specifics>
## Specific Ideas

- Fix button + status + duration should all fit in the existing check row layout from Phase 46 without requiring a redesign
- "Fix available" indicator for declined fixes should be visually distinct from both pass and fail states (e.g., a different icon or color)
- PowerShell commands in details should be immediately runnable — full command with all parameters, not partial snippets
- Target audience is IT admins building FFU images — they appreciate seeing exactly what's being run

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 47-hypervisor-conditional-logic-auto-remediation*
*Context gathered: 2026-02-06*
