# Phase 46: FFU.ArtifactScanner Module - Research

**Researched:** 2026-03-14
**Domain:** PowerShell module creation, DISM FFU metadata extraction, file system scanning
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Artifact Catalog**
- Always scan for all 7 artifact types regardless of config flags: FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO
- Missing optional artifacts show as informational "Not found" status, not errors
- Discover ALL .ffu files in the FFU folder, flag newest as primary
- Drivers treated as single artifact (folder-level): found/missing, total size, file count
- Deploy ISO only (no Capture ISO) — USB Mode is for deployment
- FFUDevelopmentPath only as input — per-artifact path overrides deferred to Phase 49
- Architecture-specific unattend scanning: look for unattend_x64.xml and unattend_arm64.xml (matches BuildFFUVM.ps1 lines 1504-1515)
- Deploy ISO architecture parsed from filename pattern (WinPE_FFU_Deploy_{arch}.iso)
- Apps.iso: existence + file size only, no ISO mount validation
- Autopilot: any .json files in Autopilot folder (matches existing validation at BuildFFUVM.ps1 line 2107)
- PPKG: any .ppkg files in PPKG folder, report count + paths + sizes
- Find-FFUArtifacts returns a single [ArtifactManifest] object (not array or hashtable)
- Graceful degradation on errors: mark individual artifacts as 'Error' status with message, continue scanning remaining artifacts

**FFU Metadata Extraction**
- DISM primary via Get-WindowsImage, filename parsing fallback if DISM fails
- Metadata extracted automatically during Find-FFUArtifacts (not lazy/separate)
- Extract metadata for ALL discovered FFU files, not just primary
- Core fields: WindowsVersion, WindowsSKU, Architecture, ImageName, BuildDate
- On DISM failure: return partial metadata from filename with MetadataSource='Filename' and ErrorMessage property
- Get-ArtifactMetadata is a public exported function (testable independently, callable by Phase 49)
- WIMMount prerequisite: reuse existing Test-FFUWimMount from FFU.Preflight (fltmc check + auto-repair), call once at scan start, cache result, skip DISM if unavailable

**Staleness & Compatibility**
- Staleness: age in days from file LastWriteTime, returned as integer AgeDays property — no tiered labels baked into scanner
- Compatibility: architecture mismatch only (FFU arch vs Deploy ISO arch)
- Mismatch severity: warning level (not blocking error) — scanner informs, doesn't gatekeep
- Compatibility checks run automatically during Find-FFUArtifacts
- Each warning includes human-readable Message property (e.g., "FFU architecture (ARM64) does not match Deploy ISO architecture (x64)")

**Output Data Model**
- PowerShell classes (not PSCustomObject) — matches FFU.Common.Classes.psm1 and FFU.Hypervisor/Classes/ pattern
- [ArtifactStatus] enum: Found, Missing, Error, Degraded
- [ArtifactType] enum: FFU, DeployISO, Drivers, PPKG, Unattend, Autopilot, AppsISO
- Multi-file artifacts: Files array (path, size, lastWrite) + summary properties (FileCount, TotalSizeBytes)
- Compatibility warnings: top-level Warnings array on ArtifactManifest (array of [CompatibilityWarning] with Severity, Message, AffectedArtifacts)
- Readiness summary: FoundCount, MissingCount, ErrorCount, IsReady boolean (true if FFU + DeployISO found, no errors)
- Scan provenance: ScanTimestamp ([DateTime]) and BasePath on manifest

**Module Structure**
- Classes/ subfolder with ArtifactScanner.Classes.psm1 (enums + data classes)
- Single FFU.ArtifactScanner.psm1 with all public functions
- Located at Modules/FFU.ArtifactScanner/

