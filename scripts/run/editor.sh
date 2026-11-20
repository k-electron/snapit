# Helpers for flows that open the Editor. Sourced by scripts/check-run.sh after lib.sh, which
# sets HELPER_EXE, APP_SOCK, EDITOR_SOCK, RUN_ROOT and INSPECT first.
# shellcheck shell=bash

helper_pid() { pid_of "$HELPER_EXE"; }

# The helper's application type as lsappinfo reports it: Foreground (a regular app: Dock icon,
# Cmd-Tab entry, its own menus) or UIElement (an agent: none of those). Empty when it is gone.
app_type() { lsappinfo info -only applicationType "$(lsappinfo find pid="$1")" 2>/dev/null | sed -n 's/.*type="\([A-Za-z]*\)".*/\1/p'; }
is_foreground() { [[ "$(app_type "$1")" == "Foreground" ]]; }

# How many ordinary windows of the process are on screen, from the window server (no names read).
onscreen_windows() { "$INSPECT" windows "$1" | grep -c onscreen; }
has_onscreen_window() { (($(onscreen_windows "$1") >= 1)); }

# The numbers of the open Editors, one per line.
open_editors() { send "$EDITOR_SOCK" editors; }

# capture_into_editor <trigger command>: runs the Capture (menu-click or press-shortcut) and
# waits until the Editor window is showing. Sets EDITOR_N (the Editor's number) and HELPER_PID.
capture_into_editor() {
  local reply
  reply="$(send_slow "$APP_SOCK" "$1")"
  if [[ "$reply" != "ok" ]]; then
    fail "the Capture ($1) finished with '$reply'"
    return 1
  fi
  EDITOR_N="$(open_editors | tail -1)"
  HELPER_PID="$(helper_pid)"
  [[ -n "$EDITOR_N" && -n "$HELPER_PID" ]]
}

# copy_closes_editor: presses ⌘C in the open Editor and waits for the helper to quit (close
# after Copy is on by default).
copy_closes_editor() {
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N copy" >/dev/null
  wait_until 10 gone "$HELPER_PID"
}
