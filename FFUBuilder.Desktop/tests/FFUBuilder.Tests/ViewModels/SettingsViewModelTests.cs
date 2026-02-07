using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using FFUBuilder.App.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace FFUBuilder.Tests.ViewModels;

public class SettingsViewModelTests
{
    private static Mock<IConfigurationService> CreateMockService()
    {
        var mock = new Mock<IConfigurationService>();
        mock.Setup(s => s.CreateDefaults()).Returns(BuildConfiguration.CreateDefaults);
        mock.Setup(s => s.GetDefaultConfigPath(It.IsAny<string>()))
            .Returns<string>(p => System.IO.Path.Combine(p, "config", "FFUConfig.json"));
        return mock;
    }

    [Fact]
    public void Constructor_InitializesWithDefaults()
    {
        var mock = CreateMockService();
        var vm = new SettingsViewModel(mock.Object);

        vm.Configuration.Should().NotBeNull();
        vm.IsDirty.Should().BeFalse();
        vm.Configuration.WindowsRelease.Should().Be(11);
        vm.Configuration.Memory.Should().Be(4294967296L);
    }

    [Fact]
    public void ResetToDefaults_SetsDefaultConfiguration()
    {
        var mock = CreateMockService();
        var vm = new SettingsViewModel(mock.Object);

        // Modify some values
        vm.Configuration.WindowsRelease = 10;
        vm.Configuration.Processors = 16;

        vm.ResetToDefaultsCommand.Execute(null);

        vm.Configuration.WindowsRelease.Should().Be(11);
        vm.Configuration.Processors.Should().Be(4);
        vm.Configuration.Memory.Should().Be(4294967296L);
    }

    [Fact]
    public void ResetToDefaults_SetsIsDirty()
    {
        var mock = CreateMockService();
        var vm = new SettingsViewModel(mock.Object);

        vm.IsDirty.Should().BeFalse();

        vm.ResetToDefaultsCommand.Execute(null);

        vm.IsDirty.Should().BeTrue();
    }

    [Fact]
    public async Task LoadConfig_ClearsIsDirty()
    {
        var mock = CreateMockService();
        var loadedConfig = new BuildConfiguration { WindowsRelease = 10, VMName = "LoadedVM" };
        mock.Setup(s => s.LoadAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(loadedConfig);

        var vm = new SettingsViewModel(mock.Object);
        vm.ConfigFilePath = @"C:\test\config.json";

        await vm.LoadConfigCommand.ExecuteAsync(null);

        vm.IsDirty.Should().BeFalse();
        vm.Configuration.WindowsRelease.Should().Be(10);
        vm.Configuration.VMName.Should().Be("LoadedVM");
    }

    [Fact]
    public async Task SaveConfig_ClearsIsDirty()
    {
        var mock = CreateMockService();
        mock.Setup(s => s.SaveAsync(It.IsAny<string>(), It.IsAny<BuildConfiguration>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var vm = new SettingsViewModel(mock.Object);
        vm.ConfigFilePath = @"C:\test\config.json";

        // Mark dirty by resetting
        vm.ResetToDefaultsCommand.Execute(null);
        vm.IsDirty.Should().BeTrue();

        await vm.SaveConfigCommand.ExecuteAsync(null);

        vm.IsDirty.Should().BeFalse();
    }

    [Fact]
    public void MemoryGB_ConvertsCorrectly()
    {
        var mock = CreateMockService();
        var vm = new SettingsViewModel(mock.Object);

        // Default is 4GB
        vm.MemoryGB.Should().Be(4.0);

        // Set to 8GB
        vm.MemoryGB = 8.0;
        vm.Configuration.Memory.Should().Be(8589934592L);

        // Set via bytes and read GB
        vm.Configuration.Memory = 17179869184L; // 16GB
        vm.Configuration = vm.Configuration; // trigger change
        vm.MemoryGB.Should().Be(16.0);
    }

    [Fact]
    public void DisksizeGB_ConvertsCorrectly()
    {
        var mock = CreateMockService();
        var vm = new SettingsViewModel(mock.Object);

        // Default is 30GB
        vm.DisksizeGB.Should().Be(30.0);

        // Set to 50GB
        vm.DisksizeGB = 50.0;
        vm.Configuration.Disksize.Should().Be(53687091200L);

        // Set via bytes and read GB
        vm.Configuration.Disksize = 107374182400L; // 100GB
        vm.Configuration = vm.Configuration; // trigger change
        vm.DisksizeGB.Should().Be(100.0);
    }

    [Fact]
    public void Validation_MemoryOutOfRange_HasError()
    {
        var mock = CreateMockService();
        var vm = new SettingsViewModel(mock.Object);

        // Set below minimum (1GB < 2GB minimum)
        vm.MemoryGB = 1.0;
        vm.ValidateAll();

        vm.HasErrors.Should().BeTrue();
        var errors = vm.GetErrors(nameof(vm.MemoryGB)).Cast<string>().ToList();
        errors.Should().Contain(e => e.Contains("2 GB"));
    }

    [Fact]
    public void Validation_ProcessorsOutOfRange_HasError()
    {
        var mock = CreateMockService();
        var vm = new SettingsViewModel(mock.Object);

        vm.Configuration.Processors = 0;
        vm.ValidateAll();

        vm.HasErrors.Should().BeTrue();

        vm.Configuration.Processors = 65;
        vm.ValidateAll();

        vm.HasErrors.Should().BeTrue();
    }

    [Fact]
    public void Validation_ValidConfig_NoErrors()
    {
        var mock = CreateMockService();
        var vm = new SettingsViewModel(mock.Object);

        vm.ValidateAll();

        vm.HasErrors.Should().BeFalse();
    }

    [Fact]
    public void EnumOptions_ContainExpectedValues()
    {
        SettingsViewModel.WindowsSKUOptions.Should().Contain("Pro");
        SettingsViewModel.WindowsSKUOptions.Should().Contain("Enterprise");
        SettingsViewModel.WindowsSKUOptions.Should().Contain("Home");

        SettingsViewModel.MakeOptions.Should().Contain("Dell");
        SettingsViewModel.MakeOptions.Should().Contain("HP");
        SettingsViewModel.MakeOptions.Should().Contain("Lenovo");

        SettingsViewModel.HypervisorTypeOptions.Should().Contain("HyperV");
        SettingsViewModel.HypervisorTypeOptions.Should().Contain("VMware");

        SettingsViewModel.BitsPriorityOptions.Should().Contain("Normal");
        SettingsViewModel.BitsPriorityOptions.Should().Contain("High");

        SettingsViewModel.WindowsReleaseOptions.Should().Contain(10);
        SettingsViewModel.WindowsReleaseOptions.Should().Contain(11);
    }
}
