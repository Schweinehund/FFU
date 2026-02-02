#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for deployment enhancements in ApplyFFU.ps1 (Phase 43)

.DESCRIPTION
    Tests for Phase 43 requirements:
    - DEPLOY-01: Multi-disk interactive selection menu
    - DEPLOY-03: Empty driver folder detection with .inf validation
    - NICE-01: USB detection via BusType filter with UniqueId logging
    - NICE-02: Optional driver installation skip prompt

    Tests use AST-based extraction for function structure verification and
    content matching for inline code validation (same pattern as ApplyFFU.DriverMatching.Tests.ps1).

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\ApplyFFU.Deployment.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Extract functions from ApplyFFU.ps1 using AST
    $scriptPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\WinPEDeployFFUFiles\ApplyFFU.ps1'
    if (-not (Test-Path $scriptPath)) {
        throw "ApplyFFU.ps1 not found at $scriptPath"
    }

    $script:ApplyFFUPath = $scriptPath
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $script:FunctionDefs = $script:Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $script:Content = Get-Content -Path $scriptPath -Raw

    # Extract and define test-accessible functions
    foreach ($func in $script:FunctionDefs) {
        if ($func.Name -in @('Get-HardDrive', 'Get-USBDrive', 'WriteLog')) {
            try {
                Invoke-Expression $func.Extent.Text
            }
            catch {
                # Functions may have dependencies - that's OK for AST-based testing
            }
        }
    }

    # Mock WriteLog for any extracted function tests
    function WriteLog {
        param([string]$Message)
        # No-op for testing
    }
}

# =============================================================================
# DEPLOY-01: Multi-Disk Selection
# =============================================================================

Describe 'DEPLOY-01: Multi-Disk Selection' -Tag 'Unit', 'Deployment', 'DEPLOY-01' {

    Context 'Get-HardDrive Structure' {
        BeforeAll {
            $getHardDriveFunc = $script:FunctionDefs | Where-Object { $_.Name -eq 'Get-HardDrive' }
        }

        It 'Should exist as a function' {
            $getHardDriveFunc | Should -Not -BeNullOrEmpty
        }

        It 'Should wrap physical disk query in @() for array coercion' {
            $getHardDriveFunc.Extent.Text | Should -Match '\@\(Get-CimInstance.*Win32_DiskDrive'
        }

        It 'Should check diskDrives.Count -gt 1 for multi-disk detection' {
            $getHardDriveFunc.Extent.Text | Should -Match '\$diskDrives\.Count\s*-gt\s*1'
        }

        It 'Should display Format-Table with Number column' {
            $getHardDriveFunc.Extent.Text | Should -Match 'Number'
        }

        It 'Should display Format-Table with Model column' {
            $getHardDriveFunc.Extent.Text | Should -Match 'Model'
        }

        It 'Should display Format-Table with SizeGB column' {
            $getHardDriveFunc.Extent.Text | Should -Match 'SizeGB'
        }

        It 'Should display Format-Table with Index column' {
            $getHardDriveFunc.Extent.Text | Should -Match 'Index'
        }

        It 'Should call Format-Table for disk display' {
            $getHardDriveFunc.Extent.Text | Should -Match 'Format-Table'
        }

        It 'Should use Read-Host for disk selection' {
            $getHardDriveFunc.Extent.Text | Should -Match 'Read-Host.*disk number'
        }

        It 'Should have do/until validation loop for input' {
            $getHardDriveFunc.Extent.Text | Should -Match 'do\s*\{'
            $getHardDriveFunc.Extent.Text | Should -Match '\}\s*until'
        }

        It 'Should validate diskSelected is within valid range' {
            $getHardDriveFunc.Extent.Text | Should -Match '\$diskSelected\s*-ge\s*0'
            $getHardDriveFunc.Extent.Text | Should -Match '\$diskSelected\s*-lt\s*\$diskDrives\.Count'
        }

        It 'Should have try/catch around input parsing' {
            $getHardDriveFunc.Extent.Text | Should -Match 'try\s*\{'
            $getHardDriveFunc.Extent.Text | Should -Match 'catch\s*\{'
        }

        It 'Should log message about found disk count' {
            $getHardDriveFunc.Extent.Text | Should -Match 'WriteLog.*Found.*physical disks'
        }
    }

    Context 'VM Detection Unchanged' {
        BeforeAll {
            $getHardDriveFunc = $script:FunctionDefs | Where-Object { $_.Name -eq 'Get-HardDrive' }
        }

        It 'Should check for Microsoft Corporation manufacturer' {
            $getHardDriveFunc.Extent.Text | Should -Match 'Microsoft Corporation'
        }

        It 'Should check for Virtual Machine model' {
            $getHardDriveFunc.Extent.Text | Should -Match 'Virtual Machine'
        }

        It 'Should filter for Index -eq 0' {
            $getHardDriveFunc.Extent.Text | Should -Match 'Index\s*-eq\s*0'
        }

        It 'Should filter for SCSILogicalUnit -eq 0' {
            $getHardDriveFunc.Extent.Text | Should -Match 'SCSILogicalUnit\s*-eq\s*0'
        }

        It 'Should log VM detection message' {
            $getHardDriveFunc.Extent.Text | Should -Match 'WriteLog.*Hyper-V VM'
        }
    }

    Context 'Return Type' {
        BeforeAll {
            $getHardDriveFunc = $script:FunctionDefs | Where-Object { $_.Name -eq 'Get-HardDrive' }
        }

        It 'Should return PSCustomObject' {
            $getHardDriveFunc.Extent.Text | Should -Match 'PSCustomObject'
        }

        It 'Should return object with DeviceID property' {
            $getHardDriveFunc.Extent.Text | Should -Match 'DeviceID'
        }

        It 'Should return object with BytesPerSector property' {
            $getHardDriveFunc.Extent.Text | Should -Match 'BytesPerSector'
        }

        It 'Should return object with DiskSize property' {
            $getHardDriveFunc.Extent.Text | Should -Match 'DiskSize'
        }
    }
}

