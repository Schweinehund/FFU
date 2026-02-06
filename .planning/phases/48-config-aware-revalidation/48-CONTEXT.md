# Phase 48: Config-Aware Revalidation - Context

**Gathered:** 2026-02-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Dashboard automatically re-runs relevant checks when the hypervisor selection changes, displays a stale data indicator when results are outdated, and provides a diagnostics export capability for support scenarios. This phase builds on Phase 47's hypervisor conditional logic and dashboard remediation infrastructure.

</domain>

<decisions>
## Implementation Decisions

### Revalidation Trigger
- Fire immediately when hypervisor dropdown value changes — no debounce, no manual step
- Only the hypervisor dropdown triggers revalidation (other VM Settings changes do not)
- Re-run scope: hypervisor category checks PLUS any checks that depend on the hypervisor selection
- If revalidation is already in progress and user changes hypervisor again: cancel current run and restart with new selection

### Staleness Display
- Stale indicator appears in the summary banner area at top of dashboard
- Results become stale ONLY on config change (hypervisor selection changed after last check) — no time-based staleness
- Visual: amber/orange banner with text like "Results may be outdated — hypervisor changed since last check (2 min ago)"
- Banner is informational only — no inline re-run action (Refresh button handles that, and auto-revalidation should cover most cases)

### Diagnostics Export
- Triggered via an "Export Diagnostics" button on the dashboard, near the Refresh button
- Button grayed out if no check results exist yet
- Output format: plain text (.txt) file — universally readable, easy to paste into emails/tickets
- Save location: FFUDevelopment\Logs folder with timestamp filename (e.g., FFU-Diagnostics-2026-02-06.txt) — no Save As dialog
- System info included: essential context only — OS version, PowerShell version, FFU Builder version, selected hypervisor, installed hypervisor versions, ADK version, available disk space
- Also includes: all check results with pass/fail/warning status, timestamps, remediation actions taken during the session

### Transition Behavior
- During revalidation: keep all results visible, dim/gray-out the categories being re-checked
- Non-affected categories stay fully visible and interactive
- Progress bar reappears during revalidation (same indeterminate bar with check name as initial launch) — consistent UX
- Summary banner stays in current state (or shows "Rechecking...") until ALL affected checks complete, then updates with final counts — no incremental count bouncing
- Build button disabled during revalidation (same as initial check run), re-enables with appropriate state once revalidation completes

### Claude's Discretion
- Exact implementation of cancel-and-restart mechanism for in-progress revalidation
- How to identify which checks are "dependent on hypervisor selection" vs independent
- Dimming opacity level and visual treatment for affected categories
- Exact diagnostics file content structure and section ordering
- How "Rechecking..." state is shown in the banner

</decisions>

<specifics>
## Specific Ideas

- Revalidation should feel seamless — user switches hypervisor and the dashboard just updates naturally
- Diagnostics export is a support-scenario feature — optimized for readability by IT support, not machine parsing
- Stale banner uses amber to stay consistent with the existing green/yellow/red color scheme (amber = attention needed, not critical)
- All recommendations chosen for this phase prioritize consistency with existing Phase 46/47 patterns over introducing new UI paradigms

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 48-config-aware-revalidation*
*Context gathered: 2026-02-06*
