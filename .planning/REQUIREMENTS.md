# Requirements: FFU Builder v1.11.0

**Defined:** 2026-02-05
**Core Value:** Enable rapid, reliable Windows deployment through pre-configured FFU images

## v1.11.0 Requirements

### DISM Resilience

- [x] **DISM-01**: Build pipeline validates DISM service health (Test-DismReady) before all Mount-WindowsImage and Add-WindowsPackage operations ✅
- [x] **DISM-02**: Build pipeline validates DISM functional state (Test-DismFunctional) after each KB install to detect degradation before cascading failures ✅
- [x] **DISM-03**: Build pipeline skips non-critical DISM operations (WinSxS cleanup) when WIMMount service is broken rather than hanging ✅

### Dashboard Foundation

- [ ] **DASH-01**: Home tab displays grouped pre-flight check results organized by category (System, Hypervisor, Build Tools, Network, Optimization)
- [ ] **DASH-02**: Each check displays visual status indicator (pass/fail/warning) with color coding (green/yellow/red)
- [ ] **DASH-03**: Dashboard runs all checks automatically on application launch without blocking the UI
- [ ] **DASH-04**: User can click a Refresh button to re-run all checks (button disabled during active builds)
- [ ] **DASH-05**: Dashboard shows a summary status at top ("Ready to Build" or "3 Critical Issues, 2 Warnings")
- [ ] **DASH-06**: Failed checks display actionable error messages with remediation guidance from FFU.Preflight
- [ ] **DASH-07**: Dashboard shows progress indication while checks are running (indeterminate progress bar with current check name)
- [ ] **DASH-08**: Build button is disabled when any critical check fails; non-critical warnings allow building with a warning dialog

### Hypervisor Conditional Logic

- [ ] **HYP-01**: Hyper-V pre-flight checks only execute when Hyper-V is the selected hypervisor in VM Settings
- [ ] **HYP-02**: VMware pre-flight checks only execute when VMware is the selected hypervisor in VM Settings
- [ ] **HYP-03**: Build is not blocked by missing Hyper-V when VMware is selected as the hypervisor
- [ ] **HYP-04**: Dashboard visually hides irrelevant hypervisor checks (shows only selected hypervisor's category)
- [ ] **HYP-05**: Dashboard displays clear skip message for non-selected hypervisor ("Hyper-V checks skipped — using VMware")

### Auto-Remediation

- [ ] **REM-01**: User can click a one-click fix button for safe issues (WIMMount repair, DISM cleanup, service restart)
- [ ] **REM-02**: Unsafe remediations (e.g., Enable Hyper-V) show a reboot confirmation dialog before executing
- [ ] **REM-03**: Failed checks display copy-paste PowerShell commands in a selectable textbox for manual remediation
- [ ] **REM-04**: Each completed check displays its duration ("Completed in 1.2s") for transparency

### Config-Aware Revalidation

- [ ] **CFG-01**: Dashboard automatically re-runs relevant checks when the hypervisor selection changes in VM Settings
- [ ] **CFG-02**: Dashboard displays a stale data indicator ("Last checked: 2 minutes ago") when results are older than the last config change
- [ ] **CFG-03**: User can export all check results to a diagnostics text file for support scenarios

## Future Requirements

Deferred to v1.12+. Tracked but not in current roadmap.

### Dashboard Enhancements

- **DASH-F01**: Persistence of check results across app sessions (invalidate on config change)
- **DASH-F02**: Step-by-step remediation wizard for complex failures
- **DASH-F03**: Check history / timeline showing changes since last run
- **DASH-F04**: Per-check refresh buttons (individual check re-run)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Live re-checking on every config keystroke | Expensive checks (Hyper-V, ADK) thrash the UI; debounced refresh on hypervisor change is sufficient |
| Automatic fixes without confirmation | Silent changes confuse users; all auto-fix requires user click |
| Nested subcategories (>2 levels) | Users lose context in deep trees; max 2 levels: Category > Checks |
| Real-time monitoring dashboard | Existing log monitoring in Monitor tab is adequate |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DISM-01 | Phase 45 | Complete |
| DISM-02 | Phase 45 | Complete |
| DISM-03 | Phase 45 | Complete |
| DASH-01 | Phase 46 | Pending |
| DASH-02 | Phase 46 | Pending |
| DASH-03 | Phase 46 | Pending |
| DASH-04 | Phase 46 | Pending |
| DASH-05 | Phase 46 | Pending |
| DASH-06 | Phase 46 | Pending |
| DASH-07 | Phase 46 | Pending |
| DASH-08 | Phase 46 | Pending |
| HYP-01 | Phase 47 | Pending |
| HYP-02 | Phase 47 | Pending |
| HYP-03 | Phase 47 | Pending |
| HYP-04 | Phase 47 | Pending |
| HYP-05 | Phase 47 | Pending |
| REM-01 | Phase 47 | Pending |
| REM-02 | Phase 47 | Pending |
| REM-03 | Phase 47 | Pending |
| REM-04 | Phase 47 | Pending |
| CFG-01 | Phase 48 | Pending |
| CFG-02 | Phase 48 | Pending |
| CFG-03 | Phase 48 | Pending |

**Coverage:**
- v1.11.0 requirements: 23 total
- Mapped to phases: 23 (100% coverage ✓)
- Unmapped: 0

---
*Requirements defined: 2026-02-05*
*Last updated: 2026-02-06 — Phase 45 requirements complete*
