import AppKit

extension SocketCommandRegistry {
    /// Registers the commands both processes answer.
    func registerBuiltinCommands() {
        register(.ping) { _ in "pong" }
        register(.quit) { _ in
            // Reply first, then quit, so the caller sees "ok".
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return "ok"
        }
        register(.engineVersion) { _ in
            (try? Engine.version()) ?? "error engine"
        }
    }
}
