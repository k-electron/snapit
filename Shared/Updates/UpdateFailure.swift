import Foundation

/// Why an Update stopped, as the Update window words it: one line naming the cause. The menu bar
/// app's reply to `install-update` leads with one word for the cause (`error <cause> <description>`);
/// a cause with no line of its own of the ones below is `.other`. Whatever the cause, the installed
/// snapit is as it was and no file of the Update is left behind.
nonisolated enum UpdateFailure: String, Equatable, Sendable {
    /// GitHub could not be reached, or the connection was lost mid-download.
    case offline
    /// GitHub did not answer, or the download stalled.
    case timeout
    /// The download does not match the hash the release publishes.
    case hashMismatch = "hash-mismatch"
    /// The downloaded bundle is not snapit: its bundle identifier is another.
    case wrongIdentifier = "wrong-identifier"
    /// The downloaded bundle's version is not the release tag the Update window announced.
    case wrongVersion = "wrong-version"
    /// The downloaded bundle's signature is not valid, nested code (the Editor helper) included.
    case badSignature = "bad-signature"
    /// The disk image would not open, or holds no snapit.
    case diskImage = "disk-image"
    /// The swap failed.
    case swap
    /// This copy of snapit cannot update itself where it runs: on a disk image, or in a folder it
    /// cannot write to.
    case notHere = "not-here"
    /// The menu bar app did not answer.
    case noAnswer = "no-answer"
    case other

    /// The cause a reply names; `.other` for a word with no line of its own.
    init(cause: String) { self = UpdateFailure(rawValue: cause) ?? .other }

    /// "Move snapit to Applications to update it here": what the Update window says in place of
    /// Update and Relaunch when this copy cannot update itself where it runs.
    static let moveLine = "Move snapit to Applications to update it here"

    /// The one line the Update window shows.
    var line: String {
        switch self {
        case .offline: "Couldn't reach GitHub. Your snapit was not changed."
        case .timeout: "GitHub took too long to answer. Your snapit was not changed."
        case .hashMismatch: "The download was damaged, so it was not installed."
        case .wrongIdentifier: "The download is not snapit, so it was not installed."
        case .wrongVersion: "The download is not the version announced, so it was not installed."
        case .badSignature: "The download's signature is not valid, so it was not installed."
        case .diskImage: "The download could not be opened, so it was not installed."
        case .swap: "snapit couldn't replace itself. Your snapit was not changed."
        case .notHere: Self.moveLine
        case .noAnswer: "snapit didn't answer. Quit snapit and open it again."
        case .other: "The Update couldn't finish. Your snapit was not changed."
        }
    }
}
