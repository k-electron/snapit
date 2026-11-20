import CoreGraphics
import Darwin
import Foundation
import SnapitEngineFFI

nonisolated extension PixelBuffer {
    /// Runs `body` with the engine's parameters for encoding these pixels as `plan` says: the
    /// level, the resolution, the size (smaller than the pixels when the engine averages them
    /// down) and this buffer's color profile.
    private func withPNGParameters<Result>(
        level: PNGLevel, plan: PNGOutputPlan, _ body: (UnsafePointer<UInt8>, UnsafePointer<SnapitPngParams>) -> Result
    ) -> Result {
        let profile = iccProfile ?? (colorSpace.copyICCData() as Data?) ?? Data()
        return profile.withUnsafeBytes { profileBytes in
            var parameters = SnapitPngParams(
                level: level.rawValue, dpi: UInt32(plan.dpi), out_width: UInt32(plan.width),
                out_height: UInt32(plan.height),
                icc: profile.isEmpty ? nil : profileBytes.bindMemory(to: UInt8.self).baseAddress,
                icc_len: profile.count)
            return withReadOnlyPixels { base, _ in
                body(base.assumingMemoryBound(to: UInt8.self), &parameters)
            }
        }
    }

    /// Encodes the pixels as a PNG the way `plan` says, in one pass: a 1x plan averages the image
    /// down while it encodes, in no buffer of its own. The bytes are page-backed memory that goes
    /// back to the OS when the returned data is released.
    func encodePNG(level: PNGLevel, plan: PNGOutputPlan) throws -> Data {
        var bytes = SnapitBytes(data: nil, len: 0, capacity: 0)
        let status = withPNGParameters(level: level, plan: plan) { pixels, parameters in
            snapit_png_encode_ex(pixels, UInt32(width), UInt32(height), stride, parameters, &bytes)
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

    /// Encodes like `encodePNG(level:plan:)` but streams the PNG into the file `descriptor`
    /// through a small buffer, so the PNG is never held in memory. The descriptor stays open.
    func writePNG(level: PNGLevel, plan: PNGOutputPlan, toDescriptor descriptor: Int32) throws {
        let status = withPNGParameters(level: level, plan: plan) { pixels, parameters in
            snapit_png_encode_to_fd(pixels, UInt32(width), UInt32(height), stride, parameters, descriptor)
        }
        try Engine.check(status)
    }

    /// Writes the PNG to the file at `url`, streamed. The PNG is encoded into a hidden partial file of
    /// its own in the same folder and renamed over `url`, so a reader that has the old file open keeps
    /// reading the old one, two writes never share a file, and nobody sees half a PNG. The file's mode is
    /// 0644 less the umask, the same as a Saved file.
    func writePNG(level: PNGLevel, plan: PNGOutputPlan, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        let partial = folder.appendingPathComponent(".\(url.lastPathComponent)-\(UUID().uuidString).partial")
        let descriptor = Darwin.open(partial.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else { throw EngineError(status: .ioFailed, rawValue: errno) }
        do {
            try writePNG(level: level, plan: plan, toDescriptor: descriptor)
            guard close(descriptor) == 0 else { throw EngineError(status: .ioFailed, rawValue: errno) }
        } catch {
            close(descriptor)
            unlink(partial.path)
            throw error
        }
        guard rename(partial.path, url.path) == 0 else {
            let code = errno
            unlink(partial.path)
            throw EngineError(status: .ioFailed, rawValue: code)
        }
    }

    /// How many source rows the engine reads for each row of a thumbnail: a few evenly spaced ones,
    /// so a thumbnail of a big Capture leaves most of its memory-mapped pages unread (and out of
    /// the helper's footprint).
    private static var thumbnailRowSamples: UInt32 { 4 }

    /// A small copy of these pixels, averaged down by the engine so that neither side is longer
    /// than `maxSide` (the drag-out thumbnail). The same color space and profile.
    func makeThumbnail(maxSide: Int) throws -> PixelBuffer {
        let longest = max(width, height)
        let factor = longest > maxSide ? Double(maxSide) / Double(longest) : 1
        let thumbnailWidth = max(1, Int((Double(width) * factor).rounded()))
        let thumbnailHeight = max(1, Int((Double(height) * factor).rounded()))
        let thumbnail = try makeEmptyBuffer(width: thumbnailWidth, height: thumbnailHeight)
        let status = withReadOnlyPixels { source, sourceStride in
            thumbnail.withPixels { destination, destinationStride in
                snapit_downscale(
                    source.assumingMemoryBound(to: UInt8.self), UInt32(width), UInt32(height), sourceStride,
                    UInt32(thumbnailWidth), UInt32(thumbnailHeight),
                    destination.assumingMemoryBound(to: UInt8.self), destinationStride, Self.thumbnailRowSamples)
            }
        }
        try Engine.check(status)
        return thumbnail
    }
}
