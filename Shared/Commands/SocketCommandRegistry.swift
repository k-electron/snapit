import Foundation

/// Maps each `SocketCommand` a process accepts to its handler. Handlers run on the main
/// actor, may suspend, and return the reply text (without a trailing newline).
@MainActor
final class SocketCommandRegistry {
    typealias Handler = @MainActor (SocketRequest) async -> String

    private var handlers: [SocketCommand: Handler] = [:]

    /// A command has one handler: a second registration would silently replace the first (the
    /// way a feature's `quit` once replaced the built-in one), so it stops a debug build.
    func register(_ command: SocketCommand, handler: @escaping Handler) {
        assert(handlers[command] == nil, "the command \(command.name) is registered twice")
        handlers[command] = handler
    }

    func handle(line: String) async -> String {
        guard let request = SocketRequest(line: line) else { return "error empty command" }
        guard let handler = handlers[request.command] else {
            return "error unknown command \(request.command.name)"
        }
        return await handler(request)
    }
}
