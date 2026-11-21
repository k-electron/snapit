# Helpers for the scripted whole-app run. Sourced by scripts/check-run.sh, which sets
# APP, APP_EXE, HELPER_EXE, RUN_ROOT, APP_SOCK, EDITOR_SOCK, INSPECT and ROOT_DIR first.
# A flow (scripts/run/flows/NN-name.sh) is sourced after these helpers and may use them.
# shellcheck shell=bash

failures=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
expect_equal() { # description, expected, actual
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
expect_contains() { # description, needle, haystack
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1 (expected to contain '$2', got '$3')"; fi
}
# expect_in_order <description> <haystack> <line>...: every line given is a whole line of the
# haystack, in the order given. Other lines may sit between them, so parallel tickets can add theirs.
expect_in_order() {
  local description="$1" haystack="$2" wanted="" found
  shift 2
  local -a remaining=()
  while IFS= read -r found; do remaining+=("$found"); done <<<"$haystack"
  local index=0
  for wanted in "$@"; do
    while ((index < ${#remaining[@]})) && [[ "${remaining[index]}" != "$wanted" ]]; do index=$((index + 1)); done
    if ((index >= ${#remaining[@]})); then
      fail "$description (missing or out of order: '$wanted' in: ${haystack//$'\n'/|})"
      return
    fi
    index=$((index + 1))
  done
  pass "$description"
}
abort() { echo "FAIL $1"; exit 1; }

# One command to a snapit process: send <socket> "<command line>". Arguments with spaces are
# percent-encoded. SEND_TIMEOUT (seconds, default 2) is how long to wait for the reply.
send() { printf '%s\n' "$2" | nc -U -w "${SEND_TIMEOUT:-2}" "$1" 2>/dev/null; }
# The same, for commands that run a whole Capture.
send_slow() { SEND_TIMEOUT=30 send "$@"; }

wait_until() { # seconds, command...
  local deadline=$((SECONDS + $1))
  shift
  while ((SECONDS < deadline)); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}
answers() { [[ "$(send "$1" ping)" == "pong" ]]; }
pid_of() { pgrep -f "$1" | head -1; }
gone() { ! kill -0 "$1" 2>/dev/null; }
cpu_seconds() { ps -o cputime= -p "$1" | awk -F'[:]' '{ print ($1 * 60) + $2 }'; }
footprint_mb() { footprint -p "$1" 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "Footprint:") { v = $(i+1); u = $(i+2); if (u == "KB") v = v / 1024; if (u == "GB") v = v * 1024; printf "%.1f", v; exit } }'; }

# Resources are judged by AGENTS.md's four questions (docs/testing.md, "Resource checks"). A check here
# measures a process against its own baseline and the size of what the feature holds, with margins that
# no machine's noise reaches, and it is the same on every machine.

# pixels_mb <width> <height>: the size in MB of a 4-byte-per-pixel image of that many pixels.
pixels_mb() { awk -v w="$1" -v h="$2" 'BEGIN { printf "%.1f", w * h * 4 / 1048576 }'; }

# memory_margin_mb [<feature MB>]: how far above its baseline a process may stand once a flow has ended: the
# larger of 25 MB and half of the feature's own size (a 5K Capture's pixels are 56 MB, so 28 MB).
memory_margin_mb() { awk -v f="${1:-0}" 'BEGIN { m = f / 2; if (m < 25) m = 25; printf "%.1f", m }'; }

# expect_memory_returns <label> <pid> <baseline MB> [<feature MB>]: the process's footprint is back near
# <baseline> (see memory_margin_mb). Memory the system gives back late is waited for, up to 10 s; what a
# flow keeps for good stays above the margin and fails.
expect_memory_returns() {
  local label="$1" pid="$2" baseline="$3" margin now=""
  margin="$(memory_margin_mb "${4:-0}")"
  memory_is_back() {
    now="$(footprint_mb "$pid")"
    awk -v a="$now" -v b="$baseline" -v max="$margin" 'BEGIN { exit !(a > 0 && a - b <= max) }'
  }
  if wait_until 10 memory_is_back; then
    pass "$label (${baseline} MB before, ${now} MB after, margin ${margin} MB)"
  else
    now="$(footprint_mb "$pid")"
    fail "$label: memory is '${now}' MB, its baseline was ${baseline} MB (margin ${margin} MB)"
  fi
}

# expect_steady_across_cycles <label> <lowest MB> <highest MB> [<feature MB>]: a footprint measured once per
# cycle stayed within the margin of memory_margin_mb from one cycle to the next.
expect_steady_across_cycles() {
  local label="$1" low="$2" high="$3" margin
  margin="$(memory_margin_mb "${4:-0}")"
  if awk -v lo="$low" -v hi="$high" -v max="$margin" 'BEGIN { exit !(lo > 0 && hi - lo <= max) }'; then
    pass "$label (${low} to ${high} MB, margin ${margin} MB)"
  else
    fail "$label: it varies from '${low}' to '${high}' MB (margin ${margin} MB)"
  fi
}

# expect_peak_proportionate <label> <peak MB> <baseline MB> <feature MB>: what a feature held at its peak is
# roughly its own size on top of the baseline: at most four times the feature plus 25 MB.
expect_peak_proportionate() {
  local label="$1" peak="$2" baseline="$3" feature="$4"
  if awk -v p="$peak" -v b="$baseline" -v f="$feature" 'BEGIN { exit !(p > 0 && p - b <= 4 * f + 25) }'; then
    pass "$label: peak ${peak} MB over a ${baseline} MB baseline, for a feature of ${feature} MB"
  else
    fail "$label: peak ${peak} MB over a ${baseline} MB baseline is far more than a feature of ${feature} MB needs"
  fi
}

# expect_not_spinning <label> <pid> <seconds>: the process used under 5% of one CPU, on average, over
# <seconds> (5 or more). A loop or a timer that never stops shows; an event the system sends does not.
expect_not_spinning() {
  local label="$1" pid="$2" seconds="$3" before after used
  if gone "$pid"; then fail "$label: the process is not running"; return; fi
  before="$(cpu_seconds "$pid")"
  sleep "$seconds"
  after="$(cpu_seconds "$pid")"
  used="$(awk -v a="$before" -v b="$after" 'BEGIN { printf "%.2f", b - a }')"
  if [[ -n "$before" && -n "$after" ]] && awk -v used="$used" -v s="$seconds" 'BEGIN { exit !(used <= 0.05 * s) }'; then
    pass "$label is not spinning (${used} s of CPU over ${seconds} s)"
  else
    fail "$label is using CPU at rest (${used} s of CPU over ${seconds} s)"
  fi
}

# expect_cache_holds_only_expected <label>: the cache folder (the run's root) holds only what a flow's end
# leaves: no shared export file, no partial file, the files of at most one Last Capture, and PNGs in drag-out.
expect_cache_holds_only_expected() {
  local unexpected
  unexpected="$(cache_leftovers)"
  if [[ -z "$unexpected" ]]; then
    pass "$1: the cache folder holds only the expected files"
  else
    fail "$1: the cache folder holds unexpected files: ${unexpected//$'\n'/ | }"
  fi
}
cache_leftovers() {
  (
    cd "$RUN_ROOT" || exit 0
    find exports -type f 2>/dev/null
    find captures -type f ! -name 'capture-*.pixels' ! -name 'capture-*.state' 2>/dev/null
    find captures -type f \( -name 'capture-*.pixels' -o -name 'capture-*.state' \) 2>/dev/null |
      sed -E 's/^captures\/capture-([0-9]+)\..*/\1/' | sort -u | tail -n +2 | sed 's/^/a second Last Capture, number /'
    find drag-out -type f ! -name '*.png' 2>/dev/null
    find . -name '*.partial' 2>/dev/null
  ) | sort -u
}

# expect_no_internet <label> <pid>: the process has no internet (TCP or UDP) socket open. The fixture
# endpoint opens none, so neither process may ever have one in a run, whatever API would open it.
expect_no_internet() {
  local sockets
  sockets="$(lsof -nP -a -i -p "$2" 2>/dev/null)"
  if [[ -z "$sockets" ]]; then pass "$1 has no internet socket open"; else fail "$1 has an internet socket open: ${sockets//$'\n'/ | }"; fi
}

# png_field <info output> <key>: one value out of `png-inspect info`.
png_field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

# Isolation: a test run must leave the user's machine as it found it. isolation_begin takes
# a snapshot of everything a run could touch by mistake; isolation_check compares at the end.
# (Not snapshotted: ~/Downloads, which a terminal may not be allowed to list. The run's Save
# location is <root>/save, checked by the `test-seams` assertions.)
isolation_state() {
  echo "-- preference files"
  find "$HOME/Library/Preferences" -maxdepth 1 -name 'dev.snapit.snapit*.plist' -exec stat -f '%N %m %z' {} + 2>/dev/null | sort
  echo "-- preferences as cfprefsd sees them"
  defaults read dev.snapit.snapit 2>&1 | shasum
  defaults read dev.snapit.snapit.editor 2>&1 | shasum
  echo "-- real cache folder"
  find "$HOME/Library/Caches/dev.snapit.snapit" -exec stat -f '%N %m %z' {} + 2>&1 | sort
}
# The general pasteboard is the user's. `general-pasteboard` prints the change count and, only when the count
# rose, a shape (`png`, `hex` for a plain string of the form #RRGGBB, `other` or `empty`; the string is
# matched in memory, never printed or kept), nothing else. snapit writes only a PNG (Copy) or such a hex string (the Color picker), so a rise
# in the count counts against the run only when the pasteboard now holds one of those shapes. A user who
# copies something else during a run does not fail it; one who copies a PNG or a #RRGGBB string still does.
# pasteboard_state <previous change count, or "-"> [<pasteboard name>]: `change_count=<n> shape=<shape>`. The shape
# is looked at only when the count differs from the previous one, so an untouched pasteboard is never read.
pasteboard_state() { "$INSPECT" general-pasteboard "$@" | tr '\n' ' '; }
# pasteboard_field <state> <key>: one value of a state line.
pasteboard_field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }
# pasteboard_verdict <state before> <state after>: `untouched`, `user-copy` or `touched`.
pasteboard_verdict() {
  local before after shape
  before="$(pasteboard_field "$1" change_count)"
  after="$(pasteboard_field "$2" change_count)"
  shape="$(pasteboard_field "$2" shape)"
  if [[ "$before" == "$after" ]]; then echo untouched
  elif [[ "$shape" == png || "$shape" == hex ]]; then echo touched
  else echo user-copy
  fi
}
isolation_begin() { ISOLATION_BEFORE="$(isolation_state)"; PASTEBOARD_BEFORE="$(pasteboard_state -)"; }
isolation_check() {
  local after pasteboard
  after="$(isolation_state)"
  pasteboard="$(pasteboard_verdict "$PASTEBOARD_BEFORE" "$(pasteboard_state "$(pasteboard_field "$PASTEBOARD_BEFORE" change_count)")")"
  if [[ "$ISOLATION_BEFORE" == "$after" && "$pasteboard" != touched ]]; then
    pass "isolation: no snapit preferences, real cache folder or general pasteboard were touched"
    [[ "$pasteboard" == user-copy ]] && echo "     (the general pasteboard changed, to something snapit never writes: not snapit's)"
  else
    fail "isolation: the run touched the real system"
    [[ "$pasteboard" == touched ]] && echo "     the general pasteboard changed to a PNG or a #RRGGBB string"
    diff <(echo "$ISOLATION_BEFORE") <(echo "$after") | sed 's/^/     /'
  fi
}

# The Editor helper's processes and the warm-up state, shared by the flows.
helper_count() { pgrep -f "$HELPER_EXE" | wc -l | tr -d ' '; }
no_helper() { [[ "$(helper_count)" == "0" ]]; }
some_helper() { [[ "$(helper_count)" != "0" ]]; }
one_snapit() { [[ "$(pgrep -f "$APP_EXE" | wc -l | tr -d ' ')" == "1" ]]; }
warm_state() { send "$APP_SOCK" "editor-warm-up state"; }
warm_is() { [[ "$(warm_state)" == "$1" ]]; }

# launch_app [<root>]: starts a menu bar app in the background in test mode under <root> (default: this
# run's), appending to <root>/app.log. The caller waits for its socket.
launch_app() {
  local root="${1:-$RUN_ROOT}"
  (SNAPIT_TEST_ROOT="$root" nohup "$APP_EXE" >>"$root/app.log" 2>&1 &)
}
# relaunch_app [<why>]: starts this run's menu bar app again (it has quit or been killed), waits until it
# answers and sets APP_PID. The run stops when it does not start.
relaunch_app() {
  launch_app
  if wait_until 15 answers "$APP_SOCK"; then pass "snapit starts again${1:+ ($1)}"; else abort "snapit did not start again${1:+ ($1)}"; fi
  APP_PID="$(pid_of "$APP_EXE")"
}
# restart_app [<why>]: quits this run's menu bar app (when it is running), waits for it to go, and starts it again.
restart_app() {
  send "$APP_SOCK" quit >/dev/null
  wait_until 30 gone "$APP_PID"
  relaunch_app "$@"
}
