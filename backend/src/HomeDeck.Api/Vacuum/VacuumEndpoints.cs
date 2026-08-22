namespace HomeDeck.Api.Vacuum;

public static class VacuumEndpoints
{
    public static RouteGroupBuilder MapVacuumEndpoints(this IEndpointRouteBuilder app)
    {
        var vacuum = app.MapGroup("/api/vacuum").WithTags("Vacuum");

        vacuum.MapGet("/", async (IVacuumProvider provider, CancellationToken ct) =>
                await provider.ReadAsync(ct))
            .WithSummary("Current state of the robot vacuum.");

        vacuum.MapPost("/start", async (IVacuumProvider provider, CancellationToken ct) =>
                await provider.StartAsync(ct))
            .WithSummary("Starts a cleaning run with the settings configured in the vendor's app.");

        vacuum.MapPost("/dock", async (IVacuumProvider provider, CancellationToken ct) =>
                await provider.DockAsync(ct))
            .WithSummary("Sends the robot back to its dock.");

        return vacuum;
    }
}
