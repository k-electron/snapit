import CryptoKit
import Foundation

/// A tool of the system run to completion, with what it printed.
nonisolated enum SystemTool {
    struct Output {
        let status: Int32
        let text: Data
    }

    /// Runs `executable` with `arguments` and waits for it. What it prints to its error stream is dropped.
    static func run(_ executable: String, _ arguments: [String]) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let text = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, text: text)
    }
}

/// What an Update does with a release's disk image: checks it against the hash the release
/// publishes, and takes `snapit.app` out of it. All of it blocks, so callers run it off the main actor.
nonisolated enum DiskImage {
    enum Failure: Error, CustomStringConvertible {
        case attachFailed
        case noApp
        case copyFailed(String)
        case detachFailed

        var description: String {
            switch self {
            case .attachFailed: "the disk image could not be opened"
            case .noApp: "the disk image holds no snapit"
            case .copyFailed(let reason): "snapit could not be copied out of the disk image: \(reason)"
            case .detachFailed: "the disk image could not be closed"
            }
        }
    }

    /// The SHA-256 of the file, as 64 lowercase hex digits.
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The hash a release's `.sha256` file holds: the first word of its text (`shasum`'s form is
    /// `<hash>  <file name>`), as 64 lowercase hex digits; nil for anything else.
    static func publishedHash(in contents: Data) -> String? {
        let word = String(decoding: contents, as: UTF8.self).split(whereSeparator: \.isWhitespace).first
        guard let hash = word.map({ $0.lowercased() }), hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        return hash
    }

    /// Attaches the disk image read-only and hidden from Finder and Spotlight (`nobrowse`) at
    /// `mountPoint`, copies the `snapit.app` on it to `destination`, and detaches it again. The
    /// image is detached whatever happens.
    static func copyApp(from image: URL, to destination: URL, mountingAt mountPoint: URL) throws {
        let attach = try SystemTool.run(
            "/usr/sbin/diskutil",
            ["image", "attach", "--readOnly", "--nobrowse", "--mountPoint", mountPoint.path, "--plist", image.path])
        guard attach.status == 0, let device = device(in: attach.text) else { throw Failure.attachFailed }
        var failure: Error?
        do {
            let source = mountPoint.appendingPathComponent("snapit.app", isDirectory: true)
            guard FileManager.default.fileExists(atPath: source.path) else { throw Failure.noApp }
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                throw Failure.copyFailed(error.localizedDescription)
            }
        } catch {
            failure = error
        }
        let detached = detach(device)
        if let failure { throw failure }
        guard detached else { throw Failure.detachFailed }
    }

    /// The whole disk the attached image is, such as `disk7`, from `diskutil image attach --plist`.
    private static func device(in plist: Data) -> String? {
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
            let entities = root["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.first?["dev-entry"] as? String
    }

    /// Ejects the attached image; when the volume is busy, forces it once.
    private static func detach(_ device: String) -> Bool {
        if (try? SystemTool.run("/usr/sbin/diskutil", ["eject", device]))?.status == 0 { return true }
        return (try? SystemTool.run("/usr/bin/hdiutil", ["detach", device, "-force"]))?.status == 0
    }
}
