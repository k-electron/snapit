import SnapitEngineFFI

/// Status code returned by every engine entry point.
enum EngineStatus: Int32, Sendable {
    case ok = 0
    case invalidArgument = 1
    case bufferTooSmall = 2
    case panic = 3
}

struct EngineError: Error, CustomStringConvertible {
    let status: EngineStatus?
    let rawValue: Int32

    var description: String {
        "engine returned status \(status.map { "\($0)" } ?? "unknown") (\(rawValue))"
    }
}

/// Thin Swift wrapper over the Rust engine's C ABI, linked statically into both executables.
/// Each feature that needs the engine adds its own `extension Engine` in its own file.
enum Engine {
    static func check(_ rawStatus: Int32) throws {
        guard rawStatus != 0 else { return }
        throw EngineError(status: EngineStatus(rawValue: rawStatus), rawValue: rawStatus)
    }

    /// The engine's version, read through the C ABI.
    static func version() throws -> String {
        var capacity = 32
        while true {
            var buffer = [CChar](repeating: 0, count: capacity)
            var length = 0
            let status = snapit_engine_version(&buffer, capacity, &length)
            if status == SNAPIT_STATUS_BUFFER_TOO_SMALL {
                capacity = length + 1
                continue
            }
            try check(status)
            return String(decoding: buffer[0..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }

    /// Makes the engine panic on purpose; the panic comes back as a status code.
    static func probePanic() -> EngineStatus? {
        EngineStatus(rawValue: snapit_engine_probe_panic())
    }
}
