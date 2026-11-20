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
| Area Capture source (frozen displays, the pointer) | one ScreenCaptureKit capture per display | the fixture image for each fake display, the pointer in the middle of the first | `snapit/Area/AreaCaptureSource.swift` |
| window list (hover highlight) | the window server's on-screen list | two fixed overlapping windows over the first fake display | `snapit/Area/OnScreenWindowSource.swift` |
| Screen Recording permission | `CGPreflightScreenCaptureAccess` | granted, never prompts | `Shared/Edges/ScreenRecordingPermission.swift` |
| pasteboard | `NSPasteboard.general` | private pasteboard `dev.snapit.test.<run>` | `Shared/Edges/AppPasteboard.swift` |
| Save location | `~/Downloads` | `<root>/save` | `Shared/Edges/SaveLocation.swift` |
| defaults | the menu bar app's bundle ID domain, in both processes | `<root>/defaults.plist` | `Shared/Edges/AppDefaults.swift` |
| Shortcuts | KeyboardShortcuts (Carbon hot keys) | injected events (`press-shortcut`) | `snapit/Shortcuts/` |
| install location | `Bundle.main.bundlePath`, `statfs`, `/Applications`, `/Volumes`, `diskutil eject` | `<root>/Applications`, fake volumes below `<root>/Volumes`, a pretended bundle path, a fake eject (`<root>/install/ejected`); relaunches are real | `snapit/Install/` |

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
| `fixture-delay <ms>` | how long the fixture Capture takes to return: the time spent choosing an Area |
| `editor-warm-up begin\|cancel\|state\|settle` | what a Capture does when it starts and when it is cancelled; `state` is `idle`, `starting` or `warm`; `settle` waits until the helper has been started and told about every Cancel so far |
| `overlay-screens-changed` | tells the Area overlay the displays changed (macOS's notification); the overlay ends |
| `fixture-fail on\|off` | makes the fixture Capture fail, so a flow can check what a Capture that ends without a Capture does (it cancels the warm-up) |
| `capture-timing` | `capture-to-editor-ms=<n> warm=yes\|no` for the last Capture: from its pixels being ready (the Capture itself is not counted) to the Editor window on screen: writing the Capture file, the command to the helper, attaching, showing, and the helper flushing its drawing before it replies. A normal run adds asking macOS to bring the helper forward |
| `fixture-display <scale> [<w> <h>]` | chooses the fake display (scale 1 or 2, size in points) |
| `fixture-extra-display <scale> <w> <h> [right\|left\|above]` or `none` | adds a second fake display next to the first, with its own scale and size; left and above put it at negative coordinates (the Area overlay gets one panel per display) |
| `fixture-pixel-layout alpha-first\|skip-first` | the layout of the first fake display's frozen image: premultiplied BGRA (the engine's in-place crop) or BGRX from a plain bitmap (the crop's fallback) |
| `press-shortcut <id>` | presses an injected Shortcut; replies `ok` when its action has finished. The Area Shortcut's action finishes when the overlay is showing; the rest is the scripted run's mouse |
| `bound-shortcuts` | the ids of the Shortcuts that are bound |
| `shortcut-combo <id>`, `shortcut-set <id> none` or `<key code> [<modifier>...]` | read or change a Shortcut's key combination |
| `menu-shortcut <id>` | the key equivalent a menu item shows now, or `none` |
| `menu-click <id>` | runs a menu item's action; replies `ok` when it has finished |
| `overlay-mouse move\|down\|drag\|up <display> <x> <y>` | sends the Area overlay a real mouse `NSEvent` at a point of that display (points from its top-left corner; 0 is the first display) |
| `overlay-key escape\|enter\|<key code>` | sends the overlay a key event through the application's event dispatch |
| `overlay-wait` | after a mouse-up or Esc: waits for the overlay to finish; replies `opened <N>` (Capture N is in the Editor), `cancelled` or `failed <why>` |
| `overlay-facts` | what the overlay shows: `displays`, `state`, `display`, `cursor`, `hover`, `selection`, `view` (`layer-hosted` when no view draws), `shown-ms` (Shortcut to overlay on screen) |
| `overlay-snapshot <display> <path>` | renders that display's layers to a PNG inside the root; the run reads pixels back with `png-inspect pixel` to check the dim and the cutout |
| `pasteboard-types`, `pasteboard-dump-png <path>`, `pasteboard-clear` | read or empty the private pasteboard (`<path>` must be inside the root) |
| `save-hold`, `save-release` | hold every Save's write (the encode into the Save location) until released, so the run can quit the helper while a Save is still being written |
| `save-pending` | how many Saves are still being written |
| `install-location` | where the menu bar app runs from: `bundle`, `translocated`, `origin`, `on-disk-image`, `mount`, `decision` (`none`, `move`, `fix-in-place`) as `key=value` lines. Also answers in a normal run |
| `install-check` | runs the launch check again; replies `none`, `move-screen-shown`, `fixed-in-place` or `not-approved` |
| `install-pretend-bundle <path>`, `install-fake-volume <path> <fs> <from> <mount> ro\|rw`, `install-reset` | make this process behave as if it ran from `<path>`, give `<path>` (and below) a fake volume for `statfs`, forget both. Paths must be inside the root |
| `install-detect <path>` | detection with the real `statfs` and `/Volumes`, same reply as `install-location` |

Commands the Editor helper (`editor.sock`) answers in test mode (`snapit-editor/Commands/EditorTestCommands.swift`):

| Command | What it does |
|---|---|
| `editors` | the numbers of the open Editors, one per line (a Capture's number is the `N` in `open-capture <N>`) |
| `editor-facts <N>` | `key=value` lines about Editor N: `pixels`, `scale`, `dpi`, `window`, `canvas`, `tool`, `activation` |
| `editor-key <N> copy\|save\|escape\|close` | sends the window the ⌘C, ⌘S, Esc or ⌘W key event; replies `ok` when a Copy or Save it started has been handed over (the helper's part of a Save ends when the menu bar app has accepted it). A key that closes the last Editor makes the helper quit before it can reply: wait for the process to go instead |
| `editor-press <N> <item id>` | runs a toolbar item's action (`copy`, `delete-capture`, `close`, ...), as its button does |
| `editor-warm`, `editor-warm-state` | builds the Editor ahead of its Capture, hidden; replies `warm window=hidden canvas=built` or `cold` |
| `export-owned-probe <N>` | makes an owned copy of Editor N's Capture, encodes it into `<root>/probe/owned.png` and replies `ok <path>` |
| `editor-toolbar <N>` | one line per tool (`tool <id> <order> <tooltip>`) and toolbar item (`item <id> <slot> <tooltip>`) |
| `export-stages` | the Export pipeline's steps in the order they run |
| `export-name <N>` | the file name Editor N's Export has (`snapit-YYYYMMDD-HHMMSS.png`, from its Capture's time) |
| `editor-save-outcome <N>` | how Editor N's latest Save ended: `none`, `handed-over`, `failed folder-not-writable <errno> <folder>` or `failed <message>` |
| `editor-drag-file <N>` | does what pressing the mouse on the thumbnail does (Fast-encodes the Export into `<root>/drag-out/<N>/`), waits and replies `ok <path>` |
| `editor-drag-thumbnail <N>` | the thumbnail view: `view=<w>x<h> thumbnail=<w>x<h>\|none` |
| `main-menu` | the helper's menu bar menus, one line each: `<menu>: <item>\|<item>...` (`-` separator) |
| `editor-mouse <N> down\|drag\|up <x> <y>`, `editor-drag <N> <x1> <y1> <x2> <y2>` | a mouse event, or a whole press-drag-release, on Editor N's canvas at a point of the Capture (image points, origin at the top left). The point is placed by asking the canvas's layer tree where it is, and the event goes through the window's `sendEvent`, as a click does |
| `editor-keystroke <N> undo\|redo\|delete\|enter\|<character>` | ⌘Z, ⇧⌘Z, ⌫, Return or a plain key (a tool's key) as the window receives it |
| `editor-style <N> fill outline\|solid`, `width <points>`, `color <RRGGBB>` | what the style controls do: the selected Annotation and the next ones, remembered through `AppDefaults.store` |
| `editor-document <N>` | `annotation <id> <kind> <x1> <y1> <x2> <y2> <RRGGBB> <width> outline\|solid` per Annotation, then `selected=`, `undo-steps=`, `redo-steps=`, `revision=`, `tool=`, `zoom=`. For setup and for the zoom precondition; assertions are on pixels and on which items are enabled |
| `editor-menu-keys` | the key equivalent each Edit menu item shows: `<title> key=<hex codes> modifiers=<mask>` |
| `editor-enabled <N> <item id>` | `yes` or `no`: whether a toolbar item is enabled (Delete Annotation is enabled exactly when something is selected) |
| `editor-controls <N>` | one line per toolbar control, `control <tooltip> <x> <y>`: its centre in window coordinates. Test mode puts an invisible marker view behind each control (`ControlMarker`) |
| `editor-background <N>` | makes another Editor's window key, so Editor N is a background Editor; replies `ok key=yes\|no` |
| `editor-click <N> tool <id>`, `item <id>`, `canvas <x> <y>` | a click (press and release through the window's `sendEvent`) on a rail button, a toolbar item or a point of the Capture. With `editor-background` first, it is the first click on a background Editor: the window refuses it for Delete Capture and accepts it everywhere else |
| `editor-preview <N> [overlay]` | renders the canvas's own layers (no selection) at the pixel size of what the canvas shows (the Capture, or what an applied crop keeps), writes the PNG into the run's `probe` folder and replies `ok <path>`; `png-inspect compare` sets it against the Export (`max_diff=0` for Redactions). `overlay` keeps the selection's and the crop rectangle's shade and handles in the picture |
| `editor-inject-effect <N> <x1> <y1> <x2> <y2>` | adds an Annotation of a test kind that Export's Annotations stage does not draw (as Redaction will not), to check it lies beneath the others in the canvas and in hit testing |
| `move-screen-facts` | the "Move snapit to Applications" window: `window`, `title`, `state` (`ready`, `moving`, `failed`), `reason`, `replaces`, `message`, `activation`, and one `button <id>\|<title>\|<tooltip>` line per button |
| `move-screen-press move\|later` | presses a button of that window; `move` replies with the menu bar app's reply (`ok` or `error <why>`) |

`editor-facts` reports `canvas=layer-hosted` only when the canvas's layer is not delegated to the
view (a layer-backed view would report `layer-backed`).

## Warm-up

A Capture that starts (its Shortcut was pressed) calls `EditorWarmUp.begin()` (`snapit/Helper/EditorWarmUp.swift`)
and, if it ends without a Capture, `EditorWarmUp.cancel()`. `begin()` starts the Editor helper hidden
(launch argument `--warm`, no activation: an agent with no Dock icon and no window) and sends it
`warm-up`, so it builds the Editor's window, toolbars and canvas without a Capture. `cancel()` sends
`cancel-warm-up`: the warm Editor goes and a helper that never showed a window quits, so no helper
process exists at rest; a helper with an Editor open stays. A warm helper also watches the menu bar
app that started it (its pid is a launch argument and an argument of `warm-up`, so a restarted snapit
adopts a running helper) and quits when that process exits while the helper has shown nothing. Opening the Capture
(`EditorHelperLauncher.open`) waits for a warm-up in progress, uses the warm Editor and ends the
warm-up. A new Capture mode adds those two calls and nothing else (the Area Capture calls `begin()` in `AreaCaptureFlow.start()` after the permission check and `cancel()` from `conclude` for every outcome but `.opened`; `fixture-delay` and `fixture-fail` apply to its frozen frames too); `scripts/run/flows/35-editor-warm-up.sh`
shows what to assert. A helper launched without `--started-by-snapit` (a Dock pin) starts the menu
bar app and quits without building anything.

The menu bar app tells the helper to open a Capture with `open-capture <N>`; the pixels reach it
through the Capture file `<root>/captures/capture-<N>.pixels` (memory-mapped, never the socket).

## The fixture image

`FixtureCaptureSource` returns a deterministic image. At `w` x `h` pixels, pixel `(x, y)` is
`R = x*255/(w-1)`, `G = y*255/(h-1)`, `B = 40` if `x/8 + y/8` is even else `200` (integer
division). The engine tests and `scripts/run/png-inspect.swift` use the same formula, so a PNG can
be checked pixel by pixel without trusting the code under test. The default fixture is 301 x 187
points: an odd width, so engine rows are padded (never assume a stride is tight).

## Adding a flow to the scripted run

`SNAPIT_FLOWS="38 40" scripts/check-run.sh <app>` runs only the flows whose names start with those numbers, for
working on one flow (flows share state, so `scripts/test.sh` always runs them all).

A flow is one file in `scripts/run/flows/`, named `NN-what-it-covers.sh`. `check-run.sh` starts the
menu bar app, then sources every flow in name order (`10-` menu bar app, `20-` Screen Capture
into the Editor and Copy, `30-` the Editor, `35-` Editor warm-up and the helper launched on its own, `36-` the Editor's tools, `38-` Redaction and Crop, `40-` Area Capture, `45-` Save and drag-out, `80-` Move to Applications and the translocation
check, `90-` Editor helper and Quit, which must stay last). Flow `80-` quits and relaunches the
menu bar app, so a flow after it starts with a freshly started menu bar app: `AT_REST` from `20-`
is stale and no in-memory state (pretended paths, fixtures, Shortcuts) survives.
A flow can use everything in `scripts/run/lib.sh` (`send`, `send_slow`, `expect_equal`,
`expect_contains`, `wait_until`, `footprint_mb`, `assert_idle_cpu`, `png_field`, ...), the Editor
helpers in `scripts/run/editor.sh` (`capture_into_editor <trigger>` runs a Capture and sets
`EDITOR_N` and `HELPER_PID`; `copy_closes_editor`, `app_type <pid>` for Foreground (Dock icon)
versus UIElement (agent), `onscreen_windows <pid>`, `helper_pid`) and the variables `APP_SOCK`,
`EDITOR_SOCK`, `RUN_ROOT`, `APP_PID`, `INSPECT` (the `png-inspect` tool, which also lists a
process's windows: `png-inspect windows <pid>`, the Area overlay's panels: `png-inspect overlay-windows <pid>`, reads one pixel in sRGB: `png-inspect pixel <file> <x> <y>` (`r g b`) or in the PNG's own color space: `png-inspect raw-pixel <file> <x> <y>` (`r,g,b`), and
compares a PNG with the fixture: `png-inspect diff-fixture <file> <w> <h> [<x0> <y0> <x1> <y1>]` prints how
many pixels changed, their bounding box and how many lie inside and outside a rectangle, and compares two
PNGs: `png-inspect compare <a> <b>`, and for a Redaction `png-inspect verify-redaction ...`, which recomputes every block mean from the fixture formula, and for a crop `png-inspect diff-crop ...`, `diff-fixture` for the pixels of the fixture that start at an origin; `scripts/run/png-inspect.swift` has the arguments). A flow that draws in
the Editor sources `scripts/run/editor-tools.sh` (`drag`, `click`, `keystroke`, `style`, `export_png`, `preview_png`,
`click_on`, `expect_enabled`, `fixture_diff`, `fixture_pixel`, ...; `36-editor-tools.sh` is the model).

The Area flow (`40-area-capture.sh`) shows how to drive an overlay: `press-shortcut capture-area`
shows it, `overlay-mouse` and `overlay-key` are the user's hand, `overlay-wait` returns when the
Capture is in the Editor or cancelled, and `png-inspect verify-fixture <file> <w> <h> <full w>
<full h> <x> <y>` checks a crop of the fixture pixel by pixel.

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

## The Area overlay

The overlay is the menu bar app's (`snapit/Area/`). Every display is frozen with one capture,
the overlay shows it in persistent Core Animation layers (`AreaOverlayScene`) updated in a
transaction with actions disabled, and letting go of the mouse crops the frozen frame in the
engine (`snapit_crop`) straight into the Capture file. Test mode shows the same panels over the
fixture displays, a little in from the main screen's bottom-left corner and only as big as the
fake display, so a run never covers the user's screen. A scripted run never activates snapit or
takes the keyboard, and its panels ignore the real mouse. `FixtureWindowSource` has two
overlapping windows over the first fake display (front 60,40 100x60; back 20,20 200x130 points)
to aim a hover at, and two that cross its left and top edges (for a second display at negative
coordinates). The fixture frames are
IOSurface-backed like a ScreenCaptureKit capture, so Core Animation shows them without copying
and the run can check that the overlay holds each frame once and gives it back.

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
returns the flattened image for a sink; `run` also Fast-encodes it (Copy). The sinks in
`Export/ExportSinks.swift` are Save (`flattenIntoSharedFile`: the image goes into a memory-mapped
file in the Capture file format, `<root>/exports/`, and the menu bar app encodes from it) and
drag-out (`writePNG`: Fast-encodes into a file, streamed). The 1x downscale is never a buffer: the
encode step reads `downscaleOnEncode` and the engine averages while it encodes
(`PNGOutputPlan` is the one rule for the size and dpi, used by both processes).

Save is `EditorSession+Save.swift`: the helper sends `save-export` and the menu bar app
(`snapit/Export/SaveService.swift`) checks the Save location at once, then encodes in the
background and writes `snapit-YYYYMMDD-HHMMSS.png`. A failed check keeps the Editor open and goes
to `SaveFailureSignal` (`Export/SaveFailure.swift`): a feature that reacts to it (the folder
Permission guide) registers with `SaveFailureSignal.observe`. Its `.folderNotWritable(folder:code:)` carries the
`errno`: `EPERM` (1) is a macOS privacy (TCC) denial, `EACCES` (13) POSIX permissions, `ENOENT` (2) a
missing folder, `EROFS` (30) a read-only volume. The signal covers only the writability check made
before the hand-over. A failure after it (disk full, the final rename) cannot reach the Editor, which
may be gone: the menu bar app sends it to `SaveService.observeWriteFailures` observers (on the main
queue) and beeps when there are none.

Quit waits for Saves that are still being written (`applicationShouldTerminate` answers
`.terminateLater` and replies from the main run loop in the common modes: a reply through
`DispatchQueue.main.async` never runs when `terminate` came from a main-queue block). A Save counts as
pending from the start of its writability check. A Save begins by removing the hidden
`.snapit-<UUID>.partial` files an earlier crash left in the Save location.

Drag-out files are written under a hidden partial name and renamed into place (a reader of an earlier
drag keeps its own file), with mode 0644 less the umask like a Saved file. They stay in
`<cache>/drag-out/<N>/` after their Editor closes; folders older than ten minutes are removed when a
Capture opens, and everything goes when the menu bar app starts or quits.

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

Selection, the style the next Annotation gets and the gesture in progress live on the `EditorSession`;
`toolbarState` is what the toolbar watches, and it changes only when a gesture starts or ends, never on
a pointer move. A kind's preview layer is made and updated with an `AnnotationRenderContext` (the
Capture's read-only pixels, the scale and the zoom), so a kind that previews from the Capture (Redaction,
through the engine) needs no other hook. `AnnotationKinds.paintOrder` is the order Export paints and the
canvas layers and hit testing follow: kinds with `drawnByAnnotationStage` false (Redaction) beneath all
the others.

A kind's `paint(for:)` (path, fill, stroke) feeds both the canvas's `CAShapeLayer` and the Export's
Core Graphics drawing, so the preview is the Export. Hit tests are exact (the inside of a filled
Annotation, the stroke of an outline). `AnnotationStage` draws every Annotation whose kind has
`drawnByAnnotationStage` true, in document order, onto the Export's owned buffer; a stage of another
feature filters `job.annotations` by `kind` (Redaction's `RedactionStage` takes its own kind and
sets `drawnByAnnotationStage` false). Tools are shared by every open Editor, so their state (`EditorSession+Annotations.swift`) never lives in a tool. The Annotation color, width and fill used last are remembered in
`AnnotationSettings` (`annotationColor` as `RRGGBB`, `annotationWidth`, `annotationFilled`).

### Redaction and Crop

A Redaction (`Annotations/RedactionAnnotationKind.swift`, `drawnByAnnotationStage` false) pixelates in
the engine (`snapit_pixelate`, `Shared/Engine/Engine+Pixelate.swift`): it reads a window of the Capture and
writes the area's block means into another buffer, never in place. The canvas's preview layer
(`RedactionPreviewLayer`, a buffer of exactly the area made from `AnnotationRenderContext.capture`) and
`RedactionStage` make the same call, so the preview is the Export bit for bit; the flow compares them with
`max_diff=0`. The Export writes into the window of its own buffer, and every Redaction reads the *original*
Capture, so Redactions that overlap look the same in both and the pixels beneath one are overwritten, never
kept.

The rule (`RedactionGeometry`), which the flow works out again on its own: the box in image points snaps
to device pixels, each edge to the nearest pixel, and is cut to the Capture. The block is a third of its
short side, between 14 and 48 points, at least 4 pixels. The grid of blocks starts at the corner of the
part of the box that is inside the image shown (the Capture, or what a crop kept). It has side / block
blocks across and down (at least one), and what is left over at the right and bottom edge is folded into
the last block of its row or column, so the edge blocks are between `block` and `2 * block - 1` pixels
wide and never a sliver or a lone pixel (a side shorter than one block is a single block). Every pixel of
a block is the floored mean of the original pixels in it, per channel. Blocks are 40 pixels for a 60 point
box at 2x; a 201 x 121 pixel Redaction has 40 pixel blocks with a last column and row 41 pixels wide.
`png-inspect verify-redaction` works the grid out from this paragraph alone and reports `survivors=` (an
original pixel left under the Redaction) and `smallest_tile=`.

Crop: `DocumentState.crop` is a rectangle in image points, set by Apply Crop (Enter or the toolbar item, one
Undo step) after the Crop tool's handles (`EditorSession+Crop.swift`, `Canvas/CropOverlayLayers.swift`). It is
stored already snapped to device pixels (`CropGeometry.pixelRect`, the one snap rule for the canvas, Apply and
`CropStage`). `CropStage` copies the part into a buffer of its own with `snapit_crop` and sets
`ExportImage.origin` in pixels; `AnnotationStage` and `RedactionStage` subtract it. The canvas moves
the layers under a clip instead of redrawing, so Annotations stay in the Capture's own coordinates. Undo and
Redo and Esc (which cancels a pending crop first) follow the document's state.

## Adding a Shortcut

Add an `AppShortcut` in its own file (`snapit/Shortcuts/AppShortcut.swift` shows the shape), bind
it with one line in `ShortcutBindings`, and press it in a flow with `press-shortcut <id>`.

## Engine tests

`engine/tests/*.rs` call the C-ABI functions directly (`pixelate.rs`: the averaged-block pixelate, with its
own independent block-mean reference, non-tight strides, edge blocks, windows, invalid and overlapping buffers). `engine/tests/support/mod.rs` has the fixture
builder (any stride, padding filled with garbage that must never reach the output) and a PNG chunk
reader that does not use the encoder under test. A new engine function gets a test file with:
a round trip, a non-tight stride, invalid arguments (null pointers, zero sizes, overflow) and its
metadata. After changing the C interface run `scripts/generate-header.sh` and commit the header.

## Never in a test

Touch the real clipboard, `~/Downloads`, the real cache folder or the bundle ID's `UserDefaults`
domain; register a real hot key; trigger a Screen Recording prompt. The paths the scripted run does
not exercise are the real ScreenCaptureKit Capture, real hot keys, and the real Screen Recording
permission and its prompt; they run only in a real install.
