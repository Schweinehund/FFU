# Phase 35: PPKG and xcopy Path Quoting - Research

**Researched:** 2026-01-28
**Domain:** PowerShell path quoting, xcopy command-line, Windows file operations
**Confidence:** HIGH

## Summary

This phase fixes PPKG (Windows Provisioning Package) file copying when filenames contain spaces. The issue affects two scripts: `ApplyFFU.ps1` (deployment) and `USBImagingToolCreator.ps1` (USB creation). Currently, `ApplyFFU.ps1` uses `xcopy` without proper path quoting (line 843), causing failures with PPKG files like "Contoso Provisioning Package.ppkg".

Phase 34 established the backtick-escaped double quote pattern (`"`path`"`) for this codebase. The same pattern should be applied here for consistency. Since `USBImagingToolCreator.ps1` does NOT currently copy PPKG files (it uses robocopy for everything except PPKG), this is actually a one-script fix unless PPKG support is intentionally added to USB creator.

**Primary recommendation:** Fix `ApplyFFU.ps1` xcopy call with backtick-escaped quotes, add Copy-Item fallback, make PPKG copy non-blocking with detailed error logging. USBImagingToolCreator.ps1 does not require changes unless PPKG support is being added.

## Standard Stack

### Core Technologies
| Technology | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| PowerShell | 5.1+ | Script execution environment | Built into Windows, used throughout FFUBuilder |
| xcopy | Built-in | File copy utility | Legacy tool, used consistently in ApplyFFU.ps1 for compatibility with WinPE |
| Copy-Item | PowerShell cmdlet | Fallback copy mechanism | Native PowerShell, more robust error handling |

### Supporting Tools
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Invoke-Process | Custom function | Wrapper for Start-Process with error handling | All external command execution in ApplyFFU.ps1 |
| robocopy | Built-in | Directory copy utility | Bulk operations in USBImagingToolCreator.ps1 and BuildFFUVM.ps1 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| xcopy | Copy-Item | More PowerShell-native, but ApplyFFU.ps1 uses xcopy consistently for WinPE compatibility |
| xcopy | robocopy | More robust and handles spaces natively, but breaks consistency with existing xcopy patterns in ApplyFFU.ps1 |
| String concatenation | Start-Process -ArgumentList array | Safer but requires refactoring Invoke-Process function |

**Installation:** No external dependencies required - all tools built into Windows.

## Architecture Patterns

### Current File Copy Patterns in FFUBuilder

**ApplyFFU.ps1 pattern (xcopy via Invoke-Process):**
```powershell
# Current implementation (line 843) - BROKEN for paths with spaces
Invoke-process xcopy.exe "$PPKGFileToInstall $USBDrive"

# Other xcopy calls in ApplyFFU.ps1 (all unquoted):
# Line 204: Invoke-Process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y"
# Line 809: Invoke-Process xcopy.exe "/h $WinRE R:\Recovery\WindowsRE\ /Y"
# Line 820: Invoke-process xcopy.exe "$APFileToInstall W:\Windows\provisioning\autopilot\"
# Line 862: Invoke-process xcopy "$UnattendFile $PantherDir /Y"
# Line 871: Invoke-Process xcopy.exe "$UnattendFile $PantherDir"
```

**BuildFFUVM.ps1 pattern (robocopy):**
```powershell
# Line 1464 - robust robocopy with retry logic
robocopy $using:PPKGFolder $PPKGPathOnUSB /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
Test-RobocopySuccess -Operation "PPKG files to USB"
```

**USBImagingToolCreator.ps1 pattern (robocopy):**
```powershell
# Lines 106, 121, 145 - all use robocopy for directory copying
Robocopy $SFolder $DFolder /E /COPYALL /R:5 /W:5 /J
# NO PPKG-specific copy operations exist in this script
```

### Pattern 1: Phase 34 Backtick-Quote Pattern (ESTABLISHED STANDARD)

