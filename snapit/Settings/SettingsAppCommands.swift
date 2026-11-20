import Foundation

nonisolated extension SocketCommand {
    /// `login-item-simulate enabled|notRegistered|requiresApproval|notFound`: sets the fake
    /// login item's status, as the user doing it in System Settings would. Test mode only.
    static let loginItemSimulate = SocketCommand("login-item-simulate")
}

extension SocketCommandRegistry {
    /// What the helper's Settings window asks of the menu bar app.
    func registerSettingsAppCommands() {
        register(.loginItemStatus) { _ in LoginItem.current.status.rawValue }
        register(.loginItemSet) { request in
            guard let value = request.arguments.first, value == "on" || value == "off" else {
                return "error login-item-set on|off"
            }
            do {
                if value == "on" { try LoginItem.current.register() } else { try LoginItem.current.unregister() }
                return LoginItem.current.status.rawValue
            } catch {
                return "error \(error.localizedDescription)"
            }
        }
        register(.applyShortcut) { request in
            guard let id = request.arguments.first, let entry = ShortcutCatalog.entry(id: id) else {
                return "error no shortcut \(request.arguments.first ?? "")"
            }
            guard let combo = ShortcutCombo.parse(wire: Array(request.arguments.dropFirst())) else {
                return "error apply-shortcut <id> none|<key code> [<modifier>,...]"
            }
            Shortcuts.current.setCombo(combo, for: entry.shortcut)
            return "ok"
        }
        guard TestMode.isActive else { return }
        register(.loginItemSimulate) { request in
            guard let status = request.arguments.first.flatMap(LoginItemStatus.init(rawValue:)) else {
                return "error login-item-simulate enabled|notRegistered|requiresApproval|notFound"
            }
            FakeLoginItem.shared.simulate(status)
            return "ok"
        }
    }
}
