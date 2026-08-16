using System.Collections.Concurrent;
using Microsoft.Extensions.Options;

namespace HomeDeck.Api.Lights;

/// <summary>Human-facing metadata for a light, keyed by device id in configuration.</summary>
public sealed class LightNaming
{
    public string? Name { get; set; }
    public string? Room { get; set; }
}

public sealed class HomeDeckOptions
{
    /// <summary>Device id (bulb MAC) to name/room. Anything unlisted still shows up, just unnamed.</summary>
    public Dictionary<string, LightNaming> Lights { get; set; } = [];
}

/// <summary>
/// The canonical, in-memory picture of every known light. Everything that changes a light
/// funnels its confirmed result through here, so all clients can be told the same story.
/// </summary>
/// <remarks>
/// In-memory on purpose: the bulbs themselves are the durable store, and a restart just
/// re-discovers them. A database here would be ceremony without a reader.
/// </remarks>
public sealed class LightRegistry(IOptions<HomeDeckOptions> options, TimeProvider time)
{
    private readonly ConcurrentDictionary<string, LightState> _lights = new();

    /// <summary>Raised whenever a light's confirmed state changes. The SignalR hub listens here.</summary>
    public event Action<LightState>? Changed;

    public IReadOnlyList<LightState> All =>
        [.. _lights.Values.OrderBy(l => l.Room).ThenBy(l => l.Name)];

    public LightState? Get(string id) => _lights.GetValueOrDefault(id);

    /// <summary>Records confirmed device state and notifies listeners if anything actually moved.</summary>
    public LightState Upsert(LightSnapshot snapshot)
    {
        var naming = options.Value.Lights.GetValueOrDefault(snapshot.DeviceId);
        var updated = new LightState(
            Id: snapshot.DeviceId,
            Name: naming?.Name ?? DefaultName(snapshot.DeviceId),
            Room: naming?.Room ?? "Unassigned",
            IsOn: snapshot.IsOn,
            Brightness: snapshot.Brightness,
            ColorTempK: snapshot.ColorTempK,
            IsReachable: true,
            UpdatedAt: time.GetUtcNow());

        return Store(updated);
    }

    public LightState? MarkUnreachable(string id)
    {
        if (_lights.GetValueOrDefault(id) is not { } current) return null;
        return Store(current with { IsReachable = false, UpdatedAt = time.GetUtcNow() });
    }

    private LightState Store(LightState updated)
    {
        var previous = _lights.GetValueOrDefault(updated.Id);
        _lights[updated.Id] = updated;

        // Compare everything except the timestamp: a poll that finds nothing new
        // must not wake up every connected client.
        if (previous is null || previous with { UpdatedAt = updated.UpdatedAt } != updated)
            Changed?.Invoke(updated);

        return updated;
    }

    private static string DefaultName(string deviceId) =>
        $"Light {deviceId[^4..].ToUpperInvariant()}";
}