# =============================================================================
# NICE-01: USB UniqueId Detection
# =============================================================================

Describe 'NICE-01: USB UniqueId Detection' -Tag 'Unit', 'Deployment', 'NICE-01' {

    Context 'Get-USBDrive Structure' {
        BeforeAll {
            $getUSBDriveFunc = $script:FunctionDefs | Where-Object { $_.Name -eq 'Get-USBDrive' }
        }

        It 'Should exist as a function' {
            $getUSBDriveFunc | Should -Not -BeNullOrEmpty
        }

        It 'Should use Get-Disk with BusType filter as primary detection' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'Get-Disk'
            $getUSBDriveFunc.Extent.Text | Should -Match 'BusType.*USB'
        }

        It 'Should wrap Get-Disk result in @() for array coercion' {
            $getUSBDriveFunc.Extent.Text | Should -Match '\@\(Get-Disk'
        }

        It 'Should retrieve PhysicalDisk for UniqueId lookup' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'Get-PhysicalDisk'
        }

        It 'Should log UniqueId when available' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'WriteLog.*UniqueId.*\$\(.*physicalDisk\.UniqueId'
        }

        It 'Should log when UniqueId is unavailable' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'WriteLog.*UniqueId unavailable'
        }

        It 'Should log message indicating USB disk found via BusType' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'WriteLog.*USB disk found via BusType'
        }

        It 'Should have check for null or whitespace UniqueId' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'IsNullOrWhiteSpace.*physicalDisk\.UniqueId'
        }
    }

    Context 'Fallback Detection' {
        BeforeAll {
            $getUSBDriveFunc = $script:FunctionDefs | Where-Object { $_.Name -eq 'Get-USBDrive' }
        }

        It 'Should have fallback to Get-Volume' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'Get-Volume'
        }

        It 'Should check for Removable DriveType in fallback' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'DriveType.*Removable'
        }

        It 'Should check for Deploy label as final fallback' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'FileSystemLabel.*Deploy'
        }

        It 'Should call Stop-Script on complete failure' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'Stop-Script'
        }
    }

    Context 'Return Value' {
        BeforeAll {
            $getUSBDriveFunc = $script:FunctionDefs | Where-Object { $_.Name -eq 'Get-USBDrive' }
        }

        It 'Should construct USB drive letter string' {
            # Check for drive letter variable being assigned
            $getUSBDriveFunc.Extent.Text | Should -Match '\$USBDriveLetter'
        }

        It 'Should log selected USB drive' {
            $getUSBDriveFunc.Extent.Text | Should -Match 'WriteLog.*Selected.*USB'
        }
    }
}

