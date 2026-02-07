using System.IO;
using System.Windows;
using FFUBuilder.App.Services;
using FFUBuilder.App.Services.Interfaces;
using FFUBuilder.App.ViewModels;
using FFUBuilder.App.Views;
using Microsoft.Extensions.DependencyInjection;
using Serilog;

namespace FFUBuilder.App;

public partial class App : Application
{
    private ServiceProvider? _serviceProvider;

    public static IServiceProvider Services { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        ConfigureLogging();

        var services = new ServiceCollection();
        ConfigureServices(services);
        _serviceProvider = services.BuildServiceProvider();
        Services = _serviceProvider;

        DispatcherUnhandledException += (_, args) =>
        {
            Log.Error(args.Exception, "Unhandled UI exception");
            MessageBox.Show(
                $"An unexpected error occurred:\n\n{args.Exception.Message}\n\nSee logs for details.",
                "FFU Builder Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            args.Handled = true;
        };

        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Log.Error(args.Exception, "Unobserved task exception");
            args.SetObserved();
        };

        var mainWindow = _serviceProvider.GetRequiredService<MainWindow>();
        mainWindow.Show();

        _ = InitializePowerShellAsync();
    }

    private static void ConfigureLogging()
    {
        var logPath = Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory, "Logs", "ffubuilder-.log");

        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Debug()
            .WriteTo.File(logPath,
                rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 14,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff} [{Level:u3}] {Message:lj}{NewLine}{Exception}")
            .CreateLogger();

        Log.Information("FFU Builder Desktop starting");
    }

    private static void ConfigureServices(IServiceCollection services)
    {
        // Services
        services.AddSingleton<IPowerShellService, PowerShellService>();
        services.AddSingleton<IConfigurationService, ConfigurationService>();
        services.AddSingleton<IPreflightService, PreflightService>();

        // ViewModels
        services.AddSingleton<MainViewModel>();
        services.AddTransient<DashboardViewModel>();
        services.AddTransient<SettingsViewModel>();
        services.AddTransient<MonitorViewModel>();
        services.AddTransient<AboutViewModel>();

        // Views
        services.AddSingleton<MainWindow>();
    }

    private async Task InitializePowerShellAsync()
    {
        try
        {
            var psService = Services.GetRequiredService<IPowerShellService>();
            var ffuDevPath = FindFFUDevelopmentPath();

            Log.Information("Initializing PowerShell with FFUDevelopmentPath: {Path}", ffuDevPath);
            await psService.InitializeAsync(ffuDevPath);
            Log.Information("PowerShell initialized with {Count} modules", psService.LoadedModules.Count);
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to initialize PowerShell modules");
            Dispatcher.Invoke(() =>
            {
                MessageBox.Show(
                    $"Failed to load PowerShell modules:\n\n{ex.Message}\n\nSome features may not work correctly.",
                    "Module Loading Warning",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            });
        }
    }

    private static string FindFFUDevelopmentPath()
    {
        // Look for FFUDevelopment relative to the app or at the standard location
        var candidates = new[]
        {
            Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "..", "FFUDevelopment")),
            @"C:\FFUDevelopment",
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "FFUDevelopment")
        };

        foreach (var candidate in candidates)
        {
            if (Directory.Exists(candidate) &&
                File.Exists(Path.Combine(candidate, "BuildFFUVM.ps1")))
            {
                return Path.GetFullPath(candidate);
            }
        }

        return @"C:\FFUDevelopment";
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_serviceProvider is IDisposable disposable)
        {
            disposable.Dispose();
        }

        Log.Information("FFU Builder Desktop shutting down");
        Log.CloseAndFlush();
        base.OnExit(e);
    }
}
