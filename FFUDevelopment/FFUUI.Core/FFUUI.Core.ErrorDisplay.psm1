<#
.SYNOPSIS
    Structured error display functions for the FFU Builder UI.

.DESCRIPTION
    Provides functions to display meaningful error dialogs with:
    - Severity indication (Critical, Error, Warning, Info)
    - Clear description of what went wrong
    - Remediation steps when available
    - Optional log file link for debugging
    - Technical error details when ErrorRecord provided

    Replaces generic MessageBox errors with actionable error dialogs.
#>

#region Internal Helper Functions

function Show-MessageBox {
    <#
    .SYNOPSIS
        Internal wrapper for WPF MessageBox to enable mocking in tests.

    .DESCRIPTION
        Wraps [System.Windows.MessageBox]::Show() to allow Pester tests to mock
        the dialog without displaying actual UI.
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.MessageBoxResult])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [System.Windows.MessageBoxButton]$Button = [System.Windows.MessageBoxButton]::OK,

        [Parameter()]
        [System.Windows.MessageBoxImage]$Icon = [System.Windows.MessageBoxImage]::Information
    )

    # Ensure WPF assembly is loaded
    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue

    return [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Icon)
}

function Format-FFUErrorMessage {
    <#
    .SYNOPSIS
        Formats error information into a structured message string.

    .DESCRIPTION
        Internal helper that builds a formatted error message with sections for:
        - Description
        - Remediation steps (numbered list if multiple)
        - Additional details (key-value pairs)
        - Log file path (if exists)

        Does NOT use emojis - uses text markers like [ERROR], ===, ---.

    .PARAMETER Description
        The main error description.

    .PARAMETER Remediation
        Array of remediation steps. Formatted as numbered list if multiple.

    .PARAMETER LogPath
        Path to log file. Included only if file exists.

    .PARAMETER Details
        Hashtable of additional key-value pairs to display.

    .OUTPUTS
        [string] - Formatted error message.

    .EXAMPLE
        $msg = Format-FFUErrorMessage -Description "Download failed" -Remediation @("Check network", "Retry")
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Description = '',

        [Parameter()]
        [string[]]$Remediation = @(),

        [Parameter()]
        [string]$LogPath = '',

        [Parameter()]
        [hashtable]$Details = @{}
    )

    $sb = [System.Text.StringBuilder]::new()

    # Description section
    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        [void]$sb.AppendLine($Description)
        [void]$sb.AppendLine()
    }

    # Additional details section
    if ($null -ne $Details -and $Details.Count -gt 0) {
        [void]$sb.AppendLine("--- DETAILS ---")
        foreach ($key in $Details.Keys) {
            [void]$sb.AppendLine("  ${key}: $($Details[$key])")
        }
        [void]$sb.AppendLine()
    }

    # Remediation section
    if ($null -ne $Remediation -and $Remediation.Count -gt 0) {
        [void]$sb.AppendLine("=== WHAT TO DO ===")
        if ($Remediation.Count -eq 1) {
            [void]$sb.AppendLine($Remediation[0])
        }
        else {
            $stepNum = 1
            foreach ($step in $Remediation) {
                [void]$sb.AppendLine("  $stepNum. $step")
                $stepNum++
            }
        }
        [void]$sb.AppendLine()
    }

    # Log file section
    if (-not [string]::IsNullOrWhiteSpace($LogPath) -and (Test-Path -Path $LogPath -PathType Leaf)) {
        [void]$sb.AppendLine("--- LOG FILE ---")
        [void]$sb.AppendLine("Check log file: $LogPath")
        [void]$sb.AppendLine()
    }

    return $sb.ToString().TrimEnd()
}

#endregion

#region Public Functions

