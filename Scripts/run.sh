#!/usr/bin/env bash
# Rebuild and relaunch, killing any previous instance so you never end up with two
# pets fighting over the notch.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/Scripts/bundle.sh" "${1:-debug}"
pkill -x NotchEyePet 2>/dev/null || true
open "$ROOT/build/NotchEyePet.app"
echo "launched — look for the eye icon in the menu bar"
