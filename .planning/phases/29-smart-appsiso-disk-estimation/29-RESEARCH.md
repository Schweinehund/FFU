# Phase 29: Smart Apps.iso & Disk Estimation - Research

**Researched:** 2026-01-25
**Domain:** Apps.iso staleness detection, content hashing, disk space estimation
**Confidence:** HIGH

## Summary

Phase 29 extends the existing Apps.iso staleness detection system with content hashing and adds pre-flight disk space estimation. Research reveals:

1. **Existing staleness detection** in BuildFFUVM.ps1 (lines 3194-3276) uses file modification times to detect when downloaded content is newer than the existing Apps.iso. This approach has limitations - it only detects changes when files are RE-DOWNLOADED, not when configuration options change.

2. **Content hashing** can be implemented using PowerShell's built-in `Get-FileHash` cmdlet (SHA256), following the pattern already used in `.security/orchestration-hashes.json` for integrity verification.

3. **Disk space estimation** builds on the existing `Get-FFURequirements` function in FFU.Preflight module (lines 206-323) which already calculates space based on features. The Apps.iso-specific estimation needs component-level granularity.

**Primary recommendation:** Extend the staleness detection with a content manifest/hash system and add Apps.iso-specific disk estimation to the pre-flight validation.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Get-FileHash | Built-in | SHA256 file hashing | Native PowerShell, cross-version compatible |
| ConvertTo-Json/From-Json | Built-in | Manifest storage | Native, human-readable format |
| Get-ChildItem | Built-in | Directory enumeration | Recursive file scanning |
| Get-PSDrive | Built-in | Disk space queries | Cross-platform disk info |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| [System.IO.Hashing] | .NET 7+ | Alternative hashing | If streaming hash needed (large files) |
| Measure-Object | Built-in | File size calculation | Summing component sizes |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SHA256 | MD5 | MD5 faster but less collision-resistant; SHA256 preferred for integrity |
| JSON manifest | SQLite | SQLite more complex; JSON sufficient for small manifests |

**Installation:**
No additional packages required - all functionality is built into PowerShell 7+.

## Architecture Patterns

### Recommended Project Structure

Based on existing module organization:

```
FFUDevelopment/
├── Modules/
│   ├── FFU.Apps/
│   │   └── FFU.Apps.psm1           # Add: Get-AppsContentManifest, Test-AppsISOStaleness
│   └── FFU.Preflight/
│       └── FFU.Preflight.psm1      # Add: Get-AppsISODiskEstimate, Test-FFUAppsISODiskSpace
├── Apps/
│   └── .manifest.json              # NEW: Content manifest file (hashes + config state)
└── BuildFFUVM.ps1                  # Modify: Call new staleness check functions
```

### Pattern 1: Content Manifest with Configuration State

**What:** Store both file hashes AND configuration state in manifest
**When to use:** When staleness depends on both file content AND build options
**Example:**
```powershell
# Manifest structure
$manifest = @{
    Version = "1.0.0"
    Generated = [DateTime]::UtcNow.ToString("o")
    ConfigState = @{
        InstallOffice = $true
        UpdateLatestDefender = $true
        UpdateLatestMSRT = $false
        UpdateEdge = $true
        UpdateOneDrive = $true
    }
    Components = @{
        Office = @{
            Path = "Apps\Office"
            Files = @(
                @{ Name = "setup.exe"; Hash = "abc123..."; Size = 12345678 }
                @{ Name = "Office\Data\..."; Hash = "def456..."; Size = 98765432 }
            )
            TotalSize = 4294967296  # 4GB
        }
        Defender = @{
            Path = "Apps\Defender"
            Files = @(...)
            TotalSize = 1073741824  # 1GB
        }
        # ... other components
    }
    TotalSize = 5368709120  # Sum of all components
    ManifestHash = "sha256-of-this-manifest"
}
```

### Pattern 2: Tiered Staleness Detection

