using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using Serilog;

namespace FFUBuilder.App.ViewModels;

public partial class DashboardViewModel : ObservableObject
{
    private readonly IPreflightService _preflightService;

    public ObservableCollection<PreflightCheck> Checks { get; } = [];
    public ICollectionView GroupedChecks { get; }

    [ObservableProperty]
    private bool _isRunning;

    [ObservableProperty]
    private string _summaryText = "Click Refresh to run preflight checks";

    [ObservableProperty]
    private int _passedCount;

    [ObservableProperty]
    private int _failedCount;

    [ObservableProperty]
    private int _warningCount;

    [ObservableProperty]
    private bool _hasCriticalFailures;

    public DashboardViewModel(IPreflightService preflightService)
    {
        _preflightService = preflightService;

        GroupedChecks = CollectionViewSource.GetDefaultView(Checks);
        GroupedChecks.GroupDescriptions.Add(new PropertyGroupDescription(nameof(PreflightCheck.Category)));
        GroupedChecks.SortDescriptions.Add(new SortDescription(nameof(PreflightCheck.Category), ListSortDirection.Ascending));
        GroupedChecks.SortDescriptions.Add(new SortDescription(nameof(PreflightCheck.Name), ListSortDirection.Ascending));
    }

    [RelayCommand(CanExecute = nameof(CanRunChecks))]
    private async Task RunAllChecksAsync()
    {
        IsRunning = true;
        RunAllChecksCommand.NotifyCanExecuteChanged();

        try
        {
            Checks.Clear();
            SummaryText = "Running preflight checks...";
            UpdateCounts();

            var progress = new Progress<PreflightCheck>(check =>
            {
                // Find existing or add new
                var existing = Checks.FirstOrDefault(c => c.Name == check.Name);
                if (existing is not null)
                {
                    var idx = Checks.IndexOf(existing);
                    Checks[idx] = check;
                }
                else
                {
                    Checks.Add(check);
                }
                UpdateCounts();
            });

            var results = await _preflightService.RunAllChecksAsync(progress);

            // Ensure all results are in the collection (Progress<T> callbacks
            // may be deferred when there is no SynchronizationContext, e.g. in tests)
            foreach (var result in results)
            {
                var existing = Checks.FirstOrDefault(c => c.Name == result.Name);
                if (existing is null)
                {
                    Checks.Add(result);
                }
                else if (existing.Status != result.Status)
                {
                    var idx = Checks.IndexOf(existing);
                    Checks[idx] = result;
                }
            }

            UpdateCounts();
            UpdateSummary();
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to run preflight checks");
            SummaryText = $"Error running checks: {ex.Message}";
        }
        finally
        {
            IsRunning = false;
            RunAllChecksCommand.NotifyCanExecuteChanged();
        }
    }

    private bool CanRunChecks() => !IsRunning;

    [RelayCommand]
    private async Task RepairCheckAsync(PreflightCheck? check)
    {
        if (check is null || !check.IsRepairable) return;

        var originalStatus = check.Status;
        check.Status = CheckStatus.Running;
        check.Message = "Repairing...";
        RefreshCheck(check);

        try
        {
            var success = await _preflightService.RepairAsync(check.Name);

            if (success)
            {
                // Re-run the check to get updated status
                var updated = await _preflightService.RunCheckAsync(check.Name);
                ReplaceCheck(check.Name, updated);
            }
            else
            {
                check.Status = CheckStatus.Failed;
                check.Message = "Repair did not succeed. See logs for details.";
                RefreshCheck(check);
            }
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Repair failed for {Check}", check.Name);
            check.Status = originalStatus;
            check.Message = $"Repair error: {ex.Message}";
            RefreshCheck(check);
        }

        UpdateCounts();
        UpdateSummary();
    }

    private void ReplaceCheck(string name, PreflightCheck updated)
    {
        var existing = Checks.FirstOrDefault(c => c.Name == name);
        if (existing is not null)
        {
            var idx = Checks.IndexOf(existing);
            Checks[idx] = updated;
        }
    }

    private void RefreshCheck(PreflightCheck check)
    {
        var idx = Checks.IndexOf(check);
        if (idx >= 0)
        {
            Checks[idx] = check;
        }
    }

    private void UpdateCounts()
    {
        PassedCount = Checks.Count(c => c.Status == CheckStatus.Passed);
        FailedCount = Checks.Count(c => c.Status == CheckStatus.Failed);
        WarningCount = Checks.Count(c => c.Status == CheckStatus.Warning);
        HasCriticalFailures = Checks.Any(c => c.Status == CheckStatus.Failed && c.Severity == "Critical");
    }

    private void UpdateSummary()
    {
        var total = Checks.Count;
        if (FailedCount > 0)
        {
            SummaryText = $"Not Ready - {FailedCount} check(s) failed, {PassedCount}/{total} passed";
        }
        else if (WarningCount > 0)
        {
            SummaryText = $"Ready with Warnings - {WarningCount} warning(s), {PassedCount}/{total} passed";
        }
        else
        {
            SummaryText = $"Ready - All {total} checks passed";
        }
    }
}
