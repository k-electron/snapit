import AppKit

/// Quit snapit, last in the menu.
@MainActor
enum QuitMenu {
    static var entries: [MenuEntry] {
        [.action(title: "Quit snapit", shortcut: "q") { NSApplication.shared.terminate(nil) }]
    }
}
