import Foundation

/// What Check for Updates found: the one answer the menu bar app gives the update window. The
/// menu bar app makes the only request snapit sends and decides the answer
/// (`snapit/Updates/UpdateAnswers.swift`); the Editor helper only shows it, so the answer travels
/// over the command socket as the reply of `check-for-updates`:
///
///     state=newer            (or up-to-date, or unreachable)
///     installed=0.1.0
///     version=0.2.0
///     url=https://github.com/k-electron/snapit/releases/tag/v0.2.0
///     reason=offline         (unreachable only)
///
///     <the release notes, verbatim>
nonisolated enum UpdateAnswer: Equatable, Sendable {
    /// Why snapit has no answer. The window words each one as a single line.
    enum Reason: String, Sendable {
        /// No connection, or the connection was lost.
        case offline
        /// GitHub did not answer in time.
        case timeout
        /// GitHub is limiting requests (HTTP 403 or 429).
        case rateLimit = "rate-limit"
        /// GitHub has no release to compare with: none published, or the newest is a draft or a
        /// pre-release.
        case noRelease = "no-release"
        /// GitHub's answer was not JSON, or lacked a tag of the form `vX.Y.Z`.
        case badResponse = "bad-response"
        /// snapit's own bundle version is not three integers.
        case ownVersion = "own-version"
        /// The menu bar app did not answer the Editor helper.
        case noAnswer = "no-answer"
    }

    /// A newer release: its version, its notes (Markdown) and the page the Download button opens.
    case newer(installed: String, version: String, downloadURL: String, notes: String)
    case upToDate(installed: String)
    case unreachable(Reason)

    var wire: String {
        switch self {
        case .newer(let installed, let version, let downloadURL, let notes):
            "state=newer\ninstalled=\(installed)\nversion=\(version)\nurl=\(downloadURL)\n\n\(notes)"
        case .upToDate(let installed):
            "state=up-to-date\ninstalled=\(installed)"
        case .unreachable(let reason):
            "state=unreachable\nreason=\(reason.rawValue)"
        }
    }

    init?(wire: String) {
        let parts = wire.components(separatedBy: "\n\n")
        let notes = parts.dropFirst().joined(separator: "\n\n")
        var fields = [String: String]()
        for line in (parts.first ?? "").split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        switch fields["state"] {
        case "newer":
            guard let installed = fields["installed"], let version = fields["version"], let url = fields["url"]
            else { return nil }
            self = .newer(installed: installed, version: version, downloadURL: url, notes: notes)
        case "up-to-date":
            guard let installed = fields["installed"] else { return nil }
            self = .upToDate(installed: installed)
        case "unreachable":
            guard let reason = fields["reason"].flatMap(Reason.init(rawValue:)) else { return nil }
            self = .unreachable(reason)
        default:
            return nil
        }
    }
}