function Show-FFUError {
    <#
    .SYNOPSIS
        Displays a structured error dialog with severity, title, description, and remediation.

    .DESCRIPTION
        Shows a WPF MessageBox with structured error information:
        - Severity: Critical, Error, Warning, or Info
        - Title: Brief error summary
        - Description: What went wrong
        - Remediation: Steps to fix the issue (numbered if multiple)
        - LogPath: If exists, shows "Check log file: path"
        - ErrorRecord: Technical details (exception message, stack trace)
        - Details: Additional key-value pairs

        Uses appropriate MessageBox icons based on severity:
        - Critical/Error: Error icon
        - Warning: Warning icon
        - Info: Information icon

    .PARAMETER Severity
        Error severity level. ValidateSet: Critical, Error, Warning, Info.

    .PARAMETER Title
        Brief error title shown in the message box title bar.

    .PARAMETER Description
        Main error description explaining what went wrong.

    .PARAMETER Remediation
        Array of remediation steps. Formatted as numbered list if multiple.

    .PARAMETER LogPath
        Path to log file. Included only if file exists.

    .PARAMETER ErrorRecord
        PowerShell ErrorRecord for technical details.

    .PARAMETER Details
        Hashtable of additional key-value pairs to display.

    .OUTPUTS
        [System.Windows.MessageBoxResult] - The button clicked by user.

    .EXAMPLE
        Show-FFUError -Severity Error -Title "Download Failed" -Description "Could not download driver package"

    .EXAMPLE
        Show-FFUError -Severity Critical -Title "Build Failed" -Description "DISM operation failed" `
            -Remediation @("Check disk space", "Verify admin rights", "Restart and retry") `
            -LogPath "C:\FFUDevelopment\Logs\build.log"
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.MessageBoxResult])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Info')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter()]
        [string[]]$Remediation = @(),

        [Parameter()]
        [string]$LogPath = '',

        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter()]
        [hashtable]$Details = @{}
    )

    # Log the error call for debugging
    $logAvailable = $false
    try {
        if ($ExecutionContext.InvokeCommand.GetCommand('WriteLog', 'Function')) {
            $logAvailable = $true
        }
    }
    catch {
        # WriteLog not available - continue without logging
        $logAvailable = $false
    }

    if ($logAvailable) {
        WriteLog "[$Severity] $Title - $Description"
    }

    # Build the message
    $sb = [System.Text.StringBuilder]::new()

    # Severity header
    [void]$sb.AppendLine("[$Severity] $Title")
    [void]$sb.AppendLine()

    # Format main content
    $formattedMessage = Format-FFUErrorMessage -Description $Description `
        -Remediation $Remediation -LogPath $LogPath -Details $Details
    [void]$sb.Append($formattedMessage)

    # Add ErrorRecord technical details if provided
    if ($null -ne $ErrorRecord) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("--- TECHNICAL DETAILS ---")
        if ($null -ne $ErrorRecord.Exception) {
            [void]$sb.AppendLine("Exception: $($ErrorRecord.Exception.Message)")
        }
        if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace)) {
            [void]$sb.AppendLine()
            [void]$sb.AppendLine("Stack Trace:")
            [void]$sb.AppendLine($ErrorRecord.ScriptStackTrace)
        }
    }

    $message = $sb.ToString()

    # Determine icon based on severity
    $icon = switch ($Severity) {
        'Critical' { [System.Windows.MessageBoxImage]::Error }
        'Error' { [System.Windows.MessageBoxImage]::Error }
        'Warning' { [System.Windows.MessageBoxImage]::Warning }
        'Info' { [System.Windows.MessageBoxImage]::Information }
    }

    # Show the message box
    return Show-MessageBox -Message $message -Title $Title -Button OK -Icon $icon
}

function Show-FFUValidationErrors {
    # Plural noun is intentional - this function displays multiple validation errors
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    <#
    .SYNOPSIS
        Displays validation errors and warnings in a structured dialog.

    .DESCRIPTION
        Shows a WPF MessageBox with validation results:
        - Errors are shown with (X) prefix
        - Warnings are shown with (!) prefix
        - Config path is shown if provided
        - Uses Error icon if errors present, Warning icon if only warnings

    .PARAMETER Errors
        Array of validation error messages.

    .PARAMETER Warnings
        Array of validation warning messages.

    .PARAMETER Title
        Dialog title. Defaults to "Configuration Validation Failed".

    .PARAMETER ConfigPath
        Path to config file being validated. Shown in message if provided.

    .OUTPUTS
        [System.Windows.MessageBoxResult] - The button clicked by user.

    .EXAMPLE
        Show-FFUValidationErrors -Errors @("Invalid path", "Missing required field")

    .EXAMPLE
        Show-FFUValidationErrors -Errors @() -Warnings @("Deprecated option used") `
            -Title "Configuration Warnings" -ConfigPath "C:\config.json"
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.MessageBoxResult])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Errors,

        [Parameter()]
        [string[]]$Warnings = @(),

        [Parameter()]
        [string]$Title = 'Configuration Validation Failed',

        [Parameter()]
        [string]$ConfigPath = ''
    )

    # Log the validation call for debugging
    $logAvailable = $false
    try {
        if ($ExecutionContext.InvokeCommand.GetCommand('WriteLog', 'Function')) {
            $logAvailable = $true
        }
    }
    catch {
        # WriteLog not available - continue without logging
        $logAvailable = $false
    }

    $errorCount = if ($null -ne $Errors) { $Errors.Count } else { 0 }
    $warningCount = if ($null -ne $Warnings) { $Warnings.Count } else { 0 }

    if ($logAvailable) {
        WriteLog "Validation: $errorCount errors, $warningCount warnings"
    }

    $sb = [System.Text.StringBuilder]::new()

    # Errors section
    if ($errorCount -gt 0) {
        [void]$sb.AppendLine("The following errors were found:")
        [void]$sb.AppendLine()
        foreach ($err in $Errors) {
            [void]$sb.AppendLine("  (X) $err")
        }
        [void]$sb.AppendLine()
    }

    # Warnings section
    if ($warningCount -gt 0) {
        if ($errorCount -eq 0) {
            [void]$sb.AppendLine("The following warnings were found:")
            [void]$sb.AppendLine()
        }
        else {
            [void]$sb.AppendLine("Additionally, the following warnings were found:")
            [void]$sb.AppendLine()
        }
        foreach ($warn in $Warnings) {
            [void]$sb.AppendLine("  (!) $warn")
        }
        [void]$sb.AppendLine()
    }

    # Config path section
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        [void]$sb.AppendLine("Config file: $ConfigPath")
    }

    $message = $sb.ToString().TrimEnd()

    # Determine icon based on content
    $icon = if ($errorCount -gt 0) {
        [System.Windows.MessageBoxImage]::Error
    }
    else {
        [System.Windows.MessageBoxImage]::Warning
    }

    # Adjust title if only warnings
    $displayTitle = if ($errorCount -eq 0 -and $warningCount -gt 0) {
        'Configuration Validation Warnings'
    }
    else {
        $Title
    }

    return Show-MessageBox -Message $message -Title $displayTitle -Button OK -Icon $icon
}

#endregion

#region Module Export

Export-ModuleMember -Function @(
    'Show-FFUError',
    'Show-FFUValidationErrors',
    'Format-FFUErrorMessage',
    'Show-MessageBox'
)

#endregion
