import Foundation

nonisolated extension SocketCommand {
    /// Test mode: holds every Save's write until `save-release`, so the run can make the helper
    /// quit while a Save is still being written. Replies `ok`.
    static let saveHold = SocketCommand("save-hold")
    /// Test mode: lets the held Saves write. Replies `ok`.
    static let saveRelease = SocketCommand("save-release")
    /// Test mode: `save-delay <seconds>` makes every Save's write start that much later. Replies `ok`.
    static let saveDelay = SocketCommand("save-delay")
    /// Test mode: `save-fail-check <errno>|off` makes every Save's writability check fail with that
    /// `errno` (1 is what macOS's privacy check gives for a folder the user denied). Replies `ok`.
    static let saveFailCheck = SocketCommand("save-fail-check")
    /// Test mode: `save-fail-write <errno>|off` makes every Save's write fail with that `errno` once
    /// it starts, after the hand-over (28 is a full disk). Replies `ok`.
    static let saveFailWrite = SocketCommand("save-fail-write")
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
        register(.saveFailCheck) { request in
            guard let code = Self.errnoArgument(request) else { return "error save-fail-check <errno>|off" }
            SaveService.shared.failChecksForTest(code: code)
            return "ok"
        }
        register(.saveFailWrite) { request in
            guard let code = Self.errnoArgument(request) else { return "error save-fail-write <errno>|off" }
            SaveService.shared.failWritesForTest(code: code)
            return "ok"
        }
        register(.savePending) { _ in
            "\(SaveService.shared.pendingCount)"
        }
    }

    /// `off`, or an `errno` number: `.some(nil)` and `.some(n)`; nil when the argument is neither.
    private static func errnoArgument(_ request: SocketRequest) -> Int32?? {
        guard let text = request.arguments.first else { return nil }
        if text == "off" { return .some(nil) }
        guard let code = Int32(text), code > 0 else { return nil }
        return .some(code)
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
