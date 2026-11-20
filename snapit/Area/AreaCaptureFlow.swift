import AppKit

/// An Area Capture: freeze every display, let the user select on the frozen image, crop the
/// frozen frame in the engine, open the Editor.
///
/// The Shortcut and the "Capture Area" menu item both call `start()`, which returns as soon as
/// the overlay is up. What happens next is the user's: a drag released (or a click on the
/// highlighted window) takes the Capture, Esc cancels. The pixels go to the Editor helper through
/// a Capture file (`CaptureHandoff`); this process keeps nothing afterwards, and every frozen
/// frame is gone when the overlay closes.
@MainActor
enum AreaCaptureFlow {
    enum StartOutcome: Equatable {
        /// The overlay is showing.
        case overlayShown
        /// Screen Recording is not granted; macOS was asked to show its prompt.
        case permissionNeeded
        /// Another Capture is still running.
        case busy
        case failed(String)
    }

    enum Result: Equatable {
        /// Capture N is showing in the Editor.
        case opened(number: Int)
        case cancelled
        case failed(String)
    }

    private static var overlay: AreaOverlayController?
    private static var previousApp: NSRunningApplication?
    private static var result: Result?
    private static var waiters: [CheckedContinuation<Result, Never>] = []

    /// Milliseconds from the start of the last `start()` until its overlay was on screen.
    private(set) static var lastShownMilliseconds: Double?

    @discardableResult
    static func start() async -> StartOutcome {
        guard CaptureGate.enter() else { return .busy }
        let began = ContinuousClock.now
        guard ScreenRecordingPermission.current.isGranted else {
            ScreenRecordingPermission.current.request()
            CaptureGate.leave()
            return .permissionNeeded
        }
        result = nil
        do {
            // The window list is read now, before anything else can change it.
            let windows = OnScreenWindowSources.current.windowsFrontToBack()
            let previous = TestMode.isActive ? nil : NSWorkspace.shared.frontmostApplication
            let source = AreaCaptureSources.current
            let displays = try await source.freezeDisplays()
            guard !displays.isEmpty else { throw ScreenCaptureError.noDisplay }

            let controller = AreaOverlayController(displays: displays, windows: windows, pointer: source.pointerLocation)
            controller.onFinish = { selection in finish(selection) }
            overlay = controller
            previousApp = previous
            controller.show(takesFocus: !TestMode.isActive)
            lastShownMilliseconds = milliseconds(since: began)
            return .overlayShown
        } catch {
            NSLog("snapit: Area Capture failed: \(error)")
            CaptureGate.leave()
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

    private static func finish(_ selection: AreaSelection?) {
        guard let controller = overlay else { return }
        overlay = nil
        let frozen = selection.map { controller.displays[$0.displayIndex] }
        controller.teardown()

        guard let selection, let frozen else {
            // Cancelled: the Shortcut works again at once, and the app the user was in gets focus back.
            let previous = previousApp
            previousApp = nil
            previous?.activate()
            conclude(.cancelled)
            return
        }
        previousApp = nil
        Task {
            conclude(await capture(frozen, area: selection.pixels))
        }
    }

    /// Crops the frozen frame in the engine into a Capture file and opens the Editor on it.
    private static func capture(_ frozen: FrozenDisplay, area: PixelRect) async -> Result {
        do {
            let number = try await CaptureHandoff.publish(frozen.screen, cropping: area)
            do {
                try await EditorHelperLauncher.open(capture: number)
            } catch {
                CaptureHandoff.discard(number: number)
                throw error
            }
            CaptureHandoff.didOpen(number: number)
            return .opened(number: number)
        } catch {
            NSLog("snapit: Area Capture failed: \(error)")
            return .failed("\(error)")
        }
    }

    private static func conclude(_ outcome: Result) {
        result = outcome
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