**What:** Three-tier check: (1) ISO exists, (2) manifest matches, (3) files unchanged
**When to use:** Optimize for common case (no changes) while catching all change types
**Example:**
```powershell
function Test-AppsISOStaleness {
    param(
        [string]$AppsISOPath,
        [string]$AppsPath,
        [hashtable]$CurrentConfig
    )

    # Tier 1: Does ISO exist?
    if (-not (Test-Path $AppsISOPath)) {
        return @{ Stale = $true; Reason = "ISO does not exist"; Action = "Create" }
    }

    # Tier 2: Does manifest exist and match current config?
    $manifestPath = Join-Path $AppsPath ".manifest.json"
    if (-not (Test-Path $manifestPath)) {
        return @{ Stale = $true; Reason = "No manifest found"; Action = "Rebuild" }
    }

    $manifest = Get-Content $manifestPath | ConvertFrom-Json
    $configChanged = Compare-ConfigState -Manifest $manifest -Current $CurrentConfig
    if ($configChanged) {
        return @{ Stale = $true; Reason = "Configuration changed: $($configChanged -join ', ')"; Action = "Rebuild" }
    }

    # Tier 3: Do file hashes match?
    $hashMismatch = Compare-ContentHashes -Manifest $manifest -AppsPath $AppsPath
    if ($hashMismatch) {
        return @{ Stale = $true; Reason = "Files changed: $($hashMismatch.Count) files"; Action = "Rebuild" }
    }

    return @{ Stale = $false; Reason = "ISO is current"; Action = "Skip" }
}
```

### Pattern 3: Component-Based Disk Estimation

**What:** Calculate disk requirements per component with multipliers for temp space
**When to use:** Pre-flight validation before Apps.iso creation
**Example:**
```powershell
# Component size estimates (empirical values)
$ComponentSizes = @{
    BaseOrchestration = 50MB      # Scripts, orchestration files
    Office = 4GB                   # Full Office install
    Defender = 1GB                 # Platform + definitions
    MSRT = 150MB                   # Malware removal tool
    Edge = 150MB                   # Edge installer
    OneDrive = 50MB                # OneDrive setup
}

function Get-AppsISODiskEstimate {
    param(
        [hashtable]$Features,
        [string]$AppsPath
    )

    $estimate = @{
        Components = @{}
        TotalContent = 0
        ISOSize = 0
        TempSpace = 0
        RequiredFree = 0
    }

    # Base orchestration always present
    $estimate.Components["Orchestration"] = $ComponentSizes.BaseOrchestration
    $estimate.TotalContent += $ComponentSizes.BaseOrchestration

    # Add enabled components
    if ($Features.InstallOffice) {
        # Check if Office already downloaded
        $officePath = Join-Path $AppsPath "Office"
        if (Test-Path $officePath) {
            $actualSize = (Get-ChildItem $officePath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $estimate.Components["Office"] = $actualSize
        } else {
            $estimate.Components["Office"] = $ComponentSizes.Office
        }
        $estimate.TotalContent += $estimate.Components["Office"]
    }

    # ... similar for other components

    # ISO creation requires ~same space as content
    $estimate.ISOSize = $estimate.TotalContent

    # Temp space for oscdimg (1.5x safety margin)
    $estimate.TempSpace = [int]($estimate.TotalContent * 0.5)

    # Total required = content + ISO + temp
    $estimate.RequiredFree = $estimate.TotalContent + $estimate.ISOSize + $estimate.TempSpace

    return $estimate
}
```

### Anti-Patterns to Avoid

- **Hashing ISO file directly:** ISO files are large (4-6GB); hash the manifest/source files instead
- **Checking only modification times:** Misses config changes and file replacements with same size
- **Global disk check only:** Must check the specific drive where Apps folder resides
- **Silent skips:** Always log WHY rebuild was skipped or triggered

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File hashing | Custom hash algorithm | Get-FileHash -Algorithm SHA256 | Built-in, tested, fast |
| Disk space check | Custom WMI query | Get-PSDrive or [System.IO.DriveInfo] | Cross-platform, reliable |
| JSON serialization | String concatenation | ConvertTo-Json -Depth 10 | Handles escaping, nesting |
| Recursive file listing | Custom directory walker | Get-ChildItem -Recurse | Handles symlinks, permissions |

**Key insight:** The existing FFU.Preflight module already has `Test-FFUDiskSpace` and `Get-FFURequirements` patterns - extend these rather than creating parallel implementations.

## Common Pitfalls

### Pitfall 1: Manifest Location vs ISO Location

**What goes wrong:** Storing manifest inside Apps folder means it gets included in ISO; storing outside means it can be orphaned.
**Why it happens:** Unclear ownership of manifest lifecycle.
**How to avoid:** Store manifest at `Apps\.manifest.json` (dotfile convention), exclude from ISO by oscdimg or accept minimal overhead (< 10KB).
**Warning signs:** Manifest missing after cleanup, or manifest bloating ISO.

### Pitfall 2: Hash Comparison Performance

