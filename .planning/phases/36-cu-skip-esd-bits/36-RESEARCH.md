# Phase 36: CU Skip Logic and ESD BITS Downloads - Research

**Researched:** 2026-01-28
**Domain:** PowerShell, Windows Update Catalog, BITS Transfer, Version Comparison
**Confidence:** HIGH

## Summary

This phase ports two upstream features from rbalsleyMSFT/FFU (commits 86d122a and 8229aa7):

1. **CU Skip Logic**: Parses ESD filename versions and KB article versions to skip downloading cumulative updates when the ESD already contains equal or newer updates. This optimization reduces bandwidth and build time for Windows 11 ESD builds.

2. **BITS Priority Configuration**: Adds user-configurable BITS transfer priority (Foreground/High/Normal/Low) across the build system and UI, allowing users to maximize download speed when needed.

Both features are well-implemented upstream with clear patterns that can be directly ported. The fork's modular architecture (FFU.Updates, FFU.Common.Core) will require minor adaptations but follows the same design principles.

**Primary recommendation:** Port both features using upstream implementation as the authoritative reference, with minimal changes to maintain consistency. Focus implementation in FFU.Updates module for CU skip logic and FFU.Common.Core for BITS priority configuration.

## Standard Stack

### Core (Already Present in Fork)

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| FFU.Updates module | 1.1.0 | Windows Update catalog parsing and download | Core module for update operations |
| FFU.Common.Core | 0.0.13 | Common utilities including Start-BitsTransferWithRetry | Shared download infrastructure |
| FFU.Common.Download | 0.0.4 | Multi-method download with fallback | Resilient download system |
| BuildFFUVM.ps1 | N/A | Main orchestrator script | Entry point for update downloads |
| BuildFFUVM_UI.xaml | N/A | WPF UI definition | User interface configuration |

### Supporting (PowerShell Built-in)

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Start-BitsTransfer | Built-in | BITS download cmdlet | Primary download method |
| [version] type | .NET | Version comparison | Parsing and comparing version strings |
| Invoke-WebRequest | Built-in | Catalog scraping | Microsoft Update Catalog queries |

### Upstream Commits (Reference Implementation)

| Commit | Feature | Files Changed | Status |
|--------|---------|---------------|--------|
| 86d122a | CU Skip Logic | BuildFFUVM.ps1 (+206/-41) | Production-ready |
| 8229aa7 | BITS Priority | 9 files (+121/-23) | Production-ready |

**Installation:**
No new dependencies required - all components already present in fork.

## Architecture Patterns

### Pattern 1: ESD Metadata Resolution (CU Skip Logic)

**What:** Separate ESD metadata resolution from download to enable version comparison before downloading updates.

**When to use:** When you need to parse version information from ESD files before deciding whether to download updates.

**Upstream implementation:**
```powershell
# Source: Commit 86d122a - BuildFFUVM.ps1
function Get-WindowsESDMetadata {
    param(
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,
        [ValidateSet('x86', 'x64', 'ARM64')]
        [string]$WindowsArch,
        [string]$WindowsLang,
        [ValidateSet('consumer', 'business')]
        [string]$MediaType
    )

    WriteLog "Resolving Windows $WindowsRelease ESD metadata"

    # Download and parse products.cab (existing logic)
    # Extract ESD metadata including version

    foreach ($file in $xmlContent.MCT.Catalogs.Catalog.PublishedMedia.Files.File) {
        if ($file.Architecture -eq $WindowsArch -and $file.LanguageCode -eq $WindowsLang -and $file.FilePath -like "*$clientType*") {
            $fileName = Split-Path $file.FilePath -Leaf
            $esdFilePath = Join-Path $PSScriptRoot $fileName
            $esdVersion = $null

            # Parse version from filename (e.g., "10.0.26100.1742_amd64_en-us_consumer.esd")
            if ($file.FileName -match '^([0-9]+\.[0-9]+)') {
                $esdVersion = $matches[1]
            }

            $esdMetadata = [pscustomobject]@{
                FileUrl   = $file.FilePath
                FileName  = $fileName
                LocalPath = $esdFilePath
                Version   = $esdVersion  # e.g., "10.0.26100.1742"
            }
            break
        }
    }

    return $esdMetadata
}
```

**Fork adaptation:** Move to FFU.Updates module as `Get-WindowsESDMetadata`, keeping same signature and return type.

### Pattern 2: KB Article Version Extraction

**What:** Enhance Get-KBLink to extract Windows version from KB article search results.

