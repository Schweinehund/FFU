using System.Collections.ObjectModel;
using System.Management.Automation;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services;
using FFUBuilder.App.Services.Interfaces;
using FluentAssertions;
using Moq;
using Xunit;

namespace FFUBuilder.Tests.Services;

public class PreflightServiceTests
{
    private static Mock<IPowerShellService> CreateMockPs(string json)
    {
        var mock = new Mock<IPowerShellService>();
        mock.Setup(p => p.IsInitialized).Returns(true);

        var psObj = new PSObject(json);
        var results = new ReadOnlyCollection<PSObject>(new List<PSObject> { psObj });

        mock.Setup(p => p.InvokeAsync(
                It.IsAny<string>(),
                It.IsAny<IDictionary<string, object>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(results);

        return mock;
    }

    [Fact]
    public async Task RunCheckAsync_ParsesPassedResult()
    {
        var json = """{"CheckName":"Administrator","Status":"Passed","Severity":"Critical","Message":"Running as Administrator","Remediation":"","DurationMs":5}""";
        var mockPs = CreateMockPs(json);
        var service = new PreflightService(mockPs.Object);

        var result = await service.RunCheckAsync("Administrator");

        result.Name.Should().Be("Administrator");
        result.Status.Should().Be(CheckStatus.Passed);
        result.Message.Should().Be("Running as Administrator");
        result.Duration.TotalMilliseconds.Should().Be(5);
    }

    [Fact]
    public async Task RunCheckAsync_ParsesFailedResult()
    {
        var json = """{"CheckName":"WimMount","Status":"Failed","Severity":"Critical","Message":"WIM Mount service not running","Remediation":"Run Repair-FFUWimMount","DurationMs":120}""";
        var mockPs = CreateMockPs(json);
        var service = new PreflightService(mockPs.Object);

        var result = await service.RunCheckAsync("WimMount");

        result.Status.Should().Be(CheckStatus.Failed);
        result.IsRepairable.Should().BeTrue();
        result.RepairFunction.Should().Be("Repair-FFUWimMount");
    }

    [Fact]
    public async Task RunCheckAsync_HandlesInvokeException()
    {
        var mockPs = new Mock<IPowerShellService>();
        mockPs.Setup(p => p.InvokeAsync(It.IsAny<string>(), null, It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("not recognized as a cmdlet"));

        var service = new PreflightService(mockPs.Object);

        var result = await service.RunCheckAsync("NonExistent");

        result.Status.Should().Be(CheckStatus.Skipped);
    }

    [Fact]
    public async Task RunAllChecksAsync_ReturnsMultipleChecks()
    {
        var json = """{"Status":"Passed","Severity":"Critical","Message":"OK","DurationMs":1}""";
        var mockPs = CreateMockPs(json);
        var service = new PreflightService(mockPs.Object);

        var results = await service.RunAllChecksAsync();

        results.Should().NotBeEmpty();
        results.All(c => c.Status == CheckStatus.Passed).Should().BeTrue();
    }

    [Fact]
    public async Task RepairAsync_ReturnsFalseForUnknownCheck()
    {
        var mockPs = new Mock<IPowerShellService>();
        var service = new PreflightService(mockPs.Object);

        var result = await service.RepairAsync("NonRepairable");

        result.Should().BeFalse();
    }

    [Fact]
    public async Task RepairAsync_CallsRepairFunction()
    {
        var json = """{"Succeeded":true,"Message":"WimMount repaired","DurationMs":500}""";
        var mockPs = CreateMockPs(json);
        var service = new PreflightService(mockPs.Object);

        var result = await service.RepairAsync("WimMount");

        result.Should().BeTrue();
        mockPs.Verify(p => p.InvokeAsync(
            It.Is<string>(s => s.Contains("Repair-FFUWimMount")),
            null,
            It.IsAny<CancellationToken>()), Times.Once);
    }
}