### Claude's Discretion
- Whether to add ConvertTo/ConvertFrom JSON serialization helpers (depends on how native ConvertTo-Json handles the classes)
- Internal helper function organization within the single .psm1
- Exact class property types for edge cases (e.g., nullable vs default values)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DISC-01 | USB Mode auto-detects all deployable artifacts from FFUDevelopmentPath on activation (FFU, boot ISO, drivers, PPKG, unattend, Autopilot, Apps.iso) | Find-FFUArtifacts function implementing full 7-type catalog; artifact path conventions from BuildFFUVM.ps1 lines 1830-1867 |
| VALID-01 | USB Mode displays found/missing status for each artifact with path and file size | ArtifactResult class with Status, FilePath, FileSizeBytes properties; [ArtifactStatus] enum |
| VALID-02 | USB Mode extracts and displays FFU metadata (Windows version, SKU, architecture) via DISM | Get-ArtifactMetadata using Get-WindowsImage; WIMMount prerequisite validation via Test-FFUWimMount |
| VALID-03 | USB Mode cross-validates artifact compatibility (architecture mismatch warning between FFU and boot ISO) | Test-ArtifactCompatibility; [CompatibilityWarning] class; arch extraction from DISM result and ISO filename |
| VALID-04 | USB Mode displays staleness indicator per artifact (age relative to current date) | AgeDays integer from [DateTime]::Now - FileInfo.LastWriteTime on each ArtifactResult |
</phase_requirements>

---

## Summary

Phase 46 creates `FFU.ArtifactScanner` — a new PowerShell module located at `Modules/FFU.ArtifactScanner/` that discovers, validates, and cross-checks deployment artifacts from an `FFUDevelopmentPath`. It defines the data contract (PowerShell classes and enums) consumed by Phase 47 (pipeline), Phase 48 (UI columns), and Phase 49 (controls). The module must be entirely self-contained and testable without an actual FFU build environment.

The implementation leverages two well-established patterns from the existing codebase: the `FFU.Hypervisor` Classes/ subfolder pattern for class organization (dot-sourcing `.ps1` files from a `Classes/` subfolder in the module root), and the `Test-FFUWimMount` function from `FFU.Preflight` for gating DISM operations behind WIMMount filter driver validation. The `Get-WindowsImage` DISM cmdlet works directly on `.ffu` files without mounting — this is the primary metadata extraction mechanism, with filename-pattern parsing as the fallback.

The module introduces no new external dependencies beyond `FFU.Core` (for WriteLog and error handling patterns) and `FFU.Preflight` (for `Test-FFUWimMount`). All artifact path conventions are derived from `BuildFFUVM.ps1` lines 1830-1867 which are the canonical path defaults already in production.

**Primary recommendation:** Model the module structure on `FFU.Hypervisor` (Classes/ subfolder + dot-sourced PS1 files), use `Get-WindowsImage -ImagePath <ffu>` for DISM metadata, reuse `Test-FFUWimMount` without modification, and implement the 7 artifact type scanners as private helper functions called by the single public `Find-FFUArtifacts` entry point.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PowerShell DISM module | Built-in | `Get-WindowsImage` for FFU metadata | Already used throughout FFU.Imaging; works on .ffu without mounting |
| FFU.Core | 1.0.24 | WriteLog, Invoke-WithErrorHandling, error handling | Foundation dependency for all FFU modules |
| FFU.Preflight | 1.6.0 | Test-FFUWimMount with auto-repair | Phase 44 established this as the WIMMount gate pattern |
| Pester 5.x | 5.x | Unit testing | Project standard per config.json test_requirements |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| System.IO.FileInfo | .NET built-in | File size, LastWriteTime for staleness | Direct .NET access avoids ThreadJob cmdlet issues |
| System.DateTime | .NET built-in | ScanTimestamp, AgeDays calculation | `[DateTime]::Now` per ThreadJob compatibility rules |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| PowerShell classes | PSCustomObject | Classes give type safety for Phase 47/48/49 consumers; PSCustomObject is untyped |
| `[DateTime]::Now` | `Get-Date` | `Get-Date` fails in ThreadJob runspaces (known project issue, documented v0.0.9) |
| `Test-FFUWimMount` (reuse) | Inline fltmc check | Reuse ensures auto-repair logic stays in one place; inline would duplicate Phase 44 work |

**Installation:** No new packages. Module is authored in-repo at `FFUDevelopment/Modules/FFU.ArtifactScanner/`.

---

## Architecture Patterns

### Recommended Project Structure
```
FFUDevelopment/Modules/FFU.ArtifactScanner/
├── Classes/
│   └── ArtifactScanner.Classes.ps1     # Enums + data classes (dot-sourced)
├── FFU.ArtifactScanner.psm1            # Module root: loads classes + public functions
└── FFU.ArtifactScanner.psd1            # Manifest: RequiredModules, FunctionsToExport, GUID
```

This mirrors the `FFU.Hypervisor` structure (Classes/ subfolder with dot-sourced `.ps1` files).