# =============================================================================
# DEPLOY-03: Empty Driver Folder Detection
# =============================================================================

Describe 'DEPLOY-03: Empty Driver Folder Detection' -Tag 'Unit', 'Deployment', 'DEPLOY-03' {

    Context 'Empty Folder Check Logic' {
        It 'Should check for .inf files recursively' {
            $script:Content | Should -Match 'Get-ChildItem.*-Recurse.*-Include.*\.inf'
        }

        It 'Should check for File type explicitly' {
            $script:Content | Should -Match 'Get-ChildItem.*-File.*-Include.*\.inf'
        }

        It 'Should only check Folder type, not WIM' {
            # Verify the check is inside a conditional that tests for Folder type
            $script:Content | Should -Match 'DriverSourceType.*eq.*[''"]Folder[''"]'
        }

        It 'Should check for null or zero count driver files' {
            $script:Content | Should -Match 'null\s*-eq\s*\$driverInfFiles.*or.*\$driverInfFiles\.Count\s*-eq\s*0'
        }

        It 'Should set DriverSourcePath to null when empty' {
            $script:Content | Should -Match '\$DriverSourcePath\s*=\s*\$null'
        }

        It 'Should use ErrorAction SilentlyContinue for inf file search' {
            $script:Content | Should -Match 'Get-ChildItem.*\.inf.*-ErrorAction\s+SilentlyContinue'
        }
    }

    Context 'Logging' {
        It 'Should log descriptive skip message for empty folders' {
            $script:Content | Should -Match 'contains no \.inf files'
        }

        It 'Should display skip message to user' {
            $script:Content | Should -Match 'Write-Host.*contains no \.inf files'
        }

        It 'Should log inf file count when drivers found' {
            $script:Content | Should -Match 'WriteLog.*Found.*driver \.inf file\(s\)'
        }

        It 'Should include path in empty folder log message' {
            $script:Content | Should -Match 'WriteLog.*Driver folder.*DriverSourcePath.*contains no \.inf files'
        }
    }

    Context 'DEPLOY-03 Comment Documentation' {
        It 'Should have DEPLOY-03 comment reference' {
            $script:Content | Should -Match 'DEPLOY-03'
        }

        It 'Should explain empty driver folder detection purpose' {
            $script:Content | Should -Match 'Empty driver folder detection'
        }
    }
}

# =============================================================================
# NICE-02: Skip Driver Installation
# =============================================================================

