namespace FFUBuilder.App.Models;

public enum CheckStatus
{
    Pending,
    Running,
    Passed,
    Warning,
    Failed
}

public enum CheckCategory
{
    System,
    Hypervisor,
    BuildTools,
    Network,
    Optimization
}

public class PreflightCheck
{
    public required string Name { get; init; }
    public required string DisplayName { get; init; }
    public CheckCategory Category { get; init; }
    public CheckStatus Status { get; set; }
    public string? Message { get; set; }
    public string? Remediation { get; set; }
    public bool IsRepairable { get; set; }
    public TimeSpan Duration { get; set; }
}
