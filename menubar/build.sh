#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Alien Compute"
BUNDLE="Alien Compute.app"
EXEC="AlienCompute"
BUNDLE_ID="gg.lethe.alien-compute"
PROXY_SRC="${PROXY_SRC:-../fleet-proxy}"
TARGET="${TARGET:-arm64-apple-macos13.0}"

rm -rf build "$BUNDLE"
mkdir -p build

echo "==> Compiling Swift sources ($TARGET)..."
swiftc -O -target "$TARGET" -o "build/$EXEC" Sources/*.swift

echo "==> Generating app icon (flying saucer)..."
swiftc -O -target "$TARGET" -o "build/makeicon" tools/main.swift Sources/SaucerShape.swift
"./build/makeicon" "build/AppIcon.iconset"
iconutil -c icns "build/AppIcon.iconset" -o "build/AppIcon.icns"

echo "==> Assembling ${BUNDLE}..."
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "build/$EXEC" "$BUNDLE/Contents/MacOS/$EXEC"
cp "build/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

if [[ ! -f "$PROXY_SRC" ]]; then
  echo "ERROR: fleet-proxy binary not found at '$PROXY_SRC'." >&2
  echo "       Set PROXY_SRC=/path/to/fleet-proxy and re-run." >&2
  exit 1
fi
cp "$PROXY_SRC" "$BUNDLE/Contents/Resources/fleet-proxy"
chmod +x "$BUNDLE/Contents/Resources/fleet-proxy" "$BUNDLE/Contents/MacOS/$EXEC"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${EXEC}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# --- Code signing -----------------------------------------------------------
# Prefer a "Developer ID Application" identity (required for notarization);
# fall back to ad-hoc so local dev builds still run on this Mac.
#   Override the identity with CODESIGN_ID="Developer ID Application: … (TEAMID)".
SIGN_ID="${CODESIGN_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
             | awk -F'"' '/Developer ID Application/{print $2; exit}')"
fi

if [[ -n "$SIGN_ID" ]]; then
  echo "==> Signing with Developer ID + hardened runtime: $SIGN_ID"
  CS_OPTS=(--force --options runtime --timestamp --sign "$SIGN_ID")
else
  echo "==> No Developer ID identity found — ad-hoc signing (NOT notarizable)."
  CS_OPTS=(--force --sign -)
fi

# Sign inner Mach-O binaries first, then the bundle.
codesign "${CS_OPTS[@]}" "$BUNDLE/Contents/Resources/fleet-proxy"
codesign "${CS_OPTS[@]}" "$BUNDLE/Contents/MacOS/$EXEC"
codesign "${CS_OPTS[@]}" "$BUNDLE"

if [[ -n "$SIGN_ID" ]]; then
  codesign --verify --deep --strict --verbose=2 "$BUNDLE"
fi

echo "==> Built $(pwd)/$BUNDLE"
echo "    Run with:  open \"$BUNDLE\"     (look for the flying-saucer icon in the menu bar)"
