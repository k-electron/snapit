import AppKit

nonisolated extension SocketCommand {
    /// Replies with one `key=value` line per test-mode seam, so the scripted run can check
    /// that every edge is the test one before it drives anything.
    static let testSeams = SocketCommand("test-seams")
    /// Replies with the type identifiers on the private pasteboard, one per line.
    static let pasteboardTypes = SocketCommand("pasteboard-types")
    /// `pasteboard-dump-png <path>`: writes the PNG on the private pasteboard to `<path>` (inside
    /// the run's root) and replies `ok <byte count>`.
    static let pasteboardDumpPNG = SocketCommand("pasteboard-dump-png")
    /// Empties the private pasteboard.
    static let pasteboardClear = SocketCommand("pasteboard-clear")
}

extension SocketCommandRegistry {
    /// The test-mode commands both processes answer. They exist only while test mode is on,
    /// so a normal run exposes nothing that reads the clipboard.
    ///
    /// A feature adds commands for its own edge in its own file (a `register…TestCommands()`
    /// in that feature's target) rather than here.
    func registerTestModeCommands() {
        guard TestMode.isActive else { return }

        register(.testSeams) { _ in
            [
                "root=\(TestMode.root?.path ?? "")",
                "pasteboard=\(AppPasteboard.current.name.rawValue)",
                "defaults=\(AppDefaults.location)",
                "save=\(SaveLocation.folder.path)",
                "cache=\(AppIdentity.cacheFolder.path)",
                "permission=\(ScreenRecordingPermission.current.isGranted ? "granted" : "denied")",
            ].joined(separator: "\n")
        }
        register(.pasteboardTypes) { _ in
            (AppPasteboard.current.types ?? []).map(\.rawValue).joined(separator: "\n")
        }
        register(.pasteboardDumpPNG) { request in
            guard let path = request.arguments.first, Self.isInsideRoot(path) else {
                return "error path must be inside the test root"
            }
            guard let data = AppPasteboard.current.data(forType: .png) else {
                return "error no png on the pasteboard"
            }
            do {
                try data.write(to: URL(fileURLWithPath: path))
                return "ok \(data.count)"
            } catch {
                return "error \(error)"
            }
        }
        register(.pasteboardClear) { _ in
            AppPasteboard.current.clearContents()
            return "ok"
        }
    }

    private static func isInsideRoot(_ path: String) -> Bool {
        guard let root = TestMode.root?.standardizedFileURL.path else { return false }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardized.hasPrefix(root + "/")
    }
}
