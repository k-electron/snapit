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

/// A Capture's pixels, in memory the engine owns (anonymous `mmap`, BGRA, premultiplied,
/// top row first). Freed, and returned to the OS, when the last reference goes.
///
/// Rows are padded: always use `stride`, never `width * 4`.
nonisolated final class PixelBuffer: @unchecked Sendable {
    private var raw: SnapitPixelBuffer

    let width: Int
    let height: Int
    /// Bytes between the starts of two rows.
    let stride: Int
    /// The color space the pixel values are in. Embedded in the PNG as its ICC profile.
    private(set) var colorSpace: CGColorSpace
    /// The ICC profile bytes the pixels came with (a Capture file carries the display's), used
    /// byte for byte when encoding. Nil: the profile of `colorSpace`.
    let iccProfile: Data?

    /// An empty (zeroed) buffer for a `width` x `height` image.
    init(width: Int, height: Int, colorSpace: CGColorSpace? = nil) throws {
        guard let w = UInt32(exactly: width), let h = UInt32(exactly: height) else {
            throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT)
        }
        var buffer = SnapitPixelBuffer(data: nil, width: 0, height: 0, stride: 0, mapped_len: 0)
        try Engine.check(snapit_buffer_alloc(w, h, &buffer))
        raw = buffer
        self.width = width
        self.height = height
        stride = buffer.stride
        self.colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        iccProfile = nil
    }

    /// Takes over a mapping the engine made (a Capture file's pixels). Freed, unmapped, when
    /// the last reference goes.
    init(adopting buffer: SnapitPixelBuffer, colorSpace: CGColorSpace, iccProfile: Data?) {
        raw = buffer
        width = Int(buffer.width)
        height = Int(buffer.height)
        stride = buffer.stride
        self.colorSpace = colorSpace
        self.iccProfile = iccProfile
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
    /// into the buffer with Core Graphics.
    func withPixels<Result>(_ body: (UnsafeMutableRawPointer, _ stride: Int) throws -> Result) rethrows -> Result {
        try body(UnsafeMutableRawPointer(raw.data), stride)
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
