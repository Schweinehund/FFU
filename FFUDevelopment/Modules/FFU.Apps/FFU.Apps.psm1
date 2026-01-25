<#
.SYNOPSIS
    FFU Builder Application Management Module

.DESCRIPTION
    Application installation and management for FFU Builder.
    Handles Office Deployment Tool, application ISO creation, and
    provisioned app removal (bloatware cleanup).

.NOTES
    Module: FFU.Apps
    Version: 1.0.0
    Dependencies: FFU.Core
#>

#Requires -Version 7.0

# Import dependencies
$modulePath = Split-Path -Parent $PSScriptRoot
Import-Module "$modulePath\FFU.Core" -Force

function Get-ODTURL {
    <#
    .SYNOPSIS
    Retrieves the download URL for the Microsoft Office Deployment Tool (ODT)

    .DESCRIPTION
    Scrapes the Microsoft download page to extract the current ODT download URL
    from embedded JSON data. Returns the direct download link for officedeploymenttool.exe.

    .PARAMETER Headers
    HTTP headers hashtable for web requests (includes session cookies and metadata)

    .PARAMETER UserAgent
    User agent string to identify the client making the request

    .EXAMPLE
    $url = Get-ODTURL -Headers $headers -UserAgent $userAgent

    .OUTPUTS
    System.String - Direct download URL for the Office Deployment Tool executable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent
    )
    try {
        [String]$ODTPage = Invoke-WebRequest 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop

        # Extract JSON data from the webpage
        if ($ODTPage -match '<script>window\.__DLCDetails__=(.*?)<\/script>') {
            # Parse JSON content
            $jsonContent = $matches[1] | ConvertFrom-Json
            $ODTURL = $jsonContent.dlcDetailsView.downloadFile[0].url

            if ($ODTURL) {
                return $ODTURL
            }
            else {
                WriteLog 'Cannot find the ODT download URL in the JSON content'
                throw 'Cannot find the ODT download URL in the JSON content'
            }
        }
        else {
            WriteLog 'Failed to extract JSON content from the ODT webpage'
            throw 'Failed to extract JSON content from the ODT webpage'
        }
    }
    catch {
        WriteLog $_.Exception.Message
        throw 'An error occurred while retrieving the ODT URL.'
    }
}

