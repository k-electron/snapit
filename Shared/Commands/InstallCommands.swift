import Foundation

/// Commands of the install location check ("Move snapit to Applications").
nonisolated extension SocketCommand {
    /// `show-move-to-applications <reason> <replaces>`: the menu bar app asks the Editor helper to
    /// show the "Move snapit to Applications" screen. `<reason>` is `disk-image` or `temporary`,
    /// `<replaces>` is `replace` when a copy already sits in Applications, else `new`.
    /// Replies `ok` once the window shows.
    static let showMoveToApplications = SocketCommand("show-move-to-applications")
    /// The helper tells the menu bar app the user chose Move to Applications. The menu bar app
    /// copies itself, strips quarantine, relaunches from Applications and ejects the disk image.
    /// Replies `ok` just before it quits, or `error <message>`.
    static let moveToApplications = SocketCommand("move-to-applications")
    /// Replies with where the menu bar app runs from, one `key=value` line each: `bundle`,
    /// `translocated`, `origin`, `on-disk-image`, `mount`, `decision`.
    static let installLocation = SocketCommand("install-location")
}
