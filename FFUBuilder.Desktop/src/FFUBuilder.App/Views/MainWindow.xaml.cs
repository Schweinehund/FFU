using System.Windows;
using System.Windows.Threading;
using FFUBuilder.App.ViewModels;

namespace FFUBuilder.App.Views;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;
    private readonly DispatcherTimer _statusTimer;

    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;

        // Poll for initialization status until ready
        _statusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _statusTimer.Tick += (_, _) =>
        {
            _viewModel.UpdateStatus();
            if (_viewModel.StatusText.StartsWith("Ready"))
            {
                _statusTimer.Stop();
            }
        };
        _statusTimer.Start();
    }
}
