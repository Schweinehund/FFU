using FFUBuilder.App.Models;

namespace FFUBuilder.App.Services.Interfaces;

public interface IPreflightService
{
    Task<IReadOnlyList<PreflightCheck>> RunAllChecksAsync(
        IProgress<PreflightCheck>? progress = null,
        CancellationToken cancellationToken = default);

    Task<PreflightCheck> RunCheckAsync(string checkName, CancellationToken cancellationToken = default);

    Task<bool> RepairAsync(string checkName, CancellationToken cancellationToken = default);
}
