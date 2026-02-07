using Newtonsoft.Json;

namespace FFUBuilder.App.Models;

public class BuildConfiguration
{
    #region Schema/Meta

    [JsonProperty("configSchemaVersion")]
    public string ConfigSchemaVersion { get; set; } = "1.0";

    #endregion

    #region Windows Settings

    [JsonProperty("WindowsRelease")]
    public int WindowsRelease { get; set; } = 11;

    [JsonProperty("WindowsSKU")]
    public string WindowsSKU { get; set; } = "Pro";

    [JsonProperty("WindowsVersion")]
    public string WindowsVersion { get; set; } = "24h2";

    [JsonProperty("WindowsArch")]
    public string WindowsArch { get; set; } = "x64";

    [JsonProperty("WindowsLang")]
    public string WindowsLang { get; set; } = "en-us";

    [JsonProperty("MediaType")]
    public string MediaType { get; set; } = "consumer";

    [JsonProperty("ProductKey")]
    public string ProductKey { get; set; } = "";

    [JsonProperty("ISOPath")]
    public string ISOPath { get; set; } = "";

    [JsonProperty("OptionalFeatures")]
    public string OptionalFeatures { get; set; } = "";

    #endregion

    #region VM Settings

    [JsonProperty("VMName")]
    public string VMName { get; set; } = "YOURPC";

    [JsonProperty("Memory")]
    public long Memory { get; set; } = 4294967296; // 4GB

    [JsonProperty("Disksize")]
    public long Disksize { get; set; } = 32212254720; // 30GB

    [JsonProperty("Processors")]
    public int Processors { get; set; } = 4;

    [JsonProperty("VMLocation")]
    public string VMLocation { get; set; } = "";

    [JsonProperty("VMSwitchName")]
    public string VMSwitchName { get; set; } = "";

    [JsonProperty("VMHostIPAddress")]
    public string VMHostIPAddress { get; set; } = "";

    [JsonProperty("LogicalSectorSizeBytes")]
    public int LogicalSectorSizeBytes { get; set; } = 512;

    [JsonProperty("VMShutdownTimeoutMinutes")]
    public int VMShutdownTimeoutMinutes { get; set; } = 60;

    [JsonProperty("FFUFileLockWaitSeconds")]
    public int FFUFileLockWaitSeconds { get; set; } = 120;

    [JsonProperty("FFUFileLockRetryCount")]
    public int FFUFileLockRetryCount { get; set; } = 3;

    [JsonProperty("FFUFileLockRetryDelaySeconds")]
    public int FFUFileLockRetryDelaySeconds { get; set; } = 10;

    #endregion

    #region Hypervisor Settings

    [JsonProperty("HypervisorType")]
    public string HypervisorType { get; set; } = "HyperV";

    [JsonProperty("ShowVMConsole")]
    public bool ShowVMConsole { get; set; } = true;

    [JsonProperty("ForceVMwareDriverDownload")]
    public bool ForceVMwareDriverDownload { get; set; }

    [JsonProperty("VMwareNetworkType")]
    public string VMwareNetworkType { get; set; } = "nat";

    [JsonProperty("VMwareNicType")]
    public string VMwareNicType { get; set; } = "e1000e";

    [JsonProperty("VirtualDiskFormat")]
    public string VirtualDiskFormat { get; set; } = "VHDX";

    [JsonProperty("VMwareSettings")]
    public VMwareSettingsModel? VMwareSettings { get; set; }

    #endregion

    #region Paths

    [JsonProperty("FFUDevelopmentPath")]
    public string FFUDevelopmentPath { get; set; } = "";

    [JsonProperty("FFUCaptureLocation")]
    public string FFUCaptureLocation { get; set; } = "";

    [JsonProperty("FFUPrefix")]
    public string FFUPrefix { get; set; } = "_FFU";

    [JsonProperty("CustomFFUNameTemplate")]
    public string CustomFFUNameTemplate { get; set; } = "{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}";

    [JsonProperty("ShareName")]
    public string ShareName { get; set; } = "FFUCaptureShare";

    [JsonProperty("SharePath")]
    public string SharePath { get; set; } = "";

    [JsonProperty("Username")]
    public string Username { get; set; } = "ffu_user";

    [JsonProperty("ConfigFile")]
    public string ConfigFile { get; set; } = "";

    [JsonProperty("ExportConfigFile")]
    public string ExportConfigFile { get; set; } = "";

    #endregion

    #region Apps/Office

    [JsonProperty("InstallApps")]
    public bool InstallApps { get; set; } = true;

    [JsonProperty("InstallOffice")]
    public bool InstallOffice { get; set; } = true;

    [JsonProperty("AppListPath")]
    public string AppListPath { get; set; } = "";

    [JsonProperty("UserAppListPath")]
    public string UserAppListPath { get; set; } = "";

    [JsonProperty("OrchestrationPath")]
    public string OrchestrationPath { get; set; } = "";

    [JsonProperty("AppsScriptVariables")]
    public Dictionary<string, string>? AppsScriptVariables { get; set; }

    [JsonProperty("OfficeConfigXMLFile")]
    public string OfficeConfigXMLFile { get; set; } = "";

    [JsonProperty("CopyOfficeConfigXML")]
    public bool CopyOfficeConfigXML { get; set; }

    [JsonProperty("InjectUnattend")]
    public bool InjectUnattend { get; set; }

    #endregion

    #region Drivers

    [JsonProperty("InstallDrivers")]
    public bool InstallDrivers { get; set; } = true;

