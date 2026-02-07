namespace FFUBuilder.App.Models;

public enum LogLevel
{
    Verbose,
    Information,
    Warning,
    Error
}

public class LogEntry
{
    public DateTime Timestamp { get; init; } = DateTime.Now;
    public LogLevel Level { get; init; } = LogLevel.Information;
    public string Message { get; init; } = string.Empty;
}
