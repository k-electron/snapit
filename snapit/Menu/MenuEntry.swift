import SwiftUI

/// One row of the menu bar menu.
struct MenuEntry: Identifiable {
    enum Kind { case action, separator }

    let id: String
    let kind: Kind
    /// The text shown for this row; nil for a separator.
    var title: String?
    var shortcut: KeyboardShortcut?
    var isEnabled = true
    var run: (@MainActor () async -> Void)?

    static func action(
        id: String, _ title: String, shortcut: KeyboardShortcut? = nil, isEnabled: Bool = true,
        run: @escaping @MainActor () async -> Void
    ) -> MenuEntry {
        MenuEntry(id: id, kind: .action, title: title, shortcut: shortcut, isEnabled: isEnabled, run: run)
    }

    static func separator(id: String) -> MenuEntry {
        MenuEntry(id: id, kind: .separator)
    }
}

/// A group of menu rows that one feature owns. A feature adds a file that defines its
/// section and lists it in `MenuModel.sections`. A section that has state (for example
/// whether a Last Capture exists) is an `@Observable` class and reads that state in
/// `entries`, so the menu follows it.
@MainActor
protocol MenuSection {
    var entries: [MenuEntry] { get }
}