**What:** Wrap paths in backtick-escaped double quotes: `` "`"$path`"" ``

**When to use:** When passing paths to external commands where spaces may exist

**Example from Phase 34 (FFU.Common.Winget.psm1):**
```powershell
# EXE installer path (line 728)
$silentInstallCommand = "`"$basePath\$resolvedRelativePath`""

# MSI installer path in arguments (line 732)
$silentInstallSwitch = "/i `"$basePath\$resolvedRelativePath`" $silentInstallSwitch".Trim()
```

**How it works:**
- Backtick (`` ` ``) escapes the double quote character in PowerShell
- Produces a literal quote character in the resulting string
- The string `"`"C:\My Files\file.exe`""` becomes `"C:\My Files\file.exe"` (with literal quotes)
- Works with both `Start-Process -FilePath` (strips quotes) and cmd.exe contexts (requires quotes)

### Pattern 2: xcopy Quoting for Invoke-Process

**What:** Quote both source and destination paths when calling xcopy via Invoke-Process

**Syntax for xcopy via Invoke-Process:**
```powershell
# Invoke-Process splits on FilePath and ArgumentList
# ArgumentList should contain: "source" "destination" switches

# CORRECT - backtick-escaped quotes around each path
Invoke-Process xcopy.exe "`"$SourcePath`" `"$DestPath`" /Y"

# WRONG - no quotes (fails with spaces)
Invoke-Process xcopy.exe "$SourcePath $DestPath /Y"

# WRONG - PowerShell string quotes (produces ""path"" in ArgumentList)
Invoke-Process xcopy.exe "`"$SourcePath`" `"$DestPath`" /Y"
```

**Why both paths need quotes:**
- xcopy syntax: `xcopy source destination [switches]`
- cmd.exe parsing splits on spaces
- Path "C:\My Documents\file.ppkg" becomes THREE arguments without quotes: `C:\My`, `Documents\file.ppkg`, `destination`
- With quotes: `"C:\My Documents\file.ppkg"` is ONE argument

### Pattern 3: Copy-Item Fallback for Resilience

**What:** If xcopy fails, fall back to Copy-Item with proper error handling

**Example:**
```powershell
try {
    # Primary: xcopy (for consistency with existing ApplyFFU.ps1 patterns)
    Invoke-Process xcopy.exe "`"$SourcePath`" `"$DestPath`" /Y"
}
catch {
    # Fallback: Copy-Item (handles spaces natively)
    WriteLog "xcopy failed, attempting Copy-Item fallback: $_"
    try {
        Copy-Item -Path $SourcePath -Destination $DestPath -Force -ErrorAction Stop
    }
    catch {
        # Non-blocking for PPKG - warn and continue
        WriteLog "WARNING: PPKG copy failed - Source: $SourcePath, Destination: $DestPath, Error: $_"
        # Do NOT throw - PPKG is optional
    }
}
```

### Anti-Patterns to Avoid

- **Concatenating unquoted paths:** `"$source $dest"` - Fails with spaces, as seen in current line 843
- **Double-wrapping quotes:** `"'$path'"` or `'`"$path`"'` - Creates nested quotes that cmd.exe can't parse
- **Using only source quotes:** `"`"$source`" $dest"` - Destination fails if it has spaces
- **Throwing on PPKG copy failure:** PPKG is optional - should warn and continue per CONTEXT.md decisions

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Path escaping utilities | Custom quote-wrapping function | Backtick-escaped inline quotes | Simple, direct, matches Phase 34 pattern |
| Retry logic for file copy | Custom loop with Sleep | robocopy with /R:5 /W:5 | Already proven in BuildFFUVM.ps1 |
| File copy error detection | Custom exit code parsing | Invoke-Process wrapper (already exists) | Centralized error handling |
| Path validation | Custom Test-Path with regex | PowerShell's Test-Path | Built-in, well-tested |

**Key insight:** Phase 34 already solved path quoting for this codebase. Don't create a new pattern - reuse the established backtick-quote approach for consistency.

## Common Pitfalls

### Pitfall 1: PowerShell String vs Command-Line Quoting Confusion

**What goes wrong:** Mixing PowerShell string quoting (`"$var"`) with cmd.exe argument quoting

**Why it happens:** PowerShell processes strings before passing to external commands. `"$path"` is a PowerShell string that gets expanded and passed WITHOUT quotes to the command.

