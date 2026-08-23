using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace HomeDeck.Api.Fishing;

public sealed class KalaUkkoOptions
{
    /// <summary>Where Kala Ukko lives. Null leaves the card saying it is not configured.</summary>
    public string? BaseUrl { get; set; }

    public string? LakeName { get; set; }
    public double? Lat { get; set; }
    public double? Lon { get; set; }
}

/// <summary>Reads the bite forecast from Kala Ukko's public endpoint.</summary>
public sealed class KalaUkkoFishingProvider(
    HttpClient http,
    IOptionsMonitor<KalaUkkoOptions> options,
    TimeProvider time) : IFishingProvider
{
    /// <summary>Matches the weather data's own lifetime; asking more often cannot learn more.</summary>
    private static readonly TimeSpan Freshness = TimeSpan.FromMinutes(10);

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly Lock _gate = new();
    private FishingState? _cached;

    public async Task<FishingState> ReadAsync(CancellationToken ct = default)
    {
        var settings = options.CurrentValue;
        var lake = settings.LakeName ?? "Järvi";

        if (string.IsNullOrWhiteSpace(settings.BaseUrl) || settings.Lat is null || settings.Lon is null)
            return Unavailable(lake);

        lock (_gate)
        {
            // Every client asking at once must still be one request out to the internet.
            if (_cached is { IsAvailable: true } cached && time.GetUtcNow() - cached.UpdatedAt < Freshness)
                return cached;
        }

        try
        {
            var reading = await http.GetFromJsonAsync<Reading>(BuildPath(settings), Json, ct);
            if (reading is null) return Unavailable(lake);

            var state = Map(reading, lake);
            lock (_gate)
            {
                _cached = state;
            }

            return state;
        }
        catch (Exception failure) when (failure is HttpRequestException or TaskCanceledException or JsonException)
        {
            // Someone else's server on the far side of the internet. Not reaching it is a
            // Tuesday, not an error worth propagating into the lights.
            return Unavailable(lake);
        }
    }

    private static string BuildPath(KalaUkkoOptions settings)
    {
        var query = new Dictionary<string, string?>
        {
            ["lat"] = settings.Lat?.ToString(CultureInfo.InvariantCulture),
            ["lon"] = settings.Lon?.ToString(CultureInfo.InvariantCulture),
            ["name"] = settings.LakeName,
        };

        var parts = query
            .Where(pair => !string.IsNullOrWhiteSpace(pair.Value))
            .Select(pair => $"{pair.Key}={Uri.EscapeDataString(pair.Value!)}");

        return "api/kalasaa?" + string.Join('&', parts);
    }

    private FishingState Map(Reading reading, string fallbackName)
    {
        var species = reading.Species?
            .Select(entry => new FishingSpecies(entry.Id, entry.Name, entry.Emoji, entry.Index))
            .ToArray() ?? [];

        return new FishingState(
            LakeName: reading.Lake?.Name ?? fallbackName,
            Best: species.FirstOrDefault(),
            Species: species,
            Comment: reading.Comment,
            Weather: reading.Weather is { } weather && reading.Water is { } water
                ? new FishingWeather(
                    AirTempC: weather.AirTempC,
                    WindMs: weather.WindMs,
                    PressureHpa: weather.PressureHpa,
                    PressureTrend: weather.PressureTrend,
                    Cloud: weather.Cloud,
                    WaterTempC: water.TempC,
                    WaterSource: water.Source)
                : null,
            IsAvailable: species.Length > 0,
            UpdatedAt: time.GetUtcNow());
    }

    private FishingState Unavailable(string lake) => new(
        LakeName: lake,
        Best: null,
        Species: [],
        Comment: null,
        Weather: null,
        IsAvailable: false,
        UpdatedAt: time.GetUtcNow());

    private sealed record Reading(
        [property: JsonPropertyName("lake")] ReadingLake? Lake,
        [property: JsonPropertyName("weather")] ReadingWeather? Weather,
        [property: JsonPropertyName("water")] ReadingWater? Water,
        [property: JsonPropertyName("species")] IReadOnlyList<ReadingSpecies>? Species,
        [property: JsonPropertyName("comment")] string? Comment);

    private sealed record ReadingLake(string? Name);

    private sealed record ReadingWeather(
        double? AirTempC,
        int WindMs,
        int PressureHpa,
        string PressureTrend,
        string Cloud);

    private sealed record ReadingWater(int TempC, string Source);

    private sealed record ReadingSpecies(string Id, string Name, string Emoji, int Index);
}
