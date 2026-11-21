#!/usr/bin/env bash
# Runs everything: repo checks, Cargo fmt/clippy/tests, the cbindgen header check, the
# Xcode build, the bundle checks and the scripted whole-app run. CI runs this script.
#
#   scripts/test.sh            all stages
#   scripts/test.sh engine     only the repo checks and the Rust stages
#
# Needs: Xcode 27 (found by scripts/xcode-env.sh when xcode-select points elsewhere), rustup (the pinned toolchain in rust-toolchain.toml), cbindgen 0.29.4.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=cargo-env.sh
source "$ROOT/scripts/cargo-env.sh"

DERIVED="$ROOT/build/DerivedData.noindex"
PRODUCTS="$DERIVED/Build/Products/Release"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

stage() { printf '\n==> %s\n' "$1"; }

unregister_built_apps() {
  # xcodebuild registers every .app it builds, in every configuration, with LaunchServices.
  local app
  for app in "$DERIVED"/Build/Products/*/snapit.app \
             "$DERIVED"/Build/Products/*/snapit.app/Contents/Helpers/"snapit Editor.app" \
             "$DERIVED"/Build/Products/*/"snapit Editor.app"; do
    if [[ -e "$app" ]]; then "$LSREGISTER" -u "$app" 2>/dev/null || true; fi
  done
}
trap unregister_built_apps EXIT

stage "repo layout"
if find . -type d -name Packages -not -path './target/*' -not -path './build/*' -not -path './.git/*' -not -path './.claude/*' | grep -q .; then
  echo "error: a folder named Packages/ exists, but .gitignore ignores that name" >&2
  exit 1
fi
grep -qx '/target/' .gitignore || { echo "error: .gitignore does not ignore /target/" >&2; exit 1; }
echo "ok"

stage "network use only in Check for Updates"
scripts/check-network.sh

stage "docs: User Guide and every relative link"
scripts/check-docs.sh

stage "cargo fmt"
"$CARGO" fmt --all --check

stage "cargo clippy"
"$CARGO" clippy --workspace --all-targets --locked -- -D warnings

stage "cargo test (C ABI)"
"$CARGO" test --workspace --locked

stage "cbindgen header matches the engine"
scripts/generate-header.sh --check

if [[ "${1:-}" == "engine" ]]; then
  echo
  echo "engine stages passed"
  exit 0
fi

# A full Xcode from here on: xcodebuild, and swift for the leak check. The engine stages above need none.
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"
# shellcheck source=leak-check.sh
source "$ROOT/scripts/leak-check.sh"

stage "xcodebuild"
xcodebuild -version
xcodebuild -project snapit.xcodeproj -scheme snapit -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  -onlyUsePackageVersionsFromResolvedFile -packageCachePath "$ROOT/build/swiftpm-cache" CODE_SIGN_IDENTITY=- -quiet build

stage "bundle checks"
scripts/check-bundle.sh "$PRODUCTS/snapit.app"

stage "scripted whole-app run"
# The run uses a private pasteboard and temporary folders. Look from outside that it left the real
# ~/Downloads and the general pasteboard alone, whether or not the run itself passed.
leak_begin
run_status=0
scripts/check-run.sh "$PRODUCTS/snapit.app" || run_status=$?
leak_status=0
leak_check || leak_status=$?
if ((run_status != 0 || leak_status != 0)); then exit 1; fi

echo
echo "all tests passed"
