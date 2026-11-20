import CoreGraphics
import Darwin
import Foundation
import SnapitEngineFFI

/// What a Capture file says about its Capture.
nonisolated struct CaptureFileInfo: Sendable {
    let width: Int
    let height: Int
    /// Bytes between the starts of two rows.
    let stride: Int
    /// Pixels per point: 2 on a Retina display, 1 otherwise.
    let scale: Double
    let captureTime: Date
    /// The display's ICC profile, exactly as the menu bar app stored it. Empty for none.
    let iccProfile: Data

    /// The Capture's size in points.
    var pointSize: CGSize { CGSize(width: Double(width) / scale, height: Double(height) / scale) }
    /// The resolution a PNG of the Capture records: 72 dpi at 1x, 144 on Retina.
    var dpi: Int { Int((72 * scale).rounded()) }
}

/// A Capture file mapped into memory, read-only. The mapping goes when the last reference does.
nonisolated struct OpenedCapture: Sendable {
    let info: CaptureFileInfo
    let pixels: PixelBuffer
}

/// Capture files: how a Capture's pixels get from the menu bar app to the Editor helper, and
/// what the Last Capture store keeps. The pixels never travel over the socket.
///
/// Each Capture is one file, `captures/capture-<N>.pixels` in snapit's private cache folder.
/// The menu bar app writes it (see `write`) and tells the helper `open-capture <N>`; the
/// helper maps it read-only (see `open`). The file format lives in the engine
/// (`engine/src/capture_file.rs`); `create(at:…)` and `open(at:)` work on any path, for other
/// files in the same format (a shared Export file).
nonisolated enum CaptureFiles {
    static var folder: URL { AppIdentity.cacheFolder.appendingPathComponent("captures", isDirectory: true) }

    static func url(number: Int) -> URL { folder.appendingPathComponent("capture-\(number).pixels") }

    private static let prefix = "capture-"
    private static let suffix = ".pixels"
    private static let partialSuffix = ".partial"

    /// Creates a Capture file at `url` for a `width` x `height` image and returns its pixels,
    /// mapped writable and zeroed. The file already has its header and ICC profile; whatever the
    /// caller draws into the buffer is what the file holds once the buffer is released. The
    /// buffer's `iccProfile` is `icc`.
    static func create(
        at url: URL, width: Int, height: Int, scale: Double, captureTime: Date, icc: Data, colorSpace: CGColorSpace
    ) throws -> PixelBuffer {
        guard let w = UInt32(exactly: width), let h = UInt32(exactly: height) else {
            throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT)
        }
        let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { throw EngineError(status: .ioFailed, rawValue: errno) }
        defer { close(descriptor) }  // the mapping stays valid after the descriptor closes

        var header = SnapitCaptureHeader()
        var mapping = SnapitPixelBuffer(data: nil, width: 0, height: 0, stride: 0, mapped_len: 0)
        let status = icc.withUnsafeBytes { bytes in
            snapit_capture_file_create(
                descriptor, w, h, scale, Int64(captureTime.timeIntervalSince1970),
                icc.isEmpty ? nil : bytes.bindMemory(to: UInt8.self).baseAddress, icc.count, &header, &mapping)
        }
        try Engine.check(status)
        return PixelBuffer(adopting: mapping, colorSpace: colorSpace, iccProfile: icc, isWritable: true)
    }

    /// Maps the Capture file at `url` read-only.
    static func open(at url: URL) throws -> OpenedCapture {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw EngineError(status: .ioFailed, rawValue: errno) }
        defer { close(descriptor) }

        var header = SnapitCaptureHeader()
        try Engine.check(snapit_capture_file_info(descriptor, &header))
        var profile = Data(count: Int(header.icc_len))
        if !profile.isEmpty {
            let count = profile.count
            let status = profile.withUnsafeMutableBytes {
                snapit_capture_file_icc(descriptor, &header, $0.bindMemory(to: UInt8.self).baseAddress, count)
            }
            try Engine.check(status)
        }
        var mapping = SnapitPixelBuffer(data: nil, width: 0, height: 0, stride: 0, mapped_len: 0)
        try Engine.check(snapit_capture_file_map(descriptor, &header, 0, &mapping))

        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = profile.isEmpty ? srgb : (CGColorSpace(iccData: profile as CFData) ?? srgb)
        let info = CaptureFileInfo(
            width: Int(header.width), height: Int(header.height), stride: Int(header.stride), scale: header.scale,
            captureTime: Date(timeIntervalSince1970: TimeInterval(header.capture_time)), iccProfile: profile)
        let pixels = PixelBuffer(adopting: mapping, colorSpace: space, iccProfile: profile, isWritable: false)
        return OpenedCapture(info: info, pixels: pixels)
    }

    /// Writes `image` as Capture N. The file is built under a partial name and renamed into
    /// place, so the helper never sees half a file. Returns once the pixels are in the file and
    /// the mapping is gone.
    static func write(number: Int, image: CGImage, scale: Double, captureTime: Date = Date()) throws {
        try write(
            number: number, width: image.width, height: image.height, scale: scale,
            colorSpace: PixelBuffer.bitmapColorSpace(for: image), captureTime: captureTime
        ) { try $0.draw(image) }
    }

    /// Writes the pixel rectangle `area` of `image` as Capture N: the engine crops it straight
    /// into the file's mapped buffer. The file carries the color space of `image`.
    static func write(number: Int, image: CGImage, cropping area: PixelRect, scale: Double, captureTime: Date = Date())
        throws
    {
        guard area.isInside(width: image.width, height: image.height) else {
            throw EngineError(status: .invalidArgument, rawValue: SNAPIT_STATUS_INVALID_ARGUMENT)
        }
        try write(
            number: number, width: area.width, height: area.height, scale: scale,
            colorSpace: PixelBuffer.bitmapColorSpace(for: image), captureTime: captureTime
        ) { try Engine.crop(image, to: area, into: $0) }
    }

    /// Writes a `width` x `height` Capture as Capture N, in the same way: `fill` puts the
    /// pixels into the file's mapped buffer.
    static func write(
        number: Int, width: Int, height: Int, scale: Double, colorSpace space: CGColorSpace,
        captureTime: Date = Date(), fill: (PixelBuffer) throws -> Void
    ) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let final = url(number: number)
        let partial = URL(fileURLWithPath: final.path + partialSuffix)
        do {
            let profile = (space.copyICCData() as Data?) ?? Data()
            // The buffer unmaps the file when it goes out of scope at the end of this block.
            let pixels = try create(
                at: partial, width: width, height: height, scale: scale, captureTime: captureTime,
                icc: profile, colorSpace: space)
            try fill(pixels)
        } catch {
            unlink(partial.path)
            throw error
        }
        guard rename(partial.path, final.path) == 0 else {
            let code = errno
            unlink(partial.path)
            throw EngineError(status: .ioFailed, rawValue: code)
        }
    }

    /// Maps Capture N read-only.
    static func open(number: Int) throws -> OpenedCapture {
        try open(at: url(number: number))
    }

    /// The numbers of the Capture files in the folder.
    static func existingNumbers() -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
            return Int(name.dropFirst(prefix.count).dropLast(suffix.count))
        }
    }

    static func remove(number: Int) {
        unlink(url(number: number).path)
    }

    /// Removes every Capture file, then the folder. Only snapit's own files are touched, never
    /// anything else in the cache folder.
    static func removeAll() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(prefix) && (name.hasSuffix(suffix) || name.hasSuffix(suffix + partialSuffix)) {
            unlink(folder.appendingPathComponent(name).path)
        }
        rmdir(folder.path)
    }
}
