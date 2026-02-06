# Phase 45: DISM Resilience Formalization - Context

**Gathered:** 2026-02-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Integrate existing Test-DismReady and Test-DismFunctional functions into the build pipeline so DISM health is validated before all image operations and degradation is detected early to prevent cascading failures. This phase is pipeline integration only — the dashboard UI surfaces these in Phase 46.

</domain>

<decisions>
## Implementation Decisions

### Failure behavior
- Pre-check failure: Retry once (restart WIMMount service), then hard stop if still broken
- Mid-build degradation (after KB install): Hard stop the build immediately — no partial image output
- Non-critical operations (WinSxS cleanup): Hard stop consistently — same behavior for all DISM failures regardless of criticality
- Cleanup on failure: Cleanup by default (unmount images, remove temp files), but skip cleanup when debug mode is active
- Debug mode: Dual-activation via `-Debug` parameter on BuildFFUVM.ps1 AND `debug: true` in config.json — either enables debug behavior. Extensible for future debug processes beyond DISM

### Check placement
- Startup gate: Run comprehensive DISM health check at build start before any operations begin
- Pre-operation: Test-DismReady before EVERY individual Mount-WindowsImage call (not batched at phase boundaries)
- Post-KB: Test-DismFunctional after EVERY individual KB install (not after full batch)
- Driver injection: All DISM operations get pre/post checks — Add-WindowsPackage included, same as mount and KB ops

### User messaging
- Error format: Structured messages with specific remediation steps — "DISM SERVICE UNAVAILABLE: WIMMount service not responding. Run 'sfc /scannow' or restart WIMMount service."
- UI visibility: Build log only for Phase 45 — dashboard integration comes in Phase 46
- Success logging: Detailed always — log all check details (service states, response times) even on success, not just on failure
- Failure context: Full context in error messages including specific operation, position in sequence, and remediation command — "DISM FAILED during KB5034441 install (operation 3/7): WIMMount service degraded"

### Recovery strategy
- Pre-check recovery: Restart WIMMount service (Stop-Service/Start-Service) — quick (~2s) and safe
- Mid-build recovery: No recovery attempt — pre-check only. Mid-build DISM degradation after KB installs is usually unrecoverable without unmount/remount
- Recovery logging: Prominent log entry for every recovery action — "DISM RECOVERY: Restarting WIMMount service... Service restarted. Rechecking DISM... OK"

### Claude's Discretion
- Exact implementation of the debug flag plumbing (parameter inheritance through call chain)
- Which specific DISM operations in the codebase need check instrumentation (code analysis required)
- Performance optimization of check frequency if needed
- Exact error message wording and remediation command specifics

</decisions>

<specifics>
## Specific Ideas

- Debug mode should be a general-purpose feature (`-Debug` + `debug: true` in config.json) that can be extended for future debug processes, not DISM-specific
- User wants detailed logging even on success — they want to see check results always, not just when something fails
- Hard stop is the consistent policy across all DISM failure types — no "skip and continue" for any DISM operation
- Recovery attempts are limited to pre-operation checks only — never attempt recovery while an image is actively mounted/being serviced

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 45-dism-resilience-formalization*
*Context gathered: 2026-02-06*
