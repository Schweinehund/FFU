using CommunityToolkit.Mvvm.ComponentModel;

namespace FFUBuilder.App.ViewModels;

public partial class SettingsViewModel : ObservableObject
{
    [ObservableProperty]
    private string _statusMessage = "Settings - Build configuration will appear here.";
}
