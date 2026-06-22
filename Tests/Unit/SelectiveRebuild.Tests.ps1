#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Pester 5.x tests for Phase 50 Selective Rebuild Pipeline

.DESCRIPTION
    Tests covering:
    - REBUILD-01: ComboBox Disposition config round-trip (save + restore)
    - D-10/D-11: 4-status scanner UI rendering (Found/Degraded/Error/Missing)
    - ArtifactStatus enum coverage for new Degraded and Error values

.NOTES
    Wave-0 scaffolding: these tests are EXPECTED to be RED (failing) after plan 50-01.
    They will turn GREEN as plans 50-02 through 50-05 implement the production code.
    Tags: Unit, SelectiveRebuild

    InModuleScope note (Phase 46 decision, STATE.md):
    PowerShell module classes and enums are NOT exported to the caller's scope.
    ArtifactStatus assertions use InModuleScope INSIDE It blocks (not wrapping Describe),
    which is the established pattern from FFU.ArtifactScanner.Tests.ps1 lines 92-113.
    Using InModuleScope at Describe level causes Discovery-phase failures because the
    module may not be loaded at parse/discovery time.
#>

BeforeAll {
    # Determine module root relative to test location
    # Test lives at: <repo>/Tests/Unit/SelectiveRebuild.Tests.ps1
    # Repo root is two levels up from the test file
    $testDir  = Split-Path $PSCommandPath -Parent         # .../Tests/Unit
    $testsDir = Split-Path $testDir -Parent               # .../Tests
    $repoRoot = Split-Path $testsDir -Parent              # .../<repo>

    $script:repoRoot = $repoRoot

    $modulePath = Join-Path $repoRoot 'FFUDevelopment\Modules\FFU.ArtifactScanner\FFU.ArtifactScanner.psd1'

    # Add modules path to PSModulePath so RequiredModules can resolve
    $modulesDir = Join-Path $repoRoot 'FFUDevelopment' | Join-Path -ChildPath 'Modules'
    if ($env:PSModulePath -notlike "*$modulesDir*") {
        $env:PSModulePath = "$modulesDir;$env:PSModulePath"
    }

    # Import the FFU.ArtifactScanner module — required for ArtifactStatus enum assertions
    Import-Module $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module FFU.ArtifactScanner -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# ArtifactStatus Enum — D-10/D-11 4-status widening
# =============================================================================

Describe 'ArtifactStatus Enum — 4-status widening' -Tag 'Unit', 'SelectiveRebuild', 'D-10', 'D-11' {

    <#
    InModuleScope is REQUIRED here (Phase 46 decision, STATE.md):
    PowerShell enum types defined inside a module are not exported to the caller's scope.
    Using InModuleScope inside each It block (not at Describe level) is the established
    pattern from FFU.ArtifactScanner.Tests.ps1 lines 92-113.
    These assertions should already be GREEN because the ArtifactStatus enum with
    Degraded and Error was implemented in Phase 46/47.
    #>

    It 'ArtifactStatus enum exposes Degraded value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactStatus]::Degraded } | Should -Not -Throw
            [ArtifactStatus]::Degraded | Should -Be 'Degraded'
        }
    }

    It 'ArtifactStatus enum exposes Error value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactStatus]::Error } | Should -Not -Throw
            [ArtifactStatus]::Error | Should -Be 'Error'
        }
    }

    It 'ArtifactStatus enum exposes Found value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactStatus]::Found } | Should -Not -Throw
            [ArtifactStatus]::Found | Should -Be 'Found'
        }
    }

    It 'ArtifactStatus enum exposes Missing value' {
        InModuleScope FFU.ArtifactScanner {
            { [ArtifactStatus]::Missing } | Should -Not -Throw
            [ArtifactStatus]::Missing | Should -Be 'Missing'
        }
    }

    It 'ArtifactStatus enum has exactly 4 values (Found, Missing, Error, Degraded)' {
        InModuleScope FFU.ArtifactScanner {
            $values = [System.Enum]::GetNames([ArtifactStatus])
            $values.Count | Should -Be 4
        }
    }
}

# =============================================================================
# D-10/D-11 4-status rendering — Handlers source text assertions (Wave-0 RED)
# =============================================================================

