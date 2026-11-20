import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

/// Test mode's Window Capture source: a fixture image of the window, with transparent rounded
/// corners, in place of ScreenCaptureKit's single-window capture.
///
/// The image is the size of the window in pixels (its frame in points times the first fake
/// display's scale), in that display's color space (sRGB at 1x, Display P3 at 2x), premultiplied
/// BGRA in IOSurface-backed memory like the real one. With `w` x `h` the size in pixels, `s` the
/// scale and `R = 8 * s` the corner radius in pixels, the pixel at `(x, y)` has
///
///     colour: the display fixture's colour at (x, y) for a w x h image, as `FixtureCaptureSource`
///             documents (R = x * 255 / (w - 1), G = y * 255 / (h - 1), B = 40 or 200 by 8 px checker)
///     alpha:  255, except in the four R x R corner squares. There, with
///             dx = 2x + 1 - 2R (left squares) or 2x + 1 - 2(w - R) (right squares), and dy likewise,
///             d2 = dx * dx + dy * dy:
///                 d2 <= (2R - 2)^2  -> 255
///                 d2 >= (2R + 2)^2  -> 0
///                 otherwise         -> 128
///     stored: each colour channel c premultiplied as (c * alpha + 127) / 255 (integer division).
///
/// `scripts/run/png-inspect.swift` recomputes the same pixels (`verify-window`).
@MainActor
final class FixtureWindowCaptureSource: WindowCaptureSource {
    static let shared = FixtureWindowCaptureSource()

    /// When true the Capture fails, as if the window had closed since it was picked
    /// (`fixture-window-fail`).
    var fails = false

    func prepare() {}
    func release() {}

    func captureWindow(_ window: OnScreenWindow) async throws -> CapturedScreen {
        if fails { throw ScreenCaptureError.windowGone }
        let display = FixtureCaptureSource.shared.display
        let scale = display.scale
        let size = FixtureCaptureSource.Display(
            scale: scale, pointWidth: Int(window.frame.width), pointHeight: Int(window.frame.height))
        return CapturedScreen(image: try Self.makeImage(size), scale: Double(scale))
    }

    /// The corner radius in points.
    static let cornerRadius = 8

    /// The alpha of pixel `(x, y)` of a `width` x `height` window image at `scale` (see the type's
    /// description).
    static func alpha(x: Int, y: Int, width: Int, height: Int, scale: Int) -> UInt8 {
        let radius = cornerRadius * scale
        func offset(_ v: Int, _ extent: Int) -> Int? {
            if v < radius { return 2 * v + 1 - 2 * radius }
            if v >= extent - radius { return 2 * v + 1 - 2 * (extent - radius) }
            return nil
        }
        guard let dx = offset(x, width), let dy = offset(y, height) else { return 255 }
        let distance = dx * dx + dy * dy
        if distance <= (2 * radius - 2) * (2 * radius - 2) { return 255 }
        if distance >= (2 * radius + 2) * (2 * radius + 2) { return 0 }
        return 128
    }

    /// The window image for `display`'s size (in points) and scale.
    static func makeImage(_ display: FixtureCaptureSource.Display) throws -> CGImage {
        let width = display.pointWidth * display.scale
        let height = display.pointHeight * display.scale
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferBytesPerRowAlignmentKey: 64,
        ]
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
            let buffer
        else { throw ScreenCaptureError.noImage }

        CVPixelBufferLockBaseAddress(buffer, [])
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            throw ScreenCaptureError.noImage
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        for y in 0..<height {
            let green = y * 255 / max(height - 1, 1)
            let row = pixels + y * bytesPerRow
            for x in 0..<width {
                let blue = (x / 8 + y / 8) % 2 == 0 ? 40 : 200
                let red = x * 255 / max(width - 1, 1)
                let alpha = Int(alpha(x: x, y: y, width: width, height: height, scale: display.scale))
                let at = row + x * 4
                at[0] = UInt8((blue * alpha + 127) / 255)
                at[1] = UInt8((green * alpha + 127) / 255)
                at[2] = UInt8((red * alpha + 127) / 255)
                at[3] = UInt8(alpha)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, display.colorSpace, .shouldPropagate)

        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == noErr, let image else {
            throw ScreenCaptureError.noImage
        }
        return image
    }
}
