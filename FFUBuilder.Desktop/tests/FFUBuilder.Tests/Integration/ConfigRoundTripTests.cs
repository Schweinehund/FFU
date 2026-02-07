using System.IO;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services;
using FluentAssertions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace FFUBuilder.Tests.Integration;

public class ConfigRoundTripTests : IDisposable
{
    private readonly string _tempDir;

    public ConfigRoundTripTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"FFUBuilderTests_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    [Fact]
    public async Task CSharp_Save_Produces_PowerShell_Compatible_Json()
    {
        var service = new ConfigurationService();
        var configPath = Path.Combine(_tempDir, "config.json");

        var config = new BuildConfiguration
        {
            WindowsRelease = 11,
            WindowsSKU = "Enterprise",
            WindowsVersion = "24h2",
            Memory = 8589934592L, // 8GB
            Disksize = 53687091200L, // 50GB
            Processors = 8,
            VMName = "TestPC",
            InstallApps = true,
            InstallOffice = false,
            InstallDrivers = true,
            Make = "Dell",
            Model = "Latitude 7490",
            HypervisorType = "HyperV",
            CompactOS = true,
            BitsPriority = "High"
        };

        await service.SaveAsync(configPath, config);

        // Verify the JSON has correct key names and types
        var json = await File.ReadAllTextAsync(configPath);
        var obj = JObject.Parse(json);

        // WindowsRelease should be an integer, not a string
        obj["WindowsRelease"]!.Type.Should().Be(JTokenType.Integer);
        obj["WindowsRelease"]!.Value<int>().Should().Be(11);

        // Memory and Disksize should be integers (bytes)
        obj["Memory"]!.Type.Should().Be(JTokenType.Integer);
        obj["Memory"]!.Value<long>().Should().Be(8589934592L);

        obj["Disksize"]!.Type.Should().Be(JTokenType.Integer);
        obj["Disksize"]!.Value<long>().Should().Be(53687091200L);

        // Booleans should be JSON booleans
        obj["InstallApps"]!.Type.Should().Be(JTokenType.Boolean);
        obj["InstallApps"]!.Value<bool>().Should().BeTrue();

        obj["InstallOffice"]!.Type.Should().Be(JTokenType.Boolean);
        obj["InstallOffice"]!.Value<bool>().Should().BeFalse();

        // Strings should be strings
        obj["WindowsSKU"]!.Type.Should().Be(JTokenType.String);
        obj["Make"]!.Value<string>().Should().Be("Dell");
    }

    [Fact]
    public async Task PowerShell_Format_Json_Loads_Into_CSharp()
    {
        // Simulate a config.json saved by the PowerShell UI
        var psJson = """
        {
            "WindowsRelease": 11,
            "WindowsSKU": "Pro",
            "WindowsVersion": "24h2",
            "WindowsArch": "x64",
            "WindowsLang": "en-us",
            "MediaType": "consumer",
            "VMName": "YOURPC",
            "Memory": 4294967296,
            "Disksize": 32212254720,
            "Processors": 4,
            "InstallApps": true,
            "InstallOffice": true,
            "InstallDrivers": true,
            "Make": "",
            "Model": "",
            "CompactOS": true,
            "Optimize": true,
            "UpdateLatestCU": true,
            "UpdateLatestNet": true,
            "UpdateLatestDefender": true,
            "UpdateEdge": true,
            "UpdateOneDrive": true,
            "HypervisorType": "HyperV",
            "BitsPriority": "Normal",
            "CleanupAppsISO": true,
            "CleanupCaptureISO": true,
            "CleanupDeployISO": true,
            "FFUPrefix": "_FFU",
            "ShareName": "FFUCaptureShare",
            "Username": "ffu_user"
        }
        """;

        var configPath = Path.Combine(_tempDir, "ps_config.json");
        await File.WriteAllTextAsync(configPath, psJson);

        var service = new ConfigurationService();
        var config = await service.LoadAsync(configPath);

        config.WindowsRelease.Should().Be(11);
        config.WindowsSKU.Should().Be("Pro");
        config.Memory.Should().Be(4294967296L);
        config.Disksize.Should().Be(32212254720L);
        config.Processors.Should().Be(4);
        config.InstallApps.Should().BeTrue();
        config.HypervisorType.Should().Be("HyperV");
        config.BitsPriority.Should().Be("Normal");
        config.FFUPrefix.Should().Be("_FFU");
    }

    [Fact]
    public async Task Full_RoundTrip_CSharp_Save_Then_Load()
    {
        var service = new ConfigurationService();
        var configPath = Path.Combine(_tempDir, "roundtrip.json");

        var original = BuildConfiguration.CreateDefaults();
        original.WindowsRelease = 10;
        original.WindowsSKU = "Enterprise";
        original.Memory = 17179869184L; // 16GB
        original.Disksize = 107374182400L; // 100GB
        original.Processors = 16;
        original.Make = "HP";
        original.Model = "EliteBook 840 G5";
        original.HypervisorType = "VMware";
        original.BitsPriority = "Foreground";
        original.InstallApps = false;

        await service.SaveAsync(configPath, original);
        var loaded = await service.LoadAsync(configPath);

        loaded.WindowsRelease.Should().Be(10);
        loaded.WindowsSKU.Should().Be("Enterprise");
        loaded.Memory.Should().Be(17179869184L);
        loaded.Disksize.Should().Be(107374182400L);
        loaded.Processors.Should().Be(16);
        loaded.Make.Should().Be("HP");
        loaded.Model.Should().Be("EliteBook 840 G5");
        loaded.HypervisorType.Should().Be("VMware");
        loaded.BitsPriority.Should().Be("Foreground");
        loaded.InstallApps.Should().BeFalse();
    }

    [Fact]
    public async Task NullValues_OmittedInJson()
    {
        var service = new ConfigurationService();
        var configPath = Path.Combine(_tempDir, "null_test.json");

        var config = new BuildConfiguration();
        // These should be null by default
        config.AppsScriptVariables.Should().BeNull();
        config.AdditionalFFUFiles.Should().BeNull();

        await service.SaveAsync(configPath, config);

        var json = await File.ReadAllTextAsync(configPath);
        // NullValueHandling.Ignore means null values are omitted
        json.Should().NotContain("\"AppsScriptVariables\"");
        json.Should().NotContain("\"AdditionalFFUFiles\"");
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, recursive: true); } catch { /* cleanup */ }
    }
}
