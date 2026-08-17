using HomeDeck.Api.Lights;
using Microsoft.Extensions.Options;

namespace HomeDeck.Api.Tests;

/// <summary>
/// The registry's change event is what SignalR pushes to clients, so "did it fire, and was it
/// right to fire" is the contract worth pinning down.
/// </summary>
public class LightRegistryTests
{
    private static LightRegistry NewRegistry(params (string Id, string Name, string Room)[] naming)
    {
        var options = new HomeDeckOptions
        {
            Lights = naming.ToDictionary(n => n.Id, n => new LightNaming { Name = n.Name, Room = n.Room }),
        };

        return new LightRegistry(new StaticOptionsMonitor<HomeDeckOptions>(options), TimeProvider.System);
    }

    private static LightSnapshot Snapshot(bool isOn = true, int brightness = 50, int? tempK = 2700) =>
        new("444f8eb4a92e", isOn, brightness, tempK);

    [Fact]
    public void Upsert_raises_Changed_the_first_time_a_light_is_seen()
    {
        var registry = NewRegistry();
        var raised = new List<LightState>();
        registry.Changed += raised.Add;

        registry.Upsert(Snapshot());

        var light = Assert.Single(raised);
        Assert.Equal("444f8eb4a92e", light.Id);
        Assert.True(light.IsReachable);
    }

    [Fact]
    public void Upsert_stays_quiet_when_a_poll_finds_nothing_new()
    {
        var registry = NewRegistry();
        registry.Upsert(Snapshot());

        var raised = 0;
        registry.Changed += _ => raised++;
        registry.Upsert(Snapshot());

        // Only the timestamp moved. Waking every connected client for that would make the
        // ten-second poll a permanent source of traffic.
        Assert.Equal(0, raised);
    }

    [Fact]
    public void Upsert_raises_Changed_when_brightness_moves()
    {
        var registry = NewRegistry();
        registry.Upsert(Snapshot(brightness: 50));

        var raised = new List<LightState>();
        registry.Changed += raised.Add;
        registry.Upsert(Snapshot(brightness: 80));

        Assert.Equal(80, Assert.Single(raised).Brightness);
    }

    [Fact]
    public void MarkUnreachable_raises_Changed_once_and_then_stays_quiet()
    {
        var registry = NewRegistry();
        registry.Upsert(Snapshot());

        var raised = 0;
        registry.Changed += _ => raised++;
        registry.MarkUnreachable("444f8eb4a92e");
        registry.MarkUnreachable("444f8eb4a92e");

        // A bulb that is still offline on the next poll is not news.
        Assert.Equal(1, raised);
    }

    [Fact]
    public void MarkUnreachable_ignores_a_light_that_was_never_seen()
    {
        var registry = NewRegistry();
        var raised = 0;
        registry.Changed += _ => raised++;

        Assert.Null(registry.MarkUnreachable("nosuchdevice"));
        Assert.Equal(0, raised);
    }

    [Fact]
    public void Configured_naming_wins_over_the_generated_fallback()
    {
        var registry = NewRegistry(("444f8eb4a92e", "Reading lamp", "Living room"));

        var light = registry.Upsert(Snapshot());

        Assert.Equal("Reading lamp", light.Name);
        Assert.Equal("Living room", light.Room);
    }

    [Fact]
    public void An_unlisted_light_is_named_after_its_device_id()
    {
        var registry = NewRegistry();

        var light = registry.Upsert(Snapshot());

        // Unnamed bulbs still have to be tellable apart in the UI.
        Assert.Equal("Light A92E", light.Name);
        Assert.Equal("Unassigned", light.Room);
    }

    /// <summary>Minimal IOptionsMonitor stand-in: the registry only ever reads CurrentValue.</summary>
    private sealed class StaticOptionsMonitor<T>(T value) : IOptionsMonitor<T>
    {
        public T CurrentValue { get; } = value;
        public T Get(string? name) => CurrentValue;
        public IDisposable? OnChange(Action<T, string?> listener) => null;
    }
}
