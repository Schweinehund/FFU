# Phase 37: Winget App Ordering and Dependencies - Research

**Researched:** 2026-01-28
**Domain:** PowerShell WinGet app pipeline -- installation ordering enforcement, Win32 dependency resolution, and deduplication
**Confidence:** HIGH

## Summary

Phase 37 adds two features to the WinGet app download-to-install pipeline: (1) post-download reordering of WinGetWin32Apps.json entries to match AppList.json sequence, and (2) automatic discovery and processing of Win32 app dependencies from WinGet's `Dependencies/` subfolder mechanism. Both features are battle-tested in the upstream repository (commits b2352e3 and ad35a0b) and the implementation approach is well-defined.

The research confirmed the exact upstream implementation: four helper functions (`Invoke-WithNamedMutex`, `Set-FileContentAtomic`, `Get-WinGetWin32AppsJsonMutexName`, `Get-WinGetYamlScalarValue`) need to be added, `Add-Win32SilentInstallCommand` needs six new parameters, a new `Add-Win32DependencySilentInstallCommands` function is needed, `Get-Application` needs dependency processing hooks, and `Get-Apps` needs post-download reordering logic. The consumer (`Install-Win32Apps.ps1` line 109) already sorts by `Priority` property, so correct priority assignment is the key to install order enforcement.

**Primary recommendation:** Follow the upstream implementation closely -- the code is verified in production and handles edge cases (architecture suffixes, dependency deduplication by PackageIdentifier, stable sort preserving original order for ties, fail-safe behavior when reordering fails).

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| System.Threading.Mutex | .NET built-in | Named mutex for cross-process/thread JSON file locking | Already used by Phase 34; upstream upgraded to `Invoke-WithNamedMutex` wrapper |
| System.IO.File.Move | .NET built-in | Atomic file replacement (temp+rename) via `Set-FileContentAtomic` | Prevents partial writes / JSON corruption |
| System.Security.Cryptography.SHA256 | .NET built-in | Path-based mutex name generation | Makes mutex names unique per JSON file path |
| System.Text.RegularExpressions.Regex | .NET built-in | YAML scalar value extraction | Parses WinGet YAML manifests without external YAML parser |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| Sort-Object -Property | PowerShell built-in | Multi-key stable sort for reordering | OrderKey, IsDependency, OriginalIndex sort during reorder |
| ConvertTo-Json / ConvertFrom-Json | PowerShell built-in | WinGetWin32Apps.json serialization | All JSON read/write operations |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Regex YAML parsing | powershell-yaml module | Would add external dependency; regex is sufficient for simple scalar extraction |
| Named Mutex | File-based locking | Mutex is already established pattern from Phase 34; file locks more complex |
| temp+rename atomic write | Set-Content directly | Direct write risks partial content on crash; atomic is safer |

## Architecture Patterns

### Recommended Change Structure

