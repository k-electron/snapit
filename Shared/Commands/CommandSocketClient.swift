import Darwin
import Foundation

/// Sends one command line to the other process and returns its reply. Never blocks the
/// calling actor: the socket work runs on a background queue.
nonisolated enum CommandSocketClient {
    private static let queue = DispatchQueue(label: "snapit.command-socket-client", attributes: .concurrent)

    @discardableResult
    static func send(
        _ command: SocketCommand, arguments: [String] = [], to path: String, timeoutSeconds: Int = 2
    ) async throws -> String {
        let request = SocketRequest(command: command, arguments: arguments)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try exchange(request, path: path, timeoutSeconds: timeoutSeconds) })
            }
        }
    }

    /// True when a process is listening on `path`.
    static func isListening(at path: String, timeoutSeconds: Int = 1) async -> Bool {
        (try? await send(.ping, to: path, timeoutSeconds: timeoutSeconds)) == "pong"
    }

    /// Blocking form of `isListening`, for a server about to take over a socket path
    /// before the run loop starts.
    static func isListeningBlocking(at path: String) -> Bool {
        (try? exchange(SocketRequest(command: .ping), path: path, timeoutSeconds: 1)) == "pong"
    }

    /// Blocking send for the last moments of a process, when nothing else needs the main
    /// thread (an application in `applicationWillTerminate` no longer services tasks).
    /// Does nothing when no process listens on `path`.
    static func sendBeforeExit(_ command: SocketCommand, arguments: [String] = [], to path: String) {
        guard isListeningBlocking(at: path) else { return }
        _ = try? exchange(SocketRequest(command: command, arguments: arguments), path: path, timeoutSeconds: 1)
    }

    private static func exchange(_ request: SocketRequest, path: String, timeoutSeconds: Int) throws -> String {
        var address = try UnixSocket.address(path: path)
        let descriptor = try UnixSocket.makeSocket()
        defer { close(descriptor) }
        UnixSocket.setTimeouts(descriptor, seconds: timeoutSeconds)

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw SocketError.system("connect", errno) }

        UnixSocket.write(descriptor, request.line + "\n")
        var reply = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count <= 0 { break }
            reply.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
