import SwiftUI

/// Renders `MenuModel` as the menu bar menu.
struct MenuBarContent: View {
    private let model = MenuModel.shared

    var body: some View {
        ForEach(model.entries) { entry in
            switch entry.kind {
            case .info:
                Text(entry.title ?? "")
            case .action:
                Button(entry.title ?? "") { Task { await entry.run?() } }
                    .keyboardShortcut(entry.shortcut)
                    .disabled(!entry.isEnabled)
                    .help(entry.title ?? "")
            case .separator:
                Divider()
            }
        }
    }
}
