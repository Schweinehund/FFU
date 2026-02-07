using System.Management.Automation;
using FFUBuilder.App.Models;
using FFUBuilder.App.Services.Interfaces;
using Serilog;

namespace FFUBuilder.App.Services;

public class PreflightService : IPreflightService
{
    private readonly IPowerShellService _psService;

    // Individual Test-FFU* functions that can be invoked standalone
    private static readonly string[] StandaloneChecks =
    [
        "Administrator",
        "PowerShellVersion",
        "HyperV",
        "VMResources",
        "ADK",
        "WimMount",
        "DiskSpace",
        "DISMState",
        "Network",
        "AntivirusExclusions",
        "ScratchSpace"
    ];

    public PreflightService(IPowerShellService psService)
    {
        _psService = psService;
    }

    public async Task<IReadOnlyList<PreflightCheck>> RunAllChecksAsync(
        IProgress<PreflightCheck>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var checks = new List<PreflightCheck>();

        foreach (var checkName in StandaloneChecks)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var check = PreflightCheck.FromName(checkName);
            check.Status = CheckStatus.Running;
            progress?.Report(check);

            try
            {
                var result = await RunCheckAsync(checkName, cancellationToken);
                checks.Add(result);
                progress?.Report(result);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Preflight check {Check} threw an exception", checkName);
                check.Status = CheckStatus.Failed;
                check.Message = $"Check failed with error: {ex.Message}";
                checks.Add(check);
                progress?.Report(check);
            }
        }

        return checks.AsReadOnly();
    }

    public async Task<PreflightCheck> RunCheckAsync(string checkName, CancellationToken cancellationToken = default)
    {
        var check = PreflightCheck.FromName(checkName);
        var functionName = $"Test-FFU{checkName}";

        Log.Debug("Running preflight check: {Function}", functionName);

        try
        {
            var results = await _psService.InvokeAsync(
                $"{functionName} | ConvertTo-Json -Depth 5",
                cancellationToken: cancellationToken);

            if (results.Count > 0)
            {
                ParseCheckResult(check, results.First());
            }
            else
            {
                check.Status = CheckStatus.Warning;
                check.Message = "Check returned no results";
            }
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("not recognized"))
        {
            // Function doesn't exist — module may not be loaded
            check.Status = CheckStatus.Skipped;
            check.Message = $"Check function {functionName} not available";
            Log.Warning("Preflight function not available: {Function}", functionName);
        }
        catch (Exception ex)
        {
            check.Status = CheckStatus.Failed;
            check.Message = $"Error: {ex.Message}";
            Log.Error(ex, "Preflight check failed: {Function}", functionName);
        }

        return check;
    }

    public async Task<bool> RepairAsync(string checkName, CancellationToken cancellationToken = default)
    {
        if (!PreflightCheck.SafeRepairMap.TryGetValue(checkName, out var repairFunction))
        {
            Log.Warning("No repair function for check: {Check}", checkName);
            return false;
        }

        Log.Information("Running repair: {Function} for check {Check}", repairFunction, checkName);

        try
        {
            var results = await _psService.InvokeAsync(
                $"{repairFunction} | ConvertTo-Json -Depth 3",
                cancellationToken: cancellationToken);

            if (results.Count > 0)
            {
                var json = results.First().BaseObject?.ToString();
                if (!string.IsNullOrWhiteSpace(json))
                {
                    var obj = Newtonsoft.Json.JsonConvert.DeserializeObject<Dictionary<string, object?>>(json);
                    object? val = null;
                    var succeeded = obj?.TryGetValue("Succeeded", out val) == true
                        && (val is bool b ? b
                        : val?.ToString()?.Equals("true", StringComparison.OrdinalIgnoreCase) == true);
                    var message = obj?.GetValueOrDefault("Message")?.ToString() ?? "Repair completed";

                    Log.Information("Repair {Function} result: {Succeeded} - {Message}",
                        repairFunction, succeeded, message);
                    return succeeded;
                }
            }

            return true;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Repair failed: {Function}", repairFunction);
            return false;
        }
    }

    private static void ParseCheckResult(PreflightCheck check, PSObject result)
    {
        // The result is JSON-converted, so it comes back as a string
        var json = result.BaseObject?.ToString();
        if (string.IsNullOrWhiteSpace(json))
        {
            check.Status = CheckStatus.Warning;
            check.Message = "Empty result";
            return;
        }

        try
        {
            var obj = Newtonsoft.Json.JsonConvert.DeserializeObject<Dictionary<string, object?>>(json);
            if (obj is null)
            {
                check.Status = CheckStatus.Warning;
                check.Message = "Could not parse result";
                return;
            }

            // Map Status string to CheckStatus enum
            if (obj.TryGetValue("Status", out var statusVal) && statusVal is string statusStr)
            {
                check.Status = statusStr switch
                {
                    "Passed" => CheckStatus.Passed,
                    "Failed" => CheckStatus.Failed,
                    "Warning" => CheckStatus.Warning,
                    "Skipped" => CheckStatus.Skipped,
                    _ => CheckStatus.Warning
                };
            }

            if (obj.TryGetValue("Severity", out var sevVal) && sevVal is string sevStr)
            {
                check.Severity = sevStr;
            }

            if (obj.TryGetValue("Message", out var msgVal) && msgVal is string msgStr)
            {
                check.Message = msgStr;
            }

            if (obj.TryGetValue("Remediation", out var remVal) && remVal is string remStr)
            {
                check.Remediation = remStr;
            }

            if (obj.TryGetValue("DurationMs", out var durVal) && durVal is not null)
            {
                if (long.TryParse(durVal.ToString(), out var ms))
                {
                    check.Duration = TimeSpan.FromMilliseconds(ms);
                }
            }
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Failed to parse check result JSON for {Check}", check.Name);
            check.Status = CheckStatus.Warning;
            check.Message = "Result parse error";
        }
    }

    private static T? GetProperty<T>(PSObject obj, string propertyName)
    {
        var prop = obj.Properties.FirstOrDefault(p =>
            p.Name.Equals(propertyName, StringComparison.OrdinalIgnoreCase));
        if (prop?.Value is T val)
            return val;
        return default;
    }
}