**How to avoid:**
- Use backtick-escaping: `` "`"$path`"" `` produces a string containing literal quote characters
- The resulting string `"C:\My Files\file.txt"` (with quotes) is what gets passed to xcopy

**Warning signs:**
- Error message: "The system cannot find the file specified" when file exists
- Error contains partial path like "C:\My" instead of "C:\My Documents"
- Works with paths without spaces but fails with spaces

### Pitfall 2: xcopy Exit Codes and Error Detection

**What goes wrong:** xcopy returns non-zero exit codes for warnings (like "Does destination specify a file or directory?")

**Why it happens:** xcopy exit codes: 0=success, 1=no files found, 2=user pressed Ctrl+C, 4=initialization error, 5=disk write error

**How to avoid:**
- Invoke-Process in ApplyFFU.ps1 throws on non-zero exit code (line 110)
- For single-file copies, xcopy may prompt "File or Directory?" - use `/Y` to suppress
- Current code already uses Invoke-Process which handles this

**Warning signs:**
- Intermittent failures with message about file/directory ambiguity
- Script hangs waiting for user input (stdin blocked in WinPE)

### Pitfall 3: PPKG Copy as Blocking vs Non-Blocking

**What goes wrong:** Treating PPKG copy failure as fatal stops deployment when PPKG is optional

**Why it happens:** Developer habit from Phase 34 where installer path failures were fatal

**How to avoid:**
- Per CONTEXT.md: "PPKG copy failure is non-blocking in BOTH scripts"
- Catch exceptions, log warning with full details (source, dest, error), continue
- Warn instead of throw: `WriteLog "WARNING: PPKG copy failed..."`

**Warning signs:**
- Deployment stops on missing/inaccessible PPKG file
- User can't proceed even though PPKG is optional feature

### Pitfall 4: Invoke-Process ArgumentList Parsing

**What goes wrong:** Passing multi-argument strings to Invoke-Process leads to unexpected quoting behavior

**Why it happens:** Invoke-Process uses `-ArgumentList` parameter (line 88) which is a single string passed to Start-Process. Start-Process then parses this string using cmd.exe rules.

**How to avoid:**
- Keep ArgumentList as a single string with properly escaped quotes
- Don't try to split into array - Invoke-Process expects string
- Test the actual command-line that gets executed: `"$FilePath" $ArgumentList`

**Warning signs:**
- Error about too many arguments
- Arguments appear in wrong order
- Quotes show up in error messages as part of filename

## Code Examples

Verified patterns from FFUBuilder codebase:

### Example 1: Phase 34 Path Quoting (From FFU.Common.Winget.psm1)

```powershell
# Source: FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1 (lines 728-732)
# Context: Building installer paths for WinGetWin32Apps.json

$basePath = "D:\win32\$AppFolder"
if (-not [string]::IsNullOrEmpty($SubFolder)) {
    $basePath = "$basePath\$SubFolder"
}

