import AppKit

/// An Area Capture: freeze every display, let the user select on the frozen image, crop the
/// frozen frame in the engine, open the Editor.
///
/// The Shortcut and the "Capture Area" menu item both call `start()`, which returns as soon as
/// the overlay is up. What happens next is the user's: with "After selecting an Area" at Capture on
/// release, a drag released (or a click on the highlighted window) takes the Capture; with Show
/// Action bar, the Area stays and the Action bar, Return or a double-click takes it. Esc
/// cancels. The pixels go to the Editor helper through a Capture file (`CaptureHandoff`); this
/// process keeps nothing afterwards, and every frozen frame is gone when the overlay closes.
///
/// The Color picker opens over the same frozen frames: from the Action bar, or straight away from
/// the menu item and its Shortcut through `start(mode: .pickColor)`. It ends with a hex on the
/// pasteboard and a toast. No Capture is taken, so no Editor is warmed up for a pick started from
/// the menu or the Shortcut.
@MainActor
enum AreaCaptureFlow {
    enum StartOutcome: Equatable {
        /// The overlay is showing.
        case overlayShown
        /// Screen Recording is not granted: nothing was captured and the Permission guide shows.
        case permissionNeeded
        /// Another Capture is still running.
        case busy
        /// A Timed Capture was counting down: the Shortcut cancelled it.
        case countdownCancelled
        case failed(String)
    }

    enum Result: Equatable {
        /// Capture N is showing in the Editor.
        case opened(number: Int)
        /// The Color picker copied this `#RRGGBB`.
        case pickedColor(String)
        case cancelled
        /// Screen Recording is not granted: nothing was captured and the Permission guide shows.
        case permissionNeeded
        case failed(String)
    }

    private static var overlay: AreaOverlayController?
    static var previousApp: NSRunningApplication?
    private static var result: Result?
    private static var waiters: [CheckedContinuation<Result, Never>] = []

    /// Milliseconds from the start of the last `start()` until its overlay was on screen.
    private(set) static var lastShownMilliseconds: Double?

    /// Shows the overlay for an Area Capture, for a Window Capture (`.window`: the same overlay, but it
    /// picks the window under the pointer and a click captures that window alone) or for the Color
    /// picker (`.pickColor`: the overlay opens in the picker).
    @discardableResult
    static func start(mode: AreaOverlayMode = .area) async -> StartOutcome {
        // The Area Shortcut (or menu item) while a Timed Capture counts down cancels it. Window
        // Capture and the Color picker do not: they meet the gate like a Screen Capture does.
        if mode == .area, countdown != nil {
            cancelTimedCapture()
            return .countdownCancelled
        }
        guard CaptureGate.enter() else { return .busy }
        let began = ContinuousClock.now
        result = nil
        previousApp = TestMode.isActive ? nil : NSWorkspace.shared.frontmostApplication
        guard ScreenRecordingPermission.current.isGranted else {
            conclude(.permissionNeeded)
            // After `conclude` has given the user's app its focus back, so the guide comes forward last.
            await OnboardingLauncher.screenRecordingMissing()
            return .permissionNeeded
        }
        // The Capture has started: the Editor helper warms up while the displays are frozen and
        // the user chooses an Area. Picking a color takes no Capture, so nothing warms up for it.
        if mode != .pickColor { EditorWarmUp.begin() }
        do {
            // The window list is read now, before anything else can change it.
            let windows = mode == .pickColor ? [] : OnScreenWindowSources.current.windowsFrontToBack()
            let source = AreaCaptureSources.current
            let displays = try await source.freezeDisplays()
            guard !displays.isEmpty else { throw ScreenCaptureError.noDisplay }

            let controller = AreaOverlayController(
                displays: displays, windows: windows, pointer: source.pointerLocation, mode: mode)
            controller.onFinish = { outcome in finish(outcome) }
            overlay = controller
            controller.show(takesFocus: !TestMode.isActive)
            if mode == .window { WindowCaptureSources.current.prepare() }
            lastShownMilliseconds = milliseconds(since: began)
            return .overlayShown
        } catch {
            NSLog("snapit: \(mode) Capture failed: \(error)")
            conclude(.failed("\(error)"))
            return .failed("\(error)")
        }
    }

    /// The overlay is up: waits until its Capture is in the Editor, or it is cancelled.
    static func waitForResult() async -> Result {
        if let result { return result }
        return await withCheckedContinuation { waiters.append($0) }
    }

    /// The overlay that is showing now, if any.
    static var activeOverlay: AreaOverlayController? { overlay }

    /// What the overlay's outcome sets going. Every outcome closes the overlay first, which lets go
    /// of the frozen frames; a new outcome adds its arm here.
    private static func finish(_ outcome: AreaOverlayOutcome) {
        guard let controller = overlay else { return }
        overlay = nil
        switch outcome {
        case .capture(let area):
            let frozen = controller.displays[area.displayIndex]
            controller.teardown()
            Task {
                conclude(await capture(frozen.screen, area: area.pixels))
            }
        case .timed(let area, let seconds):
            beginTimedCapture(from: controller, area: area, seconds: seconds)
        case .window(let window):
            controller.teardown()
            Task {
                conclude(await WindowCaptureFlow.capture(window))
            }
        case .cancel:
            controller.teardown()
            // Cancelled: the Shortcut works again at once.
            conclude(.cancelled)
        case .pickColor(let picked):
            let frame = controller.displays[picked.displayIndex].frame
            let scale = controller.displays[picked.displayIndex].scale
            picked.copyToPasteboard()
            controller.teardown()
            ColorToast.show("Copied \(picked.hex)", on: frame, scale: scale)
            conclude(.pickedColor(picked.hex))
        }
    }

    /// Crops `screen` (a frozen frame, or a Timed Capture's fresh one) in the engine into a Capture
    /// file and opens the Editor on it.
    static func capture(_ screen: CapturedScreen, area: PixelRect) async -> Result {
        do {
            let clock = CaptureTiming.Clock()
            let number = try await CaptureHandoff.publish(screen, cropping: area)
            do {
                try await EditorHelperLauncher.open(capture: number)
            } catch {
                CaptureHandoff.discard(number: number)
                throw error
            }
            clock.stop()
            CaptureHandoff.didOpen(number: number)
            return .opened(number: number)
        } catch {
            NSLog("snapit: Area Capture failed: \(error)")
            return .failed("\(error)")
        }
    }

    /// The one exit of every Area Capture: whatever happened, the gate opens, the waiters learn
    /// the outcome, and when no Editor opened the app the user was in gets focus back.
    static func conclude(_ outcome: Result) {
        result = outcome

        // Window Capture: lets go of the shareable-window list fetched while the overlay showed.
        WindowCaptureSources.current.release()

        let previous = previousApp
        previousApp = nil
        if case .opened = outcome {} else {
            // No Capture: the helper that was warming up for it goes, and the user's app comes back.
            EditorWarmUp.cancel()
            previous?.activate()
        }
        CaptureGate.leave()
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: outcome) }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }
}
