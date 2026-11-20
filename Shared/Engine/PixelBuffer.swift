import CoreGraphics
import Foundation
import SnapitEngineFFI

/// How hard the engine works to shrink a PNG.
nonisolated enum PNGLevel: UInt32, Sendable {
    /// Copy and drag-out.
    case fast = 0
    /// Save.
    case balanced = 1
    case high = 2
}

/// A Capture's pixels, in memory the engine owns (BGRA, premultiplied, top row first). Freed,
/// and returned to the OS, when the last reference goes.
///
/// A buffer is either **writable** (anonymous memory, or a Capture file mapped writable by the
/// menu bar app) or **read-only** (the Editor helper's mapping of a Capture file). Writing to a
/// read-only mapping would crash the process, so `withPixels` and `draw` refuse it with a clear
/// message; read it with `withReadOnlyPixels`, and make a writable copy with `makeOwnedCopy`.
///
/// Rows are padded: always use `stride`, never `width * 4`.
nonisolated final class PixelBuffer: @unchecked Sendable {
    private var raw: SnapitPixelBuffer

    let width: Int
    let height: Int
    /// Bytes between the starts of two rows.
    let stride: Int
    /// False for a read-only mapping (an opened Capture file).
    let isWritable: Bool
    /// The color space the pixel values are in. Embedded in the PNG as its ICC profile.
    private(set) var colorSpace: CGColorSpace
    /// The ICC profile bytes the pixels came with (a Capture file carries the display's), used
    /// byte for byte when encoding. Nil: the profile of `colorSpace`. Every buffer made from this
    /// one (`makeOwnedCopy`, `makeEmptyBuffer`) carries it along.
    let iccProfile: Data?

    /// An empty (zeroed), writable buffer for a `width` x `height` image.
    init(width: Int, height: Int, colorSpace: CGColorSpace? = nil, iccProfile: Data? = nil) throws {
        guard let w = UInt32(exactly: width), let h = UInt32(exactly: height) else {
            throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT)
        }
        var buffer = SnapitPixelBuffer(data: nil, width: 0, height: 0, stride: 0, mapped_len: 0)
        try Engine.check(snapit_buffer_alloc(w, h, &buffer))
        raw = buffer
        self.width = width
        self.height = height
        stride = buffer.stride
        isWritable = true
        self.colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        self.iccProfile = iccProfile
    }

    /// Takes over a mapping the engine made (a Capture file's pixels). Freed, unmapped, when
    /// the last reference goes. `isWritable` says how the mapping was made.
    init(adopting buffer: SnapitPixelBuffer, colorSpace: CGColorSpace, iccProfile: Data?, isWritable: Bool) {
        raw = buffer
        width = Int(buffer.width)
        height = Int(buffer.height)
        stride = buffer.stride
        self.isWritable = isWritable
        self.colorSpace = colorSpace
        self.iccProfile = iccProfile
    }

    /// A new, empty, writable buffer of another size in the same color space, carrying the same
    /// ICC profile (what crop and 1x make, so the profile survives them byte for byte).
    func makeEmptyBuffer(width: Int, height: Int) throws -> PixelBuffer {
        try PixelBuffer(width: width, height: height, colorSpace: colorSpace, iccProfile: iccProfile)
    }

    /// A writable copy of these pixels in memory of its own: one row-by-row copy, honouring both
    /// strides. This is how an Export leaves the Capture's read-only mapping behind.
    func makeOwnedCopy() throws -> PixelBuffer {
        let copy = try makeEmptyBuffer(width: width, height: height)
        let rowBytes = width * 4
        let rows = height
        withReadOnlyPixels { source, sourceStride in
            copy.withPixels { destination, destinationStride in
                for row in 0..<rows {
                    memcpy(destination + row * destinationStride, source + row * sourceStride, rowBytes)
                }
            }
        }
        return copy
    }

    /// The color space to draw `image` in without converting it: its own, or sRGB when a
    /// bitmap can't hold that one.
    static func bitmapColorSpace(for image: CGImage) -> CGColorSpace {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let space = image.colorSpace else { return srgb }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let probe = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: bitmapInfo)
        return probe == nil ? srgb : space
    }

    /// Copies `image` into engine memory without converting it: the pixel values stay in the
    /// image's own color space (the display's, for a Capture).
    convenience init(copying image: CGImage) throws {
        try self.init(width: image.width, height: image.height, colorSpace: image.colorSpace)
        try draw(image)
    }

    deinit {
        _ = snapit_buffer_free(&raw)
    }

    /// Draws `image` over the whole buffer, copying its pixels without converting them.
    func draw(_ image: CGImage) throws {
        precondition(isWritable, "PixelBuffer.draw on a read-only Capture mapping: call makeOwnedCopy() first")
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        func makeContext(_ space: CGColorSpace) -> CGContext? {
            CGContext(
                data: raw.data, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: stride, space: space, bitmapInfo: bitmapInfo)
        }
        var context = makeContext(colorSpace)
        if context == nil, let srgb = CGColorSpace(name: CGColorSpace.sRGB) {
            // A color space a bitmap can't hold: convert to sRGB rather than lose the Capture.
            colorSpace = srgb
            context = makeContext(srgb)
        }
        guard let context else {
            throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT)
        }
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Calls `body` with the first byte of the pixels and the stride. For drawing straight
    /// into the buffer with Core Graphics. Only a writable buffer: writing to a Capture's
    /// read-only mapping would crash, so this refuses it.
    func withPixels<Result>(_ body: (UnsafeMutableRawPointer, _ stride: Int) throws -> Result) rethrows -> Result {
        precondition(isWritable, "PixelBuffer.withPixels on a read-only Capture mapping: call makeOwnedCopy() first")
        return try body(UnsafeMutableRawPointer(raw.data), stride)
    }

    /// Calls `body` with the first byte of the pixels and the stride, for reading. Works on any
    /// buffer, including the Capture's read-only mapping.
    func withReadOnlyPixels<Result>(_ body: (UnsafeRawPointer, _ stride: Int) throws -> Result) rethrows -> Result {
        try body(UnsafeRawPointer(raw.data), stride)
    }

    /// Encodes the pixels as a PNG that carries the physical size (`dpi`) and this buffer's
    /// color profile. The returned bytes are freed back to the engine when released.
    func encodePNG(level: PNGLevel, dpi: Int) throws -> Data {
        let profile = iccProfile ?? (colorSpace.copyICCData() as Data?) ?? Data()
        var bytes = SnapitBytes(data: nil, len: 0, capacity: 0)
        let status = profile.withUnsafeBytes { profileBytes in
            snapit_png_encode(
                raw.data, UInt32(width), UInt32(height), stride, level.rawValue, UInt32(dpi),
                profile.isEmpty ? nil : profileBytes.bindMemory(to: UInt8.self).baseAddress,
                profile.count, &bytes)
        }
        try Engine.check(status)
        let owned = bytes
        return Data(
            bytesNoCopy: UnsafeMutableRawPointer(owned.data), count: owned.len,
            deallocator: .custom { _, _ in
                var copy = owned
                _ = snapit_bytes_free(&copy)
            })
    }
}
