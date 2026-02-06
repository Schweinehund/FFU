# Feature Research: Readiness Dashboard for FFU Builder

**Domain:** System Readiness Dashboard / Pre-flight Validation UI
**Researched:** 2026-02-05
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Visual status indicators (pass/fail/warning) | All modern dashboards use color-coded status (green/yellow/red) | LOW | Existing FFU.Preflight returns Status enum - map to colors |
| Grouped by category | Users expect logical organization (System, Hypervisor, Storage, etc.) | LOW | FFU.Preflight has Tier 1-4 - reorganize by domain |
| Auto-run checks on launch | Users expect instant feedback, not manual trigger | MEDIUM | Home tab OnLoaded event triggers check orchestration |
| Refresh button | Standard pattern for re-validating after user fixes issues | LOW | Single button to re-run Invoke-FFUPreflight |
| Clear pass/fail summary | "3 Critical Issues, 2 Warnings" at top before drilling down | LOW | Aggregate check results into counts |
| Actionable error messages | Modern UX: "Email should include @" not just "Invalid email" | LOW | FFU.Preflight already provides remediation text |
| Progress indication | Users know checks are running, not frozen UI | MEDIUM | DispatcherTimer polling background job with progress bar |
| Expandable details | Click category to see individual check results | MEDIUM | WPF Expander or TreeView for grouped checks |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| One-click auto-remediation | Fix safe issues automatically (e.g., restart DISM service) | MEDIUM | FFU.Preflight already has remediation logic - wrap in UI action |
| Conditional requirement logic | Only show Hyper-V check when Hyper-V hypervisor selected | MEDIUM | Config-aware validation - already in Invoke-FFUPreflight |
| Real-time config awareness | Dashboard updates when user changes VM Settings tab | HIGH | Subscribe to config change events, re-run affected checks |
| Severity-based blocking | Critical fails block build, warnings show with proceed option | LOW | FFU.Preflight Severity field - use for build button enablement |
| Step-by-step remediation guidance | Not just "install ADK" but "1. Download from X, 2. Run installer, 3. Verify" | LOW | FFU.Preflight New-FFURemediationBlock already provides this |
| Check duration display | Show "HyperV check: 1.2s" for transparency | LOW | FFU.Preflight returns DurationMs - display in UI |
| Copy-paste remediation commands | PowerShell commands in selectable textbox, not plain text | LOW | TextBox with IsReadOnly for PowerShell command blocks |
| Persistence across sessions | Remember last check results until config changes or user refreshes | MEDIUM | Cache results in memory, invalidate on config change |
| Export diagnostics | "Save report" button creates text file with all check results | LOW | Serialize check results to text file with timestamp |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Live re-checking on every config change | Feels responsive and instant | Expensive checks (Hyper-V, ADK) thrash the UI, checks run faster than user types | Debounced check (wait 2s after last change) OR manual refresh only |
| Automatic fixes without confirmation | "Just fix everything for me" | Silent changes confuse users ("why did my settings change?"), risky operations (restart services) need consent | Show "Auto-fix Available" button with preview of changes |
| Nested subcategories (>2 levels deep) | Organize 20+ checks granularly | Users lose context in deep trees, harder to spot critical issues | Max 2 levels: Category → Checks (System → Admin Rights, PowerShell 7, etc.) |
| Per-check refresh buttons | "Let me re-run just this one check" | Checks have dependencies (ADK check needs Admin check first), partial state confuses logic | Single "Refresh All" button only |
| Estimated time remaining | "Checks will take ~30 seconds" | Highly variable (network checks timeout after 10s or succeed in 100ms), wrong estimates worse than no estimate | Indeterminate progress bar with "Running checks..." |
| Inline fix buttons next to each check | Feels convenient | Clutters UI, users click without reading, inconsistent (some checks can't auto-fix) | Single "Fix Issues" button at category level for fixable items |
| Check history / timeline | "Show me what changed since last check" | Adds complexity, users don't care about history - they care about current state | Current state only, with timestamp of last check |

## Feature Dependencies

```
[Visual Status Display]
    └──requires──> [Check Execution Engine]
                       └──requires──> [FFU.Preflight Module] (already exists)

[Grouped Categories]
    └──requires──> [Check Result Aggregation]
    └──enhances──> [Visual Status Display]

[Auto-run on Launch]
    └──requires──> [Background Job Pattern] (already exists in Monitor tab)

[Conditional Requirement Logic]
    └──requires──> [Config File Awareness] (already exists)
    └──requires──> [Hypervisor Type Detection] (already exists in FFU.Hypervisor)

[Auto-remediation]
    └──requires──> [Check Execution Engine]
    └──requires──> [User Confirmation Dialog]
    └──conflicts──> [Non-elevated context] (some fixes need admin)

[Build Button Blocking]
    └──requires──> [Severity-based Validation]
    └──requires──> [Check Result State Management]
```

### Dependency Notes

- **Auto-run requires Background Job Pattern:** Checks can take 10-30 seconds (network timeout, Hyper-V detection). Must not block UI thread. BuildFFUVM_UI.ps1 already has ThreadJob pattern for builds - reuse for preflight checks.
- **Conditional Logic requires Config Awareness:** Dashboard must read config.json to determine which checks are relevant (e.g., skip Hyper-V check if VMware selected).
- **Auto-remediation requires Admin:** Some fixes (restart WIMMount service, enable Hyper-V feature) require elevation. UI must detect if running elevated and show appropriate guidance.
- **Grouped Categories enhance Visual Status:** Category-level rollup (e.g., "System: 3/3 passed") provides scannable overview before expanding details.

## MVP Definition

### Launch With (v1 - Readiness Dashboard MVP)

Minimum viable product — what's needed to validate the concept.

- [x] **Visual status indicators (pass/fail/warning)** — Core feedback mechanism, users must see at-a-glance status
- [x] **Grouped by category** — Logical organization prevents overwhelming users with 15+ flat checks
- [x] **Auto-run checks on launch** — Instant feedback is expected, manual trigger feels broken
- [x] **Refresh button** — Users need to re-validate after fixing issues
- [x] **Clear pass/fail summary** — "Ready to Build" vs "3 Critical Issues" at top
- [x] **Actionable error messages** — Leverage FFU.Preflight remediation text
- [x] **Conditional requirement logic** — Don't show Hyper-V check when VMware selected (already in FFU.Preflight)
- [x] **Severity-based blocking** — Critical fails disable Build button, warnings allow proceed

**Why these 8 features:** This is the minimum feature set for a functional readiness dashboard. Without visual status + categories + auto-run, it's not really a "dashboard" - it's a hidden validation that users won't discover. Without conditional logic, VMware users see irrelevant Hyper-V errors. Without severity blocking, the dashboard is informational but powerless.

### Add After Validation (v1.1+)

Features to add once core is working and validated with real users.

- [ ] **Progress indication** — Add when users report "is it frozen?" confusion
- [ ] **Expandable details** — Add when users need to see individual check messages (MVP shows category rollup only)
- [ ] **One-click auto-remediation** — Add when we identify which checks are safe to auto-fix (start with DISM cleanup)
- [ ] **Copy-paste remediation commands** — Add when users request easier command copying
- [ ] **Check duration display** — Nice-to-have for transparency, not critical
- [ ] **Export diagnostics** — Add when users need to share check results (support scenarios)

**Trigger for adding:**
- Progress indication: After 3+ user reports of "stuck" confusion
- Expandable details: When category-level messages prove insufficient for troubleshooting
- Auto-remediation: After 2 weeks of monitoring which remediations users actually run manually

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Real-time config awareness** — Complex event wiring, diminishing returns (manual refresh sufficient)
- [ ] **Persistence across sessions** — Adds state management complexity, checks are fast enough to re-run
- [ ] **Step-by-step wizard for failures** — High complexity, remediation text already provides steps

**Why defer:**
- Real-time config awareness: The Home tab is a "check once, then switch to other tabs" workflow, not a live monitor. Refresh button is simpler and sufficient.
- Persistence: Checks complete in <30s, re-running on app restart is acceptable. Stale cached results cause confusion ("I fixed it, why is it still red?").
- Wizard for failures: High development cost for marginal UX improvement over existing remediation text.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority | Rationale |
|---------|------------|---------------------|----------|-----------|
| Visual status indicators | HIGH | LOW | P1 | Core dashboard requirement, simple color mapping |
| Grouped by category | HIGH | LOW | P1 | Essential for usability with 15+ checks |
| Auto-run on launch | HIGH | MEDIUM | P1 | Expected behavior, leverages existing ThreadJob pattern |
| Conditional requirement logic | HIGH | LOW | P1 | Already in FFU.Preflight, just expose in UI |
| Severity-based blocking | HIGH | LOW | P1 | Core validation gate, simple boolean logic |
| Refresh button | MEDIUM | LOW | P1 | Standard pattern, users expect it |
| Clear pass/fail summary | HIGH | LOW | P1 | First thing users see, sets context |
| Actionable error messages | HIGH | LOW | P1 | FFU.Preflight provides this, just display it |
| Progress indication | MEDIUM | MEDIUM | P2 | Improves perceived performance, not critical |
| Expandable details | MEDIUM | MEDIUM | P2 | Useful for troubleshooting, not needed for overview |
| One-click auto-remediation | MEDIUM | MEDIUM | P2 | Nice-to-have, but risky without careful testing |
| Copy-paste commands | LOW | LOW | P2 | Convenience feature, not blocking |
| Check duration display | LOW | LOW | P3 | Transparency nice-to-have |
| Export diagnostics | LOW | LOW | P3 | Support scenario, not daily use |
| Real-time config awareness | MEDIUM | HIGH | P3 | Complex, diminishing returns vs manual refresh |
| Persistence across sessions | LOW | MEDIUM | P3 | Checks are fast, re-running is acceptable |

**Priority key:**
- P1: Must have for launch (MVP)
- P2: Should have, add when possible (v1.1)
- P3: Nice to have, future consideration (v2+)

## Grouped Category Structure

Based on FFU.Preflight module and readiness dashboard best practices, organize checks into these categories:

### Category 1: System Requirements (Always Run)
**Purpose:** Validate baseline environment before anything else
**Checks:**
- Administrator Rights (Test-FFUAdministrator) - CRITICAL
- PowerShell 7+ (Test-FFUPowerShellVersion) - CRITICAL
- Disk Space (Test-FFUDiskSpace) - CRITICAL
- Scratch Space (Test-FFUScratchSpace) - CRITICAL

**UI Behavior:**
- Always visible, never collapsed
- First category to run (fail-fast if basics missing)
- Red header if any check fails

### Category 2: Hypervisor (Conditional)
**Purpose:** Validate virtualization platform (conditional on hypervisor type)
**Checks:**
- Hyper-V Feature (Test-FFUHyperV) - CRITICAL when HypervisorType=HyperV
- Hyper-V Switch Conflict (Test-FFUHyperVSwitchConflict) - CRITICAL when HypervisorType=VMware
- VMware vmxtoolkit (Test-FFUVmxToolkit) - WARNING when HypervisorType=VMware
- VMware Drivers (Test-FFUVMwareDrivers) - INFO when HypervisorType=VMware
- VMware Bridge Config (Test-FFUVMwareBridgeConfiguration) - WARNING when HypervisorType=VMware
- VM Resources (Test-FFUVMResources) - CRITICAL when CreateVM=true
- VM Host IP Address (Test-FFUHostIPAddress) - WARNING when HypervisorType=VMware and InstallApps=true

**UI Behavior:**
- Show/hide based on config.json HypervisorType
- Hyper-V users see Hyper-V checks only
- VMware users see VMware checks + Hyper-V conflict check

### Category 3: Build Tools (Always Run)
**Purpose:** Validate required tools for FFU creation
**Checks:**
- Windows ADK (Test-FFUADK) - CRITICAL
- WIMMount Service (Test-FFUWimMount) - CRITICAL
- DISM State (Test-FFUDISMState) - CRITICAL

**UI Behavior:**
- Always visible
- Run after System Requirements pass (dependencies)
- Each check has auto-remediation option

### Category 4: Network & Updates (Conditional)
**Purpose:** Validate connectivity for downloads
**Checks:**
- Network Connectivity (Test-FFUNetwork) - CRITICAL when DownloadDrivers=true OR DownloadUpdates=true
- Apps.iso Disk Space (Test-FFUAppsISODiskSpace) - CRITICAL when InstallApps=true
- Capture Disk Space (Test-FFUCaptureDiskSpace) - CRITICAL

**UI Behavior:**
- Show when any download feature enabled
- Skip if fully offline build

### Category 5: Configuration (Conditional)
**Purpose:** Validate config file if provided
**Checks:**
- Config File Validation (Test-FFUConfigurationFile) - CRITICAL when ConfigFile parameter provided

**UI Behavior:**
- Only show if config file path provided
- Hidden for UI-only usage (no ConfigFile parameter)

### Category 6: Optimization (Non-blocking)
**Purpose:** Warnings that don't prevent build but may impact performance
**Checks:**
- Antivirus Exclusions (Test-FFUAntivirusExclusions) - WARNING
- DISM Cleanup Available (Invoke-FFUDISMCleanup check) - INFO

**UI Behavior:**
- Always last category
- Yellow/amber color (warnings, not errors)
- "Recommended but not required" header text

## Competitor Feature Analysis

| Feature | Windows 11 Readiness (SCCM) | Visual Studio Installer | SAP Readiness Check | Our Approach |
|---------|------------------------------|-------------------------|----------------------|--------------|
| Grouped status checks | ✅ Hardware/Software/Apps | ✅ Workloads/Components | ✅ Functional Areas | ✅ System/Hypervisor/Tools/Network/Config/Optimization |
| Auto-run on launch | ✅ Auto-scans devices | ✅ Pre-install checks | ✅ Initial assessment | ✅ Home tab OnLoaded event |
| Conditional checks | ✅ Edition-specific rules | ✅ Workload dependencies | ✅ Module dependencies | ✅ Hypervisor-specific, feature-gated |
| Auto-remediation | ❌ Manual only | ⚠️ Some components | ⚠️ Limited scope | ✅ Safe fixes (DISM cleanup, service restart) |
| Severity levels | ✅ Compatible/Upgrade/Incompatible | ✅ Required/Recommended | ✅ Critical/Warning/Info | ✅ Critical/Warning/Info (FFU.Preflight Severity) |
| Copy-paste commands | ❌ UI-driven only | ❌ GUI installer | ✅ SQL scripts provided | ✅ PowerShell commands in textbox |
| Export results | ✅ CSV/Excel | ❌ No export | ✅ PDF report | ✅ Text file export (v1.1) |
| Progress indication | ✅ Scanning... | ✅ Checking prerequisites | ✅ Step X of Y | ✅ Indeterminate progress bar |

**Key Differentiators from Competitors:**
1. **One-click auto-remediation:** Most tools show errors but don't fix them. We fix safe issues automatically (DISM cleanup, service restart, WIMMount repair).
2. **Conditional hypervisor checks:** VS Installer and SAP don't handle multi-platform scenarios. We show Hyper-V OR VMware checks, not both.
3. **Copy-paste PowerShell commands:** SAP provides SQL scripts, but installers don't. We provide ready-to-run PowerShell in selectable textbox.

## Real-World UX Patterns (2026)

Based on web research, modern readiness dashboards follow these patterns:

### Pattern 1: Real-Time Feedback (Not Just On-Submit)
**Source:** [UI Design Trends 2026](https://www.index.dev/blog/ui-ux-design-trends), [Inline Validation UX](https://www.smashingmagazine.com/2022/09/inline-validation-web-forms-ux/)

> "Input validation in 2026 emphasizes real-time feedback (not just on submit), inline error messages (next to field), and constructive suggestions (not just 'invalid')."

**Application to FFU Builder:**
- Show check status as checks run (not all at end)
- Display remediation steps inline with failed check (not in separate dialog)
- Use constructive language: "ADK not found at C:\Program Files\Windows Kits\10. Install from https://..." not just "ADK missing"

### Pattern 2: Automated Remediation as Industry Shift
**Source:** [Automated Remediation 2026 Trends](https://www.sentinelone.com/cybersecurity-101/cybersecurity/vulnerability-remediation-tools/), [Remediation Automation](https://www.kusari.dev/learning-center/remediation-automation)

> "In 2026, teams are rethinking the idea that automatic remediation is too risky to implement, as manual remediation proves unsustainable... AI engines successfully generating accurate code patches for 85% of standard OWASP vulnerabilities."

> "Organizations can create dashboards and reporting that give security leaders visibility into remediation automation effectiveness, tracking metrics like percentage of vulnerabilities resolved automatically, time-to-remediation improvements, and issues caused by automated fixes."

**Application to FFU Builder:**
- Start with safe auto-fixes: DISM cleanup (Invoke-FFUDISMCleanup already exists)
- Track remediation success: "WIMMount repaired in 2.3s" in details
- Progressive enhancement: Add more auto-fixes as confidence grows (v1.1: restart services, v1.2: enable Hyper-V)

### Pattern 3: Progress Transparency
**Source:** [Mobile UX Patterns 2026](https://www.sanjaydey.com/mobile-ux-ui-design-patterns-2026-data-backed/)

> "When an app is processing, designers should show this status—users are fine with waiting as long as they know they're not waiting in vain, using spinners, progress bars, and skeleton screens to reduce uncertainty and build trust."

**Application to FFU Builder:**
- Indeterminate progress bar during checks (not frozen UI)
- Current check name displayed: "Checking Hyper-V feature..."
- Check duration in results: "Completed in 1.2s" builds trust

### Pattern 4: Wizard-Style Multi-Step Validation
**Source:** [Fintech Design Patterns 2026](https://www.eleken.co/blog-posts/modern-fintech-design-guide)

> "A common pattern replaces long forms with wizard-style onboarding, breaking it into small steps with clear progress indicators, guiding users screen by screen rather than asking for everything at once."

**Application to FFU Builder:**
- NOT applicable - our dashboard is a status overview, not a wizard
- BUT: Remediation guidance uses step-by-step format (already in FFU.Preflight New-FFURemediationBlock)
- Category expansion provides progressive disclosure without wizard complexity

### Pattern 5: Conditional Field Complexity
**Source:** [Form Validation Best Practices 2026](https://ivyforms.com/blog/form-validation-best-practices/)

> "Making conditional validation work in complex forms requires validation logic that might be difficult to maintain if some fields have dependencies or show up only in certain conditions."

**Application to FFU Builder:**
- Conditional checks already implemented in FFU.Preflight Invoke-FFUPreflight
- UI must reflect same logic: Hide Hyper-V category when HypervisorType=VMware
- Use clear skip messages: "Hyper-V checks skipped (using VMware hypervisor)"

## Sources

### Readiness Dashboard Patterns
- [Dashboard Readiness Assessment | Demand Metric](https://www.demandmetric.com/content/dashboard-readiness-assessment)
- [The 2026 IT Readiness Checklist | Bay Computing](https://baymcp.com/the-2026-it-readiness-checklist-from-legacy-systems-to-future-ready-operations/)
- [Continuous Compliance Dashboard Approach | AuditBoard](https://auditboard.com/blog/iso-27001-compliance-software-for-continuous-compliance)
- [Manage Windows 11 Readiness Dashboard | Microsoft Learn](https://learn.microsoft.com/en-us/intune/configmgr/osd/deploy-use/manage-windows-11-readiness-dashboard)
- [Kubernetes Node Readiness Controller 2026](https://kubernetes.io/blog/2026/02/03/introducing-node-readiness-controller/)
- [SAP Solution Readiness Dashboard | CoreALM](https://corealm.com/solution-readiness-dashboard-helping-your-it-projects/)

### Pre-flight Validation UX
- [UI Design Trends 2026 | Landdding](https://landdding.com/blog/ui-design-trends-2026)
- [12 UI/UX Design Trends 2026 (Data-Backed) | Index.dev](https://www.index.dev/blog/ui-ux-design-trends)
- [7 Mobile UX/UI Design Patterns 2026](https://www.sanjaydey.com/mobile-ux-ui-design-patterns-2026-data-backed/)
- [Fintech Design Guide 2026 | Eleken](https://www.eleken.co/blog-posts/modern-fintech-design-guide)
- [Form Validation Best Practices | IvyForms](https://ivyforms.com/blog/form-validation-best-practices/)
- [Inline Validation UX | Smashing Magazine](https://www.smashingmagazine.com/2022/09/inline-validation-web-forms-ux/)

### Automated Remediation Trends
- [9 Vulnerability Remediation Tools 2026 | SentinelOne](https://www.sentinelone.com/cybersecurity-101/cybersecurity/vulnerability-remediation-tools/)
- [Automated Remediation for Data Security | Sentra](https://www.sentra.io/blog/how-automated-remediation-enables-proactive-data-protection-at-scale)
- [What is Remediation Automation? | Kusari](https://www.kusari.dev/learning-center/remediation-automation)
- [Cybersecurity Predictions 2026 | Security Boulevard](https://securityboulevard.com/2026/01/cybersecurity-snapshot-predictions-for-2026-ai-attack-acceleration-automated-remediation-custom-made-ai-security-tools-machine-identity-threats-and-more/)

### Windows Installer Patterns
- [Prerequisites Page | Advanced Installer](https://www.advancedinstaller.com/user-guide/prerequisites.html)
- [Application Deployment Prerequisites | Visual Studio | Microsoft Learn](https://learn.microsoft.com/en-us/visualstudio/deployment/application-deployment-prerequisites?view=visualstudio)
- [Prerequisites Dialog Box | Visual Studio | Microsoft Learn](https://learn.microsoft.com/en-us/visualstudio/ide/reference/prerequisites-dialog-box?view=vs-2022)

---
*Feature research for: FFU Builder Readiness Dashboard*
*Researched: 2026-02-05*
*Confidence: HIGH*