### Pattern 1: Classes/ Subfolder with Dot-Sourcing

**What:** Separate class definitions into `Classes/*.ps1` files; the root `.psm1` dot-sources them in dependency order.
**When to use:** Any module with PowerShell class definitions that downstream modules need access to.
**Example:**
```powershell
# Source: FFU.Hypervisor/FFU.Hypervisor.psm1 lines 27-43 (established pattern)
$script:ModuleRoot = $PSScriptRoot
$script:ClassesPath = Join-Path $ModuleRoot 'Classes'

# Load classes in dependency order (enums first, then classes that use them)
. (Join-Path $ClassesPath 'ArtifactScanner.Classes.ps1')
```

### Pattern 2: WIMMount Gate with Cached Result

**What:** Call `Test-FFUWimMount` once at the start of `Find-FFUArtifacts`, cache the result in a script-scoped variable, and skip DISM calls if WIMMount is unavailable.
**When to use:** Any code path that calls `Get-WindowsImage` or other DISM cmdlets.
**Example:**
```powershell
# Validate WIMMount once — skip DISM for ALL FFU files if unavailable
$wimMountResult = Test-FFUWimMount
$script:WimMountAvailable = ($wimMountResult.Status -eq 'Passed')

if (-not $script:WimMountAvailable) {
    # Fall through to filename-based metadata extraction
    WriteLog "WARNING: WIMMount unavailable — FFU metadata will use filename parsing fallback"
}
```

### Pattern 3: Graceful Per-Artifact Error Isolation

**What:** Wrap each artifact scan in `try/catch`; on failure set `Status = [ArtifactStatus]::Error` with an `ErrorMessage` string, then `continue` to the next artifact.
**When to use:** All 7 artifact type scanners. Matches `Invoke-BuildPhase` graceful degradation pattern from FFU.Core v1.0.22.
**Example:**
```powershell
try {
    $ffu = [FFUArtifactResult]::new()
    $ffu.ArtifactType = [ArtifactType]::FFU
    # ... scan logic
}
catch {
    $ffu.Status = [ArtifactStatus]::Error
    $ffu.ErrorMessage = $_.Exception.Message
    WriteLog "ArtifactScanner: FFU scan failed — $($_.Exception.Message)"
}
```

### Pattern 4: `[DateTime]::Now` for ThreadJob Compatibility

**What:** Use `[DateTime]::Now` instead of `Get-Date` everywhere.
**When to use:** All timestamp and staleness calculations. `Get-Date` may be unavailable in ThreadJob runspaces (project-wide known issue, fixed in FFU.Common v0.0.9).
**Example:**
```powershell
# AgeDays calculation — ThreadJob safe
$ageDays = ([DateTime]::Now - $fileInfo.LastWriteTime).TotalDays
$result.AgeDays = [int][Math]::Floor($ageDays)
```

### Pattern 5: RequiredModules Hashtable Format

**What:** Declare module dependencies using the standardized hashtable format in `.psd1`.
**When to use:** All new module manifests in this project.
**Example:**
```powershell
# Source: FFU.Core.psd1, FFU.Hypervisor.psd1 (project standard)
RequiredModules = @(
    @{ModuleName = 'FFU.Core';      ModuleVersion = '1.0.0'},
    @{ModuleName = 'FFU.Preflight'; ModuleVersion = '1.0.0'}
)
```

### Anti-Patterns to Avoid
- **PSCustomObject instead of classes:** Downstream Phase 47/48/49 need typed properties for data binding and pipeline. PSCustomObject is untyped and can't enforce schema.
- **Lazy DISM metadata:** CONTEXT.md locked metadata extraction as eager (during Find-FFUArtifacts). Implementing lazy loading would violate the data contract downstream phases depend on.
- **Returning an array:** `Find-FFUArtifacts` must return a single `[ArtifactManifest]` object. Arrays don't carry the Warnings, Readiness, and ScanTimestamp fields.
- **`Get-Date` calls:** Use `[DateTime]::Now`. `Get-Date` fails in ThreadJob runspaces.
- **`Write-Warning` calls:** Use safe logging pattern (`if ($function:WriteLog) { WriteLog "WARNING: ..." }` else fallback). `Write-Warning` may be unavailable in ThreadJob runspaces.
- **Hardcoding artifact paths:** Derive all paths from `$FFUDevelopmentPath` using `Join-Path`. The canonical defaults are in BuildFFUVM.ps1 lines 1830-1867.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WIMMount filter validation | Custom fltmc parser | `Test-FFUWimMount` from FFU.Preflight | Phase 44 built this with auto-repair, registry checks, service restart |
| Error handling wrapper | Custom try/catch boilerplate | `Invoke-WithErrorHandling` from FFU.Core | Handles retry logic, cleanup registration, structured error output |
| ThreadJob-safe logging | Custom console writes | `WriteLog` with `$function:WriteLog` guard | Project-wide pattern for all modules since FFU.Common v0.0.12 |
| DISM image inspection | Custom binary parsing of FFU | `Get-WindowsImage -ImagePath` | DISM handles FFU format natively; custom parsing is fragile |

