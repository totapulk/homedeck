#!/usr/bin/env bash
#
# Builds the Flutter web app into the backend's static root, so that running the backend serves
# the UI as well as the API. One origin means the browser build needs no address configured and
# no CORS in production.
#
#     scripts/build-web.sh
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/backend/src/HomeDeck.Api/wwwroot"

cd "$root/app"

# An absolute output path on purpose: given a relative one, the Windows shader compiler builds a
# path with mixed separators and fails to create its own output directory.
flutter build web --output "$out"

# --output empties the directory first, and this placeholder is what keeps wwwroot in git.
touch "$out/.gitkeep"

echo
echo "Built into $out"
echo "Run the backend and open http://<this machine>:5080"
