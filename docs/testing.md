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
| `activation-plan test\|normal` | how the helper is brought forward when a Capture opens (`activate-at-launch`, `activate-after-open`); a scripted run never activates it |
| `capture-source` | `fixture` when the Capture source is the test one |
| `fixture-display <scale> [<w> <h>]` | chooses the fake display (scale 1 or 2, size in points) |
| `press-shortcut <id>` | presses an injected Shortcut; replies `ok` when its action has finished |
| `bound-shortcuts` | the ids of the Shortcuts that are bound |
| `shortcut-combo <id>`, `shortcut-set <id> none` or `<key code> [<modifier>...]` | read or change a Shortcut's key combination |
| `menu-shortcut <id>` | the key equivalent a menu item shows now, or `none` |
| `menu-click <id>` | runs a menu item's action; replies `ok` when it has finished |
| `pasteboard-types`, `pasteboard-dump-png <path>`, `pasteboard-clear` | read or empty the private pasteboard (`<path>` must be inside the root) |

Commands the Editor helper (`editor.sock`) answers in test mode (`snapit-editor/Commands/EditorTestCommands.swift`):

| Command | What it does |
|---|---|
| `editors` | the numbers of the open Editors, one per line (a Capture's number is the `N` in `open-capture <N>`) |
| `editor-facts <N>` | `key=value` lines about Editor N: `pixels`, `scale`, `dpi`, `window`, `canvas`, `tool`, `activation` |
| `editor-key <N> copy\|escape\|close` | sends the window the ⌘C, Esc or ⌘W key event; replies `ok` when a Copy it started has finished. A key that closes the last Editor makes the helper quit before it can reply: wait for the process to go instead |
| `editor-press <N> <item id>` | runs a toolbar item's action (`copy`, `delete-capture`, `close`, ...), as its button does |
| `editor-warm`, `editor-warm-state` | builds the Editor ahead of its Capture, hidden; replies `warm window=hidden canvas=built` or `cold` |
| `export-owned-probe <N>` | makes an owned copy of Editor N's Capture, encodes it into `<root>/probe/owned.png` and replies `ok <path>` |
| `editor-toolbar <N>` | one line per tool (`tool <id> <order> <tooltip>`) and toolbar item (`item <id> <slot> <tooltip>`) |
| `export-stages` | the Export pipeline's steps in the order they run |
| `main-menu` | the helper's menu bar menus, one line each: `<menu>: <item>\|<item>...` (`-` separator) |
| `editor-mouse <N> down\|drag\|up <x> <y>`, `editor-drag <N> <x1> <y1> <x2> <y2>` | a pointer event, or a whole press-drag-release, on Editor N's canvas at a point of the Capture (image points, origin at the top left). The event goes through the canvas's own handlers, so the zoom mapping and the active tool are exercised |
| `editor-keystroke <N> undo\|redo\|delete\|<character>` | ⌘Z, ⇧⌘Z, ⌫ or a plain key (a tool's key) as the window receives it |
| `editor-style <N> fill outline\|solid`, `width <points>`, `color <RRGGBB>` | what the style controls do: the selected Annotation and the next ones, remembered through `AppDefaults.store` |
| `editor-document <N>` | `annotation <id> <kind> <x1> <y1> <x2> <y2> <RRGGBB> <width> outline\|solid` per Annotation, then `selected=`, `undo-steps=`, `redo-steps=`, `revision=`, `tool=`, `zoom=` |
| `editor-menu-keys` | the key equivalent each Edit menu item shows: `<title> key=<hex codes> modifiers=<mask>` |
| `editor-first-click <N>` | one line per control host in the window, `<name> yes\|no`: whether the first click on a background Editor reaches it |

`editor-facts` reports `canvas=layer-hosted` only when the canvas's layer is not delegated to the
view (a layer-backed view would report `layer-backed`).

The menu bar app tells the helper to open a Capture with `open-capture <N>`; the pixels reach it
through the Capture file `<root>/captures/capture-<N>.pixels` (memory-mapped, never the socket).

## The fixture image

`FixtureCaptureSource` returns a deterministic image. At `w` x `h` pixels, pixel `(x, y)` is
`R = x*255/(w-1)`, `G = y*255/(h-1)`, `B = 40` if `x/8 + y/8` is even else `200` (integer
division). The engine tests and `scripts/run/png-inspect.swift` use the same formula, so a PNG can
be checked pixel by pixel without trusting the code under test. The default fixture is 301 x 187
points: an odd width, so engine rows are padded (never assume a stride is tight).

## Adding a flow to the scripted run

A flow is one file in `scripts/run/flows/`, named `NN-what-it-covers.sh`. `check-run.sh` starts the
menu bar app, then sources every flow in name order (`10-` menu bar app, `20-` Screen Capture
into the Editor and Copy, `30-` the Editor, `35-` the Editor's tools, `90-` Editor helper and Quit, which must stay last).
A flow can use everything in `scripts/run/lib.sh` (`send`, `send_slow`, `expect_equal`,
`expect_contains`, `wait_until`, `footprint_mb`, `assert_idle_cpu`, `png_field`, ...), the Editor
helpers in `scripts/run/editor.sh` (`capture_into_editor <trigger>` runs a Capture and sets
`EDITOR_N` and `HELPER_PID`; `copy_closes_editor`, `app_type <pid>` for Foreground (Dock icon)
versus UIElement (agent), `onscreen_windows <pid>`, `helper_pid`) and the variables `APP_SOCK`,
`EDITOR_SOCK`, `RUN_ROOT`, `APP_PID`, `INSPECT` (the `png-inspect` tool, which also lists a
process's windows: `png-inspect windows <pid>`, reads one pixel: `png-inspect pixel <file> <x> <y>`, and
compares a PNG with the fixture: `png-inspect diff-fixture <file> <w> <h> [<x0> <y0> <x1> <y1>]` prints how
many pixels changed, their bounding box and how many lie inside and outside a rectangle). A flow that draws in
the Editor sources `scripts/run/editor-tools.sh` (`drag`, `click`, `keystroke`, `style`, `export_png`,
`fixture_diff`, `fixture_pixel`, ...; `35-editor-tools.sh` is the model).

1. Pick the fixture: `send "$APP_SOCK" "fixture-display 2 301 187"`.
2. Drive the app through a command, never the real system. A Capture opens an Editor in the helper:
   `capture_into_editor "menu-click capture.screen"`, then drive the Editor with `editor-key` and
   `editor-press` on `$EDITOR_SOCK`.
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

## Adding to the Editor

Each part of the Editor is one file plus one line in a registry, so tickets that run in parallel
touch different files. Registry arrays have one entry per line with a trailing comma; two tickets
adding an entry in the same place get a one-line merge conflict, and the fix is to keep both sides.

| To add | Add a file in `snapit-editor/Editor/` | And one line in |
|---|---|---|
| an Annotation tool on the left toolbar | `Tools/<Name>Tool.swift` (`EditorTool`: `id`, `order`, `title`, `symbol`, `key`, pointer hooks in image points) | `Tools/ToolRegistry.swift` |
| a control in the top toolbar, a key equivalent or a menu item | `Toolbar/<Name>ToolbarItem.swift` (`EditorToolbarItem`: `id`, `slot`, `order`, `symbol`, `tooltip`, `perform`, and optionally `keyEquivalent` and `menu`; slot `.menuOnly` for an item with no button) | `Toolbar/ToolbarRegistry.swift` |
| an Export pipeline step | `Export/<Name>Stage.swift` (`ExportStage`: `id`, `order`, `apply`) | `Export/ExportPipeline.swift` |
| a kind of Annotation (its look, hit test, handles and Export drawing) | `Annotations/<Name>AnnotationKind.swift` (`AnnotationKind`: `id`, `paint(for:)`, and what differs from the defaults; its `static let` name goes in an `extension AnnotationKindID`) | `Annotations/AnnotationKinds.swift` |
| a tool that drags out one kind of Annotation | `Tools/<Name>Tool.swift` (`AnnotationDrawingTool`: only names its `annotationKind`) | `Tools/ToolRegistry.swift` |
| an Editor action | `EditorSession+<Name>.swift` (an extension of `EditorSession`, run by a toolbar item's `perform`) | nothing: the item that runs it is in `ToolbarRegistry` |
| a helper socket command | `Commands/<Name>Commands.swift` with a `register…Commands()` | `Commands/HelperCommands.swift` |

Position comes from each entry's `order` (and a toolbar item's `slot`), never from the line order.
`EditorWindow` runs an item's `keyEquivalent` and `HelperMainMenu` builds the Edit and Window menus
from the same registry, so no other file lists keys. Stage orders: crop 100, Redaction 200,
Annotations 300, 1x 400, then the PNG encode. Tooltips and full-size hit areas come with
`ToolbarButton` and `ChromeButtonStyle`; a custom control applies `.help` and `.contentShape`
itself.

The Export pipeline never touches the Capture's mapping, which is read-only (`PixelBuffer` refuses
`withPixels` and `draw` on it). The first stage that changes pixels makes the Export's one owned
buffer (`image.makeOwned()`, or crop's smaller `makeEmptyBuffer`); later stages change it in place.
Buffers made from another carry its ICC profile along. Document state a stage reads is copied into
`ExportJob` (`EditorDocument.makeExportJob`) so the pipeline runs off the main actor. `flatten`
returns the flattened image for a sink (Save's shared export file); `run` also Fast-encodes it.

The Editor's window, toolbars and canvas layers are built without a Capture (`EditorSession()`),
and `attach(_:)` gives it the Capture: a warming-up helper calls `EditorSessions.warmUp()` ahead of
time. The helper's windows all go through `HelperLifecycle`: call `windowWillShow()` before showing
a window (it makes the helper a regular app) and `windowDidShow()` after. The helper quits when its
last window closes.

### Annotations

An `Annotation` is a `Codable` value (`id`, a kind name, `start` and `end` in image points, a
style); the document keeps them in an `AnnotationHistory`, which is also `Codable` and holds the
snapshot Undo and Redo steps (100 each, oldest dropped) and the revision. A change is a gesture
(`begin`, `mutate`, `end`: one Undo step, only if the state differs) or one `change`; all of it goes
through `EditorDocument.edit`, which tells the canvas. A field added to a stored type is decoded
with `decodeIfPresent` and a default (as `AnnotationStyle` does), so what an older snapit stored
still opens.

A kind's `paint(for:)` (path, fill, stroke) feeds both the canvas's `CAShapeLayer` and the Export's
Core Graphics drawing, so the preview is the Export. Hit tests are exact (the inside of a filled
Annotation, the stroke of an outline). `AnnotationStage` draws every Annotation whose kind has
`drawnByAnnotationStage` true, in document order, onto the Export's owned buffer; a stage of another
feature filters `job.annotations` by `kind` (Redaction's `RedactionStage` takes its own kind and
sets `drawnByAnnotationStage` false). Selection, the style the next Annotation gets and the gesture
in progress live on the `EditorSession` (`EditorSession+Annotations.swift`), never in a tool: tools
are shared by every open Editor. The Annotation color, width and fill used last are remembered in
`AnnotationSettings` (`annotationColor` as `RRGGBB`, `annotationWidth`, `annotationFilled`).

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
