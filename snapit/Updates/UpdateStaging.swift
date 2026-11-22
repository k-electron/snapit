import Darwin
import Foundation

/// What marks a folder as an Update's staging folder, and what may be deleted of it. The Update
/// writes a marker file holding its own process id into the folder it makes; the relaunched copy
/// deletes the folder it was handed, and the folders of Updates that never finished, only where the
/// marker is there. A path on a command line, or a folder that merely sits beside a staging
/// folder, is never deleted on its word alone.
nonisolated enum UpdateStaging {
    static let markerName = ".snapit-update"
    /// Where `BundleSwap` puts the old copy when the volume cannot swap two folders. If the new copy
    /// could not be put in place after that, this is the only snapit there is: it is never swept.
    static let oldCopyName = "previous.app"

    /// Marks `folder` as the staging folder of the Update that process `owner` runs.
    static func mark(_ folder: URL, owner: Int32 = getpid()) throws {
        try Data(String(owner).utf8).write(to: folder.appendingPathComponent(markerName))
    }

    /// The process that made `folder` for an Update; nil when `folder` is not a staging folder (not
    /// a real folder, a link to one, or without the marker).
    static func owner(of folder: URL) -> Int32? {
        let fileManager = FileManager.default
        guard (try? fileManager.attributesOfItem(atPath: folder.path))?[.type] as? FileAttributeType == .typeDirectory,
            let data = fileManager.contents(atPath: folder.appendingPathComponent(markerName).path),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Deletes `folder`, never to the Trash, when it is the staging folder of the Update that process
    /// `owner` ran. Anything else is left and logged.
    static func remove(_ folder: URL, madeBy owner: Int32) {
        guard Self.owner(of: folder) == owner else {
            NSLog("snapit: \(folder.path) is not the staging folder of the Update that started this copy, so it is left")
            return
        }
        delete(folder)
    }

    /// Deletes the staging folders of Updates that never finished, in `parent` beside `keep`: the
    /// ones whose process has quit, unless one holds the old copy of snapit that could not be put
    /// back (`oldCopyName`).
    static func sweepAbandoned(in parent: URL, keeping keep: URL?) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: parent.path) else { return }
        for name in names {
            let folder = parent.appendingPathComponent(name, isDirectory: true)
            if let keep, folder.standardizedFileURL == keep.standardizedFileURL { continue }
            guard let owner = owner(of: folder), !isRunning(owner) else { continue }
            if fileManager.fileExists(atPath: folder.appendingPathComponent(oldCopyName).path) {
                NSLog("snapit: \(folder.path) holds the old copy of snapit from an Update that could not finish, so it is left")
                continue
            }
            delete(folder)
        }
    }

    private static func delete(_ folder: URL) {
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            if FileManager.default.fileExists(atPath: folder.path) {
                NSLog("snapit: could not remove the Update's leftovers at \(folder.path): \(error)")
            }
        }
    }

    private static func isRunning(_ process: Int32) -> Bool {
        kill(process, 0) == 0 || errno == EPERM
    }
}
