using CommunityToolkit.Mvvm.ComponentModel;
using FFUBuilder.App.Services.Interfaces;

namespace FFUBuilder.App.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly IPowerShellService _powerShellService;

    [ObservableProperty]
    private string _title = "FFU Builder";

    [ObservableProperty]
    private string _statusText = "Initializing...";

    [ObservableProperty]
    private int _selectedTabIndex;

    public MainViewModel(IPowerShellService powerShellService)
    {
        _powerShellService = powerShellService;
    }

    public void UpdateStatus()
    {
        if (_powerShellService.IsInitialized)
        {
            StatusText = $"Ready - {_powerShellService.LoadedModules.Count} modules loaded";
            Title = $"FFU Builder v2.0.0-alpha1";
        }
        else
        {
            StatusText = "PowerShell modules not loaded";
        }
    }
}
