using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace HomeDeck.Api.Vacuum;

public sealed class DreameOptions
{
    /// <summary>Where the Python sidecar listens. Null leaves the vacuum simulated.</summary>
    public string? SidecarUrl { get; set; }
}

/// <summary>The real robot, reached through the sidecar that speaks its vendor's cloud.</summary>
public sealed class DreameVacuumProvider(HttpClient http, TimeProvider time) : IVacuumProvider
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public Task<VacuumState> ReadAsync(CancellationToken ct = default) =>
        CallAsync(HttpMethod.Get, "state", ct);

    public Task<VacuumState> StartAsync(CancellationToken ct = default) =>
        CallAsync(HttpMethod.Post, "start", ct);

    public Task<VacuumState> DockAsync(CancellationToken ct = default) =>
        CallAsync(HttpMethod.Post, "dock", ct);

    private async Task<VacuumState> CallAsync(HttpMethod method, string path, CancellationToken ct)
    {
        try
        {
            using var response = await http.SendAsync(new HttpRequestMessage(method, path), ct);

            // 503 is the sidecar saying the cloud or the robot was silent. That is a state to
            // show, not an exception to throw.
            if (response.StatusCode == HttpStatusCode.ServiceUnavailable)
                return Unknown();

            response.EnsureSuccessStatusCode();

            var reading = await response.Content.ReadFromJsonAsync<Reading>(Json, ct);
            return reading is null ? Unknown() : Map(reading);
        }
        catch (Exception failure) when (failure is HttpRequestException or TaskCanceledException)
        {
            // A separate process that can be down while the rest of the house is fine.
            return Unknown();
        }
    }

    private VacuumState Map(Reading reading) => new(
        Name: "Robot vacuum",
        Activity: Enum.TryParse<VacuumActivity>(reading.Activity, ignoreCase: true, out var activity)
            ? activity
            : VacuumActivity.Unknown,
        BatteryPercent: reading.BatteryPercent,
        IsSimulated: false,
        UpdatedAt: time.GetUtcNow());

    private VacuumState Unknown() => new(
        Name: "Robot vacuum",
        Activity: VacuumActivity.Unknown,
        BatteryPercent: null,
        IsSimulated: false,
        UpdatedAt: time.GetUtcNow());

    private sealed record Reading(
        string Activity,
        int? BatteryPercent,
        [property: JsonPropertyName("raw")] string? Raw);
}
