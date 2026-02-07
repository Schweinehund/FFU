using FFUBuilder.App.Models;

namespace FFUBuilder.App.Services.Interfaces;

public interface IBuildService
{
    BuildState CurrentState { get; }
    event EventHandler<BuildState>? StateChanged;

    Task StartBuildAsync(
        BuildConfiguration config,
        IProgress<BuildProgress>? progress = null,
        IProgress<LogEntry>? logProgress = null,
        CancellationToken cancellationToken = default);

    void RequestCancellation();
}