# EXE installer - wrap entire path in backtick-escaped quotes
if ($installerExt -ieq ".exe") {
    $silentInstallCommand = "`"$basePath\$resolvedRelativePath`""
}
# MSI installer - quote path in msiexec arguments
elseif ($installerExt -ieq ".msi") {
    $silentInstallCommand = "msiexec"
    $silentInstallSwitch = "/i `"$basePath\$resolvedRelativePath`" $silentInstallSwitch".Trim()
}
else {
    # Default - wrap in quotes defensively
    $silentInstallCommand = "`"$basePath\$resolvedRelativePath`""
}
```

**Key takeaway:** Backtick-quote pattern works for paths passed to JSON that are later executed by ProcessStartInfo.

### Example 2: Invoke-Process Wrapper (From ApplyFFU.ps1)

```powershell
# Source: FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1 (lines 78-137)
# Context: Wrapper function that all xcopy calls use

function Invoke-Process {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ArgumentList
    )

    $ErrorActionPreference = 'Stop'

    try {
        $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"

        $startProcessParams = @{
            FilePath               = $FilePath
            ArgumentList           = $ArgumentList
            RedirectStandardError  = $stdErrTempFile
            RedirectStandardOutput = $stdOutTempFile
            Wait                   = $true
            PassThru               = $true
            NoNewWindow            = $true
        }

        if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
            $cmd = Start-Process @startProcessParams
            $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
            $cmdError = Get-Content -Path $stdErrTempFile -Raw

            if ($cmd.ExitCode -ne 0) {
                if ($cmdError) { throw $cmdError.Trim() }
                if ($cmdOutput) { throw $cmdOutput.Trim() }
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    WriteLog $cmdOutput
                }
            }
        }
    }
    catch {
        $errorMsg = if ($_.Exception.Message) { $_.Exception.Message } else { $_.ToString() }
        WriteLog "Invoke-Process failed: $errorMsg"
        Write-Host 'Script failed - check scriptlog.txt on the USB drive for more info'
        throw $_
    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
    }
}
```

**Key takeaway:** Invoke-Process throws on non-zero exit codes. PPKG copy must catch and handle this to remain non-blocking.

### Example 3: Current PPKG Copy (BROKEN)

```powershell
# Source: FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1 (line 843)
# Context: Copy PPKG file to USB drive during deployment

# CURRENT (BROKEN with spaces):
Invoke-process xcopy.exe "$PPKGFileToInstall $USBDrive"

# Problem: If $PPKGFileToInstall = "E:\PPKG\Contoso Package.ppkg"
# xcopy receives arguments: "E:\PPKG\Contoso Package.ppkg E:\"
# cmd.exe parses as: ["E:\PPKG\Contoso", "Package.ppkg", "E:\"]
# Result: "Cannot find E:\PPKG\Contoso"
```

### Example 4: Fixed PPKG Copy (CORRECT)

```powershell
# Source: Solution for ApplyFFU.ps1 line 843
# Context: Fixed version with backtick-escaped quotes and fallback

If ($PPKGFileToInstall) {
    Write-SectionHeader -Title 'Applying Provisioning Package'
    try {
        # Make sure to delete any existing PPKG on the USB drive
        Get-Childitem -Path $USBDrive\*.ppkg | ForEach-Object {
            Remove-item -Path $_.FullName
        }
        WriteLog "Copying $PPKGFileToInstall to $USBDrive"
        Write-Host "Copying $PPKGFileToInstall to $USBDrive"

        # Primary method: xcopy with proper quoting
        try {
            Invoke-process xcopy.exe "`"$PPKGFileToInstall`" `"$USBDrive`" /Y"
            WriteLog "Copying $PPKGFileToInstall to $USBDrive succeeded"
            Write-Host "Copying $PPKGFileToInstall to $USBDrive succeeded"
        }
        catch {
            # Fallback: Copy-Item (handles spaces natively)
            WriteLog "xcopy failed, attempting Copy-Item fallback: $_"
            Copy-Item -Path $PPKGFileToInstall -Destination $USBDrive -Force -ErrorAction Stop
            WriteLog "Copy-Item fallback succeeded for $PPKGFileToInstall"
            Write-Host "Copy-Item fallback succeeded for $PPKGFileToInstall"
        }
    }
    catch {
        # PPKG is optional - warn and continue (non-blocking per CONTEXT.md)
        $errorMsg = "PPKG copy failed - Source: $PPKGFileToInstall, Destination: $USBDrive, Error: $_"
        Writelog "WARNING: $errorMsg"
        Write-Host "WARNING: $errorMsg"
        # DO NOT throw - PPKG copy failure should not stop deployment
    }
}
```

**Key takeaway:** Nested try-catch allows xcopy primary with Copy-Item fallback, while outer catch makes entire operation non-blocking.

### Example 5: robocopy Pattern (From BuildFFUVM.ps1)

```powershell
# Source: FFUDevelopment/BuildFFUVM.ps1 (lines 1461-1465)
# Context: How PPKGs are copied during build process

