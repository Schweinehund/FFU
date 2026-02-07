using CommunityToolkit.Mvvm.ComponentModel;

namespace FFUBuilder.App.ViewModels;

public partial class AboutViewModel : ObservableObject
{
    [ObservableProperty]
    private string _appVersion = "v2.0.0-alpha1";

    [ObservableProperty]
    private string _description = "Windows FFU image builder with native WPF UI";
}
