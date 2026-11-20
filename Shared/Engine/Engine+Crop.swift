import CoreGraphics
import Foundation
import SnapitEngineFFI

/// A rectangle of whole pixels, top-left origin.
nonisolated struct PixelRect: Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    func isInside(width imageWidth: Int, height imageHeight: Int) -> Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= imageWidth && y + height <= imageHeight
    }
}

nonisolated extension Engine {
    /// Copies the pixel rectangle `area` of `image` into `buffer`, which must be exactly the
    /// size of `area`. The engine does the copy, byte for byte: no resampling and no color
    /// conversion, so the pixel values stay in the image's own color space.
    ///
    /// A `CGImage` that holds 8-bit BGRA with premultiplied alpha first (what ScreenCaptureKit
    /// produces) is read through its own row stride. Any other layout is first drawn into engine
    /// memory, which then serves as the source.
    static func crop(_ image: CGImage, to area: PixelRect, into buffer: PixelBuffer) throws {
        guard area.width == buffer.width, area.height == buffer.height,
            area.isInside(width: image.width, height: image.height)
        else { throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT) }

        if let data = image.bgraPixelData {
            try cropBytes(data, width: image.width, height: image.height, stride: image.bytesPerRow, area: area, into: buffer)
        } else {
            try crop(try PixelBuffer(copying: image), to: area, into: buffer)
        }
    }

    /// Copies the pixel rectangle `area` of `source` into `buffer` (exactly the size of `area`).
    /// `source` may be a read-only mapping.
    static func crop(_ source: PixelBuffer, to area: PixelRect, into buffer: PixelBuffer) throws {
        guard area.width == buffer.width, area.height == buffer.height,
            area.isInside(width: source.width, height: source.height)
        else { throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT) }
        try source.withReadOnlyPixels { base, stride in
            try copyRectangle(
                from: base.assumingMemoryBound(to: UInt8.self), width: source.width, height: source.height,
                stride: stride, area: area, into: buffer)
        }
    }

    private static func cropBytes(
        _ data: CFData, width: Int, height: Int, stride: Int, area: PixelRect, into buffer: PixelBuffer
    ) throws {
        guard let base = CFDataGetBytePtr(data), CFDataGetLength(data) >= stride * (height - 1) + width * 4 else {
            throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT)
        }
        try copyRectangle(from: base, width: width, height: height, stride: stride, area: area, into: buffer)
    }

    private static func copyRectangle(
        from base: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int, area: PixelRect, into buffer: PixelBuffer
    ) throws {
        try check(
            buffer.withPixels { destination, destinationStride in
                snapit_crop(
                    base, UInt32(width), UInt32(height), stride, UInt32(area.x), UInt32(area.y), UInt32(area.width),
                    UInt32(area.height), destination.assumingMemoryBound(to: UInt8.self), destinationStride)
            })
    }
}

nonisolated extension CGImage {
    /// The pixel bytes, when they are 8-bit BGRA with premultiplied alpha first (the layout of
    /// engine buffers), read through `bytesPerRow`. Nil for any other layout.
    fileprivate var bgraPixelData: CFData? {
        let wanted = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let layout = bitmapInfo.rawValue & (CGBitmapInfo.alphaInfoMask.rawValue | CGBitmapInfo.byteOrderMask.rawValue)
        guard bitsPerComponent == 8, bitsPerPixel == 32, layout == wanted, bytesPerRow >= width * 4 else { return nil }
        return dataProvider?.data
    }
}
