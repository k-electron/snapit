import Darwin
import Foundation

/// Listens on a Unix-domain socket and runs one command per connection through a
/// `SocketCommandRegistry`. Event driven: the dispatch source sleeps until a client
/// connects, so the process stays at 0% CPU at rest.
final class CommandSocketServer: @unchecked Sendable {
    private let path: String
    private let registry: SocketCommandRegistry
    private let queue = DispatchQueue(label: "snapit.command-socket")
    private var source: DispatchSourceRead?

    init(path: String, registry: SocketCommandRegistry) {
        self.path = path
        self.registry = registry
    }

    func start() throws {
        var address = try UnixSocket.address(path: path)
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
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

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(on: listener) }
        let socketPath = path
        source.setCancelHandler {
            close(listener)
            unlink(socketPath)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func acceptPending(on listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { return }
            serve(client)
        }
    }

    /// Reads one line, runs it on the main actor and writes the reply.
    private func serve(_ client: Int32) {
        defer { close(client) }
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        UnixSocket.setTimeouts(client, seconds: 2)

        var line = [UInt8]()
        var byte: UInt8 = 0
        while line.count < 65_536, read(client, &byte, 1) == 1, byte != UInt8(ascii: "\n") {
            line.append(byte)
        }
        let text = String(decoding: line, as: UTF8.self)
        let registry = self.registry
        let reply = DispatchQueue.main.sync {
            MainActor.assumeIsolated { registry.handle(line: text) }
        }
        UnixSocket.write(client, reply + "\n")
    }
}