**When to use:** When querying Microsoft Update Catalog for cumulative updates.

**Upstream implementation:**
```powershell
# Source: Commit 86d122a - Get-KBLink enhancement
$results = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=$Name" -Headers $Headers -UserAgent $UserAgent

# Extract KB article ID and Windows version from HTML
if ($Name -notmatch 'Defender|Edge') {
    $global:LastKBArticleID = $null
    $global:LastKBWindowsVersion = $null

    # Try to match KB with version: "(KB5046613) (10.0.26100.2454)"
    if ($results.Content -match '\(KB(\d+)\)[^(<]*\(([0-9]+\.[0-9]+)\)\s*<') {
        $kbArticleID = "KB$($matches[1])"
        $global:LastKBArticleID = $kbArticleID
        $global:LastKBWindowsVersion = $matches[2]  # e.g., "10.0.26100.2454"
        WriteLog "Found KB article ID: $kbArticleID with Windows version $($matches[2])"
    }
    # Fallback to just KB ID without version
    elseif ($results.Content -match '>\s*([^\(<]+)\(KB(\d+)\)(?:\s*\([^)]+\))*\s*<') {
        $kbArticleID = "KB$($matches[2])"
        $global:LastKBArticleID = $kbArticleID
        WriteLog "Found KB article ID: $kbArticleID (no Windows version found)"
    }
}
```

**Fork adaptation:** Update existing Get-KBLink in FFU.Updates module to include version extraction logic.

### Pattern 3: Version Comparison and Skip Logic

**What:** Compare ESD version with CU version to decide whether to skip download.

**When to use:** After resolving ESD metadata and KB search results, before downloading updates.

**Upstream implementation:**
```powershell
# Source: Commit 86d122a - Version comparison
$esdVerObj = $null
$cuVerObj = $null

# Parse versions to .NET [version] objects
if ($esdVersion) { try { $esdVerObj = [version]$esdVersion } catch { } }
if ($cuKbWindowsVersion) { try { $cuVerObj = [version]$cuKbWindowsVersion } catch { } }

# Compare and skip if ESD >= CU
if ($esdVerObj -and $cuVerObj) {
    if ($esdVerObj -eq $cuVerObj -or $esdVerObj -gt $cuVerObj) {
        $skipReason = if ($esdVerObj -eq $cuVerObj) { 'matches' } else { 'is newer than' }
        WriteLog "Windows 11 ESD version $esdVersion $skipReason CU version $cuKbWindowsVersion. Skipping CU download and installation."

        # Track skipped updates for VHDX cache matching
        if ($AllowVHDXCaching -and $cuUpdateInfos -and $cuUpdateInfos.Count -gt 0) {
            foreach ($cuUpdateInfo in $cuUpdateInfos) {
                if (-not [string]::IsNullOrWhiteSpace($cuUpdateInfo.Name) -and -not $cachedIncludedUpdateNames.Contains($cuUpdateInfo.Name)) {
                    $cachedIncludedUpdateNames.Add($cuUpdateInfo.Name)
                }
            }
        }

        # Clear CU from download queue
        $cuUpdateInfos.Clear()
        $UpdateLatestCU = $false
        $CUPath = $null
    }
}
```

**Fork adaptation:** Implement in BuildFFUVM.ps1 after Get-WindowsESDMetadata call, before update download loop.

### Pattern 4: BITS Priority Configuration

**What:** Environment variable + script-level variable + parameter-based priority configuration for BITS transfers.

**When to use:** All BITS download operations throughout the system.

**Upstream implementation:**
```powershell
# Source: Commit 8229aa7 - FFU.Common.Core.psm1

# Script-level initialization
$script:BitsTransferPriority = 'Normal'
if (-not [string]::IsNullOrWhiteSpace($env:FFU_BITS_PRIORITY)) {
    $script:BitsTransferPriority = $env:FFU_BITS_PRIORITY
}

# Configuration function
function Set-BitsTransferPriority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Foreground', 'High', 'Normal', 'Low')]
        [string]$Priority
    )

    $script:BitsTransferPriority = $Priority
    try {
        Set-Item -Path Env:FFU_BITS_PRIORITY -Value $Priority -ErrorAction Stop
    }
    catch {
        WriteLog "Failed to set FFU_BITS_PRIORITY environment variable: $($_.Exception.Message)"
    }
    WriteLog "BITS transfer priority set to $Priority."
}

# Enhanced Start-BitsTransferWithRetry
function Start-BitsTransferWithRetry {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$Retries = 3,
        [ValidateSet('Foreground','High','Normal','Low')]
        [string]$Priority  # New parameter
    )

    # Priority resolution cascade: parameter -> env var -> script var -> default
    if ([string]::IsNullOrWhiteSpace($Priority)) {
        if (-not [string]::IsNullOrWhiteSpace($env:FFU_BITS_PRIORITY)) {
            $Priority = $env:FFU_BITS_PRIORITY
        }
        elseif (-not [string]::IsNullOrWhiteSpace($script:BitsTransferPriority)) {
            $Priority = $script:BitsTransferPriority
        }
        else {
            $Priority = 'Normal'
        }
    }

    # Use resolved priority in BITS transfer
    Start-BitsTransfer -Source $Source -Destination $Destination -Priority $Priority -ErrorAction Stop
}
```

