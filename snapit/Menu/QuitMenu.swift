import AppKit
import SwiftUI

/// Quit snapit, last in the menu.
struct QuitMenu: MenuSection {
    var entries: [MenuEntry] {
        [.action(id: "quit", "Quit snapit", shortcut: KeyboardShortcut("q")) {
            NSApplication.shared.terminate(nil)
        }]
    }
}
