namespace HomeDeck.Api.Lights;

/// <summary>
/// Keeps the registry honest. Lights can also be changed from the WiZ app or a wall switch,
/// and nothing tells us when that happens — so we ask, on a slow interval.
/// </summary>
/// <remarks>
/// One broadcast packet refreshes every bulb at once, which is why polling is affordable here.
/// </remarks>
public sealed class LightPollingService(LightService lights, ILogger<LightPollingService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(10);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        do
        {
            try
            {
                await lights.RefreshAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                // A flaky network must not kill the poller — the next tick tries again.
                logger.LogError(ex, "Light refresh failed");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}