**Key insight:** `Get-WindowsImage` works directly on `.ffu` files without mounting. It returns `ImageName`, `ImageDescription`, `Architecture` (0=x86, 9=amd64/x64, 12=arm64), `Version`, `EditionId`, `InstallationType`, and `Languages`. This is the only DISM call needed for metadata — no mount/dismount required.

---

## Common Pitfalls

### Pitfall 1: Get-WindowsImage Architecture Encoding
**What goes wrong:** `Get-WindowsImage` returns `Architecture` as an integer (0=x86, 9=x64/amd64, 12=arm64), not a string. Code that compares this directly to a string like `"x64"` will always return false.
**Why it happens:** The DISM module uses the same integer encoding as the Windows PE architecture constants.
**How to avoid:** Map the integer to a canonical string in `Get-ArtifactMetadata`. Use a `switch` statement: `0 -> 'x86'`, `9 -> 'x64'`, `12 -> 'arm64'`.
**Warning signs:** Compatibility check always reports mismatch even when FFU and ISO are the same arch.

### Pitfall 2: Import-Module DISM Required Before Get-WindowsImage
**What goes wrong:** `Get-WindowsImage` may not be available if the DISM module isn't loaded. In some runspace contexts the module is present but not auto-loaded.
**Why it happens:** DISM is not in the default module auto-load path in all contexts (e.g., background jobs).
**How to avoid:** Always call `Import-Module DISM -ErrorAction Stop` before `Get-WindowsImage`. Per CONTEXT.md: "All DISM calls run with explicit `Import-Module DISM`."
**Warning signs:** `Get-WindowsImage: The term 'Get-WindowsImage' is not recognized` error in job contexts.

### Pitfall 3: WIMMount Required for Get-WindowsImage on FFU Files
**What goes wrong:** `Get-WindowsImage -ImagePath <ffu>` silently fails or returns `DismInitialize failed. Error code = 0x80004005` if WIMMount filter driver is not loaded, even though the FFU is not being mounted.
**Why it happens:** DISM initializes WIMMount even for read-only metadata operations on FFU files.
**How to avoid:** Always call `Test-FFUWimMount` before any `Get-WindowsImage` call. Cache the result; if unavailable, skip DISM and fall back to filename parsing.
**Warning signs:** DISM calls returning 0x80004005 or hanging with no output.

### Pitfall 4: PowerShell Class Cross-Scope Type Availability
**What goes wrong:** Downstream code (Phase 47/48/49) calls `[ArtifactManifest]::new()` or uses `-is [ArtifactManifest]` and gets `Unable to find type [ArtifactManifest]`.
**Why it happens:** PowerShell module classes are not exported to the caller's scope — only functions defined with `function` keyword are exported. This is a known project issue documented in FFU.Hypervisor v1.1.4.
**How to avoid:** Export factory functions for cross-scope class instantiation: e.g., `New-ArtifactManifest`. This is how `FFU.Hypervisor` handles `New-VMConfiguration`. For type checking, accept `[object]` parameters (see `Test-VMStateOff` pattern in FFU.Hypervisor v1.1.15).
**Warning signs:** Downstream code fails with "Unable to find type" errors.

