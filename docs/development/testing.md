# Testing snapit

Two seams, both run by `scripts/test.sh` (and CI):

1. **The scripted whole-app run**, `scripts/check-run.sh`. It starts the built `snapit.app` in
   hidden *test mode* and drives it from the outside.
2. **The engine's C-ABI tests**, `cargo test`. They call the same `snapit_*` functions Swift calls,
   with fixture buffers.

Tests assert only on what is observable: the pasteboard's PNG, files, sockets and their replies,
processes, memory, CPU at rest and the cache folder's files. They never reach into classes or private state.

## Running the tests

```sh
scripts/test.sh          # everything
scripts/test.sh engine   # repo checks, the docs check, Cargo fmt, clippy, tests and the header check only
```

A fresh clone runs `git config core.hooksPath .githooks` once to enable the pre-commit hook, which runs `scripts/test.sh engine`.

The scripts that call Xcode's tools source `scripts/xcode-env.sh`: when `DEVELOPER_DIR` is unset and `xcode-select` points at the Command Line Tools, it uses `/Applications/Xcode.app` (or the newest other `/Applications/Xcode*.app`) for that run, with no `sudo` and no change to system settings.

`scripts/test.sh` runs, in order:

1. Repo layout checks, and `scripts/check-network.sh`: the only code in snapit that may open a network connection is `snapit/Updates/GitHubReleaseEndpoint.swift` (Check for Updates), and the engine uses none.
2. `scripts/check-docs.sh`, the docs check: the User Guide's sections, links and checklist (see "The User Guide" below), and every relative link in every Markdown file in the repo outside build output and Cargo's `target/` folder, which has to resolve to a file that exists. The check names the file and line of a link that does not resolve, and skips code spans and fenced code.
3. `cargo fmt --check`, `cargo clippy` and `cargo test`. The Cargo tests call the engine through the same C-ABI functions Swift calls.
4. The cbindgen header check: the committed header must match the engine.
5. The Xcode build.
6. `scripts/check-bundle.sh`: the Editor helper is nested in `Contents/Helpers`, both bundles verify with `codesign --verify --strict`, same name and icon.
7. `scripts/check-run.sh`, the scripted whole-app run. It starts snapit in test mode (`SNAPIT_TEST_ROOT` points at a fresh temporary folder), so the Capture source returns fixture images, Screen Recording reads as granted, the clipboard is a private pasteboard, and the Save location, cache and defaults live in the temporary folder. It drives the menu item and the Shortcut for a Screen Capture at 1x and 2x, opens each Capture in the Editor helper (Dock icon while it is open, process lifecycle, memory-mapped Capture file), copies it with ⌘C and checks the PNG on the pasteboard pixel by pixel and for its `pHYs` and ICC metadata, draws Rectangles, Ovals and Arrows with synthetic pointer input and Selects, moves, resizes, deletes, undoes and redoes them (checking the Copy output's pixels against the fixture, at 1x, 2x and on a scaled-down Capture), types Text with real key events (Core Text in the Export with the glyph's place, orientation and color checked, a click away commits and starts no new box, tool keys and ⌫ are typing, ⌘Z takes typing back first), draws translucent Highlighter strokes (blend computed from the fixture formula), chooses Annotation colors with the swatches, the eyedropper (the pixel under its hot spot at 1x and 2x, never an Annotation) and the color panel (a drag is one Undo step), and checks width presets, the remembered color, width and text size, and the first click on every control of a background Editor, draws Redactions and checks every pixel under them against block means recomputed from the fixture (the original pixels are gone, the canvas's preview is the Export bit for bit), crops with the Crop tool's handles at 1x, 2x and on a scaled-down Capture (Enter and the toolbar item, Undo and Redo, Annotations and Redactions before and after the crop, a 6K Copy), saves with ⌘S (file names, `-2`/`-3` on a clash, file mode, pixels, dpi and ICC at 2x and with the 1x setting, a Save that finishes after the Editor helper quit or snapit quit, a Save location that can't be written to), checks the drag-out thumbnail's file, closes Editors with Esc and Delete Capture, checks the Last Capture store (the state file in the private cache after each change, coalesced and skipped writes, stale writes dropped when a new Capture or Delete Capture supersedes them, Reopen Last Capture with Annotations of every kind, crop and Undo history, a damaged store, files removed by a new Capture, Delete Capture, quit and launch, memory over Reopen cycles), warms the Editor helper up when a Capture starts and cancels it (no helper process is left), launches the helper on its own, drives the Area overlay with synthetic mouse events (hover highlight, a drag released into a Capture at 1x and 2x with fractional positions, a click on a highlighted window, the 3 pt click threshold, Esc, displays of another scale and at negative coordinates, a frozen frame in another pixel layout) and checks the crop pixel by pixel and the overlay's memory, drives the Action bar (the selection staying with eight handles, resizing past the opposite edge, moving, the bar on screen at every edge and corner, Enter, a double-click with jitter, the Capture and Cancel buttons, Esc, a window click, the setting at Capture on release), drives the Color picker (from the Action bar, its P key, the menu and its Shortcut: the sampled pixel and its hex against the fixture at 1x and 2x, nudges, clicks and Enter, the toast, Esc, a second display at negative coordinates, memory), drives Timed Capture (the timer slider and its remembered value across a relaunch, a countdown of real click-through border and badge panels, the ✕ on mouse-up and the Area Shortcut cancelling, a fresh Capture at zero told from the frozen frame by a stamp, snapit's own windows kept out of it, a helper that quit during the countdown, a Capture that fails at zero, memory), drives the Window Capture (hover picks the front-most window, a click captures exactly that window at 1x and 2x with its transparent corners kept in the Copy and Save PNGs, no Action bar, Esc, a window that vanished, memory) and checks that opaque Captures still make RGB PNGs, drives Onboarding (the six steps and their stored step, resume at the next launch and at a Shortcut press, never again once finished, the Permission guide through a fake macOS for never granted, Don't Allow, a grant seen only when the window becomes active, Relaunch snapit and the update path with a fixture `tccutil`, the animation playing only while visible and stopping after a few loops, and memory), starts and quits the Editor helper, checks memory over repeated Editor cycles and that nothing spins at rest, checks the cache folder holds only the expected files after each flow, and asserts that your real preferences, cache folder and clipboard were not touched.

Flow 56 of that run covers Check for Updates with the HTTP request faked (no real network): nothing is requested until a click, a version comparison table, every kind of GitHub reply, the update window's words and release notes, what Download opens (through the browser edge), one request per check, and memory afterwards.

Flow 57 covers a missing permission: a Capture Shortcut or menu item (every Capture mode) pressed without Screen Recording shows the Permission guide, or Onboarding while that is unfinished, takes no Capture and leaves nothing running, in each state of the fake macOS (never granted, granted to the build before an update with the fixture `tccutil` resetting snapit's own entry, turned off, waiting for a relaunch), and Captures work after the grant and Relaunch snapit; a Save into a folder that can't be written to (read-only, missing, a seam for the macOS privacy denial and a read-only volume) keeps the Editor open and shows the folder Permission guide worded for the cause, with Choose another folder, Open System Settings and Try again; a Save that fails after the hand-over shows the same window from a helper started for it; and the helper's lifecycle and memory around them.

Flow 58 covers the User Guide: the menu item and Onboarding's link open one window in the helper (a second request brings it forward), the guide is read from the helper's bundle and covers a checklist of the spec's flows (`scripts/user-guide-checklist.txt`, also checked on the source by `scripts/check-docs.sh`), every section has the icon its source gives and every anchor resolves, a guide with image lines draws no image block and no alt text, sections link to each other in the window, a link to GitHub goes through the fake browser edge and any other link is dropped, search finds sections, and the menu bar app stays at its baseline and idle while the helper hosts the guide and quits with its window.

Run `scripts/test.sh` locally first: it is the first line of defense. CI is the final check, run on pushes to `main` and `integration/**` only (`.github/workflows/ci.yml`: `scripts/test.sh` on the hosted `xcode-27` arm64 runner, macOS 27 with Xcode 27). OSV-Scanner runs on the same pushes, on Ubuntu, from `.github/workflows/osv-scanner.yml`.

The rest of this doc explains test mode and how to add a flow, a fixture, a test-mode command or an engine test.

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
| Timed Capture's fresh Capture at zero | a new ScreenCaptureKit screenshot of the display, with snapit's whole application excluded by the content filter (its menu bar icon excepted), built from `OwnWindowExclusion.plan` | the fixture image of the fake display with a 4 x 4 pixel stamp in its corner (`R=250, G=<fresh Captures so far>, B=77`) and any of snapit's windows that the same `OwnWindowExclusion.plan` does not exclude painted over it. The 200 ms hide-and-fetch-again fallback (snapit missing from ScreenCaptureKit's list) is covered by `docs/development/manual-checks.md` only | `snapit/Area/Timed/TimedCaptureSource.swift` |
| window list (hover highlight) | the window server's on-screen list | two fixed overlapping windows over the first fake display | `snapit/Area/OnScreenWindowSource.swift` |
| Screen Recording permission | `CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess`, in the menu bar app only; the five states (`notDetermined`, `denied`, `granted`, `grantedStale`, `grantedNeedsRelaunch`) are derived from that, from what snapit remembers (which build was granted, whether it asked) and from whether it was granted when this process started. A grant lost by the same build is `denied` (the user turned it off); lost by another build (an update) is `grantedStale`. The build is told apart by its code directory hash | the same derivation over a flag in the run's defaults that starts granted, so a run never meets a prompt, and a settable build id (`screen-recording-build`); a request is a line in `<root>/screen-recording-requests`; `screen-recording-simulate` sets the fake macOS | `Shared/Edges/ScreenRecordingPermission.swift` |
| resetting snapit's own Screen Recording entry | `/usr/bin/tccutil reset ScreenCapture <bundle id>`, run from inside the menu bar app, failures reported | a line in `<root>/tcc-resets` and the fake macOS no longer granting; fails while `<root>/tcc-reset-fail` exists (`tcc-reset-fail on`); the real `tccutil` and the real TCC database are never touched | `snapit/Onboarding/ScreenRecordingReset.swift` |
| Onboarding's stored step | not stored: Welcome | finished, so no other flow meets Onboarding; a flow stores a step with `defaults-set onboardingStep <step>` first | `Shared/Onboarding/OnboardingStep.swift` |
| pasteboard | `NSPasteboard.general` | private pasteboard `dev.snapit.test.<run>` | `Shared/Edges/AppPasteboard.swift` |
| Save location | `~/Downloads` | `<root>/save` | `Shared/Edges/SaveLocation.swift` |
| defaults | the menu bar app's bundle ID domain, in both processes | `<root>/defaults.plist`, read and written straight through under a file lock (`FileBackedDefaults`): both processes see each other's writes at once | `Shared/Edges/AppDefaults.swift` |
| Open at Login | `SMAppService.mainApp` (menu bar app) | a status kept in the run's defaults (so it survives a relaunch as the real one does), starting `notFound` like a fresh install; a copy that runs from an Applications folder registers it on launch (on by default); the real login items are never touched | `snapit/Settings/LoginItem.swift` |
| macOS shortcut clash check | the system's enabled symbolic hot keys | ⌘⇧3, ⌘⇧4 and ⌘⇧5, and what a run adds with `system-shortcut-fixture add` | `Shared/Edges/SystemShortcutClashes.swift` |
| System Settings links | opens System Settings | appends the link to `<root>/system-settings-links` | `Shared/Edges/SystemSettingsLinks.swift` |
| Shortcuts | KeyboardShortcuts (Carbon hot keys) | injected events (`press-shortcut`) | `snapit/Shortcuts/` |
| Check for Updates' HTTP request (snapit's only network call) | one GET of GitHub's latest-release endpoint on an ephemeral session, in `GitHubReleaseEndpoint.swift`, the one file allowed to open a connection (`scripts/check-network.sh`) | a script (`update-script`) answers with a status and a body or a failure, never goes online; each request it is asked to send is logged to `<root>/update-requests` (method, address, every header); unscripted it answers as offline | `snapit/Updates/ReleaseEndpoint.swift`, `FixtureReleaseEndpoint.swift` |
| browser (the Download button, a link in release notes) | `NSWorkspace.open` of an `https` link | appends the link to `<root>/browser-links` | `Shared/Edges/BrowserLinks.swift` |
| color panel (the Editor's color wheel button) | `NSColorPanel.shared`, which keeps its mode and swatches in the helper's own preferences | a fixture with no window and no preferences (`editor-color-panel`) | `snapit-editor/Editor/Color/ColorPanelEdge.swift`, `FixtureColorPanel.swift` |
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
KeyboardShortcuts: `InjectedShortcuts` keeps the handlers in a dictionary and the combos in the run's
defaults, so a recorded Shortcut survives a relaunch of the menu bar app.

Test mode adds socket commands (they exist only while test mode is on: `menu-titles` and `start-editor` in the menu bar app, `engine-version` in both processes, and every command below). The scripted run sends them
to `$RUN_ROOT/app.sock` (menu bar app) or `$RUN_ROOT/editor.sock` (Editor helper), one line each:

| Command | What it does |
|---|---|
| `test-seams` | one `key=value` line per edge: root, pasteboard, save, cache, permission |
| `defaults-set <key> <value>`, `defaults-get <key>` | write or read a string through `AppDefaults.store`; the run writes in one process and reads in the other |
| `activation-plan test\|normal` | how the helper is brought forward when a Capture opens (`activate-at-launch`, `activate-after-open`); a scripted run never activates it |
| `capture-source` | `fixture` when the Capture source is the test one |
| `frame-freed-at-open` | `yes` when the latest Capture's frame (its `CapturedScreen`) was already gone when the Editor was asked to open it, that is once its Capture file was written; `no` while something still held it; `none` before any Capture; `unknown` when the frame carried no lifetime probe (so a check cannot pass without one). `capture_into_editor` and `area_result` assert `yes` after every Capture |
| `overlay-frames-freed` | `yes` when every frozen frame (each display's `CapturedScreen`) of the latest overlay is gone: after an overlay has ended (a pick, Esc, a Capture), read after `overlay-wait`; `no` while one is still held; `none` before any overlay; `unknown` when a frame carried no lifetime probe. Flow 47 asserts `yes` after every pick and Esc |
| `overlay-panels-freed` | `yes` when the latest overlay's controller, panels, scene views, scenes and container views are all deallocated (read after `overlay-wait`); `no <names>` lists those still alive (`no panel 0`); `none` before any overlay. Flow 47 asserts `yes` after every pick and Esc |
| `live-windows` | the app's windows now: `windows total=<n> visible=<v>`, one `window <class> total=<n> visible=<v>` line per class, `overlay <what overlay-panels-freed says>` and `toast-panel alive\|gone`. A failed memory check's log prints it |
| `ca-nudge` | shows a one point window and closes it, with a Core Animation commit before and after; replies `ok`. A failed memory check's log uses it to see whether memory waits for a round trip to the window server |
| `fixture-delay <ms>` | how long the fixture Capture takes to return: the time spent choosing an Area |
| `editor-warm-up begin\|cancel\|state\|settle` | what a Capture does when it starts and when it is cancelled; `state` is `idle`, `starting` or `warm`; `settle` waits until the helper has been started and told about every Cancel so far |
| `overlay-screens-changed` | tells the Area overlay the displays changed (macOS's notification, with the displays counted as different); the overlay ends, and so does a Timed Capture's countdown |
| `overlay-screens-noise` | the same notification with the displays as they were (what a Dock that moved posts); the overlay and the countdown carry on. The overlay and the countdown end on that notification only when the displays' IDs, frames or scales differ from when they started (`snapit/Area/DisplayConfiguration.swift`) |
| `fixture-fail on\|off` | makes the fixture Capture fail, so a flow can check what a Capture that ends without a Capture does (it cancels the warm-up) |
| `fixture-display <scale> [<w> <h>]` | chooses the fake display (scale 1 or 2, size in points) |
| `fixture-extra-display <scale> <w> <h> [right\|left\|above]` or `none` | adds a second fake display next to the first, with its own scale and size; left and above put it at negative coordinates (the Area overlay gets one panel per display) |
| `fixture-pixel-layout alpha-first\|skip-first` | the layout of the first fake display's frozen image: premultiplied BGRA (the engine's in-place crop) or BGRX from a plain bitmap (the crop's fallback) |
| `press-shortcut <id>` | presses an injected Shortcut; replies `ok` when its action has finished. The Area Shortcut's action finishes when the overlay is showing; the rest is the scripted run's mouse |
| `bound-shortcuts` | the ids of the Shortcuts that are bound |
| `shortcut-combo <id>`, `shortcut-set <id> none` or `<key code> [<modifier>...]` | read or change a Shortcut's key combination |
| `menu-shortcut <id>` | the key equivalent a menu item shows now, or `none` |
| `menu-click <id>` | runs a menu item's action; replies `ok` when it has finished |
| `login-item-status`, `login-item-set on\|off`, `login-item-simulate <status>`, `login-item-default` | the (fake) login item Settings drives: read its status, register or unregister it, set the status as System Settings would (`enabled`, `notRegistered`, `requiresApproval`, `notFound`) |
| `apply-shortcut <id> none\|<key code> [<modifier>,...]`, `shortcut-combos` | what the helper's recorder sends: rebinds a Shortcut of `ShortcutCatalog` (and the menu glyph follows); and what Settings asks when it opens: one `<id> <combo>` line per Shortcut, from the registrar |
| `menu-enabled <id>` | `yes` or `no`: whether a menu item is enabled now (Reopen Last Capture is `no` while there is no Last Capture) |
| `last-capture` | the Last Capture's number, or `none` |
| `capture-folder-race` | the next Capture file finds its (empty) folder removed between the folder being made and the file being created, as a Delete Capture can do; the write makes the folder again |
| `overlay-mouse move\|down\|drag\|up <display> <x> <y> [<click count>]` | sends the Area overlay a real mouse `NSEvent` at a point of that display (points from its top-left corner; 0 is the first display), with that click count (1 when omitted; a double-click is a `down` with 2) |
| `overlay-key escape\|enter\|left\|right\|up\|down\|<letter>\|<key code> [shift]` | sends the overlay a key event through the application's event dispatch (a letter carries the character, as a keyboard's event does; `shift` adds the Shift modifier) |
| `overlay-wait` | after a mouse-up or Esc: waits for the overlay to finish; replies `opened <N>` (Capture N is in the Editor), `picked #RRGGBB` (the Color picker copied that hex), `cancelled` or `failed <why>` |
| `overlay-facts` | what the overlay shows: `displays`, `state` (`idle`, `hoverWindow`, `dragging`, `adjusting`, `pickingColor`), `display`, `display-ids` (each display's `CGDirectDisplayID`; fake ones in test mode), `cursor`, `hover`, `area` (the display and the Area: `<display> <x>,<y> <w>x<h>`, or `none`), `view` (`layer-hosted-scene` when the scene is layer-hosted and no view draws), `after-selecting` (the setting), `handles` (how many show), `action-bar` (its frame, or `none`), `loupe` (`shown` or `hidden`: shown while selecting and while a handle is dragged), `hovered` (the tile under the pointer, or `none`), `tooltip` (its text once the pointer has rested on the tile for 0.5 s, or `none`), `scene-updates` (how many times the scene's layers were updated) |
| `overlay-actionbar` | the Action bar: `frame=<x>,<y> <w>x<h>` (or `none`), then one `item <id>\|<title>\|<tooltip>\|<key>\|<frame>` line per item, in layout order; frames are display points and an item's frame is its whole tile, its hit area. The bar is clicked with `overlay-mouse` at a point inside a frame (`42-action-bar.sh` has `tile_point` and `press_tile`) |
| `overlay-picker` | the Color picker: `display`, `pixel=<x>,<y>` (device pixels of that display's frame), `hex`, `origin` (`bar` or `entry`), `frame` (the frame's size in pixels), `loupe` (its frame in display points, or `none`), `outlined` and `swatch` (the centres of the outlined cell and the swatch, in display points, to read back from an `overlay-snapshot`); `none` when the picker is not up |
| `color-toast` | the text of the "Copied #…" toast showing now, or `none` |
| `pasteboard-string` | the plain text on the private pasteboard, or `none` |
| `timed-facts` | a Timed Capture: `state` (`counting` or `none`), `seconds`, `remaining`, `ticking` (a tick is scheduled: only while counting), `area`, `border` and `badge` (display points from the display's top-left corner), `border-panels`, `border-click-through` and `badge-click-through` (what each panel is meant to do with clicks: the border lets them through, the badge takes them; a scripted run makes every panel ignore the real mouse, so this reports the intent), `tooltip` (the ✕'s, once the pointer has rested on it); then the fresh Capture at zero: `fresh-captures` (how many so far), `fresh-after` (seconds from the countdown's start to it) and `fresh-excluded` (how many windows of snapit's were excluded). While a countdown runs the overlay is gone (`overlay-facts` replies `none`) and `png-inspect overlay-windows` lists the border's panels and the badge |
| `timed-mouse move\|down\|up cross\|body\|away` | a real mouse `NSEvent` sent to the countdown badge: over its ✕, over its seconds, or away from it (`up away` after `down cross` is a press let go elsewhere) |
| `timed-seconds-store <integer>\|<text>` | stores that raw value under the timer's key: an integer as the slider does (however far out of range) or text that is not a number, to see how the Action bar reads it |
| `fixture-fresh-ignores-exclusions on\|off` | the fixture's fresh Capture paints snapit's windows whatever is excluded, so a run can see that a Capture which let them through would show them |
| `overlay-window-count` | how many windows the app has ordered in at the overlay's level; `overlay_panels` (flow 40) reads `png-inspect overlay-windows` until the window server's list has that many, because the list lags `orderFront` and `orderOut` when the machine is busy |
| `overlay-snapshot <display> <path>` | renders that display's layers to a PNG inside the root; the run reads pixels back with `png-inspect pixel` to check the dim and the cutout |
| `pasteboard-types`, `pasteboard-dump-png <path>`, `pasteboard-clear` | read or empty the private pasteboard (`<path>` must be inside the root) |
| `save-hold`, `save-release` | hold every Save's write (the encode into the Save location) until released, so the run can quit the helper while a Save is still being written |
| `save-fail-check <errno>\|off` | makes every Save's writability check fail with that `errno` (1, `EPERM`, is what macOS's privacy check gives for a folder the user denied; 30 is a read-only volume): a run never meets a real prompt or a real read-only volume. `EACCES` and `ENOENT` need no seam: `chmod 500` the Save folder, or choose a folder that is not there |
| `save-fail-write <errno>\|off` | makes every Save's write fail with that `errno` once it starts, after the hand-over (28 is a full disk). The fault is made where the engine's answer is read (`PNGWriteFault`), so it goes through the real mapping: the engine hands the `errno` of a failed write back through `snapit_png_encode_to_fd`'s `os_error`, and an engine status (6 is not `EIO`) is never read as one. With `save-hold`, `chmod 500` on the folder before `save-release` fails the final rename for real |
| `save-pending` | how many Saves are still being written |
| `install-location` | where the menu bar app runs from: `bundle`, `translocated`, `origin`, `on-disk-image`, `mount`, `decision` (`none`, `move`, `fix-in-place`) as `key=value` lines. Also answers in a normal run |
| `install-check` | runs the launch check again; replies `none`, `move-screen-shown`, `fixed-in-place` or `not-approved` |
| `install-pretend-bundle <path>`, `install-fake-volume <path> <fs> <from> <mount> ro\|rw`, `install-reset` | make this process behave as if it ran from `<path>`, give `<path>` (and below) a fake volume for `statfs`, forget both. Paths must be inside the root |
| `update-script release <tag> <html_url> <notes> [draft\|prerelease]`, `update-script raw <status> [<body>]`, `update-script offline\|timeout`, `update-script hold on\|off` | what the fixture HTTP endpoint answers to Check for Updates (arguments are percent-encoded: notes may hold spaces and lines); `hold on` keeps a request waiting so a run sees a check in progress |
| `update-requests` | how many requests Check for Updates has sent |
| `update-redirect <url>` | whether the real endpoint would follow a redirect of its request to that address: `follow` or `refuse` |
| `update-installed-version <x.y.z>\|reset` | pretend another bundle version, or read the bundle's again |
| `update-compare <a> <b>` | the version comparison, `ReleaseVersion`, as a table check: `newer`, `same`, `older`, `invalid a` or `invalid b` |
| `install-detect <path>` | detection with the real `statfs` and `/Volumes`, same reply as `install-location` |
| `screen-recording-state`, `screen-recording-request`, `relaunch-snapit` | what the helper's Onboarding and Permission guide ask of the menu bar app, which alone asks macOS: where Screen Recording stands; ask afresh (after an update, reset snapit's own entry first; replies the state, then `reset-failed <why>` on a second line); relaunch (the helper quits first, so a reply may never reach the helper) |
| `screen-recording-simulate notDetermined\|denied\|turnedOff\|revoked\|granted\|grantedStale` | puts the fake macOS where the user doing it would (`turnedOff`: granted to this build, then switched off; `grantedStale`: granted to another build; `revoked`: only the grant goes). `granted` is the default every other flow relies on: a flow that simulates anything else puts it back. The menu bar app records whether it was granted at launch (`grantedNeedsRelaunch` is granted since): relaunch it with the fake not granted to reach that state |
| `screen-recording-build <id>` | makes this copy another build to the fake macOS, as an update does |
| `screen-recording-facts` | `state=`, `requests=` (times snapit asked macOS) and `resets=` (times it reset its own entry) |
| `tcc-reset-fail on\|off` | makes the fixture reset fail, as `tccutil` can |
| `onboarding-launch-check` | runs what a launch does for Onboarding and the update's Permission guide: `onboarding`, `permission-guide` or `none` |

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
| `editor-drag-image <N>` | presses the thumbnail (what the mouse going down does), writes the image the drag would show into the run's `probe` folder as a PNG, replies `ok <path>` and lets the press go. It is drawn at the press from the document as it is, so an edit made an instant before it is in the image; flow 45 asserts that for a rectangle and a Redaction, and that Undo takes them out |
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
| `settings-facts` | the Settings window: `window`, `title`, `activation`, then per section a `section <title>` line and one `control <id>\|<kind>\|<title>\|<value>\|<tooltip>` line per control (`display <id>\|<glyphs>` and `note <id>\|<text>` follow a Shortcut that has a combination or a flag) |
| `settings-press <control id> [<value>]` | what clicking a control does: flips a switch, picks an option (`after-selecting-area captureOnRelease`), starts a recorder (`shortcut.<id>`), clears one (`shortcut-clear.<id>`), presses a button |
| `settings-key <key code> [<modifier>,...]` | a key press sent through the application's event dispatch, as a recorder that is waiting receives it; replies `ok` once the menu bar app has been told |
| `settings-choose-save-location <folder>` | what choosing a folder in the chooser does (the folder must be inside the root) |
| `settings-snapshot <png>`, `settings-close` | render the page to a PNG inside the root; press the close button (the helper then quits) |
| `last-capture-writes` | `written=<n> dropped=<n>`: state files this helper has written, and queued writes it dropped as stale |
| `last-capture-hold on\|off` | holds every state write in front of the serial queue until released, so a run can make a queued write stale (a Capture opened meanwhile waits for the queue: run it in the background and release the hold) |
| `last-capture-roundtrip` | stores a history with one Annotation of every kind in `AnnotationKinds.all` (iterated), a kind no snapit knows, a crop and more Undo steps than the cap through the state file's encoder and decoder; `ok kinds=<ids>` or `error <what differed>` |
| `annotation-kinds` | the ids in `AnnotationKinds.all`, one per line |
| `editor-inject-kinds <N>` | one Annotation of every kind in `AnnotationKinds.all` added to Editor N, each its own Undo step (a ticket that adds a kind is covered by the Reopen flow with no edit) |
| `editor-state-crop <N> get\|set <x> <y> <w> <h>` | Editor N's crop in image points (`none` for the whole Capture); `set` is one Undo step. Stands in for the Crop tool, to check the crop is stored |
| `editor-menu-quit` | chooses "Quit snapit" in the helper's own menu (replies at once, the quit goes on in the background) |
| `editor-front` | the number of the Editor whose window is frontmost (a run never activates the helper, so no window is key; the order shows "brought forward") |
| `editor-prompt` | `none`, or `shown close\|quit editor=<N> title=… message=… buttons=Cancel,Discard escape=Cancel command-d=Discard tooltips=…\|…`: the question an Editor is waiting on |
| `editor-prompt-answer discard\|cancel\|escape\|command-d` | answers it: a button is pressed as a click does; Esc and ⌘D reach the sheet as key events. `none` when nothing is asked |
| `editor-drop <N> begin\|taken\|refused` | `begin` makes the drag's file and image from the Capture as it is now (pressing the thumbnail); the others end the thumbnail's drag session as the system does for a drop that was taken (an Export) or that nobody took |
| `export-hold on\|off` | holds every Copy and Save after it took its snapshot, until released, so the Capture can be edited while an Export is still running |
| `editor-first-mouse <N> item <id>` | the view under the centre of that toolbar item's control: `hit=<class> accepts-first-mouse=yes\|no` (Delete Capture's is `no`, every other control's `yes`) |
| `quit-event` | (both processes) sends this process the quit AppleEvent, as logout or `osascript` does, and replies `ok` at once |
| `editor-key <N> close-button` | presses the title bar's close button (`performClose`, which asks the window's delegate) |
| `reopen-notice`, `reopen-notice-close` | `shown <message>` while "That Capture couldn't be reopened." is on screen (else `none`); press its OK button |
| `onboarding-facts` | the Onboarding window: `window`, `title`, `activation`, `occlusion-visible` and `miniaturized` (as macOS reports them; test mode ignores occlusion), `step`, `step-number`, `step-title`, `stored-step` (what a relaunch resumes at), `heading`, `text`, `try-it`, `user-guide` (`available` once the User Guide window sets its hook), the step's own lines (`save-location`, `shortcut <id>\|<combo>\|<glyphs>\|<flag>`, `login`, and at Screen Recording the guide's `guide-…` lines: `guide-state`, `guide-variant` (`prompt` or `systemSettings`), `guide-update`, `guide-checks`, `guide-animation` (`playing`, `stopped` or `idle`), `guide-loops`, `guide-loop-seconds`, `guide-plays`, `guide-headline`, `guide-message`, `guide-reset-failure`, `guide-turned-off`) and one `button <id>\|<title>\|<tooltip>` line per button |
| `onboarding-press <button id>` | what clicking a button does (`next`, `back`, `done`, `open-at-login`, `user-guide`, `open-screenshot-shortcuts`, `open-system-settings`, `relaunch`, `replay`); `shortcut.<id>` starts a recorder and `shortcut-clear.<id>` clears one. The folder chooser is a real panel: `onboarding-choose-save-location <folder>` sets the folder |
| `onboarding-activate` | what happens when the user comes back to snapit's window (it lost focus, then became active): the guide looks at Screen Recording again. A scripted run never activates the helper, so this stands in for it; nothing else makes the guide look |
| `helper-owner` | (helper) the process ID of the menu bar app that started it, or `none`. A helper is a copy's own when it started it or its owner is gone (a killed copy's helper stays with the user's Editors and the next copy uses it and quits it with itself); a copy retires only a helper whose owner is a live other copy (the relaunch and Move to Applications cases). `HelperOwnership.isOurs` is the one rule |
| `onboarding-hide`, `onboarding-unhide`, `onboarding-close`, `onboarding-key <key code> [<modifier>,...]`, `onboarding-snapshot <png>`, `onboarding-user-guide-fixture on\|off` | minimise and restore the window (the animation stops and plays again); press the close button (the helper quits); a key as a Shortcut recorder receives it; render the view; set or clear the User Guide hook with one that writes `<root>/user-guide-opened` |
| `guide-facts`, `guide-press`, `guide-activate`, `guide-hide`, `guide-unhide`, `guide-close`, `guide-snapshot` | the same for a Permission guide that has its own window (a Capture without Screen Recording, an update, a folder a Save can't write to): `guide-facts` is `window`, `title`, `activation` and the guide's lines. The first argument names the guide (`folder`); the Screen Recording guide when none is named, so `guide-press folder retry` presses Try again. The folder Permission guide's lines: `guide-folder`, `guide-code` (the `errno`), `guide-cause` (`privacy`, `notPermitted`, `missing`, `readOnly`, `diskFull`, `other`), `guide-category` (the Files & Folders switch for the folder, `Documents Folder` and so on, or `none`: a folder with no switch gets no drawing and no Open System Settings; under the run's root a folder named `Documents`, `Desktop` or `Downloads` stands in for the real one, and `chflags uchg` makes a real `EPERM` with no switch), `guide-failures` (how many failures it has been shown, an open guide being updated by the next one), `guide-retry` (`available` while its Editor is open), `guide-retrying`, `guide-animation`, `guide-plays`, `guide-headline`, `guide-message` |
| `guide-choose-folder <folder>` | what choosing a folder in the folder Permission guide's chooser does (inside the run's root; the chooser is a real panel): it becomes the Save location and the Capture is saved there from its Editor |
| `system-shortcut-fixture add <key code> [<modifier>,...]\|reset` | macOS's own shortcuts a Shortcut can clash with, besides ⌘⇧3, ⌘⇧4 and ⌘⇧5 |
| `update-facts` | the update window: `window`, `title`, `activation`, `state` (`checking`, `newer`, `up-to-date`, `unreachable`), `headline`, `detail`, `reminder`, `url`, `notes` (percent-encoded), `notes-bytes`, `notes-blocks`, one `notes-block <kind>\|<text>` line per rendered block of the release notes and one `button <id>\|<title>\|<tooltip>` line per button |
| `update-press download\|close` | what pressing the window's button does (Download opens the release page through the browser edge and closes the window) |
| `update-snapshot <png>` | renders the window to a PNG inside the root |
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

