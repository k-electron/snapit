import Foundation

/// A Window Capture: the overlay highlights the window under the pointer, a click captures exactly
/// that window through a single-window content filter, and the Capture opens in the Editor. No
/// Action bar: picking a window is the whole Area.
///
/// The overlay, its frozen frames, the gate, the Editor helper's warm-up and the hand-off to the
/// Editor are the Area Capture's (`AreaCaptureFlow`, started in `.window` mode); this file is the
/// part that is a window's alone, the capture itself.
@MainActor
enum WindowCaptureFlow {
    /// The Shortcut and the "Capture Window" menu item both call this; it returns as soon as the
    /// overlay is up.
    @discardableResult
    static func start() async -> AreaCaptureFlow.StartOutcome {
        await AreaCaptureFlow.start(mode: .window)
    }

    /// Captures `window` alone and opens the Editor on it.
    static func capture(_ window: OnScreenWindow) async -> AreaCaptureFlow.Result {
        do {
            // The clock starts before the screenshot, so the time to the Editor includes it.
            let clock = CaptureTiming.Clock()
            let screen = try await WindowCaptureSources.current.captureWindow(window)
            let number = try await CaptureHandoff.publish(screen)
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
            NSLog("snapit: Window Capture failed: \(error)")
            return .failed("\(error)")
        }
    }
}
