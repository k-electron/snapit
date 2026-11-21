#!/usr/bin/env bash
# Builds snapit for release and packages it: Release build, ad-hoc signing (the Editor helper
# first, then the outer app, hardened runtime, no --deep, no entitlements), the DMG, its
# SHA-256 and the release notes. The release workflow and a local run use this same script.
#
# Usage: scripts/package-release.sh VERSION
#   VERSION is a tag or a version: v1.2.3, 1.2.3, v1.2.3-beta.1 ...
#   The bundle version is X.Y.Z (anything after a "-" is dropped); the DMG keeps the full version.
# Environment:
#   SNAPIT_BUILD_NUMBER  CFBundleVersion (default 1; the workflow passes the run number)
#   SNAPIT_DIST_DIR      where the files land (default build/release)
# Writes to SNAPIT_DIST_DIR: snapit-VERSION.dmg, snapit-VERSION.dmg.sha256, release-notes.md.
# Needs: Xcode 27, rustup, cbindgen 0.29.4 on PATH (as for scripts/test.sh), python3 3.11+.
set -euo pipefail

TAG="${1:?usage: package-release.sh VERSION (for example v1.2.3 or v1.2.3-beta.1)}"
VERSION="${TAG#v}"
if [[ ! "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
  echo "error: '$TAG' is not a version tag (expected vX.Y.Z or vX.Y.Z-beta.N)" >&2
  exit 2
fi
MARKETING="${BASH_REMATCH[1]}"
BUILD_NUMBER="${SNAPIT_BUILD_NUMBER:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"
BUILD="$ROOT/build"
DIST="${SNAPIT_DIST_DIR:-$BUILD/release}"
DERIVED="$BUILD/release-derived.noindex"
STAGE="$BUILD/release-stage.noindex"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

stage() { printf '\n==> %s\n' "$1"; }

unregister_built_apps() {
  # xcodebuild and codesigned copies register every .app with LaunchServices.
  local app
  for app in "$DERIVED"/Build/Products/*/snapit.app \
             "$DERIVED"/Build/Products/*/snapit.app/Contents/Helpers/"snapit Editor.app" \
             "$DERIVED"/Build/Products/*/"snapit Editor.app" \
             "$STAGE/snapit.app" "$STAGE/snapit.app/Contents/Helpers/snapit Editor.app"; do
    if [[ -e "$app" ]]; then "$LSREGISTER" -u "$app" 2>/dev/null || true; fi
  done
}
trap unregister_built_apps EXIT

mkdir -p "$DIST"
DMG="$DIST/snapit-$VERSION.dmg"
rm -f "$DMG" "$DMG.sha256" "$DIST/release-notes.md"
rm -rf "$STAGE"

stage "xcodebuild $VERSION (bundle version $MARKETING, build $BUILD_NUMBER)"
xcodebuild -project snapit.xcodeproj -scheme snapit -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  -onlyUsePackageVersionsFromResolvedFile -packageCachePath "$BUILD/swiftpm-cache" \
  MARKETING_VERSION="$MARKETING" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" CODE_SIGN_IDENTITY=- \
  -quiet build

stage "sign: helper first, then the app (ad-hoc, hardened runtime, no --deep, no entitlements)"
mkdir -p "$STAGE"
ditto --norsrc --noextattr "$DERIVED/Build/Products/Release/snapit.app" "$STAGE/snapit.app"
APP="$STAGE/snapit.app"
HELPER="$APP/Contents/Helpers/snapit Editor.app"
codesign --force --sign - --timestamp=none --options runtime "$HELPER"
codesign --force --sign - --timestamp=none --options runtime "$APP"

stage "verify the signed app"
codesign --verify --deep --strict --verbose=2 "$APP"
for bundle in "$APP" "$HELPER"; do
  details="$(codesign -dv "$bundle" 2>&1)"
  [[ "$details" == *'flags=0x10002(adhoc,runtime)'* ]] ||
    { echo "error: $bundle is not ad-hoc signed with the hardened runtime" >&2; exit 1; }
  [[ -z "$(codesign -d --entitlements - "$bundle" 2>/dev/null)" ]] ||
    { echo "error: $bundle has entitlements" >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")" == "$MARKETING" ]] ||
    { echo "error: $bundle does not carry version $MARKETING" >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Contents/Info.plist")" == "$BUILD_NUMBER" ]] ||
    { echo "error: $bundle does not carry build number $BUILD_NUMBER" >&2; exit 1; }
done
scripts/check-bundle.sh "$APP"

stage "DMG"
scripts/make-dmg.sh "$APP" "$DMG"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
SHA256="$(cut -d' ' -f1 "$DMG.sha256")"

stage "release notes"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHA256@/$SHA256/g" packaging/release-notes.md > "$DIST/release-notes.md"

stage "check the DMG"
scripts/check-dmg.sh "$DMG" "$MARKETING"

echo
echo "release files in $DIST:"
ls -l "$DMG" "$DMG.sha256" "$DIST/release-notes.md"
echo "$SHA256"