### Pitfall 5: ConvertTo-Json Depth Limitation on Class Instances
**What goes wrong:** `ConvertTo-Json $manifest` returns `{}` or truncated output for nested class properties.
**Why it happens:** `ConvertTo-Json` default depth is 2. `ArtifactManifest` has nested `ArtifactResult` objects with `Files` arrays — depth 3+.
**How to avoid:** If JSON serialization helpers are added (Claude's discretion item), always use `-Depth 10` or higher. Consider whether `ConvertTo-Json` handles PowerShell class instances at all in PS 5.1 (it does in PS 7+). Project minimum is PS 7.0 (`PowerShellVersion = '7.0'` in all manifests).
**Warning signs:** Phase 47 pipeline can't round-trip the manifest through JSON.

### Pitfall 6: Staleness Calculation for Folder Artifacts
**What goes wrong:** `AgeDays` for Drivers (folder-level artifact) is calculated from folder `LastWriteTime`, which updates when any file inside changes — but not when files are only read. This can show "0 days old" even for old driver sets.
**Why it happens:** File system folder timestamps are unreliable for detecting content age.
**How to avoid:** For folder artifacts (Drivers), use the newest `.LastWriteTime` among all files in the folder (`Get-ChildItem -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1`). Document this in code comments.
**Warning signs:** Drivers folder always shows 0 days old even after months of no updates.

---

## Code Examples

Verified patterns from existing codebase:

### Get-WindowsImage on FFU File (DISM Metadata Extraction)
```powershell
# Source: DISM module built-in; confirmed by project-wide DISM usage pattern
# Note: Architecture is returned as integer — map to string
Import-Module DISM -ErrorAction Stop
$imageInfo = Get-WindowsImage -ImagePath 'C:\FFUDevelopment\FFU\MyImage.ffu' -Index 1
# $imageInfo.Architecture => 9 (x64), 12 (arm64), 0 (x86)
# $imageInfo.Version       => '10.0.22621.xxx'
# $imageInfo.EditionId     => 'Professional'
# $imageInfo.ImageName     => 'Windows 11 Pro'
```

### Artifact Path Conventions (from BuildFFUVM.ps1 lines 1830-1867)
```powershell
# Source: BuildFFUVM.ps1 lines 1842-1867 — canonical default paths
$FFUCaptureLocation = "$FFUDevelopmentPath\FFU"
$DeployISO          = "$FFUDevelopmentPath\WinPE_FFU_Deploy_$WindowsArch.iso"
$DriversFolder      = "$FFUDevelopmentPath\Drivers"
$PPKGFolder         = "$FFUDevelopmentPath\PPKG"
$UnattendFolder     = "$FFUDevelopmentPath\Unattend"
$AutopilotFolder    = "$FFUDevelopmentPath\Autopilot"
$AppsISO            = "$FFUDevelopmentPath\Apps\Apps.iso"
# Unattend arch-specific files (BuildFFUVM.ps1 lines 1504-1515):
$unattendX64  = Join-Path $UnattendFolder 'unattend_x64.xml'
$unattendArm64 = Join-Path $UnattendFolder 'unattend_arm64.xml'
```

### Architecture Integer-to-String Mapping
```powershell
# Source: DISM architecture encoding (Windows PE constants)
function ConvertTo-ArchitectureString {
    param([int]$ArchInt)
    switch ($ArchInt) {
        0  { return 'x86' }
        9  { return 'x64' }
        12 { return 'arm64' }
        default { return "Unknown($ArchInt)" }
    }
}
```

### Deploy ISO Architecture from Filename
```powershell
# Source: BuildFFUVM.ps1 line 1842 pattern: WinPE_FFU_Deploy_{arch}.iso
# Parse architecture from filename
$isoFile = Get-Item -Path "$FFUDevelopmentPath\WinPE_FFU_Deploy_x64.iso"
if ($isoFile.Name -match 'WinPE_FFU_Deploy_(.+)\.iso') {
    $isoArch = $Matches[1]   # 'x64' or 'arm64'
}
```

### WIMMount Gate Pattern (from FFU.Core v1.0.23 and FFU.Preflight)
```powershell
# Source: FFU.Preflight.psm1 Test-FFUWimMount; FFU.Core Test-DismReady usage
# Call once, cache result, skip DISM if unavailable
$wimMountResult = Test-FFUWimMount -AttemptRemediation:$true
$wimMountAvailable = ($wimMountResult.Status -eq 'Passed')
if (-not $wimMountAvailable) {
    WriteLog "WARNING: WIMMount unavailable — skipping DISM metadata extraction"
}
```

### PowerShell Class with Enum (FFU.Hypervisor VMConfiguration pattern)
```powershell
# Source: FFU.Hypervisor/Classes/VMConfiguration.ps1 (dot-sourced pattern)
# ArtifactScanner.Classes.ps1 follows same structure
enum ArtifactStatus { Found; Missing; Error; Degraded }
enum ArtifactType   { FFU; DeployISO; Drivers; PPKG; Unattend; Autopilot; AppsISO }

class ArtifactFileEntry {
    [string]$FilePath
    [long]$FileSizeBytes
    [DateTime]$LastWriteTime
}

class FFUMetadata {
    [string]$WindowsVersion
    [string]$WindowsSKU
    [string]$Architecture
    [string]$ImageName
    [DateTime]$BuildDate
    [string]$MetadataSource   # 'DISM' or 'Filename'
    [string]$ErrorMessage     # populated on DISM failure
}

class ArtifactResult {
    [ArtifactType]$ArtifactType
    [ArtifactStatus]$Status
    [string]$ErrorMessage
    [int]$AgeDays
    # Single-file artifacts
    [string]$FilePath
    [long]$FileSizeBytes
    [DateTime]$LastWriteTime
    # Multi-file artifacts
    [System.Collections.Generic.List[ArtifactFileEntry]]$Files
    [int]$FileCount
    [long]$TotalSizeBytes
    # FFU-specific
    [bool]$IsPrimary          # true for newest FFU
    [FFUMetadata]$Metadata
    # Constructor initializes Files list
    ArtifactResult() { $this.Files = [System.Collections.Generic.List[ArtifactFileEntry]]::new() }
}

class CompatibilityWarning {
    [string]$Severity         # 'Warning' (not blocking)
    [string]$Message
    [string[]]$AffectedArtifacts
}

class ArtifactManifest {
    [string]$BasePath
    [DateTime]$ScanTimestamp
    [ArtifactResult[]]$FFUFiles
    [ArtifactResult]$DeployISO
    [ArtifactResult]$Drivers
    [ArtifactResult[]]$PPKGFiles
    [ArtifactResult[]]$UnattendFiles
    [ArtifactResult[]]$AutopilotFiles
    [ArtifactResult]$AppsISO
    [CompatibilityWarning[]]$Warnings
    # Readiness summary
    [int]$FoundCount
    [int]$MissingCount
    [int]$ErrorCount
    [bool]$IsReady            # true if FFU + DeployISO found, no errors
}
```

### Safe WriteLog Pattern (ThreadJob compatible)
```powershell
# Source: CLAUDE.md ThreadJob Compatibility section; FFU.Core v1.0.12 pattern
$msg = "ArtifactScanner: $someMessage"
if ($function:WriteLog) {
    WriteLog $msg
}
else {
    Write-Verbose $msg
}
```

### Autopilot Scan (from BuildFFUVM.ps1 line 2107)
```powershell
# Source: BuildFFUVM.ps1 line 2107 — exact pattern to replicate
$autopilotJsonFiles = Get-ChildItem -Path $AutopilotFolder -Filter '*.json' -ErrorAction SilentlyContinue
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline WIMMount check | Test-FFUWimMount with auto-repair (Phase 44) | 2026-03-12 | Reuse without modification |
| `Get-Date` | `[DateTime]::Now` | FFU.Common v0.0.9 | All staleness calculations must use `[DateTime]::Now` |
| `Write-Warning` | WriteLog with `$function:WriteLog` guard | FFU.Common v0.0.11 | Safe logging pattern required throughout |
| PSCustomObject returns | Factory functions for PowerShell classes | FFU.Hypervisor v1.1.4 | Export `New-ArtifactManifest` etc. for cross-scope instantiation |

**Deprecated/outdated:**
- Using `Get-Date` for timestamps: replaced by `[DateTime]::Now` project-wide
- Using `Write-Warning` in module bodies: replaced by safe logging pattern

---

## Open Questions

1. **ConvertTo-Json serialization of PowerShell class instances**
   - What we know: PS 7.0+ handles class instances with `ConvertTo-Json -Depth 10`; the project requires PS 7.0+
   - What's unclear: Whether Phase 47 or 48 will need JSON round-trip of ArtifactManifest; if so, whether native `ConvertTo-Json` suffices or a custom serializer is needed
   - Recommendation: Defer JSON helpers to Claude's discretion. Test during implementation whether `ConvertTo-Json $manifest -Depth 10` produces usable output; if not, add a `ConvertTo-ArtifactManifestJson` helper.

2. **Phase 45 Config Schema dependency**
   - What we know: CONTEXT.md says "Phase 45 config schema: ArtifactManifest structure must align with USBMode config section"; Phase 45 has not been planned yet
   - What's unclear: Specific config field names Phase 45 will define
   - Recommendation: Implement Phase 46 classes independently. Phase 46's `ArtifactManifest` is the canonical data contract — Phase 45 should reference it, not the reverse. If schema keys change after Phase 45 planning, update Phase 46 class property names at that time (low-cost change).

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Pester 5.x |
| Config file | None — runner is `Tests/Unit/Invoke-PesterTests.ps1` |
| Quick run command | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ArtifactScanner'` |
| Full suite command | `.\Tests\Unit\Invoke-PesterTests.ps1` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DISC-01 | Find-FFUArtifacts discovers all 7 artifact types | unit | `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ArtifactScanner'` | ❌ Wave 0 |
| DISC-01 | Missing optional artifacts return Missing status, not error | unit | same | ❌ Wave 0 |
| DISC-01 | Find-FFUArtifacts returns [ArtifactManifest] type | unit | same | ❌ Wave 0 |
| VALID-01 | ArtifactResult includes FilePath, FileSizeBytes, Status | unit | same | ❌ Wave 0 |
| VALID-02 | Get-ArtifactMetadata extracts WindowsVersion/SKU/Architecture via DISM mock | unit | same | ❌ Wave 0 |
| VALID-02 | Get-ArtifactMetadata falls back to filename parsing when DISM unavailable | unit | same | ❌ Wave 0 |
| VALID-03 | Test-ArtifactCompatibility returns warning when architectures mismatch | unit | same | ❌ Wave 0 |
| VALID-03 | Test-ArtifactCompatibility returns no warnings when architectures match | unit | same | ❌ Wave 0 |
| VALID-04 | ArtifactResult.AgeDays is correct integer from LastWriteTime | unit | same | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.ArtifactScanner'`
- **Per wave merge:** `.\Tests\Unit\Invoke-PesterTests.ps1`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/Unit/FFU.ArtifactScanner.Tests.ps1` — covers all DISC-01, VALID-01 through VALID-04 requirements
- [ ] `FFUDevelopment/Modules/FFU.ArtifactScanner/Classes/ArtifactScanner.Classes.ps1` — enums + data classes
- [ ] `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psm1` — module root
- [ ] `FFUDevelopment/Modules/FFU.ArtifactScanner/FFU.ArtifactScanner.psd1` — manifest with RequiredModules, FunctionsToExport, GUID

---

## Sources

### Primary (HIGH confidence)
- BuildFFUVM.ps1 lines 1830-1867 — canonical artifact path defaults (local codebase)
- BuildFFUVM.ps1 lines 1503-1515 — unattend arch-specific filename pattern (local codebase)
- BuildFFUVM.ps1 line 2107 — Autopilot .json scan pattern (local codebase)
- FFU.Hypervisor/FFU.Hypervisor.psm1 lines 27-43 — Classes/ dot-sourcing pattern (local codebase)
- FFU.Hypervisor/Classes/VMConfiguration.ps1 — PowerShell class definition pattern (local codebase)
- FFU.Preflight/FFU.Preflight.psm1 lines 1944+ — Test-FFUWimMount function signature and return type (local codebase)
- FFU.Core/FFU.Core.psd1 — RequiredModules hashtable format (local codebase)
- CLAUDE.md ThreadJob Compatibility table — `[DateTime]::Now`, safe WriteLog pattern

### Secondary (MEDIUM confidence)
- DISM module Get-WindowsImage Architecture integer encoding: 0=x86, 9=amd64, 12=arm64 — verified against Windows PE architecture constants documentation; consistent with `dism /Get-WimInfo` output patterns

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries are in-codebase or .NET built-ins; no new dependencies
- Architecture: HIGH — directly modeled on existing FFU.Hypervisor and FFU.Core patterns in this repo
- Pitfalls: HIGH — all pitfalls are drawn from documented project history (CLAUDE.md fix history, FFU.Hypervisor release notes, FFU.Core release notes)

**Research date:** 2026-03-14
**Valid until:** 2026-04-14 (stable — no external dependencies to expire)
