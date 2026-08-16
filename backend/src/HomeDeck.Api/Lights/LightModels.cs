namespace HomeDeck.Api.Lights;

/// <summary>
/// Canonical state of one light, as the API and every client sees it.
/// Deliberately vendor-neutral: nothing in here hints at WiZ, UDP or JSON payloads.
/// </summary>
public sealed record LightState(
    string Id,
    string Name,
    string Room,
    bool IsOn,
    int Brightness,
    int? ColorTempK,
    bool IsReachable,
    DateTimeOffset UpdatedAt);

/// <summary>
/// What a caller wants changed. Every field is optional — omitted means "leave as is".
/// <see cref="BrightnessDelta"/> is what the rotary knob sends: a relative nudge can never
/// fight a change someone made from the phone, because it is resolved against current state.
/// </summary>
public sealed record LightCommand
{
    public bool? IsOn { get; init; }

    /// <summary>Absolute brightness, 0-100. 0 turns the light off.</summary>
    public int? Brightness { get; init; }

    /// <summary>Relative brightness change, e.g. -5 or +5 from one encoder detent.</summary>
    public int? BrightnessDelta { get; init; }

    public int? ColorTempK { get; init; }
}

/// <summary>
/// What a provider reports back about a device. The provider owns the mapping from this
/// to whatever the hardware actually speaks; names and rooms are HomeDeck's business, not the bulb's.
/// </summary>
public sealed record LightSnapshot(string DeviceId, bool IsOn, int Brightness, int? ColorTempK);

/// <summary>
/// A source of controllable lights. WiZ is the only implementation today; the point of the
/// seam is that adding Hue or a Casambi network would not touch the API layer.
/// </summary>
public interface ILightProvider
{
    /// <summary>Finds every light this provider can reach right now.</summary>
    Task<IReadOnlyList<LightSnapshot>> DiscoverAsync(CancellationToken ct = default);

    /// <summary>Reads confirmed state from the device itself, not from cache.</summary>
    Task<LightSnapshot?> ReadAsync(string deviceId, CancellationToken ct = default);

    /// <summary>Applies absolute values and returns the state the device confirms afterwards.</summary>
    Task<LightSnapshot?> ApplyAsync(string deviceId, LightCommand command, CancellationToken ct = default);
}
