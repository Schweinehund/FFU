using CommunityToolkit.Mvvm.ComponentModel;

namespace FFUBuilder.App.ViewModels;

public partial class MonitorViewModel : ObservableObject
{
    [ObservableProperty]
    private string _statusMessage = "Monitor - Build progress will appear here.";
}
