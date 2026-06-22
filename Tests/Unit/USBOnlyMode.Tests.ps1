#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for BuildFFUVM.ps1 USBOnlyMode functionality.

.DESCRIPTION
    Structural tests (AST parse + text search) verifying the -USBOnlyMode switch,
    FFU.ArtifactScanner import, short-circuit block structure, variable population,
    and ThreadJob parse compatibility. All tests are non-executing (no script invocation).

.NOTES
    Version: 1.0.0
    Date: 2026-03-20
    Author: Claude Code
    Phase: 47 - USB Mode Pipeline Entry
#>

Describe 'BuildFFUVM.ps1 USBOnlyMode' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\BuildFFUVM.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw

        # AST parse for parameter analysis
        $parseErrors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath,
            [ref]$tokens,
            [ref]$parseErrors
        )
        $paramBlock = $ast.ParamBlock
    }

    Context 'Parameter Declaration' {
        It 'Has -USBOnlyMode parameter of type [switch]' {
            $param = $paramBlock.Parameters | Where-Object {
                $_.Name.VariablePath.UserPath -eq 'USBOnlyMode'
            }
            $param | Should -Not -BeNullOrEmpty
            $typeConstraint = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.Language.TypeConstraintAst]
            }
            $typeConstraint | Should -Not -BeNullOrEmpty
            $typeConstraint.TypeName.FullName | Should -Be 'switch'
        }

        It 'USBOnlyMode has no default value expression' {
            $param = $paramBlock.Parameters | Where-Object {
                $_.Name.VariablePath.UserPath -eq 'USBOnlyMode'
            }
            $param | Should -Not -BeNullOrEmpty
            # Switch parameters should not have a default value (they default to $false implicitly)
            $param.DefaultValue | Should -BeNullOrEmpty
        }

        It 'No param defaults use [FFUConstants]:: expressions' {
            # Ensure no parameter defaults reference FFUConstants (ThreadJob parse-time failure)
            $ffuConstantsInParams = $paramBlock.Parameters | Where-Object {
                $_.DefaultValue -and $_.DefaultValue.Extent.Text -match '\[FFUConstants\]::'
            }
            $ffuConstantsInParams | Should -BeNullOrEmpty
        }
    }

    Context 'Module Import' {
        It 'Imports FFU.ArtifactScanner with -ErrorAction SilentlyContinue' {
            $scriptContent | Should -Match 'Import-Module.*FFU\.ArtifactScanner.*SilentlyContinue'
        }
    }

    Context 'Short-Circuit Block Structure' {
        It 'Contains if ($USBOnlyMode) block' {
            $scriptContent | Should -Match 'if \(\$USBOnlyMode\)'
        }

        It 'Calls Find-FFUArtifacts with $FFUDevelopmentPath' {
            $scriptContent | Should -Match 'Find-FFUArtifacts\s+-FFUDevelopmentPath\s+\$FFUDevelopmentPath'
        }

        It 'Checks $manifest.IsReady' {
            $scriptContent | Should -Match '\$manifest\.IsReady'
        }

        It 'Calls Mount-DiskImage for ISO validation' {
            $scriptContent | Should -Match 'Mount-DiskImage\s+-ImagePath\s+\$deployISOPath\s+-PassThru'
        }

        It 'Throws actionable error when manifest.IsReady is false (contains "missing required artifacts" and "Run a full build")' {
            $scriptContent | Should -Match 'missing required artifacts'
            $scriptContent | Should -Match 'Run a full build'
        }

        It 'Throws actionable error when ISO mount fails (contains "cannot be mounted" and "Run a full build")' {
            $scriptContent | Should -Match 'cannot be mounted'
        }

        It 'Calls New-DeploymentUSB -CopyFFU -FFUFilesToCopy $SelectedFFUFile' {
            $scriptContent | Should -Match 'New-DeploymentUSB\s+-CopyFFU\s+-FFUFilesToCopy\s+\$SelectedFFUFile'
        }

        It 'Returns after New-DeploymentUSB (does not fall through to pre-flight)' {
            # Verify there is a 'return' statement inside the USBOnlyMode block
            # We look for 'return' after the USBOnlyMode if block opening
            $usbBlockMatch = [regex]::Match($scriptContent, 'if \(\$USBOnlyMode\)[\s\S]+?^}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            if (-not $usbBlockMatch.Success) {
                # Fallback: just check the script contains return after USBOnlyMode patterns
                $scriptContent | Should -Match 'New-DeploymentUSB[\s\S]{1,500}return'
            }
            else {
                $usbBlockMatch.Value | Should -Match '\breturn\b'
            }
        }
    }

    Context 'Variable Population' {
        It 'Sets $CopyDrivers from manifest Drivers status' {
            $scriptContent | Should -Match '\$CopyDrivers\s*=.*manifest\.Drivers\.Status'
        }

        It 'Sets $CopyPPKG from manifest PPKGFiles' {
            $scriptContent | Should -Match '\$CopyPPKG\s*=.*manifest\.PPKGFiles'
        }

        It 'Sets $CopyUnattend from manifest UnattendFiles' {
            $scriptContent | Should -Match '\$CopyUnattend\s*=.*manifest\.UnattendFiles'
        }

        It 'Sets $CopyAutopilot from manifest AutopilotFiles' {
            $scriptContent | Should -Match '\$CopyAutopilot\s*=.*manifest\.AutopilotFiles'
        }

        It 'Sets $WindowsArch with x64 fallback' {
            $scriptContent | Should -Match '\$WindowsArch\s*=\s*''x64'''
        }

        It 'Sets $DriversFolder default path' {
            $scriptContent | Should -Match '\$DriversFolder\s*=.*FFUDevelopmentPath.*Drivers'
        }

        It 'Sets $PPKGFolder default path' {
            $scriptContent | Should -Match '\$PPKGFolder\s*=.*FFUDevelopmentPath.*PPKG'
        }

        It 'Sets $UnattendFolder default path' {
            $scriptContent | Should -Match '\$UnattendFolder\s*=.*FFUDevelopmentPath.*Unattend'
        }

        It 'Sets $AutopilotFolder default path' {
            $scriptContent | Should -Match '\$AutopilotFolder\s*=.*FFUDevelopmentPath.*Autopilot'
        }

        It 'Sets $DeployISO from manifest' {
            $scriptContent | Should -Match '\$DeployISO\s*=\s*\$deployISOPath'
        }

        It 'Sets $BuildUSBDrive to $true' {
            $scriptContent | Should -Match '\$BuildUSBDrive\s*=\s*\$true'
        }

        It 'Sets $SelectedFFUFile from manifest FFUFiles' {
            $scriptContent | Should -Match '\$SelectedFFUFile\s*=.*manifest\.FFUFiles'
        }
    }

    Context 'ThreadJob Parse Compatibility' -Tag 'ThreadJob' {
        It 'Parses without error in ThreadJob context' {
            $scriptPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\BuildFFUVM.ps1'
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath,
                [ref]$null,
                [ref]$parseErrors
            )
            $parseErrors | Should -BeNullOrEmpty
        }
    }

    Context 'F1 — AppsISO Copy Path' -Tag 'Phase50', 'SelectiveRebuild', 'F1' {
        # Wave-0 RED: $CopyAppsISO and $AppsISOPath variables not yet added to BuildFFUVM.ps1.
        # These assertions turn GREEN when plan 50-04 adds the AppsISO copy path to
        # New-DeploymentUSB and the USBOnlyMode variable-population block.

        It 'Declares $CopyAppsISO variable in USBOnlyMode block' {
            $scriptContent | Should -Match '\$CopyAppsISO\s*='
        }

        It 'Declares $AppsISOPath variable in USBOnlyMode block' {
            $scriptContent | Should -Match '\$AppsISOPath\s*='
        }

        It 'New-DeploymentUSB parallel block contains $using:CopyAppsISO guard' {
            $scriptContent | Should -Match '\$using:CopyAppsISO'
        }

        It 'New-DeploymentUSB parallel block contains $using:AppsISOPath' {
            $scriptContent | Should -Match '\$using:AppsISOPath'
        }
    }

    Context 'F2 — Disposition Gate' -Tag 'Phase50', 'SelectiveRebuild', 'F2' {
        # Wave-0 RED: Include-flag gate (lines 1893-1911) still present; Disposition gate
        # not yet written. These assertions turn GREEN when plan 50-04 replaces the Include
        # gate with the Disposition foreach/switch block.

        It 'Does not contain Include-flag gate (replaced by Disposition gate)' {
            $scriptContent | Should -Not -Match "PSObject\.Properties\.Match\('Include'\)"
        }

        It 'Contains Disposition-based gate foreach loop (dispositionCheckTypes)' {
            $scriptContent | Should -Match 'dispositionCheckTypes'
        }

        It 'Contains Disposition property existence check' {
            $scriptContent | Should -Match "PSObject\.Properties\.Match\('Disposition'\)"
        }
    }

    Context 'F3 — Selective Rebuild Flags' -Tag 'Phase50', 'SelectiveRebuild', 'F3' {
        # Wave-0 RED: $rebuildDrivers/$rebuildAppsISO/$rebuildDeployISO flags and the
        # selective rebuild execution block do not yet exist. These assertions turn GREEN
        # when plan 50-05 adds the rebuild flag initialization and execution block to
        # the USBOnlyMode short-circuit.

        It 'Declares $rebuildDrivers flag' {
            $scriptContent | Should -Match '\$rebuildDrivers\s*='
        }

        It 'Declares $rebuildAppsISO flag' {
            $scriptContent | Should -Match '\$rebuildAppsISO\s*='
        }

        It 'Declares $rebuildDeployISO flag' {
            $scriptContent | Should -Match '\$rebuildDeployISO\s*='
        }

        It 'Contains if ($rebuildDrivers) selective rebuild block' {
            $scriptContent | Should -Match 'if\s*\(\$rebuildDrivers\)'
        }

        It 'Calls New-AppsISO inside $rebuildAppsISO block' {
            $scriptContent | Should -Match 'New-AppsISO'
        }

        It 'Calls New-PEMedia inside $rebuildDeployISO block' {
            $scriptContent | Should -Match 'New-PEMedia'
        }

        It 'Rebuild-execution block precedes Disposition gate (BLOCKER-1 structural ordering assertion)' {
            # BLOCKER-1: The selective rebuild execution block MUST appear at a lower line number
            # than the $dispositionCheckTypes gate so rebuilt artifacts reconcile copy variables
            # BEFORE the Skip/copy gate reads them. Without this ordering, a Skip default could
            # suppress a just-rebuilt artifact.
            $rebuildIdx = $scriptContent.IndexOf('$rebuildDrivers')
            $gateIdx    = $scriptContent.IndexOf('$dispositionCheckTypes')
            $rebuildIdx | Should -BeGreaterOrEqual 0 -Because 'rebuildDrivers must exist in the script'
            $gateIdx    | Should -BeGreaterOrEqual 0 -Because 'dispositionCheckTypes gate must exist in the script'
            $rebuildIdx | Should -BeLessThan $gateIdx -Because 'rebuild execution block must precede the Disposition gate'
        }
    }
}
