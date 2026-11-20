import AppKit
import ScreenCaptureKit

/// The real fresh Capture: one ScreenCaptureKit screenshot of the display, taken now, with
/// snapit's own windows (the border, the badge, its tooltip) excluded by the content filter.
struct ScreenCaptureKitTimedSource: TimedCaptureSource {
    func captureFresh(_ request: FreshCaptureRequest, hideOwnWindows: @MainActor () -> Void) async throws
        -> CapturedScreen
    {
        var content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let wanted = Set(request.excluding.map { CGWindowID($0) })
        if !wanted.isSubset(of: Set(content.windows.map(\.windowID))) {
            // The system has not listed snapit's new windows, so a filter cannot name them: take
            // them off screen and give the compositor a moment, so they cannot be in the Capture.
            hideOwnWindows()
            try await Task.sleep(for: .milliseconds(200))
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
            throw ScreenCaptureError.noDisplay
        }
        // `filter(for:in:)` excludes every window of snapit's except its menu bar icon.
        return try await ScreenCaptureKitSource.capture(filter: ScreenCaptureKitSource.filter(for: display, in: content))
    }
}
