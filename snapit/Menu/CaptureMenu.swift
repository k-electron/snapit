/// The Capture items at the top of the menu: Capture Screen, showing its current Shortcut.
struct CaptureMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .action(id: "capture.screen", "Capture Screen", shortcut: Shortcuts.current.menuShortcut(for: .screen)) {
                await ScreenCaptureFlow.run()
            },
            .separator(id: "capture.separator"),
        ]
    }
}
