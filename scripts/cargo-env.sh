#!/usr/bin/env bash
# Sourced by the other scripts. Puts a pinned-toolchain `cargo` on PATH without relying
# on a shell profile (Xcode Run Script phases and CI steps have none), and exports the
# deployment target Rust objects must match.
#
# Lookup order: rustup's proxies in $HOME/.cargo/bin, then a Homebrew rustup, then PATH.
# With a Homebrew rustup, an installed toolchain whose rustc version equals the pin in
# rust-toolchain.toml is used as it is (for example a `stable` that is currently that
# version); the pin is downloaded only when nothing installed matches.
# Needs $ROOT (the repo root) to be set by the caller.

RUSTUP=/opt/homebrew/bin/rustup

# Prints the name of an installed toolchain whose rustc version equals $1, if any.
# Runs from / on purpose: rustup commands run inside the repo read rust-toolchain.toml
# and download the pinned toolchain when it is missing, even for `toolchain list`.
snapit_installed_toolchain_for() {
  local name version
  while read -r name _; do
    version="$(cd / && "$RUSTUP" run "$name" rustc --version 2>/dev/null | awk '{ print $2 }')"
    if [[ "$version" == "$1" ]]; then
      echo "$name"
      return
    fi
  done < <(cd / && "$RUSTUP" toolchain list 2>/dev/null)
}

snapit_find_cargo() {
  if [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    echo "$HOME/.cargo/bin/cargo"
    return
  fi
  if [[ -x "$RUSTUP" ]]; then
    local channel match
    channel="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$ROOT/rust-toolchain.toml")"
    if [[ -z "${RUSTUP_TOOLCHAIN:-}" ]]; then
      match="$(snapit_installed_toolchain_for "$channel")"
      if [[ -n "$match" ]]; then
        export RUSTUP_TOOLCHAIN="$match"
      else
        (cd "$ROOT" && "$RUSTUP" toolchain install >&2) || return
      fi
    fi
    (cd "$ROOT" && "$RUSTUP" which cargo 2>/dev/null) && return
  fi
  command -v cargo || true
}

CARGO="$(snapit_find_cargo)"
if [[ -z "$CARGO" ]]; then
  echo "error: cargo not found (looked in \$HOME/.cargo/bin, rustup at $RUSTUP, PATH). Install rustup from https://rustup.rs" >&2
  exit 1
fi
# `export RUSTUP_TOOLCHAIN` inside the $(...) above does not reach this shell.
if [[ -z "${RUSTUP_TOOLCHAIN:-}" && -x "$RUSTUP" ]]; then
  _snapit_match="$(snapit_installed_toolchain_for "$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$ROOT/rust-toolchain.toml")")"
  [[ -n "$_snapit_match" ]] && export RUSTUP_TOOLCHAIN="$_snapit_match"
fi
# cargo, rustfmt and clippy find each other next to the cargo binary.
export PATH="$(dirname "$CARGO"):$PATH"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
