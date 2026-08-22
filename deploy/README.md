# Deploying to a Raspberry Pi

The target is a Raspberry Pi 3B running **Raspberry Pi OS Lite, 64-bit**, on ethernet. The
bulbs are discovered by UDP broadcast, so the Pi has to sit on the same subnet as them.

Give the Pi a DHCP reservation in the router. `homedeck.local` works through avahi, which
Raspberry Pi OS runs by default, but a stable address is worth having when it does not.

## The backend

```
deploy/deploy.sh                      # tommi@homedeck.local
deploy/deploy.sh pi@192.168.1.50      # or wherever it lives
```

That builds the web UI, publishes self-contained for `linux-arm64`, copies the result to
`/opt/homedeck`, installs the systemd unit and waits for `/health` to answer.

Self-contained means **no .NET on the Pi**: the runtime travels in the package, so it cannot
drift from the one the code was tested against. The cost is around 130 MB per deploy, plus the
web build.

The service listens on **port 80**, so the wall tablet opens `http://homedeck.local` with no
port to remember. It still runs as an ordinary user; `AmbientCapabilities=CAP_NET_BIND_SERVICE`
grants the one privilege that needs.

`appsettings.local.json` is picked up by `dotnet publish` automatically and travels with the
rest, so light names and rooms need no separate step. That also means a published package
contains the layout of one particular home, which is worth remembering before handing one to
anybody.

```
ssh tommi@homedeck.local journalctl -u homedeck-api -f
```

## Keeping it alive

Deploying again is just `deploy/deploy.sh`. Because the publish is self-contained, a .NET
update travels with it, so there is no runtime on the Pi to forget about. The OS wants
`sudo apt update && sudo apt full-upgrade` now and then, and that is the whole maintenance story.

What actually kills these machines is memory card wear, and the busiest writer is the journal.
Capping it costs nothing:

```
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/homedeck.conf >/dev/null <<'EOF'
[Journal]
SystemMaxUse=50M
EOF
sudo systemctl restart systemd-journald
```

Nothing here is irreplaceable. The lights are rediscovered on every start, the light names live
in this repository, and the only thing on the Pi that exists nowhere else is
`/etc/homedeck/dreame.env` — four lines you can retype. A dead card means flashing a new one and
running the deploy script, not recovering anything.

## The vacuum sidecar

Installed by hand, because it holds cloud credentials and those should not pass through a
script that also does eleven other things.

```
sudo apt install -y git python3-venv
sudo mkdir -p /opt/homedeck-sidecar && sudo chown "$USER" /opt/homedeck-sidecar
```

Copy `sidecar/` across, then on the Pi:

```
cd /opt/homedeck-sidecar
python3 fetch_dreame.py
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

`pip install` is the step that can go wrong here: `python-miio` pulls in `cryptography`, which
has Rust in it. On 64-bit Raspberry Pi OS there should be a prebuilt `aarch64` wheel and nothing
gets compiled. If it starts building from source, stop it — a Pi 3 will be there a long time and
may run out of memory. `MiIOProtocol` is only the base class of the *local* device protocol,
which this project never uses, so a small stub would satisfy the import.

Credentials go in a file only root and the service user can read:

```
sudo mkdir -p /etc/homedeck
sudo tee /etc/homedeck/dreame.env >/dev/null <<'EOF'
DREAME_USERNAME=you@example.com
DREAME_PASSWORD=...
DREAME_COUNTRY=eu
DREAME_DEVICE=-115626182
EOF
sudo chmod 600 /etc/homedeck/dreame.env
```

Check the account before wiring it up, which also prints the device ids:

```
DREAME_USERNAME=... DREAME_PASSWORD=... .venv/bin/python homedeck_dreame.py --probe
```

Then install the unit:

```
sed "s/%DEPLOY_USER%/$USER/" deploy/homedeck-dreame.service | \
  sudo tee /etc/systemd/system/homedeck-dreame.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now homedeck-dreame
```

The sidecar binds `127.0.0.1` and the backend reaches it there, so nothing on the network can
talk to it. Point the backend at it in `appsettings.local.json`:

```json
{ "HomeDeck": { "Dreame": { "SidecarUrl": "http://127.0.0.1:5081" } } }
```

Leave that section out and the backend serves a simulated robot instead, which is also the right
answer if the sidecar turns out to be more trouble than it is worth on this hardware.
