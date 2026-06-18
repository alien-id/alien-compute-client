#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Alien Compute.app"
VOL="Alien Compute"
DMG="Alien Compute.dmg"

# Build the app (which bundles ../fleet-proxy) if it isn't there yet.
if [[ ! -d "$APP" ]]; then
  echo "==> $APP not found; building..."
  ./build.sh
fi

# Sanity check: the proxy binary must be inside the bundle.
if [[ ! -f "$APP/Contents/Resources/fleet-proxy" ]]; then
  echo "ERROR: $APP/Contents/Resources/fleet-proxy missing — re-run ./build.sh" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

rm -f "$DMG"
echo "==> Creating $DMG..."
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Built $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"
echo "    Open it and drag Alien Compute into Applications."
