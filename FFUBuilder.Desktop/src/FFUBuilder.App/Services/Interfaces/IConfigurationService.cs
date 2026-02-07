using FFUBuilder.App.Models;

namespace FFUBuilder.App.Services.Interfaces;

public interface IConfigurationService
{
    Task<BuildConfiguration> LoadAsync(string configPath, CancellationToken cancellationToken = default);
    Task SaveAsync(string configPath, BuildConfiguration config, CancellationToken cancellationToken = default);
}
