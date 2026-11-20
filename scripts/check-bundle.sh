#!/usr/bin/env bash
# Checks the built bundle: the Editor helper nested in Contents/Helpers, both signed
# ad-hoc and verified strictly, both agents with the same name and icon, arm64 only,
# engine linked statically.
# Usage: scripts/check-bundle.sh path/to/snapit.app
set -uo pipefail

APP="${1:?usage: check-bundle.sh path/to/snapit.app}"
HELPER="$APP/Contents/Helpers/snapit Editor.app"
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

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }
equal() { [[ "$1" == "$2" && -n "$1" ]]; }

check "app executable exists" test -x "$APP/Contents/MacOS/snapit"
check "helper nested in Contents/Helpers" test -x "$HELPER/Contents/MacOS/snapit Editor"
check "app is signed strictly" codesign --verify --strict --verbose=2 "$APP"
check "helper is signed strictly" codesign --verify --strict --verbose=2 "$HELPER"
check "app signature is ad-hoc" bash -c "codesign -dv '$APP' 2>&1 | grep -q 'Signature=adhoc'"
check "helper signature is ad-hoc" bash -c "codesign -dv '$HELPER' 2>&1 | grep -q 'Signature=adhoc'"
check "outer seal covers the helper (no --deep needed)" bash -c "codesign -dvvv '$APP' 2>&1 | grep -q 'Sealed Resources'"

check "app is an agent (no Dock icon)" equal "$(plist "$APP" LSUIElement)" "true"
check "helper starts as an agent (no Dock icon)" equal "$(plist "$HELPER" LSUIElement)" "true"
check "helper has the same display name as snapit" equal "$(plist "$HELPER" CFBundleDisplayName)" "$(plist "$APP" CFBundleDisplayName)"
check "display name is snapit" equal "$(plist "$APP" CFBundleDisplayName)" "snapit"
check "helper has the same bundle name as snapit" equal "$(plist "$HELPER" CFBundleName)" "$(plist "$APP" CFBundleName)"
check "helper has the same icon name" equal "$(plist "$HELPER" CFBundleIconFile)" "$(plist "$APP" CFBundleIconFile)"
check "helper icon file is identical" cmp -s "$APP/Contents/Resources/AppIcon.icns" "$HELPER/Contents/Resources/AppIcon.icns"
check "the User Guide is bundled in the helper" test -s "$HELPER/Contents/Resources/UserGuide.md"
check "the menu bar app carries no copy of the User Guide" test ! -e "$APP/Contents/Resources/UserGuide.md"
check "helper has the same version" equal "$(plist "$HELPER" CFBundleShortVersionString)" "$(plist "$APP" CFBundleShortVersionString)"
check "helper bundle id extends the app's" equal "$(plist "$HELPER" CFBundleIdentifier)" "$(plist "$APP" CFBundleIdentifier).editor"
check "app package type is APPL" equal "$(plist "$APP" CFBundlePackageType)" "APPL"
check "helper package type is APPL" equal "$(plist "$HELPER" CFBundlePackageType)" "APPL"
check "deployment target is macOS 26.0" equal "$(plist "$APP" LSMinimumSystemVersion)" "26.0"
check "app is arm64 only" equal "$(lipo -archs "$APP/Contents/MacOS/snapit")" "arm64"
check "helper is arm64 only" equal "$(lipo -archs "$HELPER/Contents/MacOS/snapit Editor")" "arm64"
check "engine is linked statically into the app" bash -c "! otool -L '$APP/Contents/MacOS/snapit' | grep -qi snapit_engine"
check "engine is linked statically into the helper" bash -c "! otool -L '$HELPER/Contents/MacOS/snapit Editor' | grep -qi snapit_engine"
check "app contains the engine" bash -c "nm '$APP/Contents/MacOS/snapit' | grep -q snapit_engine_version"
check "helper contains the engine" bash -c "nm '$HELPER/Contents/MacOS/snapit Editor' | grep -q snapit_engine_version"

if ((failures > 0)); then
  echo "$failures bundle check(s) failed"
  exit 1
fi
echo "bundle checks passed"