## The Last Capture store

The newest Capture is the Last Capture. Its files are in `<cache>/captures/` (mode 0700, files 0600):
`capture-<N>.pixels` (written by the menu bar app when the Capture is taken) and, once the Capture has
a change, `capture-<N>.state` (JSON: `version`, `revision`, `exported`, `history`). A flow reads them
from `$RUN_ROOT/captures` with `plutil -extract <key> raw -o - <file>` (a scalar, or the count of an
array: `history.state.annotations`, `history.undoSteps`). Nothing else reaches into the store.

- **Who writes what.** Only the Last Capture's Editor writes the state, through the existing `Codable` types
  (`AnnotationHistory`, so a kind or a field another ticket adds is stored with no edit here). It hands
  `LastCaptureStore` a snapshot about 0.5 s after the first change (one-shot, never a repeating timer;
  later changes ride along) and once more, synchronously, when it closes; a snapshot is skipped when
  the revision and the exported flag are those of the last one written. Every other Editor keeps its Capture in memory.
- **Stale writes.** The store has one serial queue and a generation number, bumped on the main thread when a
  new Capture becomes the Last Capture, at Delete Capture and when the helper is told to quit. A write
  queued under an older generation is dropped when it runs, and checked again just before its rename.
  The helper replies to `open-capture` and `quit`, and sends `delete-capture`, only after `fence()` (the
  queue has drained), and the menu bar app removes files only after that.
