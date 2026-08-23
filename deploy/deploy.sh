#!/usr/bin/env bash
#
# Builds the web UI, publishes the backend for the Pi, and restarts it as a systemd service.
#
#     deploy/deploy.sh [user@host]        # default: tommi@homedeck.local
#
# The vacuum sidecar is installed separately; see README.md in this directory.
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

if ! ssh "$target" "test -w /opt/homedeck" 2>/dev/null; then
  echo "First run on this machine. Set the directory up once:" >&2
  echo >&2
  echo "    ssh $target 'sudo mkdir -p /opt/homedeck && sudo chown \$USER /opt/homedeck'" >&2
  exit 1
fi

echo "==> Copying $(du -sh "$staging/app" | cut -f1) to $target"
ssh "$target" "rm -rf /opt/homedeck/incoming && mkdir -p /opt/homedeck/incoming"
scp -q -r "$staging/app/." "$target:/opt/homedeck/incoming/"

echo "==> Swapping the release in"
# A whole directory, never files in place. scp truncates and rewrites, and a running runtime
# whose assemblies change underneath its mappings throws BadImageFormatException from wherever
# it next happens to look — a process that keeps answering while quietly doing nothing. Replacing
# the directory instead leaves the running process holding the inodes it already opened, so it is
# untouched until the restart below.
ssh "$target" 'set -e
  chmod +x /opt/homedeck/incoming/HomeDeck.Api
  rm -rf /opt/homedeck/app
  mv /opt/homedeck/incoming /opt/homedeck/app
  # Leftovers from the layout that kept the app in the top-level directory. The sidecar lives
  # here too and is deployed by hand, so it is named rather than swept up with them.
  find /opt/homedeck -mindepth 1 -maxdepth 1 ! -name app ! -name sidecar -exec rm -rf {} +'

if ! ssh "$target" "grep -q /opt/homedeck/app /etc/systemd/system/homedeck-api.service" 2>/dev/null; then
  echo "==> Installing the service (sudo on the Pi will ask for your password)"
  scp -q "$root/deploy/homedeck-api.service" "$target:/tmp/homedeck-api.service"
  ssh -t "$target" 'set -e
    sed "s/%DEPLOY_USER%/$USER/" /tmp/homedeck-api.service | \
      sudo tee /etc/systemd/system/homedeck-api.service >/dev/null
    rm /tmp/homedeck-api.service
    sudo systemctl daemon-reload
    sudo systemctl enable homedeck-api'
fi

echo "==> Restarting (sudo on the Pi will ask for your password)"
ssh -t "$target" "sudo systemctl restart homedeck-api"

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
