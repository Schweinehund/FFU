using System.Collections.ObjectModel;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using FFUBuilder.App.Services.Interfaces;
using Newtonsoft.Json.Linq;
using Serilog;

namespace FFUBuilder.App.ViewModels;

public partial class AboutViewModel : ObservableObject
{
    private readonly IPowerShellService _psService;

    [ObservableProperty]
    private string _appVersion = "v2.0.0-alpha1";

    [ObservableProperty]
    private string _buildDate = "";

    [ObservableProperty]
    private string _psVersion = "";

    [ObservableProperty]
    private string _description = "Windows FFU image builder with native WPF UI.\nCreates pre-configured Windows images deployable in under 2 minutes.";

    [ObservableProperty]
    private int _loadedModuleCount;

    public ObservableCollection<ModuleInfo> Modules { get; } = [];

    public AboutViewModel(IPowerShellService psService)
    {
        _psService = psService;
        LoadedModuleCount = psService.LoadedModules.Count;
        PsVersion = $"{psService.LoadedModules.Count} modules loaded";
        LoadVersionInfo();
    }

    private void LoadVersionInfo()
    {
        try
        {
            // Try to find version.json relative to known paths
            var candidates = new[]
            {
                Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "..", "FFUDevelopment", "version.json")),
                @"C:\FFUDevelopment\version.json",
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "FFUDevelopment", "version.json")
            };

            foreach (var path in candidates)
            {
                if (!File.Exists(path)) continue;

                var json = File.ReadAllText(path);
                var obj = JObject.Parse(json);

                if (obj["version"] is JToken ver)
                    AppVersion = $"v{ver} (Desktop v2.0.0-alpha1)";

                if (obj["buildDate"] is JToken date)
                    BuildDate = $"Build date: {date}";

                if (obj["modules"] is JObject modules)
                {
                    foreach (var prop in modules.Properties())
                    {
                        var modObj = prop.Value as JObject;
                        var isLoaded = _psService.LoadedModules.Contains(prop.Name);
                        Modules.Add(new ModuleInfo
                        {
                            Name = prop.Name,
                            Version = modObj?["version"]?.ToString() ?? "?",
                            Description = modObj?["description"]?.ToString() ?? "",
                            IsLoaded = isLoaded
                        });
                    }
                }

                Log.Debug("Loaded version info from {Path}", path);
                return;
            }

            Log.Warning("version.json not found, using defaults");
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Failed to read version.json");
        }
    }
}

public class ModuleInfo
{
    public string Name { get; init; } = "";
    public string Version { get; init; } = "";
    public string Description { get; init; } = "";
    public bool IsLoaded { get; init; }
}
