import CoreGraphics
import Foundation
import SnapitEngineFFI

nonisolated extension PixelBuffer {
    /// Calls `body` with a Core Graphics context that draws straight into these pixels, in the
    /// buffer's own color space and with its stride: no copy in, no copy out. The context's
    /// origin is the bottom left, as Core Graphics has it. Only a writable buffer: drawing
    /// into a Capture's read-only mapping would crash, so this refuses it.
    func withCGContext<Result>(_ body: (CGContext) throws -> Result) throws -> Result {
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let width = width
        let height = height
        let colorSpace = colorSpace
        return try withPixels { base, stride in
            guard
                let context = CGContext(
                    data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride,
                    space: colorSpace, bitmapInfo: bitmapInfo)
            else { throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT) }
            return try body(context)
        }
    }
}
