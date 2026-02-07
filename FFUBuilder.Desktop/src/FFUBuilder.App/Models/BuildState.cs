namespace FFUBuilder.App.Models;

public enum BuildState
{
    Idle,
    Running,
    Cancelling,
    Completed,
    Failed,
    Cancelled
}
