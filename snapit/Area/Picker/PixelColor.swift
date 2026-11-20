import CoreGraphics
import Foundation

/// One device pixel of a frozen frame.
struct PixelPoint: Equatable {
    var x: Int
    var y: Int
}

/// A pixel's color as the frozen frame stores it: the three 8-bit components in the display's own
/// color space, never converted. A Display P3 display gives Display P3 values, so the hex is the
/// value the Capture (and the Editor) holds for that pixel.
struct PixelColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    /// `#RRGGBB`, uppercase.
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

/// Reads one pixel of a frozen frame.
nonisolated enum PixelSampler {
    /// The pixel at `point`, or nil outside the image. The pixel is cropped out (no copy of the
    /// frame) and drawn into one RGBA pixel in the image's own color space, so Core Graphics matches
    /// nothing and the components are the stored ones. Any pixel layout works (BGRA, BGRX, ...).
    static func color(in image: CGImage, at point: PixelPoint) -> PixelColor? {
        guard point.x >= 0, point.y >= 0, point.x < image.width, point.y < image.height,
            let pixel = image.cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1))
        else { return nil }
        for space in [rgbSpace(of: image), CGColorSpace(name: CGColorSpace.sRGB)] {
            guard let space else { continue }
            var bytes = [UInt8](repeating: 0, count: 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.interpolationQuality = .none
                context.setBlendMode(.copy)
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            if drawn { return PixelColor(red: bytes[0], green: bytes[1], blue: bytes[2]) }
        }
        return nil
    }

    /// The image's own color space, when it is an RGB one.
    static func rgbSpace(of image: CGImage) -> CGColorSpace? {
        guard let space = image.colorSpace, space.model == .rgb else { return nil }
        return space
    }
}
