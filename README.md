# HomeDeck

[![CI](https://github.com/totapulk/homedeck/actions/workflows/ci.yml/badge.svg)](https://github.com/totapulk/homedeck/actions/workflows/ci.yml)

A small smart-home control system: a physical rotary knob (ESP32 + BLE) and a Flutter app
both drive the same lights, through one .NET backend that owns the truth about device state.

> Status: **work in progress.** See [Roadmap](#roadmap) for what is done and what is next.

## Architecture

```
[ESP32 + rotary encoder]  --BLE/GATT notify-->  [Flutter app (Android)]
                                                       |  REST + SignalR
                                                       v
[Flutter web build in a browser]  <--served by--  [ASP.NET Core backend]
                                                       |  UDP JSON (port 38899)
                                                       v
                                                  [WiZ smart bulbs]
```

Three ideas hold this together:

1. **The controller is deliberately dumb.** The ESP32 sends `ROTATE ±n` and `PRESS` — nothing
   else. It has no idea what a light, a room or a brightness level is. The app decides what an
   input means, the backend decides what the world is. Firmware never needs reflashing when
   the product changes.
2. **Relative events, not absolute values.** A rotary encoder emits deltas, so a knob can never
   fight a change made from the phone or the wall switch. (A potentiometer would have been
   absolute — and wrong.)
3. **One source of truth.** The backend confirms bulb state via WiZ `getPilot` and pushes it to
   every client over SignalR. Clients render optimistically and reconcile from those pushes.

## Repository layout

```
backend/    ASP.NET Core API + WiZ light provider (.NET 10)
  tools/
    WizProbe/   CLI used to reverse-check the WiZ UDP protocol from C#
app/        Flutter app — Android (BLE central + UI) and web (UI only)
firmware/   ESP32 rotary-encoder BLE peripheral (NimBLE-Arduino)
```

## WiZ protocol notes

Local control is plain JSON over UDP, port **38899**, no cloud account involved.

```jsonc
{"method":"getPilot","params":{}}                       // read state; broadcast = discovery
{"method":"setPilot","params":{"state":true}}           // on/off
{"method":"setPilot","params":{"dimming":30}}           // brightness, 10-100
{"method":"setPilot","params":{"temp":2700}}            // colour temperature, Kelvin
```

Broadcasting `getPilot` to `255.255.255.255:38899` makes every bulb on the subnet answer with
its own state — device discovery for free:

```
$ dotnet run --project backend/tools/WizProbe -- discover
192.168.0.220    {"method":"getPilot","env":"pro","result":{"mac":"...","state":true,"temp":2700,"dimming":80}}
```

## Roadmap

- [x] WiZ UDP protocol verified from C# (`WizProbe`: discover / get / on / off / dim)
- [x] ASP.NET Core API: `GET /api/lights`, `POST /api/lights/{id}/state`, background polling
- [x] SignalR hub for real-time state sync to all clients
- [ ] Scenes
- [ ] Flutter app: light list, on/off, brightness, colour temperature
- [ ] ESP32 firmware + BLE controller input → physical knob dims real bulbs
- [ ] Flutter web build served by the backend; deploy to Raspberry Pi
- [x] Unit tests for the pure backend logic, run in CI on every pull request
- [ ] Dreame robot vacuum integration, possibly a big button to press to activate the robot vacuum
- [ ] Cupra battery status (no official support on this, needs )


## Why this project

Want to experiment with bluetooth as well as Flutter and .NET. At the same time have a fun all-in-one integration for possible future smart home projects. Also it's nice to have a physical knob/switch, or a dashboard screen to adjust the stuff that normally requires you to reach for your phone to adjust lights etc.
