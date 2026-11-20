import Foundation

/// Turns GitHub's reply (or the failure to get one) into the `UpdateAnswer` the update window
/// shows. The whole mapping:
///
/// | GitHub's reply | Answer |
/// |---|---|
/// | no connection, a lost connection | unreachable: offline |
/// | no answer in time | unreachable: timeout |
/// | HTTP 403 or 429 | unreachable: rate limit |
/// | HTTP 404 (no release published), a draft or a pre-release | unreachable: no release |
/// | any other status but 200, a body that is not JSON, no `tag_name`, a tag that is not `vX.Y.Z` | unreachable: bad response |
/// | a tag newer than snapit's bundle version | newer, with the notes and the release page |
/// | a tag equal to or older than it | up to date |
nonisolated enum UpdateAnswers {
    /// The release notes the window shows are cut here: a longer text is the release page's to read.
    static let notesLimit = 20_000

    /// The only page the Download button may open: a page of snapit's own repository.
    private static let downloadPrefix = "/k-electron/snapit/"

    static func answer(for result: Result<ReleaseResponse, ReleaseEndpointError>, installed: String) -> UpdateAnswer {
        let response: ReleaseResponse
        switch result {
        case .failure(.offline): return .unreachable(.offline)
        case .failure(.timeout): return .unreachable(.timeout)
        case .success(let value): response = value
        }
        switch response.status {
        case 200: break
        case 403, 429: return .unreachable(.rateLimit)
        case 404: return .unreachable(.noRelease)
        default: return .unreachable(.badResponse)
        }
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: response.body),
            let tag = release.tag_name, let version = ReleaseVersion(tag)
        else { return .unreachable(.badResponse) }
        // The endpoint never returns these; if it ever did, they are not an update.
        if release.draft == true || release.prerelease == true { return .unreachable(.noRelease) }
        guard let current = ReleaseVersion(installed) else { return .unreachable(.ownVersion) }
        guard version > current else { return .upToDate(installed: current.description) }
        return .newer(
            installed: current.description, version: version.description,
            downloadURL: downloadURL(release.html_url, tag: tag), notes: notes(release.body))
    }

    /// GitHub's `html_url` when it is a page of snapit's repository, else the release page of the tag.
    static func downloadURL(_ htmlURL: String?, tag: String) -> String {
        if let htmlURL, let url = URL(string: htmlURL), url.scheme == "https", url.host == "github.com",
            url.path.hasPrefix(downloadPrefix)
        {
            return url.absoluteString
        }
        let safeTag = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return "\(ReleaseRequest.releasesPage)/tag/\(safeTag)"
    }

    static func notes(_ body: String?) -> String {
        let text = (body ?? "").replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > notesLimit else { return text }
        return String(text.prefix(notesLimit)) + "…"
    }
}

/// The fields of GitHub's release object that Check for Updates reads.
nonisolated struct LatestRelease: Decodable {
    let tag_name: String?
    let body: String?
    let html_url: String?
    let draft: Bool?
    let prerelease: Bool?
}
