using System.Collections.Concurrent;
using Microsoft.Extensions.Options;

namespace HomeDeck.Api.Lights;

/// <summary>Human-facing metadata for a light, keyed by device id in configuration.</summary>
public sealed class LightNaming
{
    public string? Name { get; set; }
    public string? Room { get; set; }

    /// <summary>
    /// Groups bulbs that share one physical lamp. Bulbs naming the same fixture are shown and
    /// controlled as one; a bulb naming none is a lamp of its own.
    /// </summary>
    public string? Fixture { get; set; }
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
/// <remarks>
/// Naming comes in through IOptionsMonitor rather than IOptions so that renaming a light in
/// appsettings.json takes effect on the next poll instead of on the next restart.
/// </remarks>
public sealed class LightRegistry(IOptionsMonitor<HomeDeckOptions> options, TimeProvider time)
{
    /// <summary>Consecutive silent polls before a light is called unreachable.</summary>
    public const int MissesBeforeUnreachable = 3;

    private readonly ConcurrentDictionary<string, LightState> _lights = new();
    private readonly ConcurrentDictionary<string, int> _misses = new();

    /// <summary>Raised whenever a light's confirmed state changes. The SignalR hub listens here.</summary>
    public event Action<LightState>? Changed;

    public IReadOnlyList<LightState> All =>
        [.. _lights.Values.OrderBy(l => l.Room).ThenBy(l => l.Name)];

    public LightState? Get(string id) => _lights.GetValueOrDefault(id);

    /// <summary>Records confirmed device state and notifies listeners if anything actually moved.</summary>
    public LightState Upsert(LightSnapshot snapshot)
    {
        _misses.TryRemove(snapshot.DeviceId, out _);

        var naming = options.CurrentValue.Lights.GetValueOrDefault(snapshot.DeviceId);
        var updated = new LightState(
            Id: snapshot.DeviceId,
            Name: naming?.Name ?? DefaultName(snapshot.DeviceId),
            Room: naming?.Room ?? "Unassigned",
            Fixture: naming?.Fixture,
            IsOn: snapshot.IsOn,
            Brightness: snapshot.Brightness,
            ColorTempK: snapshot.ColorTempK,
            IsReachable: true,
            UpdatedAt: time.GetUtcNow());

        return Store(updated);
    }

    /// <summary>
    /// Records that a light said nothing during a poll. Silence is weak evidence: the probe is
    /// an unacknowledged UDP broadcast, so a packet lost on the way out or a bulb that answers a
    /// moment late both look like death. Only a run of silent polls is allowed to mean it.
    /// </summary>
    public LightState? MarkMissing(string id)
    {
        if (_lights.GetValueOrDefault(id) is not { } current) return null;

        var misses = _misses.AddOrUpdate(id, 1, static (_, previous) => previous + 1);
        return misses >= MissesBeforeUnreachable ? MarkUnreachable(id) : current;
    }

    /// <summary>Reports a light as unreachable now, for evidence stronger than a missed poll.</summary>
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
