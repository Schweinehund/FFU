using System.Collections.Specialized;
using System.Windows.Controls;
using FFUBuilder.App.ViewModels;

namespace FFUBuilder.App.Views;

public partial class MonitorView : UserControl
{
    public MonitorView()
    {
        InitializeComponent();
        DataContext = App.Services.GetService(typeof(MonitorViewModel));

        if (DataContext is MonitorViewModel vm)
        {
            // Auto-scroll log to bottom when new entries are added
            vm.LogEntries.CollectionChanged += (_, e) =>
            {
                if (e.Action == NotifyCollectionChangedAction.Add && LogListView.Items.Count > 0)
                {
                    LogListView.ScrollIntoView(LogListView.Items[^1]);
                }
            };
        }
    }
}
