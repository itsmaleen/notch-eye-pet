#!/usr/bin/env bash
# Build NotchEyePet.app. SwiftPM alone produces a bare binary; a notch/menu-bar
# accessory app needs a real bundle with LSUIElement, or it gets a Dock icon and
# the window layering misbehaves.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/build/NotchEyePet.app"

# Signing identity is read from the environment, never committed. Set it in
# Scripts/signing.env (gitignored) or export it before running:
#
#   NOTCH_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#
# Unset means ad-hoc, which is fine for local dev but cannot be distributed:
# Gatekeeper rejects ad-hoc signatures on anything that arrives with a
# quarantine attribute. See Scripts/release.sh for the distributable path.
[ -f "$ROOT/Scripts/signing.env" ] && . "$ROOT/Scripts/signing.env"
IDENTITY="${NOTCH_SIGNING_IDENTITY:-}"

cd "$ROOT"
# UNIVERSAL=1 builds arm64 + x86_64 so the app runs on Intel Macs too. Off by
# default because it roughly doubles build time and local dev never needs it.
ARCH_ARGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIG" --product NotchEyePet "${ARCH_ARGS[@]}"
BIN="$(swift build -c "$CONFIG" --product NotchEyePet "${ARCH_ARGS[@]}" --show-bin-path)/NotchEyePet"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchEyePet"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchEyePet</string>
  <key>CFBundleDisplayName</key><string>Notch Eye Pet</string>
  <key>CFBundleIdentifier</key><string>com.itsmaleen.notcheyepet</string>
  <key>CFBundleExecutable</key><string>NotchEyePet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Accessory app: no Dock icon, no menu bar takeover. -->
  <key>LSUIElement</key><true/>
  <!-- NSCameraUsageDescription belongs here only once the opt-in blink lane lands.
       Shipping it early makes the app look like it wants the camera when it does not. -->
</dict>
</plist>
PLIST

if [ -n "$IDENTITY" ]; then
  # Hardened runtime and a secure timestamp are both prerequisites for
  # notarization; notarytool rejects the upload without them.
  codesign --force --sign "$IDENTITY" --timestamp --options runtime "$APP"
  echo "built $APP (signed: $IDENTITY)"
else
  # Ad-hoc gives the app a stable identity for TCC and keeps it from being killed.
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
    echo "warning: ad-hoc codesign failed; app may still run"
  echo "built $APP (ad-hoc, local use only)"
fi
