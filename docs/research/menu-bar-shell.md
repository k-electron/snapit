# Menu bar shell: zero idle CPU, low memory

Research for [#4](https://github.com/k-electron/snapit/issues/4), part of the v1 map [#1](https://github.com/k-electron/snapit/issues/1).

**Question.** What is the leanest way to build snapit's always-running shell on macOS 26+? Specifically: SwiftUI `MenuBarExtra` vs AppKit `NSStatusItem` for idle memory and CPU; global Shortcuts that don't need Accessibility permission (Carbon `RegisterEventHotKey` vs libraries such as KeyboardShortcuts), including a user-configurable recording UI; launch at login via `SMAppService`; and how to keep Editor and overlay windows from holding memory after they close.

**Sources.** Apple's SDK headers (read locally from the macOS 27.2 SDK shipped with Command Line Tools, Swift 6.4.2), Apple developer documentation, Apple's Energy Efficiency Guide, Apple DTS posts on the developer forums, and library source code at tagged releases. Where a statement is about measured CPU or memory, it says whether it is **sourced** or **measured here** (see [Measurements](#measurements)).

## Recommendation

Build the shell as an **`LSUIElement` agent app whose status item is an AppKit `NSStatusItem` with an `NSMenu`**. Use SwiftUI for every view (Settings, Onboarding, Editor, overlays), hosted in AppKit-owned windows created on demand and released on close. Specifically:

1. **Status item: `NSStatusItem`, not `MenuBarExtra`.** Both idle at **0.0% CPU with no idle wakeups** (measured here). `NSStatusItem` was also the lightest (11 MB vs 15 MB footprint, measured here). The deciding factor is control: `MenuBarExtra` has no public API to open its menu, reach its `NSStatusItem`, or change its presentation programmatically (SDK interface, macOS 27.2).
2. **Global Shortcuts: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 3.x** (MIT, no dependencies). It wraps Carbon `RegisterEventHotKey`, which needs **no Accessibility permission**, is event-driven, and is not deprecated in the macOS 27.2 SDK. It also ships the SwiftUI recorder UI, system-conflict detection and menu-open handling snapit would otherwise have to write.
3. **Launch at login: `SMAppService.mainApp`**, opt-in from Onboarding and Settings, with `status` read when Settings opens (no polling). Verify it on the ad-hoc-signed DMG build before relying on it (Open questions).
4. **Windows and memory**: own each Editor or overlay window in exactly one place, set `isReleasedWhenClosed = false`, and drop every strong reference on close. Allocate full-resolution Capture buffers (in the Rust engine) with **anonymous `mmap`, not `malloc`/`Vec`**. In the measurements here, a freed 56 MiB `malloc` block stayed in the app's footprint after the Editor closed, while an `mmap`'d one returned at once (73 MB → 17 MB).
5. **Idle discipline**: no timers, polling, or background loops at rest. Everything the shell waits on (status item click, hot key, Settings open) is an event.

## 1. Status item: `MenuBarExtra` vs `NSStatusItem`

### What each API offers

- **`MenuBarExtra`** is a SwiftUI `Scene`, available since macOS 13 ([SwiftUI interface in the macOS SDK](#sdk-paths): `@available(macOS 13.0, *) public struct MenuBarExtra<Label, Content> : SwiftUI.Scene`). Its public surface is two initializer families (with and without `isInserted:`) plus `.menuBarExtraStyle(.menu | .window | .automatic)` ([Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [Apple: menuBarExtraStyle(_:)](https://developer.apple.com/documentation/swiftui/scene/menubarextrastyle(_:))).
  - Apple's docs: "An app that only shows in the menu bar will be automatically terminated if the user removes the extra from the menu bar", and menu bar–only apps should set `LSUIElement` to hide from the Dock and app switcher ([Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)).
  - There is **no public API** to open or close the menu programmatically, to read the underlying `NSStatusItem`, or to reach the popup window. The SDK interface exposes nothing beyond the initializers and style ([SDK interface](#sdk-paths)). The maintained third-party workaround says the same: "`MenuBarExtra` lacks 1st-party API to get or set the menu presentation state, disable the menubar extra, access the `NSStatusItem`, or access the popup's `NSWindow`. (Still as of Xcode 26)" ([MenuBarExtraAccess README](https://github.com/orchetect/MenuBarExtraAccess#why)). That package also lists known issues with its `isPresented` binding in the `.menu` style ([same README, Known Issues](https://github.com/orchetect/MenuBarExtraAccess#known-issues)).
- **`NSStatusItem`** is created with `NSStatusBar.system.statusItem(withLength:)`. "The receiver does not retain a reference to the status item, so you need to retain it" ([Apple: statusItem(withLength:)](https://developer.apple.com/documentation/appkit/nsstatusbar/statusitem(withlength:))). It exposes `button` (image, target/action, tooltip), `menu`, `behavior` (`.removalAllowed`, `.terminationOnRemoval`), `isVisible` and `autosaveName` (`NSStatusItem.h` in the [macOS SDK](#sdk-paths)). The button is a normal `NSControl`, so snapit can, for example, open the menu on click and run a Capture on a modified click if that is ever wanted.
  - macOS 27 adds `expandedInterfaceDelegate` / `NSStatusItemExpandedInterfaceSession` for status items that show their own window instead of a menu. It is marked `API_AVAILABLE(macos(27.0))` in `NSStatusItem.h`, so a macOS 26 baseline can't depend on it. snapit's menu is a plain `NSMenu` anyway, which the header says is "handled automatically".

### Idle cost

Neither API does periodic work when idle. **Measured here** (method below), a minimal `LSUIElement` app with one menu bar icon, a three-item menu and one Carbon hot key:

| Variant | Footprint after 30 s | CPU over 60 s idle | CPU time accrued in 60 s | New idle wakeups in 60 s |
|---|---|---|---|---|
| A: SwiftUI `MenuBarExtra` (`.menu` style) | 15 MB | 0.0% | 0.00 s | 0 |
| B: AppKit `NSStatusItem` + `NSMenu` | **11 MB** | 0.0% | 0.00 s | 1 (in the first 10 s, then 0) |
| C: SwiftUI `App` + `Settings` scene + AppKit `NSStatusItem` | 16 MB | 0.0% | 0.00 s | 0 |

(Measured on macOS 27.2.1, not 26. See [Measurements](#measurements) for method and raw output.)

The difference between the variants is small: a few MB of footprint, with SwiftUI's scene machinery loaded in A and C. None of them showed any idle CPU or idle wakeups. So the choice between `MenuBarExtra` and `NSStatusItem` should rest on **control**, not on idle cost.

### Why `NSStatusItem` for snapit

snapit's shell has to coordinate things the menu can't: Shortcuts fire Captures while the menu is closed, the overlay must cover every screen, the Editor opens straight after a Capture, and the icon may need to change state (for example, while a Capture is in progress). `NSStatusItem` exposes all of that through public API. `MenuBarExtra` would need a third-party introspection package to reach the same objects. Keep SwiftUI for the views themselves: the menu content can stay a plain `NSMenu`, and Settings, Onboarding and the Editor are SwiftUI views hosted in AppKit windows (section 5).

The SwiftUI `App` lifecycle can still be the entry point. `@NSApplicationDelegateAdaptor` plus a `Settings { … }` scene (variant C below) runs as an `LSUIElement` agent and keeps a SwiftUI-native Settings window. Apple's `openSettings` environment action opens it from SwiftUI views ([Apple: openSettings](https://developer.apple.com/documentation/swiftui/environmentvalues/opensettings)). But `openSettings` is only reachable from inside a SwiftUI view hierarchy, and snapit's menu is AppKit. Hosting Settings in snapit's own `NSWindow` with `NSHostingController` avoids that seam entirely, which is what variant B models.

### Agent app setup

- Set `LSUIElement = YES` in `Info.plist`: "an agent app that runs in the background and doesn't appear in the Dock" ([Apple: LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)). This is the same as `NSApplication.ActivationPolicy.accessory`, which "corresponds to value of the `LSUIElement` key … being `1`" ([Apple: accessory](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory)).
- Set `behavior` deliberately. Apple's header says that if `.removalAllowed` is set, "It is the application's responsibility to allow the user to re-add the item." With a single icon and no Dock presence, leaving removal **off** (the default: "By default, an item is not removable") avoids an app with no visible surface. A ⌘-drag removal would otherwise leave Settings unreachable (`NSStatusItem.h`, [SDK](#sdk-paths)).

## 2. Keeping idle CPU at zero

- Apple's guidance: "Some apps use timers to monitor for key presses, mouse locations, changes to file contents, network availability, and other state changes. Timers prevent the CPU from going to or staying in the idle state … Instead of using timers to watch for events, use a more efficient service" ([Energy Efficiency Guide: Minimize Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)).
- App Nap throttles timers and lowers priority for background apps, but Apple warns: "Don't rely on App Nap to get your app to fully idle" ([Energy Efficiency Guide: Extend App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)). An agent app with no visible window is a natural App Nap candidate, but the 0% target has to come from the design itself.
- Everything snapit needs at rest is push-based: the status item (AppKit event), Carbon hot keys (a `kEventHotKeyPressed` Carbon event delivered to an installed handler, `CarbonEvents.h`), `SMAppService.status` (read on demand), and `UserDefaults`. Nothing needs a timer, poll, `CADisplayLink`, file watcher, or `Task.sleep` loop while idle.
- Rules for the codebase:
  1. No repeating `Timer`, `DispatchSourceTimer`, or `Task { while … sleep }` loops outside an active Capture or Editor session.
  2. Read `SMAppService.mainApp.status` when the Settings window appears or becomes key, not on a schedule (section 4).
  3. Create Capture-time machinery (ScreenCaptureKit streams, overlays, mouse-moved tracking) per Capture and tear it down afterwards.
  4. The Rust engine is called synchronously or on demand. It owns no background threads while idle (or parks them on a blocking wait, never a spin or sleep loop).
  5. "Check for Updates" runs only when the user picks it (per #1), so there is no periodic network wake-up.
- Verify in CI or manual QA with `top -stats pid,cpu,idlew` (idle wakeups) and Activity Monitor's Energy tab, following [Measurements](#measurements).

## 3. Global Shortcuts without Accessibility permission

### The OS mechanisms

| Mechanism | Global key events? | Permission | Source |
|---|---|---|---|
| Carbon `RegisterEventHotKey` | Yes, only the registered combo | None | `CarbonEvents.h` ([SDK](#sdk-paths)); KeyboardShortcuts FAQ "Does this package cause any permission dialogs? No." ([README](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/readme.md#faq)) |
| `NSEvent.addGlobalMonitorForEvents` | Copies only, can't consume | "Key-related events may only be monitored if accessibility is enabled or if your application is trusted for accessibility access" | [Apple](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)) |
| `CGEvent.tapCreate` | Yes | Key events only if root or "Access for assistive devices is enabled" | [Apple](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) |
| `NSEvent.addLocalMonitorForEvents` | No, own app only | None | [Apple](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)) |

**`RegisterEventHotKey` is the only permission-free way to get global Shortcuts.** Facts from the macOS 27.2 SDK header (`HIToolbox.framework/Headers/CarbonEvents.h`):

- It is **not deprecated**. It is still declared `AVAILABLE_MAC_OS_X_VERSION_10_0_AND_LATER` with no deprecation attribute, unlike several neighbouring Carbon symbols that are explicitly marked deprecated in the same header.
- Hot keys are non-exclusive by default ("notification events are sent to all registrants for that hotkey"). Passing `kEventHotKeyExclusive` claims the combo, and `eventHotKeyExistsErr` is returned if another process already holds it exclusively.
- "You do not need to unregister a hot key when your application terminates". Unregister and re-register when the user changes a Shortcut.
- It is "Not thread safe", so call it on the main thread.

### Library vs hand-rolled

**KeyboardShortcuts** ([sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), MIT, about 2.7k stars, latest release [3.1.0, 2026-09-11](https://github.com/sindresorhus/KeyboardShortcuts/releases/tag/3.1.0), Swift 6, **no transitive dependencies** ([Package.swift @ 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/Package.swift))):

- Registration is plain Carbon: `RegisterEventHotKey(..., GetEventDispatcherTarget(), 0, &eventHotKey)` with an `InstallEventHandler` for `kEventHotKeyPressed`/`Released` ([HotKey.swift @ 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/Sources/KeyboardShortcuts/HotKey.swift)). It is event-driven, with no timers in the hot path.
- It handles menu-open edge cases that a hand-rolled version would rediscover. It observes `NSMenu.didBeginTrackingNotification` and switches to run-loop-local key monitors while a menu is tracking, so Shortcuts still fire with snapit's menu open. The README feature list says "Works when `NSMenu` is open (e.g. menu bar apps)" ([README](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/readme.md#faq)), and 3.1.0 fixed function-key Shortcuts while a menu is open ([release notes](https://github.com/sindresorhus/KeyboardShortcuts/releases/tag/3.1.0)).
- **Recording UI**: `KeyboardShortcuts.Recorder` (SwiftUI) and `RecorderCocoa` (AppKit). Recording uses a local event monitor (`LocalEventMonitor(events: [.keyDown, .leftMouseUp, .rightMouseUp])` in [RecorderCocoa.swift](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/Sources/KeyboardShortcuts/RecorderCocoa.swift)), so it needs no permission. It rejects Shift-only combos, warns when a combo "is already used by the system or the app's main menu" ([README](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/readme.md)), and exposes `Shortcut.isTakenBySystem`, which checks enabled system Shortcuts via `CopySymbolicHotKeys` ([Shortcut.swift @ 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/Sources/KeyboardShortcuts/Shortcut.swift)). That is directly useful for #9, avoiding ⌘⇧3/4/5.
- Shortcuts persist in `UserDefaults` by default. Initial (default) Shortcuts are declared as `Name("…", initial: .init(.k, modifiers: [...]))` (renamed from `default:` in [3.0.0](https://github.com/sindresorhus/KeyboardShortcuts/releases/tag/3.0.0)).
- The Option-only restriction you may read about applies only to **sandboxed** apps on macOS 15.0–15.1. The library's own check returns `false` unless `majorVersion == 15`, `minorVersion` is 0 or 1, and the app is sandboxed ([Shortcut.swift `isDisallowed` @ 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts/blob/3.1.0/Sources/KeyboardShortcuts/Shortcut.swift)). It doesn't affect snapit on macOS 26+.
- Release 3.1.0 already includes a "macOS 27 compatibility" fix (recorder layout) ([commit df7b7ce](https://github.com/sindresorhus/KeyboardShortcuts/commit/df7b7ce53a2cfa4434513411f24972dd5ae0b50d)), a sign of active maintenance.

Alternatives considered:

- [soffes/HotKey](https://github.com/soffes/HotKey): MIT, a Carbon wrapper with **no recording UI**. Last release v0.2.1, 2024-12-29.
- [MASShortcut](https://github.com/cocoabits/MASShortcut): BSD-2, **archived** on GitHub. Rule it out.
- Hand-rolled Carbon: about 100 lines for registration, but the recorder UI, system-conflict detection, key-symbol rendering, localisation and menu-open handling are the bulk of KeyboardShortcuts' code (`HotKey.swift`, `KeyboardShortcuts.swift` and `RecorderCocoa.swift` alone are over 2,100 lines at 3.1.0). That isn't worth re-implementing.

**Idle cost of a registered hot key (measured here):** none. Every benchmark variant had one Carbon hot key registered, and none accrued CPU time or idle wakeups over 60 s (see [Measurements](#measurements)). The library's extra cost is its observers for menu tracking notifications, which are also push-based. It was not measured separately here.

## 4. Launch at login with `SMAppService`

- Use `SMAppService.mainApp` ("An app service object that corresponds to the main application as a login item … Use this to configure the main app to launch at login", [Apple](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)), available since macOS 13. No helper bundle is needed.
- `register()`: "If the service corresponds to the main application, the application launches on subsequent logins." Possible errors include `kSMErrorAlreadyRegistered`, `kSMErrorLaunchDeniedByUser` and, per the header, `kSMErrorInvalidSignature` "If the app bundle is not properly code signed" ([Apple: register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register()); `SMAppService.h` in the [SDK](#sdk-paths)).
- `status` returns `.notRegistered`, `.enabled`, `.requiresApproval` or `.notFound`. `.requiresApproval` "will be returned if the user revokes consent for the service to run in System Settings". `SMAppService.openSystemSettingsLoginItems()` deep-links to the panel (`SMAppService.h`).
- The header says "Apps that use SMAppService APIs must be code signed". An ad-hoc signature is a code signature: on Apple Silicon "any executable must be signed before it's allowed to run … a simple ad-hoc signature is sufficient", but such binaries "cannot pass through Gatekeeper" ([Apple: macOS Big Sur 11.0.1 Universal Apps release notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes)). No Apple document says whether ad-hoc is enough for `mainApp`. Apple DTS has said ad-hoc ("Sign to Run Locally") signing causes problems for **embedded helpers** ([Apple Developer Forums](https://developer.apple.com/forums/thread/727785)). The `mainApp` path has no helper, but **this needs a hands-on check** (see Open questions).
- System Settings shows two different lists. DTS (Quinn): "Open at Login shows a list of login items … Allow in the Background has different semantics. This is an allowlist. It doesn't show what programs *will* be launched at login, it shows what programs are *allowed* to be launched" ([Apple Developer Forums 713830](https://developer.apple.com/forums/thread/713830)). The same thread recommends testing login items on a clean user account, because stale registrations confuse results.
- **App translocation**: an un-notarized, quarantined app launched from where it was downloaded may run from a randomized path. Moving it to `/Applications` with Finder clears this ([Apple DTS: App Translocation Notes](https://developer.apple.com/forums/thread/724969)). Onboarding should get snapit into `/Applications` (the DMG layout handles this) before offering "Launch at login".
- Idle cost: none. `SMAppService` is a one-off call, and the toggle in Settings should read `status` when the Settings window appears (the user can flip it in System Settings at any time) rather than poll.
- Ask for consent instead of silently registering on first launch. Offer the toggle in Onboarding and Settings.

## 5. Editor and overlay windows must not hold memory after closing

### Facts

- `NSWindow.isReleasedWhenClosed`: "The default for `NSWindow` is `true`; the default for `NSPanel` is `false`. Release when closed, however, is ignored for windows owned by window controllers. Swift and Automatic Reference Counting (ARC) clients need to set this property to `false` to avoid releasing the window too many times" ([Apple](https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed)).
- So in Swift, **closing a window frees nothing by itself**. Memory is freed only when the last strong reference to the window (and to its content view and controller) goes away.
- SwiftUI `Window`/`WindowGroup` scenes: `openWindow` brings an existing window forward if it is already open, and `restorationBehavior(.disabled)` / `defaultLaunchBehavior(.suppressed)` control restoring and showing it at launch ([Apple: Window](https://developer.apple.com/documentation/swiftui/window), [restorationBehavior](https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:)), [defaultLaunchBehavior](https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:))). Apple doesn't document when a closed scene's view state and backing are torn down. snapit's overlays need borderless, screen-level, per-display windows anyway, which is AppKit territory.

### Measured here

Variant B. An "Editor" `NSWindow` hosts a SwiftUI view through `NSHostingView`. The view owns an `EditorSession` that holds a full-resolution 5120×2880×4-byte working buffer (56 MiB, random so the memory compressor can't shrink it), standing in for the engine's Capture buffer. Footprint is `phys_footprint` from `footprint <pid>`. Baseline before any window: **12 MB**.

| Step | Buffer from `malloc` | Buffer from anonymous `mmap` |
|---|---|---|
| Editor open (settled 5 s) | 73 MB | 73 MB |
| Close, drop all references (session `deinit` confirmed), +10 s | **73 MB** | **17 MB** |
| …then `malloc_zone_pressure_relief(nil, 0)` | 73 MB (reports 0 bytes freed) | 17 MB |
| Reopen (settled 5 s) | 88 MB | 73 MB |
| Close but **keep a strong reference** to the `NSWindow` | 88 MB (held) | 73 MB (held) |
| Then drop that reference (session `deinit` confirmed) | 88 MB | **17 MB** |

What this shows (measured here, macOS 27.2.1):

- **Closing a window without releasing it holds everything it references.** This is the anti-pattern to avoid, and it is the default outcome in Swift because `isReleasedWhenClosed` must be `false` under ARC.
- **Releasing the window graph does free the session**, but a large `malloc` block freed on the main heap **stayed in the process footprint**. The allocator kept it for reuse: the second open grew only 15 MB instead of 56 MB. In one earlier run, the second free did hand about 57 MB back, so the timing is not deterministic. Either way, Activity Monitor would show the memory as still in use after the Editor closes.
- **`mmap`/`munmap` returns memory immediately and every time.** Footprint fell to 17 MB, about 5 MB above the pre-window baseline. That remainder is a one-time AppKit/SwiftUI/Core Animation cost of having shown a window, and it did not grow on the second cycle.
- Separately, AppKit/SwiftUI dropped the source `NSImage`'s 56 MiB backing once the window had drawn (footprint peaked at about 127 MB during open and settled at 73 MB). The large cost to manage is the **app's own** full-resolution buffers, not the view's.

Rust implication: Rust `staticlib`/`cdylib` libraries "are guaranteed to use the `System` [allocator] by default" ([Rust std::alloc](https://doc.rust-lang.org/std/alloc/index.html)), and `System` "is based on `malloc` on Unix platforms" ([Rust std::alloc::System](https://doc.rust-lang.org/std/alloc/struct.System.html)). A Capture held in a `Vec<u8>` inside the engine would therefore behave like the `malloc` column. Full-frame buffers should be allocated with anonymous `mmap`, either directly through `libc` or via [`memmap2::MmapMut::map_anon`](https://docs.rs/memmap2/0.9.12/memmap2/struct.MmapMut.html) (memmap2 0.9.12, MIT/Apache-2.0, actively maintained, [repo](https://github.com/RazrFalcon/memmap2-rs)). Small allocations can stay on the default allocator.

### Pattern for snapit

1. **Editor**: one `NSWindow` (or `NSWindowController`) per Editor session, created after a Capture with `NSHostingController(rootView: EditorView(session:))`. Set `isReleasedWhenClosed = false`. In `windowWillClose`, the owner (a small `EditorCoordinator`) drops its reference to the window, controller and session, and the session drops its Rust engine handle. Nothing else (closures, `NotificationCenter` observers, Combine sinks, `@Observable` singletons) may hold the session strongly, so use `[weak self]` in long-lived closures.
2. **Overlays** (Area/Window selection, Color picker): one borderless `NSPanel` per screen, created when the Capture mode starts and released when it ends, never just hidden with `orderOut`. Release the frozen screen image the overlay shows with it.
3. **Rust engine**: the Capture's pixel buffers live in Rust, owned by an opaque handle that Swift frees exactly once (for example `deinit { engine_session_free(ptr) }`). Allocate full-frame buffers with anonymous `mmap` so freeing them returns the pages to the OS at once (measured above). Avoid keeping a long-lived "last Capture" cache.
4. **Verify** in every Editor-related PR: footprint after closing the Editor returns to within a few MB of the pre-Capture baseline (`footprint <pid>` or Xcode's Memory Graph, which also shows leaked `NSWindow`/`NSHostingView` instances).

## Measurements

**Environment:** Apple Silicon Mac, macOS 27.2.1 (build 26B131), Swift 6.4.2, `-O`, deployment target `arm64-apple-macos26.0`, each app ad-hoc signed (`codesign -s -`), `LSUIElement = YES`. All three variants register one Carbon hot key (⌃⌥⌘9) through `RegisterEventHotKey`. **These numbers come from macOS 27.2, not 26. Re-run on macOS 26 before quoting them as v1 targets.**

- **A, MenuBarExtra**: SwiftUI `App` with `MenuBarExtra(...).menuBarExtraStyle(.menu)` and four buttons.
- **B, AppKit**: `@main` enum calling `NSApplication.run()`, `NSStatusItem` with an `NSMenu` of four items.
- **C, Hybrid**: SwiftUI `App` with `@NSApplicationDelegateAdaptor`, an empty `Settings` scene, and the same `NSStatusItem`/`NSMenu` as B.

**Idle method:** launch with `open -g`, wait 30 s, then record `footprint <pid>` (`phys_footprint`, the figure Activity Monitor's "Memory" column is based on), then 60 s of `top -l 7 -s 10 -stats pid,cpu,idlew,mem` (`idlew` is the process's cumulative idle-wakeup count, so a constant value means no new wakeups) and the process's cumulative CPU time from `ps -o cputime=` before and after.

**Window method:** variant B launched directly. Steps are triggered from the shell with distributed notifications (benchmark harness only), and footprint is read both in-process (`task_info(TASK_VM_INFO).phys_footprint`) and externally (`footprint <pid>`). The Editor window is an `NSWindow` (`isReleasedWhenClosed = false`) whose `contentView` is an `NSHostingView` of a SwiftUI view. That view holds an `EditorSession` object with a 5120×2880 `NSImage` and a 56 MiB working buffer filled with `arc4random_buf`. "Close + release" means `window.close(); window.contentView = nil; window = nil`. "Close but keep" means `window.close()` only. The buffer is allocated with `malloc`/`free` or, with `BENCH_MMAP=1`, `mmap(MAP_PRIVATE|MAP_ANON)`/`munmap`.

Raw idle output (`top` columns: pid, %CPU, cumulative idle wakeups, memory):

```text
variant=A_MenuBarExtra  settled: phys_footprint 15 MB
52006  0.0  5  15M   (x7 samples, 10 s apart, idlew constant at 5)
cumulative cputime before=0:00.12 after=0:00.12

variant=B_AppKit        settled: phys_footprint 11 MB
53693  0.0  2  11M
53693  0.0  3+ 11M   (then constant at 3 for the remaining 5 samples)
cumulative cputime before=0:00.12 after=0:00.12

variant=C_Hybrid        settled: phys_footprint 16 MB
83292  0.0  0  16M   (x7 samples, idlew constant at 0)
cumulative cputime before=0:00.12 after=0:00.12
```

After the window tests, each variant was idled for another 30 s: CPU time again accrued 0.00 s and idle wakeups stayed constant. Opening a window does not leave anything ticking.

Benchmark source (the parts that matter):

```swift
// Carbon hot key used by every variant (no Accessibility prompt was shown; status=0).
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in noErr }, 1, &spec, nil, nil)
let id = EventHotKeyID(signature: OSType(0x534e4150), id: 1)
RegisterEventHotKey(UInt32(kVK_ANSI_9), UInt32(cmdKey | optionKey | controlKey), id,
                    GetEventDispatcherTarget(), 0, &ref)

// Variant B status item.
item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "…")
item.menu = menu  // NSMenu with 4 items

// Editor session used in the window test.
@MainActor final class EditorSession {
    let image: NSImage
    let count = 5120 * 2880 * 4
    nonisolated(unsafe) let pixels: UnsafeMutableRawPointer
    init(image: NSImage) {
        self.image = image
        pixels = useMmap ? mmap(nil, count, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)!
                         : malloc(count)!
        arc4random_buf(pixels, count)
    }
    deinit { if useMmap { munmap(pixels, count) } else { free(pixels) } }
}
```

## Open questions

1. **Does `SMAppService.mainApp` work reliably for an ad-hoc-signed, un-notarized app, and does registration survive an update?** The header only says apps "must be code signed". An ad-hoc signature's designated requirement is the binary's hash (`codesign -d -r-` on the benchmark app prints `designated => cdhash H"5ab2…"`), so each release is a different code identity. Needs a hands-on test on a clean user account: register, reboot, install the next build over it, reboot, and check System Settings › General › Login Items for a duplicate or stale entry. It wasn't run here, to avoid changing this machine's login items. If it fails, the fallbacks are documenting a manual "add to Login Items" step or dropping launch at login from v1.
2. **Re-measure on macOS 26.** All numbers here are from macOS 27.2.1. The conclusions (zero idle CPU, `NSStatusItem` lightest, `mmap` buffers return memory immediately) are unlikely to flip, but the absolute MB figures should be re-taken on 26 before anyone treats them as targets.
3. **Overlay memory per screen.** Not measured: the cost of one borderless `NSPanel` per display holding a frozen full-resolution screen image during Area selection. Measure it in the Capture prototype, and make sure the frozen image is released (and `mmap`/IOSurface-backed) when the overlay closes.
4. **Settings window hosting.** Hosting Settings in snapit's own `NSWindow` (variant B) or using SwiftUI's `Settings` scene with `openSettings` (variant C, +5 MB at idle) is a small call for the Settings/Onboarding ticket. This document leans B for consistency with the AppKit-owned status menu.

## SDK paths

Header facts above were read from the Command Line Tools macOS 27.2 SDK (`xcrun --show-sdk-path` → `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`):

- `System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Headers/CarbonEvents.h` (`RegisterEventHotKey`, `UnregisterEventHotKey`, `kEventHotKeyExclusive`)
- `System/Library/Frameworks/AppKit.framework/Headers/NSStatusItem.h`, `NSStatusBar.h`, `NSWindow.h`
- `System/Library/Frameworks/ServiceManagement.framework/Headers/SMAppService.h`
- `System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface` (`MenuBarExtra`, `MenuBarExtraStyle`)

The same headers are summarised on the Apple documentation pages linked inline.