if ($using:CopyPPKG) {
    $PPKGPathOnUSB = Join-Path $DeployPartitionDriveLetter "PPKG"
    WriteLog "Copying PPKGs to $PPKGPathOnUSB"
    robocopy $using:PPKGFolder $PPKGPathOnUSB /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Test-RobocopySuccess -Operation "PPKG files to USB"
}
```

**Key takeaway:** robocopy handles spaces natively without quoting, but ApplyFFU.ps1 uses xcopy consistently for WinPE compatibility.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Unquoted xcopy paths | Backtick-escaped quotes (Phase 34) | 2026-01-28 (Phase 34) | Fixes installer paths with spaces in WinGet module |
| xcopy only | xcopy primary + Copy-Item fallback | 2026-01-28 (Phase 35) | More resilient PPKG copy with graceful degradation |
| Blocking PPKG failures | Non-blocking with warnings | 2026-01-28 (Phase 35 CONTEXT.md) | Deployment continues even if optional PPKG fails |
| String concatenation | Backtick-escaped inline quoting | 2026-01-28 (Phase 34) | Standard pattern across codebase |

**Deprecated/outdated:**
- **Unquoted xcopy arguments:** Still present in 8 locations in ApplyFFU.ps1 (lines 204, 809, 820, 843, 862, 871, 912, 960). Phase 35 scope is PPKG-only (line 843), but other locations may need future fixes.
- **No fallback mechanisms:** Phase 34 established fallback as a pattern for critical operations. Phase 35 adopts this for PPKG.

## Open Questions

Things that couldn't be fully resolved:

1. **Should USBImagingToolCreator.ps1 add PPKG support?**
   - What we know: Script currently does NOT copy PPKG files. BuildFFUVM.ps1 copies PPKGs during build. ApplyFFU.ps1 copies PPKGs during deployment from USB to target.
   - What's unclear: Whether USB creation should include PPKG support (for direct-from-USB provisioning scenarios)
   - Recommendation: Out of scope for Phase 35 unless explicitly requested. CONTEXT.md lists USBImagingToolCreator.ps1 but analysis shows no PPKG copy operations exist there.

2. **Should other unquoted xcopy calls in ApplyFFU.ps1 be fixed?**
   - What we know: 8 other xcopy calls with unquoted paths exist (dism.log, WinRE, Autopilot, Unattend)
   - What's unclear: Whether these paths can contain spaces in practice
   - Recommendation: Fix opportunistically if easy during PPKG fix (Claude's discretion per CONTEXT.md), but don't expand scope to require testing all 8 scenarios.

3. **Copy-Item vs Robocopy for PPKG fallback?**
   - What we know: Copy-Item is simpler for single files. Robocopy handles retries better but adds complexity.
   - What's unclear: Whether robocopy's retry logic is worth the added code for single-file copy
   - Recommendation: Copy-Item for simplicity. PPKG files are small (<10MB typically), retries not critical since operation is non-blocking.

## Sources

### Primary (HIGH confidence)
- **FFUBuilder codebase** - Direct analysis of:
  - `FFUDevelopment/WinPEDeployFFUFiles/ApplyFFU.ps1` (lines 78-137 Invoke-Process, line 843 PPKG copy)
  - `FFUDevelopment/USBImagingToolCreator.ps1` (full file - NO PPKG operations found)
  - `FFUDevelopment/BuildFFUVM.ps1` (lines 1461-1465 robocopy PPKG copy)
  - `FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1` (lines 728-732 Phase 34 quoting pattern)
- **Phase 34 implementation** - Git commit 06e19a8 "fix(34-02): fix EXE and MSI path quoting for spaces"
- **Phase 35 CONTEXT.md** - User decisions on quoting strategy, failure behavior, fallback approach

### Secondary (MEDIUM confidence)
- [xcopy | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/xcopy) - Official xcopy documentation (does not explicitly address quoting)
- [Using xcopy with folders with spaces - DosTips.com](https://www.dostips.com/forum/viewtopic.php?t=8939) - Community consensus on double-quote requirement
- [File Paths with Spaces in Command Prompt: How to Handle Them](https://www.addictivetips.com/windows-tips/enter-file-or-folder-paths-with-spaces-in-command-prompt-on-windows-10/) - General guidance on cmd.exe quoting rules

### Tertiary (LOW confidence)
- WebSearch results on "xcopy command line path with spaces" - Multiple community sources agree on double-quote wrapping, but no single authoritative Microsoft source found that explicitly documents this.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** - All tools are built-in Windows utilities analyzed directly from codebase
- Architecture patterns: **HIGH** - Phase 34 established the pattern, directly examined in commit 06e19a8
- Pitfalls: **HIGH** - Derived from actual code patterns and cmd.exe behavior analysis
- USBImagingToolCreator.ps1 scope: **HIGH** - Full file analysis confirms no PPKG operations exist

**Research date:** 2026-01-28
**Valid until:** 2026-02-28 (30 days - stable domain, unlikely to change)

**Research artifacts examined:**
- 2 script files (ApplyFFU.ps1, USBImagingToolCreator.ps1)
- 1 module file (FFU.Common.Winget.psm1)
- 1 Git commit (Phase 34 implementation)
- 1 context document (35-CONTEXT.md)
- 249 lines of USBImagingToolCreator.ps1 (confirmed NO PPKG support)
- 137 lines of Invoke-Process implementation
- Phase 34 planning documents (34-02-PLAN.md)
