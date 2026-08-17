using System.Threading.Channels;
using HomeDeck.Api.Lights;
using Microsoft.AspNetCore.SignalR;

namespace HomeDeck.Api.Realtime;

/// <summary>
/// Bridges the registry's change notifications to connected clients.
/// </summary>
/// <remarks>
/// This exists as its own class so that <see cref="LightRegistry"/> never has to know SignalR
/// exists. The registry raises a plain event; who listens is somebody else's problem.
/// </remarks>
/// <remarks>
/// Changes go through a channel rather than being sent straight from the event handler. The
/// event is raised on whichever thread just polled a bulb or handled a request, and that thread
/// must not end up waiting on a slow WebSocket. The channel hands the work to one pump, which
/// also means clients see changes in the order they happened.
/// </remarks>
internal sealed class LightBroadcaster(
    LightRegistry registry,
    IHubContext<LightHub, ILightClient> hub,
    ILogger<LightBroadcaster> logger) : BackgroundService
{
    // Unbounded is safe here: the producer is a ten-second poller and a human pressing buttons,
    // so the queue drains far faster than it fills.
    private readonly Channel<LightState> _changes =
        Channel.CreateUnbounded<LightState>(new UnboundedChannelOptions { SingleReader = true });

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        registry.Changed += OnChanged;

        try
        {
            await foreach (var light in _changes.Reader.ReadAllAsync(stoppingToken))
            {
                try
                {
                    await hub.Clients.All.LightChanged(light);
                }
                catch (Exception ex)
                {
                    // One client's broken connection must not stop the rest from being told.
                    logger.LogWarning(ex, "Failed to broadcast state of light {Id}", light.Id);
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown.
        }
        finally
        {
            registry.Changed -= OnChanged;
        }
    }

    private void OnChanged(LightState light) => _changes.Writer.TryWrite(light);
}