- **Removal.** `CaptureFiles.remove(number:)` and `removeAll()` delete only `capture-<N>.pixels`, `.state` and their
  `.partial` files, then try `rmdir` (it fails while anything else is in the folder). The menu bar app does it
  at a new Capture, Delete Capture, a damaged Reopen, quit and launch.
- **Reopen.** The menu item sends `reopen-capture <N>`. The helper maps the pixels as they are and reads the state:
  no state file is an untouched Capture, an unreadable one (or a pixel file that is cut short) is damage. Damage
  shows `ReopenNotice` ("That Capture couldn't be reopened."), answers `error could-not-reopen` and the menu bar
  app drops the Last Capture, so the item greys out (after bringing the helper in front, so the message is
  seen). `LastCapture` (observable) is what the menu item reads. A Reopen that arrives after a newer Capture
  has become the Last Capture (Capture numbers only grow) or after the Capture was deleted answers
  `error superseded`: no message, nothing deleted, nothing demoted.
- **Quit.** The built-in `quit` command awaits `QuitPreparation.steps` (`Shared/Commands/QuitPreparation.swift`) before it
  replies, and the helper's own "Quit snapit" runs the same steps first. The Last Capture's step supersedes the
  generation and drains the queue. A feature that must act before quitting appends a step; **never register a second
  handler for `quit`** (`SocketCommandRegistry.register` asserts a command is registered once).
