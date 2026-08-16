// WizProbe — a throwaway-sized CLI for talking to WiZ bulbs over the local UDP protocol.
// This exists to prove the protocol from C# before any of it is wrapped in a web API.
// Whatever is learned here becomes WizLightProvider in the backend.
//
//   dotnet run --project backend/tools/WizProbe -- discover
//   dotnet run --project backend/tools/WizProbe -- get   192.168.1.42
//   dotnet run --project backend/tools/WizProbe -- on    192.168.1.42
//   dotnet run --project backend/tools/WizProbe -- off   192.168.1.42
//   dotnet run --project backend/tools/WizProbe -- dim   192.168.1.42 40

using System.Net;
using System.Net.Sockets;
using System.Text;

const int WizPort = 38899;

if (args.Length == 0)
{
    Console.Error.WriteLine("usage: WizProbe <discover|get|on|off|dim> [ip] [value]");
    return 1;
}

switch (args[0].ToLowerInvariant())
{
    case "discover":
        await DiscoverAsync();
        return 0;

    case "get":
        return await SendAsync(args[1], """{"method":"getPilot","params":{}}""");

    case "on":
        return await SendAsync(args[1], """{"method":"setPilot","params":{"state":true}}""");

    case "off":
        return await SendAsync(args[1], """{"method":"setPilot","params":{"state":false}}""");

    case "dim":
        var dimming = Math.Clamp(int.Parse(args[2]), 10, 100); // WiZ rejects dimming < 10
        // $$$ raw string: {{{ }}} marks the interpolation, so JSON's own braces stay literal.
        return await SendAsync(args[1], $$$"""{"method":"setPilot","params":{"dimming":{{{dimming}}},"state":true}}""");

    default:
        Console.Error.WriteLine($"unknown command: {args[0]}");
        return 1;
}

// Sends one JSON command to a single bulb and waits for its reply.
// UdpClient is IDisposable, so `using` closes the socket even if the await throws.
async Task<int> SendAsync(string ip, string json)
{
    using var udp = new UdpClient();
    var payload = Encoding.UTF8.GetBytes(json);
    await udp.SendAsync(payload, payload.Length, ip, WizPort);

    Console.WriteLine($"-> {ip}  {json}");

    // No reply within a second means the bulb is off the network or the IP is wrong.
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(1));
    try
    {
        var reply = await udp.ReceiveAsync(timeout.Token);
        Console.WriteLine($"<- {reply.RemoteEndPoint.Address}  {Encoding.UTF8.GetString(reply.Buffer)}");
        return 0;
    }
    catch (OperationCanceledException)
    {
        Console.Error.WriteLine($"<- (no response from {ip} within 1s)");
        return 2;
    }
}

// Broadcasts getPilot to the whole subnet; every WiZ bulb answers with its own state,
// which doubles as device discovery — no cloud account, no mDNS, no config file.
async Task DiscoverAsync()
{
    using var udp = new UdpClient { EnableBroadcast = true };
    var payload = Encoding.UTF8.GetBytes("""{"method":"getPilot","params":{}}""");
    await udp.SendAsync(payload, payload.Length, new IPEndPoint(IPAddress.Broadcast, WizPort));

    Console.WriteLine("broadcast getPilot, listening 3s...\n");

    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
    var seen = new HashSet<IPAddress>();
    try
    {
        while (true)
        {
            var reply = await udp.ReceiveAsync(timeout.Token);
            if (seen.Add(reply.RemoteEndPoint.Address))
                Console.WriteLine($"{reply.RemoteEndPoint.Address,-16} {Encoding.UTF8.GetString(reply.Buffer)}");
        }
    }
    catch (OperationCanceledException)
    {
        Console.WriteLine($"\n{seen.Count} bulb(s) found.");
    }
}
