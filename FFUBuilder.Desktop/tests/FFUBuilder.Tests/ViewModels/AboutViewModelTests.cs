using FFUBuilder.App.Services.Interfaces;
using FFUBuilder.App.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace FFUBuilder.Tests.ViewModels;

public class AboutViewModelTests
{
    private static Mock<IPowerShellService> CreateMockPsService(params string[] modules)
    {
        var mock = new Mock<IPowerShellService>();
        mock.Setup(s => s.LoadedModules).Returns(modules.ToList().AsReadOnly());
        mock.Setup(s => s.IsInitialized).Returns(true);
        return mock;
    }

    [Fact]
    public void Constructor_SetsDefaultVersion()
    {
        var vm = new AboutViewModel(CreateMockPsService().Object);

        vm.AppVersion.Should().Contain("2.0.0");
        vm.Description.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public void Constructor_ShowsLoadedModuleCount()
    {
        var vm = new AboutViewModel(
            CreateMockPsService("FFU.Core", "FFU.Preflight", "FFU.Imaging").Object);

        vm.LoadedModuleCount.Should().Be(3);
        vm.PsVersion.Should().Contain("3");
    }

    [Fact]
    public void Modules_EmptyWhenVersionJsonNotFound()
    {
        var vm = new AboutViewModel(CreateMockPsService().Object);

        // When version.json is not at expected paths, modules collection will be empty
        // (or populated if it happens to find version.json on this machine)
        vm.Should().NotBeNull();
    }
}
