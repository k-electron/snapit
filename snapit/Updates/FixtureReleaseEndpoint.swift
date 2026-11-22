import Foundation

/// Test mode's endpoint: answers from a script (`update-script ...`), never goes online, and
/// writes each request it is asked to send to `<root>/update-requests`, one line each, so a run
/// can see exactly what the real endpoint would send (the method, the address and every header).
/// Unscripted it answers as if offline. The files of a release (`ReleaseRequest.asset`) are served
/// from `<root>/update-assets/`, by the name that ends the address, so a run puts the disk image
/// and its `.sha256` there; a name with no file there is a 404. A download can be parked part of
/// the way (`holdDownload`): the destination then holds that share of the file and the progress
/// callback has heard it, so a run sees the Update window's progress and can press Cancel.
@MainActor
final class FixtureReleaseEndpoint: ReleaseEndpoint {
    static let shared = FixtureReleaseEndpoint()

    enum Script {
        case response(status: Int, body: Data)
        case offline
        case timeout
    }

    var script = Script.offline
    /// When set, a download of a file writes part of it and then fails with this.
    var downloadFailure: ReleaseEndpointError?
    private(set) var requestCount = 0
    private let heldRequests = FixtureGate()
    private let heldDownloads = FixtureGate()
    private var held = false
    /// The share of a release file's download that is done while it is parked, 0 to 100; nil lets
    /// downloads finish.
    private var downloadHold: Int?
    /// What a parked download reports its progress to, and the file's size.
    private var parked: (progress: @Sendable (Int64, Int64?) -> Void, size: Int64)?

    func fetch(_ request: ReleaseRequest) async throws -> ReleaseResponse {
        requestCount += 1
        log(request)
        if held { try await heldRequests.wait() }
        switch script {
        case .response(let status, let body):
            guard let file = assetFile(for: request) else { return ReleaseResponse(status: status, body: body) }
            guard let contents = try? Data(contentsOf: file) else { return ReleaseResponse(status: 404, body: Data()) }
            return ReleaseResponse(status: 200, body: contents)
        case .offline: throw ReleaseEndpointError.offline
        case .timeout: throw ReleaseEndpointError.timeout
        }
    }

    func download(
        _ request: ReleaseRequest, to destination: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> Int {
        requestCount += 1
        log(request)
        if held { try await heldRequests.wait() }
        switch script {
        case .response:
            guard let file = assetFile(for: request), let contents = try? Data(contentsOf: file) else { return 404 }
            let size = Int64(contents.count)
            if let failure = downloadFailure {
                // A connection that drops half-way leaves what arrived.
                try? contents.prefix(max(contents.count / 2, 1)).write(to: destination)
                throw failure
            }
            if let share = downloadHold {
                do {
                    try contents.prefix(contents.count * share / 100).write(to: destination)
                } catch {
                    throw ReleaseEndpointError.cannotSave
                }
                progress(size * Int64(share) / 100, size)
                parked = (progress, size)
                defer { parked = nil }
                // Until `hold-download off`, or until the Update is cancelled, which throws here.
                while downloadHold != nil { try await heldDownloads.wait() }
            }
            do {
                try contents.write(to: destination)
            } catch {
                throw ReleaseEndpointError.cannotSave
            }
            progress(size, size)
            return 200
        case .offline: throw ReleaseEndpointError.offline
        case .timeout: throw ReleaseEndpointError.timeout
        }
    }

    /// The file a release file's address names, inside `<root>/update-assets/`; nil for any other
    /// address (the check's own).
    private func assetFile(for request: ReleaseRequest) -> URL? {
        guard request.url.path.contains("/releases/download/"), let root = TestMode.root else { return nil }
        return root.appendingPathComponent("update-assets", isDirectory: true)
            .appendingPathComponent(request.url.lastPathComponent)
    }

    /// While held, a request waits before it is answered, so a run can see a check in progress.
    func hold(_ on: Bool) {
        held = on
        if !on { heldRequests.release() }
    }

    /// Parks a download of a release file once `share` per cent of it is done (0 to 100), until
    /// `holdDownload(nil)`; a download already parked reports the new share. Nil lets downloads finish.
    func holdDownload(_ share: Int?) {
        downloadHold = share
        guard let share else { return heldDownloads.release() }
        if let parked { parked.progress(parked.size * Int64(share) / 100, parked.size) }
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

/// Test mode only: parks callers until released. A parked caller whose task is cancelled stops waiting and throws.
@MainActor
final class FixtureGate {
    private var waiting: [UUID: CheckedContinuation<Void, Error>] = [:]

    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiting[id] = continuation
                    }
                }
            },
            onCancel: {
                Task { @MainActor in self.cancel(id) }
            })
    }

    func release() {
        let resumed = waiting
        waiting = [:]
        for continuation in resumed.values { continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        waiting.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
