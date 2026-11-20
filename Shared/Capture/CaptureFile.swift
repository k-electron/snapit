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
/// what the Last Capture store (a later ticket) keeps. The pixels never travel over the socket.
///
/// Each Capture is one file, `captures/capture-<N>.pixels` in snapit's private cache folder.
/// The menu bar app writes it (see `write`) and tells the helper `open-capture <N>`; the
/// helper maps it read-only (see `open`). The file format lives in the engine
/// (`engine/src/capture_file.rs`).
nonisolated enum CaptureFiles {
    static var folder: URL { AppIdentity.cacheFolder.appendingPathComponent("captures", isDirectory: true) }

    static func url(number: Int) -> URL { folder.appendingPathComponent("capture-\(number).pixels") }

    private static let prefix = "capture-"
    private static let suffix = ".pixels"
    private static let partialSuffix = ".partial"

    /// Writes `image` as Capture N. The file is built under a partial name and renamed into
    /// place, so the helper never sees half a file. Returns once the pixels are in the file and
    /// the mapping is gone.
    static func write(number: Int, image: CGImage, scale: Double, captureTime: Date = Date()) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let final = url(number: number)
        let partialPath = final.path + partialSuffix
        let descriptor = Darwin.open(partialPath, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { throw EngineError(status: .ioFailed, rawValue: errno) }
        defer { close(descriptor) }
        do {
            let space = PixelBuffer.bitmapColorSpace(for: image)
            let profile = (space.copyICCData() as Data?) ?? Data()
            var header = SnapitCaptureHeader()
            var mapping = SnapitPixelBuffer(data: nil, width: 0, height: 0, stride: 0, mapped_len: 0)
            let status = profile.withUnsafeBytes { bytes in
                snapit_capture_file_create(
                    descriptor, UInt32(image.width), UInt32(image.height), scale,
                    Int64(captureTime.timeIntervalSince1970),
                    profile.isEmpty ? nil : bytes.bindMemory(to: UInt8.self).baseAddress,
                    profile.count, &header, &mapping)
            }
            try Engine.check(status)
            // The buffer unmaps the file when it goes out of scope at the end of this block.
            let pixels = PixelBuffer(adopting: mapping, colorSpace: space, iccProfile: profile)
            try pixels.draw(image)
        } catch {
            unlink(partialPath)
            throw error
        }
        guard rename(partialPath, final.path) == 0 else {
            let code = errno
            unlink(partialPath)
            throw EngineError(status: .ioFailed, rawValue: code)
        }
    }

    /// Maps Capture N read-only.
    static func open(number: Int) throws -> OpenedCapture {
        let descriptor = Darwin.open(url(number: number).path, O_RDONLY)
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
            width: Int(header.width), height: Int(header.height), stride: header.stride, scale: header.scale,
            captureTime: Date(timeIntervalSince1970: TimeInterval(header.capture_time)), iccProfile: profile)
        return OpenedCapture(info: info, pixels: PixelBuffer(adopting: mapping, colorSpace: space, iccProfile: profile))
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
