import SwiftUI

/// One row of the menu bar menu. Features contribute their rows from their own files
/// (see `EngineVersionMenu.swift` and `QuitMenu.swift`) and `MenuModel` lists them in order.
enum MenuEntry {
    case info(String)
    case action(title: String, shortcut: KeyEquivalent?, run: @MainActor () -> Void)
    case separator

    /// The text shown for this row; nil for a separator.
    var title: String? {
        switch self {
        case .info(let title): title
        case .action(let title, _, _): title
        case .separator: nil
        }
    }
}
