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

# idle_cpu_sample <pid> <seconds>: reads the process's CPU time over one-second windows (a run of 1 or 2
# seconds is one window, as long as it is) and prints `<rate> <busiest> <active> <windows>`: `rate` is the mean
# CPU seconds per second over the quietest half of the windows, `busiest` the CPU seconds of the busiest window,
# `active` how many windows used 10 ms or more, `windows` how many there were. A short burst (a loaded
# machine, a timer of the system's) lands in one or two windows and drops out of `rate`; a loop or a timer
# of snapit's that fires again and again is in every window, or in many windows spread out, and stays.
idle_cpu_sample() {
  local pid="$1" seconds="$2" windows="$2" length=1 index previous current
  local -a used=()
  if ((seconds < 3)); then windows=1; length="$seconds"; fi
  previous="$(cpu_seconds "$pid")"
  for ((index = 0; index < windows; index++)); do
    sleep "$length"
    current="$(cpu_seconds "$pid")"
    used+=("$(awk -v a="$previous" -v b="$current" 'BEGIN { printf "%.2f", b - a }')")
    previous="$current"
  done
  printf '%s\n' "${used[@]}" | sort -n | awk -v n="$windows" -v len="$length" '
    NF { v[++count] = $1; if ($1 >= 0.01) active++ }
    END { k = int((n + 1) / 2); for (i = 1; i <= k; i++) sum += v[i]; printf "%.4f %.2f %d %d", sum / k / len, v[count], active, n }'
}
# idle_cpu_ok <sample>: a run of several windows passes when the quietest half averages at most 0.5% of a CPU
# (a steady 1% fails) and at most max(2, windows / 4) windows were active (one burst and the process's own start make two) (a timer that fires every few
# seconds fails); a single short window (1 or 2 s) passes at 0.02 s of CPU, as it always did.
idle_cpu_ok() {
  local rate busiest active windows
  read -r rate busiest active windows <<<"$1"
  if ((windows == 1)); then
    awk -v used="$busiest" 'BEGIN { exit !(used <= 0.02) }'
  else
    awk -v rate="$rate" -v active="$active" -v n="$windows" 'BEGIN { max = int(n / 4); if (max < 2) max = 2; exit !(rate <= 0.005 && active <= max) }'
  fi
}

# assert_idle_cpu <label> <pid> <seconds>: the process used no CPU for <seconds> (see idle_cpu_sample).
assert_idle_cpu() {
  local sample rate busiest active windows
  sample="$(idle_cpu_sample "$2" "$3")"
  read -r rate busiest active windows <<<"$sample"
  if idle_cpu_ok "$sample"; then
    pass "$1 idles at 0% CPU (busiest of $windows window(s) ${busiest}s of CPU, $active active, over ${3}s)"
  else
    fail "$1 used CPU at idle: $active of $windows window(s) active, ${rate}s of CPU per second in the quietest half, busiest ${busiest}s, over ${3}s"
  fi
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
