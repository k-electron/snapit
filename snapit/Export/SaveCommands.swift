import Foundation

nonisolated extension SocketCommand {
    /// Test mode: holds every Save's write until `save-release`, so the run can make the helper
    /// quit while a Save is still being written. Replies `ok`.
    static let saveHold = SocketCommand("save-hold")
    /// Test mode: lets the held Saves write. Replies `ok`.
    static let saveRelease = SocketCommand("save-release")
    /// Test mode: how many Saves are still being written.
    static let savePending = SocketCommand("save-pending")
}

extension SocketCommandRegistry {
    /// The Save request the Editor helper sends (`save-export`), and Save's test-mode commands.
    func registerSaveCommands() {
        register(.saveExport) { request in
            guard request.arguments.count >= 2 else { return "error save-export <export file> <downscale>" }
            let path = request.arguments[0]
            let downscale = request.arguments[1] == "1"
            // The writability check can wait on a folder prompt: never on the main thread.
            return await Self.begin(exportPath: path, downscale: downscale, folder: SaveLocation.folder).line
        }
        guard TestMode.isActive else { return }
        register(.saveHold) { _ in
            SaveService.shared.holdForTest()
            return "ok"
        }
        register(.saveRelease) { _ in
            SaveService.shared.releaseForTest()
            return "ok"
        }
        register(.savePending) { _ in
            "\(SaveService.shared.pendingCount)"
        }
    }

    @concurrent
    private static func begin(exportPath: String, downscale: Bool, folder: URL) async -> SaveReply {
        SaveService.shared.begin(exportPath: exportPath, downscale: downscale, folder: folder)
    }
}
