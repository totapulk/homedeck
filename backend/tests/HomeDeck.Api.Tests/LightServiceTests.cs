using HomeDeck.Api.Lights;

namespace HomeDeck.Api.Tests;

/// <summary>
/// Covers the rotary encoder's half of the contract: a relative nudge turned into an
/// absolute command against the last state the backend confirmed.
/// </summary>
public class LightServiceTests
{
    private static LightState LightAt(int brightness, bool isOn = true) => new(
        Id: "00005e005301",
        Name: "Desk",
        Room: "Office",
        Fixture: null,
        IsOn: isOn,
        Brightness: brightness,
        ColorTempK: 2700,
        IsReachable: true,
        UpdatedAt: DateTimeOffset.UnixEpoch);

    [Fact]
    public void Resolve_applies_a_delta_to_the_current_brightness()
    {
        var resolved = LightService.Resolve(new LightCommand { BrightnessDelta = -20 }, LightAt(80));

        Assert.Equal(60, resolved.Brightness);
        Assert.Null(resolved.BrightnessDelta);
    }

    [Theory]
    [InlineData(95, 20, 100)]
    [InlineData(10, -50, 0)]
    public void Resolve_clamps_to_the_ends_of_the_scale(int current, int delta, int expected)
    {
        // Ten detents past the top must still leave the light at 100, not at 300.
        var resolved = LightService.Resolve(new LightCommand { BrightnessDelta = delta }, LightAt(current));

        Assert.Equal(expected, resolved.Brightness);
    }

    [Fact]
    public void Resolve_turns_a_light_back_on_when_the_knob_is_raised_from_zero()
    {
        var resolved = LightService.Resolve(new LightCommand { BrightnessDelta = 10 }, LightAt(0, isOn: false));

        Assert.True(resolved.IsOn);
        Assert.Equal(10, resolved.Brightness);
    }

    [Fact]
    public void Resolve_turns_a_light_off_when_the_knob_reaches_zero()
    {
        // Winding the knob all the way down is how you switch a light off without a button.
        var resolved = LightService.Resolve(new LightCommand { BrightnessDelta = -30 }, LightAt(20));

        Assert.False(resolved.IsOn);
        Assert.Equal(0, resolved.Brightness);
    }

    [Fact]
    public void Resolve_leaves_absolute_commands_untouched()
    {
        var command = new LightCommand { Brightness = 40, ColorTempK = 4000 };

        Assert.Same(command, LightService.Resolve(command, LightAt(80)));
    }
}
