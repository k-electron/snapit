import ScreenCaptureKit

/// The real source of a Window Capture: `SCContentFilter(desktopIndependentWindow:)` captures
/// that window alone, even where other windows cover it. The list of shareable windows is fetched
/// once the overlay shows, while the user aims, and kept until the overlay is over.
@MainActor
final class ScreenCaptureKitWindowSource: WindowCaptureSource {
    private struct Content: @unchecked Sendable {
        let value: SCShareableContent
    }

    private var fetch: Task<Content, Error>?

    func prepare() {
        fetch = Task { @MainActor in
            Content(value: try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
        }
    }

    func release() {
        fetch?.cancel()
        fetch = nil
    }

    func captureWindow(_ window: OnScreenWindow) async throws -> CapturedScreen {
        let task = fetch ?? Task { @MainActor in
            Content(value: try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
        }
        let content = try await task.value.value
        guard let target = content.windows.first(where: { $0.windowID == window.id }) else {
            throw ScreenCaptureError.windowGone
        }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        return try await ScreenCaptureKitSource.capture(filter: filter, ignoresShadows: !WindowCapture.includesShadow)
    }
}
