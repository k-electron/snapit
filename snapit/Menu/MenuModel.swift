import Observation

/// The menu bar menu, top to bottom. Observable: the menu re-renders when any state a
/// section reads in `entries` changes. A feature adds its rows by adding a `MenuSection`
/// in its own file and listing it in `sections`.
@MainActor
@Observable
final class MenuModel {
    static let shared = MenuModel()

    var sections: [any MenuSection] = [
        CaptureMenu(),
        SettingsMenu(),
        QuitMenu(),
    ]

    var entries: [MenuEntry] {
        sections.flatMap(\.entries)
    }
}
