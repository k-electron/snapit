import AppKit

extension SocketCommandRegistry {
    /// Registers the commands both processes answer.
    func registerBuiltinCommands() {
        register(.ping) { _ in "pong" }
        register(.quit) { _ in
            await QuitPreparation.run()
            NSApplication.terminateAfterReply()
            return "ok"
        }
        registerTestModeCommands()
    }
}

extension NSApplication {
    /// Quits a moment later, so the reply to the command that asked goes out first (the caller sees "ok").
    @MainActor static func terminateAfterReply() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { shared.terminate(nil) }
    }
}
