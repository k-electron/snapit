import Foundation

/// The one request Check for Updates sends: GET GitHub's latest-release endpoint, which skips
/// drafts and pre-releases. Only a click on Check for Updates… makes it. snapit sets three headers:
/// a generic User-Agent (GitHub requires one), Accept, and a fixed Accept-Language, so the
/// user's own languages are not sent. There is no token and there are no cookies. The system's
/// HTTP client adds its own transport headers (Host, Accept-Encoding, Connection); snapit adds
/// nothing about the user or the machine. A redirect to anywhere but the same host is refused.
nonisolated struct ReleaseRequest: Sendable {
    let url: URL
    let headers: [String: String]
    let timeout: TimeInterval

    static let latest = ReleaseRequest(
        url: URL(string: "https://api.github.com/repos/k-electron/snapit/releases/latest")!,
        headers: [
            "User-Agent": "snapit", "Accept": "application/vnd.github+json", "Accept-Language": "en",
        ],
        timeout: 10)

    /// The release page snapit opens for a tag: `<this>/tag/<tag>`.
    static let releasesPage = "https://github.com/k-electron/snapit/releases"

    /// Whether a redirect of this request may be followed: only to the same host, scheme and
    /// port (GitHub redirects a renamed repository within `api.github.com`), with no user name.
    func allowsRedirect(to target: URL) -> Bool {
        let components = URLComponents(url: target, resolvingAgainstBaseURL: false)
        return components?.scheme == "https" && components?.host == url.host && components?.port == nil
            && components?.user == nil && components?.password == nil
    }
}

nonisolated struct ReleaseResponse: Sendable {
    let status: Int
    let body: Data
}

nonisolated enum ReleaseEndpointError: Error, Sendable {
    /// No connection, a refused or lost one, or a name that does not resolve.
    case offline
    case timeout
}

/// Where the request goes. Always go through `ReleaseEndpoints.current`: `GitHubReleaseEndpoint`
/// is the only code in snapit that talks to a network, and a scripted run swaps in
/// `FixtureReleaseEndpoint`, which answers from a script and never goes online.
@MainActor
protocol ReleaseEndpoint {
    func fetch(_ request: ReleaseRequest) async throws -> ReleaseResponse
}

@MainActor
enum ReleaseEndpoints {
    static let current: any ReleaseEndpoint = TestMode.isActive ? FixtureReleaseEndpoint.shared : GitHubReleaseEndpoint()
}
