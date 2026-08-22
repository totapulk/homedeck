# Vacuum sidecar

A ~200-line HTTP service that starts one robot vacuum. HomeDeck's backend calls it through
`IVacuumProvider`; without it the vacuum is simulated and everything else still works.

## Why this exists at all

HomeDeck talks to WiZ bulbs directly, in C#, over local UDP — their protocol is open and
documented, and a command never leaves the flat.

The vacuum is the opposite case. On models paired to the vendor's own cloud app the **local API
is switched off and does not come back without a factory reset**, so a "start cleaning" command
travels from the Raspberry Pi in the living room, out to a data centre, and back down to a robot
three metres away. The login flow to get there is deliberately obfuscated, and the transport is
MQTT over TLS.

Reimplementing that in C# was the obvious first idea and the wrong one: it is days of work to
build, it is someone else's protocol to keep working afterwards, and the result breaks silently
on the day the vendor changes something. Instead this process uses
[Tasshack/dreame-vacuum](https://github.com/Tasshack/dreame-vacuum) (MIT), which already
maintains that protocol, and exposes exactly three endpoints to the rest of the system.

The trade is deliberate: one extra process and a Python dependency, in exchange for not owning
2,000 lines of reverse-engineered protocol. If the vendor breaks it, one process fails and the
lights carry on.

**No Home Assistant is involved.** The library ships inside a Home Assistant integration, but
the three modules used here import nothing from it.

## Setup

```bash
cd sidecar
python fetch_dreame.py               # pulls a pinned commit into vendor/ (git-ignored)
pip install -r requirements.txt
```

Credentials come from the environment, never from a file:

```bash
export DREAME_USERNAME='you@example.com'
export DREAME_PASSWORD='...'
export DREAME_COUNTRY=eu             # us, cn, … — must match the app's region
```

Check what the account can see before wiring anything up:

```bash
python homedeck_dreame.py --probe
```

That prints every robot on the account. **With more than one, `DREAME_DEVICE` is required** —
an account can hold robots that are not yours to command, and picking by list order would work
right up until the order changed:

```bash
export DREAME_DEVICE='-115626182'
```

Then run it:

```bash
python homedeck_dreame.py            # http://127.0.0.1:5081
```

and point the backend at it in `appsettings.local.json`:

```json
{ "HomeDeck": { "Dreame": { "SidecarUrl": "http://127.0.0.1:5081" } } }
```

Leave that section out and the backend falls back to `SimulatedVacuumProvider`.

## Endpoints

| | |
|---|---|
| `GET /state` | `{"activity":"Docked","batteryPercent":100,"raw":"CHARGING_COMPLETED"}` |
| `POST /start` | starts a run with whatever the vendor's app has configured |
| `POST /dock` | sends the robot home |

`activity` is one of `Docked`, `Cleaning`, `Returning`, `Error`, `Unknown` — the robot's own
state list is far longer, and `raw` carries it for when something needs explaining. A `503`
means the request was fine and the cloud or the robot was not.

## Notes

- **Binds to loopback by default.** This process holds cloud credentials and has no
  authentication of its own, so it should not be reachable from the LAN the way the backend is.
  `DREAME_BIND` can override that; think before you do.
- **Needs internet.** The bulbs do not. When the line goes down the lights keep working and the
  vacuum does not — which is the argument for local protocols, made by the house itself.
- **The upstream commit is pinned** in `fetch_dreame.py`. Floating on a branch would mean the
  vacuum stops working on a day nobody touched this repository.
- Only `protocol.py`, `types.py` and `exceptions.py` are fetched. The rest of the package
  contains a map decoder that needs Pillow, NumPy and a V8 JavaScript engine — none of which a
  button needs, and all of which a Raspberry Pi would rather not carry.
