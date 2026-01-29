# Phase 37: Winget App Ordering and Dependencies - Context

**Gathered:** 2026-01-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Enforce AppList.json installation order through the download-to-install pipeline, and auto-resolve Win32 app dependencies with deduplication. Both modifications target FFU.Common.Winget.psm1 and build on Phase 34's mutex/atomic write patterns. No new AppList.json schema fields — dependency discovery uses Winget's native Dependencies/ subfolder mechanism.

</domain>

<decisions>
## Implementation Decisions

### Install Ordering
- Follow upstream post-download reorder approach (commit b2352e3): let parallel downloads complete in any order, then rewrite Priority values to match AppList.json sequence
- Reordering logic lives inside Get-Apps (match upstream placement) — not extracted to a separate function
- Detailed per-app logging: log each app's old Priority -> new Priority change during reorder
- Dependencies slot before their parent app via DependencyFor marker; unknown non-dependency apps go to the end of the install queue

### Dependency Resolution
- Follow upstream Dependencies/ subfolder discovery (commit ad35a0b): scan ParentApp/Dependencies/*.yaml after download completes — no custom AppList.json schema changes needed
- New standalone function Add-Win32DependencySilentInstallCommands() called after main app YAML processing (match upstream structure)
- Extend WinGetWin32Apps.json entries with DependencyFor (parent app name) and PackageIdentifier (for dedup) properties — match upstream schema
- Process all architecture variants found in Dependencies/ (x86, x64, arm64) — don't filter to target arch only

### Deduplication Logic
- Deduplicate by exact PackageIdentifier string match — if a dependency with that ID already exists in WinGetWin32Apps.json, skip the duplicate
- Log each individual skip: "Skipping duplicate dependency [Name] (PackageIdentifier: [ID]) — already queued for [ParentApp]"
- Only deduplicate auto-discovered dependencies — do not second-guess duplicate app IDs in AppList.json itself
- If same app appears both explicitly in AppList.json AND as an auto-discovered dependency, keep both entries (upstream behavior)

### Failure Behavior
- SkipRemoveOnFailure for dependency entries only — prevents deleting shared Dependencies/ folder when one dep fails; main app entries still clean up on failure as before
- Warn and proceed with unordered Priority if reordering logic fails (e.g., can't parse AppList.json) — build continues rather than failing
- Log full install manifest before installation begins: numbered list showing final order with dependency markers (e.g., "1. VCRedist (dep for Camtasia), 2. Camtasia, 3. Chrome")

### Claude's Discretion
- Malformed dependency YAML handling: Claude picks the appropriate error handling approach for unparseable dependency manifests
- Name normalization details: how architecture suffixes like "(x64)" are stripped for order matching
- Add-Win32SilentInstallCommand parameter refactoring: how new parameters (YamlFilePath, BasePathOverride, PackageIdentifier, DependencyFor, SkipRemoveOnFailure) integrate with existing signature
- Exact reordering algorithm implementation (stable sort, OrderKey assignment)

</decisions>

<specifics>
## Specific Ideas

- Follow upstream commits closely: b2352e3 (ordering) and ad35a0b (dependencies) — these are battle-tested implementations solving real-world failures (Camtasia dependency issue)
- Reordering normalizes app names by stripping arch suffixes before matching to AppList.json positions
- Dependencies use DependencyFor property so the reorder algorithm can place them immediately before their parent app
- Both features build on Phase 34's Invoke-WithNamedMutex and Set-FileContentAtomic patterns for thread-safe JSON writes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 37-winget-app-ordering-and-dependencies*
*Context gathered: 2026-01-28*
