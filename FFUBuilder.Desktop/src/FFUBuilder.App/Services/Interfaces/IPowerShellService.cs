using System.Management.Automation;

namespace FFUBuilder.App.Services.Interfaces;

public interface IPowerShellService : IAsyncDisposable
{
    bool IsInitialized { get; }
    IReadOnlyList<string> LoadedModules { get; }

    Task InitializeAsync(string ffuDevelopmentPath, CancellationToken cancellationToken = default);

    Task<IReadOnlyCollection<PSObject>> InvokeAsync(
        string script,
        IDictionary<string, object>? parameters = null,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyCollection<PSObject>> InvokeCommandAsync(
        string command,
        IDictionary<string, object>? parameters = null,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default);

    Task InvokeScriptWithStreamingAsync(
        string script,
        IDictionary<string, object>? parameters = null,
        Action<System.Management.Automation.ProgressRecord>? onProgress = null,
        Action<string>? onVerbose = null,
        Action<string>? onWarning = null,
        Action<System.Management.Automation.ErrorRecord>? onError = null,
        CancellationToken cancellationToken = default);
}
