using System.Windows.Controls;
using FFUBuilder.App.ViewModels;

namespace FFUBuilder.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
        DataContext = App.Services.GetService(typeof(SettingsViewModel));
    }
}
