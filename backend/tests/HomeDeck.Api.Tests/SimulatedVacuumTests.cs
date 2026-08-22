using HomeDeck.Api.Vacuum;

namespace HomeDeck.Api.Tests;

/// <summary>
/// The stand-in robot, which is what the knob, the endpoint and the app are demonstrated
/// against — so its behaviour is the contract the real implementation has to honour.
/// </summary>
public class SimulatedVacuumTests
{
    private static readonly DateTimeOffset Start = new(2026, 8, 21, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task It_starts_out_on_its_dock()
    {
        var (vacuum, _) = NewVacuum();

        var state = await vacuum.ReadAsync();

        Assert.Equal(VacuumActivity.Docked, state.Activity);
        Assert.Equal(100, state.BatteryPercent);
    }

    [Fact]
    public async Task Pressing_go_sends_it_out()
    {
        var (vacuum, _) = NewVacuum();

        var state = await vacuum.StartAsync();

        Assert.Equal(VacuumActivity.Cleaning, state.Activity);
    }

    [Fact]
    public async Task Pressing_go_at_a_robot_already_going_does_not_start_it_over()
    {
        var (vacuum, clock) = NewVacuum();

        await vacuum.StartAsync();
        clock.Advance(SimulatedVacuumProvider.CleaningDuration - TimeSpan.FromMinutes(1));
        await vacuum.StartAsync();

        // Past the end of the *first* run: a restart would leave it still cleaning here.
        clock.Advance(TimeSpan.FromMinutes(1) + SimulatedVacuumProvider.ReturnDuration);

        Assert.Equal(VacuumActivity.Docked, (await vacuum.ReadAsync()).Activity);
    }

    [Fact]
    public async Task It_heads_home_when_the_run_is_done()
    {
        var (vacuum, clock) = NewVacuum();

        await vacuum.StartAsync();
        clock.Advance(SimulatedVacuumProvider.CleaningDuration);

        Assert.Equal(VacuumActivity.Returning, (await vacuum.ReadAsync()).Activity);
    }

    [Fact]
    public async Task Sending_it_home_early_still_takes_the_journey()
    {
        var (vacuum, clock) = NewVacuum();

        await vacuum.StartAsync();
        clock.Advance(TimeSpan.FromMinutes(1));

        // Docking mid-run is a trip across the floor, not a teleport.
        Assert.Equal(VacuumActivity.Returning, (await vacuum.DockAsync()).Activity);

        clock.Advance(SimulatedVacuumProvider.ReturnDuration);
        Assert.Equal(VacuumActivity.Docked, (await vacuum.ReadAsync()).Activity);
    }

    [Fact]
    public async Task Its_battery_drains_while_it_is_out()
    {
        var (vacuum, clock) = NewVacuum();

        await vacuum.StartAsync();
        clock.Advance(SimulatedVacuumProvider.CleaningDuration);

        Assert.True((await vacuum.ReadAsync()).BatteryPercent < 100);
    }

    [Fact]
    public async Task It_admits_to_being_a_simulation()
    {
        var (vacuum, _) = NewVacuum();

        // The card is labelled from this flag, so it must not silently go false.
        Assert.True((await vacuum.ReadAsync()).IsSimulated);
    }

    private static (SimulatedVacuumProvider Vacuum, FixedClock Clock) NewVacuum()
    {
        var clock = new FixedClock(Start);
        return (new SimulatedVacuumProvider(clock), clock);
    }

    /// <summary>A clock that only moves when a test says so.</summary>
    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        private DateTimeOffset _now = now;

        public override DateTimeOffset GetUtcNow() => _now;

        public void Advance(TimeSpan by) => _now += by;
    }
}
