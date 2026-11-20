import SwiftUI

/// Renders `MenuModel` as the menu bar menu.
struct MenuBarContent: View {
    var body: some View {
        let entries = MenuModel.entries
        ForEach(entries.indices, id: \.self) { index in
            switch entries[index] {
            case .info(let title):
                Text(title)
            case .action(let title, let shortcut, let run):
                if let shortcut {
                    Button(title, action: run).keyboardShortcut(shortcut, modifiers: .command).help(title)
                } else {
                    Button(title, action: run).help(title)
                }
            case .separator:
                Divider()
            }
        }
    }
}
