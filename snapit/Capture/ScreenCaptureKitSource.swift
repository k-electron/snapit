import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: Error, CustomStringConvertible {
    case noDisplay
    case noImage

    var description: String {
        switch self {
        case .noDisplay: "no display under the pointer"
        case .noImage: "ScreenCaptureKit returned no SDR image"
        }
    }
}

/// The real Capture source: ScreenCaptureKit's one-shot screenshot, fetched only when asked
/// (never a stream, nothing kept warm between Captures).
struct ScreenCaptureKitSource: CaptureSource {
    func captureDisplayUnderPointer() async throws -> CapturedScreen {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { throw ScreenCaptureError.noDisplay }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.noDisplay
        }
        // snapit's own windows (a menu that is still fading out) never appear in a Capture.
        let ownApplications = content.applications.filter {
            $0.bundleIdentifier == AppIdentity.mainBundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])

        let scale = Double(filter.pointPixelScale)
        let configuration = SCScreenshotConfiguration()
        // Native pixels: the content rect is in points.
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        configuration.displayIntent = .local

        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        guard let image = output.sdrImage else { throw ScreenCaptureError.noImage }
        return CapturedScreen(image: image, scale: scale)
    }
}
