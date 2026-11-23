import Foundation

/// The release the Update window announced, as the menu bar app holds it: what an Update
/// installs. Its files are named by the version (`snapit-X.Y.Z.dmg` and its `.sha256`) and found
/// under the tag, at addresses built here from the tag, never from anything GitHub's reply says.
nonisolated struct AnnouncedRelease: Equatable, Sendable {
    /// The release's tag as GitHub wrote it (`v1.2.3`), trimmed.
    let tag: String
    /// The version, `X.Y.Z`.
    let version: String

    var diskImageName: String { "snapit-\(version).dmg" }
    var hashName: String { diskImageName + ".sha256" }

    var diskImageRequest: ReleaseRequest? { .asset(tag: tag, name: diskImageName) }
    var hashRequest: ReleaseRequest? { .asset(tag: tag, name: hashName) }
}
