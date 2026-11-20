/// The Capture items at the top of the menu: Capture Screen, showing its current Shortcut.
struct CaptureMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .action(id: "capture.area", "Capture Area", shortcut: Shortcuts.current.menuShortcut(for: .area)) {
                await AreaCaptureFlow.start()
            },
            .action(id: "capture.screen", "Capture Screen", shortcut: Shortcuts.current.menuShortcut(for: .screen)) {
                await ScreenCaptureFlow.run()
            },
            .action(id: "capture.pick-color", "Pick Color", shortcut: Shortcuts.current.menuShortcut(for: .pickColor)) {
                await AreaCaptureFlow.startPickingColor()
            },
            .separator(id: "capture.separator"),
        ]
    }
}
