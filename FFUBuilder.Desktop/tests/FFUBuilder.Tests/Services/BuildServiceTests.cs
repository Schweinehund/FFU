using System.Management.Automation;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services;
using FFUBuilder.App.Services.Interfaces;
using FluentAssertions;
using Moq;
using Xunit;

namespace FFUBuilder.Tests.Services;

public class BuildServiceTests
{
    private static Mock<IPowerShellService> CreateMockPsService()
    {
        var mock = new Mock<IPowerShellService>();
        mock.Setup(s => s.IsInitialized).Returns(true);
        return mock;
    }

    private static Mock<IConfigurationService> CreateMockConfigService()
    {
        var mock = new Mock<IConfigurationService>();
        mock.Setup(s => s.SaveAsync(It.IsAny<string>(), It.IsAny<BuildConfiguration>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        return mock;
    }

    [Fact]
    public void InitialState_IsIdle()
    {
        var service = new BuildService(CreateMockPsService().Object, CreateMockConfigService().Object);
        service.CurrentState.Should().Be(BuildState.Idle);
    }

    [Fact]
    public async Task StartBuild_ChangesStateToRunning()
    {
        var psMock = CreateMockPsService();
        psMock.Setup(s => s.InvokeScriptWithStreamingAsync(
                It.IsAny<string>(), It.IsAny<IDictionary<string, object>>(),
                It.IsAny<Action<ProgressRecord>>(), It.IsAny<Action<string>>(),
                It.IsAny<Action<string>>(), It.IsAny<Action<ErrorRecord>>(),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var service = new BuildService(psMock.Object, CreateMockConfigService().Object);
        var states = new List<BuildState>();
        service.StateChanged += (_, state) => states.Add(state);

        var config = new BuildConfiguration { FFUDevelopmentPath = @"C:\FFUDevelopment" };

        // Script won't exist, but the mock will handle invocation
        await service.StartBuildAsync(config);

        states.Should().Contain(BuildState.Running);
    }

    [Fact]
    public async Task StartBuild_CompletesSuccessfully()
    {
        var psMock = CreateMockPsService();
        psMock.Setup(s => s.InvokeScriptWithStreamingAsync(
                It.IsAny<string>(), It.IsAny<IDictionary<string, object>>(),
                It.IsAny<Action<ProgressRecord>>(), It.IsAny<Action<string>>(),
                It.IsAny<Action<string>>(), It.IsAny<Action<ErrorRecord>>(),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var service = new BuildService(psMock.Object, CreateMockConfigService().Object);
        var config = new BuildConfiguration { FFUDevelopmentPath = @"C:\FFUDevelopment" };

        await service.StartBuildAsync(config);

        service.CurrentState.Should().Be(BuildState.Completed);
    }

    [Fact]
    public async Task StartBuild_WhenCancelled_SetsStateToCancelled()
    {
        var psMock = CreateMockPsService();
        psMock.Setup(s => s.InvokeScriptWithStreamingAsync(
                It.IsAny<string>(), It.IsAny<IDictionary<string, object>>(),
                It.IsAny<Action<ProgressRecord>>(), It.IsAny<Action<string>>(),
                It.IsAny<Action<string>>(), It.IsAny<Action<ErrorRecord>>(),
                It.IsAny<CancellationToken>()))
            .ThrowsAsync(new OperationCanceledException());

        var service = new BuildService(psMock.Object, CreateMockConfigService().Object);
        var config = new BuildConfiguration { FFUDevelopmentPath = @"C:\FFUDevelopment" };

        await service.StartBuildAsync(config);

        service.CurrentState.Should().Be(BuildState.Cancelled);
    }

    [Fact]
    public async Task StartBuild_WhenFails_SetsStateToFailed()
    {
        var psMock = CreateMockPsService();
        psMock.Setup(s => s.InvokeScriptWithStreamingAsync(
                It.IsAny<string>(), It.IsAny<IDictionary<string, object>>(),
                It.IsAny<Action<ProgressRecord>>(), It.IsAny<Action<string>>(),
                It.IsAny<Action<string>>(), It.IsAny<Action<ErrorRecord>>(),
                It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Script failed"));

        var service = new BuildService(psMock.Object, CreateMockConfigService().Object);
        var config = new BuildConfiguration { FFUDevelopmentPath = @"C:\FFUDevelopment" };

        await service.StartBuildAsync(config);

        service.CurrentState.Should().Be(BuildState.Failed);
    }

    [Fact]
    public async Task StartBuild_ReportsLogEntries()
    {
        var psMock = CreateMockPsService();
        psMock.Setup(s => s.InvokeScriptWithStreamingAsync(
                It.IsAny<string>(), It.IsAny<IDictionary<string, object>>(),
                It.IsAny<Action<ProgressRecord>>(), It.IsAny<Action<string>>(),
                It.IsAny<Action<string>>(), It.IsAny<Action<ErrorRecord>>(),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var service = new BuildService(psMock.Object, CreateMockConfigService().Object);
        var config = new BuildConfiguration { FFUDevelopmentPath = @"C:\FFUDevelopment" };

        var logs = new List<LogEntry>();
        var logProgress = new Progress<LogEntry>(entry => logs.Add(entry));

        await service.StartBuildAsync(config, logProgress: logProgress);

        // Should have at least the "Build started" and "Build completed" messages
        logs.Should().HaveCountGreaterOrEqualTo(2);
        logs.Should().Contain(e => e.Message.Contains("started"));
        logs.Should().Contain(e => e.Message.Contains("completed"));
    }

    [Fact]
    public void RequestCancellation_WhenIdle_DoesNothing()
    {
        var service = new BuildService(CreateMockPsService().Object, CreateMockConfigService().Object);
        service.RequestCancellation();
        service.CurrentState.Should().Be(BuildState.Idle);
    }
}