function Get-Office {
    <#
    .SYNOPSIS
    Downloads and configures Microsoft 365 Apps (Office) for FFU deployment

    .DESCRIPTION
    Downloads Office Deployment Tool (ODT), extracts it, configures download settings,
    downloads Office files, and creates installation script for VM orchestration.

    .PARAMETER OfficePath
    Destination folder for Office files (e.g., "C:\FFUDevelopment\Apps\Office")

    .PARAMETER OfficeDownloadXML
    Path to XML configuration file for Office download

    .PARAMETER OfficeInstallXML
    Name of XML configuration file for Office installation (default: "DeployFFU.xml")

    .PARAMETER OrchestrationPath
    Path to orchestration folder where Install-Office.ps1 will be created

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download progress tracking

    .PARAMETER Headers
    HTTP headers hashtable for web requests

    .PARAMETER UserAgent
    User agent string for web requests

    .PARAMETER OfficeConfigXMLFile
    Optional custom Office configuration XML file path

    .EXAMPLE
    Get-Office -OfficePath "C:\FFU\Apps\Office" -OfficeDownloadXML "C:\FFU\Apps\Office\Download.xml" `
               -OrchestrationPath "C:\FFU\Apps\Orchestration" -FFUDevelopmentPath "C:\FFU" `
               -Headers @{} -UserAgent "Mozilla/5.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OfficePath,

        [Parameter(Mandatory = $true)]
        [string]$OfficeDownloadXML,

        [Parameter(Mandatory = $false)]
        [string]$OfficeInstallXML = "DeployFFU.xml",

        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $false)]
        [string]$OfficeConfigXMLFile
    )

    # If a custom Office Config XML is provided, use its filename for installation
    if (-not [string]::IsNullOrEmpty($OfficeConfigXMLFile)) {
        $OfficeInstallXML = Split-Path -Path $OfficeConfigXMLFile -Leaf
        WriteLog "A custom Office configuration file was specified. Using '$OfficeInstallXML' for installation."
    }

    # Ensure Office directory exists
    if (-not (Test-Path $OfficePath)) {
        WriteLog "Creating Office directory: $OfficePath"
        New-Item -Path $OfficePath -ItemType Directory -Force | Out-Null
    }

    # Download ODT with proper error handling
    $ODTUrl = Get-ODTURL -Headers $Headers -UserAgent $UserAgent
    $ODTInstallFile = Join-Path $OfficePath "odtsetup.exe"
    WriteLog "Downloading Office Deployment Toolkit from $ODTUrl to $ODTInstallFile"

    try {
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstallFile -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
        $VerbosePreference = $OriginalVerbosePreference

        # Validate download succeeded
        if (-not (Test-Path $ODTInstallFile)) {
            throw "ODT download appeared to succeed but file not found at: $ODTInstallFile"
        }
        $odtFileInfo = Get-Item $ODTInstallFile
        if ($odtFileInfo.Length -eq 0) {
            throw "ODT download resulted in empty file: $ODTInstallFile"
        }
        WriteLog "ODT downloaded successfully ($($odtFileInfo.Length) bytes)"
    }
    catch {
        throw "Failed to download Office Deployment Toolkit from $ODTUrl : $($_.Exception.Message)"
    }

    # Extract ODT
    WriteLog "Extracting ODT to $OfficePath"
    Invoke-Process $ODTInstallFile "/extract:$OfficePath /quiet" | Out-Null

    # Run setup.exe with config.xml and modify xml file to download to $OfficePath
    $xmlContent = [xml](Get-Content $OfficeDownloadXML)
    $xmlContent.Configuration.Add.SourcePath = $OfficePath
    $xmlContent.Save($OfficeDownloadXML)
    Set-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $OfficePath
    WriteLog "Downloading M365 Apps/Office to $OfficePath"
    $setupExe = Join-Path $OfficePath "setup.exe"
    Invoke-Process $setupExe "/download $OfficeDownloadXML" | Out-Null
    Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $OfficePath

    WriteLog "Cleaning up ODT default config files"
    # Clean up default configuration files - use ErrorAction to prevent non-terminating errors
    Remove-Item -Path "$OfficePath\configuration*" -Force -ErrorAction SilentlyContinue

    # Create Install-Office.ps1 in orchestration folder
    $installOfficePath = Join-Path -Path $OrchestrationPath -ChildPath "Install-Office.ps1"
    WriteLog "Creating $installOfficePath"

    # Create the Install-Office.ps1 file
    $installOfficeCommand = "& d:\Office\setup.exe /configure d:\office\$OfficeInstallXML"
    Set-Content -Path $installOfficePath -Value $installOfficeCommand -Force
    WriteLog "Install-Office.ps1 created successfully at $installOfficePath"

    # Remove the ODT setup file
    WriteLog "Removing ODT setup file"
    if (-not [string]::IsNullOrWhiteSpace($ODTInstallFile)) {
        Remove-Item -Path $ODTInstallFile -Force -ErrorAction SilentlyContinue
    }
    WriteLog "ODT setup file removed"
}

