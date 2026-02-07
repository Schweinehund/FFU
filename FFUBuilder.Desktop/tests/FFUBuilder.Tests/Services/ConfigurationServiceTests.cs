using System.IO;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services;
using FluentAssertions;
using Xunit;

namespace FFUBuilder.Tests.Services;

public class ConfigurationServiceTests : IDisposable
{
    private readonly string _tempDir;

    public ConfigurationServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"FFUBuilderTests_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    [Fact]
    public async Task LoadAsync_ReturnsDefaultsWhenFileNotFound()
    {
        var service = new ConfigurationService();
        var config = await service.LoadAsync(Path.Combine(_tempDir, "nonexistent.json"));

        config.Should().NotBeNull();
        config.WindowsRelease.Should().Be("24H2");
        config.VMName.Should().Be("FFU_Build_VM");
    }

    [Fact]
    public async Task SaveAndLoad_RoundTrips()
    {
        var service = new ConfigurationService();
        var configPath = Path.Combine(_tempDir, "config.json");

        var original = new BuildConfiguration
        {
            WindowsRelease = "23H2",
            WindowsSKU = "Enterprise",
            VMName = "Test_VM",
            Processors = 8,
            InstallApps = true
        };

        await service.SaveAsync(configPath, original);
        var loaded = await service.LoadAsync(configPath);

        loaded.WindowsRelease.Should().Be("23H2");
        loaded.WindowsSKU.Should().Be("Enterprise");
        loaded.VMName.Should().Be("Test_VM");
        loaded.Processors.Should().Be(8);
        loaded.InstallApps.Should().BeTrue();
    }

    [Fact]
    public async Task SaveAsync_CreatesDirectory()
    {
        var service = new ConfigurationService();
        var nestedPath = Path.Combine(_tempDir, "sub", "dir", "config.json");

        await service.SaveAsync(nestedPath, new BuildConfiguration());

        File.Exists(nestedPath).Should().BeTrue();
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, recursive: true); } catch { /* cleanup */ }
    }
}