- **The Quit prompt.** A step cannot cancel, so `QuitPreparation.confirmations` (each returns whether to go on) run
  first, for every quit nobody has been asked about, and `QuitPreparation.confirm()` shares one question between
  everyone who asks while it shows (at logout both processes ask at once). The menu bar app asks the helper
  (`confirm-quit`: `ok` to quit, `cancel` to stay; anything else stays while the helper is alive) from the Quit snapit
  menu item (`EditorHelperQuitCheck`, which then calls `QuitPreparation.markConsented()`), and from
  `AppDelegate.applicationShouldTerminate` for a quit the system or an AppleEvent starts (on a background queue,
  replying with `terminateLater`). The helper's own "Quit snapit", its AppleEvent quits (the Dock) and the Permission
  guide's "Relaunch snapit" ask through `confirm()` too. The `quit` command and a relaunch's own quit never ask
  (`QuitPreparation.isDecided`), so a scripted run's clean-up still quits at once; a flow reaches the prompt with
  `menu-click quit`, `editor-menu-quit` or `quit-event`. The helper's confirmation brings the first Editor with
  unexported edits forward and asks once (`EditorSessions.confirmQuit`). A prompt answered after the 3600 s time limit
  quits nothing: the menu bar app gave up waiting and stayed.
- **When a close asks.** `EditorSession.requestClose()` (the close button, ⌘W, Esc) asks when
  `closeWouldLoseWork`: not the Last Capture's Editor, and `EditorDocument.hasUnexportedEdits` (it has Annotations or a
  crop, and the revision differs from the last Copy, Save or taken drop). `close()` never asks (Delete Capture, Copy
  and Save close this way). Before counting, `commitPendingEdits()` finishes anything still being typed.
- **The prompt** is a real sheet (`EditorPrompts`) with Cancel (Esc) and Discard (⌘D). A run
  answers it with `editor-prompt-answer`, so nothing waits on a modal.
