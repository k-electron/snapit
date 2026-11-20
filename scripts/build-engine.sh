#!/usr/bin/env bash
# Builds the engine as an arm64 static library at
#   target/aarch64-apple-darwin/release/libsnapit_engine.a
# which both Xcode targets link. Called by the "Build Engine" Run Script phase of the
# Engine target (Xcode gives scripts no shell profile, so scripts/cargo-env.sh locates
# cargo) and by scripts/test.sh and CI.
#
# Only the Engine target turns ENABLE_USER_SCRIPT_SANDBOXING off: cargo reads the whole
# workspace and ~/.cargo, and writes target/, none of which a sandboxed script can declare.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=cargo-env.sh
source "$ROOT/scripts/cargo-env.sh"

# Xcode exports build settings that confuse cargo's cc/linker detection.
unset ARCHS CC CXX LD LDPLUSPLUS CPATH LIBRARY_PATH

"$CARGO" build --release --locked --target aarch64-apple-darwin -p snapit-engine

LIB="$ROOT/target/aarch64-apple-darwin/release/libsnapit_engine.a"
[[ -f "$LIB" ]] || { echo "error: $LIB was not produced" >&2; exit 1; }