**Fork adaptation:** Apply same changes to FFU.Common.Core module, add Set-BitsTransferPriority to function exports.

### Pattern 5: UI Integration for BITS Priority

**What:** ComboBox in UI's Build tab (Downloads/Network section) for priority selection.

**When to use:** User-facing configuration for download priority.

**Upstream XAML:**
```xml
<!-- Source: Commit 8229aa7 - BuildFFUVM_UI.xaml -->
<Grid Grid.Row="7" Margin="0,5">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="200"/>
        <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>
    <TextBlock Grid.Column="0" Text="BITS Priority" VerticalAlignment="Center"
               ToolTip="Controls the BITS download priority used by the UI and BuildFFUVM.ps1. Switch to Foreground to maximize download speed if needed."/>
    <ComboBox x:Name="cmbBitsPriority" Grid.Column="1" Margin="5" VerticalAlignment="Center"
              Width="150" HorizontalAlignment="Left"
              ToolTip="Controls the BITS download priority used by the UI and BuildFFUVM.ps1. Switch to Foreground to maximize download speed if needed.">
        <sys:String>Foreground</sys:String>
        <sys:String>High</sys:String>
        <sys:String>Normal</sys:String>
        <sys:String>Low</sys:String>
    </ComboBox>
</Grid>
```

**Fork adaptation:** Add to BuildFFUVM_UI.xaml in Build tab, wire up in FFUUI.Core handlers.

### Anti-Patterns to Avoid

- **Don't hardcode version strings**: Always use `[version]` type for comparison to handle edge cases correctly
- **Don't ignore parse failures**: Upstream uses try/catch around `[version]$string` and falls back to downloading CU on failure (safe default)
- **Don't modify VHDX cache logic carelessly**: The `$cachedIncludedUpdateNames` tracking is critical for cache matching when updates are skipped
- **Don't add global state unnecessarily**: Use `$global:LastKBWindowsVersion` only because Get-KBLink already uses `$global:LastKBArticleID` pattern

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Version parsing | Custom regex for major.minor.build.revision | `[version]` type with try/catch | .NET handles edge cases, culture-aware |
| BITS priority propagation | Custom config passing through call stack | Environment variable + script variable cascade | Upstream pattern works in ThreadJob contexts |
| ESD filename parsing | Complex regex for all filename formats | Simple `'^([0-9]+\.[0-9]+)'` match | Upstream tested this extensively, robust |
| Update catalog scraping | New HTML parsing logic | Enhance existing Get-KBLink regex | Catalog HTML structure is stable |

**Key insight:** Upstream spent significant effort on edge cases (version parse failures, missing versions, VHDX cache tracking). Don't simplify these patterns - they exist for good reasons discovered through production use.

## Common Pitfalls

### Pitfall 1: Version Parse Failures Breaking Builds

**What goes wrong:** `[version]$string` throws exceptions on malformed version strings, potentially breaking the build.

**Why it happens:** ESD filenames or KB search results might not contain parseable versions in all cases.

**How to avoid:** Always wrap `[version]` casts in try/catch, fall back to downloading CU on parse failure.

**Warning signs:** Build fails when specific Windows versions/updates are selected, errors mention "Cannot convert value to type System.Version".

**Upstream solution:**
```powershell
$esdVerObj = $null
if ($esdVersion) {
    try {
        $esdVerObj = [version]$esdVersion
    } catch {
        # Silent failure, $esdVerObj remains $null
    }
}

# Later: only skip if BOTH versions parsed successfully
if ($esdVerObj -and $cuVerObj) {
    # comparison logic
}
```

### Pitfall 2: VHDX Cache Mismatches After CU Skip