**What goes wrong:** Hashing 4GB of Office files takes 30+ seconds, slowing every build check.
**Why it happens:** Full recursive hash on every build attempt.
**How to avoid:** Use tiered approach - check manifest timestamp first, only hash if manifest is stale or missing.
**Warning signs:** Long delays before "Skipping Apps.iso rebuild" message.

### Pitfall 3: Config State Serialization

**What goes wrong:** Boolean values serialize differently (`$true` vs `True` vs `true`), causing false positives.
**Why it happens:** PowerShell JSON serialization quirks.
**How to avoid:** Normalize config values before comparison; compare semantically, not string-wise.
**Warning signs:** "Configuration changed" when nothing actually changed.

### Pitfall 4: Disk Space Units Confusion

**What goes wrong:** Mixing bytes, KB, MB, GB without conversion; off-by-1000 vs 1024 errors.
**Why it happens:** PowerShell uses different units in different contexts.
**How to avoid:** Always work in bytes internally, format for display only at output.
**Warning signs:** "5GB required" when 5TB is actually needed.

### Pitfall 5: Component Path Assumptions

**What goes wrong:** Hardcoding paths like `Apps\Office` when user may have custom AppsPath.
**Why it happens:** Copy-paste from existing code with hardcoded paths.
**How to avoid:** Always join paths: `Join-Path $AppsPath "Office"`.
**Warning signs:** "Path not found" errors with custom AppsPath.

## Code Examples

Verified patterns from official sources and existing codebase:

### Generating File Hash

```powershell
# Source: PowerShell built-in Get-FileHash
# Existing pattern in .security/orchestration-hashes.json
$hash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
```

### Component Size Calculation

```powershell
# Source: FFUDevelopment/BuildFFUVM.ps1 lines 2824-2828 (Defender size check pattern)
$componentFiles = Get-ChildItem -Path $componentPath -Recurse -File -ErrorAction SilentlyContinue
if ($componentFiles -and $componentFiles.Count -gt 0) {
    $componentSize = ($componentFiles | Measure-Object -Property Length -Sum).Sum
    WriteLog "Component size: $([math]::Round($componentSize/1MB, 2)) MB"
}
```

### Disk Space Validation Pattern

```powershell
# Source: FFU.Preflight.psm1 lines 850-860
$driveLetter = (Resolve-Path $FFUDevelopmentPath -ErrorAction SilentlyContinue)?.Drive.Name
if (-not $driveLetter) {
    $driveLetter = $FFUDevelopmentPath.Substring(0, 1)
}
$drive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
$availableGB = [Math]::Round($drive.Free / 1GB, 2)
```

### Existing Staleness Detection (to extend)

```powershell
# Source: BuildFFUVM.ps1 lines 3194-3276
if (Test-Path $AppsISO) {
    $isoLastWrite = (Get-Item $AppsISO).LastWriteTime
    WriteLog "Existing Apps.iso found (Last modified: $isoLastWrite). Checking if update files are newer..."

    $needsRebuild = $false
    # Check each component's newest file against ISO timestamp
    if ($UpdateLatestDefender -and (Test-Path -Path $DefenderPath)) {
        $defenderFiles = Get-ChildItem -Path $DefenderPath -Recurse -File -ErrorAction SilentlyContinue
        if ($defenderFiles) {
            $newestDefender = $defenderFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($newestDefender.LastWriteTime -gt $isoLastWrite) {
                $needsRebuild = $true
                WriteLog "Defender file is newer than Apps.iso: $($newestDefender.Name)"
            }
        }
    }
    # ... similar for MSRT, Edge, OneDrive
}
```

### WriteLog Pattern (to follow)