function New-AppsISO {
    <#
    .SYNOPSIS
    Creates an ISO file from the Apps folder for deployment

    .DESCRIPTION
    Uses oscdimg.exe from Windows ADK to create a bootable ISO containing
    applications from the Apps folder. The ISO can be mounted in VMs for
    application installation during FFU build.

    .PARAMETER ADKPath
    Path to Windows ADK installation (e.g., "C:\Program Files (x86)\Windows Kits\10\")

    .PARAMETER AppsPath
    Path to the Apps folder containing application files

    .PARAMETER AppsISO
    Output path for the ISO file

    .EXAMPLE
    New-AppsISO -ADKPath $adkPath -AppsPath "C:\FFUDevelopment\Apps" -AppsISO "C:\FFUDevelopment\Apps\Apps.iso"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ADKPath,

        [Parameter(Mandatory = $true)]
        [string]$AppsPath,

        [Parameter(Mandatory = $true)]
        [string]$AppsISO
    )

    # Construct path to oscdimg.exe in ADK
    $OSCDIMG = Join-Path $ADKPath "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

    if (-not (Test-Path $OSCDIMG)) {
        throw "oscdimg.exe not found at: $OSCDIMG. Ensure Windows ADK Deployment Tools are installed."
    }

    # Adding Long Path support for AppsPath to prevent issues with oscdimg
    $AppsPathLong = '\\?\' + $AppsPath

    WriteLog "Creating ISO from $AppsPath to $AppsISO"
    WriteLog "Using oscdimg: $OSCDIMG"

    Invoke-Process $OSCDIMG "-n -m -d $AppsPathLong $AppsISO" | Out-Null
}

function New-AppsContentManifest {
    <#
    .SYNOPSIS
    Creates a content manifest for the Apps folder with SHA256 hashes of all component files

    .DESCRIPTION
    Generates a .manifest.json file containing SHA256 hashes of all files in the Apps
    folder components (Office, Defender, MSRT, Edge, OneDrive, Orchestration, Win32, MSStore).
    The manifest includes configuration state to detect when build options change.
    This enables accurate staleness detection for Apps.iso rebuilds.

    .PARAMETER AppsPath
    Path to the Apps folder (e.g., "C:\FFUDevelopment\Apps")

    .PARAMETER ConfigState
    Hashtable containing current configuration state:
    - InstallOffice: Whether Office installation is enabled
    - UpdateLatestDefender: Whether Defender update is enabled
    - UpdateLatestMSRT: Whether MSRT update is enabled
    - UpdateEdge: Whether Edge update is enabled
    - UpdateOneDrive: Whether OneDrive update is enabled

    .EXAMPLE
    $config = @{
        InstallOffice = $true
        UpdateLatestDefender = $true
        UpdateLatestMSRT = $false
        UpdateEdge = $true
        UpdateOneDrive = $true
    }
    $manifest = New-AppsContentManifest -AppsPath "C:\FFUDevelopment\Apps" -ConfigState $config

    .OUTPUTS
    [hashtable] The manifest data structure with Version, Generated, ConfigState, Components, and ManifestHash
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$AppsPath,

        [Parameter(Mandatory)]
        [hashtable]$ConfigState
    )

    try {
        WriteLog "Generating Apps content manifest..."

        # Initialize manifest structure
        $manifest = @{
            Version     = "1.0.0"
            Generated   = [DateTime]::UtcNow.ToString("o")
            ConfigState = @{
                InstallOffice        = [bool]$ConfigState.InstallOffice
                UpdateLatestDefender = [bool]$ConfigState.UpdateLatestDefender
                UpdateLatestMSRT     = [bool]$ConfigState.UpdateLatestMSRT
                UpdateEdge           = [bool]$ConfigState.UpdateEdge
                UpdateOneDrive       = [bool]$ConfigState.UpdateOneDrive
            }
            Components  = @{}
            TotalSize   = 0
            ManifestHash = ""
        }

        # Define component paths relative to AppsPath
        $componentNames = @(
            'Orchestration',
            'Office',
            'Defender',
            'MSRT',
            'Edge',
            'OneDrive',
            'Win32',
            'MSStore'
        )

        foreach ($componentName in $componentNames) {
            $componentPath = Join-Path $AppsPath $componentName

            if (Test-Path $componentPath) {
                $componentFiles = Get-ChildItem -Path $componentPath -Recurse -File -ErrorAction SilentlyContinue

                if ($componentFiles -and $componentFiles.Count -gt 0) {
                    $fileEntries = @()
                    $componentSize = 0

                    foreach ($file in $componentFiles) {
                        $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
                        $relativePath = $file.FullName.Substring($AppsPath.Length).TrimStart('\', '/')

                        $fileEntries += @{
                            Path = $relativePath
                            Hash = $hash
                            Size = $file.Length
                        }
                        $componentSize += $file.Length
                    }

                    $sizeGB = [Math]::Round($componentSize / 1GB, 2)
                    WriteLog "  Hashing $componentName`: $($componentFiles.Count) files, $sizeGB GB"

                    $manifest.Components[$componentName] = @{
                        Path      = $componentName
                        Files     = $fileEntries
                        FileCount = $componentFiles.Count
                        TotalSize = $componentSize
                    }

                    $manifest.TotalSize += $componentSize
                }
            }
        }

        # Calculate ManifestHash (SHA256 of manifest JSON without ManifestHash field)
        $manifestForHash = $manifest.Clone()
        $manifestForHash.ManifestHash = ""
        $manifestJson = $manifestForHash | ConvertTo-Json -Depth 10 -Compress
        $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($manifestJson)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($manifestBytes)
        $manifest.ManifestHash = [BitConverter]::ToString($hashBytes).Replace("-", "")

        # Write manifest to file
        $manifestPath = Join-Path $AppsPath ".manifest.json"
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Force

        WriteLog "Manifest saved: $manifestPath"

        return $manifest
    }
    catch {
        WriteLog "ERROR: Failed to create Apps content manifest: $($_.Exception.Message)"
        throw
    }
}

