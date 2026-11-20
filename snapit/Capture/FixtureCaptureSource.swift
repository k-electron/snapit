import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

/// Test mode's Capture source: a deterministic image instead of the screen.
///
/// The scripted run chooses the fake display with the `fixture-display` command (see
/// `CaptureCommands.swift`): 1x is sRGB, 2x is Display P3, so a color space hard-coded
/// anywhere shows up as a failed check.
///
/// The image's pixel at `(x, y)` is, with `w` x `h` the size in pixels:
///
///     R = x * 255 / (w - 1)         (integer division)
///     G = y * 255 / (h - 1)
///     B = 40 if (x / 8 + y / 8) is even, else 200
///
/// `scripts/run/png-inspect.swift` and the engine tests recompute the same formula.
@MainActor
final class FixtureCaptureSource: CaptureSource {
    static let shared = FixtureCaptureSource()

    struct Display {
        var scale: Int
        var pointWidth: Int
        var pointHeight: Int

        var colorSpace: CGColorSpace {
            CGColorSpace(name: scale >= 2 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
        }
        var colorSpaceName: String { scale >= 2 ? "Display P3" : "sRGB" }
        /// The image's pixels are BGRX (alpha byte skipped and left 0) from a plain bitmap context
        /// instead of premultiplied BGRA, a layout the engine's in-place crop does not take, so
        /// the crop has to go through its fallback.
        var skipsAlpha = false
    }

    /// 1x, an odd width so every row of engine memory carries padding.
    var display = Display(scale: 1, pointWidth: 301, pointHeight: 187)

    /// How long a Capture takes, standing in for the time a user spends choosing an Area
    /// (`fixture-delay`).
    var delay = Duration.zero
    /// When true the Capture fails (`fixture-fail`).
    var fails = false

    func captureDisplayUnderPointer() async throws -> CapturedScreen {
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw ScreenCaptureError.noImage }
        let display = display
        return CapturedScreen(image: try Self.makeImage(display), scale: Double(display.scale))
    }

    /// The fixture image, in IOSurface-backed memory like a ScreenCaptureKit capture: Core
    /// Animation shows such an image without copying it, and the memory goes back the moment the
    /// last reference to the image does. Rows are aligned to 64 bytes, so they are padded unless
    /// the width happens to fit (the default 301 points never does).
    static func makeImage(_ display: Display) throws -> CGImage {
        let width = display.pointWidth * display.scale
        let height = display.pointHeight * display.scale
        if display.skipsAlpha { return try makeSkipFirstImage(display, width: width, height: height) }
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
            let green = UInt8(y * 255 / max(height - 1, 1))
            let row = pixels + y * bytesPerRow
            for x in 0..<width {
                let at = row + x * 4
                at[0] = (x / 8 + y / 8) % 2 == 0 ? 40 : 200
                at[1] = green
                at[2] = UInt8(x * 255 / max(width - 1, 1))
                at[3] = 255
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

    /// The same pixels as 8-bit BGRX from a plain bitmap context: no alpha, the fourth byte 0.
    private static func makeSkipFirstImage(_ display: Display, width: Int, height: Int) throws -> CGImage {
        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4 + 96,
                space: display.colorSpace, bitmapInfo: bitmapInfo),
            let base = context.data
        else { throw ScreenCaptureError.noImage }
        let bytesPerRow = context.bytesPerRow
        let pixels = base.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        for y in 0..<height {
            let green = UInt8(y * 255 / max(height - 1, 1))
            let row = pixels + y * bytesPerRow
            for x in 0..<width {
                let at = row + x * 4
                at[0] = (x / 8 + y / 8) % 2 == 0 ? 40 : 200
                at[1] = green
                at[2] = UInt8(x * 255 / max(width - 1, 1))
                at[3] = 0
            }
        }
        guard let image = context.makeImage() else { throw ScreenCaptureError.noImage }
        return image
    }
}
