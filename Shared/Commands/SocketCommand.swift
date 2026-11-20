import Foundation

/// A command one snapit process can send to the other over the local socket.
///
/// A command is a name plus arguments, sent as one text line: `name arg1 arg2`.
/// Each feature adds its commands in its own file:
///
///     extension SocketCommand { static let openCapture = SocketCommand("open-capture") }
///
/// and registers a handler for it in the process that receives it (see
/// `SocketCommandRegistry.register` and the per-target `*Commands.swift` file).
struct SocketCommand: Hashable, Sendable {
    let name: String

    init(_ name: String) { self.name = name }
}

/// One received command line, split into its command and arguments.
struct SocketRequest: Sendable {
    let command: SocketCommand
    let arguments: [String]

    init?(line: String) {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let name = parts.first else { return nil }
        command = SocketCommand(name)
        arguments = Array(parts.dropFirst())
    }
}

/// Commands both processes understand. `BuiltinCommands.swift` registers their handlers.
extension SocketCommand {
    /// Replies `pong`. Tells a caller the other process is up.
    static let ping = SocketCommand("ping")
    /// Quits the receiving process.
    static let quit = SocketCommand("quit")
    /// Replies with the engine version read through the C ABI.
    static let engineVersion = SocketCommand("engine-version")
}
