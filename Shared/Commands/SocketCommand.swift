import Foundation

/// A command one snapit process can send to the other over the local socket.
///
/// A command is a name plus arguments, sent as one text line: `name arg1 arg2`.
/// Arguments are percent-encoded on the wire, so an argument may contain spaces.
/// Each feature adds its commands in its own file:
///
///     extension SocketCommand { static let openCapture = SocketCommand("open-capture") }
///
/// and registers a handler for it in the process that receives it (see
/// `SocketCommandRegistry.register` and the per-target `*Commands.swift` file).
nonisolated struct SocketCommand: Hashable, Sendable {
    let name: String

    init(_ name: String) { self.name = name }
}

/// One command line on the wire: a command and its arguments.
nonisolated struct SocketRequest: Sendable {
    let command: SocketCommand
    let arguments: [String]

    init(command: SocketCommand, arguments: [String] = []) {
        self.command = command
        self.arguments = arguments
    }

    /// Parses a received line; nil when it holds no command.
    init?(line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let name = parts.first else { return nil }
        command = SocketCommand(name)
        arguments = parts.dropFirst().map { $0.removingPercentEncoding ?? $0 }
    }

    /// The line to send, without the trailing newline.
    var line: String {
        ([command.name] + arguments.map(Self.encode)).joined(separator: " ")
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ argument: String) -> String {
        argument.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}

/// Commands both processes understand. `BuiltinCommands.swift` registers their handlers.
nonisolated extension SocketCommand {
    /// Replies `pong`. Tells a caller the other process is up.
    static let ping = SocketCommand("ping")
    /// Quits the receiving process.
    static let quit = SocketCommand("quit")
    /// Replies with the engine version read through the C ABI. Test mode only.
    static let engineVersion = SocketCommand("engine-version")
    /// Makes the engine panic on purpose and replies with the status it came back as (`panic`). Test mode only.
    static let engineProbePanic = SocketCommand("engine-probe-panic")
    /// Replies with its arguments, one per line. Checks that arguments survive spaces. Test mode only.
    static let echo = SocketCommand("echo")
}
