using System.IO;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using Newtonsoft.Json;
using Serilog;

namespace FFUBuilder.App.Services;

public class ConfigurationService : IConfigurationService
{
    public async Task<BuildConfiguration> LoadAsync(string configPath, CancellationToken cancellationToken = default)
    {
        if (!File.Exists(configPath))
        {
            Log.Information("Config file not found at {Path}, returning defaults", configPath);
            return new BuildConfiguration();
        }

        var json = await File.ReadAllTextAsync(configPath, cancellationToken);
        var config = JsonConvert.DeserializeObject<BuildConfiguration>(json) ?? new BuildConfiguration();
        Log.Information("Loaded configuration from {Path}", configPath);
        return config;
    }

    public async Task SaveAsync(string configPath, BuildConfiguration config, CancellationToken cancellationToken = default)
    {
        var settings = new JsonSerializerSettings
        {
            Formatting = Formatting.Indented,
            NullValueHandling = NullValueHandling.Ignore
        };

        var json = JsonConvert.SerializeObject(config, settings);
        var directory = Path.GetDirectoryName(configPath);
        if (directory is not null && !Directory.Exists(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await File.WriteAllTextAsync(configPath, json, cancellationToken);
        Log.Information("Saved configuration to {Path}", configPath);
    }

    public BuildConfiguration CreateDefaults() => BuildConfiguration.CreateDefaults();

    public string GetDefaultConfigPath(string ffuDevelopmentPath)
        => Path.Combine(ffuDevelopmentPath, "config", "FFUConfig.json");
}
