#!/usr/bin/env bash
# Checks a built DMG from the outside: it mounts the image read-only (no Finder window, at a
# mount point inside build/), looks at what is in it, verifies the app on the volume, then
# detaches and unregisters whatever LaunchServices saw. Nothing stays mounted or registered,
# even when a check fails.
#
# Usage: scripts/check-dmg.sh path/to/snapit-X.Y.Z.dmg [expected-version]
# Uses the dmgbuild virtualenv from scripts/make-dmg.sh (build/dmg-venv) to read the window layout.
set -uo pipefail

DMG="${1:?usage: check-dmg.sh path/to/snapit-X.Y.Z.dmg [expected-version]}"
EXPECTED_VERSION="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${SNAPIT_BUILD_DIR:-$ROOT/build}"
VENV="$BUILD/dmg-venv"
DMG="$(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
MOUNT="$BUILD/dmg-mount"
failures=0

check() { # description, command...
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   $description"
  else
    echo "FAIL $description"
    failures=$((failures + 1))
  fi
}

mounted=0
cleanup() {
  if [[ -d "$MOUNT/snapit.app" ]]; then
    "$LSREGISTER" -u "$MOUNT/snapit.app" 2>/dev/null || true
    "$LSREGISTER" -u "$MOUNT/snapit.app/Contents/Helpers/snapit Editor.app" 2>/dev/null || true
  fi
  if ((mounted)); then
    hdiutil detach -quiet "$MOUNT" 2>/dev/null || hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true
  fi
  rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

[[ -f "$DMG" ]] || { echo "error: $DMG not found" >&2; exit 1; }

check "image verifies (hdiutil verify)" hdiutil verify -quiet "$DMG"

mkdir -p "$MOUNT"
if hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$DMG" >/dev/null; then
  mounted=1
  echo "ok   image mounts"
else
  echo "FAIL image mounts"
  exit 1
fi

APP="$MOUNT/snapit.app"
HELPER="$APP/Contents/Helpers/snapit Editor.app"
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

check "snapit.app is on the volume" test -d "$APP"
check "Applications is a link to /Applications" test "$(readlink "$MOUNT/Applications")" = "/Applications"
check "window background is in the image" test -s "$MOUNT/.background.tiff"
check "window layout (.DS_Store) is in the image" test -s "$MOUNT/.DS_Store"
check "background carries a Retina representation" bash -c "[[ \$(tiffutil -info '$MOUNT/.background.tiff' 2>&1 | grep -c 'Image Width') -ge 2 ]]"
check "volume holds only the app, Applications and hidden files" bash -c "[[ \$(ls '$MOUNT' | sort | tr '\n' ' ') == 'Applications snapit.app ' ]]"
check "app verifies with --deep --strict" codesign --verify --deep --strict --verbose=2 "$APP"
check "helper verifies with --strict" codesign --verify --strict --verbose=2 "$HELPER"
check "app is ad-hoc signed with the hardened runtime" bash -c "codesign -dv '$APP' 2>&1 | grep -q 'flags=0x10002(adhoc,runtime)'"
check "helper is ad-hoc signed with the hardened runtime" bash -c "codesign -dv '$HELPER' 2>&1 | grep -q 'flags=0x10002(adhoc,runtime)'"
check "app has no entitlements" bash -c "[[ -z \$(codesign -d --entitlements - '$APP' 2>/dev/null) ]]"
check "helper has no entitlements" bash -c "[[ -z \$(codesign -d --entitlements - '$HELPER' 2>/dev/null) ]]"
if [[ -n "$EXPECTED_VERSION" ]]; then
  check "app version is $EXPECTED_VERSION" test "$(plist "$APP" CFBundleShortVersionString)" = "$EXPECTED_VERSION"
  check "helper version is $EXPECTED_VERSION" test "$(plist "$HELPER" CFBundleShortVersionString)" = "$EXPECTED_VERSION"
fi

# The window layout: both icons where the background's arrow expects them.
if [[ ! -x "$VENV/bin/python" ]]; then
  echo "FAIL icons sit where the background's arrow expects them (no $VENV; run scripts/make-dmg.sh first)"
  failures=$((failures + 1))
else
  check "icons sit where the background's arrow expects them" "$VENV/bin/python" -I -c '
import sys
from ds_store import DSStore
with DSStore.open(sys.argv[1] + "/.DS_Store", "r") as store:
    locations = {entry.filename: entry.value for entry in store if entry.code == b"Iloc"}
def centre(name):
    return (locations[name]["x"], locations[name]["y"]) if isinstance(locations[name], dict) else tuple(locations[name][:2])
assert centre("snapit.app") == (180, 200), locations
assert centre("Applications") == (480, 200), locations
' "$MOUNT"
fi

if [[ -f "$DMG.sha256" ]]; then
  check "SHA-256 file matches the DMG" bash -c "cd '$(dirname "$DMG")' && shasum -a 256 -c '$(basename "$DMG").sha256'"
fi

if ((failures > 0)); then
  echo "$failures DMG check(s) failed"
  exit 1
fi
echo "DMG checks passed"
