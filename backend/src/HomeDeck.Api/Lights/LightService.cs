namespace HomeDeck.Api.Lights;

/// <summary>
/// Turns intents ("dim this a bit") into absolute device commands, and keeps the registry
/// in step with what the hardware confirms.
/// </summary>
public sealed class LightService(ILightProvider provider, LightRegistry registry, ILogger<LightService> logger)
{
    /// <summary>Re-discovers every reachable light and refreshes the registry from real device state.</summary>
    public async Task<IReadOnlyList<LightState>> RefreshAsync(CancellationToken ct = default)
    {
        var snapshots = await provider.DiscoverAsync(ct);
        foreach (var snapshot in snapshots)
            registry.Upsert(snapshot);

        // Anything we knew about that stayed quiet is offline, not deleted: a light that is
        // briefly unreachable should keep its place in the UI instead of vanishing from it.
        var seen = snapshots.Select(s => s.DeviceId).ToHashSet();
        foreach (var known in registry.All.Where(l => !seen.Contains(l.Id)))
            registry.MarkMissing(known.Id);

        return registry.All;
    }

    /// <summary>
    /// Applies a command to one light. Relative changes are resolved against the last
    /// confirmed state here — the knob says "a bit brighter", the backend decides what that means.
    /// </summary>
    public async Task<LightState?> ApplyAsync(string id, LightCommand command, CancellationToken ct = default)
    {
        if (registry.Get(id) is not { } current) return null;

        var resolved = Resolve(command, current);
        var snapshot = await provider.ApplyAsync(id, resolved, ct);

        if (snapshot is null)
        {
            logger.LogWarning("Light {Id} did not confirm the command; marking unreachable", id);
            return registry.MarkUnreachable(id);
        }

        return registry.Upsert(snapshot);
    }

    /// <summary>Collapses a possibly-relative command into absolute values. Pure, so it is easy to test.</summary>
    internal static LightCommand Resolve(LightCommand command, LightState current)
    {
        if (command.BrightnessDelta is not { } delta) return command;

        var target = Math.Clamp(current.Brightness + delta, 0, 100);
        return command with
        {
            BrightnessDelta = null,
            Brightness = target,
            // Turning the knob down to zero is a legitimate way to switch a light off,
            // and turning it up from zero switches it back on.
            IsOn = command.IsOn ?? target > 0,
        };
    }
}
