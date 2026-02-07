using FFUBuilder.App.Models;
using FluentAssertions;
using Newtonsoft.Json;
using Xunit;

namespace FFUBuilder.Tests.Models;

public class BuildConfigurationTests
{
    [Fact]
    public void Defaults_MatchSchemaDefaults()
    {
        var config = new BuildConfiguration();

        config.WindowsRelease.Should().Be(11);
        config.WindowsSKU.Should().Be("Pro");
        config.WindowsVersion.Should().Be("24h2");
        config.WindowsArch.Should().Be("x64");
        config.WindowsLang.Should().Be("en-us");
        config.MediaType.Should().Be("consumer");
        config.VMName.Should().Be("YOURPC");
        config.Memory.Should().Be(4294967296L);
        config.Disksize.Should().Be(32212254720L);
        config.Processors.Should().Be(4);
        config.LogicalSectorSizeBytes.Should().Be(512);
        config.VMShutdownTimeoutMinutes.Should().Be(60);
        config.FFUFileLockWaitSeconds.Should().Be(120);
        config.HypervisorType.Should().Be("HyperV");
        config.FFUPrefix.Should().Be("_FFU");
        config.ShareName.Should().Be("FFUCaptureShare");
        config.Username.Should().Be("ffu_user");
        config.InstallApps.Should().BeTrue();
        config.InstallOffice.Should().BeTrue();
        config.InstallDrivers.Should().BeTrue();
        config.UpdateLatestCU.Should().BeTrue();
        config.CompactOS.Should().BeTrue();
        config.Optimize.Should().BeTrue();
        config.MaxUSBDrives.Should().Be(5);
        config.BitsPriority.Should().Be("Normal");
        config.CleanupAppsISO.Should().BeTrue();
        config.CleanupCaptureVM.Should().BeTrue();
    }

    [Fact]
    public void Serialize_ProducesCompatibleJsonKeys()
    {
        var config = new BuildConfiguration();
        var json = JsonConvert.SerializeObject(config);

        json.Should().Contain("\"Memory\"");
        json.Should().Contain("\"Disksize\"");
        json.Should().Contain("\"WindowsRelease\"");
        json.Should().Contain("\"InstallApps\"");
        json.Should().Contain("\"WindowsSKU\"");
        json.Should().Contain("\"Processors\"");
        json.Should().Contain("\"VMName\"");
        json.Should().Contain("\"HypervisorType\"");
        json.Should().Contain("\"BitsPriority\"");
        json.Should().Contain("\"CompactOS\"");
    }

    [Fact]
    public void Deserialize_PowerShellConfigJson()
    {
        var json = """
        {
            "WindowsRelease": 11,
            "WindowsSKU": "Enterprise",
            "WindowsVersion": "24h2",
            "Memory": 8589934592,
            "Disksize": 53687091200,
            "Processors": 8,
            "VMName": "TestPC",
            "InstallApps": true,
            "InstallOffice": false,
            "InstallDrivers": true,
            "Make": "Dell",
            "Model": "Latitude 7490",
            "UpdateLatestCU": true,
            "CompactOS": true,
            "FFUPrefix": "_MyFFU",
            "HypervisorType": "VMware",
            "BitsPriority": "High"
        }
        """;

        var config = JsonConvert.DeserializeObject<BuildConfiguration>(json)!;

        config.WindowsRelease.Should().Be(11);
        config.WindowsSKU.Should().Be("Enterprise");
        config.Memory.Should().Be(8589934592L);
        config.Disksize.Should().Be(53687091200L);
        config.Processors.Should().Be(8);
        config.VMName.Should().Be("TestPC");
        config.InstallApps.Should().BeTrue();
        config.InstallOffice.Should().BeFalse();
        config.Make.Should().Be("Dell");
        config.Model.Should().Be("Latitude 7490");
        config.HypervisorType.Should().Be("VMware");
        config.FFUPrefix.Should().Be("_MyFFU");
        config.BitsPriority.Should().Be("High");
    }

    [Fact]
    public void Deserialize_HandlesExtraProperties()
    {
        var json = """
        {
            "WindowsRelease": 11,
            "SomeFutureProperty": "hello",
            "AnotherNew": 42
        }
        """;

        var config = JsonConvert.DeserializeObject<BuildConfiguration>(json)!;

        config.WindowsRelease.Should().Be(11);
        config.AdditionalData.Should().NotBeNull();
        config.AdditionalData.Should().ContainKey("SomeFutureProperty");
    }

    [Fact]
    public void Deserialize_HandlesMissingProperties()
    {
        var json = """
        {
            "VMName": "CustomPC"
        }
        """;

        var config = JsonConvert.DeserializeObject<BuildConfiguration>(json)!;

        config.VMName.Should().Be("CustomPC");
        // Missing properties use class defaults
        config.WindowsRelease.Should().Be(11);
        config.Memory.Should().Be(4294967296L);
        config.Processors.Should().Be(4);
        config.InstallApps.Should().BeTrue();
    }

    [Fact]
    public void MemoryAndDisksize_StoredAsBytes()
    {
        var config = new BuildConfiguration
        {
            Memory = 4294967296L,   // 4GB
            Disksize = 32212254720L // 30GB
        };

        var json = JsonConvert.SerializeObject(config);

        json.Should().Contain("4294967296");
        json.Should().Contain("32212254720");
    }

    [Fact]
    public void WindowsRelease_SerializesAsInteger()
    {
        var config = new BuildConfiguration { WindowsRelease = 11 };
        var json = JsonConvert.SerializeObject(config);

        // Should be integer 11, not string "11"
        json.Should().Contain("\"WindowsRelease\":11");
        json.Should().NotContain("\"WindowsRelease\":\"11\"");
    }

    [Fact]
    public void CreateDefaults_ReturnsNewInstance()
    {
        var config1 = BuildConfiguration.CreateDefaults();
        var config2 = BuildConfiguration.CreateDefaults();

        config1.Should().NotBeSameAs(config2);
        config1.WindowsRelease.Should().Be(11);
        config1.Memory.Should().Be(4294967296L);
    }
}