function Get-AppsContentManifest {
    <#
    .SYNOPSIS
    Reads an existing Apps content manifest

    .DESCRIPTION
    Reads and returns the .manifest.json file from the Apps folder.
    Returns $null if the manifest does not exist.

    .PARAMETER AppsPath
    Path to the Apps folder (e.g., "C:\FFUDevelopment\Apps")

    .EXAMPLE
    $manifest = Get-AppsContentManifest -AppsPath "C:\FFUDevelopment\Apps"
    if ($manifest) {
        Write-Host "Manifest version: $($manifest.Version)"
    }

    .OUTPUTS
    [PSCustomObject] The parsed manifest data, or $null if manifest does not exist
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$AppsPath
    )

    $manifestPath = Join-Path $AppsPath ".manifest.json"
    WriteLog "Reading Apps content manifest from $manifestPath"

    if (-not (Test-Path $manifestPath)) {
        WriteLog "  Manifest not found"
        return $null
    }

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

    WriteLog "  Manifest version: $($manifest.Version), generated: $($manifest.Generated)"

    return $manifest
}

function Test-AppsISOStaleness {
    <#
    .SYNOPSIS
    Tests whether the Apps.iso needs to be rebuilt based on content hash comparison

    .DESCRIPTION
    Performs three-tier staleness detection:
    - Tier 1: ISO existence check
    - Tier 2: Manifest existence and configuration comparison
    - Tier 3: File hash comparison against stored manifest

    Returns a structured result indicating whether rebuild is needed and why.

    .PARAMETER AppsISOPath
    Full path to the Apps.iso file

    .PARAMETER AppsPath
    Path to the Apps folder (e.g., "C:\FFUDevelopment\Apps")

    .PARAMETER CurrentConfig
    Hashtable containing current configuration state:
    - InstallOffice: Whether Office installation is enabled
    - UpdateLatestDefender: Whether Defender update is enabled
    - UpdateLatestMSRT: Whether MSRT update is enabled
    - UpdateEdge: Whether Edge update is enabled
    - UpdateOneDrive: Whether OneDrive update is enabled

    .EXAMPLE
    $config = @{
        InstallOffice = $true
        UpdateLatestDefender = $true
        UpdateLatestMSRT = $false
        UpdateEdge = $true
        UpdateOneDrive = $true
    }
    $result = Test-AppsISOStaleness -AppsISOPath "C:\FFU\Apps.iso" -AppsPath "C:\FFU\Apps" -CurrentConfig $config
    if ($result.Stale) {
        Write-Host "Rebuild needed: $($result.Reason)"
    }

    .OUTPUTS
    [PSCustomObject] with properties:
    - Stale: [bool] Whether ISO needs rebuild
    - Reason: [string] Explanation of staleness status
    - Action: [string] "Create", "Rebuild", or "Skip"
    - Details: [array] Specific items that changed
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$AppsISOPath,

        [Parameter(Mandatory)]
        [string]$AppsPath,

        [Parameter(Mandatory)]
        [hashtable]$CurrentConfig
    )

    WriteLog "Checking Apps.iso staleness..."

    # Tier 1: ISO existence check
    if (-not (Test-Path $AppsISOPath)) {
        WriteLog "  Tier 1: ISO does not exist at $AppsISOPath"
        WriteLog "  Result: Create - Apps.iso does not exist"
        return [PSCustomObject]@{
            Stale   = $true
            Reason  = "Apps.iso does not exist"
            Action  = "Create"
            Details = @()
        }
    }
    WriteLog "  Tier 1: ISO exists at $AppsISOPath"

    # Tier 2: Manifest existence and config comparison
    $storedManifest = Get-AppsContentManifest -AppsPath $AppsPath

    if ($null -eq $storedManifest) {
        WriteLog "  Tier 2: No content manifest found"
        WriteLog "  Result: Rebuild - No content manifest found - first build or manifest deleted"
        return [PSCustomObject]@{
            Stale   = $true
            Reason  = "No content manifest found - first build or manifest deleted"
            Action  = "Rebuild"
            Details = @()
        }
    }
    WriteLog "  Tier 2: Manifest found, comparing configuration..."

    # Compare configuration state
    $configKeys = @('InstallOffice', 'UpdateLatestDefender', 'UpdateLatestMSRT', 'UpdateEdge', 'UpdateOneDrive')
    $changedConfigs = @()

    foreach ($key in $configKeys) {
        $currentValue = [bool]$CurrentConfig[$key]
        $storedValue = [bool]$storedManifest.ConfigState.$key

        if ($currentValue -ne $storedValue) {
            $changedConfigs += "$key changed from $storedValue to $currentValue"
            WriteLog "  Tier 2: Config mismatch: $key changed from $storedValue to $currentValue"
        }
    }

    if ($changedConfigs.Count -gt 0) {
        WriteLog "  Result: Rebuild - Configuration changed"
        return [PSCustomObject]@{
            Stale   = $true
            Reason  = "Configuration changed"
            Action  = "Rebuild"
            Details = $changedConfigs
        }
    }
    WriteLog "  Tier 2: Configuration matches"

    # Tier 3: File hash comparison
    WriteLog "  Tier 3: Comparing file hashes..."

    # Generate current manifest for comparison
    $currentManifest = New-AppsContentManifest -AppsPath $AppsPath -ConfigState $CurrentConfig

    $changedFiles = @()

    # Get component names from both manifests
    $allComponents = @()
    if ($storedManifest.Components) {
        # Handle both hashtable and PSCustomObject
        if ($storedManifest.Components -is [hashtable]) {
            $allComponents += $storedManifest.Components.Keys
        }
        else {
            $allComponents += $storedManifest.Components.PSObject.Properties.Name
        }
    }
    if ($currentManifest.Components) {
        if ($currentManifest.Components -is [hashtable]) {
            $allComponents += $currentManifest.Components.Keys
        }
        else {
            $allComponents += $currentManifest.Components.PSObject.Properties.Name
        }
    }
    $allComponents = $allComponents | Select-Object -Unique

    foreach ($componentName in $allComponents) {
        # Get stored component data
        $storedComponent = $null
        if ($storedManifest.Components) {
            if ($storedManifest.Components -is [hashtable]) {
                $storedComponent = $storedManifest.Components[$componentName]
            }
            else {
                $storedComponent = $storedManifest.Components.$componentName
            }
        }

        # Get current component data
        $currentComponent = $null
        if ($currentManifest.Components) {
            if ($currentManifest.Components -is [hashtable]) {
                $currentComponent = $currentManifest.Components[$componentName]
            }
            else {
                $currentComponent = $currentManifest.Components.$componentName
            }
        }

        # Component removed
        if ($storedComponent -and -not $currentComponent) {
            $changedFiles += "$componentName`: removed (was $($storedComponent.FileCount) files)"
            WriteLog "  Tier 3: $componentName`: removed"
            continue
        }

        # Component added
        if (-not $storedComponent -and $currentComponent) {
            $changedFiles += "$componentName`: added ($($currentComponent.FileCount) files)"
            WriteLog "  Tier 3: $componentName`: added ($($currentComponent.FileCount) files)"
            continue
        }

        # Compare file counts
        $storedCount = if ($storedComponent.FileCount) { $storedComponent.FileCount } else { 0 }
        $currentCount = if ($currentComponent.FileCount) { $currentComponent.FileCount } else { 0 }

        if ($storedCount -ne $currentCount) {
            $diff = $currentCount - $storedCount
            $diffText = if ($diff -gt 0) { "+$diff" } else { "$diff" }
            $changedFiles += "$componentName`: file count changed ($storedCount -> $currentCount, $diffText files)"
            WriteLog "  Tier 3: $componentName`: file count changed ($storedCount -> $currentCount)"
            continue
        }

        # Compare individual file hashes
        $storedFiles = @{}
        if ($storedComponent.Files) {
            foreach ($file in $storedComponent.Files) {
                $path = if ($file -is [hashtable]) { $file.Path } else { $file.Path }
                $hash = if ($file -is [hashtable]) { $file.Hash } else { $file.Hash }
                $storedFiles[$path] = $hash
            }
        }

        $currentFiles = @{}
        if ($currentComponent.Files) {
            foreach ($file in $currentComponent.Files) {
                $path = if ($file -is [hashtable]) { $file.Path } else { $file.Path }
                $hash = if ($file -is [hashtable]) { $file.Hash } else { $file.Hash }
                $currentFiles[$path] = $hash
            }
        }

        $hashMismatches = 0
        foreach ($path in $currentFiles.Keys) {
            if ($storedFiles.ContainsKey($path)) {
                if ($storedFiles[$path] -ne $currentFiles[$path]) {
                    $hashMismatches++
                }
            }
            else {
                $hashMismatches++
            }
        }

        if ($hashMismatches -gt 0) {
            $changedFiles += "$componentName`: $hashMismatches file(s) with hash mismatch"
            WriteLog "  Tier 3: $componentName`: $hashMismatches file(s) changed"
        }
    }

    if ($changedFiles.Count -gt 0) {
        WriteLog "  Result: Rebuild - Content files changed"
        return [PSCustomObject]@{
            Stale   = $true
            Reason  = "Content files changed"
            Action  = "Rebuild"
            Details = $changedFiles
        }
    }

    # No changes detected
    WriteLog "  Result: Skip - Apps.iso is current - no content or config changes detected"
    return [PSCustomObject]@{
        Stale   = $false
        Reason  = "Apps.iso is current - no content or config changes detected"
        Action  = "Skip"
        Details = @()
    }
}

