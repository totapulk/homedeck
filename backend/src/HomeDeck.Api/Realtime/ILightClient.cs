using HomeDeck.Api.Lights;

namespace HomeDeck.Api.Realtime;

/// <summary>
/// Everything the backend can say to a connected client. Declaring it as an interface makes
/// the wire contract a compile-time thing: a mistyped method name fails the build instead of
/// sending a message that silently reaches nobody.
/// </summary>
/// <remarks>
/// These method names go on the wire verbatim, so Flutter subscribes to "LightsSnapshot"
/// and "LightChanged" exactly as spelled here.
/// </remarks>
public interface ILightClient
{
    /// <summary>The full picture, sent once when a client connects.</summary>
    Task LightsSnapshot(IReadOnlyList<LightState> lights);

    /// <summary>One light's confirmed state, sent whenever it actually changes.</summary>
    Task LightChanged(LightState light);
}
