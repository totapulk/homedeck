namespace HomeDeck.Api.Lights;

public static class LightEndpoints
{
    public static RouteGroupBuilder MapLightEndpoints(this IEndpointRouteBuilder app)
    {
        var lights = app.MapGroup("/api/lights").WithTags("Lights");

        lights.MapGet("/", (LightRegistry registry) => registry.All)
            .WithSummary("Last confirmed state of every known light.");

        lights.MapGet("/{id}", (string id, LightRegistry registry) =>
                registry.Get(id) is { } light ? Results.Ok(light) : Results.NotFound())
            .WithSummary("Last confirmed state of one light.");

        lights.MapPost("/{id}/state", async (
            string id, LightCommand command, LightService service, CancellationToken ct) =>
        {
            if (Validate(command) is { } error)
                return Results.ValidationProblem(error);

            var light = await service.ApplyAsync(id, command, ct);
            if (light is null) return Results.NotFound();

            // An unreachable light is not a client error: the request was fine, the bulb was not.
            return light.IsReachable
                ? Results.Ok(light)
                : Results.Json(light, statusCode: StatusCodes.Status503ServiceUnavailable);
        })
            .WithSummary("Changes one light. Accepts absolute values or a relative brightness delta.");

        lights.MapPost("/refresh", async (LightService service, CancellationToken ct) =>
                await service.RefreshAsync(ct))
            .WithSummary("Re-discovers lights on the network and refreshes state from the devices.");

        return lights;
    }

    private static Dictionary<string, string[]>? Validate(LightCommand command)
    {
        Dictionary<string, string[]> errors = [];

        if (command is { IsOn: null, Brightness: null, BrightnessDelta: null, ColorTempK: null })
            errors[""] = ["Command must change at least one property."];

        if (command is { Brightness: not null, BrightnessDelta: not null })
            errors[nameof(command.Brightness)] = ["Send either an absolute brightness or a delta, not both."];

        if (command.Brightness is < 0 or > 100)
            errors[nameof(command.Brightness)] = ["Brightness must be between 0 and 100."];

        if (command.BrightnessDelta is < -100 or > 100)
            errors[nameof(command.BrightnessDelta)] = ["Brightness delta must be between -100 and 100."];

        if (command.ColorTempK is < 2200 or > 6500)
            errors[nameof(command.ColorTempK)] = ["Colour temperature must be between 2200K and 6500K."];

        return errors.Count > 0 ? errors : null;
    }
}
