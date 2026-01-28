# Phase 36: CU Skip Logic and ESD BITS Downloads - Context

**Gathered:** 2026-01-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Skip unnecessary CU (Cumulative Update) downloads when the ESD image version already matches or exceeds the available CU version, and switch ESD downloads to BITS transfer with user-configurable priority. Both changes optimize build time and download reliability.

</domain>

<decisions>
## Implementation Decisions

### CU Skip Messaging
- Full comparison logging: show both ESD and CU versions with human-readable reason
- Format when skipping: `ESD {version} already includes CU KB{id} ({version}) - skipping download`
- Format when downloading: `CU KB{id} ({version}) > ESD ({version}) - downloading update`
- Both skip and download decisions logged at INFO level (standard WriteLog, no special prefix)
- Log messages include version + reason so users understand WHY without needing debug mode

### Version Comparison Edge Cases
- Use full version string comparison (e.g., 10.0.26100.2894), not just build number
- On parse failure: download CU anyway (safe default) with warning about unparseable version
- When no CU found in catalog: warn and continue (`No CU found for this build - proceeding without cumulative update`)
- Equal version handling: Claude's discretion based on upstream behavior (see below)

### BITS Transfer Behavior
- Add `-BitsPriority` parameter (matching upstream pattern) for user-configurable BITS priority
- Default priority: Foreground (fastest — build speed is priority)
- Progress logging at regular intervals (e.g., every 30 seconds) with bytes transferred and percentage
- Fallback behavior: Claude's discretion based on existing FFU.Common.Download fallback chain patterns
- Expose BitsPriority in UI in existing Downloads/Network section

### Skip Override Option
- Follow upstream approach for any CU skip override mechanism, with minimal changes to stay consistent with codebase
- If override exists: expose in both UI (Downloads/Network section) and as script parameter
- If upstream has no override: don't add one (version comparison is deterministic)

### Claude's Discretion
- Equal version handling (>= vs > for skip threshold) — follow upstream behavior
- BITS fallback chain specifics — integrate with existing FFU.Common.Download patterns
- BITS progress log detail level (file size, ETA) — based on what BITS natively provides
- Exact progress logging interval — pick reasonable default

</decisions>

<specifics>
## Specific Ideas

- Upstream added a `-BitsPriority` parameter to let users choose BITS download priority across the build system and UI — port this pattern
- BITS priority should be configurable in the UI in the existing Downloads/Network section alongside any CU override
- Approach should introduce minimal changes while staying consistent with existing codebase patterns

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 36-cu-skip-esd-bits*
*Context gathered: 2026-01-28*
