using Newtonsoft.Json;

namespace FFUBuilder.App.Models;

public class BuildConfiguration
{
    [JsonProperty("WindowsRelease")]
    public string WindowsRelease { get; set; } = "24H2";

    [JsonProperty("WindowsSKU")]
    public string WindowsSKU { get; set; } = "Pro";

    [JsonProperty("VMName")]
    public string VMName { get; set; } = "FFU_Build_VM";

    [JsonProperty("Memory")]
    public long Memory { get; set; } = 4294967296; // 4GB

    [JsonProperty("Disksize")]
    public long Disksize { get; set; } = 53687091200; // 50GB

    [JsonProperty("Processors")]
    public int Processors { get; set; } = 4;

    [JsonProperty("FFUDevelopmentPath")]
    public string? FFUDevelopmentPath { get; set; }

    [JsonProperty("FFUCaptureLocation")]
    public string? FFUCaptureLocation { get; set; }

    [JsonProperty("InstallApps")]
    public bool InstallApps { get; set; }

    [JsonProperty("InstallOffice")]
    public bool InstallOffice { get; set; }

    [JsonProperty("InstallDrivers")]
    public bool InstallDrivers { get; set; }

    [JsonProperty("ApplyDrivers")]
    public bool ApplyDrivers { get; set; }

    [JsonProperty("OEM")]
    public string? OEM { get; set; }

    [JsonProperty("Model")]
    public string? Model { get; set; }

    [JsonProperty("ConfigFile")]
    public string? ConfigFile { get; set; }
}