**What goes wrong:** When CU is skipped due to version match, VHDX cache doesn't recognize that the update is implicitly included in the ESD, leading to unnecessary VHDX rebuilds.

**Why it happens:** Cache matching compares applied update filenames, but skipped updates have no filename.

**How to avoid:** Track skipped update names in `$cachedIncludedUpdateNames` list, include them in cache comparison logic.

**Warning signs:** VHDX caching not working when using recent ESD files, builds always recreate VHDX even when updates haven't changed.

**Upstream solution:**
```powershell
# When skipping CU, track its name for cache matching
if ($AllowVHDXCaching -and $cuUpdateInfos -and $cuUpdateInfos.Count -gt 0) {
    foreach ($cuUpdateInfo in $cuUpdateInfos) {
        if (-not [string]::IsNullOrWhiteSpace($cuUpdateInfo.Name) -and -not $cachedIncludedUpdateNames.Contains($cuUpdateInfo.Name)) {
            $cachedIncludedUpdateNames.Add($cuUpdateInfo.Name)
        }
    }
}

# Later in cache comparison
$requiredUpdateFileNames = @()
if ($requiredUpdates.Count -gt 0) {
    $requiredUpdateFileNames += $requiredUpdates | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_.Name)) { $_.Name }
        elseif (-not [string]::IsNullOrWhiteSpace($_.Url)) { ($_.Url -split '/')[-1] }
    }
}
if ($cachedIncludedUpdateNames.Count -gt 0) {
    $requiredUpdateFileNames += $cachedIncludedUpdateNames  # Include skipped updates
}
```

### Pitfall 3: BITS Priority Not Propagating to Background Jobs

**What goes wrong:** UI sets BITS priority, but background job (Start-ThreadJob) doesn't respect it.

**Why it happens:** Environment variables don't automatically propagate to ThreadJobs.

**How to avoid:** Use environment variable for propagation, set it both in parent process and pass it through job initialization.

**Warning signs:** UI shows selected priority, but build log shows "Normal" priority being used for downloads.

**Upstream solution:**
```powershell
# In UI handler (FFUUI.Core.Handlers.psm1)
Set-BitsTransferPriority -Priority $selectedPriority

# Set-BitsTransferPriority updates both script var and env var
$script:BitsTransferPriority = $Priority
Set-Item -Path Env:FFU_BITS_PRIORITY -Value $Priority

# In Start-BitsTransferWithRetry (FFU.Common.Core.psm1)
# Priority resolution checks env var first
if ([string]::IsNullOrWhiteSpace($Priority)) {
    if (-not [string]::IsNullOrWhiteSpace($env:FFU_BITS_PRIORITY)) {
        $Priority = $env:FFU_BITS_PRIORITY  # Picks up from environment
    }
}
```

### Pitfall 4: Windows 10 or ISO-Based Builds Trying to Use ESD Logic

**What goes wrong:** CU skip logic runs for Windows 10 or ISO-based builds where ESD metadata doesn't apply.

**Why it happens:** ESD metadata resolution only works for Windows 11 MCT downloads.

**How to avoid:** Upstream guards CU skip logic with `if ($WindowsRelease -eq 11 -and -not $ISOPath)`.

**Warning signs:** Errors about missing ESD metadata when building Windows 10 or using custom ISOs.

**Upstream solution:**
```powershell
# Only resolve ESD metadata for Windows 11 ESD builds
if ($WindowsRelease -eq 11 -and -not $ISOPath) {
    try {
        $esdMetadata = Get-WindowsESDMetadata -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsLang $WindowsLang -MediaType $mediaType
        if ($esdMetadata -and $esdMetadata.Version) {
            $esdVersion = $esdMetadata.Version
            WriteLog "ESD version identified as $esdVersion"
        }
    }
    catch {
        WriteLog "Failed to resolve Windows ESD metadata: $($_.Exception.Message)"
    }
}
```

## Code Examples

### Example 1: Full CU Skip Logic Integration

