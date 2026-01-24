# Phase 20: FFU.Updates Reliability - Research

**Researched:** 2026-01-23
**Domain:** Windows Update catalog queries, MSU download validation, update application isolation, cache management
**Confidence:** HIGH

## Summary

This research analyzes the FFU.Updates module's current state and identifies gaps between existing implementation and the REL-UPD reliability requirements. The module already has substantial infrastructure for catalog queries (Get-ProductsCab, Get-KBLink), MSU handling (Add-WindowsPackageWithUnattend with CAB extraction), and retry logic (Add-WindowsPackageWithRetry). However, there are specific gaps in:

1. **Catalog query resilience** - Get-KBLink has basic retry (3 attempts with exponential backoff), but Get-ProductsCab has no retry logic
2. **MSU download validation** - Basic size/hash validation exists for products.cab, but MSU downloads only check file size > 0
3. **Update application isolation** - No isolation between updates - one failure stops the entire update process
4. **Catalog cache management** - No caching layer exists; products.cab/xml are downloaded fresh each time

The existing patterns from Phase 15-19 (exponential backoff, error classification, cleanup registration, structured readiness results) can be extended directly to this module. The `Start-BitsTransferWithRetry` function in FFU.Common.Core provides the download resilience foundation.

**Primary recommendation:** Extend existing Get-KBLink retry pattern to Get-ProductsCab, add MSU integrity validation using SHA256 from catalog metadata, implement per-update try/catch with result collection for isolation, and add optional caching layer with staleness detection for products.cab.

## Standard Stack

The established patterns for this domain are already in the codebase:

### Core Patterns to Extend

| Pattern | Location | Purpose | Why Standard |
|---------|----------|---------|--------------|
| Get-KBLink retry | FFU.Updates | Retry with exponential backoff | Already has 3-retry, 2x backoff |
| Start-BitsTransferWithRetry | FFU.Common.Core | Multi-method download fallback | BITS -> WebRequest -> WebClient -> curl |
| Invoke-WithErrorHandling | FFU.Core | Generic retry wrapper | Logging, cleanup, retry delay |
| Test-IsTransientImagingError | FFU.Imaging | Transient error classification | Pattern for Test-IsTransientUpdateError |
| Add-WindowsPackageWithRetry | FFU.Updates | Package retry with validation | Mount state, DISM health checks |

### Supporting Functions

| Function | Module | Purpose | When to Use |
|----------|--------|---------|-------------|
| WriteLog | FFU.Core | Thread-safe logging | All error messages |
| Test-MountedImageDiskSpace | FFU.Updates | Pre-validation | Before MSU application |
| Test-FileLocked | FFU.Updates | File access check | Before MSU extraction |
| Test-DISMServiceHealth | FFU.Updates | DISM availability | Before package operations |
| Test-MountState | FFU.Updates | Mount validation | Before retry attempts |

### No New External Dependencies Required

The existing module structure provides everything needed:
- FFU.Updates depends on FFU.Core
- FFU.Common.Core provides resilient downloads
- SHA256 hashing via [System.Security.Cryptography.SHA256]
- Product catalog metadata includes Digest and Size for validation

## Architecture Patterns

### Pattern 1: Catalog Query with Retry

**What:** Wrap catalog HTTP requests with retry logic using exponential backoff with jitter.

**When to use:** Get-ProductsCab, Invoke-RestMethod calls in catalog functions.

**Source:** Get-KBLink already implements this pattern (lines 388-412).

```powershell
# Extend Get-ProductsCab with same retry pattern as Get-KBLink
function Invoke-CatalogQueryWithRetry {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Query,

        [Parameter()]
        [string]$OperationName = 'Catalog query',

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$BaseDelaySeconds = 10
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            $result = & $Query
            return $result
        }
        catch {
            $lastError = $_
            WriteLog "WARNING: $OperationName failed (attempt $attempt of $MaxRetries): $($_.Exception.Message)"

            if ($attempt -lt $MaxRetries) {
                # Exponential backoff with jitter (prevents thundering herd)
                $jitter = Get-Random -Minimum 0 -Maximum 3
                $delay = ($BaseDelaySeconds * [math]::Pow(2, $attempt - 1)) + $jitter
                WriteLog "Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
            }
        }
    }

    WriteLog "ERROR: $OperationName failed after $MaxRetries attempts"
    throw $lastError
}
```

