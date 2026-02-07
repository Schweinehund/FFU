using FFUBuilder.App.Services.Interfaces;
using FFUBuilder.App.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace FFUBuilder.Tests.ViewModels;

public class MainViewModelTests
{
    [Fact]
    public void Constructor_SetsDefaultTitle()
    {
        var mockPs = new Mock<IPowerShellService>();
        var vm = new MainViewModel(mockPs.Object);

        vm.Title.Should().Be("FFU Builder");
        vm.StatusText.Should().Be("Initializing...");
    }

    [Fact]
    public void UpdateStatus_WhenInitialized_ShowsModuleCount()
    {
        var mockPs = new Mock<IPowerShellService>();
        mockPs.Setup(p => p.IsInitialized).Returns(true);
        mockPs.Setup(p => p.LoadedModules).Returns(new List<string> { "FFU.Core", "FFU.Constants" }.AsReadOnly());

        var vm = new MainViewModel(mockPs.Object);
        vm.UpdateStatus();

        vm.StatusText.Should().Contain("2 modules loaded");
        vm.Title.Should().Contain("v2.0.0");
    }

    [Fact]
    public void UpdateStatus_WhenNotInitialized_ShowsWarning()
    {
        var mockPs = new Mock<IPowerShellService>();
        mockPs.Setup(p => p.IsInitialized).Returns(false);

        var vm = new MainViewModel(mockPs.Object);
        vm.UpdateStatus();

        vm.StatusText.Should().Contain("not loaded");
    }
}
