import Foundation

/// Maps each `SocketCommand` a process accepts to its handler. Handlers run on the main
/// actor and return the reply text (without a trailing newline).
@MainActor
final class SocketCommandRegistry {
    typealias Handler = @MainActor (SocketRequest) -> String

    private var handlers: [SocketCommand: Handler] = [:]

    func register(_ command: SocketCommand, handler: @escaping Handler) {
        handlers[command] = handler
    }

    func handle(line: String) -> String {
        guard let request = SocketRequest(line: line) else { return "error empty command" }
        guard let handler = handlers[request.command] else {
            return "error unknown command \(request.command.name)"
        }
        return handler(request)
    }
}
