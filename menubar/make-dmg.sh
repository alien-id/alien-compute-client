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

# --- Notarize + staple ------------------------------------------------------
# Runs only when the app is Developer ID signed AND a notarytool credential
# profile exists. No-op for ad-hoc/local builds.
#   Create the profile once:
#     xcrun notarytool store-credentials AC_NOTARY \
#       --apple-id <APPLE_ID> --team-id <TEAMID> --password <app-specific-pw>
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

# Capture the signature once. Piping into `grep -q` would close the pipe early
# and SIGPIPE codesign, which under `set -o pipefail` makes the test look false.
APP_SIG="$(codesign -dvv "$APP" 2>&1 || true)"
if grep -q 'Authority=Developer ID Application' <<<"$APP_SIG"; then
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Notarizing $DMG (profile: $NOTARY_PROFILE) — can take a few minutes…"
    if ! xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait; then
      echo "!!  Notarization failed. Inspect with:" >&2
      echo "      xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE" >&2
      exit 1
    fi
    echo "==> Stapling ticket to the DMG and app…"
    xcrun stapler staple "$DMG"
    xcrun stapler staple "$APP" || true   # best-effort: also staple the standalone app
    echo "==> Gatekeeper assessment:"
    spctl -a -t exec -vv "$APP" 2>&1 | sed 's/^/    /' || true
    echo "==> Notarized & stapled: $(pwd)/$DMG"
  else
    team="$(awk -F= '/TeamIdentifier/{print $2}' <<<"$APP_SIG")"
    echo "!!  Developer ID signed, but notary profile '$NOTARY_PROFILE' was not found."
    echo "    Create it once, then re-run ./make-dmg.sh:"
    echo "      xcrun notarytool store-credentials $NOTARY_PROFILE \\"
    echo "        --apple-id <APPLE_ID> --team-id ${team:-<TEAMID>} --password <app-specific-pw>"
  fi
else
  echo "==> App is ad-hoc signed — skipping notarization."
  echo "    (Downloaded copies will be blocked by Gatekeeper until notarized.)"
fi

echo "    Open it and drag Alien Compute into Applications."
