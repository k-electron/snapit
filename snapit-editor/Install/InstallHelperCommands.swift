import AppKit

nonisolated extension SocketCommand {
    /// Replies with facts about the "Move snapit to Applications" screen, one `key=value` line
    /// each (`window`, `title`, `state`, `reason`, `replaces`, `message`) and one
    /// `button <id>|<title>|<tooltip>` line per button. Test mode only.
    static let moveScreenFacts = SocketCommand("move-screen-facts")
    /// `move-screen-press move|later`: presses a button of the screen. Replies with the menu
    /// bar app's reply for `move`, `ok` for `later`. Test mode only.
    static let moveScreenPress = SocketCommand("move-screen-press")
}

extension SocketCommandRegistry {
    func registerInstallHelperCommands() {
        register(.showMoveToApplications) { request in
            let arguments = request.arguments
            guard arguments.count == 2, let reason = MoveToApplicationsModel.Reason(rawValue: arguments[0]) else {
                return "error show-move-to-applications disk-image|temporary replace|new"
            }
            MoveToApplicationsScreen.show(reason: reason, replacesExisting: arguments[1] == "replace")
            return "ok"
        }
        guard TestMode.isActive else { return }
        register(.moveScreenFacts) { _ in
            guard let screen = MoveToApplicationsScreen.shared, let window = screen.window else { return "window=none" }
            let model = screen.model
            var lines = [
                "window=\(window.isVisible ? "visible" : "hidden")",
                "title=\(model.title)",
                "state=\(model.state.name)",
                "reason=\(model.reason.rawValue)",
                "replaces=\(model.replacesExisting)",
                "message=\(model.message)",
                "activation=\(NSApp.activationPolicy() == .regular ? "regular" : "accessory")",
            ]
            lines += model.buttons.map(\.factsLine)
            return lines.joined(separator: "\n")
        }
        register(.moveScreenPress) { request in
            guard let screen = MoveToApplicationsScreen.shared else { return "error no Move to Applications screen" }
            switch request.arguments.first {
            case "move": return await screen.model.move()
            case "later":
                screen.model.later()
                return "ok"
            default: return "error move-screen-press move|later"
            }
        }
    }
}
