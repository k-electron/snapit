import Foundation

/// The menu bar menu, top to bottom. A feature adds its rows by adding a file that
/// defines its own `[MenuEntry]` and listing that file's entries here.
@MainActor
enum MenuModel {
    static var entries: [MenuEntry] {
        EngineVersionMenu.entries
            + QuitMenu.entries
    }
}
