#!/usr/bin/env bash
# Sourced by the scripts that call Xcode's tools (xcodebuild, xcrun, swift, swiftc). Makes sure
# they find a full Xcode even when `xcode-select -p` points at the Command Line Tools, which
# have no xcodebuild.
#
# It does nothing when DEVELOPER_DIR is already set (CI sets it, and so does anyone who chose
# an Xcode on purpose) or when the active developer directory already holds a working
# xcodebuild. Otherwise it exports DEVELOPER_DIR for the first Xcode that answers
# `xcodebuild -version`: /Applications/Xcode.app first, then the newest other
# /Applications/Xcode*.app. It runs no sudo and changes no system setting: the choice lives in
# this shell and its children only. When it finds no Xcode it prints how to fix that and exits.

_snapit_xcode_works() { # [developer dir]: does a full Xcode answer there (or, with none given, by default)?
  if [[ -n "${1:-}" ]]; then
    DEVELOPER_DIR="$1" xcodebuild -version >/dev/null 2>&1
  else
    xcodebuild -version >/dev/null 2>&1
  fi
}

_snapit_select_xcode() {
  local app
  if [[ -n "${DEVELOPER_DIR:-}" ]] || _snapit_xcode_works; then
    return 0
  fi
  # Xcode.app first, then the others, newest name last in `sort -V` and so tried first.
  while IFS= read -r app; do
    [[ -n "$app" && -d "$app/Contents/Developer" ]] || continue
    if _snapit_xcode_works "$app/Contents/Developer"; then
      export DEVELOPER_DIR="$app/Contents/Developer"
      return 0
    fi
  done < <(
    echo /Applications/Xcode.app
    ls -d /Applications/Xcode*.app 2>/dev/null | grep -vx /Applications/Xcode.app | sort -V -r
  )
  echo "error: no usable Xcode. \`xcode-select -p\` is $(xcode-select -p 2>/dev/null || echo 'unset') and no /Applications/Xcode*.app answers \`xcodebuild -version\` (is the license accepted?). Install Xcode 27, or set DEVELOPER_DIR to an Xcode's Contents/Developer folder, for example: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" >&2
  return 1
}

_snapit_select_xcode || exit 1
