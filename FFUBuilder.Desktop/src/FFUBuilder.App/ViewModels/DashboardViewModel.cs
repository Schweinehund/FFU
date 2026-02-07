using CommunityToolkit.Mvvm.ComponentModel;

namespace FFUBuilder.App.ViewModels;

public partial class DashboardViewModel : ObservableObject
{
    [ObservableProperty]
    private string _statusMessage = "Dashboard - Preflight checks will appear here.";
}
