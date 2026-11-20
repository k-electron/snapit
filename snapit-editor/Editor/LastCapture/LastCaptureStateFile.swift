import Darwin
import Foundation

/// What the state file beside the Last Capture's pixels holds: the Annotations, the crop and the
/// Undo history (all of it `AnnotationHistory`, which is `Codable` and capped at 100 steps), the
/// revision, and whether the Capture was exported at that revision.
///
/// The Annotations are stored through the `Codable` types themselves, never a second schema, so a
/// kind or a field a ticket adds is stored the day it exists, and a kind this snapit does not know
/// (a newer one wrote it) survives a Reopen untouched.
nonisolated struct LastCaptureState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = LastCaptureState.currentVersion
    /// `history.revision`, repeated at the top so a reader need not decode the history.
    var revision: Int
    /// True when the Capture had no changes since its last Export.
    var exported: Bool
    var history: AnnotationHistory

    init(history: AnnotationHistory, exported: Bool) {
        revision = history.revision
        self.exported = exported
        self.history = history
    }

    private enum CodingKeys: String, CodingKey { case version, revision, exported, history }

    /// The history is required: a file without it is not a state file. Everything else has a
    /// default, so a file an older snapit wrote still opens.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        history = try container.decode(AnnotationHistory.self, forKey: .history)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        revision = history.revision
        exported = try container.decodeIfPresent(Bool.self, forKey: .exported) ?? false
    }
}

/// Reads and writes the Last Capture's state file, `captures/capture-<N>.state`.
nonisolated enum LastCaptureStateFile {
    static func encode(_ state: LastCaptureState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) throws -> LastCaptureState {
        try JSONDecoder().decode(LastCaptureState.self, from: data)
    }

    /// The stored state of Capture N. Nil when there is no state file: the Editor writes one only
    /// after the first change, so an untouched Last Capture has pixels alone, and that is not
    /// damage. Throws when the file is there and cannot be read.
    static func read(number: Int) throws -> LastCaptureState? {
        let url = CaptureFiles.stateURL(number: number)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
        return try decode(data)
    }

    /// Writes `data` as Capture N's state file: under a partial name first, then renamed into
    /// place, so a reader never sees half a file. `stillWanted` is asked just before the rename
    /// (a write the store has since superseded is dropped): when it says no, nothing is left.
    /// Returns false when `stillWanted` said no. Throws when the file could not be written.
    static func write(_ data: Data, number: Int, stillWanted: () -> Bool) throws -> Bool {
        let final = CaptureFiles.stateURL(number: number)
        let partial = CaptureFiles.partialURL(for: final)
        let descriptor = Darwin.open(partial.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32?
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 {
                    failure = errno
                    return
                }
                offset += count
            }
        }
        close(descriptor)
        if let failure {
            unlink(partial.path)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        guard stillWanted() else {
            unlink(partial.path)
            return false
        }
        guard rename(partial.path, final.path) == 0 else {
            let code = errno
            unlink(partial.path)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return true
    }
}
