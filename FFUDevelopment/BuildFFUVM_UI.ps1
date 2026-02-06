<#
.SYNOPSIS
    Launches the FFU Development UI, a WPF application for configuring and running the FFU build process.
.DESCRIPTION
    The BuildFFUVM_UI.ps1 script is the main entry point for the FFU Development user interface. It initializes and displays a WPF-based graphical interface defined in BuildFFUVM_UI.xaml.

    The script is responsible for:
    - Initializing a global state object to manage UI controls, data, and application flags.
    - Importing the required FFU.Common and FFUUI.Core modules which contain the business logic.
    - Ensuring system prerequisites, such as PowerShell 7 and Long Path Support, are met.
    - Loading the XAML window, initializing UI controls with default values, and registering all event handlers.
    - Launching the core build script (BuildFFUVM.ps1) in a background job when the user initiates a build.
    - Providing real-time feedback by monitoring the build log file and updating the UI's progress bar and log viewer.
    - Handling cleanup operations, such as reverting system settings, when the application is closed.

    This script acts as the primary host for the UI, connecting the user interface with the underlying build and logic modules.
#>
#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding()]
[System.STAThread()]
param()

# Check PowerShell Version
# Note: FFUBuilder requires PowerShell 7.0 or later
# - PowerShell 7+ provides modern features, performance, and cross-platform compatibility
# - Windows management cmdlets use .NET DirectoryServices APIs for compatibility
# - The #Requires -Version 7.0 directive above enforces this requirement
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "PowerShell 7.0 or later is required to run this script. Please install PowerShell 7 from https://aka.ms/powershell"
    exit 1
}

# FFU Builder Version - loaded from version.json (single source of truth)
$FFUDevelopmentPath = $PSScriptRoot
$script:versionJsonPath = Join-Path $FFUDevelopmentPath "version.json"
if (Test-Path $script:versionJsonPath) {
    $script:versionInfo = Get-Content $script:versionJsonPath -Raw | ConvertFrom-Json
    $script:FFUBuilderVersion = $script:versionInfo.version
    $script:FFUBuilderBuildDate = $script:versionInfo.buildDate
    $script:FFUBuilderModules = $script:versionInfo.modules
}
else {
    # Fallback if version.json not found
    $script:FFUBuilderVersion = "1.2.0"
    $script:FFUBuilderBuildDate = "2025-12-09"
    $script:FFUBuilderModules = $null
    Write-Warning "version.json not found at $script:versionJsonPath - using fallback version"
}

# Creating custom state object to hold UI state and data

$script:uiState = [PSCustomObject]@{
    FFUDevelopmentPath = $FFUDevelopmentPath;
    Window             = $null;
    Controls           = @{
        featureCheckBoxes               = @{};
        UpdateInstallAppsBasedOnUpdates = $null
    };
    Data               = @{
        allDriverModels             = [System.Collections.Generic.List[PSCustomObject]]::new();
        appsScriptVariablesDataList = [System.Collections.Generic.List[PSCustomObject]]::new();
        versionData                 = $null;
        vmSwitchMap                 = @{};
        logData                     = $null;
        pollTimer                   = $null;
        lastConfigFilePath          = $null;
        messagingContext            = $null;   # Synchronized queue for real-time UI updates
        configValidationResult      = $null;   # REL-UI-05: Stores validation result from config loading
        hasValidationErrors         = $false   # REL-UI-05: Quick flag for build-time check
    };
    Flags              = @{
        installAppsForcedByUpdates        = $false;
        prevInstallAppsStateBeforeUpdates = $null;
        installAppsCheckedByOffice        = $false;
        lastSortProperty                  = $null;
        lastSortAscending                 = $true;
        isBuilding                        = $false;
        isCleanupRunning                  = $false
    };
    Defaults           = @{};
    LogFilePath        = "$FFUDevelopmentPath\FFUDevelopment_UI.log";
    Version            = @{
        Number    = $script:FFUBuilderVersion
        BuildDate = $script:FFUBuilderBuildDate
        Modules   = $script:FFUBuilderModules
    }
}

# Remove any existing modules to avoid conflicts
if (Get-Module -Name 'FFU.Common' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFU.Common' -Force
}
if (Get-Module -Name 'FFUUI.Core' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFUUI.Core' -Force
}
if (Get-Module -Name 'FFU.Messaging' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFU.Messaging' -Force
}
# Import Modules
Import-Module "$PSScriptRoot\FFU.Common" -Force
Import-Module "$PSScriptRoot\FFUUI.Core" -Force
# Import FFU.Messaging for real-time UI updates via synchronized queue
# This provides ~20x faster updates (50ms vs 1000ms) compared to file polling
Import-Module "$PSScriptRoot\Modules\FFU.Messaging" -Force -DisableNameChecking

# Set the log path IMMEDIATELY after module imports, BEFORE any WriteLog calls
# This prevents "CommonCoreLogFilePath not set" warnings during ThreadJob handling
Set-CommonCoreLogPath -Path $script:uiState.LogFilePath

# Import ThreadJob module for better credential handling in background jobs
# ThreadJob runs jobs as threads in the current process, preserving network credentials
# This fixes BITS authentication error 0x800704DD (ERROR_NOT_LOGGED_ON)
if (-not (Get-Module -ListAvailable -Name ThreadJob)) {
    WriteLog "ThreadJob module not found. Attempting to install..."
    try {
        Install-Module -Name ThreadJob -Force -Scope CurrentUser -ErrorAction Stop
        WriteLog "ThreadJob module installed successfully."
    }
    catch {
        Write-Warning "Failed to install ThreadJob module: $($_.Exception.Message)"
        Write-Warning "BITS transfers may fail with authentication errors (0x800704DD)."
        Write-Warning "Install ThreadJob manually: Install-Module -Name ThreadJob -Scope CurrentUser"
    }
}

if (Get-Module -ListAvailable -Name ThreadJob) {
    Import-Module ThreadJob -Force
    WriteLog "ThreadJob module loaded successfully."
}
else {
    Write-Warning "ThreadJob module not available. Using Start-Job (may cause BITS authentication issues)."
}

# Setting long path support - this prevents issues where some applications have deep directory structures
# and driver extraction fails due to long paths.
$script:uiState.Flags.originalLongPathsValue = $null # Store original value
try {
    $script:uiState.Flags.originalLongPathsValue = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
}
catch {
    # Key or value might not exist, which is fine.
    WriteLog "Could not read initial LongPathsEnabled value (may not exist)."
}

# Enable long paths if not already enabled
if ($script:uiState.Flags.originalLongPathsValue -ne 1) {
    try {
        WriteLog 'LongPathsEnabled is not set to 1. Setting it to 1 for the duration of this script.'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Force
        WriteLog 'LongPathsEnabled set to 1.'
    }
    catch {
        WriteLog "Error setting LongPathsEnabled registry key: $($_.Exception.Message). Long path issues might persist."
    }
}
else {
    WriteLog "LongPathsEnabled is already set to 1."
}

if (Test-Path -Path $script:uiState.LogFilePath) {
    Remove-item -Path $script:uiState.LogFilePath -Force
}

Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore, PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Load XAML
$xamlPath = Join-Path $PSScriptRoot "BuildFFUVM_UI.xaml"
if (-not (Test-Path $xamlPath)) {
    Write-Error "XAML file not found: $xamlPath"
    return
}
$xamlString = Get-Content $xamlPath -Raw
$reader = New-Object System.IO.StringReader($xamlString)
$xmlReader = [System.Xml.XmlReader]::Create($reader)
$window = [Windows.Markup.XamlReader]::Load($xmlReader)

$window.Add_Loaded({
        # Pass the state object to all initialization functions
        $script:uiState.Window = $window
        $window.Tag = $script:uiState

        # Update window title with version
        $window.Title = "FFU Builder UI v$($script:uiState.Version.Number)"

        Initialize-UIControls -State $script:uiState
        Initialize-UIDefaults -State $script:uiState
        Initialize-DynamicUIElements -State $script:uiState
        Register-EventHandlers -State $script:uiState

        # Initialize About tab
        Initialize-AboutTab -State $script:uiState

        # Attempt automatic load of previous environment (silent)
        try {
            Invoke-AutoLoadPreviousEnvironment -State $script:uiState
        }
        catch {
            WriteLog "Auto-load previous environment failed: $($_.Exception.Message)"
        }
    })