```
FFU.Common.Winget.psm1
├── Helper Functions (NEW - top of file before existing functions)
│   ├── Get-WinGetWin32AppsJsonMutexName  (path-based mutex name)
│   ├── Invoke-WithNamedMutex             (generic mutex wrapper)
│   ├── Set-FileContentAtomic             (temp+rename write)
│   └── Get-WinGetYamlScalarValue         (YAML key-value extraction)
├── Add-Win32SilentInstallCommand (MODIFIED)
│   ├── +6 new parameters (YamlFilePath, BasePathOverride, PackageIdentifier, DependencyFor, SkipRemoveOnFailure switch, refactored AppFolder to Mandatory)
│   ├── Mutex upgrade: raw Mutex → Invoke-WithNamedMutex + Get-WinGetWin32AppsJsonMutexName
│   ├── Write upgrade: Set-Content → Set-FileContentAtomic
│   ├── Deduplication by PackageIdentifier (primary) + CommandLine/Arguments (secondary)
│   ├── DependencyFor and PackageIdentifier metadata on JSON entries
│   ├── SkipRemoveOnFailure guard on all Remove-Item calls
│   └── Multi-installer disambiguation by YAML basename match
├── Add-Win32DependencySilentInstallCommands (NEW)
│   ├── Discovers Dependencies/ subfolder under parent app
│   ├── Processes each *.yaml dependency manifest
│   ├── Calls Add-Win32SilentInstallCommand with dependency params
│   └── Returns 0 (success) or 5 (failure)
├── Get-Application (MODIFIED)
│   └── Call Add-Win32DependencySilentInstallCommands after main app Add-Win32SilentInstallCommand
├── Get-Apps (MODIFIED)
│   ├── Mutex upgrade: raw Mutex → Invoke-WithNamedMutex in override section
│   ├── Write upgrade: Set-Content → Set-FileContentAtomic in override section
│   └── NEW: Post-download reorder section (after override section)
│       ├── Build desiredOrderMap from AppList.json winget entries
│       ├── Normalize names (strip architecture suffixes)
│       ├── Handle DependencyFor entries (IsDependency=0 sorts before parent)
│       ├── Stable sort by OrderKey, IsDependency, OriginalIndex
│       ├── Reassign Priority sequentially
│       └── Atomic write if order/priority changed
└── Export-ModuleMember (MODIFIED)
    └── Add: Add-Win32DependencySilentInstallCommands (new export)
```

