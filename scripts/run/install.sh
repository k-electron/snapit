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
