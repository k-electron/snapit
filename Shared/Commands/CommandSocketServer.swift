import Darwin
import Foundation

/// Listens on a Unix-domain socket and runs one command per connection through a
/// `SocketCommandRegistry`. Event driven: the dispatch source sleeps until a client
/// connects, so the process stays at 0% CPU at rest. Commands run in a main-actor task,
/// so a slow handler never blocks the main thread or other connections.
nonisolated final class CommandSocketServer: @unchecked Sendable {
    private let path: String
    private let registry: SocketCommandRegistry
    private let acceptQueue = DispatchQueue(label: "snapit.command-socket.accept")
    private let connectionQueue = DispatchQueue(label: "snapit.command-socket.connections", attributes: .concurrent)
    private var source: DispatchSourceRead?

    init(path: String, registry: SocketCommandRegistry) {
        self.path = path
        self.registry = registry
    }

    /// Starts listening. Throws `SocketError.alreadyRunning` when another process answers
    /// on the path; a stale socket file left by a crashed process is replaced.
    func start() throws {
        var address = try UnixSocket.address(path: path)
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if CommandSocketClient.isListeningBlocking(at: path) { throw SocketError.alreadyRunning(path) }
        unlink(path)

        let listener = try UnixSocket.makeSocket()
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(listener)
            throw SocketError.system("bind", code)
        }
        chmod(path, 0o600)
        guard listen(listener, 8) == 0 else {
            let code = errno
            close(listener)
            throw SocketError.system("listen", code)
        }
        _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptPending(on: listener) }
        source.setCancelHandler { close(listener) }
        self.source = source
        source.resume()
    }

    /// Stops listening and removes the socket file before returning.
    func stop() {
        // A server that is not listening (never started, or already stopped) does not own the
        // path any more: a relaunched snapit may be listening on it.
        guard source != nil else { return }
        source?.cancel()
        source = nil
        unlink(path)
    }

    private func acceptPending(on listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { return }
            serve(client)
        }
    }

    /// Reads one line off the main thread, runs it in a main-actor task, writes the reply.
    private func serve(_ client: Int32) {
        connectionQueue.async { [registry, connectionQueue] in
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            UnixSocket.setTimeouts(client, seconds: 2)

            var line = [UInt8]()
            var byte: UInt8 = 0
            while line.count < 65_536, read(client, &byte, 1) == 1, byte != UInt8(ascii: "\n") {
                line.append(byte)
            }
            let text = String(decoding: line, as: UTF8.self)
            Task {
                let reply = await registry.handle(line: text)
                connectionQueue.async {
                    UnixSocket.write(client, reply + "\n")
                    close(client)
                }
            }
        }
    }
}
