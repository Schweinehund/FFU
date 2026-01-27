# Phase 33: OEM Driver Logging - Context

**Gathered:** 2026-01-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Audit all OEM driver operations to ensure proper file logging (WriteLog) instead of console-only output. Covers driver selection, download, extraction, and injection across all OEM paths (Dell, HP, Lenovo, Microsoft). All error paths must include actionable remediation messages logged to FFUDevelopment.log.

</domain>

<decisions>
## Implementation Decisions

### Audit Scope & Boundaries
- **All driver code paths in scope:** FFU.Drivers module, BuildFFUVM.ps1 driver sections, FFU.Common.Drivers, and Drivers/Providers/
- **Include Phase 31/32 code:** HP exit code 1168 and Dell CatalogPC.xml handling are included in the audit despite being recently written
- **All console output types:** Audit and migrate Write-Host, Write-Warning, AND Write-Verbose calls — not just Write-Host
- **Dual output required:** When replacing console output, keep Write-Host for console visibility AND add WriteLog for file logging
- **[Console]::WriteLine() excluded:** ThreadJob-safe [Console] calls (from v0.0.10 fix) stay as-is — do NOT migrate these to WriteLog

### Log Message Standards
- **Structured prefix format:** All OEM driver log messages use `[OEM][Model][Operation]` prefix — e.g., `[Dell][Latitude 7490][Download] Downloading CatalogPC.cab...`
- **Retrofit all existing messages:** Update existing Write-Host messages to use the structured prefix format when adding WriteLog
- **Severity levels:** Match whatever WriteLog already supports — do not introduce new severity levels
- **Start + completion logging:** Log when each operation begins AND ends — e.g., `Starting Dell driver download...` then `Dell driver download complete (42 files)`
- **Include timing:** Log elapsed duration for download, extraction, and injection operations — e.g., `Dell driver download complete in 12.3s`

### Remediation Message Content
- **Specific numbered/bulleted steps:** Remediation messages provide step-by-step guidance (Claude decides numbered vs bulleted based on whether order matters)
- **Copy-paste ready commands:** Include exact commands or config changes needed to fix the issue — e.g., `$env:HTTP_PROXY = "http://proxy:8080"`
- **Always include exception/error code:** Log the full exception message and error code alongside remediation steps
- **Categorize root cause:** Tag as "User Action:" (e.g., check config) vs "Environment:" (e.g., network down) so users know what they can fix
- **Always state build impact:** Non-critical failures explicitly state build will continue — e.g., "Build will continue without Dell drivers."
- **Point to log file:** Remediation messages include `See FFUDevelopment.log for full error details`
- **Self-contained messages:** No external links to GitHub issues or documentation — all remediation info is in the message itself

### Migration Strategy
- **Dual output everywhere:** WriteLog for file logging + Write-Host for console visibility on every migrated call
- **WriteLog + keep Write-Verbose:** Add WriteLog for file logging but preserve Write-Verbose for users running with -Verbose
- **Research produces inventory:** Research phase creates a full inventory of all Write-Host/Warning/Verbose calls in driver code paths, referenced in the plan
- **Mock-based Pester tests:** Mock WriteLog and assert it was called with expected parameters — fast, isolated tests

### Claude's Discretion
- Numbered steps vs bullet points for multi-step remediation (based on whether order matters)
- ThreadJob-safe $function:WriteLog guard pattern — apply consistently or case-by-case based on execution context
- Timing implementation — Measure-Command vs [Diagnostics.Stopwatch] based on operation structure and existing patterns

</decisions>

<specifics>
## Specific Ideas

- Structured prefix format `[OEM][Model][Operation]` enables easy grep/filtering of log files
- Every non-critical failure message must explicitly say "Build will continue without [X] drivers" — never leave the user wondering if the build stopped
- Remediation steps should be copy-paste ready for IT admins who may not be PowerShell experts

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 33-oem-driver-logging*
*Context gathered: 2026-01-27*
