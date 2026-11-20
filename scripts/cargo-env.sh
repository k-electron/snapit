#!/usr/bin/env bash
# Sourced by the other scripts. Puts a pinned-toolchain `cargo` on PATH without relying
# on a shell profile (Xcode Run Script phases and CI steps have none), and exports the
# deployment target Rust objects must match.
#
# It finds rustup in ${CARGO_HOME:-$HOME/.cargo}/bin, then /opt/homebrew/bin, then
# /opt/homebrew/opt/rustup/bin, and uses an installed toolchain whose rustc version
# equals the pin in rust-toolchain.toml (for example a `stable` that is currently that
# version). It never downloads a toolchain: when none matches it prints how to install
# the pin and exits. Without rustup it falls back to a cargo in CARGO_HOME or on PATH.
# Needs $ROOT (the repo root) to be set by the caller.

_snapit_cargo_bin="${CARGO_HOME:-$HOME/.cargo}/bin"

_snapit_find_rustup() {
  local candidate
  for candidate in "$_snapit_cargo_bin/rustup" /opt/homebrew/bin/rustup /opt/homebrew/opt/rustup/bin/rustup; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
}

# Prints the name of an installed toolchain whose rustc version equals $2, if any.
# Runs from / on purpose: a rustup command run inside the repo reads rust-toolchain.toml
# and downloads the pinned toolchain when it is missing, even for `toolchain list`.
_snapit_installed_toolchain_for() {
  local rustup="$1" name version
  while read -r name _; do
    version="$(cd / && "$rustup" run "$name" rustc --version 2>/dev/null | awk '{ print $2 }')"
    if [[ "$version" == "$2" ]]; then
      echo "$name"
      return
    fi
  done < <(cd / && "$rustup" toolchain list 2>/dev/null)
}

_snapit_resolve_cargo() {
  local rustup channel match
  rustup="$(_snapit_find_rustup)"
  if [[ -n "$rustup" ]]; then
    channel="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$ROOT/rust-toolchain.toml")"
    if [[ -z "${RUSTUP_TOOLCHAIN:-}" ]]; then
      match="$(_snapit_installed_toolchain_for "$rustup" "$channel")"
      if [[ -z "$match" ]]; then
        echo "error: Rust $channel (pinned in rust-toolchain.toml) is not installed. Run: (cd '$ROOT' && rustup toolchain install)" >&2
        exit 1
      fi
      export RUSTUP_TOOLCHAIN="$match"
    fi
    (cd / && "$rustup" which cargo)
    return
  fi
  if [[ -x "$_snapit_cargo_bin/cargo" ]]; then
    echo "$_snapit_cargo_bin/cargo"
    return
  fi
  command -v cargo
}

# Not in a subshell, so RUSTUP_TOOLCHAIN reaches this shell and its children.
_snapit_cargo_out="$(mktemp)"
if ! _snapit_resolve_cargo >"$_snapit_cargo_out"; then
  rm -f "$_snapit_cargo_out"
  echo "error: no usable cargo (looked for rustup in $_snapit_cargo_bin, /opt/homebrew/bin and /opt/homebrew/opt/rustup/bin, then for cargo in CARGO_HOME and PATH). Install rustup from https://rustup.rs" >&2
  exit 1
fi
CARGO="$(cat "$_snapit_cargo_out")"
rm -f "$_snapit_cargo_out"
# cargo, rustfmt and clippy find each other next to the cargo binary.
export PATH="$(dirname "$CARGO"):$PATH"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
