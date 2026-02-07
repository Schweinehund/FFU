using FFUBuilder.App.Models;

namespace FFUBuilder.App.Services.Interfaces;

public interface IBuildService
{
    BuildState CurrentState { get; }

    Task StartBuildAsync(
        BuildConfiguration config,
        IProgress<BuildProgress> progress,
        CancellationToken cancellationToken = default);

    void RequestCancellation();
}