```powershell
# Source: Upstream commit 86d122a - BuildFFUVM.ps1 (lines 5621-5763)

# Initialize tracking variables
$esdMetadata = $null
$esdVersion = $null
$cuKbWindowsVersion = $null
$cupKbWindowsVersion = $null
$cachedIncludedUpdateNames = [System.Collections.Generic.List[string]]::new()

# Step 1: Resolve ESD metadata (Windows 11 only)
if ($WindowsRelease -eq 11 -and -not $ISOPath) {
    try {
        $esdMetadata = Get-WindowsESDMetadata -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsLang $WindowsLang -MediaType $mediaType
        if ($esdMetadata -and $esdMetadata.Version) {
            $esdVersion = $esdMetadata.Version
            WriteLog "ESD version identified as $esdVersion"
        }
    }
    catch {
        WriteLog "Failed to resolve Windows ESD metadata: $($_.Exception.Message)"
    }
}

# Step 2: Search for CU updates (existing logic, now captures version)
if ($UpdateLatestCU -and -not $UpdatePreviewCU) {
    WriteLog "`$UpdateLatestCU is set to true, checking for latest CU"
    # ... construct $Name ...
    WriteLog "Searching for $Name from Microsoft Update Catalog"
    (Get-UpdateFileInfo -Name $Name) | ForEach-Object { $cuUpdateInfos.Add($_) }
    $cuKbArticleId = $global:LastKBArticleID
    $cuKbWindowsVersion = $global:LastKBWindowsVersion  # New: capture version
}

# Step 3: Parse versions and compare
$esdVerObj = $null
$cuVerObj = $null
if ($esdVersion) { try { $esdVerObj = [version]$esdVersion } catch { } }
if ($cuKbWindowsVersion) { try { $cuVerObj = [version]$cuKbWindowsVersion } catch { } }

# Step 4: Skip CU if ESD >= CU
if ($esdVerObj -and $cuVerObj) {
    if ($esdVerObj -eq $cuVerObj -or $esdVerObj -gt $cuVerObj) {
        $skipReason = if ($esdVerObj -eq $cuVerObj) { 'matches' } else { 'is newer than' }
        WriteLog "Windows 11 ESD version $esdVersion $skipReason CU version $cuKbWindowsVersion. Skipping CU download and installation."

        # Track for VHDX cache
        if ($AllowVHDXCaching -and $cuUpdateInfos -and $cuUpdateInfos.Count -gt 0) {
            foreach ($cuUpdateInfo in $cuUpdateInfos) {
                if (-not [string]::IsNullOrWhiteSpace($cuUpdateInfo.Name) -and -not $cachedIncludedUpdateNames.Contains($cuUpdateInfo.Name)) {
                    $cachedIncludedUpdateNames.Add($cuUpdateInfo.Name)
                }
            }
        }

        # Clear from download queue
        $cuUpdateInfos.Clear()
        $UpdateLatestCU = $false
        $CUPath = $null
    }
}
```

### Example 2: BITS Priority Resolution Cascade

```powershell
# Source: Upstream commit 8229aa7 - FFU.Common.Core.psm1

# Priority resolution cascade in Start-BitsTransferWithRetry
function Start-BitsTransferWithRetry {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$Retries = 3,
        [ValidateSet('Foreground','High','Normal','Low')]
        [string]$Priority
    )

    # Cascade: parameter -> env var -> script var -> default
    if ([string]::IsNullOrWhiteSpace($Priority)) {
        if (-not [string]::IsNullOrWhiteSpace($env:FFU_BITS_PRIORITY)) {
            $Priority = $env:FFU_BITS_PRIORITY
            WriteLog "Using BITS priority from environment: $Priority"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($script:BitsTransferPriority)) {
            $Priority = $script:BitsTransferPriority
            WriteLog "Using BITS priority from script variable: $Priority"
        }
        else {
            $Priority = 'Normal'
            WriteLog "Using default BITS priority: Normal"
        }
    }

    # Use in BITS transfer
    Start-BitsTransfer -Source $Source -Destination $Destination -Priority $Priority -ErrorAction Stop
}
```

### Example 3: UI BITS Priority Handler

```powershell
# Source: Upstream commit 8229aa7 - FFUUI.Core.Handlers.psm1

# When user changes BITS priority in UI
$cmbBitsPriority.Add_SelectionChanged({
    $selectedPriority = $cmbBitsPriority.SelectedItem
    if (-not [string]::IsNullOrWhiteSpace($selectedPriority)) {
        try {
            Set-BitsTransferPriority -Priority $selectedPriority
            WriteLog "BITS transfer priority changed to: $selectedPriority"
        }
        catch {
            WriteLog "ERROR: Failed to set BITS priority: $($_.Exception.Message)"
        }
    }
})

