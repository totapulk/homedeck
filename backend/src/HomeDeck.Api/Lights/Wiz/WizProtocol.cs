using System.Text.Json;
using System.Text.Json.Serialization;

namespace HomeDeck.Api.Lights.Wiz;

/// <summary>
/// Everything WiZ-specific that involves no I/O: building request payloads, parsing replies,
/// and translating between HomeDeck's brightness scale and WiZ's "dimming".
/// Keeping this pure is what makes it unit-testable without a bulb on the desk.
/// </summary>
internal static class WizProtocol
{
    public const int Port = 38899;

    /// <summary>WiZ refuses dimming below 10 — below that a bulb is simply off.</summary>
    public const int MinDimming = 10;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static string GetPilot() => """{"method":"getPilot","params":{}}""";

    /// <summary>
    /// Builds a setPilot payload for absolute values. Relative changes are resolved before
    /// they get here — the protocol layer has no idea what the light's current state is.
    /// </summary>
    /// <exception cref="ArgumentException">The command asks for nothing at all.</exception>
    public static string SetPilot(LightCommand command)
    {
        if (command.BrightnessDelta is not null)
            throw new ArgumentException("Relative changes must be resolved to absolute values first.", nameof(command));

        var wanted = new WizPilotParams();

        // Brightness 0 means off; anything else implies on, so the bulb does not need two round trips.
        if (command.Brightness is { } brightness)
        {
            if (brightness <= 0)
            {
                wanted.State = false;
            }
            else
            {
                wanted.State = true;
                wanted.Dimming = ToDimming(brightness);
            }
        }

        // An explicit on/off wins over the one implied by brightness.
        if (command.IsOn is { } isOn)
            wanted.State = isOn;

        if (command.ColorTempK is { } temp)
            wanted.Temp = Math.Clamp(temp, 2200, 6500);

        if (wanted is { State: null, Dimming: null, Temp: null })
            throw new ArgumentException("Command changes nothing.", nameof(command));

        return JsonSerializer.Serialize(new WizRequest("setPilot", wanted), JsonOptions);
    }

    /// <summary>
    /// Reads a getPilot / setPilot reply. Returns null for anything unparseable or for a
    /// bulb that answered with an error — a malformed UDP packet must never take the API down.
    /// </summary>
    public static LightSnapshot? ParsePilot(ReadOnlySpan<byte> payload)
    {
        try
        {
            using var doc = JsonDocument.Parse(payload.ToArray());
            if (!doc.RootElement.TryGetProperty("result", out var result)) return null;
            if (!result.TryGetProperty("mac", out var mac) || mac.ValueKind != JsonValueKind.String) return null;

            var state = result.TryGetProperty("state", out var s) && s.ValueKind == JsonValueKind.True;
            var dimming = result.TryGetProperty("dimming", out var d) && d.TryGetInt32(out var dv) ? dv : MinDimming;
            int? temp = result.TryGetProperty("temp", out var t) && t.TryGetInt32(out var tv) ? tv : null;

            return new LightSnapshot(mac.GetString()!, state, FromDimming(dimming, state), temp);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>HomeDeck brightness (0-100) to WiZ dimming (10-100).</summary>
    public static int ToDimming(int brightness) => Math.Clamp(brightness, MinDimming, 100);

    /// <summary>WiZ dimming to HomeDeck brightness. A light that is off has brightness 0.</summary>
    public static int FromDimming(int dimming, bool state) => state ? Math.Clamp(dimming, MinDimming, 100) : 0;

    private sealed record WizRequest(
        [property: JsonPropertyName("method")] string Method,
        [property: JsonPropertyName("params")] WizPilotParams Params);

    private sealed class WizPilotParams
    {
        public bool? State { get; set; }
        public int? Dimming { get; set; }
        public int? Temp { get; set; }
    }
}
