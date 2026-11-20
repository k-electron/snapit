#!/usr/bin/env bash
# Regenerates engine/include/snapit_engine.h from the engine with cbindgen.
# `scripts/generate-header.sh --check` writes to a temp file and fails when the committed
# header differs (the CI drift check).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HEADER="$ROOT/engine/include/snapit_engine.h"
WANT_CBINDGEN="0.29.4"

if ! command -v cbindgen >/dev/null 2>&1; then
  echo "error: cbindgen not found. Install it with: cargo install cbindgen --version $WANT_CBINDGEN --locked" >&2
  exit 2
fi
HAVE_CBINDGEN="$(cbindgen --version | awk '{print $2}')"
if [[ "$HAVE_CBINDGEN" != "$WANT_CBINDGEN" ]]; then
  echo "warning: cbindgen $HAVE_CBINDGEN found, $WANT_CBINDGEN expected; output may differ" >&2
fi

generate() {
  (cd "$ROOT/engine" && cbindgen --config cbindgen.toml --crate snapit-engine --lockfile ../Cargo.lock --output "$1" .)
}

if [[ "${1:-}" == "--check" ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  generate "$TMP/snapit_engine.h" 2>/dev/null
  if ! diff -u "$HEADER" "$TMP/snapit_engine.h"; then
    echo "error: engine/include/snapit_engine.h does not match the engine. Run scripts/generate-header.sh and commit." >&2
    exit 1
  fi
  echo "header matches the engine"
else
  generate "$HEADER"
  echo "wrote $HEADER"
fi
