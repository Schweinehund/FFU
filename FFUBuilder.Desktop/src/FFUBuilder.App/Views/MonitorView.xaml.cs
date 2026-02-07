using System.Windows.Controls;
using FFUBuilder.App.ViewModels;

namespace FFUBuilder.App.Views;

public partial class MonitorView : UserControl
{
    public MonitorView()
    {
        InitializeComponent();
        DataContext = App.Services.GetService(typeof(MonitorViewModel));
    }
}
