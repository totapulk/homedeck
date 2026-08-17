using HomeDeck.Api.Lights;
using Microsoft.AspNetCore.SignalR;

namespace HomeDeck.Api.Realtime;

/// <summary>
/// The real-time endpoint clients connect to. It is deliberately push-only: commands still go
/// through the REST API, so there is exactly one way to change a light and one way to hear
/// about it. Adding command methods here would give the system two front doors to keep in step.
/// </summary>
public sealed class LightHub(LightRegistry registry) : Hub<ILightClient>
{
    public override async Task OnConnectedAsync()
    {
        // A fresh client gets the whole picture immediately, so it never has to fetch over REST
        // and subscribe separately and then work out which of the two arrived first.
        await Clients.Caller.LightsSnapshot(registry.All);
        await base.OnConnectedAsync();
    }
}
