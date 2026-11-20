import Darwin
import Foundation

enum SocketError: Error, CustomStringConvertible {
    case pathTooLong(String)
    case system(String, Int32)

    var description: String {
        switch self {
        case .pathTooLong(let path):
            return "socket path is longer than \(UnixSocket.maxPathLength) bytes: \(path)"
        case .system(let call, let code):
            return "\(call) failed: \(String(cString: strerror(code)))"
        }
    }
}

/// Small helpers over POSIX Unix-domain sockets.
enum UnixSocket {
    /// `sun_path` holds 104 bytes on macOS, including the terminating NUL.
    static let maxPathLength = 103

    static func address(path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8CString)
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else { throw SocketError.pathTooLong(path) }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            for (index, byte) in bytes.enumerated() {
                destination[index] = UInt8(bitPattern: byte)
            }
        }
        return address
    }

    static func makeSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SocketError.system("socket", errno) }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return descriptor
    }

    static func setTimeouts(_ descriptor: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, size)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, size)
    }

    static func write(_ descriptor: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if written <= 0 { return }
            offset += written
        }
    }
}