    [JsonProperty("Make")]
    public string Make { get; set; } = "";

    [JsonProperty("Model")]
    public string Model { get; set; } = "";

    [JsonProperty("DriversFolder")]
    public string DriversFolder { get; set; } = "";

    [JsonProperty("DriversJsonPath")]
    public string DriversJsonPath { get; set; } = "";

    [JsonProperty("PEDriversFolder")]
    public string PEDriversFolder { get; set; } = "";

    [JsonProperty("CopyDrivers")]
    public bool CopyDrivers { get; set; }

    [JsonProperty("CopyPEDrivers")]
    public bool CopyPEDrivers { get; set; }

    [JsonProperty("UseDriversAsPEDrivers")]
    public bool UseDriversAsPEDrivers { get; set; }

    [JsonProperty("CompressDownloadedDriversToWim")]
    public bool CompressDownloadedDriversToWim { get; set; }

    #endregion

    #region Updates

    [JsonProperty("UpdateLatestCU")]
    public bool UpdateLatestCU { get; set; } = true;

    [JsonProperty("UpdateLatestNet")]
    public bool UpdateLatestNet { get; set; } = true;

    [JsonProperty("UpdateLatestNet48")]
    public bool UpdateLatestNet48 { get; set; } = true;

    [JsonProperty("UpdateLatestDefender")]
    public bool UpdateLatestDefender { get; set; } = true;

    [JsonProperty("UpdateEdge")]
    public bool UpdateEdge { get; set; } = true;

    [JsonProperty("UpdateOneDrive")]
    public bool UpdateOneDrive { get; set; } = true;

    [JsonProperty("UpdateLatestMSRT")]
    public bool UpdateLatestMSRT { get; set; } = true;

    [JsonProperty("UpdateLatestMicrocode")]
    public bool UpdateLatestMicrocode { get; set; }

    [JsonProperty("UpdatePreviewCU")]
    public bool UpdatePreviewCU { get; set; }

    [JsonProperty("IncludePreviewUpdates")]
    public bool IncludePreviewUpdates { get; set; }

    [JsonProperty("BitsPriority")]
    public string BitsPriority { get; set; } = "Normal";

    #endregion

    #region Build Options

    [JsonProperty("CompactOS")]
    public bool CompactOS { get; set; } = true;

    [JsonProperty("Optimize")]
    public bool Optimize { get; set; } = true;

    [JsonProperty("CreateCaptureMedia")]
    public bool CreateCaptureMedia { get; set; } = true;

    [JsonProperty("CreateDeploymentMedia")]
    public bool CreateDeploymentMedia { get; set; } = true;

    [JsonProperty("UpdateADK")]
    public bool UpdateADK { get; set; } = true;

    #endregion

    #region USB/Deployment

    [JsonProperty("BuildUSBDrive")]
    public bool BuildUSBDrive { get; set; }

    [JsonProperty("MaxUSBDrives")]
    public int MaxUSBDrives { get; set; } = 5;

    [JsonProperty("AllowExternalHardDiskMedia")]
    public bool AllowExternalHardDiskMedia { get; set; }

    [JsonProperty("PromptExternalHardDiskMedia")]
    public bool PromptExternalHardDiskMedia { get; set; } = true;

    [JsonProperty("CopyAutopilot")]
    public bool CopyAutopilot { get; set; }

    [JsonProperty("CopyUnattend")]
    public bool CopyUnattend { get; set; }

    [JsonProperty("CopyPPKG")]
    public bool CopyPPKG { get; set; }

    [JsonProperty("CopyAdditionalFFUFiles")]
    public bool CopyAdditionalFFUFiles { get; set; }

    [JsonProperty("AdditionalFFUFiles")]
    public List<string>? AdditionalFFUFiles { get; set; }

    [JsonProperty("USBDriveList")]
    public Dictionary<string, string>? USBDriveList { get; set; }

    [JsonProperty("RemoveFFU")]
    public bool RemoveFFU { get; set; }

    #endregion

    #region Cleanup

    [JsonProperty("CleanupAppsISO")]
    public bool CleanupAppsISO { get; set; } = true;

    [JsonProperty("CleanupCaptureISO")]
    public bool CleanupCaptureISO { get; set; } = true;

    [JsonProperty("CleanupCaptureVM")]
    public bool CleanupCaptureVM { get; set; } = true;

    [JsonProperty("CleanupDeployISO")]
    public bool CleanupDeployISO { get; set; } = true;

    [JsonProperty("CleanupDrivers")]
    public bool CleanupDrivers { get; set; }

    [JsonProperty("CleanupCurrentRunDownloads")]
    public bool CleanupCurrentRunDownloads { get; set; }

    [JsonProperty("RemoveApps")]
    public bool RemoveApps { get; set; }

    [JsonProperty("RemoveUpdates")]
    public bool RemoveUpdates { get; set; }

    #endregion

    #region Network

    [JsonProperty("Headers")]
    public Dictionary<string, string>? Headers { get; set; }

    [JsonProperty("UserAgent")]
    public string UserAgent { get; set; } = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0";

    [JsonProperty("AllowVHDXCaching")]
    public bool AllowVHDXCaching { get; set; }

    #endregion

    [JsonExtensionData]
    public Dictionary<string, object?>? AdditionalData { get; set; }

    public static BuildConfiguration CreateDefaults() => new();
}

public class VMwareSettingsModel
{
    [JsonProperty("NetworkType")]
    public string NetworkType { get; set; } = "nat";

    [JsonProperty("NicType")]
    public string NicType { get; set; } = "e1000e";
}
