import Darwin
import Foundation

/// Where Save and drag-out keep their files in snapit's private cache folder.
///
/// * `exports/`: the shared export file the Editor helper flattens into (Capture file format,
///   memory-mapped) and the menu bar app encodes from. The menu bar app unlinks the file as soon
///   as it has mapped it, so a Save that is running leaves nothing behind.
/// * `drag-out/<N>/`: the PNG a drag out of Editor N offers, named like the Saved file.
nonisolated enum ExportFiles {
    static var exportsFolder: URL { AppIdentity.cacheFolder.appendingPathComponent("exports", isDirectory: true) }
    static var dragOutFolder: URL { AppIdentity.cacheFolder.appendingPathComponent("drag-out", isDirectory: true) }

    static func dragOutFolder(captureNumber: Int) -> URL {
        dragOutFolder.appendingPathComponent(String(captureNumber), isDirectory: true)
    }

    /// Makes `folder` private to the user (mode 0700), with its parents.
    static func ensureFolder(_ folder: URL) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// True when `path` is a file directly inside the exports folder (symbolic links resolved).
    static func isExportFile(path: String) -> Bool {
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let folder = exportsFolder.resolvingSymlinksInPath()
        return file.deletingLastPathComponent().path == folder.path && file.pathExtension == "pixels"
    }

    /// Removes the Editor's drag-out folder (its PNG, then the folder).
    static func removeDragOut(captureNumber: Int) {
        remove(folder: dragOutFolder(captureNumber: captureNumber), fileSuffixes: [".png", ".partial"])
        rmdir(dragOutFolder.path)
    }

    /// Removes every shared export file and every drag-out file, then their folders. Only snapit's
    /// own files are touched, never anything else in the cache folder.
    static func removeAll() {
        remove(folder: exportsFolder, fileSuffixes: [".pixels"])
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dragOutFolder.path)) ?? []
        for name in names where Int(name) != nil {
            remove(folder: dragOutFolder.appendingPathComponent(name), fileSuffixes: [".png", ".partial"])
        }
        rmdir(dragOutFolder.path)
    }

    private static func remove(folder: URL, fileSuffixes: [String]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where fileSuffixes.contains(where: name.hasSuffix) {
            unlink(folder.appendingPathComponent(name).path)
        }
        rmdir(folder.path)
    }
}