### Pattern 2: MSU Integrity Validation

**What:** Validate downloaded MSU files using SHA256 hash and size comparison.

**When to use:** After Save-KB downloads, before Add-WindowsPackageWithUnattend.

**Source:** Get-ProductsCab already validates products.cab (lines 138-155).

```powershell
function Test-MSUIntegrity {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter()]
        [string]$ExpectedHash,

        [Parameter()]
        [int64]$ExpectedSize,

        [Parameter()]
        [int]$MinimumSizeBytes = 1MB
    )

    $result = @{
        Valid = $true
        FilePath = $FilePath
        Errors = [System.Collections.Generic.List[string]]::new()
    }

    # Check file exists
    if (-not (Test-Path $FilePath)) {
        $result.Valid = $false
        $result.Errors.Add("File not found: $FilePath")
        return [PSCustomObject]$result
    }

    $fileInfo = Get-Item $FilePath

    # Check for empty file (corruption indicator)
    if ($fileInfo.Length -eq 0) {
        $result.Valid = $false
        $result.Errors.Add("File is empty (0 bytes) - download incomplete or corrupted")
        return [PSCustomObject]$result
    }

    # Check minimum size (suspicious if too small)
    if ($fileInfo.Length -lt $MinimumSizeBytes) {
        $result.Valid = $false
        $result.Errors.Add("File is suspiciously small ($([math]::Round($fileInfo.Length / 1KB, 2)) KB) - expected > $([math]::Round($MinimumSizeBytes / 1KB, 2)) KB")
        return [PSCustomObject]$result
    }

    # Check expected size if provided
    if ($ExpectedSize -gt 0 -and $fileInfo.Length -ne $ExpectedSize) {
        $result.Valid = $false
        $result.Errors.Add("Size mismatch: expected $ExpectedSize bytes, got $($fileInfo.Length) bytes")
    }

    # Check hash if provided
    if ($ExpectedHash) {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($FilePath)
        try {
            $hashBytes = $sha256.ComputeHash($fs)
            $actualHash = [Convert]::ToBase64String($hashBytes)
        }
        finally {
            $fs.Dispose()
        }

        if ($actualHash -ne $ExpectedHash) {
            $result.Valid = $false
            $result.Errors.Add("Hash mismatch: expected $ExpectedHash, got $actualHash")
        }
    }

    [PSCustomObject]$result
}
```

### Pattern 3: Update Application Isolation

**What:** Apply updates independently so one failure doesn't block others.

**When to use:** When applying multiple updates (CU, .NET, Defender, etc.).

**Source:** Phase 18 pattern for collecting results from multiple operations.

```powershell
function Invoke-UpdatesWithIsolation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$MountPath,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$Updates,  # Array of @{ Name; Path; Type; Required }

        [Parameter()]
        [switch]$StopOnCriticalFailure
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $hasFailures = $false
    $hasCriticalFailure = $false

    foreach ($update in $Updates) {
        $updateResult = @{
            Name = $update.Name
            Type = $update.Type
            Status = 'Pending'
            Error = $null
            Duration = $null
        }

        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            WriteLog "Applying update: $($update.Name) ($($update.Type))"

            Add-WindowsPackageWithRetry -Path $MountPath -PackagePath $update.Path
            $stopwatch.Stop()

            $updateResult.Status = 'Success'
            $updateResult.Duration = $stopwatch.Elapsed.TotalSeconds
            WriteLog "Update $($update.Name) applied successfully in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s"
        }
        catch {
            $stopwatch.Stop()
            $updateResult.Status = 'Failed'
            $updateResult.Error = $_.Exception.Message
            $updateResult.Duration = $stopwatch.Elapsed.TotalSeconds
            $hasFailures = $true

            WriteLog "ERROR: Update $($update.Name) failed: $($_.Exception.Message)"

            if ($update.Required) {
                $hasCriticalFailure = $true
                WriteLog "CRITICAL: Required update $($update.Name) failed"

                if ($StopOnCriticalFailure) {
                    $results.Add([PSCustomObject]$updateResult)
                    break
                }
            }
        }

        $results.Add([PSCustomObject]$updateResult)
    }

    [PSCustomObject]@{
        AllSucceeded = -not $hasFailures
        HasCriticalFailure = $hasCriticalFailure
        TotalCount = $Updates.Count
        SuccessCount = ($results | Where-Object Status -eq 'Success').Count
        FailureCount = ($results | Where-Object Status -eq 'Failed').Count
        Results = $results
    }
}
```