- **Kinds with fields.** `AnnotationKind.sampleAnnotation(id:origin:index:)` gives the round-trip one Annotation of
  the kind with every field non-default; the default sets the style. A kind that adds a field to `Annotation` (Text's
  string and size, #25's) overrides it and sets that field to a non-default value, so a field missing from the
  `Codable` keys fails `last-capture-roundtrip`.

`scripts/run/flows/50-last-capture.sh` is the model. To work on one flow, `SNAPIT_FLOWS="10 20 50" scripts/check-run.sh <app>`
runs only the flows whose numbers are listed (a flow that needs `AT_REST` needs flow `20`).


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
menu bar app, then sources every flow in name order (`05-` the run's own measuring tools, `10-` menu bar app, `20-` Screen Capture
into the Editor and Copy, `30-` the Editor, `35-` Editor warm-up and the helper launched on its own, `36-` the Editor's tools, `37-` Text, Highlighter, color and width, `38-` Redaction and Crop, `40-` Area Capture with Capture on release, `42-` Area Capture with the Action bar, `43-` Timed Capture (its relaunch check, that the timer is remembered, runs in a second snapit under its own root, because a relaunched snapit's test defaults cannot change a key an earlier launch stored), `44-` Window Capture, `45-` Save and drag-out, `47-` the Color picker (before the Last Capture flow and Settings, which relaunch the menu bar app), `50-` the Last Capture store and Reopen Last Capture (which quits and restarts the menu bar app), `52-` Settings (which quits and restarts the menu bar app), `56-` Check for Updates, `57-` a missing permission (Screen Recording at a Shortcut press or menu item, a folder a Save can't write to, a Save that fails after the hand-over; it relaunches the menu bar app), `80-` Move to Applications and the translocation
check, `90-` Editor helper and Quit, which must stay last). Flow `80-` quits and relaunches the
menu bar app, so a flow after it starts with a freshly started menu bar app: `AT_REST` from `20-`
is stale and no in-memory state (pretended paths, fixtures, Shortcuts) survives.
Flow 44 uses the helpers of flow 40: `SNAPIT_FLOWS="40 44" scripts/check-run.sh <app>` runs the two.
A flow can use everything in `scripts/run/lib.sh` (`send`, `send_slow`, `expect_equal`,
`expect_contains`, `wait_until`, `footprint_mb`, `expect_memory_returns`, `expect_not_spinning`, `png_field`, ...), the Editor
helpers in `scripts/run/editor.sh` (`capture_into_editor <trigger>` runs a Capture and sets
`EDITOR_N` and `HELPER_PID`; `copy_closes_editor`, `app_type <pid>` for Foreground (Dock icon)
versus UIElement (agent), `onscreen_windows <pid>`, `helper_pid`) and the variables `APP_SOCK`,
`EDITOR_SOCK`, `RUN_ROOT`, `APP_PID`, `INSPECT` (the `png-inspect` tool, which also lists a
process's windows: `png-inspect windows <pid>`, the Area overlay's panels: `png-inspect overlay-windows <pid>`, reads one pixel in sRGB: `png-inspect pixel <file> <x> <y>` (`r g b`) or in the PNG's own color space: `png-inspect raw-pixel <file> <x> <y>` (`r,g,b`), and
compares a PNG with the fixture: `png-inspect diff-fixture <file> <w> <h> [<x0> <y0> <x1> <y1>]` prints how
many pixels changed, their bounding box and how many lie inside and outside a rectangle, and compares two
PNGs: `png-inspect compare <a> <b>`, and for a Redaction `png-inspect verify-redaction ...`, which recomputes every block mean from the fixture formula, and for a crop `png-inspect diff-crop ...`, `diff-fixture` for the pixels of the fixture that start at an origin; `scripts/run/png-inspect.swift` has the arguments). A flow that draws in
the Editor sources `scripts/run/editor-tools.sh` (`drag`, `click`, `keystroke`, `style`, `export_png`, `preview_png`,
`click_on`, `expect_enabled`, `expect_within`, `blend`, `fixture_diff`, `fixture_pixel`, ...; `36-editor-tools.sh` is the model). `SNAPIT_FLOWS=<regex>` runs only the flows whose file name matches, while you write one.

The Area flows (`40-area-capture.sh`, `42-action-bar.sh` and `43-timed-capture.sh`; each uses the earlier ones' helpers) show how to drive an overlay. "After selecting an Area" is the default (Show Action bar) unless a flow writes `defaults-set afterSelectingArea captureOnRelease`, as flow 40 does at its top, so a flow that drives the overlay sets the one it needs. In a flow: `press-shortcut capture-area`
shows it, `overlay-mouse` and `overlay-key` are the user's hand, `overlay-wait` returns when the
Capture is in the Editor or cancelled, and `png-inspect verify-fixture <file> <w> <h> <full w>
<full h> <x> <y>` checks a crop of the fixture pixel by pixel.

1. Pick the fixture: `send "$APP_SOCK" "fixture-display 2 301 187"`.
2. Drive the app through a command, never the real system. A Capture opens an Editor in the helper:
   `capture_into_editor "menu-click capture.screen"`, then drive the Editor with `editor-key` and
   `editor-press` on `$EDITOR_SOCK`.
3. Assert on what is observable: dump the pasteboard PNG (`pasteboard-dump-png`), read it with
   `"$INSPECT" info` and `"$INSPECT" verify-fixture`, look at files under `$RUN_ROOT/save`, and check
   that memory returned with `expect_memory_returns` (see "Resource checks").
4. Delete what you create under `$RUN_ROOT` (the run removes the root at the end).

### Asynchronous work, and a slow machine

A check reads what a command has finished, and waits for what it has only started. `press-shortcut`, `menu-click` and
`editor-press` reply when their action has finished; a window the helper shows, a window that closes, a process that
quits, a look at the permission, a file the app removes at quit and the window server's list of windows follow some
time after. A flow reads those only once the exact condition holds: `wait_until <seconds> <predicate>` with a generous
bound, then one `expect_*` of the value (never a `sleep` before a read, never a looser expectation).

- `open_editors_are <numbers>` and `expect_onscreen_windows <description> <pid> <count>` (`editor.sh`) wait for the open
  Editors and for the window server's count of a process's windows.
- A counter a launch can move (`screen-recording-facts` `resets=`) is read before the launch (`restart_app`), and the
  flow asserts the exact change once the launch's own effect is visible (the guide is showing, `guide-state` is
  `denied`), then asserts what a later press adds (nothing) once the press has been processed (`guide-checks` rose).
- The guide looks at the permission when its window becomes active; a look already under way answers for the
  permission as it was before, so a flow that changes the fake macOS repeats `guide-activate` or `onboarding-activate`
  (`wait_until 15 ... guide_activate_until <key> <value>`) until the guide shows the new value.
- `area_result` prints the overlay's facts when `overlay-wait` gives no answer, so the log names the state a gesture
  left the overlay in.

`check-run.sh` also ends with the isolation assertion: no `dev.snapit.snapit*.plist` in
`~/Library/Preferences` is new or changed, `defaults read` of the bundle ID domains is unchanged,
`~/Library/Caches/dev.snapit.snapit` is unchanged and the general pasteboard was not written to by the
run. The general pasteboard is the user's, and a user may copy something during a run, so the run never
reads its contents: `png-inspect general-pasteboard` prints the change count and, only when the count differs from the one it is given, a shape (`png`, `hex`
for plain text of the form #RRGGBB, matched in memory and never printed, `other`, `empty`); a pasteboard
nobody wrote to is never read. snapit writes
only a PNG (Copy) or a hex string (the Color picker), so a rise in the count fails the run only when the
pasteboard now has one of those two shapes (`pasteboard_verdict` in `lib.sh`); a copy of anything else
passes with a note. A user who copies a PNG (a screenshot to the clipboard) or a #RRGGBB string during a run
still trips it: run again. A real regression, product code writing to `NSPasteboard.general`, changes the
count to one of those shapes and is caught. Flow `05-run-helpers.sh` puts a PNG, a hex string and other text on a
private pasteboard (`png-inspect pasteboard-fixture`, never the general one) and runs the same probe and
`pasteboard_verdict` over it: the PNG and the hex string fail, the other text does not.

`overlay_panels` waits up to 20 s for the window server's list to agree with the app's own count.

The menu bar app is started again with `relaunch_app [<why>]` (after it quit or was killed; sets `APP_PID`),
`restart_app [<why>]` (quit, wait, relaunch) and `launch_app [<root>]` (a second one under its own root), all in
`lib.sh`; do not write a flow's own `nohup "$APP_EXE"`. The helper's process count and the warm-up state are
`helper_count`, `no_helper`, `some_helper`, `warm_state`, `warm_is`, also in `lib.sh`.

## Resource checks

snapit's resources are judged by the four questions in `CODING_STANDARDS.md` ("Engineering priorities"): justified,
proportionate, released, well chosen. A review reads the code against them; the run checks release and
proportion from the outside, against the process's own baseline and the feature's own size, with margins
no machine's noise reaches, and it runs the same on every machine. The checks, all in `scripts/run/lib.sh`:

- **Memory returns** (`expect_memory_returns <label> <pid> <baseline MB> [<feature MB>]`): after a flow of Captures,
  Saves, Redactions, Editor cycles and the like, the process's footprint is back within the larger of 25 MB
  and half of the feature's own size (`pixels_mb <w> <h>`, e.g. 56 MB for a 5K Capture) of its baseline. It polls
  for up to 10 s, because the system gives some memory back late. `expect_steady_across_cycles` holds
  the helper's footprint to the same margin from one cycle to the next.
- **Peak is the feature's size** (`expect_peak_proportionate`): what an overlay or a set of Redactions holds
  at its peak is at most four times the feature's own size plus 25 MB on top of the baseline.
- **A Capture's frame goes with its file** (`frame-freed-at-open`): the menu bar app lets go of the frame
  (a `CapturedScreen`) once its Capture file is written, before it waits for the Editor to open; every
  Capture (Screen, Area, Window, Timed) asserts it.
- **An overlay's frames and objects go when it ends** (`overlay-frames-freed`, `overlay-panels-freed`): after a
  Color picker pick or Esc the app holds none of the overlay's frozen frames and none of its controller, panels
  or scene views (flow 47). These are the release check of a flow that ends on an idle overlay: the footprint
  keeps a closed overlay's last 5K surface for as long as the window server holds it (a CI runner's virtual
  display holds it long after the app let go), so flow 47 asserts the app's own hold and its peak, and does not
  compare its footprint at rest with a baseline.
- **A failed memory check names the holder** (`memory_diagnosis` in `scripts/run/lib.sh`): the log of a failed
  `expect_memory_returns` carries the footprint's largest categories, the regions with 8 MB or more dirty
  (`footprint -vv`), the IOSurface, CoreAnimation, CG image and MALLOC lines of `vmmap --summary` and of
  `vmmap -v`, the live window, layer, image and surface classes of `heap`, the `leaks` line and, for the menu bar
  app, `live-windows` and the overlay probes. Every tool is limited in time and never fails the run. It then
  logs three nudges with the footprint before and after each (`nudge wait 3 s`, `nudge a window shown and
  closed`, `nudge fixture display reset`): a footprint that falls was waiting for the system, one that stays
  is held. Flow 47 also prints an `info:` line after its ten picks (not a check) with the footprint at rest.
- **The helper goes** (`gone "$HELPER_PID"` after the last window closes, in every flow that opens one):
  no helper process is left at rest.
- **The cache folder holds only what a flow's end leaves** (`expect_cache_holds_only_expected`, run by
  `check-run.sh` after every flow): no shared export file, no `.partial` file, the files of at most one
  Last Capture, and only PNGs in `drag-out/`.
