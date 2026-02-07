using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using FFUBuilder.App.Services.Interfaces;
using Serilog;

namespace FFUBuilder.App.Services;

public sealed class PowerShellService : IPowerShellService
{
    private Runspace? _runspace;
    private readonly SemaphoreSlim _semaphore = new(1, 1);
    private readonly List<string> _loadedModules = [];
    private bool _disposed;

    // Module load order matches BuildFFUVM.ps1 dependency chain
    private static readonly string[] ModuleLoadOrder =
    [
        "FFU.Constants",
        "FFU.Core",
        "FFU.ADK",
        "FFU.Apps",
        "FFU.Drivers",
        "FFU.Imaging",
        "FFU.Media",
        "FFU.Updates",
        "FFU.VM",
        "FFU.Hypervisor",
        "FFU.Preflight",
        "FFU.Messaging",
        "FFU.ConfigMigration",
        "FFU.Checkpoint",
        "FFU.BuildTest"
    ];

    public bool IsInitialized => _runspace?.RunspaceStateInfo.State == RunspaceState.Opened;
    public IReadOnlyList<string> LoadedModules => _loadedModules.AsReadOnly();

    public async Task InitializeAsync(string ffuDevelopmentPath, CancellationToken cancellationToken = default)
    {
        await _semaphore.WaitAsync(cancellationToken);
        try
        {
            if (IsInitialized)
            {
                Log.Warning("PowerShell already initialized, skipping");
                return;
            }

            Log.Information("Creating PowerShell runspace");

            var iss = InitialSessionState.CreateDefault2();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Unrestricted;
            _runspace = RunspaceFactory.CreateRunspace(iss);
            _runspace.Open();

            // Set up PSModulePath to include the Modules directory
            var modulesPath = Path.Combine(ffuDevelopmentPath, "Modules");
            await InvokeInternalAsync(
                $@"$modulesPath = '{EscapeSingleQuotes(modulesPath)}'
if ($env:PSModulePath -notlike ""*$modulesPath*"") {{
    $env:PSModulePath = ""$modulesPath;$env:PSModulePath""
}}");

            Log.Information("PSModulePath configured with: {Path}", modulesPath);

            // Import FFU.Common first (it's in its own directory, not under Modules/)
            var ffuCommonPath = Path.Combine(ffuDevelopmentPath, "FFU.Common");
            if (Directory.Exists(ffuCommonPath))
            {
                await ImportModuleAsync(ffuCommonPath, "FFU.Common");
            }

            // Import modules in dependency order — continue on failure
            // (some modules require admin elevation via #Requires -RunAsAdministrator)
            foreach (var moduleName in ModuleLoadOrder)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var modulePath = Path.Combine(modulesPath, moduleName);
                if (Directory.Exists(modulePath))
                {
                    try
                    {
                        await ImportModuleAsync(modulePath, moduleName);
                    }
                    catch (Exception ex)
                    {
                        Log.Warning(ex, "Skipping module {Module} (may require elevation)", moduleName);
                    }
                }
                else
                {
                    Log.Warning("Module directory not found: {Path}", modulePath);
                }
            }

            Log.Information("PowerShell initialization complete. {Count} modules loaded", _loadedModules.Count);
        }
        finally
        {
            _semaphore.Release();
        }
    }

    private async Task ImportModuleAsync(string modulePath, string moduleName)
    {
        try
        {
            await InvokeInternalAsync(
                $"Import-Module '{EscapeSingleQuotes(modulePath)}' -Force -ErrorAction Stop");
            _loadedModules.Add(moduleName);
            Log.Debug("Loaded module: {Module}", moduleName);
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to load module: {Module} from {Path}", moduleName, modulePath);
            throw;
        }
    }

    public async Task<IReadOnlyCollection<PSObject>> InvokeAsync(
        string script,
        IDictionary<string, object>? parameters = null,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!IsInitialized)
            throw new InvalidOperationException("PowerShell service not initialized. Call InitializeAsync first.");

        await _semaphore.WaitAsync(cancellationToken);
        try
        {
            return await InvokeInternalAsync(script, parameters);
        }
        finally
        {
            _semaphore.Release();
        }
    }

    public async Task<IReadOnlyCollection<PSObject>> InvokeCommandAsync(
        string command,
        IDictionary<string, object>? parameters = null,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!IsInitialized)
            throw new InvalidOperationException("PowerShell service not initialized. Call InitializeAsync first.");

        await _semaphore.WaitAsync(cancellationToken);
        try
        {
            using var ps = PowerShell.Create();
            ps.Runspace = _runspace;
            ps.AddCommand(command);

            if (parameters is not null)
            {
                foreach (var kvp in parameters)
                {
                    ps.AddParameter(kvp.Key, kvp.Value);
                }
            }

            if (progress is not null)
            {
                ps.Streams.Progress.DataAdded += (_, e) =>
                {
                    var record = ps.Streams.Progress[e.Index];
                    progress.Report($"[{record.PercentComplete}%] {record.Activity}: {record.StatusDescription}");
                };
            }

            ps.Streams.Error.DataAdded += (_, e) =>
            {
                var error = ps.Streams.Error[e.Index];
                Log.Error("PowerShell error in {Command}: {Error}", command, error.ToString());
            };

            ps.Streams.Warning.DataAdded += (_, e) =>
            {
                var warning = ps.Streams.Warning[e.Index];
                Log.Warning("PowerShell warning in {Command}: {Warning}", command, warning.ToString());
            };

            ps.Streams.Verbose.DataAdded += (_, e) =>
            {
                var verbose = ps.Streams.Verbose[e.Index];
                Log.Debug("PowerShell verbose in {Command}: {Message}", command, verbose.ToString());
            };

            var results = await Task.Run(() => ps.Invoke(), cancellationToken);

            if (ps.HadErrors)
            {
                var errors = string.Join(Environment.NewLine,
                    ps.Streams.Error.Select(e => e.ToString()));
                throw new InvalidOperationException(
                    $"PowerShell command '{command}' completed with errors:\n{errors}");
            }

            return new ReadOnlyCollection<PSObject>(results.ToList());
        }
        finally
        {
            _semaphore.Release();
        }
    }

    private Task<IReadOnlyCollection<PSObject>> InvokeInternalAsync(
        string script,
        IDictionary<string, object>? parameters = null)
    {
        return Task.Run(() =>
        {
            using var ps = PowerShell.Create();
            ps.Runspace = _runspace;
            ps.AddScript(script);

            if (parameters is not null)
            {
                foreach (var kvp in parameters)
                {
                    ps.AddParameter(kvp.Key, kvp.Value);
                }
            }

            var results = ps.Invoke();

            if (ps.HadErrors)
            {
                var errors = string.Join(Environment.NewLine,
                    ps.Streams.Error.Select(e => e.ToString()));
                throw new InvalidOperationException(
                    $"PowerShell script failed:\n{errors}\n\nScript: {script[..Math.Min(200, script.Length)]}");
            }

            return (IReadOnlyCollection<PSObject>)new ReadOnlyCollection<PSObject>(results.ToList());
        });
    }

    private static string EscapeSingleQuotes(string value) => value.Replace("'", "''");

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;

        await _semaphore.WaitAsync();
        try
        {
            if (_runspace is not null)
            {
                _runspace.Close();
                _runspace.Dispose();
                _runspace = null;
            }
        }
        finally
        {
            _semaphore.Release();
            _semaphore.Dispose();
        }

        Log.Information("PowerShell service disposed");
    }
}