### Pattern 4: Catalog Cache Management

**What:** Cache products.cab with staleness detection and transparent refresh.

**When to use:** Before downloading products.cab in Get-WindowsESD.

**Source:** New pattern, but follows file validation from Get-ProductsCab.

```powershell
function Get-CachedProductsCab {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$Architecture,

        [Parameter(Mandatory)]
        [string]$BuildVersion,

        [Parameter(Mandatory)]
        [string]$UserAgent,

        [Parameter()]
        [int]$MaxAgeHours = 24,

        [Parameter()]
        [switch]$ForceRefresh
    )

    $cacheFile = Join-Path $CachePath "products_${Architecture}_${BuildVersion}.cab"
    $cacheMetaFile = "$cacheFile.meta"

    # Check if valid cache exists
    $useCache = $false
    if (-not $ForceRefresh -and (Test-Path $cacheFile) -and (Test-Path $cacheMetaFile)) {
        try {
            $meta = Get-Content $cacheMetaFile -Raw | ConvertFrom-Json
            $cacheAge = ([DateTime]::Now - [DateTime]$meta.Downloaded).TotalHours

            if ($cacheAge -lt $MaxAgeHours) {
                # Verify cache integrity
                $integrityCheck = Test-MSUIntegrity -FilePath $cacheFile `
                    -ExpectedHash $meta.Hash -ExpectedSize $meta.Size

                if ($integrityCheck.Valid) {
                    WriteLog "Using cached products.cab (age: $([math]::Round($cacheAge, 1))h)"
                    $useCache = $true
                }
                else {
                    WriteLog "WARNING: Cache integrity check failed: $($integrityCheck.Errors -join '; ')"
                    WriteLog "Refreshing cache..."
                }
            }
            else {
                WriteLog "Cache is stale (age: $([math]::Round($cacheAge, 1))h > max: ${MaxAgeHours}h)"
            }
        }
        catch {
            WriteLog "WARNING: Failed to read cache metadata: $($_.Exception.Message)"
        }
    }

    if (-not $useCache) {
        # Download fresh copy
        WriteLog "Downloading fresh products.cab..."
        Get-ProductsCab -OutFile $cacheFile -Architecture $Architecture `
            -BuildVersion $BuildVersion -UserAgent $UserAgent

        # Get file hash for cache metadata
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($cacheFile)
        try {
            $hashBytes = $sha256.ComputeHash($fs)
            $fileHash = [Convert]::ToBase64String($hashBytes)
        }
        finally {
            $fs.Dispose()
        }

        # Write cache metadata
        $meta = @{
            Downloaded = [DateTime]::Now.ToString('o')
            Hash = $fileHash
            Size = (Get-Item $cacheFile).Length
            Architecture = $Architecture
            BuildVersion = $BuildVersion
        }
        $meta | ConvertTo-Json | Set-Content $cacheMetaFile

        WriteLog "Products.cab cached successfully"
    }

    return $cacheFile
}
```

### Recommended Project Structure

The FFU.Updates reliability functions should be organized as:
```
FFU.Updates.psm1
  |-- Existing functions (unchanged)
  |-- New reliability functions (REL-UPD-*):
      |-- Invoke-CatalogQueryWithRetry (REL-UPD-01: Catalog resilience)
      |-- Test-MSUIntegrity (REL-UPD-02: Download validation)
      |-- Invoke-UpdatesWithIsolation (REL-UPD-03: Update isolation)
      |-- Get-CachedProductsCab (REL-UPD-04: Cache management)
      |-- Test-IsTransientUpdateError (error classification helper)
```

### Anti-Patterns to Avoid

- **Unbounded retry:** Always use MaxRetries to prevent infinite loops
- **Silent cache use:** Log when using cached data for debugging
- **All-or-nothing updates:** One update failure shouldn't abort entire build
- **Hash-only validation:** Also check file size for quick corruption detection
- **Fixed retry delays:** Use exponential backoff with jitter to prevent thundering herd

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Download retry | Custom loop | Start-BitsTransferWithRetry | Multi-method fallback already implemented |
| Hash validation | Manual SHA256 | Pattern from Get-ProductsCab | Already handles streaming, proper cleanup |
| Error classification | Simple string match | Test-IsTransientImagingError pattern | Needs HResult + pattern matching |
| Exponential backoff | Manual sleep calc | Get-KBLink pattern | Already has jitter handling |
| DISM pre-checks | Inline validation | Test-MountState, Test-DISMServiceHealth | Already exported from module |

**Key insight:** FFU.Updates already has significant catalog query and MSU handling logic. This phase standardizes retry patterns, adds validation, and implements isolation - not replacing existing functionality.

## Common Pitfalls

### Pitfall 1: Microsoft Update Catalog Rate Limiting

**What goes wrong:** Catalog queries fail with 429 Too Many Requests or connection resets.

**Why it happens:** Microsoft Update Catalog has rate limits, especially for automated queries.

**How to avoid:**
1. Use exponential backoff (2x delay on each retry)
2. Add jitter to prevent synchronized retries (thundering herd)
3. Cache products.cab when possible (24-hour staleness window)
4. Log rate limit responses distinctly for debugging

**Warning signs:** Consistent failures after 2-3 quick retries, "connection forcibly closed" errors.

### Pitfall 2: MSU Download Incomplete Without Error

**What goes wrong:** MSU file downloads but is truncated or corrupt, expand.exe fails later.

**Why it happens:** Network interruption during download, disk full, or BITS silent failure.

**How to avoid:**
1. Validate file size > 0 immediately after download
2. Check against expected size from catalog metadata when available
3. Use SHA256 validation for critical updates
4. Re-download on validation failure (don't just warn)

**Warning signs:** expand.exe exit code -1, "Can't open input file" errors.

### Pitfall 3: One Bad Update Blocks All Updates

**What goes wrong:** First update in sequence fails, remaining updates never attempted.

**Why it happens:** Sequential application without try/catch per update.

**How to avoid:**
1. Wrap each update application in isolated try/catch
2. Collect results for all updates, report summary at end
3. Distinguish "required" vs "optional" updates for stop-on-failure logic
4. Continue with remaining updates after non-critical failures

**Warning signs:** "CU failed" stops Defender and .NET updates from applying.

### Pitfall 4: Stale Cache Causes Wrong Update Version

**What goes wrong:** Cached products.cab returns older update version, build has outdated patches.

**Why it happens:** No cache staleness check, or age threshold too long.

**How to avoid:**
1. Store download timestamp in cache metadata
2. Use 24-hour default staleness (adjustable)
3. Validate cache integrity on load (size + hash)
4. Provide ForceRefresh option for troubleshooting

**Warning signs:** "Latest CU" is actually from last month, security patches missing.

### Pitfall 5: Products.cab Corruption Goes Undetected

**What goes wrong:** Cache file corrupted, XML parsing fails with cryptic error.

**Why it happens:** Disk error, process crash during write, antivirus interference.

**How to avoid:**
1. Validate hash from server response (already implemented in Get-ProductsCab)
2. Re-validate on cache load
3. Delete corrupted cache and re-download
4. Log corruption detection clearly for debugging

**Warning signs:** "Root element is missing" XML error, "CAB archive is corrupt".

## Code Examples

Verified patterns from existing codebase:

### Catalog Query Retry (from Get-KBLink)
```powershell
# Source: FFU.Updates.psm1 lines 388-412
$maxRetries = 3
$retryDelay = 10
$results = $null

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    try {
        $results = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=$Name" -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
        break
    }
    catch {
        $VerbosePreference = $OriginalVerbosePreference
        if ($attempt -eq $maxRetries) {
            WriteLog "ERROR: Failed to search Update Catalog after $maxRetries attempts: $($_.Exception.Message)"
            return [PSCustomObject]@{
                KBArticleID = $null
                Links = @()
            }
        }
        WriteLog "WARNING: Update Catalog search failed (attempt $attempt of $maxRetries): $($_.Exception.Message)"
        WriteLog "Retrying in $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
        $retryDelay = $retryDelay * 2  # Exponential backoff
        $VerbosePreference = 'SilentlyContinue'
    }
}
```

### Hash/Size Validation (from Get-ProductsCab)
```powershell
# Source: FFU.Updates.psm1 lines 138-155
$actualSize = (Get-Item $OutFile).Length
if ($actualSize -ne $serverSize) {
    throw "Size check failed. Expected $serverSize bytes. Got $actualSize bytes."
}

$sha256 = [System.Security.Cryptography.SHA256]::Create()
$fs = [System.IO.File]::OpenRead($OutFile)
try {
    $hashBytes = $sha256.ComputeHash($fs)
}
finally {
    $fs.Dispose()
}
$actualDigestB64 = [Convert]::ToBase64String($hashBytes)

if ($actualDigestB64 -ne $serverDigestB64) {
    throw "Digest check failed. Expected $serverDigestB64. Got $actualDigestB64."
}
```

### MSU Integrity Check (from Add-WindowsPackageWithUnattend)
```powershell
# Source: FFU.Updates.psm1 lines 1162-1175
# Validate MSU file integrity before attempting extraction
WriteLog "Validating MSU package integrity: $packageName"
$msuFileInfo = Get-Item $PackagePath -ErrorAction Stop

if ($msuFileInfo.Length -eq 0) {
    WriteLog "ERROR: MSU package is empty (0 bytes): $packageName"
    throw "Corrupted or incomplete MSU package: $packageName"
}

# Check for minimum reasonable MSU size (typically >1MB)
if ($msuFileInfo.Length -lt 1MB) {
    WriteLog "WARNING: MSU package is suspiciously small ($([Math]::Round($msuFileInfo.Length / 1MB, 2)) MB): $packageName"
}

WriteLog "MSU package validation passed. Size: $([Math]::Round($msuFileInfo.Length / 1MB, 2)) MB"
```

### Retry with Mount Validation (from Add-WindowsPackageWithRetry)
```powershell
# Source: FFU.Updates.psm1 lines 1051-1079
if ($attempt -gt 1) {
    WriteLog "Retry attempt $attempt of $MaxRetries for package: $packageName"

    # Validate mount state before retry
    WriteLog "Validating mounted image state..."
    if (-not (Test-MountState -Path $Path)) {
        WriteLog "CRITICAL: Mounted image at $Path is no longer accessible"
        throw "Mounted image lost between retry attempts. Cannot continue."
    }
    WriteLog "Mount state validation passed. Image is accessible."

    # Validate DISM service health before retry
    WriteLog "Validating DISM service health..."
    if (-not (Test-DISMServiceHealth)) {
        WriteLog "CRITICAL: DISM service (TrustedInstaller) is not healthy"
        throw "DISM service is not available for retry. Cannot continue."
    }
    WriteLog "DISM service health check passed. TrustedInstaller is available."

    WriteLog "Waiting $RetryDelaySeconds seconds before retry..."
    Start-Sleep -Seconds $RetryDelaySeconds
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No catalog retry | Get-KBLink has 3-retry with backoff | v1.0.3 | Handles transient catalog failures |
| Direct MSU application | Add-WindowsPackageWithUnattend CAB extraction | v1.0.2 | Bypasses UUP checkpoint issues |
| No size validation | Basic size check (> 0, > 1MB warning) | v1.0.2 | Catches empty/corrupt downloads |
| Single retry | Add-WindowsPackageWithRetry with mount check | v1.0.0 | Validates state between retries |
| No products.cab validation | SHA256 + size validation | v1.0.0 | Catches incomplete downloads |

**Current gaps to address:**
- Get-ProductsCab has NO retry (Get-KBLink does)
- No MSU hash validation (only size check)
- No update isolation (one failure stops all)
- No catalog caching (fresh download each time)

## Open Questions

Things that were resolved during research:

1. **Catalog retry parameters**
   - What we know: Get-KBLink uses 3 retries, 10s base delay, 2x backoff
   - Resolution: Apply same pattern to Get-ProductsCab
   - Confidence: HIGH - pattern already tested in production

2. **MSU hash availability**
   - What we know: Products.cab metadata includes Digest (SHA256) for ESD files
   - What's unclear: Does Update Catalog provide hash for MSU files?
   - Resolution: Use size validation as primary, hash optional
   - Recommendation: Check if catalog search response includes file digest

3. **Cache location**
   - What we know: Products.cab is downloaded to $TempPath
   - Resolution: Use dedicated cache subfolder: $FFUDevelopmentPath\.cache\catalogs
   - Recommendation: Add cleanup to existing cleanup registration system

## Sources

### Primary (HIGH confidence)
- FFU.Updates.psm1 source (v1.0.5) - Existing retry, validation patterns
- FFU.Common.Core.psm1 source - Start-BitsTransferWithRetry implementation
- FFU.Core.psm1 source (v1.0.9) - Invoke-WithErrorHandling, cleanup registration
- Phase 18 RESEARCH.md - Error classification, state verification patterns
- Phase 19 RESEARCH.md - Structured readiness results pattern

### Secondary (MEDIUM confidence)
- Microsoft Update Catalog HTML structure - Verified via Get-KBLink implementation
- DISM package application behavior - Verified via Add-WindowsPackageWithUnattend tests

### Tertiary (LOW confidence)
- Microsoft Update Catalog rate limiting - Inferred from retry pattern necessity
- MSU hash availability from catalog - Not verified, may require investigation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Patterns exist in codebase and Phase 17-19
- Architecture: HIGH - Direct extension of existing error handling
- Pitfalls: HIGH - Based on existing module issues and release notes
- Code examples: HIGH - Extracted directly from working module code

**Research date:** 2026-01-23
**Valid until:** 2026-02-23 (stable patterns, catalog API unchanged)

## Requirement-Specific Findings

### REL-UPD-01: Catalog Query Retry
- **Pattern:** Invoke-CatalogQueryWithRetry with exponential backoff + jitter
- **Integration:** Wrap Invoke-RestMethod calls in Get-ProductsCab lines 86, 106
- **Existing:** Get-KBLink already has retry (lines 388-412), extend to Get-ProductsCab
- **Confidence:** HIGH - straightforward pattern extension

### REL-UPD-02: MSU Download Validation
- **Pattern:** Test-MSUIntegrity with size check + optional hash validation
- **Integration:** Call after Save-KB download, before Add-WindowsPackageWithUnattend
- **Existing:** Basic size check in Add-WindowsPackageWithUnattend (lines 1162-1175)
- **Enhancement:** Add hash validation when metadata available, auto-redownload on failure
- **Confidence:** HIGH - extends existing validation pattern

### REL-UPD-03: Update Application Isolation
- **Pattern:** Invoke-UpdatesWithIsolation with per-update try/catch and result collection
- **Integration:** Replace sequential update loop in BuildFFUVM.ps1 update section
- **Existing:** No isolation currently - sequential application stops on first failure
- **Enhancement:** Collect results, distinguish required/optional, continue after non-critical
- **Confidence:** HIGH - standard pattern from Phase 18

### REL-UPD-04: Catalog Cache Management
- **Pattern:** Get-CachedProductsCab with staleness detection and integrity validation
- **Integration:** Replace direct Get-ProductsCab call in Get-WindowsESD
- **Existing:** No caching - fresh download each time
- **Enhancement:** 24-hour cache with hash validation, transparent refresh on staleness/corruption
- **Confidence:** MEDIUM - new functionality, but follows established validation patterns
