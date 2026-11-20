import AppKit
import SwiftUI

/// A separator, then Quit snapit, last in the menu.
struct QuitMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .separator(id: "quit.separator"),
            .action(id: "quit", "Quit snapit", shortcut: KeyboardShortcut("q")) {
                NSApplication.shared.terminate(nil)
            },
        ]
    }
}
