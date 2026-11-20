import Foundation
import SnapitEngineFFI

nonisolated extension PixelRect {
    var origin: (x: Int, y: Int) { (x, y) }

    /// The rectangle moved by `(dx, dy)`.
    func offset(by dx: Int, _ dy: Int) -> PixelRect {
        PixelRect(x: x + dx, y: y + dy, width: width, height: height)
    }
}

nonisolated extension Engine {
    /// Pixelates `area` of the image `window` (a rectangle of `source`, or all of it) in the
    /// engine and writes the result into `destination` with the area's top left at `at`. The
    /// grid of `block` x `block` pixel tiles starts at the area's top left corner, and every
    /// pixel of a tile becomes the tile's mean.
    ///
    /// `area` is in the window's own pixels (the origin is the window's top left). `source` is
    /// only read, so it may be a Capture's read-only mapping; it is never `destination`. The
    /// live preview (a buffer of the area's size, `at` zero) and the Export (the Export's own
    /// buffer, `at` the area's place in it) are this one call, so they cannot differ.
    static func pixelate(
        _ source: PixelBuffer, window: PixelRect, area: PixelRect, block: Int, into destination: PixelBuffer,
        at origin: (x: Int, y: Int) = (0, 0)
    ) throws {
        let invalid = EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT)
        guard window.isInside(width: source.width, height: source.height),
            area.isInside(width: window.width, height: window.height), block > 0, source !== destination,
            origin.x >= 0, origin.y >= 0, origin.x + area.width <= destination.width,
            origin.y + area.height <= destination.height
        else { throw invalid }
        try source.withReadOnlyPixels { base, stride in
            let windowBase = base.assumingMemoryBound(to: UInt8.self) + window.y * stride + window.x * 4
            try check(
                destination.withPixels { target, targetStride in
                    snapit_pixelate(
                        windowBase, UInt32(window.width), UInt32(window.height), stride, UInt32(area.x), UInt32(area.y),
                        UInt32(area.width), UInt32(area.height), UInt32(block),
                        target.assumingMemoryBound(to: UInt8.self) + origin.y * targetStride + origin.x * 4, targetStride)
                })
        }
    }
}