- **Nothing spins at rest** (`expect_not_spinning <label> <pid> <seconds>`): the process averaged under 5% of
  one CPU over the seconds given. It runs on the Editor helper holding the heaviest Editor of the run
  (flow 38), on the menu bar app with the Area overlay up (flow 40) and at the end of the run (flow 90).

Flow `05-run-helpers.sh` checks the spin check on a process that burns CPU and on one that sleeps, and the
cache check on a leftover export file.

Review checklist for a change that holds a resource (CPU, memory, GPU, disk, file handles; the questions
are `CODING_STANDARDS.md`'s, "Engineering priorities"): justified, proportionate, released, well chosen.

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

The Action bar is layers over one `NSGlassEffectView` (Liquid Glass), because AppKit and SwiftUI controls keep memory for good once a process has shown them. Each panel's content view is an `AreaOverlayContainerView`: the layer-hosting
`AreaOverlayView` (the scene) fills it and, once an Area is being adjusted, the bar sits above it as
two small views, `ActionBarBackdropView` (an `NSGlassEffectView`, the Liquid Glass capsule) and
`ActionBarTileView` (layer-hosting, the tiles). Both return nil from `hitTest` and so does the
container (it hands everything to the scene view): every click reaches `AreaOverlayView`, whose
controller finds the tile under the pointer from `ActionBar.control(at:)` and calls its pointer hooks.
A tile is a full-size hit area. Tooltips are `CATextLayer` pills in the scene, shown after the pointer
rests 0.5 s on a tile (a one-shot `DispatchWorkItem`, cancelled when the pointer leaves): AppKit
tooltips sit below the overlay's window level. The container draws nothing (`wantsUpdateLayer`), so
no full-screen backing store exists.

Flow 42 checks that five Captures through the bar leave memory where it was and that the overlay with
the bar up peaks in proportion to its frozen frame. The Color picker toast and the countdown badge are glass too.

### The Color picker

The Color picker is a state of the Area overlay (`State.pickingColor`), not a second overlay system:
the same frozen frames, panels and key monitor. It opens from the Action bar (`PickColorActionBarItem`:
the button and P; Esc goes back to the bar with the Area kept), and from the menu's Pick Color
and the `pick-color` Shortcut (`AreaCaptureFlow.startPickingColor()`: the overlay starts in the picker,
Esc ends it, and no Editor is warmed up because no Capture opens). `ColorPickerSession` is the sampled
device pixel as a plain value: the pointer aims it with `AreaGeometry.pixel(of:scale:...)` (display-local
points, `floor(point * scale)`), the arrow keys nudge it by one device pixel (Shift: ten) and clamp it
to the frame, so a nudge at 2x is half a point and the pointer does not move. A press picks when it is
let go, wherever it was dragged to; the second click of a double-click on the Pick Color button within
`NSEvent.doubleClickInterval` of the picker opening is that button's and picks nothing.

The hex is the frozen frame's pixel as stored, in the display's own color space, never converted to
sRGB: `PixelColorReader` crops the one pixel out of the `CGImage` and draws it into a 1 x 1 context in the
image's own color space, so a Display P3 display gives Display P3 values (the same numbers the Capture
file and the Editor hold for that pixel) and any pixel layout reads alike. The loupe (`PickLoupe`)
shows 15 x 15 device pixels at 16x with the sampled pixel outlined, and its swatch is filled in the
frame's color space too. The dim and the crosshair are off while picking. On a pick the flow copies the
uppercase hex through `AppPasteboard.current` and `ColorToast` shows "Copied #RRGGBB" in a small
non-activating panel of its own (the overlay has closed): its fade and its removal are one-shot delays,
and a new toast replaces the old one.

`47-color-picker.sh` checks the sampled pixel and hex against the fixture formula at 1x and 2x, at the
frame's corners, on a second display at negative coordinates (left and above), with a BGRX frame,
under either "After selecting an Area" setting, reads the outlined cell and the swatch back from
`overlay-snapshot`, and checks memory, the toast's lifetime and the missing warm-up.
`SNAPIT_FLOWS="10 20 40 42 47"` runs just those flows (each builds on the helpers of the ones before it).

## The Window Capture

The Window Capture (`snapit/Window/`) is the Area overlay in `.window` mode (`AreaCaptureFlow.start(mode:)`,
`WindowCaptureFlow.start()`): the same panels, frozen frames, layers and window list (`OnScreenWindow`, now with
the `CGWindowID`), but the pointer only picks. Hover highlights the front-most window under the pointer from the
list read when the Shortcut fired (no window-server call per move, no polling); a click captures that window and
nothing else (`AreaOverlayOutcome.window`); a drag selects nothing; there is no Action bar whatever "After
selecting an Area" says. The capture itself is a second seam, `WindowCaptureSources.current`: the real one
(`ScreenCaptureKitWindowSource`) fetches `SCShareableContent` once the overlay shows, matches the window id and
captures through `SCContentFilter(desktopIndependentWindow:)` at `contentRect * pointPixelScale`, SDR, in the
display's color space; the fixture one (`FixtureWindowCaptureSource`) returns an image of the window's size with
transparent rounded corners (the formula is in its header and in `scripts/run/png-inspect.swift`).
`fixture-window-fail on|off` makes the capture fail, as if the window had closed.

**Shadow.** The spec leaves the window shadow open. Window Captures do not include it
(`WindowCapture.includesShadow` is false, passed to ScreenCaptureKit as `ignoreShadows`), and the Capture is exactly
the window's frame with transparent rounded corners. Flipping the constant is a one-line change; the steps to check
it are in `docs/development/manual-checks.md`.

**Alpha.** Pixels are premultiplied BGRA in memory, in the Capture file and through the Export stages (crop copies
bytes; Annotations are drawn by Core Graphics into a premultiplied context, so they composite over the corners).
The engine's PNG encoder looks at the pixels: when every alpha is 255 (a Screen or Area Capture) the PNG is RGB
(colour type 2), otherwise RGBA (colour type 6) with the colours un-premultiplied, and the 1x average and the
thumbnail average all four premultiplied channels. The scripted run asserts both: window Captures give RGBA PNGs
through Copy and Save (and the 1x averaged ones), a Screen Capture and an Area Capture still give RGB ones
(`png-inspect info` prints `color_type`; `rgba-pixel` and `verify-window` decode the PNG with a decoder of their
own, so a premultiplied or dropped alpha shows).

## Adding to the Area overlay

