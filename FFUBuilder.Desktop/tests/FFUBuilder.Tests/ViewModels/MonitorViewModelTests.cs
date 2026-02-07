using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using FFUBuilder.App.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace FFUBuilder.Tests.ViewModels;

public class MonitorViewModelTests
{
    private static Mock<IBuildService> CreateMockBuildService()
    {
        var mock = new Mock<IBuildService>();
        mock.Setup(s => s.CurrentState).Returns(BuildState.Idle);
        return mock;
    }

    private static Mock<IConfigurationService> CreateMockConfigService()
    {
        var mock = new Mock<IConfigurationService>();
        return mock;
    }

    [Fact]
    public void Constructor_InitializesIdle()
    {
        var vm = new MonitorViewModel(CreateMockBuildService().Object, CreateMockConfigService().Object);

        vm.BuildState.Should().Be(BuildState.Idle);
        vm.ProgressPercent.Should().Be(0);
        vm.LogEntries.Should().BeEmpty();
        vm.CanStartBuild.Should().BeTrue();
        vm.CanCancel.Should().BeFalse();
    }

    [Fact]
    public void BuildState_UpdatesStatusMessage()
    {
        var buildMock = CreateMockBuildService();
        var vm = new MonitorViewModel(buildMock.Object, CreateMockConfigService().Object);

        vm.BuildState = BuildState.Running;
        vm.StatusMessage.Should().Contain("progress");

        vm.BuildState = BuildState.Completed;
        vm.StatusMessage.Should().Contain("completed");

        vm.BuildState = BuildState.Failed;
        vm.StatusMessage.Should().Contain("failed");

        vm.BuildState = BuildState.Cancelled;
        vm.StatusMessage.Should().Contain("cancelled");
    }

    [Fact]
    public void CanStartBuild_FalseWhenRunning()
    {
        var vm = new MonitorViewModel(CreateMockBuildService().Object, CreateMockConfigService().Object);

        vm.BuildState = BuildState.Running;
        vm.CanStartBuild.Should().BeFalse();

        vm.BuildState = BuildState.Cancelling;
        vm.CanStartBuild.Should().BeFalse();
    }

    [Fact]
    public void CanStartBuild_TrueAfterCompletion()
    {
        var vm = new MonitorViewModel(CreateMockBuildService().Object, CreateMockConfigService().Object);

        vm.BuildState = BuildState.Completed;
        vm.CanStartBuild.Should().BeTrue();

        vm.BuildState = BuildState.Failed;
        vm.CanStartBuild.Should().BeTrue();

        vm.BuildState = BuildState.Cancelled;
        vm.CanStartBuild.Should().BeTrue();
    }

    [Fact]
    public void CanCancel_TrueOnlyWhenRunning()
    {
        var vm = new MonitorViewModel(CreateMockBuildService().Object, CreateMockConfigService().Object);

        vm.BuildState = BuildState.Idle;
        vm.CanCancel.Should().BeFalse();

        vm.BuildState = BuildState.Running;
        vm.CanCancel.Should().BeTrue();

        vm.BuildState = BuildState.Completed;
        vm.CanCancel.Should().BeFalse();
    }

    [Fact]
    public void ClearLog_RemovesAllEntries()
    {
        var vm = new MonitorViewModel(CreateMockBuildService().Object, CreateMockConfigService().Object);

        vm.LogEntries.Add(new LogEntry { Level = LogLevel.Information, Message = "Test 1" });
        vm.LogEntries.Add(new LogEntry { Level = LogLevel.Warning, Message = "Test 2" });

        vm.LogEntries.Should().HaveCount(2);

        vm.ClearLogCommand.Execute(null);

        vm.LogEntries.Should().BeEmpty();
    }

    [Fact]
    public void IsBuilding_TrueWhenRunningOrCancelling()
    {
        var vm = new MonitorViewModel(CreateMockBuildService().Object, CreateMockConfigService().Object);

        vm.BuildState = BuildState.Idle;
        vm.IsBuilding.Should().BeFalse();

        vm.BuildState = BuildState.Running;
        vm.IsBuilding.Should().BeTrue();

        vm.BuildState = BuildState.Cancelling;
        vm.IsBuilding.Should().BeTrue();

        vm.BuildState = BuildState.Completed;
        vm.IsBuilding.Should().BeFalse();
    }
}
