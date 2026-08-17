using System.Text.Json;
using HomeDeck.Api.Lights;
using HomeDeck.Api.Lights.Wiz;
using HomeDeck.Api.Realtime;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
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
app.MapHub<LightHub>("/hubs/lights");

app.Run();
