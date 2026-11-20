import SwiftUI

/// The Capture items at the top of the menu: Capture Screen, with its default Shortcut.
struct CaptureMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .action(
                id: "capture.screen", "Capture Screen",
                shortcut: KeyboardShortcut("3", modifiers: [.control, .option, .command])
            ) {
                await ScreenCaptureFlow.run()
            },
            .separator(id: "capture.separator"),
        ]
    }
}
