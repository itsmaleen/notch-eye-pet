#!/usr/bin/env bash
# Install the built app into /Applications and relaunch it from there.
#
# Running out of build/ is fine for a quick look, but wrong for daily use, for two
# reasons that both bite silently:
#
#   1. bundle.sh does `rm -rf` on that bundle at the start of every build, so the
#      app you are "using" disappears the next time anyone builds.
#   2. SMAppService registers whatever path the app is running from, so a "Launch
#      at login" enabled while running from build/ points at a path that step 1
#      deletes. The toggle keeps reading as on while quietly doing nothing.
#
# Takes whatever is currently in build/, so run Scripts/release.sh first if you
# want the notarized universal build rather than a local debug one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/build/NotchEyePet.app"
DEST="/Applications/NotchEyePet.app"

if [ ! -d "$SRC" ]; then
  echo "error: nothing built at $SRC" >&2
  echo "run Scripts/bundle.sh (local) or Scripts/release.sh (distributable) first" >&2
  exit 1
fi

pkill -x NotchEyePet 2>/dev/null || true

# ditto rather than cp -R: it preserves the code signature and the stapled
# notarization ticket, both of which a naive recursive copy can mangle.
rm -rf "$DEST"
ditto "$SRC" "$DEST"

codesign --verify --strict "$DEST" || echo "warning: signature did not verify after copy"

open "$DEST"
echo "installed and launched $DEST"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DEST/Contents/Info.plist" \
  | sed 's/^/version /'
echo "look for the eye icon in the menu bar"
