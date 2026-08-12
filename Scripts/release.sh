#!/usr/bin/env bash
# Build a distributable NotchEyePet.app: universal, Developer ID signed, notarized,
# and stapled. The stapled ticket is what lets someone download the zip and just
# open the app, with no Gatekeeper dialog and no Terminal incantation.
#
# Requires (both read from the environment, never committed):
#   NOTCH_SIGNING_IDENTITY  "Developer ID Application: Your Name (TEAMID)"
#   NOTCH_NOTARY_PROFILE    name of a notarytool keychain profile
#
# Create the notary profile once:
#   xcrun notarytool store-credentials "notch-eye-pet" \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# Put both values in Scripts/signing.env, which is gitignored.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/Scripts/signing.env" ] && . "$ROOT/Scripts/signing.env"

APP="$ROOT/build/NotchEyePet.app"
ZIP="$ROOT/build/NotchEyePet.zip"

if [ -z "${NOTCH_SIGNING_IDENTITY:-}" ]; then
  echo "error: NOTCH_SIGNING_IDENTITY is not set. See the header of this script." >&2
  exit 1
fi

echo "==> building universal release bundle"
UNIVERSAL=1 "$ROOT/Scripts/bundle.sh" release

echo "==> verifying signature"
codesign --verify --strict --verbose=2 "$APP"

if [ -z "${NOTCH_NOTARY_PROFILE:-}" ]; then
  echo
  echo "warning: NOTCH_NOTARY_PROFILE is not set, so the app is signed but NOT notarized."
  echo "Gatekeeper will still block it on download. See the header of this script." >&2
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "wrote $ZIP (signed, not notarized)"
  exit 0
fi

echo "==> submitting to notary service (this takes a few minutes)"
# Notarization consumes a zip, but the ticket has to be stapled to the .app, so
# this upload archive is scratch: the shipping zip is rebuilt after stapling.
NOTARIZE_ZIP="$ROOT/build/notarize-upload.zip"
ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTCH_NOTARY_PROFILE" --wait
rm -f "$NOTARIZE_ZIP"

echo "==> stapling ticket"
xcrun stapler staple "$APP"

echo "==> verifying Gatekeeper acceptance"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> packaging"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "done: $ZIP"
lipo -archs "$APP/Contents/MacOS/NotchEyePet"
