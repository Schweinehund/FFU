using System.Windows.Controls;
using FFUBuilder.App.ViewModels;

namespace FFUBuilder.App.Views;

public partial class DashboardView : UserControl
{
    public DashboardView()
    {
        InitializeComponent();
        DataContext = App.Services.GetService(typeof(DashboardViewModel));
    }
}
