using System.Text.Json;
using System.Text.Json.Serialization;
using HomeDeck.Api.Lights;
using HomeDeck.Api.Lights.Wiz;
using HomeDeck.Api.Realtime;
using HomeDeck.Api.Vacuum;

var builder = WebApplication.CreateBuilder(args);

// Naming your own bulbs should not mean committing a map of your home to a public repository,
// so the light names live in a file git ignores. Optional on purpose: without it the app still
// runs, it just calls every light by its device id.
builder.Configuration.AddJsonFile("appsettings.local.json", optional: true, reloadOnChange: true);

builder.Services.AddOpenApi();

// Enum names, not numbers: reordering a C# enum must not silently change what clients render.
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
builder.Services.Configure<HomeDeckOptions>(builder.Configuration.GetSection("HomeDeck"));

// TimeProvider is injected rather than calling DateTimeOffset.Now directly, so tests can
// control the clock instead of sleeping.
builder.Services.AddSingleton(TimeProvider.System);

// Singletons: the provider caches device addresses and the registry is the canonical state,
// both of which must outlive a single request.
builder.Services.AddSingleton<ILightProvider, WizLightProvider>();
builder.Services.AddSingleton<LightRegistry>();
builder.Services.AddSingleton<LightService>();
builder.Services.AddHostedService<LightPollingService>();

// No sidecar configured means a simulated robot, so the app and the knob work on a machine
// that has never seen a vacuum. See sidecar/README.md for why there is a sidecar at all.
builder.Services.Configure<DreameOptions>(builder.Configuration.GetSection("HomeDeck:Dreame"));

var sidecar = builder.Configuration["HomeDeck:Dreame:SidecarUrl"];
if (string.IsNullOrWhiteSpace(sidecar))
{
    builder.Services.AddSingleton<IVacuumProvider, SimulatedVacuumProvider>();
}
else
{
    builder.Services.AddHttpClient<IVacuumProvider, DreameVacuumProvider>(client =>
    {
        client.BaseAddress = new Uri(sidecar.TrimEnd('/') + "/");

        // A command here crosses the internet twice before the robot moves.
        client.Timeout = TimeSpan.FromSeconds(20);
    });
}

// Real-time push of confirmed state to every connected client.
builder.Services.AddSignalR()
    // Spelled out so hub payloads look exactly like the REST ones; a client should not need
    // two different casing rules for the same LightState.
    .AddJsonProtocol(o => o.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase);
builder.Services.AddHostedService<LightBroadcaster>();

// The Flutter web build is served from this same origin in production, but during development
// it runs on its own port — hence a LAN-wide open policy. There is no auth to protect anyway.
// The origin is reflected rather than answered with "*", because SignalR's browser clients send
// credentials by default and a wildcard origin makes the browser reject a credentialed request.
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .SetIsOriginAllowed(_ => true)
    .AllowCredentials()
    .AllowAnyHeader()
    .AllowAnyMethod()));

var app = builder.Build();

if (app.Environment.IsDevelopment())
    app.MapOpenApi();

app.UseCors();

// No HTTPS redirect: this is a LAN appliance reached by IP or homedeck.local, with no
// certificate that phones and browsers would accept anyway.
app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapLightEndpoints();
app.MapVacuumEndpoints();
app.MapHub<LightHub>("/hubs/lights");

app.Run();
