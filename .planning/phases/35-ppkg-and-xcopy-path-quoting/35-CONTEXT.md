# Phase 35: PPKG and xcopy Path Quoting - Context

**Gathered:** 2026-01-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix provisioning package filename handling so PPKG files with spaces in their names copy correctly during deployment (ApplyFFU.ps1) and USB creation (USBImagingToolCreator.ps1). Two scripts affected, both use xcopy for PPKG file operations.

</domain>

<decisions>
## Implementation Decisions

### Quoting strategy
- Use backtick-escaped double quotes around paths — same pattern as Phase 34's Winget path quoting for codebase consistency
- Quote BOTH source and destination paths defensively — handles spaces anywhere in the path
- Our codebase quoting pattern takes priority over upstream's approach if they conflict

### Copy method
- Keep xcopy as primary copy method (Claude's discretion on whether to match or differ between scripts)
- Add Copy-Item fallback if xcopy fails — belt and suspenders approach
- Claude's discretion on whether ApplyFFU.ps1 and USBImagingToolCreator.ps1 use identical or context-appropriate patterns

### Failure behavior
- PPKG copy failure is non-blocking in BOTH scripts — warn and continue
- Warning message must include the actual source path, destination path, and error message for user diagnosis
- Same warn-and-continue behavior for both deployment (ApplyFFU.ps1) and USB creation (USBImagingToolCreator.ps1)

### Claude's Discretion
- Whether to fix adjacent unquoted paths in the same functions (if found during implementation)
- Whether to use identical copy patterns in both scripts or context-appropriate variations
- Primary vs fallback copy method choice (xcopy vs Copy-Item vs robocopy)
- Exact implementation of the Copy-Item fallback mechanism

</decisions>

<specifics>
## Specific Ideas

- Phase 34 established the backtick-escaped quote pattern — reuse that for consistency
- xcopy + Copy-Item fallback gives reliability without abandoning upstream alignment
- Verbose failure logging helps users self-diagnose remaining edge cases

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 35-ppkg-and-xcopy-path-quoting*
*Context gathered: 2026-01-28*
