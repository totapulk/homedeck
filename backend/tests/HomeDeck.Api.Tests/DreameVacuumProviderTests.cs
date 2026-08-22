using System.Net;
using System.Text;
using HomeDeck.Api.Vacuum;

namespace HomeDeck.Api.Tests;

/// <summary>
/// The half of the integration that is ours: what the sidecar says, and what the API reports.
/// The cloud protocol belongs to the library behind the sidecar; how this backend copes when
/// that library fails does not.
/// </summary>
public class DreameVacuumProviderTests
{
    [Fact]
    public async Task It_reports_what_the_sidecar_saw()
    {
        var vacuum = Sidecar(HttpStatusCode.OK, """
            {"activity":"Cleaning","batteryPercent":63,"raw":"SWEEPING_AND_MOPPING"}
            """);

        var state = await vacuum.ReadAsync();

        Assert.Equal(VacuumActivity.Cleaning, state.Activity);
        Assert.Equal(63, state.BatteryPercent);
    }

    [Fact]
    public async Task A_real_robot_is_never_labelled_a_simulation()
    {
        var vacuum = Sidecar(HttpStatusCode.OK, """{"activity":"Docked","batteryPercent":100}""");

        Assert.False((await vacuum.ReadAsync()).IsSimulated);
    }

    [Fact]
    public async Task An_activity_this_backend_has_never_heard_of_is_unknown_rather_than_a_crash()
    {
        var vacuum = Sidecar(HttpStatusCode.OK, """{"activity":"Mopping","batteryPercent":50}""");

        // The robot has far more states than this API models, and the vendor adds more.
        Assert.Equal(VacuumActivity.Unknown, (await vacuum.ReadAsync()).Activity);
    }

    [Fact]
    public async Task A_robot_that_will_not_answer_is_a_state_and_not_an_error()
    {
        var vacuum = Sidecar(HttpStatusCode.ServiceUnavailable, """{"error":"cloud timed out"}""");

        var state = await vacuum.ReadAsync();

        Assert.Equal(VacuumActivity.Unknown, state.Activity);
        Assert.Null(state.BatteryPercent);
    }

    [Fact]
    public async Task A_sidecar_that_is_not_running_costs_the_vacuum_and_nothing_else()
    {
        var vacuum = new DreameVacuumProvider(
            new HttpClient(new RefusingHandler()) { BaseAddress = new Uri("http://localhost:5081/") },
            TimeProvider.System);

        // A separate process on a separate schedule; it must not throw out of a shared host.
        Assert.Equal(VacuumActivity.Unknown, (await vacuum.ReadAsync()).Activity);
    }

    [Fact]
    public async Task Starting_and_docking_go_to_the_endpoints_the_sidecar_serves()
    {
        var paths = new List<string>();
        var handler = new StubHandler(HttpStatusCode.OK, """{"activity":"Cleaning"}""", paths);
        var vacuum = new DreameVacuumProvider(
            new HttpClient(handler) { BaseAddress = new Uri("http://localhost:5081/") },
            TimeProvider.System);

        await vacuum.StartAsync();
        await vacuum.DockAsync();

        Assert.Equal(["POST /start", "POST /dock"], paths);
    }

    private static DreameVacuumProvider Sidecar(HttpStatusCode status, string body) =>
        new(
            new HttpClient(new StubHandler(status, body, [])) { BaseAddress = new Uri("http://localhost:5081/") },
            TimeProvider.System);

    private sealed class StubHandler(HttpStatusCode status, string body, List<string> paths)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken ct)
        {
            paths.Add($"{request.Method} {request.RequestUri!.AbsolutePath}");

            return Task.FromResult(new HttpResponseMessage(status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            });
        }
    }

    private sealed class RefusingHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken ct) =>
            throw new HttpRequestException("connection refused");
    }
}
