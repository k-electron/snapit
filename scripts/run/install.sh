# Helpers for flows that move snapit between places (the install location check). Sourced by
# scripts/check-run.sh after lib.sh, which sets RUN_ROOT first.
# shellcheck shell=bash

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

# The run's root with symlinks resolved (/tmp is /private/tmp): the form paths take once a
# relaunched copy reports where it runs from.
real_root() { (cd -P "$RUN_ROOT" && pwd); }

# unregister_fixture_apps: every .app copy a flow placed under the run's root (the fixture
# Applications folder and the fake disk image volumes) is removed from LaunchServices.
unregister_fixture_apps() {
  local app
  while IFS= read -r app; do
    "$LSREGISTER" -u "$app" 2>/dev/null || true
  done < <(find "$RUN_ROOT/Applications" "$RUN_ROOT/Volumes" -maxdepth 5 -name '*.app' 2>/dev/null)
}

# detach_update_images: a disk image an Update attached under the run's root (at <root>/update-staging/volume)
# and left attached, for a run that stopped half way. A finished Update has detached it.
detach_update_images() {
  local mount_point
  while IFS= read -r mount_point; do
    [[ -n "$mount_point" ]] && diskutil eject "$mount_point" >/dev/null 2>&1
  done < <(mount | sed -n "s|^.* on \(.*$(basename "$RUN_ROOT")/update-staging/volume\) (.*|\1|p")
}

# build_update_image <dir> <image file name> <bundle version> [<bundle identifier>] [tamper]: the
# files of a release for an Update to download, in <dir>: a disk image of that name holding a copy
# of the built snapit ($APP) at that version (both Info.plists), signed ad hoc (the helper first,
# then the app: no --deep), and the image's .sha256 in the form the release publishes. A bundle
# identifier replaces the copy's own; `tamper` changes the helper's program after signing, so the
# signature no longer verifies. Aborts the run when the copy's signature is not what was asked for.
# The copy and its LaunchServices registrations are removed again.
build_update_image() {
  local dir="$1" image="$2" version="$3" identifier="${4:-}" tamper="${5:-}" app plist
  app="$dir/src/snapit.app"
  mkdir -p "$dir/src"
  ditto --norsrc --noextattr "$APP" "$app"
  for plist in "$app/Contents/Info.plist" "$app/Contents/Helpers/snapit Editor.app/Contents/Info.plist"; do
    plutil -replace CFBundleShortVersionString -string "$version" "$plist"
  done
  if [[ -n "$identifier" ]]; then plutil -replace CFBundleIdentifier -string "$identifier" "$app/Contents/Info.plist"; fi
  codesign --force --sign - --timestamp=none --options runtime "$app/Contents/Helpers/snapit Editor.app" >/dev/null 2>&1
  codesign --force --sign - --timestamp=none --options runtime "$app" >/dev/null 2>&1
  if [[ "$tamper" == tamper ]]; then printf 'x' >>"$app/Contents/Helpers/snapit Editor.app/Contents/MacOS/snapit Editor"; fi
  if codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
    if [[ "$tamper" == tamper ]]; then abort "the tampered copy for $image still verifies"; fi
  elif [[ "$tamper" != tamper ]]; then
    abort "the copy for $image does not verify"
  fi
  hdiutil create -srcfolder "$dir/src" -volname snapit -format UDZO -quiet "$dir/$image" >/dev/null 2>&1
  (cd "$dir" && shasum -a 256 "$image" >"$image.sha256")
  "$LSREGISTER" -u "$app/Contents/Helpers/snapit Editor.app" 2>/dev/null
  "$LSREGISTER" -u "$app" 2>/dev/null
  rm -rf "$dir/src"
  if [[ -s "$dir/$image" && -s "$dir/$image.sha256" ]]; then return 0; fi
  abort "no disk image was built for $image"
}

# quarantine_count <path>: how many items under <path> carry com.apple.quarantine.
quarantine_count() { xattr -rl "$1" 2>/dev/null | grep -c 'com.apple.quarantine:' | tr -d ' '; }

# approve_quarantine <path>: marks <path> and everything inside as quarantined and approved with
# Open Anyway (flags 00c3, as macOS writes them). unapprove_quarantine writes 0083, which is
# quarantined and not approved.
approve_quarantine() { xattr -rw com.apple.quarantine "00c3;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$1"; }
unapprove_quarantine() { xattr -rw com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$1"; }

# wait_for_pid <executable path>: waits for a process of that executable and prints its pid.
wait_for_pid() {
  local deadline=$((SECONDS + ${2:-20})) found
  while ((SECONDS < deadline)); do
    found="$(pid_of "$1")"
    if [[ -n "$found" ]]; then echo "$found"; return 0; fi
    sleep 0.2
  done
  return 1
}
