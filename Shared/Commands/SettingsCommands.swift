import Foundation

/// Commands of the Settings window. The menu bar app never opens a window: it asks the Editor
/// helper to show Settings, and the helper asks the menu bar app for the things only it can do
/// (Open at Login, applying a Shortcut).
nonisolated extension SocketCommand {
    /// The menu bar app asks the Editor helper to show Settings, or to bring it forward when it
    /// is already open. Replies `ok` once the window is on screen.
    static let showSettings = SocketCommand("show-settings")
    /// The helper asks the menu bar app whether snapit opens at login. Replies `enabled`,
    /// `notRegistered`, `requiresApproval` or `notFound`.
    static let loginItemStatus = SocketCommand("login-item-status")
    /// `login-item-set on|off`: the helper asks the menu bar app to register or unregister
    /// `SMAppService.mainApp`. Replies the status that follows, or `error <why>`.
    static let loginItemSet = SocketCommand("login-item-set")
    /// `apply-shortcut <id> none|<key code> [<modifier>,...]`: the helper tells the menu bar app
    /// the user recorded a Shortcut; it rebinds the Shortcut and the menu glyph follows. Replies `ok`.
    static let applyShortcut = SocketCommand("apply-shortcut")
    /// The helper asks which key combination each Shortcut of `ShortcutCatalog` has now, as the
    /// menu bar app's registrar reports it. Replies one `<id> none|<key code> [<modifier>,...]`
    /// line per Shortcut.
    static let shortcutCombos = SocketCommand("shortcut-combos")
}

/// What `SMAppService.mainApp` reports.
nonisolated enum LoginItemStatus: String, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}
