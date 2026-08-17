using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace HomeDeck.Api.Lights.Wiz;

internal sealed class WizLightProvider(ILogger<WizLightProvider> logger) : ILightProvider
{
    private static readonly TimeSpan DiscoveryWindow = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan ProbeInterval = TimeSpan.FromMilliseconds(500);
    private const int Probes = 3;

    private static readonly TimeSpan RequestTimeout = TimeSpan.FromMilliseconds(600);
    private const int Attempts = 2; // UDP has no retransmit of its own

    private readonly ConcurrentDictionary<string, IPAddress> _addresses = new();

    public async Task<IReadOnlyList<LightSnapshot>> DiscoverAsync(CancellationToken ct = default)
    {
        using var udp = new UdpClient { EnableBroadcast = true };

        // Every bulb on the subnet answers a broadcast getPilot with its own state,
        // so one packet gives us discovery and a full state refresh at the same time.
        var found = new Dictionary<string, LightSnapshot>();
        using var window = CancellationTokenSource.CreateLinkedTokenSource(ct);
        window.CancelAfter(DiscoveryWindow);

        var probing = ProbeAsync(udp, window.Token);

        try
        {
            while (true)
            {
                var reply = await udp.ReceiveAsync(window.Token);
                if (WizProtocol.ParsePilot(reply.Buffer) is not { } snapshot) continue;

                _addresses[snapshot.DeviceId] = reply.RemoteEndPoint.Address;
                found[snapshot.DeviceId] = snapshot;
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            // Discovery window elapsed — that is the normal way out of the loop.
        }

        await probing;

        logger.LogInformation("WiZ discovery found {Count} bulb(s)", found.Count);
        return [.. found.Values];
    }

    private static async Task ProbeAsync(UdpClient udp, CancellationToken ct)
    {
        var payload = Encoding.UTF8.GetBytes(WizProtocol.GetPilot());
        var broadcast = new IPEndPoint(IPAddress.Broadcast, WizProtocol.Port);

        try
        {
            for (var probe = 1; probe <= Probes; probe++)
            {
                await udp.SendAsync(payload, broadcast, ct);
                if (probe < Probes) await Task.Delay(ProbeInterval, ct);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    public async Task<LightSnapshot?> ReadAsync(string deviceId, CancellationToken ct = default)
        => await RequestAsync(deviceId, WizProtocol.GetPilot(), ct);

    public async Task<LightSnapshot?> ApplyAsync(string deviceId, LightCommand command, CancellationToken ct = default)
    {
        await RequestAsync(deviceId, WizProtocol.SetPilot(command), ct);

        // setPilot only answers {"success":true}, so the state we report is always one the
        // bulb confirmed via getPilot — never the state we merely hoped we had set.
        return await RequestAsync(deviceId, WizProtocol.GetPilot(), ct);
    }

    private async Task<LightSnapshot?> RequestAsync(string deviceId, string json, CancellationToken ct)
    {
        if (!_addresses.TryGetValue(deviceId, out var address))
        {
            logger.LogWarning("No known address for device {DeviceId}; run discovery first", deviceId);
            return null;
        }

        var payload = Encoding.UTF8.GetBytes(json);
        var endpoint = new IPEndPoint(address, WizProtocol.Port);

        for (var attempt = 1; attempt <= Attempts; attempt++)
        {
            using var udp = new UdpClient();
            await udp.SendAsync(payload, endpoint, ct);

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(RequestTimeout);
            try
            {
                var reply = await udp.ReceiveAsync(timeout.Token);
                return WizProtocol.ParsePilot(reply.Buffer);
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            {
                logger.LogDebug("No reply from {Address} (attempt {Attempt}/{Attempts})", address, attempt, Attempts);
            }
        }

        return null; // Caller marks the light unreachable rather than failing the whole request.
    }
}
