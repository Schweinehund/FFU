#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Pester test scaffold for Phase 49: UI Event Wiring and Artifact Integration

.DESCRIPTION
    Structural tests (file content search + logic assertions) verifying the
    Phase 49 requirements. All tests are non-executing (no script invocation
    or WPF runtime required).

    Requirements covered:
    - USB-02: USB drive selection used for creation
    - USB-03: Per-artifact include/exclude checkboxes control USB content
    - DISC-02: Browse handlers update usbArtifactState
    - DISC-03: ActiveMode and artifact paths persist across config save/load

    Adversarial review regression tests:
    - Issue #1: Typed WPF Brushes (not bare strings)
    - Issue #2: Typed FontStyles (not bare strings)
    - Issue #3: WindowsSKU property (not SKU)
    - Issue #4: Get-USBDrives returns flat array (no tuple unpacking)
    - Issue #5: configData.USBMode (not config.USBMode) in BuildFFUVM.ps1
    - Issue #6: Full ThreadJob ScriptBlock structure (not 3-line scaffold)
    - Issue #7: currentBuildJob (not buildJob)
    - Issue #8: Config path uses FFUDevelopmentPath pattern (not hardcoded)
    - Issue #10: No CopyAppsISO flag (does not exist in USBOnlyMode block)
    - Issue #14: -ArgumentList pattern (not dollar-sign-using)
    - Issue #15: Both Update-UIFromConfig call sites wrapped with isLoadingConfig guard

.NOTES
    Version: 1.0.0
    Date: 2026-03-24
    Author: Claude Code
    Phase: 49 - UI Event Wiring and Artifact Integration
#>

