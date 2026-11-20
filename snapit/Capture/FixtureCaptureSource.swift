import CoreGraphics
import Foundation

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
    }

    /// 1x, an odd width so every row of engine memory carries padding.
    var display = Display(scale: 1, pointWidth: 301, pointHeight: 187)

    /// How long a Capture takes, standing in for the time a user spends choosing an Area
    /// (`fixture-delay`).
    var delay = Duration.zero

    func captureDisplayUnderPointer() async throws -> CapturedScreen {
        if delay > .zero { try await Task.sleep(for: delay) }
        let display = display
        return CapturedScreen(image: try Self.makeImage(display), scale: Double(display.scale))
    }

    private static func makeImage(_ display: Display) throws -> CGImage {
        let width = display.pointWidth * display.scale
        let height = display.pointHeight * display.scale
        // Source rows deliberately wider than the pixels, as ScreenCaptureKit's can be.
        let bytesPerRow = width * 4 + 96
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: display.colorSpace, bitmapInfo: bitmapInfo),
            let base = context.data
        else { throw ScreenCaptureError.noImage }

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
        guard let image = context.makeImage() else { throw ScreenCaptureError.noImage }
        return image
    }
}