Describe 'FFUUI.Core.Handlers — 4-status rendering (D-10/D-11)' -Tag 'Unit', 'SelectiveRebuild', 'D-10', 'D-11' {

    BeforeAll {
        $handlersPath = Join-Path $script:repoRoot 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Handlers.psm1'
        $script:handlersContent = Get-Content -Path $handlersPath -Raw
    }

    Context 'Phase 50 — $artifactMap disposition keys' {

        It '$artifactMap source contains dispCtrl key (renamed from includeCtrl)' {
            # Wave-0 RED: Handlers.psm1 still uses includeCtrl; dispCtrl added in plan 50-03
            $script:handlersContent | Should -Match 'dispCtrl'
        }

        It '$artifactMap source contains tier key for artifact scope classification' {
            # Wave-0 RED: tier key not yet present; added in plan 50-03
            $script:handlersContent | Should -Match "'tier'"
        }

        It '$artifactMap source contains warnCtrl key for Degraded warning surface' {
            # Wave-0 RED: warnCtrl key not yet present; added in plan 50-03
            $script:handlersContent | Should -Match 'warnCtrl'
        }

        It '$artifactMap source does NOT contain includeCtrl (renamed to dispCtrl)' {
            # Wave-0 RED: includeCtrl still present until plan 50-03 renames it
            $script:handlersContent | Should -Not -Match 'includeCtrl'
        }
    }

    Context 'Phase 50 — 4-status rendering switch' {

        It 'Source contains switch over artifact status (not binary if/else)' {
            # Wave-0 RED: binary if/else still present; switch added in plan 50-03
            $script:handlersContent | Should -Match 'switch\s*\(\$result\.Status\.ToString\(\)\)'
        }

        It 'Source contains Degraded case in status switch' {
            # Wave-0 RED: Degraded case not yet present
            $script:handlersContent | Should -Match "'Degraded'"
        }

        It 'Source contains Error case in status switch' {
            # Wave-0 RED: Error case not yet present in the rendering switch
            $script:handlersContent | Should -Match "'Error'"
        }

        It 'Source references DarkOrange for Degraded status foreground' {
            # Wave-0 RED: DarkOrange not yet referenced
            $script:handlersContent | Should -Match 'DarkOrange'
        }

        It 'Source references usb{Type}Warning-style control name' {
            # Wave-0 RED: warnCtrl references not yet present
            $script:handlersContent | Should -Match 'usb\w+Warning'
        }
    }
}

# =============================================================================
# Disposition Config Round-Trip — REBUILD-01 (Wave-0 RED)
# =============================================================================

