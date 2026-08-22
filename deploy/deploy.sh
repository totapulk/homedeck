#!/usr/bin/env bash
#
# Builds the web UI, publishes the backend for the Pi, and installs it as a systemd service.
#
#     deploy/deploy.sh [user@host]        # default: tommi@homedeck.local
#
# Assumes the target can sudo without a password, which is how Raspberry Pi Imager sets up the
# first account. The vacuum sidecar is installed separately; see README.md in this directory.
#
set -euo pipefail

target="${1:-tommi@homedeck.local}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

echo "==> Building the web UI"
"$root/scripts/build-web.sh" >/dev/null

echo "==> Publishing for linux-arm64"
# Self-contained: the Pi needs no .NET installed, and the runtime cannot drift from what was
# tested here. Costs about 130 MB, which a memory card does not notice.
dotnet publish "$root/backend/src/HomeDeck.Api" \
  --configuration Release \
  --runtime linux-arm64 \
  --self-contained true \
  --output "$staging/app" \
  --nologo

echo "==> Copying $(du -sh "$staging/app" | cut -f1) to $target"
ssh "$target" 'sudo systemctl stop homedeck-api 2>/dev/null || true
               sudo mkdir -p /opt/homedeck
               sudo chown -R "$USER" /opt/homedeck'

scp -q -r "$staging/app/." "$target:/opt/homedeck/"
scp -q "$root/deploy/homedeck-api.service" "$target:/tmp/homedeck-api.service"

echo "==> Installing the service"
ssh "$target" 'set -euo pipefail
  chmod +x /opt/homedeck/HomeDeck.Api
  sed "s/%DEPLOY_USER%/$USER/" /tmp/homedeck-api.service | \
    sudo tee /etc/systemd/system/homedeck-api.service >/dev/null
  rm /tmp/homedeck-api.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now homedeck-api
  sudo systemctl restart homedeck-api'

echo "==> Waiting for it to answer"
host="${target#*@}"
for _ in $(seq 30); do
  # No -S here: a service that has not finished starting is what this loop is for, and
  # printing the connection error on every attempt makes a normal wait look like a failure.
  if curl -fs -o /dev/null "http://$host/health"; then
    echo
    echo "Up: http://$host/"
    exit 0
  fi
  sleep 1
done

echo "No answer from http://$host/health — check: ssh $target journalctl -u homedeck-api -n 50" >&2
exit 1
