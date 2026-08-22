# HomeDeck

[![CI](https://github.com/totapulk/homedeck/actions/workflows/ci.yml/badge.svg)](https://github.com/totapulk/homedeck/actions/workflows/ci.yml)

Smart-home control for one flat: a physical rotary knob, a phone app, and any browser on the
local network, all driving the same devices through one backend that holds the current state.

The knob is an ESP32 that reports two things — a control was turned, a control was pressed — and
knows nothing else. What an event means is decided in the app. That is why the same three-byte
notification dims WiZ bulbs over local UDP and starts a robot vacuum reachable only through its
manufacturer's cloud.

Two knobs on one board is a proof of concept. The intended shape is several controls around the
flat with their assignments editable rather than compiled in. See
[Where this is going](#where-this-is-going).

## Architecture

```
[ESP32 + two rotary encoders]
             |
             |  BLE/GATT notify: [control, event, delta]
             v
    [Flutter app (Android)]
             |
             |  REST + SignalR
             v
   [ASP.NET Core backend] ---- serves the Flutter web build ----> [any browser on the LAN]
        |            \
        |             \  HTTP on loopback
   UDP  |              v
 :38899 |        [Python sidecar]
        |               |  MQTT over TLS
        v               v
   [WiZ bulbs]   [vendor cloud] ---> [robot vacuum]
```

- **The controller is dumb.** No concept of a light, a room or a vacuum in the firmware.
  Changing what a knob does is a change to one class in the app, with nothing to reflash.
- **Relative events, not absolute values.** Encoders send deltas, so a knob cannot fight a
  change made from the phone or the wall switch. A potentiometer would have.
- **One source of truth.** The backend confirms bulb state with `getPilot` and pushes it to
  every client over SignalR. Clients render optimistically and reconcile from those pushes.
- **Vendors stay behind interfaces.** `ILightProvider` and `IVacuumProvider` are all the rest of
  the backend sees, which is why the vacuum also has a working simulated implementation.

## Layout

```
backend/    ASP.NET Core API, WiZ light provider, SignalR hub (.NET 10)
  tools/WizProbe/   CLI used to work out the WiZ UDP protocol from C#
app/        Flutter app — Android (BLE central + UI) and web (UI only)
firmware/   ESP32 rotary-encoder BLE peripheral (NimBLE-Arduino, PlatformIO)
sidecar/    Small Python service, the only way to reach the vacuum
scripts/    Build the web app into the backend's static root
```

The last three have their own READMEs: GATT contract and wiring in `firmware/knob/`, the cloud
problem in `sidecar/`.

## Running it

```
dotnet run --project backend/src/HomeDeck.Api        # http://0.0.0.0:5080

cd app
flutter run --dart-define=HOMEDECK_API=http://192.168.1.23:5080
```

The backend binds every interface so a phone can reach it. A native build has no way to guess
that address and must be told.

The browser version needs no address, because the backend serves it:

```
scripts/build-web.sh
```

That builds into `backend/src/HomeDeck.Api/wwwroot`, after which `http://<the machine>:5080` is
the whole UI on any device on the network. The page asks the origin it was loaded from, so
there is nothing to configure and nothing to rebuild when the address changes.

Both the knob and the vacuum are optional. Without a board, the app has an on-screen pad that
emits identical events; without a sidecar, the backend serves a simulated robot that docks,
cleans and drains a battery on a timer.

## Lights: WiZ over UDP

Plain JSON on port **38899**, no cloud account, nothing leaves the flat.

```jsonc
{"method":"getPilot","params":{}}                       // read state; broadcast = discovery
{"method":"setPilot","params":{"state":true}}           // on/off
{"method":"setPilot","params":{"dimming":30}}           // brightness, 10-100
{"method":"setPilot","params":{"temp":2700}}            // colour temperature, Kelvin
```

Broadcasting `getPilot` to `255.255.255.255:38899` makes every bulb answer with its own state,
which is discovery for free:

```
$ dotnet run --project backend/tools/WizProbe -- discover
192.168.1.23    {"method":"getPilot","result":{"mac":"...","state":true,"dimming":80}}
```

`WizProbe` predates the backend and is still the quickest way to tell whether the bulb is
ignoring you or the backend is.

## Vacuum: cloud only

On models paired to the manufacturer's app the local API is switched off and does not come back
without a factory reset, so "start cleaning" travels to a data centre and back to a robot three
metres away. The login is obfuscated and the transport is MQTT over TLS.

Reimplementing that in C# would have been days of work and someone else's protocol to maintain.
Instead a ~200-line Python process wraps a library that already tracks it and exposes three
endpoints; the backend sees only `IVacuumProvider`. When the connection drops the lights keep
working and the vacuum does not.

## Configuration

Bulb names map MAC addresses to rooms, which is a fact about one home rather than about this
software. It lives in `appsettings.local.json`, which git ignores:

```
cp backend/src/HomeDeck.Api/appsettings.local.template.json \
   backend/src/HomeDeck.Api/appsettings.local.json
```

Optional — without it every bulb still appears, named after its device id. Vacuum credentials
are environment variables read by the sidecar, so they are in no file here.

## Tests

100 tests in CI on every pull request, 44 backend and 56 app: the WiZ payload builder, encoder
deltas to brightness intents, reconciliation between optimistic UI and backend pushes, and the
vacuum provider when the sidecar is unreachable. `ControllerInput` and `IVacuumProvider` have
test implementations, so nothing needs a radio, a bulb or a cloud account.

## Where this is going

Several controls around the flat, all running the same firmware, and a screen for saying which
one does what. Three things are in the way, and none of them is the firmware:

- **Addressing.** A control is identified by its index on one board. More boards need a device
  id alongside it, to tell knob 0 by the door from knob 0 on the desk.
- **The mapping is code.** It is a map literal in `app/lib/main.dart`. It should be data: stored
  in the backend, edited from the UI, changed without a rebuild. `ControlTarget` is a two-method
  interface, so this is a data-modelling problem rather than an architectural one.
- **Range and power.** One phone can hold several connections, but that makes the phone the
  thing which has to be home and charged. A mains-powered hub is the better central, and enough
  controls make a mesh more sensible than a star.

An IKEA Zigbee remote is the next test of the idea: it should drop in as another
`ControllerInput` and change nothing above it.

## Roadmap

- [x] WiZ UDP protocol worked out from C# (`WizProbe`: discover / get / on / off / dim)
- [x] ASP.NET Core API, background polling, SignalR hub
- [x] Flutter app: light list, grouping by room and fixture, on/off, brightness
- [x] ESP32 firmware and BLE controller input — the knob dims real bulbs
- [x] Robot vacuum: a knob press starts it, via a sidecar and the vendor's cloud
- [x] Unit tests in CI on every pull request
- [x] Flutter web build served by the backend, on one origin with the API
- [ ] Colour temperature as a control, not only a readout
- [ ] Scenes
- [ ] Deploy to a Raspberry Pi and a wall-mounted tablet
- [ ] Car battery status, if it can be done politely — there is no official API

## Notes

Flutter, .NET and ESP32 BLE were all new here and much of this was written with AI assistance.
Two things kept that honest: the tests, and reading dependencies before running them. The
vendored Dreame client turned out to contain Google Analytics calls reporting a hash of the
device MAC, in a function this project never reaches. It is pinned to a commit hash.

A physical knob does turn out to be nicer than reaching for a phone
