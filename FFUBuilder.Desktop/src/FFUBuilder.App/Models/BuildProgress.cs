namespace FFUBuilder.App.Models;

public class BuildProgress
{
    public int PercentComplete { get; init; }
    public string Activity { get; init; } = string.Empty;
    public string StatusDescription { get; init; } = string.Empty;
    public DateTime Timestamp { get; init; } = DateTime.Now;
}
