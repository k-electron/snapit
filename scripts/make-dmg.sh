#!/usr/bin/env bash
# Makes the snapit DMG with dmgbuild 2.x: the app, an Applications link, and a window background
# with an arrow into Applications and the First open line. The background is drawn by
# packaging/dmg/make-background.swift on every run, so no image is committed. dmgbuild writes
# the window layout itself (no Finder, no AppleScript) and cleans up its own temporary mount.
#
# Usage: scripts/make-dmg.sh path/to/snapit.app path/to/snapit-X.Y.Z.dmg
# Needs: python3 3.11 or later, network for the first run (dmgbuild is installed with
# --require-hashes from packaging/dmg/requirements.txt into build/dmg-venv).
set -euo pipefail

APP="${1:?usage: make-dmg.sh path/to/snapit.app path/to/output.dmg}"
OUT="${2:?usage: make-dmg.sh path/to/snapit.app path/to/output.dmg}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"
BUILD="${SNAPIT_BUILD_DIR:-$ROOT/build}"
VENV="$BUILD/dmg-venv"
ART="$BUILD/dmg-art"

# One place for the window geometry (points, from the window's top left).
WIDTH=660 HEIGHT=440
APP_X=180 APP_Y=200
APPLICATIONS_X=480 APPLICATIONS_Y=200

[[ -d "$APP" ]] || { echo "error: $APP is not a folder" >&2; exit 1; }
mkdir -p "$BUILD" "$(dirname "$OUT")"
APP="$(cd "$APP" && pwd)"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

REQUIREMENTS="$ROOT/packaging/dmg/requirements.txt"
REQUIREMENTS_HASH="$(shasum -a 256 "$REQUIREMENTS" | cut -d' ' -f1)"
if [[ ! -x "$VENV/bin/dmgbuild" || "$(cat "$VENV/requirements.sha256" 2>/dev/null)" != "$REQUIREMENTS_HASH" ]]; then
  rm -rf "$VENV"
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' ||
    { echo "error: dmgbuild 2.x needs python3 3.11 or later" >&2; exit 1; }
  python3 -m venv "$VENV"
  "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check --no-cache-dir \
    --require-hashes --only-binary :all: -r "$REQUIREMENTS"
  echo "$REQUIREMENTS_HASH" > "$VENV/requirements.sha256"
fi

rm -rf "$ART"
trap 'rm -rf "$ART"' EXIT
swift "$ROOT/packaging/dmg/make-background.swift" "$ART" \
  "$WIDTH" "$HEIGHT" "$APP_X" "$APP_Y" "$APPLICATIONS_X" "$APPLICATIONS_Y"

rm -f "$OUT"
"$VENV/bin/dmgbuild" -s "$ROOT/packaging/dmg/settings.py" \
  -D "app=$APP" -D "background=$ART/background.png" \
  -D "width=$WIDTH" -D "height=$HEIGHT" \
  -D "app_x=$APP_X" -D "app_y=$APP_Y" \
  -D "applications_x=$APPLICATIONS_X" -D "applications_y=$APPLICATIONS_Y" \
  snapit "$OUT"

echo "made $OUT"
