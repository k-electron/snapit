import Foundation

/// The one request Check for Updates sends: GET GitHub's latest-release endpoint, which skips
/// drafts and pre-releases. Only a click on Check for Updates… makes it. The request carries a
/// generic User-Agent (GitHub requires one) and nothing else about the user or the machine: no
/// token, no cookies.
nonisolated struct ReleaseRequest: Sendable {
    let url: URL
    let headers: [String: String]
    let timeout: TimeInterval

    static let latest = ReleaseRequest(
        url: URL(string: "https://api.github.com/repos/k-electron/snapit/releases/latest")!,
        headers: ["User-Agent": "snapit", "Accept": "application/vnd.github+json"],
        timeout: 10)

    /// The release page snapit opens when GitHub's own link cannot be used.
    static let releasesPage = "https://github.com/k-electron/snapit/releases"
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
