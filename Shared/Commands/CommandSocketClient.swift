import Darwin
import Foundation

/// Sends one command line to the other process and returns its reply.
enum CommandSocketClient {
    @discardableResult
    static func send(_ command: SocketCommand, arguments: [String] = [], to path: String) throws -> String {
        var address = try UnixSocket.address(path: path)
        let descriptor = try UnixSocket.makeSocket()
        defer { close(descriptor) }
        UnixSocket.setTimeouts(descriptor, seconds: 2)

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw SocketError.system("connect", errno) }

        UnixSocket.write(descriptor, ([command.name] + arguments).joined(separator: " ") + "\n")
        var reply = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count <= 0 { break }
            reply.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    /// True when a process is listening on `path`.
    static func isListening(at path: String) -> Bool {
        (try? send(.ping, to: path)) == "pong"
    }
}