# Button: Build FFU
$script:uiState.Controls.btnRun = $window.FindName('btnRun')
$script:uiState.Controls.btnRun.Add_Click({
        # Get a local reference to the button for convenience in this handler
        $btnRun = $script:uiState.Controls.btnRun
        try {
            # Dashboard warning confirmation (DASH-08)
            if (-not $script:uiState.Flags.isBuilding) {
                # Check for critical failures first
                $criticalCount = if ($script:uiState.Data.ContainsKey('dashboardCriticalCount')) { $script:uiState.Data.dashboardCriticalCount } else { 0 }
                if ($criticalCount -gt 0) {
                    [System.Windows.MessageBox]::Show(
                        "$criticalCount critical pre-flight issue(s) must be resolved before building.`n`nGo to the Home tab and click Refresh to re-check after fixing issues.",
                        "Build Blocked",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                    return
                }

                # Check for warnings
                $warningCount = if ($script:uiState.Data.ContainsKey('dashboardWarningCount')) { $script:uiState.Data.dashboardWarningCount } else { 0 }
                if ($warningCount -gt 0) {
                    $dialogResult = [System.Windows.MessageBox]::Show(
                        "Pre-flight checks detected $warningCount warning(s) that may affect the build.`n`nDo you want to continue anyway?",
                        "Build Warnings",
                        [System.Windows.MessageBoxButton]::YesNo,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                    if ($dialogResult -ne [System.Windows.MessageBoxResult]::Yes) {
                        return
                    }
                }
            }

            # If a build is running and cleanup is not already running, treat this click as Cancel
            if ($script:uiState.Flags.isBuilding -and -not $script:uiState.Flags.isCleanupRunning) {
                $btnRun.IsEnabled = $false
                $script:uiState.Controls.txtStatus.Text = "Cancel requested. Stopping build..."
                WriteLog "Cancel requested by user. Stopping background build job."

                # Request cancellation via messaging context (notifies background job)
                if ($null -ne $script:uiState.Data.messagingContext) {
                    Request-FFUCancellation -Context $script:uiState.Data.messagingContext
                    WriteLog "Cancellation requested via messaging context."
                }

                # Stop the timer
                if ($null -ne $script:uiState.Data.pollTimer) {
                    $script:uiState.Data.pollTimer.Stop()
                    $script:uiState.Data.pollTimer = $null
                }

                # Close the messaging context
                if ($null -ne $script:uiState.Data.messagingContext) {
                    Close-FFUMessagingContext -Context $script:uiState.Data.messagingContext
                    $script:uiState.Data.messagingContext = $null
                }

                # Stop and remove the running build job
                $jobToStop = $script:uiState.Data.currentBuildJob
                $script:uiState.Data.currentBuildJob = $null
                if ($null -ne $jobToStop) {
                    try {
                        # Attempt graceful stop first
                        Stop-Job -Job $jobToStop -ErrorAction SilentlyContinue
                        Wait-Job -Job $jobToStop -Timeout 5 -ErrorAction SilentlyContinue | Out-Null
                    }
                    catch {
                        WriteLog "Stop-Job threw: $($_.Exception.Message)"
                    }

                    # If the job's hosting process is still alive, kill its process tree to stop child tools like DISM
                    try {
                        $jobProcId = $null
                        if ($null -ne $jobToStop.ChildJobs -and $jobToStop.ChildJobs.Count -gt 0) {
                            $jobProcId = $jobToStop.ChildJobs[0].ProcessId
                        }
                        if ($jobProcId) {
                            # Recursively terminate the job process and any children
                            function Stop-ProcessTree {
                                param([int]$parentPid)
                                $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$parentPid" -ErrorAction SilentlyContinue
                                foreach ($child in $children) {
                                    Stop-ProcessTree -parentPid $child.ProcessId
                                }
                                try { Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue } catch {}
                            }
                            Stop-ProcessTree -parentPid $jobProcId
                        }
                    }
                    catch {
                        WriteLog "Error terminating job process tree: $($_.Exception.Message)"
                    }

                    # Safety net: kill any active DISM capture still running
                    try {
                        $dismCaptures = Get-CimInstance Win32_Process -Filter "Name='DISM.EXE'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match '/Capture-FFU' }
                        foreach ($p in $dismCaptures) {
                            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
                        }
                    }
                    catch {
                        WriteLog "Error stopping DISM capture processes: $($_.Exception.Message)"
                    }

                    # Also stop Office ODT setup.exe if running (to avoid recreating files after cleanup)
                    try {
                        $officePathForKill = $null

                        # Prefer explicit UI path
                        $uiOfficePath = $script:uiState.Controls.txtOfficePath.Text
                        if (-not [string]::IsNullOrWhiteSpace($uiOfficePath)) {
                            $officePathForKill = $uiOfficePath
                        }
                        else {
                            # Fall back to the last config path only if known
                            $lastConfigPathLocal = $script:uiState.Data.lastConfigFilePath
                            if (-not [string]::IsNullOrWhiteSpace($lastConfigPathLocal)) {
                                $ffuDevRoot = Split-Path (Split-Path $lastConfigPathLocal -Parent) -Parent
                                if (-not [string]::IsNullOrWhiteSpace($ffuDevRoot)) {
                                    $officePathForKill = Join-Path $ffuDevRoot 'Apps\Office'
                                }
                            }
                        }

                        # Only proceed when a valid Office folder exists
                        if ($officePathForKill -and (Test-Path -LiteralPath $officePathForKill -PathType Container)) {
                            $setupProcs = Get-CimInstance Win32_Process -Filter "Name='setup.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -like "$officePathForKill*" }
                            foreach ($p in $setupProcs) {
                                try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
                            }
                        }
                    }
                    catch {
                        WriteLog "Error stopping Office setup.exe processes: $($_.Exception.Message)"
                    }

                    try {
                        Remove-Job -Job $jobToStop -Force -ErrorAction SilentlyContinue
                        WriteLog "Background build job stopped and removed."
                    }
                    catch {
                        WriteLog "Error removing background build job: $($_.Exception.Message)"
                    }
                }

                # Start cleanup using the same BuildFFUVM.ps1 via -Cleanup short-circuit
                $lastConfigPath = $script:uiState.Data.lastConfigFilePath
                if ([string]::IsNullOrWhiteSpace($lastConfigPath)) {
                    WriteLog "No stored config file path found. Cleanup cannot proceed."
                    $script:uiState.Controls.txtStatus.Text = "Build canceled. No config found for cleanup."
                    $script:uiState.Flags.isBuilding = $false
                    $script:uiState.Flags.isCleanupRunning = $false
                    $btnRun.Content = "Build FFU"
                    $btnRun.IsEnabled = $true
                    # Re-enable dashboard refresh after build
                    $script:uiState.Controls.btnRefreshChecks.IsEnabled = $true
                    $script:uiState.Controls.btnRefreshChecks.ToolTip = $null
                    return
                }

                $ffuDevPath = Split-Path (Split-Path $lastConfigPath -Parent) -Parent
                $mainLogPath = Join-Path $ffuDevPath "FFUDevelopment.log"

                WriteLog "Starting cleanup without deleting FFUDevelopment.log (will append new entries)."

                $script:uiState.Controls.txtStatus.Text = "Cancel in progress... Cleaning environment..."
                WriteLog "Starting cleanup job (BuildFFUVM.ps1 -Cleanup)."

                # Prepare parameters for cleanup
                # Inform user: in-progress items will be removed; ask whether to also remove other items downloaded during this run
                $removeCurrentRunToo = $false
                $promptText = "Cancel requested.`n`nWe'll remove the download currently in progress to avoid partial/corrupt content.`n`nDo you also want to remove other items downloaded during this run? Previously downloaded items will be kept."
                $result = [System.Windows.MessageBox]::Show($promptText, "Cancel cleanup options", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
                if ($result -eq [System.Windows.MessageBoxResult]::Yes) { $removeCurrentRunToo = $true }

                $cleanupParams = @{
                    ConfigFile                 = $lastConfigPath
                    Cleanup                    = $true
                    # Avoid wiping all user content on cancel
                    RemoveApps                 = $false
                    RemoveUpdates              = $false
                    CleanupDrivers             = $false
                    # Scoped removal to current run only (optional per user choice)
                    CleanupCurrentRunDownloads = $removeCurrentRunToo
                }

                $cleanupScriptBlock = {
                    param($buildParams, $PSScriptRoot)
                    & "$PSScriptRoot\BuildFFUVM.ps1" @buildParams
                }

                # Start cleanup job using ThreadJob for credential inheritance
                # ThreadJob preserves network credentials, preventing BITS error 0x800704DD
                if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
                    $script:uiState.Data.currentBuildJob = Start-ThreadJob -ScriptBlock $cleanupScriptBlock -ArgumentList @($cleanupParams, $PSScriptRoot)
                    WriteLog "Cleanup job started using ThreadJob (with network credential inheritance)."
                }
                else {
                    $script:uiState.Data.currentBuildJob = Start-Job -ScriptBlock $cleanupScriptBlock -ArgumentList @($cleanupParams, $PSScriptRoot)
                    WriteLog "WARNING: Cleanup job started using Start-Job (network credentials may not be available for BITS transfers)."
                }

                # Create a timer to poll the cleanup job
                # Note: Cleanup runs without messagingContext, so no real-time log updates
                # The log file is still written for post-mortem review
                $script:uiState.Data.pollTimer = New-Object System.Windows.Threading.DispatcherTimer
                $script:uiState.Data.pollTimer.Interval = [TimeSpan]::FromSeconds(1)
                $script:uiState.Flags.isCleanupRunning = $true

                $script:uiState.Data.pollTimer.Add_Tick({
                        param($sender, $e)
                        $currentJob = $script:uiState.Data.currentBuildJob

                        if ($null -eq $currentJob -or $null -eq $script:uiState.Data.pollTimer) {
                            if ($null -ne $sender) { $sender.Stop() }
                            $script:uiState.Data.pollTimer = $null
                            return
                        }

                        if ($currentJob.State -in 'Completed', 'Failed', 'Stopped') {
                            if ($null -ne $sender) { $sender.Stop() }
                            $script:uiState.Data.pollTimer = $null

                            $script:uiState.Controls.txtStatus.Text = "Build canceled. Environment cleaned."
                            $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                            $script:uiState.Controls.pbOverallProgress.Value = 0

                            # Receive and remove cleanup job
                            $currentJob | Receive-Job -ErrorAction SilentlyContinue | Out-Null
                            Remove-Job -Job $currentJob -Force
                            $script:uiState.Data.currentBuildJob = $null

                            # Reset flags and button
                            $script:uiState.Flags.isCleanupRunning = $false
                            $script:uiState.Flags.isBuilding = $false
                            $btn = $script:uiState.Controls.btnRun
                            $btn.Content = "Build FFU"
                            $btn.IsEnabled = $true
                            # Re-enable dashboard refresh after cleanup
                            $script:uiState.Controls.btnRefreshChecks.IsEnabled = $true
                            $script:uiState.Controls.btnRefreshChecks.ToolTip = $null
                        }
                    })

                $script:uiState.Data.pollTimer.Start()
                return
            }

            # Not currently building: start a new build

            # REL-UI-05: Check for known validation errors from config loading
            if ($script:uiState.Data.hasValidationErrors) {
                $userChoice = [System.Windows.MessageBox]::Show(
                    "The current configuration has validation errors.`n`nDo you want to start the build anyway?",
                    "Configuration Warning",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Warning
                )
                if ($userChoice -ne [System.Windows.MessageBoxResult]::Yes) {
                    WriteLog "Build cancelled due to validation errors."
                    $script:uiState.Controls.txtStatus.Text = "Build canceled: Configuration has validation errors."
                    return
                }
                WriteLog "User chose to proceed with build despite validation errors."
            }

            $btnRun.IsEnabled = $false

            # Switch to Monitor Tab
            $script:uiState.Controls.MainTabControl.SelectedItem = $script:uiState.Controls.MonitorTab
            
            # Clear previous log data and reset autoscroll
            if ($null -ne $script:uiState.Data.logData) {
                $script:uiState.Data.logData.Clear()
                $script:uiState.Flags.autoScrollLog = $true
            }

            $progressBar = $script:uiState.Controls.pbOverallProgress
            $txtStatus = $script:uiState.Controls.txtStatus
            $progressBar.Visibility = 'Visible'
            $txtStatus.Text = "Starting FFU build..."
            
            # Gather config on the UI thread before starting the job
            $config = Get-UIConfig -State $script:uiState

            # Validate Additional FFU selection if enabled
            if ($config.BuildUSBDrive -and $config.CopyAdditionalFFUFiles -and (($null -eq $config.AdditionalFFUFiles) -or ($config.AdditionalFFUFiles.Count -eq 0))) {
                [System.Windows.MessageBox]::Show("Please select at least one additional FFU file to copy, or uncheck 'Copy Additional FFU Files'.", "Selection Required", "OK", "Warning") | Out-Null
                $btnRun.IsEnabled = $true
                $script:uiState.Controls.txtStatus.Text = "Build canceled: Additional FFU selection required."
                return
            }

            # PRE-FLIGHT VALIDATION: Verify FFUDevelopmentPath exists and is valid
            $ffuDevPath = $config.FFUDevelopmentPath
            if ([string]::IsNullOrWhiteSpace($ffuDevPath)) {
                [System.Windows.MessageBox]::Show("FFU Development Path is not set. Please specify a valid path in the Build tab.", "Configuration Error", "OK", "Error") | Out-Null
                $btnRun.IsEnabled = $true
                $script:uiState.Controls.txtStatus.Text = "Build canceled: FFU Development Path not set."
                return
            }

            # Check if path exists
            if (-not (Test-Path -LiteralPath $ffuDevPath -PathType Container)) {
                $msgResult = [System.Windows.MessageBox]::Show(
                    "FFU Development Path does not exist:`n`n$ffuDevPath`n`nBuildFFUVM.ps1 will fail immediately with parameter validation error.`n`nDo you want to create this directory?",
                    "Path Not Found",
                    "YesNo",
                    "Warning"
                )
                if ($msgResult -eq [System.Windows.MessageBoxResult]::Yes) {
                    try {
                        New-Item -ItemType Directory -Path $ffuDevPath -Force | Out-Null
                        WriteLog "Created FFU Development Path: $ffuDevPath"
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Failed to create directory:`n`n$($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
                        $btnRun.IsEnabled = $true
                        $script:uiState.Controls.txtStatus.Text = "Build canceled: Could not create FFU Development Path."
                        return
                    }
                }
                else {
                    $btnRun.IsEnabled = $true
                    $script:uiState.Controls.txtStatus.Text = "Build canceled: FFU Development Path does not exist."
                    return
                }
            }

            # Ensure config subdirectory exists (required for saving build configuration)
            $configDir = Join-Path $ffuDevPath "config"
            if (-not (Test-Path -LiteralPath $configDir -PathType Container)) {
                try {
                    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                    WriteLog "Created config subdirectory: $configDir"
                }
                catch {
                    [System.Windows.MessageBox]::Show("Failed to create config subdirectory:`n`n$($_.Exception.Message)`n`nThe build cannot proceed without this directory.", "Error", "OK", "Error") | Out-Null
                    $btnRun.IsEnabled = $true
                    $script:uiState.Controls.txtStatus.Text = "Build canceled: Could not create config subdirectory."
                    return
                }
            }

            # Warn if FFUDevelopmentPath doesn't match where UI is running from
            $expectedPath = $script:uiState.FFUDevelopmentPath
            if ($ffuDevPath -ne $expectedPath) {
                WriteLog "WARNING: FFU Development Path ($ffuDevPath) does not match UI script location ($expectedPath)"
                WriteLog "This may indicate a configuration loaded from a different installation location."
                $msgResult = [System.Windows.MessageBox]::Show(
                    "WARNING: FFU Development Path mismatch detected.`n`n" +
                    "Configured Path: $ffuDevPath`n" +
                    "UI Location: $expectedPath`n`n" +
                    "This usually means you loaded a configuration file from a different FFUBuilder installation.`n`n" +
                    "Using a mismatched path may cause builds to fail or produce unexpected results.`n`n" +
                    "Do you want to continue anyway?",
                    "Path Mismatch Warning",
                    "YesNo",
                    "Warning"
                )
                if ($msgResult -eq [System.Windows.MessageBoxResult]::No) {
                    $btnRun.IsEnabled = $true
                    $script:uiState.Controls.txtStatus.Text = "Build canceled: Path mismatch."
                    return
                }
            }

            $configFilePath = Join-Path $config.FFUDevelopmentPath "\config\FFUConfig.json"
            # Sort top-level keys alphabetically for consistent output
            $sortedConfig = [ordered]@{}
            foreach ($k in ($config.Keys | Sort-Object)) { $sortedConfig[$k] = $config[$k] }

            # Save config file with error handling
            try {
                $sortedConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8 -ErrorAction Stop
                $script:uiState.Data.lastConfigFilePath = $configFilePath
                WriteLog "Build configuration saved to: $configFilePath"
            }
            catch {
                $errorMsg = "Failed to save build configuration file:`n`n$($_.Exception.Message)`n`nPath: $configFilePath`n`nPlease verify write permissions and disk space."
                WriteLog "ERROR: $errorMsg"
                [System.Windows.MessageBox]::Show($errorMsg, "Configuration Save Error", "OK", "Error") | Out-Null
                $btnRun.IsEnabled = $true
                $script:uiState.Controls.txtStatus.Text = "Build canceled: Could not save configuration."
                return
            }
            
            if ($config.InstallOffice -and $config.OfficeConfigXMLFile) {
                Copy-Item -Path $config.OfficeConfigXMLFile -Destination $config.OfficePath -Force
                WriteLog "Office Configuration XML file copied successfully."
            }
            
            $txtStatus.Text = "Executing BuildFFUVM.ps1 in the background..."
            WriteLog "Executing BuildFFUVM.ps1 in the background..."

            # Define main log path for monitoring (matches cleanup flow definition)
            $mainLogPath = Join-Path $ffuDevPath "FFUDevelopment.log"

            # ============================================================================
            # Initialize FFU.Messaging context for real-time UI updates
            # This provides ~20x faster updates (50ms vs 1000ms) via synchronized queue
            # File logging is kept as backup for persistence and troubleshooting
            # ============================================================================
            $script:uiState.Data.messagingContext = New-FFUMessagingContext -EnableFileLogging -LogFilePath $mainLogPath
            WriteLog "Messaging context initialized with real-time queue + file logging."

            # Prepare parameters for splatting
            $buildParams = @{
                ConfigFile = $configFilePath
            }
            if ($config.Verbose) {
                $buildParams['Verbose'] = $true
            }

            # Define the script block to run in the background job
            # Note: MessagingContext is passed separately as it's a synchronized hashtable
            $scriptBlock = {
                param($buildParams, $ScriptRoot, $SyncContext)

                # Set working directory to the script's location
                # This ensures BuildFFUVM.ps1 runs with the correct working directory context.
                # ThreadJobs start in the user's Documents folder, not the script's directory.
                # Setting location here provides defense-in-depth for any relative path operations.
                Set-Location $ScriptRoot

                # Import FFU.Messaging module in ThreadJob context for queue access
                Import-Module "$ScriptRoot\Modules\FFU.Messaging" -Force -DisableNameChecking

                # Import FFU.Common.Core and set messaging context for real-time WriteLog updates
                # This enables WriteLog to write to both the log file AND the messaging queue
                Import-Module "$ScriptRoot\FFU.Common\FFU.Common.Core.psm1" -Force -DisableNameChecking
                if ($SyncContext) {
                    Set-CommonCoreMessagingContext -Context $SyncContext
                }

                # If messaging context is available, set build state
                if ($SyncContext) {
                    Set-FFUBuildState -Context $SyncContext -State Running -SendMessage
                }

                try {
                    # This script runs in a new process. BuildFFUVM.ps1 is expected to handle its own module imports.
                    & "$ScriptRoot\BuildFFUVM.ps1" @buildParams -MessagingContext $SyncContext

                    # Mark completion if context available
                    if ($SyncContext) {
                        Set-FFUBuildState -Context $SyncContext -State Completed -SendMessage
                    }
                }
                catch {
                    if ($SyncContext) {
                        Write-FFUError -Context $SyncContext -Message "Build failed: $($_.Exception.Message)" -Source 'BuildFFUVM'
                        Set-FFUBuildState -Context $SyncContext -State Failed -SendMessage
                    }
                    throw
                }
            }

            # FIX: Delete old log file BEFORE starting the background job to prevent race condition
            # where the UI's StreamReader opens the old log file before the background job deletes it.
            # This prevents stale log entries from appearing in the Monitor tab.
            if (Test-Path $mainLogPath) {
                try {
                    Remove-Item -Path $mainLogPath -Force -ErrorAction Stop
                    WriteLog "Removed previous log file to prevent race condition."
                    # Small delay to ensure file system operation completes
                    Start-Sleep -Milliseconds 100
                }
                catch {
                    # Log warning but don't fail the build - the background job will handle it
                    WriteLog "Warning: Could not remove old log file: $($_.Exception.Message)"
                }
            }

            # Start the job and store it in the shared state object
            # Use ThreadJob for credential inheritance (fixes BITS error 0x800704DD)
            # Pass messaging context for real-time UI updates via synchronized queue
            if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
                $script:uiState.Data.currentBuildJob = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList @($buildParams, $PSScriptRoot, $script:uiState.Data.messagingContext)
                WriteLog "Build job started using ThreadJob (with network credential inheritance + messaging context)."
            }
            else {
                $script:uiState.Data.currentBuildJob = Start-Job -ScriptBlock $scriptBlock -ArgumentList @($buildParams, $PSScriptRoot, $script:uiState.Data.messagingContext)
                WriteLog "WARNING: Build job started using Start-Job (network credentials may not be available for BITS transfers)."
            }

            # ============================================================================
            # Create timer with 50ms interval for real-time UI updates via messaging queue
            # This is 20x faster than the previous 1-second file-polling approach
            # Timer reads from ConcurrentQueue (lock-free)
            # ============================================================================
            $script:uiState.Data.pollTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:uiState.Data.pollTimer.Interval = [TimeSpan]::FromMilliseconds(50)
            
            # Add the Tick event handler
            # ============================================================================
            # REAL-TIME UI UPDATES: Reads from synchronized queue (messagingContext)
            # Queue polling at 50ms provides near-instant UI feedback
            # ============================================================================
            $script:uiState.Data.pollTimer.Add_Tick({
                    param($sender, $e)
                    # This scriptblock runs on the UI thread, so it can safely access script-scoped variables
                    $currentJob = $script:uiState.Data.currentBuildJob
                    $msgContext = $script:uiState.Data.messagingContext
                    $lastLine = $null

                    # PRIMARY: Read from messaging queue (real-time, lock-free)
                    if ($null -ne $msgContext -and $null -ne $msgContext.MessageQueue) {
                        $messages = Read-FFUMessages -Context $msgContext -MaxMessages 50
                        foreach ($msg in $messages) {
                            # Format message for display
                            $displayText = $msg.ToLogString()
                            $script:uiState.Data.logData.Add($displayText)
                            $lastLine = $displayText

                            # Handle progress messages specially
                            # Note: Use string comparison instead of [FFUMessageLevel]::Progress enum
                            # because PowerShell enums defined in modules are not exported via Import-Module
                            # (would require 'using module' at parse-time which has path issues)
                            if ($msg.Level.ToString() -eq 'Progress' -or $msg.Data.ContainsKey('PercentComplete')) {
                                $percentage = if ($msg.Data.ContainsKey('PercentComplete')) { $msg.Data['PercentComplete'] } else { 0 }
                                $statusMsg = if ($msg.Data.ContainsKey('CurrentOperation')) { $msg.Data['CurrentOperation'] } else { $msg.Message }

                                $script:uiState.Controls.pbOverallProgress.Value = $percentage
                                $script:uiState.Controls.txtStatus.Text = $statusMsg
                            }
                        }

                        # Scroll to latest if auto-scroll enabled and messages were received
                        if ($messages.Count -gt 0 -and $script:uiState.Flags.autoScrollLog -and $lastLine) {
                            $script:uiState.Controls.lstLogOutput.ScrollIntoView($lastLine)
                            $script:uiState.Controls.lstLogOutput.SelectedIndex = $script:uiState.Controls.lstLogOutput.Items.Count - 1
                        }
                    }

                    # If job is somehow null or the timer has been nulled out, stop the timer
                    if ($null -eq $currentJob -or $null -eq $script:uiState.Data.pollTimer) {
                        if ($null -ne $sender) {
                            $sender.Stop()
                        }
                        $script:uiState.Data.pollTimer = $null
                        return
                    }

                    # Check if the job has reached a terminal state
                    if ($currentJob.State -in 'Completed', 'Failed', 'Stopped') {
                        # Stop the timer, we're done polling
                        if ($null -ne $sender) {
                            $sender.Stop()
                        }
                        $script:uiState.Data.pollTimer = $null

                        # Final read of any remaining messages from queue
                        if ($null -ne $msgContext -and $null -ne $msgContext.MessageQueue) {
                            $finalMessages = Read-FFUMessages -Context $msgContext -MaxMessages 1000
                            foreach ($msg in $finalMessages) {
                                $displayText = $msg.ToLogString()
                                $script:uiState.Data.logData.Add($displayText)
                                $lastLine = $displayText

                                # Note: Use string comparison instead of [FFUMessageLevel] enum (see earlier comment)
                                if ($msg.Level.ToString() -eq 'Progress' -or $msg.Data.ContainsKey('PercentComplete')) {
                                    $percentage = if ($msg.Data.ContainsKey('PercentComplete')) { $msg.Data['PercentComplete'] } else { 0 }
                                    $statusMsg = if ($msg.Data.ContainsKey('CurrentOperation')) { $msg.Data['CurrentOperation'] } else { $msg.Message }
                                    $script:uiState.Controls.pbOverallProgress.Value = $percentage
                                    $script:uiState.Controls.txtStatus.Text = $statusMsg
                                }
                            }

                            # Close messaging context
                            Close-FFUMessagingContext -Context $msgContext
                            $script:uiState.Data.messagingContext = $null
                        }

                        # Scroll to last line if auto-scroll enabled
                        if ($script:uiState.Flags.autoScrollLog -and $null -ne $lastLine) {
                            $script:uiState.Controls.lstLogOutput.ScrollIntoView($lastLine)
                            $script:uiState.Controls.lstLogOutput.SelectedIndex = $script:uiState.Controls.lstLogOutput.Items.Count - 1
                        }

                        # Determine final status based on job result and error output
                        # Even "Completed" jobs can have errors (e.g., parameter validation failures)
                        $jobOutput = Receive-Job -Job $currentJob -Keep -ErrorVariable jobErrors -ErrorAction SilentlyContinue

                        # Check for explicit success marker FIRST
                        # BuildFFUVM.ps1 outputs a PSCustomObject with FFUBuildSuccess=$true on successful completion
                        # This takes priority over non-terminating errors in the error stream
                        $successMarker = $null
                        if ($jobOutput) {
                            $successMarker = $jobOutput | Where-Object {
                                $_ -is [PSCustomObject] -and $_.PSObject.Properties['FFUBuildSuccess'] -and $_.FFUBuildSuccess -eq $true
                            } | Select-Object -Last 1
                        }

                        if ($successMarker) {
                            # Explicit success marker found - build completed successfully
                            # Ignore any non-terminating errors that may have been captured
                            $hasErrors = $false
                            WriteLog "Success marker detected: $($successMarker.Message)"
                        }
                        else {
                            # No success marker - fall back to error stream check
                            $hasErrors = ($jobErrors.Count -gt 0) -or ($currentJob.State -eq 'Failed') -or ($currentJob.State -eq 'Stopped')
                        }

                        # Additional check: if log file was never created, the job likely failed early
                        # NOTE: Use script-scoped uiState.FFUDevelopmentPath (not $config which is out of scope in this timer handler)
                        $mainLogPath = Join-Path $script:uiState.FFUDevelopmentPath "FFUDevelopment.log"
                        if (-not (Test-Path -LiteralPath $mainLogPath)) {
                            $hasErrors = $true
                        }

                        if ($hasErrors) {
                            # Extract rich error context from job and messaging (REL-UI-05)
                            $errorInfo = Get-FFUJobError -Job $currentJob `
                                -MessagingContext $script:uiState.Data.messagingContext `
                                -LogPath $mainLogPath

                            # Log the error for debugging
                            WriteLog "BuildFFUVM.ps1 job failed. Type: $($errorInfo.ErrorType). Source: $($errorInfo.Source). Message: $($errorInfo.Message)"

                            # Display structured error with remediation (REL-UI-04)
                            Show-FFUError -Severity 'Error' `
                                -Title $errorInfo.Title `
                                -Description $errorInfo.Message `
                                -Remediation $errorInfo.Remediation `
                                -LogPath $errorInfo.LogPath `
                                -Details $errorInfo.Details

                            # Receive & remove job before UI reset
                            $currentJob | Receive-Job -ErrorAction SilentlyContinue | Out-Null
                            Remove-Job -Job $currentJob -Force
                            $script:uiState.Data.currentBuildJob = $null

                            # Use centralized UI reset (REL-UI-03)
                            Reset-FFUUIToIdle -State $script:uiState -StatusMessage "Build failed. Check log for details."
                            # Re-enable dashboard refresh after build failure
                            $script:uiState.Controls.btnRefreshChecks.IsEnabled = $true
                            $script:uiState.Controls.btnRefreshChecks.ToolTip = $null
                        }
                        else {
                            # Job completed successfully with no errors
                            WriteLog "BuildFFUVM.ps1 job completed successfully."

                            # Receive & remove job
                            $currentJob | Receive-Job -ErrorAction SilentlyContinue | Out-Null
                            Remove-Job -Job $currentJob -Force
                            $script:uiState.Data.currentBuildJob = $null

                            # Update UI for success
                            $script:uiState.Controls.pbOverallProgress.Value = 100
                            $script:uiState.Controls.txtStatus.Text = "FFU build completed successfully."

                            # Reset button and flags for next run
                            $script:uiState.Flags.isBuilding = $false
                            $script:uiState.Flags.isCleanupRunning = $false
                            $script:uiState.Controls.btnRun.Content = "Build FFU"
                            $script:uiState.Controls.btnRun.IsEnabled = $true
                            # Re-enable dashboard refresh after successful build
                            $script:uiState.Controls.btnRefreshChecks.IsEnabled = $true
                            $script:uiState.Controls.btnRefreshChecks.ToolTip = $null
                        }
                    }
                })
            
            # Start the timer
            $script:uiState.Data.pollTimer.Start()

            # Mark building and toggle button to Cancel
            $script:uiState.Flags.isBuilding = $true
            $btnRun.Content = "Cancel"
            $btnRun.IsEnabled = $true

            # Disable dashboard refresh during active build
            $script:uiState.Controls.btnRefreshChecks.IsEnabled = $false
            $script:uiState.Controls.btnRefreshChecks.ToolTip = "Refresh disabled during active build"
        }
        catch {
            # This catch block handles errors during the setup of the job (e.g., Get-UIConfig fails)
            $errorMessage = "An error occurred before starting the build job: $_"
            WriteLog $errorMessage
            [System.Windows.MessageBox]::Show($errorMessage, "Error", "OK", "Error")

            # Use centralized UI reset (REL-UI-03)
            # Reset-FFUUIToIdle handles messaging context cleanup internally
            Reset-FFUUIToIdle -State $script:uiState -StatusMessage "Build failed to start."
            # Re-enable dashboard refresh after build startup failure
            $script:uiState.Controls.btnRefreshChecks.IsEnabled = $true
            $script:uiState.Controls.btnRefreshChecks.ToolTip = $null
        }
    })

# Add handler for Remove button clicks
$window.Add_SourceInitialized({
        $listView = $window.FindName('lstApplications')
        $listView.AddHandler(
            [System.Windows.Controls.Button]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($buttonSender, $clickEventArgs)
                if ($clickEventArgs.OriginalSource -is [System.Windows.Controls.Button] -and $clickEventArgs.OriginalSource.Content -eq "Remove") {
                    Remove-Application -priority $clickEventArgs.OriginalSource.Tag -State $script:uiState
                }
            }
        )
    })

# Register cleanup to reclaim memory and revert LongPathsEnabled setting when the UI window closes
$window.Add_Closed({
        # Stop any running build job if the window is closed
        if ($null -ne $script:uiState.Data.currentBuildJob) {
            WriteLog "UI closing, stopping background build job."

            # Stop the timer
            if ($null -ne $script:uiState.Data.pollTimer) {
                $script:uiState.Data.pollTimer.Stop()
                $script:uiState.Data.pollTimer = $null
            }

            # Request cancellation and close messaging context
            if ($null -ne $script:uiState.Data.messagingContext) {
                Request-FFUCancellation -Context $script:uiState.Data.messagingContext
                Close-FFUMessagingContext -Context $script:uiState.Data.messagingContext
                $script:uiState.Data.messagingContext = $null
            }

            # Stop and remove the job
            $jobToStop = $script:uiState.Data.currentBuildJob
            $script:uiState.Data.currentBuildJob = $null # Clear it from state first

            try {
                Stop-Job -Job $jobToStop
                Remove-Job -Job $jobToStop
                WriteLog "Background job stopped and removed."
            }
            catch {
                WriteLog "Error stopping or removing background job: $($_.Exception.Message)"
            }
        }

        # Stop dashboard poll timer and clean up dashboard job on close
        if ($null -ne $script:uiState.Data.dashboardPollTimer) {
            $script:uiState.Data.dashboardPollTimer.Stop()
            $script:uiState.Data.dashboardPollTimer = $null
        }
        if ($null -ne $script:uiState.Data.currentDashboardJob) {
            try {
                Stop-Job -Job $script:uiState.Data.currentDashboardJob -ErrorAction SilentlyContinue
                Remove-Job -Job $script:uiState.Data.currentDashboardJob -Force -ErrorAction SilentlyContinue
            }
            catch {
                WriteLog "Error stopping dashboard job on close: $($_.Exception.Message)"
            }
            $script:uiState.Data.currentDashboardJob = $null
        }

        # Revert LongPathsEnabled registry setting if it was changed by this script
        if ($script:uiState.Flags.originalLongPathsValue -ne 1) {
            # Only revert if we changed it from something other than 1
            try {
                $currentValue = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
                if ($currentValue -eq 1) {
                    # Double-check it's still 1 before reverting
                    $revertValue = if ($null -eq $script:uiState.Flags.originalLongPathsValue) { 0 } else { $script:uiState.Flags.originalLongPathsValue } # Revert to original or 0 if it didn't exist
                    WriteLog "Reverting LongPathsEnabled registry key back to original value ($revertValue)."
                    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value $revertValue -Force
                    WriteLog "LongPathsEnabled reverted."
                }
            }
            catch {
                WriteLog "Error reverting LongPathsEnabled registry key: $($_.Exception.Message)."
            }
        }

        # # Garbage collection
        # [System.GC]::Collect()
        # [System.GC]::WaitForPendingFinalizers()
    })

# --------------------------------------------------------------------------
# SECTION: Pre-Flight Dashboard
# --------------------------------------------------------------------------

function Start-DashboardChecks {
    <#
    .SYNOPSIS
        Launches FFU.Preflight checks in a background ThreadJob and wires messaging for live UI updates.
    .DESCRIPTION
        Shows progress panel, disables refresh, clears previous results, creates messaging context,
        gathers feature selections from UI, and starts a ThreadJob that runs Invoke-FFUPreflight.
        Check results are sent back via FFU.Messaging ConcurrentQueue as structured messages.
    #>

    # Show progress panel and disable refresh
    $script:uiState.Controls.pnlDashboardProgress.Visibility = 'Visible'
    $script:uiState.Controls.btnRefreshChecks.IsEnabled = $false

    # Clear previous results
    Clear-DashboardResults -State $script:uiState

    # Hide hypervisor info banner (will be shown again after determining hypervisor type)
    $script:uiState.Controls.borderHypervisorInfo.Visibility = 'Collapsed'

    # Set summary banner to loading state
    $script:uiState.Controls.txtSummaryStatus.Text = 'Checking system readiness...'

    # Create messaging context for dashboard (reuse or create new)
    if ($null -eq $script:uiState.Data.dashboardMessagingContext) {
        $script:uiState.Data.dashboardMessagingContext = New-FFUMessagingContext
    }

    # Initialize category stats tracking
    $script:uiState.Data.dashboardCategoryStats = @{
        System       = @{ Total = 0; Passed = 0; Failed = 0; Warning = 0 }
        Hypervisor   = @{ Total = 0; Passed = 0; Failed = 0; Warning = 0 }
        BuildTools   = @{ Total = 0; Passed = 0; Failed = 0; Warning = 0 }
        Network      = @{ Total = 0; Passed = 0; Failed = 0; Warning = 0 }
        Optimization = @{ Total = 0; Passed = 0; Failed = 0; Warning = 0 }
    }

    # Phase 48: Check result storage for diagnostics export
    if ($null -eq $script:uiState.Data.dashboardCheckResults) {
        $script:uiState.Data.dashboardCheckResults = @{}
    }

    # Phase 48: Clear check results for new run
    $script:uiState.Data.dashboardCheckResults = @{}

    # Phase 48: Dim hypervisor category if this is a revalidation (not first run)
    if ($script:uiState.Data.resultsStale -eq $true) {
        $depChecks = Get-HypervisorDependentChecks
        # Dim only the Hypervisor category (only category with hypervisor-dependent checks)
        Set-CategoryDimmed -State $script:uiState -Category 'Hypervisor' -IsDimmed $true
        # Update summary banner to "Rechecking..." state
        $brushConverter = [System.Windows.Media.BrushConverter]::new()
        $script:uiState.Controls.borderSummaryStatus.Background = $brushConverter.ConvertFromString('#E0E0E0')
        $script:uiState.Controls.txtSummaryStatus.Text = 'Rechecking environment...'
        $script:uiState.Controls.txtSummaryStatus.Foreground = $brushConverter.ConvertFromString('#616161')
    }

    # Phase 48: Disable build and export during revalidation (CFG-01 transition behavior)
    $script:uiState.Controls.btnRun.IsEnabled = $false
    $script:uiState.Controls.btnExportDiagnostics.IsEnabled = $false

    # Gather feature selections from UI checkboxes
    $features = @{
        CreateVM              = $true  # Always check VM readiness
        CreateCaptureMedia    = [bool]$script:uiState.Controls.chkCreateCaptureMedia.IsChecked
        CreateDeploymentMedia = [bool]$script:uiState.Controls.chkCreateDeploymentMedia.IsChecked
        InstallApps           = [bool]$script:uiState.Controls.chkInstallApps.IsChecked
        UpdateLatestCU        = [bool]$script:uiState.Controls.chkLatestCU.IsChecked
        DownloadDrivers       = [bool]$script:uiState.Controls.chkDownloadDrivers.IsChecked
    }

    # Determine hypervisor type from UI dropdown
    $hypervisorType = switch ($script:uiState.Controls.cmbHypervisorType.SelectedIndex) {
        0 { 'HyperV' }
        1 { 'VMware' }
        2 { 'Auto' }
        default { 'HyperV' }
    }

    # Update hypervisor info banner (Phase 47: HYP-04, HYP-05)
    Update-HypervisorCategoryVisibility -State $script:uiState -HypervisorType $hypervisorType

    # Launch background job via Start-ThreadJob
    $script:uiState.Data.currentDashboardJob = Start-ThreadJob -ScriptBlock {
        param($context, $features, $ffuPath, $hypervisorType)

        # Add module path for FFU.Preflight and FFU.Messaging
        $modulePath = Join-Path $ffuPath 'Modules'
        if ($env:PSModulePath -notlike "*$modulePath*") {
            $env:PSModulePath = "$modulePath;$env:PSModulePath"
        }

        Import-Module FFU.Preflight -Force
        Import-Module FFU.Messaging -Force

        try {
            Write-FFUMessage -Context $context -Message "DASHBOARD_STARTED" -Level Info

            $result = Invoke-FFUPreflight -Features $features `
                -FFUDevelopmentPath $ffuPath `
                -HypervisorType $hypervisorType `
                -SkipCleanup `
                -ErrorAction Stop

            # Send individual check results from all tiers
            $checkNum = 0
            $allTiers = @('Tier1Results', 'Tier2Results', 'Tier3Results')
            $totalChecks = 0
            foreach ($tier in $allTiers) {
                $totalChecks += $result.$tier.Count
            }

            foreach ($tier in $allTiers) {
                foreach ($checkName in $result.$tier.Keys) {
                    $checkNum++
                    $check = $result.$tier[$checkName]

                    # Send progress update
                    Write-FFUMessage -Context $context `
                        -Message "DASHBOARD_PROGRESS|$checkNum|$totalChecks|$checkName" -Level Info

                    # Send check result (pipe-delimited format with DurationMs - Phase 47: REM-04)
                    $severity = if ($check.PSObject.Properties['Severity']) { $check.Severity } else { 'Info' }
                    $remediation = if ($check.PSObject.Properties['Remediation']) { $check.Remediation } else { '' }
                    $durationMs = if ($check.PSObject.Properties['DurationMs']) { $check.DurationMs } else { 0 }
                    # Replace pipes in message/remediation to avoid delimiter collision
                    $safeMsg = ($check.Message -replace '\|', ' - ')
                    $safeRemed = ($remediation -replace '\|', ' - ')

                    Write-FFUMessage -Context $context `
                        -Message "DASHBOARD_CHECK|$checkName|$($check.Status)|$severity|$safeMsg|$safeRemed|$durationMs" -Level Info
                }
            }

            # Send completion with severity counts
            Write-FFUMessage -Context $context `
                -Message "DASHBOARD_COMPLETE|$($result.CriticalCount)|$($result.WarningCount)|$totalChecks|$checkNum" -Level Info
        }
        catch {
            Write-FFUMessage -Context $context `
                -Message "DASHBOARD_ERROR|Pre-flight checks failed: $($_.Exception.Message)" -Level Error
        }
    } -ArgumentList $script:uiState.Data.dashboardMessagingContext, $features, $FFUDevelopmentPath, $hypervisorType
}

# --------------------------------------------------------------------------
# Dashboard DispatcherTimer: polls messaging context at 50ms for live UI updates
# --------------------------------------------------------------------------
$script:uiState.Data.dashboardPollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:uiState.Data.dashboardPollTimer.Interval = [TimeSpan]::FromMilliseconds(50)

$script:uiState.Data.dashboardPollTimer.Add_Tick({
    param($sender, $e)

    # Return early if no messaging context
    if ($null -eq $script:uiState.Data.dashboardMessagingContext) {
        return
    }

    $msgContext = $script:uiState.Data.dashboardMessagingContext
    $msg = $null

    # Drain messages from queue
    while ($msgContext.MessageQueue.TryDequeue([ref]$msg)) {
        $msgText = $msg.Message

        if ($msgText -eq 'DASHBOARD_STARTED') {
            # No additional action needed; progress already shown
            continue
        }

        if ($msgText -like 'DASHBOARD_PROGRESS|*') {
            # Format: DASHBOARD_PROGRESS|{num}|{total}|{name}
            $parts = $msgText -split '\|', 4
            if ($parts.Count -ge 4) {
                $checkNum = $parts[1]
                $totalChecks = $parts[2]
                $checkName = $parts[3]
                $script:uiState.Controls.txtDashboardProgressStatus.Text = "Running check $checkNum of ${totalChecks}: $checkName..."
                $script:uiState.Controls.progressDashboard.Maximum = [int]$totalChecks
                $script:uiState.Controls.progressDashboard.Value = [int]$checkNum
            }
            continue
        }

        if ($msgText -like 'DASHBOARD_CHECK|*') {
            # Format: DASHBOARD_CHECK|{name}|{status}|{severity}|{message}|{remediation}|{durationMs} (Phase 47: REM-04)
            $parts = $msgText -split '\|', 7
            if ($parts.Count -ge 5) {
                $name = $parts[1]
                $status = $parts[2]
                $severity = $parts[3]
                $message = $parts[4]
                $remediation = if ($parts.Count -ge 6) { $parts[5] } else { '' }
                $durationMs = if ($parts.Count -ge 7) { [int]$parts[6] } else { 0 }

                # Resolve category and update UI (Phase 47: REM-04 - pass DurationMs and handler scriptblocks)
                $category = Get-CheckCategory -CheckName $name
                Update-DashboardCheckUI -State $script:uiState -CheckName $name `
                    -Status $status -Severity $severity -Message $message -Remediation $remediation `
                    -DurationMs $durationMs `
                    -OnFixClick $script:onFixClickHandler `
                    -OnUnsafeFixClick $script:onUnsafeFixClickHandler `
                    -OnCopyClick $script:onCopyClickHandler

                # Phase 48: Store check result for diagnostics export (CFG-03)
                $script:uiState.Data.dashboardCheckResults[$name] = @{
                    Status      = $status
                    Severity    = $severity
                    Message     = $message
                    Remediation = $remediation
                    DurationMs  = $durationMs
                    Category    = $category
                    Timestamp   = [DateTime]::Now
                }

                # Track category stats
                $stats = $script:uiState.Data.dashboardCategoryStats[$category]
                if ($null -ne $stats) {
                    $stats.Total++
                    switch ($status) {
                        'Passed'  { $stats.Passed++ }
                        'Failed'  {
                            if ($severity -eq 'Critical') { $stats.Failed++ }
                            else { $stats.Warning++ }
                        }
                        'Warning' { $stats.Warning++ }
                        'Skipped' { $stats.Total-- }
                    }

                    # Live update category summary as each check completes
                    Update-CategorySummary -State $script:uiState -Category $category `
                        -TotalChecks $stats.Total -PassedChecks $stats.Passed `
                        -FailedChecks $stats.Failed -WarningChecks $stats.Warning
                }
            }
            continue
        }

        if ($msgText -like 'DASHBOARD_COMPLETE|*') {
            # Format: DASHBOARD_COMPLETE|{criticalCount}|{warningCount}|{totalChecks}|{passedChecks}
            $parts = $msgText -split '\|', 5
            if ($parts.Count -ge 5) {
                $criticalCount = [int]$parts[1]
                $warningCount = [int]$parts[2]
                $totalChecks = [int]$parts[3]
                $passedChecks = $totalChecks - $criticalCount - $warningCount

                # Hide progress, enable refresh
                $script:uiState.Controls.pnlDashboardProgress.Visibility = 'Collapsed'
                $script:uiState.Controls.btnRefreshChecks.IsEnabled = $true

                # Store counts for build button warning dialog
                $script:uiState.Data.dashboardCriticalCount = $criticalCount
                $script:uiState.Data.dashboardWarningCount = $warningCount

                # Update summary banner and build button state
                Update-SummaryStatus -State $script:uiState -CriticalCount $criticalCount `
                    -WarningCount $warningCount -TotalChecks $totalChecks -PassedChecks $passedChecks
                Update-BuildButtonState -State $script:uiState -CriticalCount $criticalCount `
                    -WarningCount $warningCount

                # Phase 48: Restore dimmed categories and clear staleness (CFG-01, CFG-02)
                Set-CategoryDimmed -State $script:uiState -Category 'Hypervisor' -IsDimmed $false
                $script:uiState.Data.resultsStale = $false
                $script:uiState.Controls.borderStaleResults.Visibility = 'Collapsed'
                $script:uiState.Data.lastCheckCompletedAt = [DateTime]::Now

                # Phase 48: Enable Export Diagnostics button after first successful check run (CFG-03)
                $script:uiState.Controls.btnExportDiagnostics.IsEnabled = $true

                # Reorder categories: failures first, then warnings, then passing
                $container = $script:uiState.Controls.stackDashboardContainer
                if ($null -ne $container) {
                    $expanders = @()
                    $nonExpanders = @()
                    foreach ($child in @($container.Children)) {
                        if ($child -is [System.Windows.Controls.Expander]) {
                            $expanders += $child
                        }
                        else {
                            $nonExpanders += $child
                        }
                    }

                    $sortedExpanders = $expanders | Sort-Object {
                        $catName = $_.Name -replace '^exp', ''
                        $catStats = $script:uiState.Data.dashboardCategoryStats[$catName]
                        if ($null -eq $catStats) { return 2 }
                        if ($catStats.Failed -gt 0) { return 0 }
                        if ($catStats.Warning -gt 0) { return 1 }
                        return 2
                    }

                    $container.Children.Clear()
                    foreach ($item in $nonExpanders) { [void]$container.Children.Add($item) }
                    foreach ($exp in $sortedExpanders) { [void]$container.Children.Add($exp) }
                }
            }
            continue
        }

        if ($msgText -like 'DASHBOARD_ERROR|*') {
            # Format: DASHBOARD_ERROR|{message}
            $errorMsg = $msgText.Substring('DASHBOARD_ERROR|'.Length)

            # Hide progress, enable refresh, show error in summary
            $script:uiState.Controls.pnlDashboardProgress.Visibility = 'Collapsed'
            $script:uiState.Controls.btnRefreshChecks.IsEnabled = $true

            $brushConverter = [System.Windows.Media.BrushConverter]::new()
            $script:uiState.Controls.borderSummaryStatus.Background = $brushConverter.ConvertFromString('#FFEBEE')
            $script:uiState.Controls.txtSummaryStatus.Text = "Error: $errorMsg"
            $script:uiState.Controls.txtSummaryStatus.Foreground = $brushConverter.ConvertFromString('#C62828')

            # Phase 48: Restore dimmed categories on error
            Set-CategoryDimmed -State $script:uiState -Category 'Hypervisor' -IsDimmed $false
            $script:uiState.Data.resultsStale = $false
            $script:uiState.Controls.borderStaleResults.Visibility = 'Collapsed'

            continue
        }
    }

    # Check if dashboard job has completed and clean up
    $dashJob = $script:uiState.Data.currentDashboardJob
    if ($null -ne $dashJob -and $dashJob.State -in @('Completed', 'Failed', 'Stopped')) {
        try {
            $dashJob | Receive-Job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $dashJob -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Silently handle job cleanup errors
        }
        $script:uiState.Data.currentDashboardJob = $null
    }
})

# Start the dashboard poll timer
$script:uiState.Data.dashboardPollTimer.Start()

# --------------------------------------------------------------------------
# SECTION: Dashboard Button Click Handler Scriptblocks (Phase 47: REM-01, REM-02, REM-03)
# --------------------------------------------------------------------------
# These scriptblocks are passed to Update-DashboardCheckUI via -OnFixClick,
# -OnUnsafeFixClick, and -OnCopyClick parameters. Buttons are wired at creation time.
# --------------------------------------------------------------------------

$script:onFixClickHandler = {
    param($sender, $e)
    $cn = $sender.Tag  # CheckName stored in Tag by Update-DashboardCheckUI

    try {
        # Disable button and show fixing state
        $sender.Content = 'Fixing...'
        $sender.IsEnabled = $false
        $sender.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E0E0E0')

        # Execute repair in ThreadJob to avoid blocking UI
        $repairJob = Start-ThreadJob -ScriptBlock {
            param($checkName, $ffuPath)
            $modulePath = Join-Path $ffuPath 'Modules'
            if ($env:PSModulePath -notlike "*$modulePath*") {
                $env:PSModulePath = "$modulePath;$env:PSModulePath"
            }
            $ffuuiPath = Join-Path $ffuPath 'FFUUI.Core'
            Import-Module (Join-Path $ffuuiPath 'FFUUI.Core.psd1') -Force -ErrorAction SilentlyContinue
            Import-Module FFU.Preflight -Force

            Invoke-DashboardRemediation -CheckName $checkName -FFUDevelopmentPath $ffuPath
        } -ArgumentList $cn, $script:FFUDevelopmentPath

        # Poll for repair completion using DispatcherTimer (500ms)
        $repairTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $repairTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $repairTimer.Tag = @{ Job = $repairJob; Button = $sender; CheckName = $cn }
        $repairTimer.Add_Tick({
            param($timerSender, $timerE)
            $job = $timerSender.Tag.Job
            $btn = $timerSender.Tag.Button
            $cn = $timerSender.Tag.CheckName

            if ($job.State -in @('Completed', 'Failed', 'Stopped')) {
                $timerSender.Stop()
                $repairResult = $null
                try {
                    $repairResult = Receive-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                } catch { }

                $succeeded = $false
                if ($null -ne $repairResult -and $repairResult.PSObject.Properties['Succeeded']) {
                    $succeeded = $repairResult.Succeeded
                }

                if ($succeeded) {
                    $btn.Content = 'Fixed!'
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C8E6C9')
                    Invoke-SingleCheckRefresh -CheckName $cn -State $script:uiState
                } else {
                    # Repair failed — re-enable Fix button for retry
                    $btn.Content = 'Fix'
                    $btn.IsEnabled = $true
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C8E6C9')
                    $errorMsg = if ($null -ne $repairResult -and $repairResult.PSObject.Properties['Message']) { $repairResult.Message } else { 'Repair failed' }
                    $btn.ToolTip = $errorMsg
                }
            }
        })
        $repairTimer.Start()
    } catch {
        # Error handling: reset button state and show error to user
        $sender.Content = 'Fix'
        $sender.IsEnabled = $true
        $sender.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C8E6C9')
        $sender.ToolTip = "Fix failed: $($_.Exception.Message)"
    }
}.GetNewClosure()

$script:onUnsafeFixClickHandler = {
    param($sender, $e)
    $cn = $sender.Tag  # CheckName stored in Tag

    try {
        $unsafeMap = Get-UnsafeRemediationMap
        $info = $unsafeMap[$cn]
        if ($null -eq $info) { return }

        $result = [System.Windows.MessageBox]::Show(
            $info.ConfirmMessage,
            $info.ConfirmTitle,
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )

        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            $sender.Content = 'Fixing...'
            $sender.IsEnabled = $false

            try {
                Invoke-Expression $info.Command
                [System.Windows.MessageBox]::Show(
                    $info.SuccessMessage,
                    'Reboot Required',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            } catch {
                [System.Windows.MessageBox]::Show(
                    "Failed to execute: $($_.Exception.Message)",
                    'Error',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
                # Reset button state on failure
                $sender.Content = 'Fix...'
                $sender.IsEnabled = $true
            }
        } else {
            # User declined — show "Fix available" indicator
            if ($null -ne $script:uiState.Data) {
                $script:uiState.Data."fixDeclined_$cn" = $true
            }
            $sender.Content = 'Fix available'
            $sender.FontStyle = [System.Windows.FontStyles]::Italic
            $sender.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1565C0')
            $sender.Background = [System.Windows.Media.Brushes]::Transparent
            $sender.BorderThickness = [System.Windows.Thickness]::new(0)
        }
    } catch {
        # Error handling: reset button state and show error
        $sender.Content = 'Fix...'
        $sender.IsEnabled = $true
        [System.Windows.MessageBox]::Show(
            "Unexpected error: $($_.Exception.Message)",
            'Error',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}.GetNewClosure()

$script:onCopyClickHandler = {
    param($sender, $e)
    $cn = $sender.Tag  # CheckName stored in Tag

    try {
        # Find the associated TextBox in the same parent panel
        $parent = $sender.Parent
        if ($null -ne $parent) {
            foreach ($child in $parent.Children) {
                if ($child -is [System.Windows.Controls.TextBox] -and $child.Name -eq "txtRemediation_$cn") {
                    [System.Windows.Clipboard]::SetText($child.Text)
                    $originalContent = $sender.Content
                    $sender.Content = 'Copied!'

                    # Reset after 2 seconds using DispatcherTimer
                    $resetTimer = [System.Windows.Threading.DispatcherTimer]::new()
                    $resetTimer.Interval = [TimeSpan]::FromSeconds(2)
                    $resetTimer.Tag = @{ Button = $sender; OriginalContent = $originalContent }
                    $resetTimer.Add_Tick({
                        param($ts, $te)
                        $ts.Tag.Button.Content = $ts.Tag.OriginalContent
                        $ts.Stop()
                    })
                    $resetTimer.Start()
                    break
                }
            }
        }
    } catch {
        # Error handling: show error on button and reset
        $sender.Content = 'Error!'
        $sender.ToolTip = "Copy failed: $($_.Exception.Message)"
        # Reset after 2 seconds
        $resetTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $resetTimer.Interval = [TimeSpan]::FromSeconds(2)
        $resetTimer.Tag = @{ Button = $sender }
        $resetTimer.Add_Tick({
            param($ts, $te)
            $ts.Tag.Button.Content = 'Copy'
            $ts.Tag.Button.ToolTip = $null
            $ts.Stop()
        })
        $resetTimer.Start()
    }
}.GetNewClosure()

function Invoke-SingleCheckRefresh {
    <#
    .SYNOPSIS
        Re-runs a single dashboard check after a successful repair.
    .DESCRIPTION
        Launches a ThreadJob to execute the specific Test-FFU* function for the given
        check name, polls for completion, and updates the dashboard UI with the new result.
    .PARAMETER CheckName
        The check name (e.g., 'WimMount', 'DISMState').
    .PARAMETER State
        The UI state object containing Controls and Data hashtables.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CheckName,
        [PSCustomObject]$State
    )
    try {
        $refreshJob = Start-ThreadJob -ScriptBlock {
            param($checkName, $ffuPath)
            $modulePath = Join-Path $ffuPath 'Modules'
            if ($env:PSModulePath -notlike "*$modulePath*") {
                $env:PSModulePath = "$modulePath;$env:PSModulePath"
            }
            Import-Module FFU.Preflight -Force

            $funcName = "Test-FFU$checkName"
            $result = & $funcName
            return $result
        } -ArgumentList $CheckName, $script:FFUDevelopmentPath

        $refreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $refreshTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $refreshTimer.Tag = @{ Job = $refreshJob; CheckName = $CheckName; State = $State }
        $refreshTimer.Add_Tick({
            param($ts, $te)
            $job = $ts.Tag.Job
            $cn = $ts.Tag.CheckName
            $state = $ts.Tag.State

            if ($job.State -in @('Completed', 'Failed', 'Stopped')) {
                $ts.Stop()
                $checkResult = $null
                try {
                    $checkResult = Receive-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                } catch { }

                if ($null -ne $checkResult) {
                    $category = Get-CheckCategory -CheckName $cn
                    $panel = $state.Controls."pnl${category}Checks"
                    if ($null -ne $panel) {
                        $severity = if ($checkResult.PSObject.Properties['Severity']) { $checkResult.Severity } else { 'Info' }
                        $remediation = if ($checkResult.PSObject.Properties['Remediation']) { $checkResult.Remediation } else { '' }
                        $durationMs = if ($checkResult.PSObject.Properties['DurationMs']) { $checkResult.DurationMs } else { 0 }

                        # Pass handler scriptblocks so new buttons are wired at creation time
                        Update-DashboardCheckUI -State $state -CheckName $cn `
                            -Status $checkResult.Status -Severity $severity `
                            -Message $checkResult.Message -Remediation $remediation `
                            -DurationMs $durationMs `
                            -OnFixClick $script:onFixClickHandler `
                            -OnUnsafeFixClick $script:onUnsafeFixClickHandler `
                            -OnCopyClick $script:onCopyClickHandler
                    }
                }
            }
        })
        $refreshTimer.Start()
    } catch {
        # If refresh fails, log but don't crash — user can click Refresh manually
        if ($function:WriteLog) {
            WriteLog "WARNING: Single check refresh failed for $CheckName`: $($_.Exception.Message)"
        }
    }
}

# --------------------------------------------------------------------------
# Refresh button handler: re-runs dashboard checks on click
# --------------------------------------------------------------------------
$script:uiState.Controls.btnRefreshChecks.Add_Click({
    # Don't refresh during active builds
    if ($script:uiState.Flags.isBuilding) {
        return
    }
    Start-DashboardChecks
})

# --------------------------------------------------------------------------
# Auto-run dashboard checks on launch (non-blocking via ThreadJob)
# --------------------------------------------------------------------------
Start-DashboardChecks

[void]$window.ShowDialog()
