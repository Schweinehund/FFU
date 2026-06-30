#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for upstream changes ported in the 2026-06-21 upstream sync.

.DESCRIPTION
    Covers the high-impact bug-fix bundle ported from rbalsleyMSFT/FFU (upstream/UI):
    - T1-6 (2a77cf1): MSI path quoting in msiexec arguments (Format-MsiArguments)
    - T1-5 (96603f0): Disk size included in VHDX cache validation
    - T2-3 (c6088d9): 30-second delay for Windows Security Platform in Defender update script
    - T2-2a (6df32b6): Get-WmiObject -> Get-CimInstance for USB drive enumeration
    - T2-2b (63ef35a): USB empty-array guard (USBDrives.Count -eq 0)

    Format-MsiArguments is behaviorally tested via AST extraction (the host script
    Install-Win32Apps.ps1 executes a main body on load, so it cannot be dot-sourced).
    BuildFFUVM.ps1 changes are content-verified (the file is too large/coupled to load).

.NOTES
    See .planning/reports/upstream-sync-audit-2026-06-21.md for the full audit.
    Run with: Invoke-Pester -Path .\Tests\Unit\Upstream.SyncPorts.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:InstallWin32Path = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Apps\Orchestration\Install-Win32Apps.ps1'
    $script:BuildPath        = Join-Path $PSScriptRoot '..\..\FFUDevelopment\BuildFFUVM.ps1'

    if (-not (Test-Path $script:InstallWin32Path)) { throw "Install-Win32Apps.ps1 not found at $script:InstallWin32Path" }
    if (-not (Test-Path $script:BuildPath))        { throw "BuildFFUVM.ps1 not found at $script:BuildPath" }

    # AST-extract Format-MsiArguments so it can be invoked in isolation
    $installAst = [System.Management.Automation.Language.Parser]::ParseFile($script:InstallWin32Path, [ref]$null, [ref]$null)
    $funcDefs   = $installAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $fmt        = $funcDefs | Where-Object { $_.Name -eq 'Format-MsiArguments' }
    if ($fmt) { Invoke-Expression $fmt.Extent.Text }

    $script:BuildContent = Get-Content -Path $script:BuildPath -Raw
}

Describe 'T1-6: MSI path quoting (Format-MsiArguments)' -Tag 'Unit', 'UpstreamSync', 'Apps' {

    It 'Should be defined in Install-Win32Apps.ps1' {
        Get-Command Format-MsiArguments -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Quotes an unquoted MSI path containing spaces' {
        $result = Format-MsiArguments -CommandLine 'msiexec' -Arguments '/i C:\Program Files\App\setup.msi /qn'
        $result | Should -Be '/i "C:\Program Files\App\setup.msi" /qn'
    }

    It 'Quotes an unquoted MSI path at end of argument string' {
        $result = Format-MsiArguments -CommandLine 'msiexec.exe' -Arguments '/i C:\path with space\thing.msi'
        $result | Should -Be '/i "C:\path with space\thing.msi"'
    }

    It 'Leaves an already-quoted MSI path unchanged' {
        $args = '/i "C:\Program Files\App\setup.msi" /qn'
        Format-MsiArguments -CommandLine 'msiexec' -Arguments $args | Should -Be $args
    }

    It 'Does not modify arguments for non-msiexec commands' {
        $args = '/i C:\Program Files\App\setup.msi /qn'
        Format-MsiArguments -CommandLine 'setup.exe' -Arguments $args | Should -Be $args
    }

    It 'Quotes an unquoted MSI path even without spaces (harmless, matches upstream)' {
        # Upstream behavior: any unquoted /i <...>.msi is wrapped; quoting a space-less
        # path is still a valid msiexec invocation.
        Format-MsiArguments -CommandLine 'msiexec' -Arguments '/i C:\Apps\setup.msi /qn' |
            Should -Be '/i "C:\Apps\setup.msi" /qn'
    }

    It 'Install-Applications invokes Format-MsiArguments before dispatch' {
        $installContent = Get-Content -Path $script:InstallWin32Path -Raw
        $installContent | Should -Match 'Format-MsiArguments\s+-CommandLine\s+\$app\.CommandLine\s+-Arguments\s+\$joinedArgs'
    }
}

Describe 'T1-5: Disk size in VHDX cache validation' -Tag 'Unit', 'UpstreamSync', 'Cache' {

    It 'VhdxCacheItem class declares a Disksize property' {
        $script:BuildContent | Should -Match '\[uint64\]\$Disksize'
    }

    It 'Cache validation rejects a cached config missing Disksize' {
        $script:BuildContent | Should -Match "PSObject\.Properties\.Name -notcontains 'Disksize'"
    }

    It 'Cache validation compares cached Disksize to current Disksize' {
        $script:BuildContent | Should -Match '\$cachedDisksize -ne \$Disksize'
    }

    It 'Cache save persists the current Disksize' {
        $script:BuildContent | Should -Match '\$cachedVHDXInfo\.Disksize = \$Disksize'
    }
}

Describe 'T2-3: Defender Windows Security Platform delay' -Tag 'Unit', 'UpstreamSync', 'Defender' {

    It 'Seeds the Defender install command with a 30-second sleep' {
        $script:BuildContent | Should -Match '\$installDefenderCommand = "Start-Sleep -Seconds 30'
    }
}

Describe 'T2-2: USB drive detection hardening' -Tag 'Unit', 'UpstreamSync', 'USB' {

    It 'Uses Get-CimInstance (not Get-WmiObject) for USB disk enumeration' {
        $script:BuildContent | Should -Match "Get-CimInstance -ClassName Win32_DiskDrive -Filter ""MediaType='Removable Media'"""
    }

    It 'Does not use deprecated Get-WmiObject for Win32_DiskDrive' {
        $script:BuildContent | Should -Not -Match 'Get-WmiObject -Class Win32_DiskDrive'
    }

    It 'Guards no-USB-found using count check rather than null comparison' {
        $script:BuildContent | Should -Match 'if \(\$USBDrives\.Count -eq 0\)'
    }
}
