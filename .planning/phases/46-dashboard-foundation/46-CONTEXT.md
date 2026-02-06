# Phase 46: Dashboard Foundation - Context

**Gathered:** 2026-02-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Transform the Home tab from placeholder text into a live pre-flight readiness dashboard. Users see grouped checks with visual status indicators, auto-running on launch without blocking the UI. Summary banner shows overall readiness. Build button gated on critical failures.

Phase 47 handles hypervisor-conditional logic and auto-remediation buttons. Phase 48 handles config-aware revalidation and staleness detection. This phase builds the dashboard infrastructure and visual presentation only.

</domain>

<decisions>
## Implementation Decisions

### Check layout & grouping
- Expandable categories: grouped by category (System, Hypervisor, Build Tools, Network, Optimization) with expand/collapse
- Compact one-line checks: each check shows name + status icon only (detail on click/expand)
- Aggregate status on collapsed categories: icon + count (e.g., "Build Tools ✓ (4/4)" or "System ⚠ (3/5 — 2 warnings)")
- Severity-first ordering: categories with failures sort to top, warnings next, then passing. Dynamically reorders after each run

### Status indicators & summary
- Colored circles with symbols: green circle + checkmark (✓), red circle + X (✗), yellow triangle + exclamation (⚠). High contrast, accessible, universally understood
- Full-width status bar at top: green "Ready to Build" or red "3 Critical Issues, 2 Warnings". Color changes based on worst status
- Per-check spinner icon while running: each check shows spinning indicator while executing, resolves to pass/fail/warn
- Three severity levels: Critical (red, blocks build), Warning (yellow, allows build with dialog), Info (blue/gray, informational)

### Run behavior & progress
- Sequential execution with live updates: checks run one at a time, each result updates immediately. Avoids threading complexity and respects implicit check dependencies
- Refresh button disabled during run: grayed out with tooltip "Checks in progress..." while executing, re-enabled on completion
- Text counter + current check name below summary banner: "Running check 5 of 12: Windows ADK Installation..." No progress bar (checks take different times, bar would be jerky)
- Results persist within session: switching tabs preserves last results. Cleared on app close or manual Refresh

### Failure presentation & guidance
- Expand in-place on click: click failed check to expand inline showing error description and remediation steps. Same interaction pattern as category expand/collapse
- Structured remediation format: one-line problem description, then numbered remediation steps. Matches Phase 45 DISM error format pattern already in codebase
- Auto-expand critical failures only: critical (build-blocking) failures auto-expand on completion. Warnings and info stay collapsed
- Build gating: Build button disabled (grayed) on any critical failure. When only warnings exist, Build button enabled but shows confirmation dialog: "Build may be affected by 2 warnings. Continue?"

### Claude's Discretion
- Exact WPF control choices (TreeView vs custom ItemsControl for categories)
- Spinner animation implementation (WPF Storyboard vs timer-based)
- Exact color hex values (follow existing UI theme)
- Category icon choices (if any, beyond status indicators)
- Spacing, padding, and typography within existing UI patterns
- How to wire sequential check execution to WPF dispatcher updates

</decisions>

<specifics>
## Specific Ideas

- Status icons should use Unicode symbols that render well in WPF without custom icon assets
- Category expand/collapse should match common WPF TreeView/Expander patterns
- The summary status bar pattern ("Ready to Build" / "3 Critical Issues, 2 Warnings") is similar to Visual Studio error list summary
- Remediation steps format should be consistent with the Phase 45 DISM error messages (already using numbered remediation steps in BuildFFUVM.ps1, FFU.Updates, FFU.Media)
- Check execution should use the existing FFU.Messaging pattern for background thread to UI communication (ConcurrentQueue-based)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 46-dashboard-foundation*
*Context gathered: 2026-02-06*