```powershell
# Source: FFU.Common.Core.psm1 lines 141-200
# All logging must use WriteLog for consistency
WriteLog "Apps.iso content hash mismatch detected"
WriteLog "  Changed files: $changedCount"
WriteLog "  Reason: Configuration changed (InstallOffice: $false -> $true)"
WriteLog "  Action: Rebuilding Apps.iso"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Timestamp-only staleness | Hash-based staleness | This phase | Catches all changes, not just downloads |
| Manual cleanup guess | Pre-flight disk estimate | This phase | Fail-fast before long downloads |
| Silent skip | Logged skip with reason | This phase | Better diagnostics |

**Deprecated/outdated:**
- None in this domain; this is new functionality building on existing patterns

## Open Questions

Things that couldn't be fully resolved:

1. **Manifest storage location**
   - What we know: `.manifest.json` in Apps folder is conventional
   - What's unclear: Should it be excluded from ISO via oscdimg flag or accepted?
   - Recommendation: Accept in ISO (< 10KB overhead), simplifies implementation

2. **Hash algorithm choice**
   - What we know: SHA256 is used in orchestration-hashes.json
   - What's unclear: Is MD5 acceptable for performance on large Office folders?
   - Recommendation: Use SHA256 for consistency; performance mitigated by tiered checks

3. **Custom apps handling**
   - What we know: Win32 and MSStore folders contain user-provided apps
   - What's unclear: Should we hash user apps or just track presence?
   - Recommendation: Hash all files for completeness; warn if custom apps folder is very large

## Sources

### Primary (HIGH confidence)
- FFUDevelopment/BuildFFUVM.ps1 lines 3194-3276 - Existing staleness detection
- FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1 lines 206-323, 802-925 - Get-FFURequirements, Test-FFUDiskSpace
- FFUDevelopment/Modules/FFU.Apps/FFU.Apps.psm1 - New-AppsISO function
- FFUDevelopment/.security/orchestration-hashes.json - SHA256 hashing pattern

### Secondary (MEDIUM confidence)
- FFUDevelopment/FFU.Common/FFU.Common.Core.psm1 lines 141-200 - WriteLog patterns
- PowerShell documentation for Get-FileHash, Get-PSDrive

### Tertiary (LOW confidence)
- None - all patterns verified from codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools are built-in PowerShell cmdlets
- Architecture: HIGH - Extends existing patterns in codebase
- Pitfalls: MEDIUM - Based on general PowerShell experience, not specific incidents

**Research date:** 2026-01-25
**Valid until:** 2026-02-25 (30 days - stable domain, extending existing patterns)

## Files to Modify

| File | Changes | Rationale |
|------|---------|-----------|
| `FFUDevelopment/Modules/FFU.Apps/FFU.Apps.psm1` | Add `Get-AppsContentManifest`, `Test-AppsISOStaleness`, `New-AppsContentManifest` | Core staleness detection functions |
| `FFUDevelopment/Modules/FFU.Apps/FFU.Apps.psd1` | Export new functions | Module manifest update |
| `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` | Add `Get-AppsISODiskEstimate`, `Test-FFUAppsISODiskSpace` | Disk estimation functions |
| `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1` | Export new functions | Module manifest update |
| `FFUDevelopment/BuildFFUVM.ps1` | Replace lines 3194-3276 with call to `Test-AppsISOStaleness`; add disk check | Integration point |
| `Tests/Unit/FFU.Apps.Tests.ps1` | Add tests for new functions | Coverage |
| `Tests/Unit/FFU.Preflight.Tests.ps1` | Add tests for disk estimation | Coverage |

## Component Paths Reference

Based on BuildFFUVM.ps1 variable definitions:

| Component | Path Variable | Default Path |
|-----------|--------------|--------------|
| Apps root | `$AppsPath` | `$FFUDevelopmentPath\Apps` |
| Apps ISO | `$AppsISO` | `$FFUDevelopmentPath\Apps\Apps.iso` |
| Orchestration | `$OrchestrationPath` | `$AppsPath\Orchestration` |
| Office | `$OfficePath` | `$AppsPath\Office` |
| Defender | `$DefenderPath` | `$AppsPath\Defender` |
| MSRT | `$MSRTPath` | `$AppsPath\MSRT` |
| OneDrive | `$OneDrivePath` | `$AppsPath\OneDrive` |
| Edge | `$EdgePath` | `$AppsPath\Edge` |

## Estimated Component Sizes

Based on real-world observations (useful for disk estimation):

| Component | Typical Size | Notes |
|-----------|-------------|-------|
| Orchestration scripts | ~50 MB | Base scripts, always present |
| Office (M365 Apps) | ~4 GB | Full 64-bit install with all languages |
| Defender Platform | ~500 MB | Platform update MSU |
| Defender Definitions | ~500 MB | mpam-fe.exe |
| MSRT | ~150 MB | Malicious software removal tool |
| Edge | ~150 MB | MSI installer |
| OneDrive | ~50 MB | Setup executable |
| **Total (all enabled)** | **~5.5 GB** | Content only |
| **Apps.iso** | **~5.5 GB** | Same as content |
| **Temp space** | **~2.75 GB** | oscdimg working space |
| **Required free** | **~14 GB** | Content + ISO + temp + margin |
