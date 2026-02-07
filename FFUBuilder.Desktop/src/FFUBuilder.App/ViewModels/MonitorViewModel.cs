using System.Collections.ObjectModel;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using Serilog;

namespace FFUBuilder.App.ViewModels;

public partial class MonitorViewModel : ObservableObject
{
    private readonly IBuildService _buildService;
    private readonly IConfigurationService _configService;
    private CancellationTokenSource? _buildCts;
    private DateTime _buildStartTime;
    private DispatcherTimer? _elapsedTimer;

    public ObservableCollection<LogEntry> LogEntries { get; } = [];

    [ObservableProperty]
    private BuildState _buildState = BuildState.Idle;

    [ObservableProperty]
    private int _progressPercent;

    [ObservableProperty]
    private string _progressActivity = "";

    [ObservableProperty]
    private string _progressStatus = "";

    [ObservableProperty]
    private string _statusMessage = "Ready to build";

    [ObservableProperty]
    private string _elapsedTime = "00:00:00";

    [ObservableProperty]
    private bool _hasCriticalFailures;

    [ObservableProperty]
    private BuildConfiguration? _buildConfiguration;

    public bool CanStartBuild => BuildState == BuildState.Idle
                                 || BuildState == BuildState.Completed
                                 || BuildState == BuildState.Failed
                                 || BuildState == BuildState.Cancelled;

    public bool CanCancel => BuildState == BuildState.Running;

    public bool IsBuilding => BuildState == BuildState.Running || BuildState == BuildState.Cancelling;

    public MonitorViewModel(IBuildService buildService, IConfigurationService configService)
    {
        _buildService = buildService;
        _configService = configService;

        _buildService.StateChanged += (_, state) =>
        {
            BuildState = state;
            OnPropertyChanged(nameof(CanStartBuild));
            OnPropertyChanged(nameof(CanCancel));
            OnPropertyChanged(nameof(IsBuilding));
            StartBuildCommand.NotifyCanExecuteChanged();
            CancelBuildCommand.NotifyCanExecuteChanged();
        };
    }

    partial void OnBuildStateChanged(BuildState value)
    {
        StatusMessage = value switch
        {
            BuildState.Idle => "Ready to build",
            BuildState.Running => "Build in progress...",
            BuildState.Cancelling => "Cancelling build...",
            BuildState.Completed => "Build completed successfully",
            BuildState.Failed => "Build failed — see log for details",
            BuildState.Cancelled => "Build was cancelled",
            _ => StatusMessage
        };
    }

    [RelayCommand(CanExecute = nameof(CanStartBuild))]
    private async Task StartBuildAsync()
    {
        if (BuildConfiguration is null)
        {
            StatusMessage = "No build configuration set";
            return;
        }

        LogEntries.Clear();
        ProgressPercent = 0;
        ProgressActivity = "";
        ProgressStatus = "";
        _buildStartTime = DateTime.Now;
        StartElapsedTimer();

        _buildCts = new CancellationTokenSource();

        var progressHandler = new Progress<BuildProgress>(p =>
        {
            ProgressPercent = p.PercentComplete;
            ProgressActivity = p.Activity;
            ProgressStatus = p.StatusDescription;
        });

        var logHandler = new Progress<LogEntry>(entry =>
        {
            LogEntries.Add(entry);
        });

        try
        {
            await _buildService.StartBuildAsync(
                BuildConfiguration,
                progressHandler,
                logHandler,
                _buildCts.Token);
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Build command failed");
            LogEntries.Add(new LogEntry
            {
                Level = LogLevel.Error,
                Message = $"Unexpected error: {ex.Message}"
            });
        }
        finally
        {
            StopElapsedTimer();
            _buildCts?.Dispose();
            _buildCts = null;
        }
    }

    [RelayCommand(CanExecute = nameof(CanCancel))]
    private void CancelBuild()
    {
        _buildService.RequestCancellation();
        _buildCts?.Cancel();
    }

    [RelayCommand]
    private void ClearLog()
    {
        LogEntries.Clear();
    }

    private void StartElapsedTimer()
    {
        _elapsedTimer?.Stop();
        _elapsedTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _elapsedTimer.Tick += (_, _) =>
        {
            var elapsed = DateTime.Now - _buildStartTime;
            ElapsedTime = elapsed.ToString(@"hh\:mm\:ss");
        };
        _elapsedTimer.Start();
    }

    private void StopElapsedTimer()
    {
        _elapsedTimer?.Stop();
        _elapsedTimer = null;
    }
}
