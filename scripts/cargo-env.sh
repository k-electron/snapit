#!/usr/bin/env bash
# Sourced by the other scripts. Puts a pinned-toolchain `cargo` on PATH without relying
# on a shell profile (Xcode Run Script phases and CI steps have none), and exports the
# deployment target Rust objects must match.
#
# Lookup order: rustup's proxies in $HOME/.cargo/bin, then a Homebrew rustup, then PATH.
# Needs $ROOT (the repo root) to be set by the caller.

RUSTUP=/opt/homebrew/bin/rustup

snapit_find_cargo() {
  if [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    echo "$HOME/.cargo/bin/cargo"
    return
  fi
  if [[ -x "$RUSTUP" ]]; then
    local channel found
    channel="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$ROOT/rust-toolchain.toml")"
    # With RUSTUP_TOOLCHAIN set, or the pinned toolchain already installed, this resolves
    # without installing anything.
    if [[ -n "${RUSTUP_TOOLCHAIN:-}" ]] || "$RUSTUP" toolchain list | grep -q "^${channel}-"; then
      if found="$(cd "$ROOT" && "$RUSTUP" which cargo 2>/dev/null)" && [[ -x "$found" ]]; then
        echo "$found"
        return
      fi
    else
      # The pinned toolchain is missing: fetch it, as the first `cargo` call on a
      # developer machine would.
      (cd "$ROOT" && "$RUSTUP" toolchain install >&2 && "$RUSTUP" which cargo)
      return
    fi
  fi
  command -v cargo || true
}

CARGO="$(snapit_find_cargo)"
if [[ -z "$CARGO" ]]; then
  echo "error: cargo not found (looked in \$HOME/.cargo/bin, rustup at $RUSTUP, PATH). Install rustup from https://rustup.rs" >&2
  exit 1
fi
# cargo, rustfmt and clippy find each other next to the cargo binary.
export PATH="$(dirname "$CARGO"):$PATH"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
