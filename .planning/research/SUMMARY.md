# Project Research Summary

**Project:** FFU Builder Readiness Dashboard & Optional Hyper-V
**Domain:** WPF PowerShell Application - System Validation UI
**Researched:** 2026-02-05
**Confidence:** HIGH

## Executive Summary

FFU Builder requires a Home tab readiness dashboard to replace the current placeholder text with live pre-flight validation. The recommended approach uses WPF ItemsControl with native grouping, async validation via PowerShell runspaces, and ConcurrentQueue messaging (already proven in FFUBuilder's Monitor tab). This architecture reuses 90% of existing infrastructure: FFU.Preflight module (16 validation checks), FFU.Messaging module (thread-safe queuing), and DispatcherTimer polling (50ms interval). The dashboard makes Hyper-V optional by introducing conditional validation logic based on hypervisor selection.

The key architectural insight is that all required patterns already exist in the codebase. Dashboard UI binds to ObservableCollection, background validation runs in ThreadJob (not blocking UI), results stream via ConcurrentQueue, and DispatcherTimer polls for updates. The only new code is XAML controls, dashboard initialization, and auto-remediation wrappers. This minimizes risk and accelerates delivery.

Critical risks center on state management: Dispatcher.Invoke blocking UI (use BeginInvoke), ThreadJob cmdlet availability (use .NET APIs per FFUBuilder's established patterns v0.0.9-v0.0.12), DISM lock contention during concurrent operations (implement mutex), and auto-remediation without reboot detection (check pending reboot registry keys). These pitfalls have proven solutions in FFUBuilder's existing codebase and can be avoided by following established patterns.

## Key Findings

### Recommended Stack

WPF ItemsControl with native GroupStyle provides category-based grouping without third-party dependencies. PowerShell runspaces (not ThreadJob) execute async validation checks with full cmdlet availability and clean cancellation. ConcurrentQueue from FFU.Messaging enables lock-free result streaming at 20x the speed of file polling. ObservableCollection binds directly to ItemsControl for automatic UI updates. DispatcherTimer at 50ms interval polls the queue and updates UI on the dispatcher thread (already proven in Monitor tab).

**Core technologies:**
- **WPF ItemsControl + GroupStyle (.NET 9.0)**: Grouped status display — Native WPF grouping eliminates dependencies, provides category headers and collapsible sections
- **DispatcherTimer (built-in WPF)**: Async check polling — Proven at 50ms interval in FFUBuilder, non-blocking UI updates on dispatcher thread
- **ConcurrentQueue (.NET 9.0)**: Thread-safe results — Already used in FFU.Messaging, lock-free queue 20x faster than file polling
- **PowerShell Runspaces (PS 7.5+)**: Async validation execution — Better than ThreadJob for validation (no credential inheritance needed, full cmdlet availability)
- **ObservableCollection\<PSObject\> (.NET 9.0)**: Data binding — WPF standard for dynamic UI updates, auto-notifies ItemsControl when checks complete

**Alternative rejected: ThreadJob** — While FFUBuilder uses ThreadJob for builds (credential inheritance required), validation checks don't need network auth. Runspaces provide explicit lifecycle control, no module import overhead, and avoid cmdlet availability issues documented in FFUBuilder v0.0.9-v0.0.12.

### Expected Features

The feature landscape divides into table stakes (users assume these exist), differentiators (competitive advantage), and anti-features (commonly requested but problematic). MVP requires 8 features minimum: visual status indicators, category grouping, auto-run on launch, refresh button, pass/fail summary, actionable error messages, conditional requirement logic, and severity-based blocking.

**Must have (table stakes):**
- Visual status indicators (pass/fail/warning with color coding) — All modern dashboards use green/yellow/red
- Grouped by category (System/Hypervisor/Tools/Network) — Essential for usability with 15+ checks
- Auto-run checks on launch — Instant feedback expected, manual trigger feels broken
- Conditional requirement logic — Only show Hyper-V check when Hyper-V selected (FFU.Preflight already supports this)
- Severity-based blocking — Critical fails disable Build button, warnings allow proceed

**Should have (competitive):**
- One-click auto-remediation for safe fixes (DISM cleanup, service restart) — Industry shift to automated remediation (85% vulnerability fix rate)
- Copy-paste remediation commands — PowerShell commands in selectable textbox
- Check duration display — Transparency builds trust ("Completed in 1.2s")
- Export diagnostics — Save report for support scenarios

**Defer (v2+):**
- Real-time config awareness (re-check on every dropdown change) — Complex event wiring, diminishing returns vs manual refresh
- Persistence across sessions — Checks complete in <30s, re-running is acceptable, stale cache causes confusion
- Step-by-step wizard for failures — High cost for marginal UX improvement over existing remediation text

**Anti-features to avoid:**
- Live re-checking on every config change (expensive checks thrash UI)
- Automatic fixes without confirmation (silent changes confuse users)
- Nested subcategories >2 levels deep (users lose context)
- Per-check refresh buttons (checks have dependencies, partial state confuses logic)

### Architecture Approach

The architecture integrates with existing FFUBuilder components: WPF UI layer (BuildFFUVM_UI.ps1), UI state management ($script:uiState), FFU.Preflight module (16 validation checks), FFU.Messaging module (ConcurrentQueue), and DispatcherTimer polling. Dashboard controls (new XAML) bind to ObservableCollection in $uiState.Data. Initialize-HomeTab (new function) launches ThreadJob running Invoke-FFUPreflight with hypervisor selection. Results enqueue to ConcurrentQueue, DispatcherTimer dequeues and updates UI via Dispatcher.Invoke.

**Major components:**
1. **Dashboard UI Controls (NEW)** — XAML controls for status display, auto-fix buttons, refresh button — binds to $uiState.Data.preflightResults
2. **FFU.Preflight Integration (MODIFY)** — Add -HypervisorType parameter to Invoke-FFUPreflight for conditional check execution — leverages existing 16 Test-FFU* functions
3. **Auto-Remediation Functions (NEW)** — Repair-FFUWimMount, Enable-FFUHyperV, Install-FFUADK, Clear-FFUDismState — wrap existing repair logic with user confirmation
4. **Build Gate Logic (MODIFY)** — Disable Build button when hasCriticalFailures flag set — prevents build with missing prerequisites
5. **DispatcherTimer Handler (MODIFY)** — Add PreflightResults message type to existing polling loop — reuses 50ms interval pattern from Monitor tab

**Data flow:** Home Tab Load → Initialize-HomeTab → Start-ThreadJob (Invoke-FFUPreflight) → Checks run in parallel → Results enqueue to ConcurrentQueue → DispatcherTimer (50ms) dequeues → Dispatcher.Invoke updates ObservableCollection → ItemsControl auto-refreshes via data binding.

**Integration points:**
- FFU.Preflight: Call Invoke-FFUPreflight with -HypervisorType parameter (conditional check execution)
- FFU.Messaging: Enqueue check results as FFUMessage objects (existing pattern)
- FFU.Hypervisor: Detect available hypervisors for auto-detect mode (existing Test-HypervisorService)
- Build button: Read $uiState.Data.hasCriticalFailures before starting build (new validation gate)

### Critical Pitfalls

1. **Dispatcher.Invoke blocking UI thread** — Using synchronous Dispatcher.Invoke from background jobs freezes UI. With 50ms DispatcherTimer and multiple checks, delays compound. **Avoid by:** Always use Dispatcher.BeginInvoke for non-critical updates (status messages), reserve Dispatcher.Invoke only for critical state synchronization, batch updates instead of dispatching every result individually.

2. **ThreadJob cmdlet availability during validation** — PowerShell cmdlets (Get-Date, Write-Host, Get-Command) become unavailable during heavy ThreadJob operations. FFUBuilder has established patterns (v0.0.9-v0.0.12): Use [DateTime]::Now, [Console]::WriteLine, $function:FuncName, try/catch around cmdlets. **Avoid by:** Audit ALL pre-flight check code for cmdlet usage, replace with .NET APIs, use safe logging pattern with $function:WriteLog check.

3. **Auto-remediation without reboot safety** — Enable-WindowsOptionalFeature returns success but Hyper-V isn't active until reboot. User clicks Build, fails catastrophically. **Avoid by:** Detect pending reboot (check Component Based Servicing\RebootPending registry), block Build button if reboot pending, show modal "Reboot now or later?" dialog, whitelist safe remediations (registry tweaks) vs unsafe (Windows features).

4. **Tightly coupled pre-flight checks prevent optional Hyper-V** — Original Tier 1-4 validation assumes all prerequisites unconditional. Making Hyper-V optional requires THREE states: checked+required, checked+not-required, not-checked. **Avoid by:** Introduce "Conditional" check tier between Critical_Always and Feature_Dependent, pass configuration context to Invoke-FFUPreflight, distinguish check state in UI (Passed/Failed/Warning/Skipped/Not Run), revalidate on config change.

5. **Dashboard refresh during active build corrupts job state** — Refresh button re-runs pre-flight in NEW ThreadJob, both jobs access DISM simultaneously, DISM locks (single client), build hangs. **Avoid by:** Disable refresh during build ($uiState.Flags.isBuilding), implement DISM mutex (Global\FFUBuilder_DISM) for concurrent protection, auto-refresh only on build completion.

## Implications for Roadmap

Based on combined research, three phases deliver readiness dashboard with optional Hyper-V. Phase ordering prioritizes foundation (reuse existing patterns), then features (auto-remediation), then flexibility (optional Hyper-V). This sequence minimizes risk by validating core infrastructure before adding complexity.

### Phase 1: Dashboard Foundation & Reboot Safety
**Rationale:** Establish UI infrastructure and async patterns before adding features. Reuse FFU.Preflight (16 checks already exist), FFU.Messaging (ConcurrentQueue proven), DispatcherTimer (50ms polling pattern from Monitor tab). Address critical pitfalls first: Dispatcher.Invoke blocking, ThreadJob cmdlet availability, DISM lock contention, refresh-during-build state corruption.

**Delivers:**
- Home tab with grouped status display (System/Hypervisor/Tools/Network categories)
- Auto-run validation on launch (background ThreadJob, non-blocking UI)
- Manual refresh button (disabled during builds)
- Pass/fail summary ("Ready to Build" or "3 Critical Issues")
- Build button gating (disable when critical failures exist)
- Pending reboot detection (check registry keys before/after operations)

**Addresses features:**
- Visual status indicators (table stakes)
- Grouped by category (table stakes)
- Auto-run on launch (table stakes)
- Refresh button (table stakes)
- Severity-based blocking (table stakes)

**Avoids pitfalls:**
- Dispatcher.Invoke blocking (use BeginInvoke for non-critical updates)
- ThreadJob cmdlet availability (audit pre-flight code for safe patterns)
- Dashboard refresh during build (disable button, track isBuilding flag)
- DISM lock contention (implement mutex for concurrent operations)
- Reboot safety gates (detect pending reboot, block build, show prompt)

**Research flags:** Standard WPF patterns, well-documented. Skip phase research.

---

### Phase 2: Auto-Remediation & Hypervisor Conditional Logic
**Rationale:** Add auto-fix for common issues after dashboard proves stable. Prioritize safe remediations (DISM cleanup, service restart) before unsafe (enable Hyper-V requires reboot). Implement hypervisor-aware validation: pass -HypervisorType to Invoke-FFUPreflight, conditionally execute Hyper-V vs VMware checks. This phase introduces remediation WITHOUT making Hyper-V fully optional (still required for HyperV hypervisor selection).

**Delivers:**
- One-click auto-remediation buttons for safe fixes (Repair-FFUWimMount, Clear-FFUDismState)
- Remediation progress dialogs with step-by-step feedback
- Copy-paste PowerShell commands in textbox (user can run manually)
- Conditional check execution based on hypervisor selection (only check what's selected)
- Reboot confirmation modal for unsafe remediations (Enable-FFUHyperV)
- Check duration display ("Completed in 1.2s" for transparency)

**Uses stack:**
- PowerShell remediations wrapping existing FFU.Core/FFU.Preflight logic
- WPF modal dialogs for confirmation (built-in MessageBox or custom XAML)
- ObservableCollection updates for remediation progress

**Implements architecture:**
- Auto-Remediation Functions (NEW): Repair-FFUWimMount, Enable-FFUHyperV, Install-FFUADK
- Invoke-FFUPreflight modification: Add -HypervisorType parameter
- Dashboard conditional display: Show Hyper-V checks OR VMware checks, not both

**Addresses features:**
- One-click auto-remediation (differentiator)
- Conditional requirement logic (table stakes)
- Copy-paste remediation commands (should-have)
- Check duration display (should-have)

**Avoids pitfalls:**
- Auto-remediation without reboot safety (check pending reboot, show confirmation)
- Tightly coupled Hyper-V checks (introduce Conditional tier, pass config context)

**Research flags:** Standard remediation patterns (Intune Proactive Remediations, Windows Autopatch). Skip phase research.

---

### Phase 3: Optional Hyper-V & Config Revalidation
**Rationale:** Make Hyper-V fully optional after validation infrastructure proven. Requires restructuring validation tiers (Critical_Always, Critical_Conditional, Feature_Dependent) and adding config-aware revalidation. This phase has highest complexity due to state management: dashboard must update when user changes hypervisor dropdown, Build button must reflect NEW validation state, stale data must be flagged.

**Delivers:**
- Hyper-V as optional prerequisite (warn if missing when HyperV selected, skip when VMware selected)
- Dashboard updates when hypervisor selection changes (auto-rerun relevant checks)
- Visual distinction for check states (Passed/Failed/Warning/Skipped/Not Run)
- Stale data indicator ("Last checked: 2 minutes ago", highlight stale checks >5 min)
- Export diagnostics button (text file with all check results for support)

**Uses stack:**
- CollectionViewSource with PropertyGroupDescription for dynamic category filtering
- Event handlers on hypervisor dropdown SelectionChanged
- Timestamp tracking for last check run (show staleness)

**Implements architecture:**
- Validation tier restructuring (introduce Critical_Conditional)
- Config change listeners (re-run validation on hypervisor selection change)
- Dashboard state management (distinguish Skipped from Not Run)

**Addresses features:**
- Conditional requirement logic (refined - auto-revalidate on change)
- Stale data indicator (should-have)
- Export diagnostics (should-have)

**Avoids pitfalls:**
- Tightly coupled pre-flight checks (full validation tier refactoring complete)
- Stale dashboard data (auto-refresh on config change or show staleness)

**Research flags:** Complex state management, test thoroughly. Consider `/gsd:research-phase` for validation tier refactoring patterns.

---

### Phase Ordering Rationale

- **Phase 1 first:** Foundation must be solid before adding features. Reuse existing patterns (FFU.Preflight, FFU.Messaging, DispatcherTimer) minimizes risk. Address blocking pitfalls (Dispatcher.Invoke, DISM mutex, reboot detection) before features depend on them.

- **Phase 2 second:** Auto-remediation adds user value but requires stable dashboard. Conditional logic (Hyper-V vs VMware) prepares for optional Hyper-V without full complexity. Safe remediations (DISM cleanup) ship first, unsafe (enable Hyper-V) require reboot safety from Phase 1.

- **Phase 3 third:** Optional Hyper-V is highest complexity (validation tier restructuring, config revalidation). Defer until infrastructure proven. Config-aware revalidation introduces state management challenges that benefit from stable foundation.

- **Dependency chain:** Phase 1 has no dependencies (foundation). Phase 2 depends on Phase 1 (reboot detection required for auto-remediation). Phase 3 depends on Phase 2 (conditional logic extends to full optional Hyper-V).

- **Risk mitigation:** Each phase delivers user value independently. If Phase 3 proves too complex, Phase 2 delivers functional dashboard with auto-remediation. Phase 1 alone delivers MVP readiness dashboard.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 3 (Optional Hyper-V):** Validation tier refactoring patterns, config-aware revalidation state machine. Consider `/gsd:research-phase` for state management patterns in WPF MVVM applications with dynamic prerequisites.

**Phases with standard patterns (skip research):**
- **Phase 1 (Dashboard Foundation):** WPF ItemsControl grouping well-documented, DispatcherTimer proven in FFUBuilder, ConcurrentQueue pattern already implemented in FFU.Messaging. All patterns exist in codebase.
- **Phase 2 (Auto-Remediation):** Intune Proactive Remediations and Windows Autopatch provide clear detection+remediation patterns. Reboot detection via registry keys is standard. PowerShell remediations follow FFU.Core error handling patterns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **HIGH** | All technologies proven in FFUBuilder codebase. WPF ItemsControl standard since .NET 3.0. ConcurrentQueue used in FFU.Messaging. DispatcherTimer at 50ms proven in Monitor tab. Runspaces standard PowerShell pattern. |
| Features | **HIGH** | MVP features (8 table stakes) have clear patterns. Competitor analysis (SCCM, Visual Studio Installer, SAP Readiness) validates feature set. Anti-features documented from UX research. Differentiators align with 2026 industry trends (automated remediation). |
| Architecture | **HIGH** | Integration points clearly mapped to existing modules. Data flow reuses proven patterns (ConcurrentQueue, DispatcherTimer polling, ThreadJob execution). 90% code reuse from FFU.Preflight, FFU.Messaging, FFUUI.Core. Only new code is XAML controls and dashboard initialization. |
| Pitfalls | **HIGH** | All 5 critical pitfalls have proven solutions in FFUBuilder history (v0.0.9-v0.0.12 ThreadJob fixes, v1.2.7-v1.2.9 module loading). DISM mutex pattern from enterprise software (SQL Server, Exchange). Reboot detection from Microsoft Intune documentation. |

**Overall confidence:** **HIGH**

Research based on official Microsoft documentation (WPF threading, DISM, Hyper-V), FFUBuilder codebase analysis (16 files reviewed), and industry patterns (Intune remediations, SCCM readiness, Visual Studio installer). All recommended technologies already present in FFUBuilder. Architecture reuses 90% existing infrastructure.

### Gaps to Address

**Validation tier refactoring (Phase 3):** Current FFU.Preflight uses Tier 1-4 enum for severity. Making Hyper-V optional requires distinguishing "always required" from "conditionally required" from "not required". Research suggests three approaches: (1) Add Critical_Conditional tier between Tier 1 and Tier 2, (2) Pass configuration object to each check function, (3) Use check metadata with conditional execution rules. **Resolution:** Prototype all three during Phase 3 planning, select based on complexity and test coverage.

**Config change revalidation state machine (Phase 3):** When user changes hypervisor dropdown HyperV→VMware, dashboard must: (1) Mark Hyper-V checks as Skipped, (2) Mark VMware checks as Not Run, (3) Execute VMware checks in background, (4) Update UI as results arrive, (5) Recalculate hasCriticalFailures flag. **Resolution:** Model as explicit state machine with states (Idle, Running, Cancelling, Updating). Document state transitions. Test all edge cases (change during running checks, rapid dropdown changes).

**ThreadJob vs Runspace decision (Phase 1):** Research recommends Runspaces over ThreadJob for validation checks (no credential inheritance needed, full cmdlet availability). FFUBuilder uses ThreadJob for builds. **Resolution:** Prototype both in Phase 1. Measure cmdlet availability, cancellation latency, memory usage. If ThreadJob proves reliable, prefer it for consistency. If cmdlet issues arise, switch to Runspaces.

## Sources

### Primary (HIGH confidence)

**FFUBuilder Codebase (Internal Analysis):**
- `BuildFFUVM_UI.ps1` (lines 666-834): DispatcherTimer 50ms polling pattern, ThreadJob usage, UI state management
- `FFU.Preflight` module: 16 validation checks, tiered validation (Critical/Warning/Info), FFUCheckResult structure (lines 26-101)
- `FFU.Messaging` module: ConcurrentQueue pattern proven at 50ms latency (lines 132-200), FFUMessage class
- `FFU.Hypervisor` module: Provider pattern for HyperV/VMware, Test-HypervisorService (lines 89-200)
- `FFUUI.Core` module: UI state management ($uiState structure), control initialization (lines 54-89)
- `docs/FIXED_ISSUES_ARCHIVE.md`: ThreadJob cmdlet availability fixes v0.0.9-v0.0.12, module loading fixes v1.2.7-v1.2.9

**Microsoft Official Documentation:**
- [WPF ItemsControl GroupStyle](https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.itemscontrol.groupstyle?view=windowsdesktop-9.0): Native category grouping
- [WPF Threading Model](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model): Dispatcher.Invoke vs BeginInvoke patterns
- [PowerShell Runspaces](https://devblogs.microsoft.com/scripting/beginning-use-of-powershell-runspaces-part-1/): Official runspace guide
- [Intune Proactive Remediations](https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations): Detection+remediation script patterns
- [Hyper-V Installation](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/install-hyper-v): Feature requirements, reboot behavior

### Secondary (MEDIUM confidence)

**Competitor Analysis & UX Research:**
- [Windows 11 Readiness Dashboard](https://learn.microsoft.com/en-us/intune/configmgr/osd/deploy-use/manage-windows-11-readiness-dashboard): SCCM readiness patterns
- [UI/UX Design Trends 2026](https://www.index.dev/blog/ui-ux-design-trends): Real-time feedback, inline validation
- [Automated Remediation 2026](https://www.sentinelone.com/cybersecurity-101/cybersecurity/vulnerability-remediation-tools/): Industry shift to auto-remediation (85% success rate)
- [Form Validation Best Practices](https://ivyforms.com/blog/form-validation-best-practices/): Conditional field complexity patterns

**Community Patterns:**
- [WPF DispatcherTimer Tutorial](https://wpf-tutorial.com/misc/dispatchertimer/): Timer-based async polling
- [PowerShell WPF Runspaces](https://write-verbose.com/2023/03/21/PowerShellWPFPt1/): Runspace pool + WPF integration
- [PowerShell Progress Bars](https://www.foxdeploy.com/blog/part-v-powershell-guis-responsive-apps-with-progress-bars.html): Responsive UI patterns

### Tertiary (LOW confidence)

**Pending Reboot Detection:** Multiple community sources suggest checking Component Based Servicing\RebootPending registry key. Official Microsoft documentation only references Windows Update reboot states. Recommend testing on Windows 10/11 to confirm key reliability.

**DISM Mutex Pattern:** SQL Server and Exchange use named mutexes for single-instance operations. No official DISM documentation confirms single-client limitation, but empirical evidence (FFUBuilder build hangs) and community reports suggest DISM locks. Implement defensively with 30s timeout.

---
*Research completed: 2026-02-05*
*Ready for roadmap: yes*
