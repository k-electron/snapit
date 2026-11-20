# Testing snapit

Two seams, both run by `scripts/test.sh` (and CI):

1. **The scripted whole-app run**, `scripts/check-run.sh`. It starts the built `snapit.app` in
   hidden *test mode* and drives it from the outside.
2. **The engine's C-ABI tests**, `cargo test`. They call the same `snapit_*` functions Swift calls,
   with fixture buffers.

Tests assert only on what is observable: the pasteboard's PNG, files, sockets and their replies,
processes, CPU and memory. They never reach into classes or private state.

## Test mode

Setting `SNAPIT_TEST_ROOT` to a folder turns test mode on for a process (the menu bar app passes
it on to the Editor helper it starts). `scripts/check-run.sh` makes a fresh root per run, so two
runs, two worktrees and the user's own snapit never collide. In test mode every edge that touches
the real system is replaced:

| Edge | Normal | Test mode | Code |
|---|---|---|---|
| cache folder and sockets | `~/Library/Caches/dev.snapit.snapit` | the root | `Shared/AppIdentity.swift` |
| Capture source | ScreenCaptureKit | fixture images, 1x sRGB or 2x Display P3 | `snapit/Capture/` |
| Screen Recording permission | `CGPreflightScreenCaptureAccess` | granted, never prompts | `Shared/Edges/ScreenRecordingPermission.swift` |
| pasteboard | `NSPasteboard.general` | private pasteboard `dev.snapit.test.<run>` | `Shared/Edges/AppPasteboard.swift` |
| Save location | `~/Downloads` | `<root>/save` | `Shared/Edges/SaveLocation.swift` |
| defaults | the menu bar app's bundle ID domain, in both processes | `<root>/defaults.plist` | `Shared/Edges/AppDefaults.swift` |
| Shortcuts | KeyboardShortcuts (Carbon hot keys) | injected events (`press-shortcut`) | `snapit/Shortcuts/` |

Product code always asks the edge (`AppPasteboard.current`, `SaveLocation.folder`,
`AppDefaults.store`, `CaptureSources.current`, `Shortcuts.current`, ...) and never the real system
directly: not `NSPasteboard.general`, `UserDefaults.standard`, `~/Downloads`,
`CGPreflightScreenCaptureAccess` or `KeyboardShortcuts` outside its registrar. KeyboardShortcuts
writes `UserDefaults.standard` the moment a name with an initial value is created, which is why test
mode never touches it.

### Shortcuts, and the two processes

