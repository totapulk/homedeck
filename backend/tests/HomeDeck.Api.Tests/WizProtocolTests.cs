using System.Text;
using HomeDeck.Api.Lights;
using HomeDeck.Api.Lights.Wiz;

namespace HomeDeck.Api.Tests;

/// <summary>
/// The protocol layer is pure, so these run without a bulb, a socket or a running host.
/// That is the whole reason the UDP I/O lives somewhere else.
/// </summary>
public class WizProtocolTests
{
    // Captured from a real bulb during discovery, with only the MAC swapped for one of the
    // addresses RFC 7042 reserves for documentation.
    private const string RealGetPilotReply =
        """{"method":"getPilot","env":"pro","result":{"mac":"00005e005301","rssi":-41,"state":true,"sceneId":11,"temp":2700,"dimming":80}}""";

    [Fact]
    public void SetPilot_maps_brightness_to_dimming_and_implies_on()
    {
        var json = WizProtocol.SetPilot(new LightCommand { Brightness = 60 });

        Assert.Equal("""{"method":"setPilot","params":{"state":true,"dimming":60}}""", json);
    }

    [Fact]
    public void SetPilot_treats_zero_brightness_as_off()
    {
        // The bulb has no "0% and still on" state, so the intent has to become state:false.
        var json = WizProtocol.SetPilot(new LightCommand { Brightness = 0 });

        Assert.Equal("""{"method":"setPilot","params":{"state":false}}""", json);
    }

    [Theory]
    [InlineData(1, 10)]   // WiZ rejects dimming below 10
    [InlineData(10, 10)]
    [InlineData(150, 100)]
    public void SetPilot_clamps_dimming_into_the_range_the_bulb_accepts(int brightness, int expectedDimming)
    {
        var json = WizProtocol.SetPilot(new LightCommand { Brightness = brightness });

        Assert.Contains($"\"dimming\":{expectedDimming}", json);
    }

    [Fact]
    public void SetPilot_refuses_a_command_that_still_carries_a_delta()
    {
        // Relative changes must be resolved against current state before reaching the wire;
        // silently dropping one would make a knob turn do nothing at all.
        var command = new LightCommand { BrightnessDelta = -5 };

        Assert.Throws<ArgumentException>(() => WizProtocol.SetPilot(command));
    }

    [Fact]
    public void ParsePilot_reads_a_real_bulb_reply()
    {
        var snapshot = WizProtocol.ParsePilot(Encoding.UTF8.GetBytes(RealGetPilotReply));

        Assert.NotNull(snapshot);
        Assert.Equal("00005e005301", snapshot.DeviceId);
        Assert.True(snapshot.IsOn);
        Assert.Equal(80, snapshot.Brightness);
        Assert.Equal(2700, snapshot.ColorTempK);
    }

    [Fact]
    public void ParsePilot_reports_zero_brightness_for_a_light_that_is_off()
    {
        // A bulb keeps its last dimming value while off; HomeDeck reports what the room looks like.
        var reply = """{"method":"getPilot","result":{"mac":"00005e005302","state":false,"temp":2700,"dimming":53}}""";

        var snapshot = WizProtocol.ParsePilot(Encoding.UTF8.GetBytes(reply));

        Assert.NotNull(snapshot);
        Assert.False(snapshot.IsOn);
        Assert.Equal(0, snapshot.Brightness);
    }

    [Theory]
    [InlineData("not json at all")]
    [InlineData("""{"method":"setPilot","result":{"success":true}}""")] // no mac, so no light to identify
    [InlineData("""{"method":"getPilot","error":{"code":-32700}}""")]
    public void ParsePilot_returns_null_instead_of_throwing_on_unusable_payloads(string payload)
    {
        // Anything on the network can send a UDP packet to this port; a stray one
        // must not take down a light refresh.
        Assert.Null(WizProtocol.ParsePilot(Encoding.UTF8.GetBytes(payload)));
    }
}
