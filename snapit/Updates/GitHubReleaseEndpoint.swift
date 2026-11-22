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
        let session = Self.makeSession(for: request)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: Self.urlRequest(for: request))
            guard let http = response as? HTTPURLResponse else { throw ReleaseEndpointError.offline }
            return ReleaseResponse(status: http.statusCode, body: data)
        } catch let error as URLError {
            throw Self.endpointError(for: error)
        }
    }

    func download(_ request: ReleaseRequest, to destination: URL) async throws -> Int {
        let session = Self.makeSession(for: request)
        defer { session.finishTasksAndInvalidate() }
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await session.download(for: Self.urlRequest(for: request))
        } catch let error as URLError {
            throw Self.endpointError(for: error)
        }
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: temporary)
            throw ReleaseEndpointError.offline
        }
        guard http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            return http.statusCode
        }
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw ReleaseEndpointError.cannotSave
        }
        return 200
    }

    private static func makeSession(for request: ReleaseRequest) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.totalTimeout ?? request.timeout + 5
        return URLSession(configuration: configuration, delegate: RedirectGuard(request), delegateQueue: nil)
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
