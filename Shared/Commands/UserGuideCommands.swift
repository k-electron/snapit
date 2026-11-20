import Foundation

/// Commands of the User Guide. The menu bar app never opens a window: it asks the Editor helper to
/// show the guide, which the helper reads from its own bundle.
nonisolated extension SocketCommand {
    /// The menu bar app asks the Editor helper to show the User Guide, or to bring it forward when
    /// it is already open. Replies `ok` once the window is on screen.
    static let showUserGuide = SocketCommand("show-user-guide")
}
