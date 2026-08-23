namespace HomeDeck.Api.Fishing;

public static class FishingEndpoints
{
    public static RouteGroupBuilder MapFishingEndpoints(this IEndpointRouteBuilder app)
    {
        var fishing = app.MapGroup("/api/fishing").WithTags("Fishing");

        fishing.MapGet("/", async (IFishingProvider provider, CancellationToken ct) =>
                await provider.ReadAsync(ct))
            .WithSummary("Today's bite forecast for the configured lake.");

        return fishing;
    }
}
