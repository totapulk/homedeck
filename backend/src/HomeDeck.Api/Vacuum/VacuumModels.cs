namespace HomeDeck.Api.Vacuum;

public enum VacuumActivity
{
    Unknown,
    Docked,
    Cleaning,
    Returning,
    Error,
}

public sealed record VacuumState(
    string Name,
    VacuumActivity Activity,
    int? BatteryPercent,
    bool IsSimulated,
    DateTimeOffset UpdatedAt);

/// <summary>
/// A robot vacuum HomeDeck can reach. The seam matters here because the vendor disables the
/// local API on cloud-paired models, so the real implementation goes out through a sidecar
/// rather than straight at the device like <see cref="Lights.ILightProvider"/> does.
/// </summary>
public interface IVacuumProvider
{
    Task<VacuumState> ReadAsync(CancellationToken ct = default);

    /// <summary>Starts a run with whatever settings the vendor's app last configured.</summary>
    Task<VacuumState> StartAsync(CancellationToken ct = default);

    Task<VacuumState> DockAsync(CancellationToken ct = default);
}
