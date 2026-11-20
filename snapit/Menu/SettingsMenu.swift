import SwiftUI

/// Settings…. User Guide and Check for Updates… follow it, each as its own `MenuSection` listed
/// after this one in `MenuModel.sections`.
struct SettingsMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .action(id: "settings", "Settings…", shortcut: KeyboardShortcut(",")) {
                await SettingsLauncher.show()
            },
        ]
    }
}