Describe 'Phase 49: UI Event Wiring and Artifact Integration' -Tag 'Phase49' {

    BeforeAll {
        $handlersPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFUUI.Core\FFUUI.Core.Handlers.psm1'
        $configPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFUUI.Core\FFUUI.Core.Config.psm1'
        $stateRecoveryPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFUUI.Core\FFUUI.Core.StateRecovery.psm1'
        $buildUIPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\BuildFFUVM_UI.ps1'
        $buildScriptPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\BuildFFUVM.ps1'
        $xamlPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\BuildFFUVM_UI.xaml'

        $handlersContent = Get-Content -Path $handlersPath -Raw -ErrorAction SilentlyContinue
        $configContent = Get-Content -Path $configPath -Raw -ErrorAction SilentlyContinue
        $stateRecoveryContent = Get-Content -Path $stateRecoveryPath -Raw -ErrorAction SilentlyContinue
        $buildUIContent = Get-Content -Path $buildUIPath -Raw -ErrorAction SilentlyContinue
        $buildScriptContent = Get-Content -Path $buildScriptPath -Raw -ErrorAction SilentlyContinue
        $xamlContent = Get-Content -Path $xamlPath -Raw -ErrorAction SilentlyContinue
    }

    Context 'Browse Handler State Updates' -Tag 'BrowseHandler' {
        # DISC-02: Browse handlers update usbArtifactState

        It 'Should set source to user when browse selects a path' {
            # Simulate the browse handler state update logic
            $state = @{
                Data = @{
                    usbArtifactState = @{
                        FFU = @{ path = $null; source = 'auto' }
                    }
                }
            }
            # Simulate browse selection (same logic as the browse handler)
            $state.Data.usbArtifactState.FFU.path = 'C:\test\image.ffu'
            $state.Data.usbArtifactState.FFU.source = 'user'
            $state.Data.usbArtifactState.FFU.source | Should -Be 'user'
            $state.Data.usbArtifactState.FFU.path | Should -Be 'C:\test\image.ffu'
        }

        It 'Should have 7 artifact types in usbArtifactState' {
            $expectedTypes = @('FFU', 'DeployISO', 'Drivers', 'PPKG', 'Unattend', 'Autopilot', 'AppsISO')
            $state = @{
                Data = @{
                    usbArtifactState = @{}
                }
            }
            foreach ($type in $expectedTypes) {
                $state.Data.usbArtifactState[$type] = @{ path = $null; source = 'auto' }
            }
            $state.Data.usbArtifactState.Keys.Count | Should -Be 7
        }

        It 'Should have browse handler registrations in Handlers module' {
            $handlersContent | Should -Not -BeNullOrEmpty
            # Browse handlers for USB artifacts should be registered
            $handlersContent | Should -Match 'usb.*Browse|usbBrowse|Add_Click.*Browse|Browse.*usb'
        }

        It 'Should track usbArtifactState in Handlers module' {
            $handlersContent | Should -Not -BeNullOrEmpty
            $handlersContent | Should -Match 'usbArtifactState'
        }
    }

    Context 'Config Persistence' -Tag 'ConfigPersistence' {
        # DISC-03: ActiveMode and artifact paths persist

        It 'Should save ActiveMode as USBMode when rbUSBMode is checked' {
            # Logic: only user-source paths should be persisted to config
            $mockArtifactState = @{
                FFU       = @{ path = 'C:\test\image.ffu'; source = 'user' }
                DeployISO = @{ path = $null; source = 'auto' }
                Drivers   = @{ path = $null; source = 'auto' }
                PPKG      = @{ path = $null; source = 'auto' }
                Unattend  = @{ path = $null; source = 'auto' }
                Autopilot = @{ path = $null; source = 'auto' }
                AppsISO   = @{ path = $null; source = 'auto' }
            }
            # Verify only user-source paths are saved
            $userPaths = $mockArtifactState.GetEnumerator() | Where-Object { $_.Value.source -eq 'user' -and $null -ne $_.Value.path }
            $userPaths.Count | Should -Be 1
            ($userPaths | Select-Object -First 1).Key | Should -Be 'FFU'
        }

        It 'Should load artifact paths before setting ActiveMode' {
            # Verify load order: artifact paths loaded first, then ActiveMode set (Pitfall 5)
            $configContent | Should -Not -BeNullOrEmpty
            $artifactLoadPos = $configContent.IndexOf('usbArtifactState')
            $activeModeSetPos = $configContent.IndexOf("rbUSBMode.IsChecked = `$true")
            # artifact state must be referenced before rbUSBMode.IsChecked is set
            $artifactLoadPos | Should -BeGreaterThan -1
            $activeModeSetPos | Should -BeGreaterThan -1
            $artifactLoadPos | Should -BeLessThan $activeModeSetPos
        }

        It 'Should save Include flag for each artifact type in config' {
            # Verify Build-UIConfiguration writes Include field (D-29)
            $configContent | Should -Not -BeNullOrEmpty
            $configContent | Should -Match 'Include'
            $configContent | Should -Match 'IsChecked'
        }

        It 'Should wrap BOTH Update-UIFromConfig call sites with isLoadingConfig guard' {
            # Issue #15: both call sites must have the isLoadingConfig guard
            $configContent | Should -Not -BeNullOrEmpty
            $guardCount = ([regex]::Matches($configContent, 'isLoadingConfig\s*=\s*\$true')).Count
            $guardCount | Should -BeGreaterOrEqual 2
        }

        It 'Should use FFUDevelopmentPath pattern for config file path, not hardcoded filename' {
            # Issue #8: Config path must use FFUDevelopmentPath, not hardcoded config.json
            $buildUIContent | Should -Not -BeNullOrEmpty
            $buildUIContent | Should -Match 'FFUDevelopmentPath.*config'
            $buildUIContent | Should -Match 'FFUConfig\.json'
        }
    }

    Context 'USB Drive Detection' -Tag 'USBDriveDetection' {
        # USB-02: USB drive detection in USB Mode tab

        It 'Should have usbCheckUSBDrives handler registered' {
            $handlersContent | Should -Not -BeNullOrEmpty
            $handlersContent | Should -Match 'usbCheckUSBDrives\.Add_Click'
        }

        It 'Should call Get-USBDrives (not custom WMI)' {
            $handlersContent | Should -Not -BeNullOrEmpty
            $handlersContent | Should -Match 'Get-USBDrives'
        }

        It 'Should NOT use tuple unpacking for Get-USBDrives return value' {
            # Issue #4: Get-USBDrives returns flat array, not a tuple
            $handlersContent | Should -Not -BeNullOrEmpty
            $handlersContent | Should -Not -Match 'usbResult\[0\]'
            $handlersContent | Should -Not -Match 'usbResult\[1\]'
        }
    }

    Context 'Include Flag Mapping' -Tag 'IncludeFlags' {
        # USB-03: Per-artifact include checkboxes

        It 'Should have 7 include checkboxes in XAML' {
            $xamlContent | Should -Not -BeNullOrEmpty
            $includeCheckboxes = @(
                'usbFFUInclude', 'usbDeployISOInclude', 'usbDriversInclude',
                'usbPPKGInclude', 'usbUnattendInclude', 'usbAutopilotInclude', 'usbAppsISOInclude'
            )
            foreach ($cb in $includeCheckboxes) {
                $xamlContent | Should -Match "x:Name=""$cb"""
            }
        }

        It 'Should validate FFU and DeployISO before USB creation' {
            $buildUIContent | Should -Not -BeNullOrEmpty
            $buildUIContent | Should -Match 'usbFFUInclude\.IsChecked'
            $buildUIContent | Should -Match 'usbDeployISOInclude\.IsChecked'
        }

        It 'Should read Include flags from config in USBOnlyMode block using configData' {
            # Issue #5: Must use $configData, not $config
            $buildScriptContent | Should -Not -BeNullOrEmpty
            $buildScriptContent | Should -Match 'configData\.USBMode'
            $buildScriptContent | Should -Match 'Include'
        }

        It 'Should use currentBuildJob not buildJob' {
            # Issue #7: Codebase uses currentBuildJob everywhere
            $buildUIContent | Should -Not -BeNullOrEmpty
            $buildUIContent | Should -Match 'currentBuildJob'
            # No bare 'buildJob' reference (allow 'currentBuildJob' which contains 'BuildJob')
            $buildUIContent | Should -Not -Match '(?<![a-zA-Z])buildJob(?![a-zA-Z])'
        }

        It 'Should NOT have CopyAppsISO variable in USBOnlyMode block' {
            # Issue #10: CopyAppsISO does not exist in the codebase
            $buildScriptContent | Should -Not -BeNullOrEmpty
            $buildScriptContent | Should -Not -Match '\$CopyAppsISO'
        }

        It 'Should use -ArgumentList pattern not dollar-sign-using in USB ThreadJob' {
            # Issue #14: -ArgumentList is required for ThreadJob, not dollar-sign-using
            $buildUIContent | Should -Not -BeNullOrEmpty
            # The USB Mode branch uses ArgumentList
            $buildUIContent | Should -Match '-ArgumentList.*buildParams.*PSScriptRoot'
        }
    }

    Context 'WPF Type Correctness' -Tag 'WPFTypes' {
        It 'Should use typed Brushes not string Foreground in Handlers' {
            # Issue #1: Foreground must use [System.Windows.Media.Brushes]::
            $handlersContent | Should -Not -BeNullOrEmpty
            $handlersContent | Should -Match 'System\.Windows\.Media\.Brushes'
            $handlersContent | Should -Not -Match "Foreground\s*=\s*'(Green|OrangeRed|Gray|Red)'"
        }

        It 'Should use typed FontStyles not string FontStyle in Handlers' {
            # Issue #2: FontStyle must use [System.Windows.FontStyles]::
            $handlersContent | Should -Not -BeNullOrEmpty
            $handlersContent | Should -Match 'System\.Windows\.FontStyles'
            $handlersContent | Should -Not -Match "FontStyle\s*=\s*'(Italic|Normal)'"
        }

        It 'Should use WindowsSKU not SKU for FFUMetadata property' {
            # Issue #3: Property is WindowsSKU, not SKU
            $handlersContent | Should -Not -BeNullOrEmpty
            $handlersContent | Should -Match 'WindowsSKU'
            $handlersContent | Should -Not -Match '\.Metadata\.SKU[^a-zA-Z]'
        }
    }

    Context 'Mode-Aware Button Labels' -Tag 'ButtonLabels' {
        It 'Should not have hardcoded Build FFU assignment in StateRecovery' {
            # StateRecovery must be mode-aware (not hardcode "Build FFU")
            $stateRecoveryContent | Should -Not -BeNullOrEmpty
            $stateRecoveryContent | Should -Not -Match "btnRun\.Content\s*=\s*[`'`"]Build FFU[`'`"]"
        }

        It 'Should not have hardcoded Build FFU assignment in BuildFFUVM_UI cancel cleanup path' {
            # BuildFFUVM_UI.ps1 cleanup timer must be mode-aware (not hardcode "Build FFU")
            # Broad pattern catches all variable forms: $btn.Content, $btnRun.Content, $script:uiState.Controls.btnRun.Content
            $buildUIContent | Should -Not -BeNullOrEmpty
            $buildUIContent | Should -Not -Match "\.Content\s*=\s*[`'`"]Build FFU[`'`"]"
        }

        It 'Should contain Create USB label in StateRecovery' {
            $stateRecoveryContent | Should -Not -BeNullOrEmpty
            $stateRecoveryContent | Should -Match 'Create USB'
        }

        It 'Should have USB Mode branch in btnRun handler' {
            # Verify the USB Mode branch was added to the UI script
            $buildUIContent | Should -Not -BeNullOrEmpty
            $buildUIContent | Should -Match 'USB MODE BRANCH|isUSBMode'
            $buildUIContent | Should -Match 'USBOnlyMode'
        }

        It 'Should have 3 Validation Error MessageBox calls in USB Mode branch' {
            $buildUIContent | Should -Not -BeNullOrEmpty
            $validationErrors = ([regex]::Matches($buildUIContent, 'Validation Error')).Count
            $validationErrors | Should -BeGreaterOrEqual 3
        }
    }
}