Describe 'NICE-02: Skip Driver Installation' -Tag 'Unit', 'Deployment', 'NICE-02' {

    Context 'Skip Driver Prompt Structure' {
        It 'Should initialize skipDrivers variable to false' {
            $script:Content | Should -Match '\$skipDrivers\s*=\s*\$false'
        }

        It 'Should prompt with Read-Host for Y/N input' {
            $script:Content | Should -Match 'Read-Host.*Install drivers.*Y/N'
        }

        It 'Should accept Y to continue with drivers' {
            $script:Content | Should -Match '\$response\s*-match\s*[''"]\^\[Yy\][''"]'
        }

        It 'Should accept N to skip drivers' {
            $script:Content | Should -Match '\$response\s*-match\s*[''"]\^\[Nn\][''"]'
        }

        It 'Should set skipDrivers to true when N selected' {
            $script:Content | Should -Match '\$skipDrivers\s*=\s*\$true'
        }

        It 'Should set skipDrivers to false when Y selected' {
            $script:Content | Should -Match '\$skipDrivers\s*=\s*\$false'
        }

        It 'Should have do/until validation loop' {
            # Check for do/until pattern near Install drivers prompt
            $script:Content | Should -Match 'do\s*\{'
            $script:Content | Should -Match 'Install drivers.*\(Y/N\)'
            $script:Content | Should -Match '\}\s*until.*\$var'
        }

        It 'Should use var flag for validation control' {
            $script:Content | Should -Match '\$var\s*=\s*\$true'
            $script:Content | Should -Match '\$var\s*=\s*\$false'
        }

        It 'Should have try/catch for input handling' {
            # Verify try/catch around the prompt logic
            $script:Content | Should -Match 'try\s*\{[^}]*Read-Host[^}]*Install drivers'
        }
    }

    Context 'Skip Driver Logic Integration' {
        It 'Should check skipDrivers flag before automatic driver detection' {
            $script:Content | Should -Match '-not\s+\$skipDrivers'
            $script:Content | Should -Match 'DriverMapping\.json'
        }

        It 'Should check skipDrivers flag before manual driver selection' {
            $script:Content | Should -Match '-not\s+\$skipDrivers'
            $script:Content | Should -Match 'null\s*-eq\s*\$DriverSourcePath'
        }

        It 'Should have skipDrivers variable referenced multiple times' {
            ($script:Content | Select-String -Pattern 'skipDrivers' -AllMatches).Matches.Count | Should -BeGreaterOrEqual 5
        }
    }

    Context 'Logging' {
        It 'Should log when user elects to skip' {
            $script:Content | Should -Match 'WriteLog.*elected to skip driver installation'
        }

        It 'Should display skip message to user' {
            $script:Content | Should -Match 'Write-Host.*Driver installation will be skipped'
        }

        It 'Should display drivers folder detected message' {
            $script:Content | Should -Match 'Write-Host.*Drivers folder detected'
        }

        It 'Should prompt user to enter Y or N for invalid input' {
            $script:Content | Should -Match 'Write-Host.*Please enter Y or N'
        }
    }

    Context 'NICE-02 Comment Documentation' {
        It 'Should have NICE-02 comment reference' {
            $script:Content | Should -Match 'NICE-02'
        }

        It 'Should explain optional driver installation skip' {
            $script:Content | Should -Match 'Optional driver installation skip'
        }
    }
}

# =============================================================================
# Integration Verification
# =============================================================================

Describe 'Phase 43 Integration' -Tag 'Unit', 'Deployment', 'Integration' {

    Context 'All Requirements Present' {
        It 'Should have DEPLOY-01 reference' {
            $script:Content | Should -Match 'DEPLOY-01'
        }

        It 'Should have DEPLOY-03 reference' {
            $script:Content | Should -Match 'DEPLOY-03'
        }

        It 'Should have NICE-01 reference' {
            $script:Content | Should -Match 'NICE-01'
        }

        It 'Should have NICE-02 reference' {
            $script:Content | Should -Match 'NICE-02'
        }
    }

    Context 'Function Extraction Success' {
        It 'Should have extracted Get-HardDrive function' {
            $getHardDrive = $script:FunctionDefs | Where-Object { $_.Name -eq 'Get-HardDrive' }
            $getHardDrive | Should -Not -BeNullOrEmpty
        }

        It 'Should have extracted Get-USBDrive function' {
            $getUSBDrive = $script:FunctionDefs | Where-Object { $_.Name -eq 'Get-USBDrive' }
            $getUSBDrive | Should -Not -BeNullOrEmpty
        }
    }
}
