import Foundation

/// Commands of Check for Updates. The menu bar app makes the one request and never opens a
/// window; the Editor helper shows the update window and asks the menu bar app for the answer.
nonisolated extension SocketCommand {
    /// The menu bar app asks the Editor helper to show the update window and check: the window
    /// opens saying it is checking, the helper sends `check-for-updates`, and the window shows the
    /// answer. A check already running is not started again. Replies `ok` once the window is on
    /// screen, not when the answer is in.
    static let showUpdateCheck = SocketCommand("show-update-check")
    /// The helper asks the menu bar app to check: the one request snapit sends, to GitHub's latest
    /// release. Replies with an `UpdateAnswer`'s wire form once GitHub has answered or failed.
    static let checkForUpdates = SocketCommand("check-for-updates")
    /// `install-update <version>`: the helper asks the menu bar app to run the Update to the release
    /// its window announced (`<version>` is the `X.Y.Z` the window shows; the menu bar app installs
    /// only the release its own check announced, and refuses any other). The reply comes when the
    /// new copy has been started, or when the Update stopped: `ok`, or `error <cause> <description>`
    /// (the cause is one word) with the installed copy as it was. A successful Update quits the helper before the reply goes out, so
    /// the helper may never hear it.
    static let installUpdate = SocketCommand("install-update")
    /// The helper asks the menu bar app whether this copy can update itself where it runs: `yes`, or
    /// `no` on a disk image or in a folder snapit cannot write to (the window then says "Move snapit
    /// to Applications to update it here" in place of Update and Relaunch).
    static let updateCanInstall = SocketCommand("update-can-install")
}
