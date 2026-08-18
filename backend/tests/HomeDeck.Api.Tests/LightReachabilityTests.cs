using HomeDeck.Api.Lights;
using Microsoft.Extensions.Options;

namespace HomeDeck.Api.Tests;

/// <summary>
/// Discovery is an unacknowledged UDP broadcast, so silence from a bulb is ordinary rather than
/// alarming. These pin down how much silence it takes before the UI is allowed to say so.
/// </summary>
public class LightReachabilityTests
{
    private const string DeviceId = "00005e005301";

    private static LightRegistry NewRegistry() =>
        new(new StaticOptionsMonitor(new HomeDeckOptions()), TimeProvider.System);

    private static LightRegistry RegistryKnowing(string deviceId)
    {
        var registry = NewRegistry();
        registry.Upsert(new LightSnapshot(deviceId, IsOn: true, Brightness: 50, ColorTempK: 2700));
        return registry;
    }

    [Fact]
    public void One_silent_poll_does_not_condemn_a_light()
    {
        var registry = RegistryKnowing(DeviceId);

        var light = registry.MarkMissing(DeviceId);

        Assert.True(light!.IsReachable);
    }

    [Fact]
    public void A_run_of_silent_polls_does()
    {
        var registry = RegistryKnowing(DeviceId);

        LightState? light = null;
        for (var poll = 0; poll < LightRegistry.MissesBeforeUnreachable; poll++)
            light = registry.MarkMissing(DeviceId);

        Assert.False(light!.IsReachable);
    }

    [Fact]
    public void A_single_reply_wipes_the_slate()
    {
        var registry = RegistryKnowing(DeviceId);

        registry.MarkMissing(DeviceId);
        registry.MarkMissing(DeviceId);
        registry.Upsert(new LightSnapshot(DeviceId, IsOn: true, Brightness: 50, ColorTempK: 2700));

        // The two earlier misses must not carry over, or a bulb on a lossy network would be
        // condemned by misses spread across minutes.
        Assert.True(registry.MarkMissing(DeviceId)!.IsReachable);
    }

    [Fact]
    public void Clients_hear_about_it_once_and_not_on_every_later_poll()
    {
        var registry = RegistryKnowing(DeviceId);

        var raised = 0;
        registry.Changed += _ => raised++;
        for (var poll = 0; poll < LightRegistry.MissesBeforeUnreachable + 3; poll++)
            registry.MarkMissing(DeviceId);

        Assert.Equal(1, raised);
    }

    [Fact]
    public void A_light_that_was_never_seen_is_not_invented()
    {
        Assert.Null(NewRegistry().MarkMissing("nosuchdevice"));
    }

    private sealed class StaticOptionsMonitor(HomeDeckOptions value) : IOptionsMonitor<HomeDeckOptions>
    {
        public HomeDeckOptions CurrentValue { get; } = value;
        public HomeDeckOptions Get(string? name) => CurrentValue;
        public IDisposable? OnChange(Action<HomeDeckOptions, string?> listener) => null;
    }
}
