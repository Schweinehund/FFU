using System.Windows.Controls;
using FFUBuilder.App.ViewModels;

namespace FFUBuilder.App.Views;

public partial class AboutView : UserControl
{
    public AboutView()
    {
        InitializeComponent();
        DataContext = App.Services.GetService(typeof(AboutViewModel));
    }
}
