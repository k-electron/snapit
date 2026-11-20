import AppKit

extension SocketCommandRegistry {
    /// Registers the commands both processes answer.
    func registerBuiltinCommands() {
        register(.ping) { _ in "pong" }
        register(.quit) { _ in
            // Reply first, then quit, so the caller sees "ok".
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApplication.shared.terminate(nil) }
            return "ok"
        }
        register(.engineVersion) { _ in
            (try? Engine.version()) ?? "error engine"
        }
        register(.engineProbePanic) { _ in
            Engine.probePanic().map { "\($0)" } ?? "unknown"
        }
        register(.echo) { request in
            request.arguments.joined(separator: "\n")
        }
        registerTestModeCommands()
    }
}
