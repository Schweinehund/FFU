using System.IO;
using FFUBuilder.App.Services;
using FluentAssertions;
using Xunit;

namespace FFUBuilder.Tests.Services;

public class PowerShellServiceTests
{
    private static string? FindFFUDevelopmentPath()
    {
        var candidates = new[]
        {
            Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "..", "..", "..", "FFUDevelopment")),
            @"C:\FFUDevelopment",
            @"C:\claude\FFUBuilder\FFUDevelopment"
        };

        return candidates.FirstOrDefault(p =>
            Directory.Exists(p) && File.Exists(Path.Combine(p, "BuildFFUVM.ps1")));
    }

    [Fact]
    public void NewService_IsNotInitialized()
    {
        var service = new PowerShellService();

        service.IsInitialized.Should().BeFalse();
        service.LoadedModules.Should().BeEmpty();
    }

    [Fact]
    public async Task InitializeAsync_WithInvalidPath_LoadsNoModules()
    {
        var service = new PowerShellService();

        await service.InitializeAsync(@"C:\NonExistent\Path");

        service.IsInitialized.Should().BeTrue("runspace should still be created");
        service.LoadedModules.Should().BeEmpty("no module directories exist at the path");

        await service.DisposeAsync();
    }

    [Fact]
    public async Task InitializeAsync_LoadsAvailableModules()
    {
        var ffuDevPath = FindFFUDevelopmentPath();
        if (ffuDevPath is null)
        {
            // Skip: FFUDevelopment directory not found
            return;
        }

        var service = new PowerShellService();

        await service.InitializeAsync(ffuDevPath);

        service.IsInitialized.Should().BeTrue();
        service.LoadedModules.Should().NotBeEmpty();
        // Foundation modules should always load (no admin requirement)
        service.LoadedModules.Should().Contain("FFU.Constants");
        service.LoadedModules.Should().Contain("FFU.Core");

        await service.DisposeAsync();
    }

    [Fact]
    public async Task InitializeAsync_LoadsModulesInCorrectOrder()
    {
        var ffuDevPath = FindFFUDevelopmentPath();
        if (ffuDevPath is null)
        {
            return;
        }

        var service = new PowerShellService();

        await service.InitializeAsync(ffuDevPath);

        var modules = service.LoadedModules;
        if (modules.Contains("FFU.Constants") && modules.Contains("FFU.Core"))
        {
            var constantsIdx = modules.ToList().IndexOf("FFU.Constants");
            var coreIdx = modules.ToList().IndexOf("FFU.Core");
            constantsIdx.Should().BeLessThan(coreIdx, "FFU.Constants must load before FFU.Core");
        }
        else
        {
            // In non-admin environments, some modules may not load
            modules.Should().NotBeEmpty("at least some modules should load");
        }

        await service.DisposeAsync();
    }

    [Fact]
    public async Task InvokeAsync_CanExecuteSimpleScript()
    {
        var ffuDevPath = FindFFUDevelopmentPath();
        if (ffuDevPath is null)
        {
            return;
        }

        var service = new PowerShellService();
        await service.InitializeAsync(ffuDevPath);

        var results = await service.InvokeAsync("2 + 2");

        results.Should().HaveCount(1);
        results.First().BaseObject.Should().Be(4);

        await service.DisposeAsync();
    }

    [Fact]
    public async Task InvokeAsync_ThrowsWhenNotInitialized()
    {
        var service = new PowerShellService();

        var act = () => service.InvokeAsync("Get-Date");

        await act.Should().ThrowAsync<InvalidOperationException>()
            .WithMessage("*not initialized*");

        await service.DisposeAsync();
    }

    [Fact]
    public async Task DisposeAsync_CanBeCalledMultipleTimes()
    {
        var service = new PowerShellService();

        await service.DisposeAsync();
        await service.DisposeAsync();
    }
}