KeyboardShortcuts stores the user's choice in `UserDefaults.standard` of the process it runs in, so
it works only in the menu bar app. The Editor helper (Settings, Onboarding) must not use
KeyboardShortcuts' recorder or storage. It uses a binding-based recorder, stores the combination
through `AppDefaults.store`, and sends a socket command; the menu bar app then applies it with
`Shortcuts.current.setCombo(_:for:)`. `ShortcutRegistrar` also has `combo(for:)` and
`menuShortcut(for:)` (the menu item's glyph follows the current Shortcut). A Shortcut that is
unassigned by default, like Pick Color, has `defaultKeyCode: nil`. Test mode never touches
KeyboardShortcuts: `InjectedShortcuts` keeps the combos in a dictionary.

Test mode adds socket commands (they exist only while test mode is on). The scripted run sends them
to `$RUN_ROOT/app.sock` (menu bar app) or `$RUN_ROOT/editor.sock` (Editor helper), one line each:

| Command | What it does |
|---|---|
| `test-seams` | one `key=value` line per edge: root, pasteboard, save, cache, permission |
| `defaults-set <key> <value>`, `defaults-get <key>` | write or read a string through `AppDefaults.store`; the run writes in one process and reads in the other |
| `capture-source` | `fixture` when the Capture source is the test one |
| `fixture-display <scale> [<w> <h>]` | chooses the fake display (scale 1 or 2, size in points) |
| `press-shortcut <id>` | presses an injected Shortcut; replies `ok` when its action has finished |
| `bound-shortcuts` | the ids of the Shortcuts that are bound |
| `shortcut-combo <id>`, `shortcut-set <id> none` or `<key code> [<modifier>...]` | read or change a Shortcut's key combination |
| `menu-shortcut <id>` | the key equivalent a menu item shows now, or `none` |
| `menu-click <id>` | runs a menu item's action; replies `ok` when it has finished |
| `pasteboard-types`, `pasteboard-dump-png <path>`, `pasteboard-clear` | read or empty the private pasteboard (`<path>` must be inside the root) |

## The fixture image

`FixtureCaptureSource` returns a deterministic image. At `w` x `h` pixels, pixel `(x, y)` is
`R = x*255/(w-1)`, `G = y*255/(h-1)`, `B = 40` if `x/8 + y/8` is even else `200` (integer
division). The engine tests and `scripts/run/png-inspect.swift` use the same formula, so a PNG can
be checked pixel by pixel without trusting the code under test. The default fixture is 301 x 187
points: an odd width, so engine rows are padded (never assume a stride is tight).

## Adding a flow to the scripted run

A flow is one file in `scripts/run/flows/`, named `NN-what-it-covers.sh`. `check-run.sh` starts the
menu bar app, then sources every flow in name order (`10-` menu bar app, `20-` Screen Capture,
`90-` Editor helper and Quit, which must stay last). A flow can use everything in
`scripts/run/lib.sh` (`send`, `send_slow`, `expect_equal`, `expect_contains`, `wait_until`,
`footprint_mb`, `assert_idle_cpu`, `png_field`, ...) and the variables `APP_SOCK`, `EDITOR_SOCK`,
`RUN_ROOT`, `APP_PID`, `INSPECT` (the `png-inspect` tool).

1. Pick the fixture: `send "$APP_SOCK" "fixture-display 2 301 187"`.
2. Drive the app through a command, never the real system.
3. Assert on what is observable: dump the pasteboard PNG (`pasteboard-dump-png`), read it with
   `"$INSPECT" info` and `"$INSPECT" verify-fixture`, look at files under `$RUN_ROOT/save`, measure
   `footprint_mb` and `assert_idle_cpu`.
4. Delete what you create under `$RUN_ROOT` (the run removes the root at the end).

`check-run.sh` also ends with the isolation assertion: no `dev.snapit.snapit*.plist` in
`~/Library/Preferences` is new or changed, `defaults read` of the bundle ID domains is unchanged,
`~/Library/Caches/dev.snapit.snapit` is unchanged and the general pasteboard's change count is the
same as before the run.

## Adding an edge or a test-mode command

A feature that touches a new part of the real system adds one file for that edge:

- a protocol (or small enum) with the real implementation beside it,
- a `current` that returns the fixture or the fake when `TestMode.isActive`,
- the fixture type in its own file,
- its test-mode commands in a `…Commands.swift` file: a `SocketCommand` constant and a
  `register…TestCommands()` extension on `SocketCommandRegistry` that starts with
  `guard TestMode.isActive else { return }`, called by one line in `registerAppCommands()`
  (`snapit/Commands/AppCommands.swift`) or `registerHelperCommands()`
  (`snapit-editor/Commands/HelperCommands.swift`).

`snapit/Capture/CaptureSource.swift` with `FixtureCaptureSource.swift` and `CaptureCommands.swift`
is the model to copy. Edges both processes need live in `Shared/Edges/`; their commands in
`Shared/TestMode/TestModeCommands.swift`.

## Adding a Shortcut

Add an `AppShortcut` in its own file (`snapit/Shortcuts/AppShortcut.swift` shows the shape), bind
it with one line in `ShortcutBindings`, and press it in a flow with `press-shortcut <id>`.

## Engine tests

`engine/tests/*.rs` call the C-ABI functions directly. `engine/tests/support/mod.rs` has the fixture
builder (any stride, padding filled with garbage that must never reach the output) and a PNG chunk
reader that does not use the encoder under test. A new engine function gets a test file with:
a round trip, a non-tight stride, invalid arguments (null pointers, zero sizes, overflow) and its
metadata. After changing the C interface run `scripts/generate-header.sh` and commit the header.

## Never in a test

Touch the real clipboard, `~/Downloads`, the real cache folder or the bundle ID's `UserDefaults`
domain; register a real hot key; trigger a Screen Recording prompt. The paths the scripted run does
not exercise are the real ScreenCaptureKit Capture, real hot keys, and the real Screen Recording
permission and its prompt; they run only in a real install.
