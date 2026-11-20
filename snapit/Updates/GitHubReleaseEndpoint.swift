import Foundation

/// The real endpoint, and the only file in snapit that opens a network connection (`scripts/check-network.sh`
/// fails the repo checks if any other file does). One request on an ephemeral session: no
/// cache, no cookies, no stored credentials, nothing kept on disk. A redirect is followed only
/// within the same host (`ReleaseRequest.allowsRedirect`); a refused one ends the request with
/// the redirect's own status, which the answer reads as a bad response. The session is
/// invalidated as soon as the request ends, so nothing stays alive between clicks.
struct GitHubReleaseEndpoint: ReleaseEndpoint {
    func fetch(_ request: ReleaseRequest) async throws -> ReleaseResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.timeout + 5
        let session = URLSession(configuration: configuration, delegate: RedirectGuard(request), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var urlRequest = URLRequest(
            url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeout)
        urlRequest.httpMethod = "GET"
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw ReleaseEndpointError.offline }
            return ReleaseResponse(status: http.statusCode, body: data)
        } catch let error as URLError {
            throw error.code == .timedOut ? ReleaseEndpointError.timeout : ReleaseEndpointError.offline
        }
    }
}

/// Refuses a redirect that leaves the request's host.
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
