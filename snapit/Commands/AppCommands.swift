import Foundation
import SwiftUI

nonisolated extension SocketCommand {
    /// Replies with the titles of the menu bar menu, one per line ("-" for a separator).
    /// The scripted run reads the menu through it. Test mode only.
    static let menuTitles = SocketCommand("menu-titles")
    /// `menu-click <id>`: runs the action of the menu item with that id, as choosing it
    /// does, and replies `ok` when the action has finished. Test mode only.
    static let menuClick = SocketCommand("menu-click")
    /// `menu-shortcut <id>`: replies `<character> <modifiers, comma separated>`, the key
    /// equivalent the menu item shows now, or `none`. Test mode only.
    static let menuShortcut = SocketCommand("menu-shortcut")
    /// Starts the Editor helper, marked as started by snapit, and replies `ok`. Test mode only.
    static let startEditor = SocketCommand("start-editor")
}

extension SocketCommandRegistry {
    /// Registers the commands only the menu bar app answers. A feature adds its own
    /// `register…Commands()` in its own file and calls it here with one line.
    func registerAppCommands() {
        registerMenuCommands()
        registerEditorHelperCommands()
        registerCaptureTestCommands()
        registerCaptureDeleteCommands()
        registerLastCaptureTestCommands()
        registerSaveCommands()
        registerAreaTestCommands()
        registerWindowTestCommands()
        registerEditorActivationTestCommands()
        registerEditorWarmUpTestCommands()
        registerShortcutTestCommands()
        registerInstallCommands()
        registerSettingsAppCommands()
        registerOnboardingAppCommands()
        registerUpdateAppCommands()
    }

    private func registerMenuCommands() {
        guard TestMode.isActive else { return }
        register(.menuTitles) { _ in
            MenuModel.shared.entries.map { $0.title ?? "-" }.joined(separator: "\n")
        }
        register(.menuClick) { request in
            await Self.withMenuEntry(request) { entry in
                guard entry.isEnabled, let run = entry.run else { return "error menu item is disabled" }
                await run()
                return "ok"
            }
        }
        register(.menuShortcut) { request in
            await Self.withMenuEntry(request) { entry in
                guard let shortcut = entry.shortcut else { return "none" }
                let names: [(EventModifiers, String)] = [
                    (.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "command"),
                ]
                let modifiers = names.filter { shortcut.modifiers.contains($0.0) }.map(\.1)
                return "\(shortcut.key.character) \(modifiers.joined(separator: ","))"
            }
        }
    }

    /// Runs `body` on the menu item a `menu-click` or `menu-shortcut` request names, or replies the error.
    private static func withMenuEntry(
        _ request: SocketRequest, _ body: @MainActor (MenuEntry) async -> String
    ) async -> String {
        let id = request.arguments.first ?? ""
        guard let entry = MenuModel.shared.entries.first(where: { $0.id == id }) else {
            return "error no menu item \(id)"
        }
        return await body(entry)
    }

    private func registerEditorHelperCommands() {
        guard TestMode.isActive else { return }
        register(.startEditor) { _ in
            do {
                try await EditorHelperLauncher.start()
                return "ok"
            } catch {
                return "error \(error)"
            }
        }
    }
}