| To add | Add a file in `snapit/Area/` | And |
|---|---|---|
| a button on the Action bar | `ActionBar/<Name>ActionBarItem.swift` (`ActionBarItem`: `id`, `order`, `title`, optionally `glyph` (a `CGPath` in a 14 x 14 box, origin at the bottom left), `look`, `tooltip`, optionally `keyEquivalent`, and `perform(on:)`) | one line in `ActionBar/ActionBarRegistry.swift` |
| a control that is not a button (Timed Capture's slider) | the same item file, with `makeControl(context:)` returning an `ActionBarControl` subclass (`ActionBar/ActionBarControl.swift`): set `preferredSize`, add layers to `layer` in `didLayout()`, override `pointerDown`/`pointerDragged`/`pointerUp` (points in the tile's own space, top-left origin; the controller keeps calling `pointerDragged` while the button is down, wherever the pointer is) and `stateChanged()` for hover and press. `prototype/area-overlay`'s `Geo.dBar`, `sliderValue` and `sliderX` are the slider's geometry | one line in the registry |
| a key that runs an Action bar item (the Color picker's P) | nothing: the item's `keyEquivalent` | the key monitor in `AreaOverlayController.handle` asks the registry |
| a new way out of the overlay (Timed Capture) | a case in `Overlay/AreaOverlayOutcome.swift`, produced by the item through `host.finish(with:)`, and its handling in `AreaCaptureFlow+<Name>.swift` | one arm in `AreaCaptureFlow.finish` |
| an overlay mode (the Color picker's pointer mode) | a case in `AreaOverlayController.State` and the handling of its pointer and key events | `AreaSceneState` for what it draws |
| a test command about the Action bar | `ActionBar/ActionBarCommands.swift` (`registerActionBarTestCommands()`) | nothing |

An item's tile is its hit area and its `tooltip` is the pill the scene draws: the standard button control does both, and a custom control needs only to give `id` and `tooltip` to `ActionBarControl.init`. The bar's size follows the controls' `preferredSize`. A control changes layers inside `CATransaction.setDisableActions(true)`.
`FrozenDisplay.displayID` is the display's `CGDirectDisplayID` for a
feature that needs to know which display an Area is on (Timed Capture's fresh Capture).

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
Permission guide) registers with `SaveFailureSignal.observe` (`FolderGuide.register()`, once, when the helper
starts serving; `observeHandedOver` closes the guide when a Save from its Editor goes through). Its `.folderNotWritable(folder:code:)` carries the
`errno`: `EPERM` (1) is a macOS privacy (TCC) denial, `EACCES` (13) POSIX permissions, `ENOENT` (2) a
missing folder, `EROFS` (30) a read-only volume. The signal covers only the writability check made
before the hand-over. A failure after it (disk full, the final rename) cannot reach the Editor, which
may be gone: the menu bar app sends it to `SaveService.observeWriteFailures` observers (on the main
queue) and beeps when there are none. `SaveFailureNotice` (`snapit/Export/`) is the one observer: it asks
the helper, started if it is not running, for the folder Permission guide's window
(`show-permission-guide folder <errno|none> <folder>`), worded "Your Capture was not saved", with Choose
another folder (for the next Save) and no Try again, because the pixels have been handed over. The menu bar
app opens no window itself, and the helper quits when that window closes. Nothing is shown once the menu bar app is quitting.

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

### Text, Highlighter, color and width

`TextAnnotationKind` overrides what a path-painted kind gets for free: `TextLayout` sets the lines (the one place that knows font, line height and baselines) and Core Text draws them in the Export and in the canvas's `TextAnnotationLayer`, a `CALayer` whose `draw(in:)` calls the kind's own `draw`, so the preview is the Export (same glyph settings in every context, whole-point layer frames so nothing is resampled). While a text is typed, `TextEditingController` holds an `NSTextView` in a host view beside the canvas (the canvas is layer-hosting, so it cannot have subviews). A press on the canvas first asks `EditorSession.consumesPointerDown` (`EditorSession+Text.swift`): a click while typing only commits, and the canvas refuses first responder while a text is typed so AppKit does not move the keyboard on that same press. Commit also happens on Esc, another tool, Copy and closing; a plain key (a tool's letter, ⌫) is a character while typing, and ⌘Z undoes the typing (the text view's own `UndoManager`) before it undoes Annotations.

The Highlighter paints translucent at paint time (stored colors stay opaque) and has its own width presets (`WidthChoice`) and remembered key (`highlighterWidth`). The color controls and the size control (three tiles: text sizes for a Text, widths for the rest, since the two never apply together) are always in the options pill (a toolbar never changes size) and are disabled when they do not apply (`EditorSession+Color.swift`). Narrower than the pills need on one row, the options pill takes a second row under the title bar row (`EditorChrome`), so the window can be about half a 1440 pt display wide. A color is kept in extended sRGB (`AnnotationColor`), so a Display P3 pixel sRGB cannot show survives the eyedropper. The text view's ⌘X, ⌘C, ⌘V and ⌘A are routed in `EditorWindow` and go through `AppPasteboard.current` (`TextEditingView`). The eyedropper is not a tool on the rail but a mode (`isEyedropperActive`, `EyedropperTool`), reading the Capture's read-only pixels. The color panel is an edge (`ColorPanelEdge`); `ColorPanelController` turns a drag in it into one Undo bracket that the mouse coming up closes, with no timer.

Test-mode commands for these: `editor-type` (key events, `%0A` is Return), `editor-text` (the editing state, whether the eyedropper is on, each Text's box), `editor-double-click`, `editor-color-panel` (`state`, `choose`, `drag`), `editor-window-image` (draws the window's content to a PNG, for looking at the layout), `editor-key-command` (⌘ and a key), `editor-pasteboard-string`, `editor-control-enabled <N> <tooltip>` (whether a control is greyed out as the window shows it), `editor-layout` (minimum width, overlapping controls, which row the options pill is on), `editor-eyedropper-cursor` (the cursor glyph's tip against its hot spot at 1x and 2x), `editor-become-key` (an inactive app has no key window, so this sends the delegate what AppKit would), and `editor-click <N> control <tooltip>` for one control of an item that has several (a swatch, a width tile).

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

Add an `AppShortcut` in its own file (`Shared/Shortcuts/AppShortcut.swift` shows the shape; the
type is shared because Settings in the helper lists the Shortcuts), bind it with one line in
`ShortcutBindings`, and press it in a flow with `press-shortcut <id>`. A Shortcut the user may
record in Settings is also an `Entry` in `Shared/Shortcuts/ShortcutCatalog.swift` (`AppShortcut.window`
and `AppShortcut.pickColor` are in their own files beside `AppShortcut.swift`). `Shortcuts.current` is an `ObservedShortcuts`: a menu
section that reads `menuShortcut(for:)` follows `setCombo`, so a rebound Shortcut's glyph changes
with no code of its own.

## Settings

Settings is one window in the Editor helper (`snapit-editor/Settings/`): `SettingsWindow` (one
instance; a second request brings it forward and reads Open at Login again), `SettingsView` (a
single `Form`, one `Section` per `SettingsSection`) and `SettingsModel` (what it shows; every
change is written through `AppDefaults.store` at once, and the Editor, the Area flow and Save read
their key when they need it, so nothing waits for a relaunch). `SettingsControls.swift` holds each
control's id, title and tooltip, which the view and `settings-facts` both read. The About section is
a list: a row is one file (`VersionAboutRow.swift`: its `SettingsControl` and an `AboutRow`, text or
button) and one line in `AboutRows.all`; the view and `settings-facts` draw from the list.

| To add | Do |
|---|---|
| a setting | a key and a reader in `Shared/Settings/<Name>Settings.swift` (the reader falls back to the default); a `SettingsControl` in `SettingsControls.swift`; a setter in `SettingsModel`; a row in `SettingsView`; a line in `SettingsFacts.describe()` and a case in `SettingsFacts.press` |
| something Settings needs from the menu bar app | a `SocketCommand` in `Shared/Commands/SettingsCommands.swift` and its handler in `snapit/Settings/SettingsAppCommands.swift` (Open at Login and applying a Shortcut do this) |
| a window of the helper that opens Settings, or a row beside it | `SettingsWindow.show()` is the one entry; the menu bar app's `SettingsMenu` section holds Settings…; User Guide and Check for Updates… are each a `MenuSection` file and one line in `MenuModel.sections` after it (`QuitMenu` brings the separator before Quit snapit). The order in `MenuModel.sections` is `SettingsMenu`, then the User Guide's section, then `CheckForUpdatesMenu`, then `QuitMenu`: a User Guide section goes between `SettingsMenu` and `CheckForUpdatesMenu`, never after it |

Open at Login lives in the menu bar app (`LoginItem.current`: `SMAppService.mainApp`, or the fake
in test mode); the helper sends `login-item-status` (and `shortcut-combos`) when Settings opens or
comes forward and `login-item-set` when the switch is flipped. Nothing polls. `LoginItemDefault`
registers the login item on the launch of a copy that runs from an Applications folder with no
move or fix pending (`InstallCheck.plan() == .stay`), and records the flag `openAtLoginDefaultApplied`
only once registering worked, so a later Off survives relaunches (`login-item-default` runs it with
the install location the run pretends; flows 52 and 80 use it). The Shortcut recorders use
`ShortcutRecorder`, a local key monitor that exists only while one waits. It refuses what every app
depends on (⌘ alone with a letter or number, ⌥ or ⌥⇧ alone, ⇧ alone) with a hint and a beep, and ignores
key repeats; the result goes to the menu bar app with `apply-shortcut`. The menu bar app's registrar
is the only copy of a combination: Settings asks `shortcut-combos` when it opens (Onboarding does the
same). Two Shortcuts never share keys: recording a combination another Shortcut has removes it
from that one ("Removed from Area."). A combination macOS also uses (`SystemShortcuts.current`)
carries a note under its recorder; it is still accepted.

While developing one flow, `SNAPIT_FLOWS="20 40 45 52" scripts/check-run.sh <app>` runs only
those flows (`52-settings.sh` uses helpers of 20, 40 and 45). The flow `52-settings.sh` is the model for driving a helper window: read `settings-facts`, act with
`settings-press` and `settings-key`, and assert on what the rest of snapit does.

## Onboarding and the Permission guide

Onboarding is a window in the Editor helper (`snapit-editor/Onboarding/`): `OnboardingWindow` (one
instance), `OnboardingModel` (the six `OnboardingStep`s, what each offers, the buttons), `OnboardingView`.
It reuses Settings' pieces: its own `SettingsModel` for the Save location, the Shortcut recorders
(`ShortcutRecorderRows`, `ShortcutRecorder`, `apply-shortcut`) and Open at Login. The step is stored
through `AppDefaults.store` (`onboardingStep`) as it changes; reaching Done stores `finished` and a
finished Onboarding never starts over. The menu bar app decides when it shows
(`snapit/Onboarding/OnboardingLauncher.swift`): after the install location check passes at a launch,
and from every Shortcut press (`ShortcutBindings` runs each action through `whenSetUp`) until it is
finished. After Onboarding is finished, a launch that finds Screen Recording gone after it was granted
(`grantedStale`) opens the Screen Recording guide alone.

The Permission guide (`PermissionGuideModel`, `PermissionGuideView`, `PermissionGuideWindow` for its
own window) is one component: Onboarding's second step and the standalone window show the same model. It
asks the menu bar app over the socket (`screen-recording-state`, `screen-recording-request`); the helper
never calls `ScreenRecordingPermission`, because macOS would list it as a second app. It looks at the
permission when it first shows and when the window becomes active, never on a timer: a scripted run
changes the fake macOS (`screen-recording-simulate`), waits, and asserts the guide has not looked until
`onboarding-activate` / `guide-activate`. The drawing (`GuideDrawing`, `GuideTimeline`) is SwiftUI shapes
whose whole state is one number, `GuideAnimation.progress`; a play is one finite animation of a few loops
(`guide-loops`, `guide-loop-seconds`), and hiding the window or leaving the step cancels it by giving the
drawing a new identity (without that, SwiftUI keeps evaluating the cancelled animation until its
duration ends, which keeps a hidden window busy). `flows/54-onboarding.sh` is the model: it
stores a step, relaunches the menu bar app (a real relaunch keeps the test root), and drives every path.

| To add | Do |
|---|---|
| a Permission guide for another permission | a case in `PermissionGuideKind` (`Shared/Commands/OnboardingCommands.swift`), a model that conforms to `GuideContent` and a drawing beside the Screen Recording ones (`FolderGuideModel` and `FolderGuideDrawing` are the second), a branch in `show-permission-guide`'s handler (`OnboardingHelperCommands.swift`), and the menu bar app asks for it with `OnboardingLauncher.showPermissionGuide(_:details:)`. `PermissionGuideWindow` hosts one window per kind, and the `guide-…` test commands take the kind first |
| a step of Onboarding | a case in `OnboardingStep`, its words and buttons in `OnboardingModel`, its view in `OnboardingView`, its lines in `OnboardingFacts` |
| the User Guide link's target | set `UserGuideLink.open` when the helper launches (in `registerHelperCommands`), not when the User Guide window opens, because Onboarding may show first; the Done step shows the link only when it is set |
| a Capture that finds Screen Recording missing at a Shortcut press | do not call `ScreenRecordingPermission.current.request()` (after an update it does nothing, and it marks snapit as asked): show the guide with `OnboardingLauncher.showPermissionGuide(.screenRecording)`, which asks through `ScreenRecordingAsk` (`screen-recording-request`) and resets a stale entry first. `ScreenCaptureFlow` and `AreaCaptureFlow` (Area, Window and Pick Color modes) do this through `OnboardingLauncher.screenRecordingMissing()`, after the Capture gate is open: it shows Onboarding when that is unfinished (its own Screen Recording step is the guide, so two windows never ask macOS at once), the Screen Recording guide alone when it is finished. A Shortcut meets `whenSetUp` first, a menu item reaches the same check from the flow. After the first update guide has reset the history, later presses show the plain "Turn on Screen Recording" wording |
| a quit that has to ask about Editors | `SnapitRelaunch.run()` ("Relaunch snapit") quits the helper with the built-in `quit`, which runs `QuitPreparation` but asks nothing: the Quit prompt of #28 goes in front of that call |
## Check for Updates

Check for Updates… (the menu, and Settings › About) is snapit's only network call. The menu bar
app makes it; the Editor helper shows the update window and never touches a network.

- **One click, one request.** `CheckForUpdatesMenu` asks the helper to show the update window
  (`show-update-check`); the window (`UpdateWindow.showAndCheck()`, which the About row's button
  calls too) says it is checking and sends `check-for-updates` to the menu bar app, which makes
  the request and replies with an `UpdateAnswer` (`Shared/Updates/UpdateAnswer.swift`, the wire form
  is in its comment). A click while a check runs joins it, in both processes. Nothing asks GitHub at
  launch, on a timer or in the background.
- **The mapping** from GitHub's reply to an answer is one table in `snapit/Updates/UpdateAnswers.swift`
  (`ReleaseVersion` compares three integers, tolerates a leading `v` and rejects everything else).
  A reply row is a case of `56-check-for-updates.sh`: add the row and the case together.
- **The edge** is `ReleaseEndpoints.current`. Product code never builds a request: it hands a
  `ReleaseRequest` (address, headers, timeout) to the endpoint. `GitHubReleaseEndpoint.swift` is
  the one file that may contain `URLSession`, `URLRequest`, `NWConnection` and the like;
  `scripts/check-network.sh` (run by `scripts/test.sh` and the scripted run) fails when any other file
  has them, or the other ways code gets online (sockets, `AsyncImage`, HTML in an attributed string,
  a shell tool such as curl, an `http(s)://` address outside the two files that name GitHub's, a
  network entitlement or App Transport Security setting); when that file stops matching; when
  `import WebKit` appears (a web view can load anything; the User Guide is drawn natively, so the script's
  `WEBKIT_ALLOWED` list is empty); when the engine
  uses a socket or an HTTP library; and when `Cargo.lock` or `Package.resolved` has a crate or
  package that is not on the script's reviewed lists (a new dependency fails until someone has read it).
  Never write those names, even in a comment, anywhere else. Flow 56 adds the runtime check:
  `lsof -a -i` finds no internet socket in the menu bar app or the helper, whatever API would open one.
  The real `URLSession`/CFNetwork/TLS path (memory and CPU after a real check, redirects,
  the headers the HTTP client adds itself) is covered by manual check 9 and 8 in `docs/development/manual-checks.md` only.
- **The window** is `snapit-editor/Updates/`: `UpdateModel` (every word and tooltip, once),
  `UpdateWindow` (window and view), `ReleaseNotesBlocks` (the notes' Markdown as headings, bullets and
  paragraphs, inline Markdown applied, an image shown as its alternative text and never fetched; parsed
  once), `UpdateHelperCommands`. Notes are cut at 300 lines and 20,000 bytes. A link in the notes and
  the Download button open through `BrowserLinks`, which opens `https` links only. The Download button's
  page is built from the tag (`https://github.com/k-electron/snapit/releases/tag/<tag>`); the `html_url`
  in GitHub's reply is never used. The real request sets `User-Agent`, `Accept` and a fixed
  `Accept-Language: en`, and follows a redirect only within `api.github.com`
  (`ReleaseRequest.allowsRedirect`, checked with `update-redirect <url>`).
- **Real network** (the real endpoint, a private repository answering 404, a proxy, no connection)
  is in `docs/development/manual-checks.md`.

## The User Guide

The User Guide is a window in the Editor helper (`snapit-editor/UserGuide/`), drawn natively from one Markdown file,
`docs/UserGuide.md`: no web view, no network, no image. The same file is the guide on GitHub, where its image lines show
screenshots. The Xcode project lists it as a resource of the helper (a file reference in the `docs` group and a build
file in the helper's Resources phase, since `docs/` is not a synchronized folder), so it lands at
`snapit Editor.app/Contents/Resources/UserGuide.md`, once, and `scripts/check-bundle.sh` asserts that and that the menu
bar app has none. No other copy exists in the repo. The menu bar app only asks for the guide
(`UserGuideMenu` → `show-user-guide`, `Shared/Commands/UserGuideCommands.swift`); the helper reads the bundled file when
the window opens and drops it when it closes. `UserGuideWindow` is one window (a second request brings it forward),
`UserGuideModel` is what it shows (the section on the page, the search, the one `follow(_:)` every link goes through, every
tooltip), `UserGuideView` draws it and `GuideDocument` parses the Markdown. `UserGuideLink.open` (Onboarding's Done step) is
set in `registerUserGuideHelperCommands()` when the helper launches, not when the window opens.

The source is a small subset of Markdown that reads well on GitHub and in the window: `# Group`, a section written
`## <a id="id"></a>Title <!-- icon: sf.symbol -->` (the anchor makes the id a link target on GitHub, the comment carries
the SF Symbol, and GitHub shows neither), `###`, paragraphs (the window draws one per line; keep a blank line between
paragraphs, notes and lists so GitHub does not join them), `- ` bullets, `1. ` steps, `> ` notes, pipe tables, and inline
Markdown. A link is `[text](#id)` to a section, which works in the window and on GitHub, or an
`https://github.com/k-electron/snapit…` link, which opens through `BrowserLinks` only when clicked; any other link is
dropped. An image is a line of its own, `![alt](images/…)`, a relative path into `docs/images/`: the window skips the line
entirely, with no block and no alt text. The window also skips HTML comments, whether on one line, inline or across
several lines. Write the words from `GLOSSARY.md` and from the code (the menu, `SettingsControls`, the tool keys), never
from memory.

| To add | Do |
|---|---|
| a section | a `## <a id="id"></a>Title <!-- icon: sf.symbol -->` in `docs/UserGuide.md` (and a line in `scripts/user-guide-checklist.txt` naming the terms it must hold), then `scripts/check-docs.sh` |
| a flow to the checklist | a line in `scripts/user-guide-checklist.txt`: the section id, a bar, then the terms it must hold separated by semicolons. `scripts/check-docs.sh` (run by `scripts/test.sh` before the build) checks the source, and flow 58 checks the guide the helper loaded |
| a block kind | a case in `GuideBlock`, its parsing in `GuideDocument.init(markdown:)` and its view in `UserGuideView.swift` |

The docs check reads the source and names the file and line of every failure: a duplicate section id, a section without
an anchor and an icon, a `#id` link that names no section, an image outside the docs images folder (the path must start
`images/`, with no `..` and no scheme), and a link that goes anywhere but a section or snapit's GitHub repository.

`58-user-guide.sh` drives it: the menu order, one window for any number of requests (and a Dock icon), the checklist read back
through `user-guide-facts` and `user-guide-text <id>`, the icon of every section and the count of section links against the
source, the blocks the selected section draws (`block <kind>|<text>` lines of the facts), navigation (`user-guide-select`,
`user-guide-link`, `user-guide-press`), search, links (GitHub reaches `<root>/browser-links`, everything else is refused),
Onboarding's link, and the helper's lifecycle and memory. The flow also writes a guide with image lines, a linked image,
an inline image and comments in every form to the root and opens it with
`user-guide-fixture <file in the root>` (`off` drops it): the next window parses that file with the same parser instead of the
bundled one, and the flow shows that no image block, alt text or comment text is drawn or found by search. `user-guide-snapshot`
renders only part of a SwiftUI view: for the look use a real screen (`docs/development/manual-checks.md`).

## CI environment

CI runs `scripts/test.sh` on a GitHub-hosted macOS runner, which is a virtual machine: a virtual
display with no GPU, a few CPUs shared with the host, and a window server that may post
screen-parameter notifications for nothing (a Dock that resized, a display that "changed" to the same
frame). The run is the same there as anywhere: every check, margin and wait is identical on every machine.

- **The preamble.** `scripts/check-run.sh` starts with `environment:` lines: macOS version and build,
  model, CPUs, memory, load, Xcode, and every real screen (frame, visible frame, scale, pixels, color
  space). The fixture displays are fake; the real screens are only where their panels sit. When a check
  fails the run prints the app's `snapit:` log (why each overlay and countdown ended).
- **Product behaviour.** The overlay and a Timed Capture's countdown end on a change of displays, and
  only on one: they compare each display's ID, frame and scale with the ones they started under, never
  the visible frame (`DisplayConfiguration`). The checks `overlay-screens-noise` makes (flows 40 and 43)
  say a notification with the same displays does nothing.
- A check that waits for something the system does late (the memory of a frozen frame coming back while a
  countdown runs) polls for a few seconds rather than looking once.

## Engine tests

`engine/tests/*.rs` call the C-ABI functions directly (`pixelate.rs`: the averaged-block pixelate, with its
own independent block-mean reference, non-tight strides, edge blocks, windows, invalid and overlapping buffers). `engine/tests/support/mod.rs` has the fixture
builder (any stride, padding filled with garbage that must never reach the output) and a PNG chunk
reader that does not use the encoder under test. A new engine function gets a test file with:
a round trip, a non-tight stride, invalid arguments (null pointers, zero sizes, overflow) and its
metadata. `engine/tests/png_alpha.rs` is the model for transparent pixels (premultiplied input, straight RGBA out,
the opaque case staying RGB, averaging, the thumbnail). After changing the C interface run `scripts/generate-header.sh` and commit the header.

## Never in a test

Touch the real clipboard, `~/Downloads`, the real cache folder or the bundle ID's `UserDefaults`
domain; register a real hot key; trigger a Screen Recording prompt; run the real `tccutil` or read the real TCC database. The paths the scripted run does
not exercise are the real ScreenCaptureKit Capture, real hot keys, and the real Screen Recording
permission and its prompt; they run only in a real install.
