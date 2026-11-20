import Foundation

/// Test mode's endpoint: answers from a script (`update-script ...`), never goes online, and
/// writes each request it is asked to send to `<root>/update-requests`, one line each, so a run
/// can see exactly what the real endpoint would send (the method, the address and every header).
/// Unscripted it answers as if offline.
@MainActor
final class FixtureReleaseEndpoint: ReleaseEndpoint {
    static let shared = FixtureReleaseEndpoint()

    enum Script {
        case response(status: Int, body: Data)
        case offline
        case timeout
    }

    var script = Script.offline
    private(set) var requestCount = 0
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func fetch(_ request: ReleaseRequest) async throws -> ReleaseResponse {
        requestCount += 1
        log(request)
        if held { await withCheckedContinuation { waiting.append($0) } }
        switch script {
        case .response(let status, let body): return ReleaseResponse(status: status, body: body)
        case .offline: throw ReleaseEndpointError.offline
        case .timeout: throw ReleaseEndpointError.timeout
        }
    }

    /// While held, a request waits before it is answered, so a run can see a check in progress.
    func hold(_ on: Bool) {
        held = on
        guard !on else { return }
        let resumed = waiting
        waiting = []
        for continuation in resumed { continuation.resume() }
    }

    private func log(_ request: ReleaseRequest) {
        guard let root = TestMode.root else { return }
        let headers = request.headers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let line = Data("GET \(request.url.absoluteString) timeout=\(Int(request.timeout)) \(headers)\n".utf8)
        let file = root.appendingPathComponent("update-requests")
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }
}
