using System.Net;
using System.Text;
using HomeDeck.Api.Fishing;
using Microsoft.Extensions.Options;

namespace HomeDeck.Api.Tests;

/// <summary>
/// The bite index is Kala Ukko's to compute and Kala Ukko's to test. What belongs here is what
/// this backend does with the answer, and what it does when there is no answer.
/// </summary>
public class KalaUkkoFishingProviderTests
{
    private const string Body = """
        {
          "lake": {"name":"Jyväsjärvi","lat":62.235,"lon":25.77},
          "weather": {"airTempC":18.6,"windMs":3,"pressureHpa":1006,
                      "pressureTrend":"hitaasti_laskeva","cloud":"pilvinen"},
          "water": {"tempC":17,"source":"syke"},
          "species": [
            {"id":"ahven","name":"Ahven","emoji":"🐠","index":79},
            {"id":"hauki","name":"Hauki","emoji":"🐊","index":58}
          ],
          "comment": "Ukko nyökkäilee."
        }
        """;

    [Fact]
    public async Task It_reports_the_forecast_it_was_given()
    {
        var state = await Ukko(HttpStatusCode.OK, Body).ReadAsync();

        Assert.True(state.IsAvailable);
        Assert.Equal("Jyväsjärvi", state.LakeName);
        Assert.Equal("Ukko nyökkäilee.", state.Comment);
        Assert.Equal(17, state.Weather!.WaterTempC);
    }

    [Fact]
    public async Task The_best_species_is_the_first_one_listed()
    {
        // Kala Ukko sorts them; re-sorting here would be a second opinion nobody asked for.
        var state = await Ukko(HttpStatusCode.OK, Body).ReadAsync();

        Assert.Equal("ahven", state.Best!.Id);
        Assert.Equal(79, state.Best.Index);
        Assert.Equal(2, state.Species.Count);
    }

    [Fact]
    public async Task A_lake_that_was_never_configured_is_unavailable_rather_than_a_guess()
    {
        var provider = new KalaUkkoFishingProvider(
            new HttpClient(new StubHandler(HttpStatusCode.OK, Body)),
            Options(new KalaUkkoOptions()),
            TimeProvider.System);

        var state = await provider.ReadAsync();

        Assert.False(state.IsAvailable);
        Assert.Empty(state.Species);
    }

    [Fact]
    public async Task A_site_that_is_down_costs_the_fishing_card_and_nothing_else()
    {
        var provider = new KalaUkkoFishingProvider(
            new HttpClient(new RefusingHandler()) { BaseAddress = new Uri("https://kalaukko.com/") },
            Options(Configured),
            TimeProvider.System);

        // Someone else's server on the far side of the internet. The lights do not care.
        Assert.False((await provider.ReadAsync()).IsAvailable);
    }

    [Fact]
    public async Task Nonsense_from_the_far_end_is_unavailable_rather_than_an_exception()
    {
        var state = await Ukko(HttpStatusCode.OK, "<html>502 Bad Gateway</html>").ReadAsync();

        Assert.False(state.IsAvailable);
    }

    [Fact]
    public async Task The_lake_is_asked_for_by_coordinate()
    {
        var requests = new List<string>();
        var provider = new KalaUkkoFishingProvider(
            new HttpClient(new StubHandler(HttpStatusCode.OK, Body, requests))
            {
                BaseAddress = new Uri("https://kalaukko.com/"),
            },
            Options(Configured),
            TimeProvider.System);

        await provider.ReadAsync();

        // Invariant culture: a Finnish decimal comma here would be a different lake.
        Assert.Contains("lat=62.235", requests[0]);
        Assert.Contains("lon=25.77", requests[0]);
    }

    [Fact]
    public async Task Several_clients_asking_at_once_is_still_one_request_out()
    {
        var requests = new List<string>();
        var clock = new FixedFishingClock(DateTimeOffset.Parse("2026-08-22T12:00:00Z"));
        var provider = new KalaUkkoFishingProvider(
            new HttpClient(new StubHandler(HttpStatusCode.OK, Body, requests))
            {
                BaseAddress = new Uri("https://kalaukko.com/"),
            },
            Options(Configured),
            clock);

        await provider.ReadAsync();
        await provider.ReadAsync();
        clock.Advance(TimeSpan.FromMinutes(5));
        await provider.ReadAsync();

        Assert.Single(requests);
    }

    [Fact]
    public async Task A_forecast_older_than_the_weather_behind_it_is_fetched_again()
    {
        var requests = new List<string>();
        var clock = new FixedFishingClock(DateTimeOffset.Parse("2026-08-22T12:00:00Z"));
        var provider = new KalaUkkoFishingProvider(
            new HttpClient(new StubHandler(HttpStatusCode.OK, Body, requests))
            {
                BaseAddress = new Uri("https://kalaukko.com/"),
            },
            Options(Configured),
            clock);

        await provider.ReadAsync();
        clock.Advance(TimeSpan.FromMinutes(11));
        await provider.ReadAsync();

        Assert.Equal(2, requests.Count);
    }

    private static KalaUkkoOptions Configured => new()
    {
        BaseUrl = "https://kalaukko.com",
        LakeName = "Jyväsjärvi",
        Lat = 62.235,
        Lon = 25.77,
    };

    private static KalaUkkoFishingProvider Ukko(HttpStatusCode status, string body) =>
        new(
            new HttpClient(new StubHandler(status, body)) { BaseAddress = new Uri("https://kalaukko.com/") },
            Options(Configured),
            TimeProvider.System);

    private static IOptionsMonitor<KalaUkkoOptions> Options(KalaUkkoOptions value) =>
        new StaticOptions(value);

    private sealed class StaticOptions(KalaUkkoOptions value) : IOptionsMonitor<KalaUkkoOptions>
    {
        public KalaUkkoOptions CurrentValue => value;

        public KalaUkkoOptions Get(string? name) => value;

        public IDisposable? OnChange(Action<KalaUkkoOptions, string?> listener) => null;
    }

    private sealed class StubHandler(HttpStatusCode status, string body, List<string>? requests = null)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken ct)
        {
            requests?.Add(request.RequestUri!.PathAndQuery);

            return Task.FromResult(new HttpResponseMessage(status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            });
        }
    }

    private sealed class RefusingHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken ct) =>
            throw new HttpRequestException("no route to host");
    }

    private sealed class FixedFishingClock(DateTimeOffset now) : TimeProvider
    {
        private DateTimeOffset _now = now;

        public override DateTimeOffset GetUtcNow() => _now;

        public void Advance(TimeSpan by) => _now += by;
    }
}
