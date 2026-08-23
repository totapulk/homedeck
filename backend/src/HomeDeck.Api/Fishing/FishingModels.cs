namespace HomeDeck.Api.Fishing;

public sealed record FishingSpecies(string Id, string Name, string Emoji, int Index);

public sealed record FishingWeather(
    double? AirTempC,
    int WindMs,
    int PressureHpa,
    string PressureTrend,
    string Cloud,
    int WaterTempC,
    /// <summary>"syke" for a real reading, "estimate" when no station was near enough.</summary>
    string WaterSource);

public sealed record FishingState(
    string LakeName,
    FishingSpecies? Best,
    IReadOnlyList<FishingSpecies> Species,
    string? Comment,
    FishingWeather? Weather,
    bool IsAvailable,
    DateTimeOffset UpdatedAt);

/// <summary>
/// Today's fishing conditions for one lake. Unlike the lights and the vacuum, nothing here is a
/// device in the flat: it is another of this developer's own products answering over the
/// internet, and the only one of the three that HomeDeck can do nothing about.
/// </summary>
public interface IFishingProvider
{
    Task<FishingState> ReadAsync(CancellationToken ct = default);
}
