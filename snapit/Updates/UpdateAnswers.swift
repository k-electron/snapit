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
/// | any other status but 200 (a refused redirect included), a body that is not JSON, no `tag_name`, a tag that is not `vX.Y.Z` | unreachable: bad response |
/// | a tag newer than snapit's bundle version | newer, with the notes and the release page of the tag |
/// | a tag equal to or older than it | up to date |
nonisolated enum UpdateAnswers {
    /// The release notes the window shows are cut at this many lines and this many UTF-8 bytes,
    /// whichever comes first: a longer text is the release page's to read.
    static let notesLineLimit = 300
    static let notesByteLimit = 20_000

    static func answer(for result: Result<ReleaseResponse, ReleaseEndpointError>, installed: String) -> UpdateAnswer {
        decide(for: result, installed: installed).answer
    }

    /// The answer, and for a newer release the release it announces: the one an Update installs.
    static func decide(
        for result: Result<ReleaseResponse, ReleaseEndpointError>, installed: String
    ) -> (answer: UpdateAnswer, announced: AnnouncedRelease?) {
        let response: ReleaseResponse
        switch result {
        case .failure(.offline), .failure(.cannotSave): return (.unreachable(.offline), nil)
        case .failure(.timeout): return (.unreachable(.timeout), nil)
        case .success(let value): response = value
        }
        switch response.status {
        case 200: break
        case 403, 429: return (.unreachable(.rateLimit), nil)
        case 404: return (.unreachable(.noRelease), nil)
        default: return (.unreachable(.badResponse), nil)
        }
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: response.body),
            let tag = release.tag_name, let version = ReleaseVersion(tag)
        else { return (.unreachable(.badResponse), nil) }
        // The endpoint never returns these; if it ever did, they are not an update.
        if release.draft == true || release.prerelease == true { return (.unreachable(.noRelease), nil) }
        guard let current = ReleaseVersion(installed) else { return (.unreachable(.ownVersion), nil) }
        guard version > current else { return (.upToDate(installed: current.description), nil) }
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            .newer(
                installed: current.description, version: version.description,
                releasePage: releasePage(tag: tag), notes: notes(release.body)),
            AnnouncedRelease(tag: trimmedTag, version: version.description)
        )
    }

    /// The release page of a tag in snapit's repository. Built here from the tag that
    /// `ReleaseVersion` accepted (digits, dots and a leading `v`), never taken from GitHub's
    /// `html_url`: a link in a reply is not trusted to point anywhere.
    static func releasePage(tag: String) -> String {
        "\(ReleaseRequest.releasesPage)/tag/\(tag.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func notes(_ body: String?) -> String {
        var text = (body ?? "").replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var cut = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > notesLineLimit {
            text = lines.prefix(notesLineLimit).joined(separator: "\n")
            cut = true
        }
        var bytes = 0
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            bytes += String(scalar).utf8.count
            if bytes > notesByteLimit {
                cut = true
                break
            }
            kept.append(scalar)
        }
        return cut ? String(kept) + "…" : String(kept)
    }
}

/// The fields of GitHub's release object that Check for Updates reads. Its `html_url` is not one:
/// the Release Page link is built from the tag.
nonisolated struct LatestRelease: Decodable {
    let tag_name: String?
    let body: String?
    let draft: Bool?
    let prerelease: Bool?
}