### Pattern 1: Invoke-WithNamedMutex Wrapper
**What:** Generic named mutex wrapper that replaces raw `New-Object System.Threading.Mutex` / try/finally blocks
**When to use:** All JSON file I/O operations on shared files (replaces Phase 34's inline mutex pattern)
**Source:** Upstream FFU.Common.Winget.psm1

```powershell
function Invoke-WithNamedMutex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MutexName,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 60
    )
    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    $lockTaken = $false
    try {
        $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
        if (-not $lockTaken) {
            throw "Timed out waiting for mutex '$MutexName' after $TimeoutSeconds seconds."
        }
        & $ScriptBlock
    }
    finally {
        if ($lockTaken) {
            try { $mutex.ReleaseMutex() | Out-Null }
            catch { }
        }
        $mutex.Dispose()
    }
}
```

### Pattern 2: Set-FileContentAtomic (Temp+Rename)
**What:** Writes content to a temp file then atomically renames to target, preventing partial writes
**When to use:** All WinGetWin32Apps.json writes
**Source:** Upstream FFU.Common.Winget.psm1

```powershell
function Set-FileContentAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $parentPath = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $parentPath -PathType Container)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }
    $tempPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    Set-Content -Path $tempPath -Value $Content -Encoding UTF8
    try {
        [System.IO.File]::Move($tempPath, $Path, $true)
    }
    catch {
        Move-Item -Path $tempPath -Destination $Path -Force
    }
}
```

### Pattern 3: Stable Multi-Key Sort for Ordering
**What:** Three-key sort that preserves AppList.json order, puts dependencies before parents, and maintains original order for ties
**When to use:** Post-download reorder section in Get-Apps

```powershell
# OrderKey = position from AppList.json (or MaxValue for unknown)
# IsDependency = 0 for dependency, 1 for regular (so deps sort first within same OrderKey)
# OriginalIndex = position in current JSON array (stable sort tiebreaker)
$sorted = $indexed | Sort-Object -Property OrderKey, IsDependency, OriginalIndex
```

### Pattern 4: Dependency Discovery via Dependencies/ Subfolder
**What:** Scan `ParentApp/Dependencies/*.yaml` for WinGet dependency manifests after download completes
**When to use:** After each Win32 app is added to WinGetWin32Apps.json

```powershell
$dependenciesFolderPath = Join-Path -Path $ParentAppFolderPath -ChildPath 'Dependencies'
if (Test-Path -Path $dependenciesFolderPath -PathType Container) {
    $dependencyYamlFiles = Get-ChildItem -Path $dependenciesFolderPath -Filter "*.yaml" -File
    foreach ($yamlFile in $dependencyYamlFiles) {
        $yamlText = Get-Content -Path $yamlFile.FullName -Raw
        $packageIdentifier = Get-WinGetYamlScalarValue -YamlText $yamlText -Key 'PackageIdentifier'
        # Process each dependency...
    }
}
```

### Anti-Patterns to Avoid

- **Do NOT extract reorder logic to a separate function:** CONTEXT.md locks this decision -- "Reordering logic lives inside Get-Apps (match upstream placement)"
- **Do NOT filter dependencies by target architecture:** CONTEXT.md says "Process all architecture variants found in Dependencies/"
- **Do NOT deduplicate explicit AppList.json entries:** Only auto-discovered dependencies get deduplication
- **Do NOT fail the build when reordering fails:** "Warn and proceed with unordered Priority if reordering logic fails"
- **Do NOT remove existing inline mutex pattern entirely before replacing:** Upgrade incrementally -- replace Phase 34's raw mutex with `Invoke-WithNamedMutex` wrapper

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML parsing | Full YAML parser | `Get-WinGetYamlScalarValue` regex helper | WinGet YAMLs use simple `Key: Value` format; full parser would be an external dependency |
| File locking | Custom lock file mechanism | `Invoke-WithNamedMutex` with `System.Threading.Mutex` | Named mutexes work across processes and threads, established pattern |
| Atomic file writes | Direct `Set-Content` | `Set-FileContentAtomic` temp+rename | Direct writes can produce partial content on crash/interrupt |
| Mutex name generation | Hardcoded string | `Get-WinGetWin32AppsJsonMutexName` with SHA256 hash of path | Path-based names ensure different JSON files get different mutexes |
| Dependency deduplication | Name-based matching | PackageIdentifier matching (primary) + CommandLine/Arguments (secondary) | Names can vary (architecture suffixes); PackageIdentifier is canonical |

**Key insight:** The upstream implementation already handles all edge cases discovered during real-world usage (e.g., Camtasia dependency issue). Replicating it closely avoids re-discovering the same edge cases.

## Common Pitfalls

### Pitfall 1: Architecture Suffix Mismatch During Reorder
**What goes wrong:** App names in WinGetWin32Apps.json include architecture suffixes like "(x64)" but AppList.json uses plain names
**Why it happens:** When downloading for multiple architectures, Add-Win32SilentInstallCommand appends `($SubFolder)` to the Name property
**How to avoid:** Normalize names by stripping trailing `\s+\((x86|x64|arm64)\)$` before matching against desiredOrderMap. For DependencyFor entries, use the DependencyFor value (parent name) as the base name instead.
**Warning signs:** Apps appear at the end of the install queue despite being in AppList.json

### Pitfall 2: Mutex Scope Variable Capture in ScriptBlock
**What goes wrong:** Variables from the outer scope are not accessible inside `Invoke-WithNamedMutex`'s ScriptBlock parameter
**Why it happens:** PowerShell scriptblocks passed to `Invoke-WithNamedMutex` execute in the same scope when invoked with `& $ScriptBlock`, but closures can be tricky
**How to avoid:** The upstream uses `& $ScriptBlock` (call operator) which inherits parent scope. Variables like `$winGetWin32Path`, `$overrideMap`, `$appsData` must be defined BEFORE the `Invoke-WithNamedMutex` call. Do NOT use `Invoke-Command` which would create a new scope.
**Warning signs:** "Variable not found" errors inside the mutex scriptblock

### Pitfall 3: Dependency Folder Shared Across Apps
**What goes wrong:** Removing a failed dependency app's folder deletes the shared `Dependencies/` folder needed by sibling dependencies
**Why it happens:** Default behavior of `Add-Win32SilentInstallCommand` removes the app folder on failure
**How to avoid:** Pass `-SkipRemoveOnFailure` for all dependency entries. Only dependency entries get this flag; main app entries should still clean up on failure.
**Warning signs:** "Path not found" errors when processing second dependency after first failed

### Pitfall 4: JSON Array Single-Element Behavior
**What goes wrong:** When WinGetWin32Apps.json contains exactly one entry, `ConvertFrom-Json` returns a single PSCustomObject instead of an array
**Why it happens:** PowerShell's JSON deserialization behavior for single-element arrays
**How to avoid:** Always cast with `[array]$appsData = ...` as the current code already does. The upstream adds null-check: `if ($null -eq $appsData) { $appsData = @() }`
**Warning signs:** "Cannot index into a null array" or "Method invocation failed because [PSCustomObject] does not contain a method named 'Count'"

### Pitfall 5: Return Values Inside ScriptBlock
**What goes wrong:** `return` inside `Invoke-WithNamedMutex`'s ScriptBlock does not exit the outer function
**Why it happens:** The ScriptBlock is invoked with `&` which means `return` exits only the ScriptBlock, not the calling function
**How to avoid:** Capture the ScriptBlock's return value: `$outcome = Invoke-WithNamedMutex -MutexName $name -ScriptBlock { ... return @{Added=$true} }`. Then check `$outcome` after the call to decide what the outer function returns.
**Warning signs:** Function continues executing after what should have been a duplicate-skip return

### Pitfall 6: Corrupt JSON Recovery
**What goes wrong:** If WinGetWin32Apps.json gets corrupted (partial write, concurrent access), `ConvertFrom-Json` throws and blocks all subsequent app additions
**Why it happens:** Power loss, forced process termination during write
**How to avoid:** The upstream wraps `ConvertFrom-Json` in try/catch, backs up corrupt file with timestamp suffix, and rebuilds from scratch. Combined with `Set-FileContentAtomic`, this provides defense in depth.
**Warning signs:** Build fails with "ConvertFrom-Json: Invalid JSON primitive"

## Code Examples

### Complete Reorder Algorithm (from upstream Get-Apps)

```powershell
# Source: Upstream FFU.Common.Winget.psm1 commit b2352e3 + ad35a0b merged
# Placed in Get-Apps after the override section

# Post-processing: Ensure WinGetWin32Apps.json ordering matches AppList.json
try {
    $winGetWin32Path = Join-Path -Path $OrchestrationPath -ChildPath 'WinGetWin32Apps.json'
    if (Test-Path -Path $winGetWin32Path) {
        # Build desired order map from AppList.json (winget entries only)
        $desiredOrderMap = @{}
        $orderIndex = 0
        foreach ($app in ($apps.apps | Where-Object { $_.source -eq 'winget' })) {
            if (-not [string]::IsNullOrWhiteSpace($app.name) -and
                -not $desiredOrderMap.ContainsKey($app.name)) {
                $desiredOrderMap[$app.name] = $orderIndex
                $orderIndex++
            }
        }

        if ($desiredOrderMap.Count -gt 0) {
            $mutexName = Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $winGetWin32Path
            Invoke-WithNamedMutex -MutexName $mutexName -TimeoutSeconds 60 -ScriptBlock {
                [array]$currentAppsData = Get-Content -Path $winGetWin32Path -Raw | ConvertFrom-Json
                if ($null -eq $currentAppsData) { $currentAppsData = @() }

                if ($currentAppsData.Count -gt 1) {
                    $originalNames = @($currentAppsData | ForEach-Object { $_.Name })
                    $indexed = @()
                    for ($i = 0; $i -lt $currentAppsData.Count; $i++) {
                        $entry = $currentAppsData[$i]

                        # Check DependencyFor property
                        $dependencyFor = $null
                        if ($entry.PSObject.Properties['DependencyFor']) {
                            $dependencyFor = $entry.DependencyFor
                        }

                        # Normalize name: use DependencyFor if set, strip arch suffixes
                        $baseName = $entry.Name
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $baseName = $dependencyFor
                        }
                        if (-not [string]::IsNullOrWhiteSpace($baseName)) {
                            $baseName = ($baseName -replace '\s+\((x86|x64|arm64)\)$', '')
                        }

                        # Unknown entries get MaxValue (pushed to end)
                        $orderKey = [int]::MaxValue
                        if (-not [string]::IsNullOrWhiteSpace($baseName) -and
                            $desiredOrderMap.ContainsKey($baseName)) {
                            $orderKey = [int]$desiredOrderMap[$baseName]
                        }

                        # Dependencies sort before parent (0 < 1)
                        $isDependency = 1
                        if (-not [string]::IsNullOrWhiteSpace($dependencyFor)) {
                            $isDependency = 0
                        }

                        $indexed += [PSCustomObject]@{
                            OrderKey      = $orderKey
                            IsDependency  = $isDependency
                            OriginalIndex = $i
                            App           = $entry
                        }
                    }

                    $sorted = $indexed | Sort-Object -Property OrderKey, IsDependency, OriginalIndex
                    $reorderedApps = @($sorted | ForEach-Object { $_.App })

                    # Detect changes
                    $priorityNeedsUpdate = $false
                    for ($p = 0; $p -lt $reorderedApps.Count; $p++) {
                        if ($reorderedApps[$p].PSObject.Properties['Priority'] -and
                            $reorderedApps[$p].Priority -eq ($p + 1)) {
                            continue
                        }
                        $priorityNeedsUpdate = $true
                        break
                    }
                    $sortedNames = @($reorderedApps | ForEach-Object { $_.Name })
                    $orderNeedsUpdate = (($originalNames -join "`n") -ne ($sortedNames -join "`n"))

                    if ($orderNeedsUpdate -or $priorityNeedsUpdate) {
                        for ($p = 0; $p -lt $reorderedApps.Count; $p++) {
                            $reorderedApps[$p].Priority = $p + 1
                        }
                        $jsonText = $reorderedApps | ConvertTo-Json -Depth 10
                        Set-FileContentAtomic -Path $winGetWin32Path -Content $jsonText
                        WriteLog "Reordered and re-prioritized WinGetWin32Apps.json to match AppList.json ordering."
                    }
                    else {
                        WriteLog "WinGetWin32Apps.json is already ordered to match AppList.json; no reorder needed."
                    }
                }
            }
        }
    }
}
catch {
    WriteLog "Failed to reorder WinGetWin32Apps.json: $($_.Exception.Message)"
}
```

### Dependency Processing Call in Get-Application

```powershell
# Source: Upstream FFU.Common.Winget.psm1 commit ad35a0b
# After main app Add-Win32SilentInstallCommand call:

# Add dependency install commands first (de-duped). Fail if any dependency cannot process
$depResult = Add-Win32DependencySilentInstallCommands `
    -ParentAppName $AppName `
    -ParentAppFolderPath $appFolderPath `
    -OrchestrationPath $OrchestrationPath `
    -SubFolder $subFolderForCommand
if ($depResult -ne 0) {
    WriteLog "Failed to process dependencies for $AppName. Error code: $depResult"
    return 5
}
```

### Deduplication Inside Add-Win32SilentInstallCommand

```powershell
# Source: Upstream FFU.Common.Winget.psm1 commit ad35a0b
# Inside the Invoke-WithNamedMutex ScriptBlock:

# De-dupe by PackageIdentifier first, then by command+args
$isDuplicate = $false
if (-not [string]::IsNullOrWhiteSpace($PackageIdentifier)) {
    $existingById = $appsData | Where-Object {
        $_.PSObject.Properties['PackageIdentifier'] -and
        $_.PackageIdentifier -eq $PackageIdentifier
    } | Select-Object -First 1
    if ($existingById) { $isDuplicate = $true }
}
if (-not $isDuplicate) {
    $existingByCommand = $appsData | Where-Object {
        $_.PSObject.Properties['CommandLine'] -and
        $_.PSObject.Properties['Arguments'] -and
        $_.CommandLine -eq $silentInstallCommand -and
        $_.Arguments -eq $silentInstallSwitch
    } | Select-Object -First 1
    if ($existingByCommand) { $isDuplicate = $true }
}
if ($isDuplicate) {
    WriteLog "Skipping duplicate Win32 install entry: Name='$appName' PackageIdentifier='$PackageIdentifier'"
    return @{ Added = $false; Reason = 'Duplicate' }
}
```

## State of the Art

| Old Approach (Phase 34) | Current Approach (Phase 37) | When Changed | Impact |
|-------------------------|----------------------------|--------------|--------|
| Raw `New-Object System.Threading.Mutex` inline | `Invoke-WithNamedMutex` wrapper | Upstream post-34 | Cleaner code, timeout support, best-effort release |
| Hardcoded `WinGetWin32AppsJsonLock` mutex name | `Get-WinGetWin32AppsJsonMutexName` with SHA256 hash | Upstream post-34 | Unique mutex per JSON file path |
| `Set-Content` for JSON writes | `Set-FileContentAtomic` temp+rename | Upstream post-34 | Prevents partial writes on crash |
| Priority = append order (download completion order) | Priority = AppList.json order (post-download reorder) | Upstream b2352e3 | Deterministic install sequence |
| No dependency awareness | `Add-Win32DependencySilentInstallCommands` auto-discovery | Upstream ad35a0b | Prerequisites install before dependent apps |
| Name-only duplicate check | PackageIdentifier + CommandLine/Arguments dedup | Upstream ad35a0b | Correct dedup for dependencies with architecture variants |

## Implementation Sequencing

Based on the dependency graph and upstream structure, the three plans should be:

### Plan 1: Helper Functions + Add-Win32SilentInstallCommand Upgrade
- Add 4 helper functions (Invoke-WithNamedMutex, Set-FileContentAtomic, Get-WinGetWin32AppsJsonMutexName, Get-WinGetYamlScalarValue)
- Upgrade Add-Win32SilentInstallCommand: add 6 new parameters, replace raw mutex with Invoke-WithNamedMutex, replace Set-Content with Set-FileContentAtomic, add PackageIdentifier deduplication, add DependencyFor/PackageIdentifier metadata, add SkipRemoveOnFailure guard, add multi-installer disambiguation by YAML basename
- Upgrade Get-Apps override section: replace raw mutex with Invoke-WithNamedMutex, replace Set-Content with Set-FileContentAtomic
- Update Export-ModuleMember

### Plan 2: Dependency Resolution + Ordering
- Add Add-Win32DependencySilentInstallCommands function
- Hook dependency processing into Get-Application (after main app command, call dependency processing)
- Add post-download reorder logic to Get-Apps (build desiredOrderMap, stable sort, reassign priorities)
- Add detailed logging (full install manifest before installation begins)

### Plan 3: Pester Tests
- Test ordering preservation (apps install in AppList.json order)
- Test dependency resolution (dependencies discovered and added)
- Test deduplication (duplicate PackageIdentifier skipped)
- Test DependencyFor ordering (dependencies sort before parent)
- Test architecture suffix normalization
- Test fail-safe behavior (reorder failure warns, doesn't fail build)
- Test SkipRemoveOnFailure behavior
- Test helper functions (Invoke-WithNamedMutex, Set-FileContentAtomic, Get-WinGetYamlScalarValue)

## Existing Code State (Fork vs Upstream Delta)

### What Phase 34 Already Provides (in our fork)
- `Add-Win32SilentInstallCommand`: Basic mutex protection with raw `System.Threading.Mutex` and `WinGetWin32AppsJsonLock` name, duplicate detection by Name
- `Get-Apps` override section: Basic mutex protection with raw `System.Threading.Mutex`
- Both use `Set-Content` for writes (not atomic)

### What Phase 37 Must Add (upstream delta)

**New functions (4):**
1. `Get-WinGetWin32AppsJsonMutexName` -- SHA256-based mutex name from file path
2. `Invoke-WithNamedMutex` -- Generic mutex wrapper with timeout
3. `Set-FileContentAtomic` -- Temp+rename atomic write
4. `Get-WinGetYamlScalarValue` -- Regex-based YAML scalar extraction

**New function (1):**
5. `Add-Win32DependencySilentInstallCommands` -- Dependency discovery and processing

**Modified functions (3):**
6. `Add-Win32SilentInstallCommand` -- 6 new params, mutex/write upgrades, dedup, metadata, SkipRemoveOnFailure, YAML basename disambiguation
7. `Get-Application` -- Hook dependency processing after main app
8. `Get-Apps` -- Mutex/write upgrades in override section + new reorder section

**Modified export:**
9. `Export-ModuleMember` -- Add new exported functions

### Key Differences from Upstream

The upstream also changed `Get-Apps` to use parallel processing (`Invoke-ParallelProcessing`), added `$LogFilePath` and `$ThrottleLimit` parameters, and refactored the download loop. Our fork still uses sequential download (foreach loop). Phase 37 should NOT port the parallel download changes -- only the ordering and dependency features. The sequential download loop in our fork's `Get-Apps` still works correctly with the new features because:
- `Add-Win32SilentInstallCommand` handles concurrent writes regardless of calling pattern
- The reorder logic runs AFTER all downloads complete (same position as upstream)
- Dependency processing happens inside `Get-Application` per-app (same call site)

## Open Questions

1. **Phase 34 mutex upgrade path**
   - What we know: Phase 34 uses raw `System.Threading.Mutex` with hardcoded name. Phase 37 upgrades to `Invoke-WithNamedMutex` with hash-based name.
   - What's unclear: Whether to upgrade Phase 34's existing inline mutex code in-place or leave it and only use new pattern for new code
   - Recommendation: Replace ALL raw mutex usage with `Invoke-WithNamedMutex` during Phase 37 (cleaner, more maintainable, consistent pattern)

2. **FFUUI.Core.Winget.psm1 integration**
   - What we know: The UI module's `Start-WingetAppDownloadTask` also calls `Get-Application` and has its own AppList.json management
   - What's unclear: Whether the UI code path needs dependency hooks too
   - Recommendation: The UI passes `-SkipWin32Json` to `Get-Application`, so dependency processing would be skipped in UI mode. This matches upstream behavior. No UI module changes needed for Phase 37.

3. **Export-ModuleMember additions**
   - What we know: Currently exports `Get-Application, Get-Apps, Confirm-WinGetInstallation, Add-Win32SilentInstallCommand, Install-Winget`
   - What's unclear: Which new functions need exporting
   - Recommendation: Export `Add-Win32DependencySilentInstallCommands` (public API). Keep helper functions (`Invoke-WithNamedMutex`, `Set-FileContentAtomic`, `Get-WinGetWin32AppsJsonMutexName`, `Get-WinGetYamlScalarValue`) as module-internal (not exported) since they are implementation details. The upstream exports `Add-Win32SilentInstallCommand` and `Add-Win32DependencySilentInstallCommands` but NOT the helpers.

## Sources

### Primary (HIGH confidence)
- Upstream commit b2352e3 diff -- ordering implementation (WebFetch of GitHub commit + raw file)
- Upstream commit ad35a0b diff -- dependency handling implementation (WebFetch of GitHub commit)
- Upstream `FFU.Common.Winget.psm1` raw file from UI_2510 branch -- complete current implementation including all helper functions
- Fork `FFU.Common.Winget.psm1` -- current codebase state (direct file read)
- Fork `Install-Win32Apps.ps1` -- consumer of WinGetWin32Apps.json (direct file read, line 109: `Sort-Object -Property Priority`)
- Phase 34 plan documents (34-01-PLAN.md, 34-02-PLAN.md, 34-03-PLAN.md) -- what's already implemented
- Phase 37 CONTEXT.md -- locked decisions and Claude's discretion areas

### Secondary (MEDIUM confidence)
- Upstream FFU.Common.Core.psm1 -- confirmed helper functions are NOT in this file (they live in FFU.Common.Winget.psm1)
- FFUUI.Core.Winget.psm1 -- confirmed UI path passes `-SkipWin32Json` (no dependency processing needed in UI mode)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all components are .NET built-ins, already established patterns in the codebase
- Architecture: HIGH -- follows upstream implementation exactly, code is verified in production
- Pitfalls: HIGH -- identified from upstream code review and real-world issues (Camtasia dependency discovery)

**Research date:** 2026-01-28
**Valid until:** 2026-02-28 (stable domain, upstream code changes infrequently)
