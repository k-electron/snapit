import Foundation

/// A request to GitHub. There are two kinds, and only a click on Check for Updates… starts either:
/// the check itself (`latest`: GET GitHub's latest-release endpoint, which skips drafts and
/// pre-releases) and, when the user then chooses Update and Relaunch, the two files of the release
/// that was announced (`asset`: its disk image and that image's `.sha256`). snapit sets three
/// headers: a generic User-Agent (GitHub requires one), Accept, and a fixed Accept-Language, so
/// the user's own languages are not sent. There is no token and there are no cookies. The
/// system's HTTP client adds its own transport headers (Host, Accept-Encoding, Connection); snapit
/// adds nothing about the user or the machine.
nonisolated struct ReleaseRequest: Sendable {
    /// Where a redirect of the request may lead.
    enum Redirects: Sendable {
        /// Only to the same host (GitHub redirects a renamed repository within `api.github.com`).
        case sameHost
        /// The same host, or GitHub's download host: a release file's address on github.com
        /// redirects to `release-assets.githubusercontent.com`.
        case toGitHubDownloads
    }

    let url: URL
    let headers: [String: String]
    /// How long the connection may stay silent.
    let timeout: TimeInterval
    var redirects = Redirects.sameHost
    /// How long the whole transfer may take; without it, `timeout` plus 5 seconds.
    var totalTimeout: TimeInterval?

    static let latest = ReleaseRequest(
        url: URL(string: "https://api.github.com/repos/k-electron/snapit/releases/latest")!,
        headers: [
            "User-Agent": "snapit", "Accept": "application/vnd.github+json", "Accept-Language": "en",
        ],
        timeout: 10)

    /// The release page snapit opens for a tag: `<this>/tag/<tag>`.
    static let releasesPage = "https://github.com/k-electron/snapit/releases"

    /// A file of the release announced as `tag`: `<releases page>/download/<tag>/<name>`. The address
    /// is built here from the tag that `ReleaseVersion` accepted, never taken from anything GitHub's
    /// reply says.
    static func asset(tag: String, name: String) -> ReleaseRequest? {
        guard let url = URL(string: "\(releasesPage)/download/\(tag)/\(name)") else { return nil }
        return ReleaseRequest(
            url: url,
            headers: ["User-Agent": "snapit", "Accept": "application/octet-stream", "Accept-Language": "en"],
            timeout: 30, redirects: .toGitHubDownloads, totalTimeout: 900)
    }

    /// Whether a redirect of this request may be followed: always to https with no port and no user
    /// name, and then to the hosts the request's `redirects` names.
    func allowsRedirect(to target: URL) -> Bool {
        let components = URLComponents(url: target, resolvingAgainstBaseURL: false)
        guard components?.scheme == "https", components?.port == nil, components?.user == nil,
            components?.password == nil, let host = components?.host?.lowercased()
        else { return false }
        let sameHost = host == url.host?.lowercased()
        switch redirects {
        case .sameHost: return sameHost
        case .toGitHubDownloads: return sameHost || host.hasSuffix(".githubusercontent.com")
        }
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
    /// A download arrived but could not be put where it was to go.
    case cannotSave
}

/// Where the request goes. Always go through `ReleaseEndpoints.current`: `GitHubReleaseEndpoint`
/// is the only code in snapit that talks to a network, and a scripted run swaps in
/// `FixtureReleaseEndpoint`, which answers from a script and never goes online.
@MainActor
protocol ReleaseEndpoint {
    func fetch(_ request: ReleaseRequest) async throws -> ReleaseResponse
    /// Downloads the response body into the file at `destination` (which must not exist yet) and
    /// returns the HTTP status. Only a 200 leaves a file there.
    func download(_ request: ReleaseRequest, to destination: URL) async throws -> Int
}

@MainActor
enum ReleaseEndpoints {
    static let current: any ReleaseEndpoint = TestMode.isActive ? FixtureReleaseEndpoint.shared : GitHubReleaseEndpoint()
}
