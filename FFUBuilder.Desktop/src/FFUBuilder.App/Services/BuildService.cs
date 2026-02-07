using System.IO;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using Newtonsoft.Json;
using Serilog;

namespace FFUBuilder.App.Services;

public class BuildService : IBuildService
{
    private readonly IPowerShellService _psService;
    private readonly IConfigurationService _configService;
    private CancellationTokenSource? _cts;

    public BuildState CurrentState { get; private set; } = BuildState.Idle;
    public event EventHandler<BuildState>? StateChanged;

    public BuildService(IPowerShellService psService, IConfigurationService configService)
    {
        _psService = psService;
        _configService = configService;
    }

    public async Task StartBuildAsync(
        BuildConfiguration config,
        IProgress<BuildProgress>? progress = null,
        IProgress<LogEntry>? logProgress = null,
        CancellationToken cancellationToken = default)
    {
        if (CurrentState == BuildState.Running || CurrentState == BuildState.Cancelling)
        {
            throw new InvalidOperationException("A build is already in progress");
        }

        SetState(BuildState.Running);
        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

        try
        {
            // Save config to temp file for the build script
            var tempConfigPath = Path.Combine(Path.GetTempPath(), $"ffubuilder_{Guid.NewGuid():N}.json");
            await _configService.SaveAsync(tempConfigPath, config, _cts.Token);

            logProgress?.Report(new LogEntry
            {
                Level = LogLevel.Information,
                Message = "Build started — configuration saved"
            });

            // Build the script to invoke BuildFFUVM.ps1
            var ffuDevPath = config.FFUDevelopmentPath;
            if (string.IsNullOrEmpty(ffuDevPath))
            {
                ffuDevPath = @"C:\FFUDevelopment";
            }

            var scriptPath = Path.Combine(ffuDevPath, "BuildFFUVM.ps1");
            if (!File.Exists(scriptPath))
            {
                throw new FileNotFoundException($"Build script not found: {scriptPath}");
            }

            var script = $"& '{EscapeSingleQuotes(scriptPath)}' -ConfigFile '{EscapeSingleQuotes(tempConfigPath)}' -Verbose";

            Log.Information("Starting build with script: {Script}", scriptPath);

            await _psService.InvokeScriptWithStreamingAsync(
                script,
                parameters: null,
                onProgress: record =>
                {
                    progress?.Report(new BuildProgress
                    {
                        PercentComplete = Math.Max(0, Math.Min(100, record.PercentComplete)),
                        Activity = record.Activity ?? "",
                        StatusDescription = record.StatusDescription ?? ""
                    });
                },
                onVerbose: msg =>
                {
                    logProgress?.Report(new LogEntry
                    {
                        Level = LogLevel.Verbose,
                        Message = msg
                    });
                },
                onWarning: msg =>
                {
                    logProgress?.Report(new LogEntry
                    {
                        Level = LogLevel.Warning,
                        Message = msg
                    });
                    Log.Warning("Build warning: {Message}", msg);
                },
                onError: err =>
                {
                    logProgress?.Report(new LogEntry
                    {
                        Level = LogLevel.Error,
                        Message = err.ToString()
                    });
                    Log.Error("Build error: {Error}", err.ToString());
                },
                cancellationToken: _cts.Token);

            // Clean up temp config
            TryDeleteFile(tempConfigPath);

            logProgress?.Report(new LogEntry
            {
                Level = LogLevel.Information,
                Message = "Build completed successfully"
            });

            SetState(BuildState.Completed);
        }
        catch (OperationCanceledException)
        {
            logProgress?.Report(new LogEntry
            {
                Level = LogLevel.Warning,
                Message = "Build was cancelled"
            });
            SetState(BuildState.Cancelled);
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Build failed");
            logProgress?.Report(new LogEntry
            {
                Level = LogLevel.Error,
                Message = $"Build failed: {ex.Message}"
            });
            SetState(BuildState.Failed);
        }
        finally
        {
            _cts?.Dispose();
            _cts = null;
        }
    }

    public void RequestCancellation()
    {
        if (CurrentState != BuildState.Running) return;

        Log.Information("Build cancellation requested");
        SetState(BuildState.Cancelling);
        _cts?.Cancel();
    }

    private void SetState(BuildState newState)
    {
        CurrentState = newState;
        StateChanged?.Invoke(this, newState);
    }

    private static string EscapeSingleQuotes(string value) => value.Replace("'", "''");

    private static void TryDeleteFile(string path)
    {
        try { File.Delete(path); } catch { /* ignore cleanup errors */ }
    }
}
