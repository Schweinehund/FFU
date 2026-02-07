namespace FFUBuilder.App.Models;

public enum CheckStatus
{
    Pending,
    Running,
    Passed,
    Warning,
    Failed,
    Skipped
}

public enum CheckCategory
{
    System,
    Hypervisor,
    BuildTools,
    Network,
    Optimization
}

public class PreflightCheck
{
    public required string Name { get; init; }
    public required string DisplayName { get; init; }
    public CheckCategory Category { get; init; }
    public CheckStatus Status { get; set; }
    public string? Severity { get; set; }
    public string? Message { get; set; }
    public string? Remediation { get; set; }
    public bool IsRepairable { get; init; }
    public string? RepairFunction { get; init; }
    public TimeSpan Duration { get; set; }

    // Static mapping from check name to category (matches FFUUI.Core.Dashboard.psm1)
    public static readonly Dictionary<string, CheckCategory> CategoryMap = new()
    {
        ["Administrator"] = CheckCategory.System,
        ["PowerShellVersion"] = CheckCategory.System,
        ["VMResources"] = CheckCategory.System,
        ["ScratchSpace"] = CheckCategory.System,
        ["HyperV"] = CheckCategory.Hypervisor,
        ["VmxToolkit"] = CheckCategory.Hypervisor,
        ["VMwareDrivers"] = CheckCategory.Hypervisor,
        ["VMwareBridgeConfig"] = CheckCategory.Hypervisor,
        ["HyperVSwitchConflict"] = CheckCategory.Hypervisor,
        ["ADK"] = CheckCategory.BuildTools,
        ["WimMount"] = CheckCategory.BuildTools,
        ["DiskSpace"] = CheckCategory.BuildTools,
        ["DISMState"] = CheckCategory.BuildTools,
        ["DISMCleanup"] = CheckCategory.BuildTools,
        ["AppsISODiskSpace"] = CheckCategory.BuildTools,
        ["CaptureDiskSpace"] = CheckCategory.BuildTools,
        ["Network"] = CheckCategory.Network,
        ["HostIPAddress"] = CheckCategory.Network,
        ["AntivirusExclusions"] = CheckCategory.Optimization,
        ["Configuration"] = CheckCategory.Optimization
    };

    // Friendly display names (matches FFUUI.Core.Dashboard.psm1)
    public static readonly Dictionary<string, string> FriendlyNames = new()
    {
        ["Administrator"] = "Administrator Privileges",
        ["PowerShellVersion"] = "PowerShell Version",
        ["VMResources"] = "VM Resources",
        ["ScratchSpace"] = "Scratch Space",
        ["HyperV"] = "Hyper-V",
        ["VmxToolkit"] = "VMX Toolkit",
        ["VMwareDrivers"] = "VMware Drivers",
        ["VMwareBridgeConfig"] = "VMware Bridge Configuration",
        ["HyperVSwitchConflict"] = "Hyper-V Switch Conflict",
        ["ADK"] = "Windows ADK",
        ["WimMount"] = "WIM Mount Service",
        ["DiskSpace"] = "Disk Space",
        ["DISMState"] = "DISM Service State",
        ["DISMCleanup"] = "DISM Cleanup",
        ["AppsISODiskSpace"] = "Apps ISO Disk Space",
        ["CaptureDiskSpace"] = "Capture Disk Space",
        ["Network"] = "Network Connectivity",
        ["HostIPAddress"] = "Host IP Address",
        ["AntivirusExclusions"] = "Antivirus Exclusions",
        ["Configuration"] = "Configuration File"
    };

    // Checks that have safe one-click repair functions
    public static readonly Dictionary<string, string> SafeRepairMap = new()
    {
        ["WimMount"] = "Repair-FFUWimMount",
        ["DISMState"] = "Repair-FFUDismState",
        ["DISMCleanup"] = "Invoke-FFUDISMCleanup",
        ["Network"] = "Repair-FFUNetwork"
    };

    public static PreflightCheck FromName(string checkName)
    {
        return new PreflightCheck
        {
            Name = checkName,
            DisplayName = FriendlyNames.GetValueOrDefault(checkName, checkName),
            Category = CategoryMap.GetValueOrDefault(checkName, CheckCategory.System),
            Status = CheckStatus.Pending,
            IsRepairable = SafeRepairMap.ContainsKey(checkName),
            RepairFunction = SafeRepairMap.GetValueOrDefault(checkName)
        };
    }
}