Describe 'Disposition Config Round-Trip' -Tag 'Unit', 'SelectiveRebuild', 'REBUILD-01' {

    BeforeAll {
        # Import Config module for source-text structural assertions
        # Source-text tests do NOT require WPF runtime
        $projectRoot = $script:repoRoot
        $configModulePath = Join-Path $projectRoot 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1'

        # Stub WriteLog before importing (called at module scope during parse)
        function global:WriteLog { param([string]$Message) }

        Import-Module $configModulePath -Force -ErrorAction Stop

        $script:configContent = Get-Content -Path $configModulePath -Raw
    }

    AfterAll {
        Remove-Module FFUUI.Core.Config -Force -ErrorAction SilentlyContinue
        if (Test-Path 'Function:global:WriteLog') {
            Remove-Item -Path 'Function:global:WriteLog' -ErrorAction SilentlyContinue
        }
    }

    Context 'Build-UIConfiguration source text — Disposition write (Wave-0 RED)' {

        It 'Config module source reads SelectedItem.Tag for disposition (not checkbox IsChecked)' {
            # Wave-0 RED: Config.psm1 still writes Include from checkbox; SelectedItem.Tag added in plan 50-02
            $script:configContent | Should -Match 'SelectedItem\.Tag'
        }

        It 'Config module source writes Disposition key to artifact entry' {
            # Wave-0 RED: Config.psm1 writes both Disposition = ''Reuse'' hardcoded and Include; dynamic Disposition read added in plan 50-02
            $script:configContent | Should -Match '\$disposition'
        }

        It 'Config module source does NOT write Include key for USB artifacts (D-01 removes Include)' {
            # Wave-0 RED: Include key still present until plan 50-02
            $script:configContent | Should -Not -Match "Include\s*=\s*\$includeChecked"
        }

        It 'Config module source references usb{Type}Disposition control name for ComboBox read' {
            # Wave-0 RED: dispCtrlName variable using Disposition suffix not yet present
            $script:configContent | Should -Match 'Disposition'
        }
    }

    Context 'Update-UIFromConfig source text — Disposition restore (Wave-0 RED)' {

        It 'Config module source restores Disposition via PSObject.Properties.Match check' {
            # Wave-0 RED: Update-UIFromConfig still restores Include checkbox; ComboBox restore added in plan 50-02
            $script:configContent | Should -Match "PSObject\.Properties\.Match\('Disposition'\)"
        }

        It 'Config module source does NOT restore Include property for USB artifacts' {
            # Wave-0 RED: Include restore still present until plan 50-02
            $script:configContent | Should -Not -Match "PSObject\.Properties\.Match\('Include'\)"
        }

        It 'Config module source selects ComboBox item by Tag match during restore' {
            # Wave-0 RED: Tag-based restore not yet present; added in plan 50-02
            $script:configContent | Should -Match '\$item\.Tag\s*-eq\s*\$targetDisp'
        }
    }

    Context 'Build-UIConfiguration functional — Rebuild disposition round-trip (Wave-0 RED)' {

        It 'Build-UIConfiguration is exported from Config module' {
            Get-Command -Module 'FFUUI.Core.Config' -Name 'Build-UIConfiguration' | Should -Not -BeNullOrEmpty
        }

        It 'Build-UIConfiguration writes Rebuild disposition to config when ComboBox Tag is Rebuild' {
            # Wave-0 RED: Config.psm1 writes hardcoded Reuse; Rebuild read from ComboBox added in plan 50-02
            $state = [PSCustomObject]@{
                Controls = @{
                    rbUSBMode                  = [PSCustomObject]@{ IsChecked = $true }
                    usbFFUDisposition          = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbDeployISODisposition    = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbDriversDisposition      = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Rebuild' } }
                    usbPPKGDisposition         = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbUnattendDisposition     = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbAutopilotDisposition    = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbAppsISODisposition      = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                }
                Data = @{
                    usbArtifactState = @{
                        FFU       = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        DeployISO = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        Drivers   = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Rebuild' }
                        PPKG      = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        Unattend  = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        Autopilot = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        AppsISO   = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                    }
                }
                FFUDevelopmentPath = 'C:\FFUDevelopment'
            }

            $buildUIConfig = Get-Command -Module 'FFUUI.Core.Config' -Name 'Build-UIConfiguration' -ErrorAction SilentlyContinue
            if ($null -eq $buildUIConfig) {
                Set-ItResult -Skipped -Because 'Build-UIConfiguration not yet exported (Wave-0)'
                return
            }

            $config = Build-UIConfiguration -State $state

            # Wave-0 RED: Config writes hardcoded 'Reuse'; this assertion will fail until plan 50-02
            $config.USBMode.Artifacts['Drivers'].Disposition | Should -Be 'Rebuild'
        }

        It 'Build-UIConfiguration config entry contains NO Include key for any artifact (D-01)' {
            # Wave-0 RED: Config still writes Include key alongside Disposition; removed in plan 50-02
            $state = [PSCustomObject]@{
                Controls = @{
                    rbUSBMode                  = [PSCustomObject]@{ IsChecked = $true }
                    usbFFUDisposition          = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbDeployISODisposition    = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbDriversDisposition      = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbPPKGDisposition         = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbUnattendDisposition     = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbAutopilotDisposition    = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                    usbAppsISODisposition      = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = 'Reuse' } }
                }
                Data = @{
                    usbArtifactState = @{
                        FFU       = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        DeployISO = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        Drivers   = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        PPKG      = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        Unattend  = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        Autopilot = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                        AppsISO   = [PSCustomObject]@{ source = 'auto'; path = $null; disposition = 'Reuse' }
                    }
                }
                FFUDevelopmentPath = 'C:\FFUDevelopment'
            }

            $buildUIConfig = Get-Command -Module 'FFUUI.Core.Config' -Name 'Build-UIConfiguration' -ErrorAction SilentlyContinue
            if ($null -eq $buildUIConfig) {
                Set-ItResult -Skipped -Because 'Build-UIConfiguration not yet exported (Wave-0)'
                return
            }

            $config = Build-UIConfiguration -State $state

            # Wave-0 RED: Include key still present in artifact entries until plan 50-02 removes it
            foreach ($artifactType in @('FFU', 'DeployISO', 'Drivers', 'PPKG', 'Unattend', 'Autopilot', 'AppsISO')) {
                $entry = $config.USBMode.Artifacts[$artifactType]
                $entry.PSObject.Properties.Match('Include').Count | Should -Be 0 `
                    -Because "D-01: Include field removed; Disposition is canonical"
            }
        }
    }
}