# Load priority from config on UI initialization
if ($config.BitsPriority) {
    $cmbBitsPriority.SelectedItem = $config.BitsPriority
}
else {
    $cmbBitsPriority.SelectedItem = 'Normal'  # Default
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Always download CU for Windows 11 builds | Check ESD version first, skip if current | Dec 2025 (86d122a) | Saves 3-4GB bandwidth per build when using recent ESD |
| Hardcoded BITS Normal priority | User-configurable priority (Foreground/High/Normal/Low) | Nov 2025 (8229aa7) | Users can maximize download speed when needed |
| Always remove KB folder after build | Conditionally remove based on $RemoveUpdates parameter | Dec 2025 (86d122a) | Reduces redundant downloads across multiple builds |

**Deprecated/outdated:**
- Unconditional CU downloads - now outdated for Windows 11 ESD builds, upstream checks version first
- BITS Normal priority hardcoded in Start-BitsTransferWithRetry - now configurable via parameter/env var

## Open Questions

1. **Equal Version Handling (>= vs >)**
   - What we know: Upstream uses `$esdVerObj -eq $cuVerObj -or $esdVerObj -gt $cuVerObj` (skips on equal)
   - What's unclear: Should equal versions skip (assuming ESD already includes it) or download (to ensure it's applied)?
   - Recommendation: Follow upstream logic (skip on equal) - if ESD and CU have same version, ESD already includes that CU

2. **BITS Fallback Chain Integration**
   - What we know: Fork has FFU.Common.Download with multi-method fallback (BITS -> WebRequest -> WebClient -> curl)
   - What's unclear: Should BITS priority apply to just BITS, or influence fallback method order?
   - Recommendation: Apply priority only to BITS method, don't change fallback order - fallback is for when BITS fails entirely

3. **Progress Logging Detail Level**
   - What we know: Context says "progress logging at regular intervals (e.g., every 30 seconds) with bytes transferred and percentage"
   - What's unclear: Upstream commit 8229aa7 doesn't show ESD progress logging changes in the diff
   - Recommendation: Implement basic progress logging using BITS job progress properties (`BytesTransferred`, `BytesTotal`), log every 30 seconds

4. **CU Skip Override Mechanism**
   - What we know: Context says "follow upstream approach for any CU skip override mechanism"
   - What's unclear: Upstream commit 86d122a doesn't add a `-SkipCUVersionCheck` or similar parameter
   - Recommendation: Don't add override parameter - version comparison is deterministic and safe. If users want to force CU download, they can delete the ESD file.

## Sources

### Primary (HIGH confidence)

- **Upstream commit 86d122a** (`https://github.com/rbalsleyMSFT/FFU/commit/86d122aacf8274aa61a070e8ccdd5da8313a2848`) - Full CU skip logic implementation, tested in production
- **Upstream commit 8229aa7** (`https://github.com/rbalsleyMSFT/FFU/commit/8229aa73fe6b591680a6b1fb79227ea1a8874bc0`) - BITS priority configuration, tested in production
- **Fork codebase** (`C:\claude\FFUBuilder\FFUDevelopment`) - Current module structure, coding patterns, test examples
- **Start-BitsTransfer documentation** ([Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/bitstransfer/start-bitstransfer?view=windowsserver2025-ps)) - Authoritative BITS priority levels documentation

### Secondary (MEDIUM confidence)

- **PowerShell version comparison** ([Alkane Solutions](https://www.alkanesolutions.co.uk/2022/08/26/compare-version-numbers-with-powershell/)) - .NET [version] type usage patterns
- **BITS usage guide** ([Windows OS Hub](https://woshub.com/copying-large-files-using-bits-and-powershell/)) - BITS transfer best practices and priority behavior

### Tertiary (LOW confidence)

- N/A - All critical information sourced from HIGH/MEDIUM confidence sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components already present in fork, upstream commits production-tested
- Architecture: HIGH - Upstream implementation is authoritative reference, patterns proven in production
- Pitfalls: HIGH - Pitfalls extracted from upstream code (error handling, cache tracking, guards)

**Research date:** 2026-01-28
**Valid until:** 2026-02-28 (30 days - stable feature set, unlikely to change)

**Key findings for planner:**
1. Port both features as-is from upstream with minimal changes
2. Focus on FFU.Updates module for CU skip, FFU.Common.Core for BITS priority
3. Version comparison must handle parse failures gracefully (try/catch + safe default)
4. VHDX cache tracking is critical - don't simplify the `$cachedIncludedUpdateNames` logic
5. BITS priority uses environment variable for ThreadJob propagation
6. UI integration requires XAML changes + handler wiring in FFUUI.Core
7. Testing should cover version parse failures, equal versions, missing versions, VHDX cache matching
