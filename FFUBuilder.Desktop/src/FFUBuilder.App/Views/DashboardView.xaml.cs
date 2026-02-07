using System.Windows.Controls;
using FFUBuilder.App.ViewModels;

namespace FFUBuilder.App.Views;

public partial class DashboardView : UserControl
{
    public DashboardView()
    {
        InitializeComponent();
        DataContext = App.Services.GetService(typeof(DashboardViewModel));

        Loaded += async (_, _) =>
        {
            if (DataContext is DashboardViewModel vm && vm.Checks.Count == 0)
            {
                await vm.RunAllChecksCommand.ExecuteAsync(null);
            }
        };
    }
}
