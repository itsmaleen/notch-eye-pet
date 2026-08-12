#!/usr/bin/env bash
# Build NotchEyePet.app. SwiftPM alone produces a bare binary; a notch/menu-bar
# accessory app needs a real bundle with LSUIElement, or it gets a Dock icon and
# the window layering misbehaves.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/build/NotchEyePet.app"

cd "$ROOT"
swift build -c "$CONFIG" --product NotchEyePet
BIN="$(swift build -c "$CONFIG" --product NotchEyePet --show-bin-path)/NotchEyePet"

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
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Accessory app: no Dock icon, no menu bar takeover. -->
  <key>LSUIElement</key><true/>
  <!-- NSCameraUsageDescription belongs here only once the opt-in blink lane lands.
       Shipping it early makes the app look like it wants the camera when it does not. -->
</dict>
</plist>
PLIST

# Ad-hoc sign so the app has a stable identity for TCC and does not get killed.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "warning: ad-hoc codesign failed; app may still run"

echo "built $APP"
