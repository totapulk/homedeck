namespace HomeDeck.Api.Vacuum;

/// <summary>
/// A stand-in robot, used when no sidecar is configured. State is derived from a single
/// timestamp rather than advanced by a timer, which keeps it testable with a fake clock.
/// </summary>
public sealed class SimulatedVacuumProvider(TimeProvider time) : IVacuumProvider
{
    public static readonly TimeSpan CleaningDuration = TimeSpan.FromMinutes(4);
    public static readonly TimeSpan ReturnDuration = TimeSpan.FromSeconds(45);

    private readonly Lock _gate = new();
    private DateTimeOffset? _startedAt;

    public Task<VacuumState> ReadAsync(CancellationToken ct = default) =>
        Task.FromResult(Snapshot());

    public Task<VacuumState> StartAsync(CancellationToken ct = default)
    {
        lock (_gate)
        {
            // Pressing "go" at something already going restarts nothing; a real robot shrugs too.
            _startedAt ??= time.GetUtcNow();
        }

        return Task.FromResult(Snapshot());
    }

    public Task<VacuumState> DockAsync(CancellationToken ct = default)
    {
        lock (_gate)
        {
            // Rewind to where the return leg begins, so docking early still takes the journey.
            if (_startedAt is not null)
                _startedAt = time.GetUtcNow() - CleaningDuration;
        }

        return Task.FromResult(Snapshot());
    }

    private VacuumState Snapshot()
    {
        var now = time.GetUtcNow();

        DateTimeOffset? startedAt;
        lock (_gate)
        {
            if (_startedAt is { } started && now - started >= CleaningDuration + ReturnDuration)
                _startedAt = null;

            startedAt = _startedAt;
        }

        var elapsed = startedAt is { } start ? now - start : TimeSpan.Zero;
        var activity = startedAt is null
            ? VacuumActivity.Docked
            : elapsed < CleaningDuration
                ? VacuumActivity.Cleaning
                : VacuumActivity.Returning;

        return new VacuumState(
            Name: "Robot vacuum",
            Activity: activity,
            BatteryPercent: Battery(activity, elapsed),
            IsSimulated: true,
            UpdatedAt: now);
    }

    private static int Battery(VacuumActivity activity, TimeSpan elapsed)
    {
        if (activity == VacuumActivity.Docked) return 100;

        var spent = elapsed / (CleaningDuration + ReturnDuration);
        return Math.Clamp((int)Math.Round(100 - spent * 35), 1, 100);
    }
}
