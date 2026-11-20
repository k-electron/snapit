import Foundation

nonisolated extension SocketCommand {
    /// `save-export <export file> <downscale: 0|1>`: the Editor helper tells the menu bar app to
    /// Save the flattened image in the shared export file (`ExportFiles`). The menu bar app maps
    /// the file, checks the Save location is writable and replies at once (`SaveReply`); it then
    /// Balanced-encodes in the background and writes `snapit-YYYYMMDD-HHMMSS.png`, so the Save
    /// finishes even when the helper quits straight after the reply.
    static let saveExport = SocketCommand("save-export")
}

/// The menu bar app's answer to a Save request, as one reply line.
nonisolated enum SaveReply: Equatable, Sendable {
    /// The file is mapped and the Save location is writable. The encode runs in the background.
    case accepted
    /// The Save location could not be written to: a folder macOS protects, one that is gone or
    /// read-only. `code` is the `errno`. The Editor stays open.
    case folderNotWritable(folder: String, code: Int32)
    /// Anything else that stopped the Save (the shared file could not be read).
    case failed(String)

    var line: String {
        switch self {
        case .accepted: "ok"
        case .folderNotWritable(let folder, let code): "error folder-not-writable \(code) \(folder)"
        case .failed(let message): "error \(message)"
        }
    }

    init(line: String) {
        if line == "ok" {
            self = .accepted
            return
        }
        let prefix = "error folder-not-writable "
        if line.hasPrefix(prefix) {
            let rest = line.dropFirst(prefix.count)
            let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            if let code = parts.first.flatMap({ Int32($0) }) {
                self = .folderNotWritable(folder: parts.count > 1 ? String(parts[1]) : "", code: code)
                return
            }
        }
        self = .failed(line.hasPrefix("error ") ? String(line.dropFirst(6)) : line)
    }
}