function Remove-Apps {

    # Check if the file exists before attempting to clear it
    if (Test-Path -Path $wingetWin32jsonFile) {
        WriteLog "Removing $wingetWin32jsonFile"
        Remove-Item -Path $wingetWin32jsonFile -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    # Clean up Win32 and MSStore folders
    if (Test-Path -Path "$AppsPath\Win32" -PathType Container) {
        WriteLog "Cleaning up Win32 folder"
        Remove-Item -Path "$AppsPath\Win32" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -Path "$AppsPath\MSStore" -PathType Container) {
        WriteLog "Cleaning up MSStore folder"
        Remove-Item -Path "$AppsPath\MSStore" -Recurse -Force -ErrorAction SilentlyContinue
    }

    #Remove the Office Download and ODT
    if ($InstallOffice) {
        $ODTPath = "$AppsPath\Office"
        $OfficeDownloadPath = "$ODTPath\Office"
        WriteLog 'Removing Office and ODT download'
        if (-not [string]::IsNullOrWhiteSpace($OfficeDownloadPath)) {
            Remove-Item -Path $OfficeDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path "$ODTPath\setup.exe" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$orchestrationPath\Install-Office.ps1" -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }

    #Remove AppsISO
    if ($CleanupAppsISO) {
        WriteLog "Removing $AppsISO"
        Remove-Item -Path $AppsISO -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
}

function Remove-DisabledArtifacts {
    <#
    .SYNOPSIS
    Removes artifacts for features disabled via command-line flags

    .DESCRIPTION
    Cleans up downloaded artifacts (Office, Defender, MSRT, OneDrive, Edge) when
    the corresponding install/update flags are disabled. Prevents unnecessary
    artifacts from being included in the final FFU image.

    .EXAMPLE
    Remove-DisabledArtifacts
    #>
    [CmdletBinding()]
    param()

    # Remove Office artifacts if Install Office is disabled
    if (-not $InstallOffice) {
        $removed = $false
        if (Test-Path -Path $installOfficePath) {
            WriteLog "Install Office disabled - removing $installOfficePath"
            Remove-Item -Path $installOfficePath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $OfficePath) {
            WriteLog 'Removing Office and ODT download'
            $OfficeDownloadPath = "$OfficePath\Office"
            Remove-Item -Path $OfficeDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$OfficePath\setup.exe" -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }


    # Remove Defender artifacts if Defender update is disabled
    if (-not $UpdateLatestDefender) {
        $removed = $false
        if (Test-Path -Path $installDefenderPath) {
            WriteLog "Update Defender disabled - removing $installDefenderPath"
            Remove-Item -Path $installDefenderPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $DefenderPath) {
            WriteLog "Update Defender disabled - removing $DefenderPath"
            Remove-Item -Path $DefenderPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove MSRT artifacts if MSRT update is disabled
    if (-not $UpdateLatestMSRT) {
        $removed = $false
        if (Test-Path -Path $installMSRTPath) {
            WriteLog "Update MSRT disabled - removing $installMSRTPath"
            Remove-Item -Path $installMSRTPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $MSRTPath) {
            WriteLog "Update MSRT disabled - removing $MSRTPath"
            Remove-Item -Path $MSRTPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove OneDrive artifacts if OneDrive update is disabled
    if (-not $UpdateOneDrive) {
        $removed = $false
        if (Test-Path -Path $installODPath) {
            WriteLog "Update OneDrive disabled - removing $installODPath"
            Remove-Item -Path $installODPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $OneDrivePath) {
            WriteLog "Update OneDrive disabled - removing $OneDrivePath"
            Remove-Item -Path $OneDrivePath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove Edge artifacts if Edge update is disabled
    if (-not $UpdateEdge) {
        $removed = $false
        if (Test-Path -Path $installEdgePath) {
            WriteLog "Update Edge disabled - removing $installEdgePath"
            Remove-Item -Path $installEdgePath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $EdgePath) {
            WriteLog "Update Edge disabled - removing $EdgePath"
            Remove-Item -Path $EdgePath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ODTURL',
    'Get-Office',
    'New-AppsISO',
    'Remove-Apps',
    'Remove-DisabledArtifacts',
    'New-AppsContentManifest',
    'Get-AppsContentManifest',
    'Test-AppsISOStaleness'
)