using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using FFUBuilder.App.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace FFUBuilder.Tests.ViewModels;

public class DashboardViewModelTests
{
    private static Mock<IPreflightService> CreateMockService(params PreflightCheck[] checks)
    {
        var mock = new Mock<IPreflightService>();
        mock.Setup(s => s.RunAllChecksAsync(It.IsAny<IProgress<PreflightCheck>>(), It.IsAny<CancellationToken>()))
            .Callback<IProgress<PreflightCheck>?, CancellationToken>((progress, _) =>
            {
                foreach (var c in checks)
                    progress?.Report(c);
            })
            .ReturnsAsync(checks.ToList().AsReadOnly());
        return mock;
    }

    [Fact]
    public void Constructor_InitializesEmpty()
    {
        var mock = new Mock<IPreflightService>();
        var vm = new DashboardViewModel(mock.Object);

        vm.Checks.Should().BeEmpty();
        vm.IsRunning.Should().BeFalse();
        vm.SummaryText.Should().Contain("Refresh");
    }

    [Fact]
    public async Task RunAllChecks_PopulatesChecks()
    {
        var checks = new[]
        {
            new PreflightCheck { Name = "Administrator", DisplayName = "Admin", Status = CheckStatus.Passed, IsRepairable = false },
            new PreflightCheck { Name = "Network", DisplayName = "Network", Status = CheckStatus.Passed, IsRepairable = true, RepairFunction = "Repair-FFUNetwork" }
        };
        var mock = CreateMockService(checks);
        var vm = new DashboardViewModel(mock.Object);

        await vm.RunAllChecksCommand.ExecuteAsync(null);

        vm.Checks.Should().HaveCount(2);
        vm.PassedCount.Should().Be(2);
        vm.FailedCount.Should().Be(0);
    }

    [Fact]
    public async Task RunAllChecks_CountsFailures()
    {
        var checks = new[]
        {
            new PreflightCheck { Name = "Admin", DisplayName = "Admin", Status = CheckStatus.Passed, IsRepairable = false },
            new PreflightCheck { Name = "WimMount", DisplayName = "WIM", Status = CheckStatus.Failed, Severity = "Critical", IsRepairable = true, RepairFunction = "Repair-FFUWimMount" }
        };
        var mock = CreateMockService(checks);
        var vm = new DashboardViewModel(mock.Object);

        await vm.RunAllChecksCommand.ExecuteAsync(null);

        vm.FailedCount.Should().Be(1);
        vm.HasCriticalFailures.Should().BeTrue();
        vm.SummaryText.Should().Contain("failed");
    }

    [Fact]
    public void CategoryMap_ContainsExpectedEntries()
    {
        PreflightCheck.CategoryMap.Should().ContainKey("Administrator");
        PreflightCheck.CategoryMap["Administrator"].Should().Be(CheckCategory.System);
        PreflightCheck.CategoryMap["WimMount"].Should().Be(CheckCategory.BuildTools);
        PreflightCheck.CategoryMap["Network"].Should().Be(CheckCategory.Network);
        PreflightCheck.CategoryMap["AntivirusExclusions"].Should().Be(CheckCategory.Optimization);
    }

    [Fact]
    public void FriendlyNames_ContainsExpectedEntries()
    {
        PreflightCheck.FriendlyNames["HyperV"].Should().Be("Hyper-V");
        PreflightCheck.FriendlyNames["ADK"].Should().Be("Windows ADK");
        PreflightCheck.FriendlyNames["DISMState"].Should().Be("DISM Service State");
    }

    [Fact]
    public void FromName_CreatesCorrectCheck()
    {
        var check = PreflightCheck.FromName("WimMount");

        check.Name.Should().Be("WimMount");
        check.DisplayName.Should().Be("WIM Mount Service");
        check.Category.Should().Be(CheckCategory.BuildTools);
        check.IsRepairable.Should().BeTrue();
        check.RepairFunction.Should().Be("Repair-FFUWimMount");
        check.Status.Should().Be(CheckStatus.Pending);
    }

    [Fact]
    public void SafeRepairMap_ContainsFourEntries()
    {
        PreflightCheck.SafeRepairMap.Should().HaveCount(4);
        PreflightCheck.SafeRepairMap.Should().ContainKey("WimMount");
        PreflightCheck.SafeRepairMap.Should().ContainKey("DISMState");
        PreflightCheck.SafeRepairMap.Should().ContainKey("DISMCleanup");
        PreflightCheck.SafeRepairMap.Should().ContainKey("Network");
    }
}
