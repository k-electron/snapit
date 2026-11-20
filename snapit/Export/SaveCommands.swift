import Foundation

nonisolated extension SocketCommand {
    /// Test mode: holds every Save's write until `save-release`, so the run can make the helper
    /// quit while a Save is still being written. Replies `ok`.
    static let saveHold = SocketCommand("save-hold")
    /// Test mode: lets the held Saves write. Replies `ok`.
    static let saveRelease = SocketCommand("save-release")
    /// Test mode: `save-delay <seconds>` makes every Save's write start that much later. Replies `ok`.
    static let saveDelay = SocketCommand("save-delay")
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
        register(.saveDelay) { request in
            guard let seconds = request.arguments.first.flatMap(Double.init), seconds >= 0 else { return "error save-delay <seconds>" }
            SaveService.shared.delayWritesForTest(seconds: seconds)
            return "ok"
        }
        register(.savePending) { _ in
            "\(SaveService.shared.pendingCount)"
        }
    }

    /// Runs the check on a queue of its own, not a cooperative-pool thread: a folder prompt blocks
    /// the thread until the user answers.
    private static func begin(exportPath: String, downscale: Bool, folder: URL) async -> SaveReply {
        await withCheckedContinuation { continuation in
            checkQueue.async {
                continuation.resume(returning: SaveService.shared.begin(exportPath: exportPath, downscale: downscale, folder: folder))
            }
        }
    }

    private static let checkQueue = DispatchQueue(label: "snapit.save.check", qos: .userInitiated, attributes: .concurrent)
}
