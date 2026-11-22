import Foundation

/// The real endpoint, and the only file in snapit that opens a network connection (`scripts/check-network.sh`
/// fails the repo checks if any other file does). It sends two kinds of request, both made only
/// after a click on Check for Updates…: the check's one request, and the download of the files of
/// the release the window announced (`ReleaseRequest.asset`). Each is one request on an ephemeral
/// session: no cache, no cookies, no stored credentials, nothing kept on disk but the file asked
/// for. A redirect is followed only where the request's own policy allows (`ReleaseRequest.allowsRedirect`);
/// a refused one ends the request with the redirect's own status, which the answer reads as a bad
/// response. The session is invalidated as soon as the request ends, so nothing stays alive between
/// clicks.
struct GitHubReleaseEndpoint: ReleaseEndpoint {
    func fetch(_ request: ReleaseRequest) async throws -> ReleaseResponse {
        let session = Self.makeSession(for: request, delegate: RedirectGuard(request))
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: Self.urlRequest(for: request))
            guard let http = response as? HTTPURLResponse else { throw ReleaseEndpointError.offline }
            return ReleaseResponse(status: http.statusCode, body: data)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw Self.endpointError(for: error)
        }
    }

    func download(
        _ request: ReleaseRequest, to destination: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> Int {
        let delegate = DownloadDelegate(request, destination: destination, progress: progress)
        let session = Self.makeSession(for: request, delegate: delegate)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: Self.urlRequest(for: request))
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.begin(continuation)
                    task.resume()
                    if Task.isCancelled { task.cancel() }
                }
            } onCancel: {
                task.cancel()
            }
        } catch let error as URLError {
            // A cancelled transfer leaves no file: the system deletes its temporary one.
            if error.code == .cancelled { throw CancellationError() }
            throw Self.endpointError(for: error)
        }
    }

    private static func makeSession(for request: ReleaseRequest, delegate: URLSessionDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.totalTimeout ?? request.timeout + 5
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private static func urlRequest(for request: ReleaseRequest) -> URLRequest {
        var urlRequest = URLRequest(
            url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeout)
        urlRequest.httpMethod = "GET"
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        return urlRequest
    }

    private static func endpointError(for error: URLError) -> ReleaseEndpointError {
        error.code == .timedOut ? .timeout : .offline
    }
}

/// Refuses a redirect that the request's policy does not allow.
private nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let request: ReleaseRequest

    init(_ request: ReleaseRequest) { self.request = request }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(newRequest.url.map(request.allowsRedirect(to:)) == true ? newRequest : nil)
    }
}

/// A download task's delegate: refuses the redirects the request's policy does not allow, reports
/// how many bytes have arrived, moves the file to its destination the moment the system hands it
/// over (it deletes its own copy when that callback returns) and ends the transfer's one
/// continuation with the HTTP status, or with the error that stopped it.
private nonisolated final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let request: ReleaseRequest
    private let destination: URL
    private let progress: @Sendable (Int64, Int64?) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int, Error>?
    private var status = 0
    private var saveFailed = false

    init(_ request: ReleaseRequest, destination: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.request = request
        self.destination = destination
        self.progress = progress
    }

    func begin(_ continuation: CheckedContinuation<Int, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(newRequest.url.map(request.allowsRedirect(to:)) == true ? newRequest : nil)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        var failed = false
        if code == 200 {
            do {
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                failed = true
            }
        }
        lock.withLock {
            status = code
            saveFailed = failed
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, status, saveFailed) = lock.withLock { () -> (CheckedContinuation<Int, Error>?, Int, Bool) in
            defer { self.continuation = nil }
            return (self.continuation, self.status, self.saveFailed)
        }
        if let error {
            continuation?.resume(throwing: error)
        } else if saveFailed {
            continuation?.resume(throwing: ReleaseEndpointError.cannotSave)
        } else if status == 0 {
            continuation?.resume(throwing: ReleaseEndpointError.offline)
        } else {
            continuation?.resume(returning: status)
        }
    }
}
