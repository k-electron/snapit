import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: Error, CustomStringConvertible {
    case noDisplay
    case noImage
    case windowGone

    var description: String {
        switch self {
        case .noDisplay: "no display under the pointer"
        case .windowGone: "the window is no longer on screen"
        case .noImage: "ScreenCaptureKit returned no SDR image"
        }
    }
}

/// The real Capture source: ScreenCaptureKit's one-shot capture, fetched only when asked
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
        return try await Self.capture(filter: Self.filter(for: display, in: content))
    }

    /// A filter for the whole `display`. snapit's own windows (a menu still fading out, later its
    /// overlay) never appear in a Capture. Its menu bar icon is a status item window, part of the
    /// screen, so it stays in.
    static func filter(for display: SCDisplay, in content: SCShareableContent) -> SCContentFilter {
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let ownWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == AppIdentity.mainBundleIdentifier
                && $0.windowLayer != statusLayer
        }
        return SCContentFilter(display: display, excludingWindows: ownWindows)
    }

    /// One-shot capture of what `filter` selects: native pixels, SDR, in the display's color space.
    /// `ignoresShadows` is nil for a display filter; a single-window filter passes whether the
    /// window's shadow is left out. The scale of a window Capture is the filter's, so a mismatch
    /// between the size asked for and the size delivered (a shadow squeezed in) shows in the log
    /// and does not skew the scale.
    static func capture(filter: SCContentFilter, ignoresShadows: Bool? = nil) async throws -> CapturedScreen {
        let requestedScale = Double(filter.pointPixelScale)
        let configuration = SCScreenshotConfiguration()
        // Native pixels: the content rect is in points.
        configuration.width = Int((filter.contentRect.width * requestedScale).rounded())
        configuration.height = Int((filter.contentRect.height * requestedScale).rounded())
        configuration.showsCursor = false
        if let ignoresShadows { configuration.ignoreShadows = ignoresShadows }
        configuration.dynamicRange = .sdr
        configuration.displayIntent = .local

        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        guard let image = output.sdrImage else { throw ScreenCaptureError.noImage }
        if ignoresShadows != nil {
            if image.width != configuration.width || image.height != configuration.height {
                NSLog(
                    "snapit: window image is \(image.width) x \(image.height), asked for \(configuration.width) x \(configuration.height)"
                )
            }
            return CapturedScreen(image: image, scale: requestedScale)
        }
        // The scale the Capture records is the one the pixels really have, whatever was asked for.
        let scale = filter.contentRect.width > 0 ? Double(image.width) / filter.contentRect.width : requestedScale
        return CapturedScreen(image: image, scale: scale)
    }
}
