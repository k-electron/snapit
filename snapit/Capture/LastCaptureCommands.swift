import Foundation

nonisolated extension SocketCommand {
    /// `last-capture`: the Last Capture's number, or `none`. Test mode only.
    static let lastCapture = SocketCommand("last-capture")
    /// `menu-enabled <id>`: `yes` or `no`, whether the menu item with that id is enabled now
    /// (a greyed item is `no`). Test mode only.
    static let menuEnabled = SocketCommand("menu-enabled")
}

extension SocketCommandRegistry {
    func registerLastCaptureTestCommands() {
        guard TestMode.isActive else { return }
        register(.lastCapture) { _ in
            LastCapture.shared.number.map(String.init) ?? "none"
        }
        register(.menuEnabled) { request in
            guard let id = request.arguments.first,
                let entry = MenuModel.shared.entries.first(where: { $0.id == id })
            else { return "error no menu item \(request.arguments.first ?? "")" }
            return entry.isEnabled ? "yes" : "no"
        }
    }
}
