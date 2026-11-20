import SwiftUI

/// Settings…, then the other app rows (User Guide, Check for Updates…), then a separator.
struct SettingsMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .action(id: "settings", "Settings…", shortcut: KeyboardShortcut(",")) {
                await SettingsLauncher.show()
            },
            .separator(id: "settings.separator"),
        ]
    }
}
